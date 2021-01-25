pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";
import "./TimeUtil.sol";
import "./TypeConvertUtil.sol";
import "./EnumerableSet.sol";
import "./EnterpriseInfoAdmin.sol";

interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) external; }
/*
* 股权Token通证合约，遵循类似ERC20标准
*/
contract StockToken {

    using SafeMath for uint;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    //小数点个数，最小的代币单位
    uint8 internal decimals = 0;
    //董监高的限售比例
    uint8 public ratio=75;
    uint256 internal _number=1;
    //T+5日限售
    uint8 internal T_DAYS=5;

    /*******  EnterpriseInfoAdmin合约引入  *******/
    EnterpriseInfoAdmin internal enterpriseInfoAdmin;

    // 被授权进行股份登记操作的地址
    mapping (address => bool) internal authorizedCaller;

    //股份登记机构，该机构才有权限进行股权通证的修改
    address public publisher;
    //企业合约地址
    address public enterpriseAddress;
    //股权Token对应的企业ID
    string public stockCode;
    //股权Token的名字，可以为数字或字母
    string public name;
    //最大持股人数，有限公司50人，股份公司200人
    uint8 public maxNumberShareholders;
    //登记的股权总数
    uint256 public totalSupply;
    //已经登记的股权数量，该数量不能大于totalSupply
    uint256 public actualRegisterAmount;
    //上次计算限售的时间，每年计算一次
    uint public computerSalesDate;
    //当前持股人数
    uint8 public numberShareholders;
    //1-上市、2-退市、3-停牌
    uint8 public stockStatus;
    //高管信息
    address[] public managerAddress;
    /******* 股权限售结构体 *******/
    struct stockRestrict {
        // 份额
        uint256 balance;
        // 计算限售年份
        string year;
    }

    /******* 股权冻结结构体 *******/
    struct stockFrozen {
        //冻结编号
        string number;
        // 1--司法冻结 2--轮候冻结
        uint8 types;
        // 份额
        uint256 balance;
        // 解冻时间
        uint date;
    }

    /******* 股权质押/解押结构体 *******/
    struct stockPledge {
        //解押编号
        string number;
        //质权人地址
        address pledgee;
        // 份额
        uint256 balance;
        // 解押时间
        uint date;
    }

    /******* 股权状态结构体 *******/
    struct StockStatus {
        //业务编号
        uint number;
        //轮候的编号
        uint numberNext;
        // 1--司法冻结 2--轮候冻结  3--质押
        uint8 types;
        //质权人地址，发起冻结方地址
        address pledgee;
        // 份额
        uint256 balance;
        // 解冻/解押时间
        uint date;
    }

    /******* 股权状态结构体 *******/
    struct StockAllowStatus {
        //授权解押/解冻的业务编号
        uint allowNumber;
        //业务编号
        uint number;
        // 1--解押 2--解冻
        uint8 types;
        // 份额
        uint256 balance;
        // 解冻/解押时间
        uint date;
        //是否处理
        bool isdo;
    }


    // 用mapping保存每个股东的总余额
    struct BalanceMapUnit{
          mapping (address => uint256) balanceOf;
          address[] holderList;
    }
    BalanceMapUnit internal balanceOfHolder;

    // 用mapping保存每个地址对应的可用余额
    mapping (address => uint256) internal balanceOfUsable;


    // 用mapping保存董监高的限售明细
    struct ManagerMapUnit
    {
        mapping (address => uint256) salesOfrestriction;
        address[] managerList;
    }
    ManagerMapUnit  manamgerMap;


   // 用mapping保存冻结的明细(持有人->（冻结编号->冻结明细）)
    mapping (address =>  mapping (uint256 => StockStatus)) internal frozenList;
    // 用mapping保存冻结关系（冻结编号-持有人）
    mapping(uint256 => address) frozenMapping;
    //冻结编号的数组
    uint256[] frozenIds;

    // 用mapping保存每个地址对应的冻结余额
    mapping (address => uint256) internal balanceOffrozen;


    // 存储对股权的质押信息(出质人->（质押编号->质押明细）)
    mapping (address => mapping (uint256 => StockStatus)) internal pledgeList;
    // 用mapping保存质押关系（质押编号-出质人）
    mapping(uint256 => address) pledgeMapping;
    //质押编号的数组
    uint256[] pledgeIds;

    // 用mapping保存每个地址对应的质押余额
    mapping (address => uint256) internal balanceOfpledge;

    // 存储同意出质人解押的押信息(质权人->（解押押编号->解押明细）)
    mapping (address => mapping (uint256 => StockAllowStatus)) internal allowReleaselist;
    // 用mapping保存解押关系（解押押编号-质权人）
    mapping(uint256 => address) allowReleaseMapping;
    //质押编号的数组
    uint256[] allowReleaseIds;

    // 用mapping保存每个地址对应的交易冻结余额
    mapping (address => uint256) internal balanceOftranferFrozen;

    //转让列表详情（受让方地址->（受让时间->受让数量）），计算T+5限售使用
    mapping(address =>mapping(uint256=>uint256)) internal transferList;
    //转让时间列表（受让方地址->受让时间）
    mapping(address =>uint256) internal transferAddressList;
    //受让时间列表
    EnumerableSet.UintSet transferTimeSet;
    //受让方地址列表
    EnumerableSet.AddressSet transferAddressSet;


    //股份初始化登记事件
    event InitStock(address holder,uint amount,bool isManager);
    //冻结股权事件
    event FrozenStock(uint number,address stockholder,uint amount,uint date);
    //解冻股权事件
    event UnfrozenStock(address stockholder,uint number,uint _amount);
    //质押股权事件
    event PledgeStock(address pledgee,uint amount,uint _date);
    //解药股权事件
    event ReleaseStock(address pledgee,uint number);

    // 事件，用来通知客户端交易发生
    event Transfer(address from, address to, uint256 value);

    /******* 业务代码常量 *******/
    int8 constant internal SUCCESS_RETURN = 1;

     /******* 业务常量 *******/
    //uint8 constant internal TWO_HUNDRED=200;
   // uint8 constant internal FIFTY=50;
    uint8 constant internal LIST=1; //上市
    uint8 constant internal DELISTING=2; //退市
    uint8 constant internal SUSPEND=3; //停牌

    uint8 constant internal TWO_HUNDRED=4;
    uint8 constant internal FIFTY=3;


    /******* 执行状态码常量 *******/
    uint8 constant internal LAWFROZEN = 1;  //司法冻结
    uint8 constant internal WAITINGFROZEN = 2;  //轮候冻结
    uint8 constant internal PLEDGE=3;     //质押
    uint8 constant internal RELEASE=1;   //解押
    uint8 constant internal UNFREEZE=2;   //解冻


    modifier onlyOwner() {
        require(msg.sender == publisher);
        _;
    }

    modifier onlyAuthorizedCaller() {
       // require(authorizedCaller[msg.sender]);
        _;
    }
    function setAuthorizedCaller(address caller) public onlyOwner(){

        authorizedCaller[caller] = true;
    }
    function cancelAuthorizedCaller(address caller) public onlyOwner(){

        authorizedCaller[caller] = false;
    }

        /**
     * 初始化构造
     */
/*    constructor() public {
      //  address _enterpriseAddress=new address("0x146ceff5d1a950eb4c3b9fc9cc54528122cd260c");
        publisher = msg.sender;
        totalSupply = 100000000;
        stockCode = "666666";                      // 股份代码
        name = "TEST";                               // 股份名称
      //  enterpriseAddress=_enterpriseAddress;       //企业合约地址
    }*/

    /**
     * 初始化构造
     */
    constructor(address _enterpriseAddress,string memory _enterpriseId,string memory _name,string memory _stockCode,uint256 _totalSupply,uint8 _stockStatus) public {
        publisher = msg.sender;
        enterpriseInfoAdmin=EnterpriseInfoAdmin(_enterpriseAddress);
        totalSupply = _totalSupply * 10 ** uint256(decimals);  // 股权的总份额，份额跟最小的代币单位有关，份额 = 币数 * 10 ** decimals。
        stockCode = _stockCode;                      // 股份代码
        name = _name;                               // 股份名称
        enterpriseAddress=_enterpriseAddress;       //企业合约地址
        uint types=enterpriseInfoAdmin.getEnterpriseType(_enterpriseId);
        if(types==1){
            maxNumberShareholders=TWO_HUNDRED;
        }else{
            maxNumberShareholders=FIFTY;
        }
        managerAddress=enterpriseInfoAdmin.getEnterpriseManager(_enterpriseId);
        stockStatus=_stockStatus;
    }

    /**
     * 初始化股权登记
     */
    function initRegistration(address stockholder,uint initAmount) public onlyAuthorizedCaller returns(int8){
        bool _isManager=false;
        require(initAmount>0,"初始股份必须大于零");
        require(totalSupply>=actualRegisterAmount.add(initAmount),"登记的数量大于了发行的总数");
        require(balanceOfHolder.balanceOf[stockholder]==0,"该账户已经进行了初始登记");
        require(maxNumberShareholders>numberShareholders,"该股权的持股数量已经超过上限");
        for(uint i=0;i<managerAddress.length;i++){
            if(StringUtil.compareTwoString(LibAddress.addressToString(stockholder),LibAddress.addressToString(managerAddress[i]))){
                _isManager=true;
                break;
            }
        }
        balanceOfHolder.balanceOf[stockholder]=initAmount * 10 ** uint256(decimals);
        balanceOfHolder.holderList.push(stockholder);
        if(_isManager){
            manamgerMap.salesOfrestriction[stockholder]=initAmount.mul(ratio).div(100);
            manamgerMap.managerList.push(stockholder);
        }
        balanceOfUsable[stockholder]=initAmount.sub(manamgerMap.salesOfrestriction[stockholder]);
        actualRegisterAmount+=initAmount;
        numberShareholders++;
        emit InitStock(stockholder,initAmount,_isManager);
        return SUCCESS_RETURN;
    }

    /**
     * 新增股权登记
     */
    function incrRegistration(address stockholder,uint incrAmount) public onlyAuthorizedCaller returns(int8){
        require(incrAmount>0,"新增股份必须大于零");
        require(totalSupply>=actualRegisterAmount.add(incrAmount),"新增登记后的股份数量不能大于发行的总数");
        require(balanceOfHolder.balanceOf[stockholder]!=0,"该账户未做过股权登记，不可增资");
        balanceOfHolder.balanceOf[stockholder]+=incrAmount * 10 ** uint256(decimals);
        bool _isManager=false;
        for(uint i=0;i<managerAddress.length;i++){
            if(StringUtil.compareTwoString(LibAddress.addressToString(stockholder),LibAddress.addressToString(managerAddress[i]))){
                _isManager=true;
                break;
            }
        }
        uint restriction=0;
        if(_isManager){
            restriction=incrAmount.mul(ratio).div(100);
            manamgerMap.salesOfrestriction[stockholder]+=restriction;
        }
        balanceOfUsable[stockholder]+=incrAmount.sub(restriction);
        actualRegisterAmount+=incrAmount;
        return SUCCESS_RETURN;
    }

    /**
     * 减少股权登记
     */
    function reduceRegistration(address stockholder,uint reduceAmount) public onlyAuthorizedCaller returns(int8){
        require(reduceAmount>0,"减持股份必须大于零");
        require(balanceOfHolder.balanceOf[stockholder]!=0,"该账户未做过股权登记，不可减持操作");
        uint amountTmp=manamgerMap.salesOfrestriction[stockholder].add(balanceOfUsable[stockholder]);
        require(amountTmp>=reduceAmount,"减持的股份数量不能大于可用数量和冻结数量之和");
        bool _isManager=false;
        for(uint i=0;i<managerAddress.length;i++){
            if(StringUtil.compareTwoString(LibAddress.addressToString(stockholder),LibAddress.addressToString(managerAddress[i]))){
                _isManager=true;
                break;
            }
        }
        uint reduceRestriction=0;
        if(_isManager){
            reduceRestriction=reduceAmount.mul(ratio).div(100);
            if(manamgerMap.salesOfrestriction[stockholder]<=reduceRestriction){
                manamgerMap.salesOfrestriction[stockholder]=0;
            }else{
               manamgerMap.salesOfrestriction[stockholder]-=reduceRestriction;
            }
        }
        balanceOfUsable[stockholder]-=reduceAmount.sub(reduceRestriction);
        balanceOfHolder.balanceOf[stockholder]-=reduceAmount * 10 ** uint256(decimals);
        actualRegisterAmount-=reduceAmount;
        return SUCCESS_RETURN;
    }

    /**
     * 计算限售，每年统一计算一次
     *
     */
    function computerSalesOfrestriction() public onlyAuthorizedCaller returns(int8){
      uint newYear=TimeUtil.getNowYear();
        if(computerSalesDate<newYear){
          computerSalesDate=newYear;
            for(uint i=0;i<manamgerMap.managerList.length;i++){
                address address_tmp=manamgerMap.managerList[i];
                //限售数量不为零而且上次计算限售的年份早于当前年份
                if(manamgerMap.salesOfrestriction[address_tmp]>0){
                    manamgerMap.salesOfrestriction[address_tmp]=balanceOfHolder.balanceOf[address_tmp].mul(ratio).div(100);
                    balanceOfUsable[address_tmp]=balanceOfHolder.balanceOf[address_tmp].sub(manamgerMap.salesOfrestriction[address_tmp]);
                }
            }
        }
        return SUCCESS_RETURN;
    }

    /**
     * 根据股东账户查询股权数量
     *@param _holder      股东账户地址
     * @return            股权总数量
     * @return            持股总数量，可用数量，董监高限售，交易冻结数量，冻结数量，质押数量
     */
    function getStockAmountForJson(address _holder)public view returns(string memory){
        string memory _balances=StringUtil.strConcat3("{\"balances\":",TypeConvertUtil.uintToString(balanceOfHolder.balanceOf[_holder]),",");
        string memory _usable_balances=StringUtil.strConcat3("\"usable_balances\":",TypeConvertUtil.uintToString(balanceOfUsable[_holder]),",");
        string memory _salesOfrestriction=StringUtil.strConcat3("\"salesOfrestriction\":",TypeConvertUtil.uintToString(manamgerMap.salesOfrestriction[_holder]),",");
        string memory _tranferFrozen=StringUtil.strConcat3("\"tranferFrozen\":",TypeConvertUtil.uintToString(balanceOftranferFrozen[_holder]),",");
        string memory _balanceOffrozen=StringUtil.strConcat3("\"balanceOffrozen\":",TypeConvertUtil.uintToString(balanceOffrozen[_holder]),",");
        string memory _balanceOfpledge=StringUtil.strConcat3("\"balanceOfpledge\":",TypeConvertUtil.uintToString(balanceOfpledge[_holder]),"}");
        string memory result=StringUtil.strConcat6(_balances,_usable_balances,_salesOfrestriction,_tranferFrozen,_balanceOffrozen,_balanceOfpledge);
        return result;
    }

    /**
     * 根据股东账户查询股权数量
     *@param _holder      股东账户地址
     * @return            股权总数量
     * @return            持股总数量，可用数量，董监高限售，交易冻结数量，冻结数量，质押数量
     */
    function getStockAmountForArray(address _holder)public view returns(uint256,uint256,uint256,uint256,uint256,uint256){
         return (balanceOfHolder.balanceOf[_holder],balanceOfUsable[_holder],manamgerMap.salesOfrestriction[_holder],balanceOftranferFrozen[_holder],balanceOffrozen[_holder],balanceOfpledge[_holder]);
    }
    /**
     * 查询所有股东的持股信息
     * @return            账户地址数组和份额数组
     */
    function getAllStockAmounttoArray() public view onlyAuthorizedCaller returns(address[] memory,uint256[] memory){
        address[] memory _address= new address[](balanceOfHolder.holderList.length);
        uint256[] memory _values= new uint256[](balanceOfHolder.holderList.length);
      for(uint i=0;i<balanceOfHolder.holderList.length;i++){
          _values[i]=balanceOfHolder.balanceOf[balanceOfHolder.holderList[i]];
          _address[i]=balanceOfHolder.holderList[i];
      }
       return(_address,_values);
    }

    /**
     * 股份冻结
     *@param stockholder   股东账户地址
     *@param amount       冻结份额
     * @return            冻结编号
     */
    function frozenStock(address _stockholder,uint _amount,uint _date) public onlyAuthorizedCaller returns(uint){
        require(stockStatus!=DELISTING,"退市的股权不可办理冻结业务");
        require(balanceOfHolder.balanceOf[_stockholder].sub(balanceOffrozen[_stockholder])>=_amount,"可够冻结的数量不足");
        uint number_tmp=_number++;
        balanceOffrozen[_stockholder]+=_amount;
        frozenList[_stockholder][number_tmp].number=number_tmp;
        frozenList[_stockholder][number_tmp].types=LAWFROZEN;
        frozenList[_stockholder][number_tmp].balance=_amount;
        frozenList[_stockholder][number_tmp].date=_date;
        frozenList[_stockholder][number_tmp].numberNext=0;

        //更新可用数量
        if(balanceOfUsable[_stockholder]>=_amount){
          balanceOfUsable[_stockholder]-=_amount;
        }else{
          balanceOfUsable[_stockholder]=0;
        }

        frozenMapping[number_tmp]=_stockholder;
        frozenIds.push(number_tmp);

        emit FrozenStock(number_tmp,_stockholder,_amount,_date);
        return number_tmp;
    }

    /**
     * 股份轮候冻结
     *@param stockholder   股东账户地址
     *@param amount       冻结份额
     * @return            可用数量
     */
     function waitingFrozenStock(address stockholder,uint numberId,uint date) public onlyAuthorizedCaller returns(uint){
       require(stockStatus!=DELISTING,"退市的股权不可办理冻结业务");
       require(frozenList[stockholder][numberId].number>0,"没有此编号的冻结业务");
       require(frozenList[stockholder][numberId].balance>0,"此编号的冻结业务已经解冻，不能轮候冻结");
       uint number_tmp=_number++;
       //更新上一次冻结业务的轮候编号
       frozenList[stockholder][numberId].numberNext=number_tmp;
       //新增冻结
       frozenList[stockholder][number_tmp].number=number_tmp;
       frozenList[stockholder][number_tmp].types=WAITINGFROZEN;
       frozenList[stockholder][number_tmp].balance=frozenList[stockholder][numberId].balance;
       frozenList[stockholder][number_tmp].date=date;
       frozenList[stockholder][number_tmp].numberNext=0;

       frozenMapping[number_tmp]=stockholder;
       frozenIds.push(number_tmp);
       return number_tmp;
       //轮候冻结，可用数量不变
    }

    /**
     * 股份解冻
     *@param stockholder   股东账户地址
     *@param amount       冻结份额
     * @return            冻结编号
     */
    function unfrozenStock(address _stockholder,uint numberId,uint _amount) public onlyAuthorizedCaller returns(uint){
        require(frozenList[_stockholder][numberId].types==LAWFROZEN||frozenList[_stockholder][numberId].types==WAITINGFROZEN,"此业务不是冻结类业务，不能进行解冻操作");
        require(frozenList[_stockholder][numberId].balance>=_amount,"待解冻的金额不能大于冻结的金额");
        frozenList[_stockholder][numberId].balance-=_amount;
        frozenList[_stockholder][numberId].date=TimeUtil.getNowDateForUint();

        if(frozenList[_stockholder][numberId].numberNext>0 && frozenList[_stockholder][numberId].balance==0){
          uint numberNext=frozenList[_stockholder][numberId].numberNext;
          //将轮候冻结更为冻结
          frozenList[_stockholder][numberNext].types=LAWFROZEN;
        }else{
          balanceOffrozen[_stockholder]-=_amount;
        }

        //该笔冻结已经全部解冻
        if(frozenList[_stockholder][numberId].balance==0){
           // frozenMap.remove(numberId);
           //delete frozenList[_stockholder];
          // delete frozenMapping[numberId];
        }

        //更新可用金额
         balanceOfUsable[_stockholder]=balanceOfHolder.balanceOf[_stockholder].sub(balanceOfpledge[_stockholder].add(balanceOffrozen[_stockholder]));
         emit UnfrozenStock(_stockholder,numberId,_amount);
        return balanceOfUsable[_stockholder];
    }

    function getFrozenStock() public returns(string memory){
        bool start=false;
        string memory result="[";
        uint256 number;
        address _holder;
        for(uint i=0;i<frozenIds.length;i++){
            number=frozenIds[i];
            _holder=frozenMapping[number];
            if(_holder == msg.sender){
               if(!start){
                   start=true;
               }else{
                  result= StringUtil.strConcat2(result,",");
               }
             string memory _num=StringUtil.strConcat3("{\"number\":",TypeConvertUtil.uintToString(frozenList[_holder][number].number),",");
               string memory _types=StringUtil.strConcat3("\"types\":",TypeConvertUtil.uintToString(frozenList[_holder][number].types),",");
               string memory _balance=StringUtil.strConcat3("\"balance\":",TypeConvertUtil.uintToString(frozenList[_holder][number].balance),",");
               string memory _date=StringUtil.strConcat3("\"date\":",TypeConvertUtil.uintToString(frozenList[_holder][number].date),"}");
               string memory _res=StringUtil.strConcat4(_num,_types,_balance,_date);
               result= StringUtil.strConcat2(result,_res);
            }
        }
        result= StringUtil.strConcat2(result,"]");
        return result;
    }

    function getFrozenStock(address holder) public view onlyAuthorizedCaller returns(string memory){
        bool start=false;
        string memory result="[";
        uint256 number;
        address _holder;
        for(uint i=0;i<frozenIds.length;i++){
            number=frozenIds[i];
            _holder=frozenMapping[number];
            if(_holder == holder){
               if(!start){
                   start=true;
               }else{
                  result= StringUtil.strConcat2(result,",");
               }
             string memory _num=StringUtil.strConcat3("{\"number\":",TypeConvertUtil.uintToString(frozenList[_holder][number].number),",");
               string memory _types=StringUtil.strConcat3("\"types\":",TypeConvertUtil.uintToString(frozenList[_holder][number].types),",");
               string memory _balance=StringUtil.strConcat3("\"balance\":",TypeConvertUtil.uintToString(frozenList[_holder][number].balance),",");
               string memory _date=StringUtil.strConcat3("\"date\":",TypeConvertUtil.uintToString(frozenList[_holder][number].date),"}");
               string memory _res=StringUtil.strConcat4(_num,_types,_balance,_date);
               result= StringUtil.strConcat2(result,_res);
            }
        }
        result= StringUtil.strConcat2(result,"]");
        return result;
    }

    /**
     * 股份质押
     *@param pledgee      质权人账户地址
     *@param amount       质押数量
     *@param date         解押时间 格式：yyyymmdd
     * @return            质押编号
     */
    function pledgeStock(address _pledgee,uint _amount,uint _date)public returns(uint){
      require(stockStatus!=DELISTING,"退市的股权不可办理质押业务");
      //冻结的股份不能质押,不能重复质押，只有可用数量用于质押，故要判断可用数量是否大于质押数量
      require(balanceOfUsable[msg.sender]>=_amount,"可用数量未达到质押数量");
      uint number_tmp=_number++;
      pledgeList[msg.sender][number_tmp].number=number_tmp;
      pledgeList[msg.sender][number_tmp].types=PLEDGE;
      pledgeList[msg.sender][number_tmp].pledgee=_pledgee;
      pledgeList[msg.sender][number_tmp].balance=_amount;
      pledgeList[msg.sender][number_tmp].date=_date;
      //扣除可用数量
      balanceOfUsable[msg.sender]-=_amount;
      //增加质押数量
      balanceOfpledge[msg.sender]+=_amount;


      pledgeMapping[number_tmp]=msg.sender;
      pledgeIds.push(number_tmp);

      emit PledgeStock(_pledgee,_amount,_date);
      return number_tmp;
    }

    /**
     * 质权人同意股份解押
     *@param _number      质押编号
     *@param amount       解押数量
     *@param _date         解押时间 格式：yyyymmdd
     * @return            解押编号
     */
    function allowPledgeStock(uint number,uint amount,uint _date)public returns(uint){
      uint number_tmp=_number++;
      allowReleaselist[msg.sender][number_tmp].allowNumber=number_tmp;
      allowReleaselist[msg.sender][number_tmp].number=number;
      allowReleaselist[msg.sender][number_tmp].types=RELEASE;
      allowReleaselist[msg.sender][number_tmp].balance+=amount;
      allowReleaselist[msg.sender][number_tmp].date=_date;
      allowReleaseMapping[number_tmp]=msg.sender;
      allowReleaseIds.push(number_tmp);
      return number_tmp;
    }

    function getAllowPledgeStock(address _pledgee) public view onlyAuthorizedCaller returns(string memory){
        bool start=false;
        string memory result="[";
        uint256 number;
        address _holder;
        for(uint i=0;i<allowReleaseIds.length;i++){
            number=allowReleaseIds[i];
            _holder=allowReleaseMapping[number];
            if(_holder == _pledgee){
               if(!start){
                   start=true;
               }else{
                  result= StringUtil.strConcat2(result,",");
               }
            string memory _allownum=StringUtil.strConcat3("{\"allowNumber\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].allowNumber),",");
             string memory _num=StringUtil.strConcat3("\"number\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].number),",");
               string memory _types=StringUtil.strConcat3("\"types\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].types),",");
               string memory _balance=StringUtil.strConcat3("\"balance\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].balance),",");
               string memory _date=StringUtil.strConcat3("\"date\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].date),"}");
               string memory _res=StringUtil.strConcat5(_allownum,_num,_types,_balance,_date);
               result= StringUtil.strConcat2(result,_res);
            }
        }
        result= StringUtil.strConcat2(result,"]");
        return result;
    }


    /**
     * 出质人解押股份
     *@param _pledgee      质权人地址
     *@param _number      同意解押的编号
     * @return            解押成功与否
     */
     function startUnPledgeStock(address _pledgee,uint allowUnPledgeNumber)public returns(int8){
       require(!allowReleaselist[_pledgee][allowUnPledgeNumber].isdo,"该笔解押押已经处理");
       require(allowReleaselist[_pledgee][allowUnPledgeNumber].types==RELEASE,"该笔解押未经得质权人同意");
       require(allowReleaselist[_pledgee][allowUnPledgeNumber].date>TimeUtil.getNowDateForUint(),"该笔解押未到解押时间");
       //获取质押编号
       uint number_tmp=allowReleaselist[_pledgee][allowUnPledgeNumber].number;
       require(pledgeList[msg.sender][number_tmp].types==PLEDGE,"该笔业务不是质押业务");
       require(pledgeList[msg.sender][number_tmp].balance>=allowReleaselist[_pledgee][allowUnPledgeNumber].balance,"申请解押的金额不能大于质押金额");
       pledgeList[msg.sender][number_tmp].balance-=allowReleaselist[_pledgee][allowUnPledgeNumber].balance;
       //减少质押数量
       balanceOfpledge[msg.sender]-=allowReleaselist[_pledgee][allowUnPledgeNumber].balance;
       //增加可用数量
        balanceOfUsable[msg.sender]=balanceOfHolder.balanceOf[msg.sender].sub(balanceOfpledge[msg.sender].add(balanceOffrozen[msg.sender]));
       allowReleaselist[_pledgee][allowUnPledgeNumber].isdo=true;
       emit ReleaseStock(_pledgee,allowUnPledgeNumber);
     }


    /**
     * 获取质押明细
     *@param holder       出质人地址
     * @return            质押明细
     */
    function getPledgeStock(address holder) public view onlyAuthorizedCaller returns(string memory){
        bool start=false;
        string memory result="[";
        uint256 number;
        address _holder;
        for(uint i=0;i<pledgeIds.length;i++){
            number=pledgeIds[i];
            _holder=pledgeMapping[number];
            if(_holder == holder){
               if(!start){
                   start=true;
               }else{
                  result= StringUtil.strConcat2(result,",");
               }
             string memory _num=StringUtil.strConcat3("{\"number\":",TypeConvertUtil.uintToString(pledgeList[_holder][number].number),",");
               string memory _types=StringUtil.strConcat3("\"types\":",TypeConvertUtil.uintToString(pledgeList[_holder][number].types),",");
               string memory _balance=StringUtil.strConcat3("\"balance\":",TypeConvertUtil.uintToString(pledgeList[_holder][number].balance),",");
               string memory _date=StringUtil.strConcat3("\"date\":",TypeConvertUtil.uintToString(pledgeList[_holder][number].date),"}");
               string memory _res=StringUtil.strConcat4(_num,_types,_balance,_date);
               result= StringUtil.strConcat2(result,_res);
            }
        }
        result= StringUtil.strConcat2(result,"]");
        return result;
    }

     /**
      *  股份转移
      * 从创建交易者账号发送`_value`个代币到 `_to`账号
      *
      * @param _to 接收者地址
      * @param _value 转移数额
      */
     function transferStock(address _to, uint256 _value) public returns (bool success){
        require(stockStatus!=DELISTING,"退市的股权不能转让交易");
        address _from =msg.sender;
        // 确保目标地址不为0x0，因为0x0地址代表销毁
        require(_to != 0x0);
        //重新计算可用份额
        _computerUsable(_from);
        require(balanceOfUsable[_from]>=_value,"可用数量不足");
        if(balanceOfHolder.balanceOf[_to]==0){
           require(maxNumberShareholders>numberShareholders,"该股权的持股数量已经超过上限");
           numberShareholders++;
        }
        // 以下用来检查交易，
        uint previousBalances =balanceOfHolder.balanceOf[_from].add(balanceOfHolder.balanceOf[_to]);

        // Subtract from the sender
        balanceOfHolder.balanceOf[_from] =balanceOfHolder.balanceOf[_from].sub(_value) ;
        balanceOfUsable[_from]-=_value;
        //如果全部卖出，则持股人数减一
        if(balanceOfHolder.balanceOf[_from]==0){
            numberShareholders--;
        }
        // Add the same to the recipient
        balanceOfHolder.balanceOf[_to] = balanceOfHolder.balanceOf[_to].add(_value);
        //将转让记录加入转让列表中，用于T+5日限制的计算
        uint transferTime=TimeUtil.getNowDateForUint();
        uint endTime=transferTime.add(T_DAYS);
        transferList[_to][endTime]+=_value;
        transferAddressList[_to]=endTime;
        transferTimeSet.add(endTime);
        transferAddressSet.add(_to);
        balanceOftranferFrozen[_to]+=_value;

        emit Transfer(_from, _to, _value);
        // 用assert来检查代码逻辑。
        assert(balanceOfHolder.balanceOf[_from] + balanceOfHolder.balanceOf[_to] == previousBalances);
        return true;
     }

     /**
      * 每日计算可用份额
      */
    function computerUsableForDaily() public returns(bool) {
        uint transferTime;
        address addressTmp;
        uint nowTime=TimeUtil.getNowDateForUint();
        for(uint x=0;x<transferAddressSet.length();x++){
            for(uint i=0;i<transferTimeSet.length();i++){
                if(transferTimeSet.at(i)<=nowTime){
                     transferTime=transferTimeSet.at(i);
                     uint transferAmount=transferList[transferAddressSet.at(x)][transferTime];
                        if(transferAmount>0){
                          balanceOfUsable[transferAddressSet.at(x)]+=transferAmount;
                         }
                    // delete transferList[transferAddressSet.at(x)][transferTime];
                     transferTimeSet.remove(transferTime);
                }
            }
            transferAddressSet.remove(transferAddressSet.at(x));
        }
        return true;
    }
     /**
      * 查询股东的交易冻结明细
      *
      * @param _address 持有人地址
      */
    function getBalanceOftransferFrozen(address _address) public view returns(string) {
        bool start=false;
        string memory result="[";
        uint transferAmount;
        for(uint i=0;i<transferTimeSet.length();i++){
                transferAmount=transferList[_address][transferTimeSet.at(i)];
                if(transferAmount>0){
                     if(!start){
                        start=true;
                    }else{
                        result= StringUtil.strConcat2(result,",");
                    }
                    string memory _balance=StringUtil.strConcat3("{\"balance\":",TypeConvertUtil.uintToString(transferAmount),",");
                    string memory _date=StringUtil.strConcat3("\"allowable_trading_date\":",TypeConvertUtil.uintToString(transferTimeSet.at(i)),"}");
                    result= StringUtil.strConcat3(result,_balance,_date);
                }
        }
        result= StringUtil.strConcat2(result,"]");
        return result;
    }


     /**
      * 计算可用份额（内部调用）
      *
      * @param _address 持有人地址
      */
    function _computerUsable(address _address) internal returns(bool) {
        uint transferAmount;
        uint nowTime=TimeUtil.getNowDateForUint();
        for(uint i=0;i<transferTimeSet.length();i++){
            if(transferTimeSet.at(i)<=nowTime){
                 transferAmount=transferList[_address][transferTimeSet.at(i)];
                 if(transferAmount>0){
                      balanceOfUsable[_address]+=transferAmount;
                 }
                 delete transferList[_address][transferTimeSet.at(i)];
            }
        }
        transferAddressSet.remove(_address);
        return true;
    }

    /**
     * 更新发行的总股本
     *
     * @param _totalSupply 更新的总股本
     * @return            剩余股份登记的余额
     *
     */
    function updatetotalSupply(uint _totalSupply)public onlyAuthorizedCaller returns(uint){
        require(_totalSupply>actualRegisterAmount,"更新后的总股本必须大于实际发行的总股本");
        totalSupply=_totalSupply;
        return _totalSupply.sub(actualRegisterAmount);
    }

    /**
     * 更新股权的状态
     *
     * @param _stockStatus 更新股权的状态 1-上市、2-退市、3-停牌
     * @return            更新是否成功
     *
     */
    function updateStockStatus(uint8 _stockStatus)public onlyAuthorizedCaller returns(bool){
        stockStatus=_stockStatus;
        return true;
    }

}
