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
    EnumerableSet.AddressSet internal managerAddress;

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
        // 总份额
        uint256 balance;
        // 限售份额
        uint256 balanceOfrestriction;
        // 流通份额
        uint256 balanceOfcirculation;
        // 解冻/解押时间
        uint date;
    }

    /******* 股权质押处理结构体 *******/
    struct StockPledgeDealing {
        // 总份额
        uint256 balance;
        // 限售份额
        uint256 balanceOfrestriction;
        // 流通份额
        uint256 balanceOfcirculation;
    }

    /******* 股权冻结处理结构体 *******/
    struct StockFrozenDealing {
        // 总份额
        uint256 balance;
        // 限售份额
        uint256 balanceOfrestriction;
        // 流通份额
        uint256 balanceOfcirculation;
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
          EnumerableSet.AddressSet holderList;
    }
    BalanceMapUnit internal balanceOfHolder;


    // 用mapping保存董监高的限售股份额
    struct ManagerMapUnit
    {
        mapping (address => uint256) salesOfrestriction;
        EnumerableSet.AddressSet managerList;
    }
    ManagerMapUnit  manamgerMap;
    // 用mapping保存每个地址的流通股份额
    mapping (address => uint256) internal balanceOfcirculation;


    // 用mapping保存每个地址对应的可用余额
    mapping (address => uint256) internal balanceOfUsable;


   // 用mapping保存冻结的明细(持有人->（冻结编号->冻结明细）)
    mapping (address =>  mapping (uint256 => StockStatus)) internal frozenList;
    // 用mapping保存冻结关系（冻结编号-持有人）
    mapping(uint256 => address) frozenMapping;
    //冻结编号的数组
    EnumerableSet.UintSet frozenIds;
    // 用mapping保存每个地址对应的冻结余额
    mapping (address => StockFrozenDealing) internal balanceOffrozen;

    // 用mapping保存轮候冻结的明细(持有人->（冻结编号->待冻结明细）)
     mapping (address =>  mapping (uint256 => StockStatus)) internal waitingFrozenList;
     //轮候冻结编号的数组
     EnumerableSet.UintSet waitingFrozenIds;
     // 用mapping保存冻结关系（冻结编号-持有人）
     mapping(uint256 => address) waitingFrozenMapping;
     // 用mapping保存每个地址对应的冻结余额
     mapping (address => uint256) internal balanceOfwaitingFrozen;


    // 存储对股权的质押信息(出质人->（质押编号->质押明细）)
    mapping (address => mapping (uint256 => StockStatus)) internal pledgeList;
    // 用mapping保存质押关系（质押编号-出质人）
    mapping(uint256 => address) pledgeMapping;
    //质押编号的数组
    EnumerableSet.UintSet pledgeIds;
    // 用mapping保存每个地址对应的质押余额
    mapping (address => StockPledgeDealing) internal balanceOfpledge;
    // 存储同意出质人解押的押信息(质权人->（解押押编号->解押明细）)
    mapping (address => mapping (uint256 => StockAllowStatus)) internal allowReleaselist;
    // 用mapping保存解押关系（解押押编号-质权人）
    mapping(uint256 => address) allowReleaseMapping;
    //质押编号的数组
    EnumerableSet.UintSet allowReleaseIds;



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
        address[] memory _managerAddress=enterpriseInfoAdmin.getEnterpriseManager(_enterpriseId);
        for(uint i=0;i<_managerAddress.length;i++){
            managerAddress.add(_managerAddress[i]);
        }
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
        balanceOfHolder.balanceOf[stockholder]=initAmount * 10 ** uint256(decimals);
        balanceOfHolder.holderList.add(stockholder);
        if(managerAddress.contains(stockholder)){
            _isManager=true;
            manamgerMap.salesOfrestriction[stockholder]=initAmount.mul(ratio).div(100);
            manamgerMap.managerList.add(stockholder);
        }
        balanceOfcirculation[stockholder]=initAmount.sub(manamgerMap.salesOfrestriction[stockholder]);
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
        uint restriction=0;
        if(managerAddress.contains(stockholder)){
          restriction=incrAmount.mul(ratio).div(100);
          manamgerMap.salesOfrestriction[stockholder]+=restriction;
        }
        balanceOfcirculation[stockholder]+=incrAmount.sub(restriction);
        balanceOfUsable[stockholder]+=incrAmount.sub(restriction);
        actualRegisterAmount+=incrAmount;
        return SUCCESS_RETURN;
    }

    /**
     * 减少股权登记(减资)
     */
    function reduceRegistration(address stockholder,uint reduceAmount) public onlyAuthorizedCaller returns(int8){
        require(reduceAmount>0,"减持股份必须大于零");
        require(balanceOfHolder.balanceOf[stockholder]!=0,"该账户未做过股权登记，不可减持操作");
        if(managerAddress.contains(stockholder)){
            //前置条件：
          uint disableRestriction=balanceOffrozen[stockholder].balanceOfrestriction.add(balanceOfpledge[stockholder].balanceOfrestriction);
          uint disableCirculation=balanceOffrozen[stockholder].balanceOfcirculation.add(balanceOfpledge[stockholder].balanceOfcirculation);
          uint reduceRestriction=reduceAmount.mul(ratio).div(100);
          uint reduceCirculation=reduceAmount.sub(reduceRestriction);
          require(balanceOfcirculation[stockholder]>disableCirculation.add(reduceCirculation),"该减资对象为董监高，流通股与限售股按比例减持，而未被质押或冻结的流通股份额小于待减持的份额25%，不可减持");
          require(manamgerMap.salesOfrestriction[stockholder]>disableRestriction.add(reduceRestriction),"该减资对象为董监高，流通股与限售股按比例减持，而未被质押或冻结的限售股份额小于待减持的份额75%，不可减持");
        }else{
          //前置条件： (总股-已冻结额-已质押额)>减资额
            uint disableAmount=balanceOffrozen[stockholder].balance.add(balanceOfpledge[stockholder].balance);
            require(balanceOfHolder.balanceOf[stockholder]>disableAmount.add(reduceAmount),"未被冻结或质押的股份份额小于待减持份额，不可减持");
        }

        uint _reduceRestriction=0;
        if(managerAddress.contains(stockholder)){
          _reduceRestriction=reduceAmount.mul(ratio).div(100);
          manamgerMap.salesOfrestriction[stockholder]-=_reduceRestriction;
        }
        balanceOfUsable[stockholder]-=reduceAmount.sub(_reduceRestriction);
        balanceOfHolder.balanceOf[stockholder]-=reduceAmount * 10 ** uint256(decimals);
        actualRegisterAmount-=reduceAmount;
        //无需重新计算限售

        return SUCCESS_RETURN;
    }

    /**
     * 股份冻结
     *@param stockholder   股东账户地址
     *@param amount       冻结份额
     * @return            冻结编号
     */
    function frozenStock(address _stockholder,uint _amount,uint _date) public onlyAuthorizedCaller returns(uint){
        require(stockStatus!=DELISTING,"退市的股权不可办理冻结业务");
        require(balanceOfHolder.balanceOf[_stockholder].sub(balanceOffrozen[_stockholder].balance)>=_amount,"可够冻结的数量不足");
        balanceOffrozen[_stockholder].balance+=_amount;
        uint _balanceOfcirculation;
        uint _balanceOfrestriction;
        //董监高的冻结操作：
        if(managerAddress.contains(_stockholder)){
          //已冻结的限售额>0 则说明流通股已经全部冻结
          if(balanceOffrozen[_stockholder].balanceOfrestriction>0){
            balanceOffrozen[_stockholder].balanceOfrestriction+=_amount;
            _balanceOfrestriction=_amount;
            _balanceOfcirculation=0;
          }else{
            //(流通股-已冻结的流通额)<=待冻结额
            uint subAmount=balanceOfcirculation[_stockholder].sub(balanceOffrozen[_stockholder].balanceOfcirculation);
            //(流通股-已冻结的流通额)<=待冻结额
            if(subAmount<=_amount){
              balanceOffrozen[_stockholder].balanceOfcirculation=balanceOfcirculation[_stockholder];
              balanceOffrozen[_stockholder].balanceOfrestriction=_amount.sub(subAmount);
              balanceOfUsable[_stockholder]=0;
              _balanceOfrestriction=_amount.sub(subAmount);
              _balanceOfcirculation=subAmount;
            }else{
              balanceOffrozen[_stockholder].balanceOfcirculation+=_amount;
              balanceOfUsable[_stockholder]-=_amount;
              _balanceOfrestriction=0;
              _balanceOfcirculation=_amount;
            }
          }
        }else{
          //非高管的冻结操作：
          balanceOfUsable[_stockholder]-=_amount;
        }

        //冻结编号
        uint number_tmp=_number++;
        frozenList[_stockholder][number_tmp].number=number_tmp;
        frozenList[_stockholder][number_tmp].types=LAWFROZEN;
        frozenList[_stockholder][number_tmp].balance=_amount;
        //董监高的冻结
        if(managerAddress.contains(_stockholder)){
          frozenList[_stockholder][number_tmp].balanceOfcirculation=_balanceOfcirculation;
          frozenList[_stockholder][number_tmp].balanceOfrestriction=_balanceOfrestriction;
        }
        frozenList[_stockholder][number_tmp].date=_date;

        frozenMapping[number_tmp]=_stockholder;
        frozenIds.add(number_tmp);

        emit FrozenStock(number_tmp,_stockholder,_amount,_date);
        return number_tmp;
    }

    /**
     * 股份轮候冻结，若有剩余的股份可以直接冻结，则需现冻结部分，不够的再执行轮候冻结
     *@param stockholder   股东账户地址
     *@param amount       冻结份额
     *@param date         解冻日期
     *@param numberId     对于整个冻结业务，若分为直接冻结和轮候冻结，需填写直接冻结编号；若是整体冻结为轮候冻结，则填写0
     * @return            可用数量
     */
     function waitingFrozenStock(address stockholder,uint _amount,uint date,uint numberId) public onlyAuthorizedCaller returns(uint){
       require(stockStatus!=DELISTING,"退市的股权不可办理冻结业务");
       uint _balanceOfFronzen=balanceOfHolder.balanceOf[stockholder].sub(balanceOffrozen[stockholder].balance);
       require(_balanceOfFronzen==0,StringUtil.strConcat2("还有可直接冻结的余额:",TypeConvertUtil.uintToString(_balanceOfFronzen)));
       uint number_tmp=_number++;
       if(numberId>0){
         require(frozenList[stockholder][numberId].number>0,"该账户下没有此编号的冻结业务");
         require(frozenList[stockholder][numberId].balance>0,"此编号的冻结业务已经解冻，不能继续轮候冻结");
         //更新上一次冻结业务的轮候编号
         frozenList[stockholder][numberId].numberNext=number_tmp;
       }

       //新增冻结
       waitingFrozenList[stockholder][number_tmp].number=number_tmp;
       waitingFrozenList[stockholder][number_tmp].types=WAITINGFROZEN;
       waitingFrozenList[stockholder][number_tmp].balance=_amount;
       waitingFrozenList[stockholder][number_tmp].date=date;
       waitingFrozenList[stockholder][number_tmp].numberNext=0;
       waitingFrozenMapping[number_tmp]=stockholder;
       waitingFrozenIds.add(number_tmp);
       balanceOfwaitingFrozen[stockholder]+=_amount;
       return number_tmp;
       //轮候冻结，可用数量不变
    }

    /**
     * 股份解冻，对于每笔冻结只能整体解冻，不可解冻部分
     *@param stockholder   股东账户地址
     *@param amount       冻结份额
     * @return            冻结编号
     */
    function unfrozenStock(address _stockholder,uint numberId) public onlyAuthorizedCaller returns(uint){
        require(frozenList[_stockholder][numberId].types==LAWFROZEN||frozenList[_stockholder][numberId].types==WAITINGFROZEN,"此业务不是冻结类业务，不能进行解冻操作");
        require(frozenList[_stockholder][numberId].balance>=0,"待解冻的金额应该大于0");
        uint _balance=frozenList[_stockholder][numberId].balance; //解押份额
        uint _balanceOfrestriction=frozenList[_stockholder][numberId].balanceOfrestriction; //解押的限售份额
        uint _balanceOfcirculation=frozenList[_stockholder][numberId].balanceOfcirculation; //解押的流通份额
        //解押操作：
        balanceOffrozen[_stockholder].balanceOfcirculation-=_balanceOfcirculation;
        balanceOffrozen[_stockholder].balanceOfrestriction-=_balanceOfrestriction;
        balanceOffrozen[_stockholder].balance-=_balance;
        frozenList[_stockholder][numberId].balance=0;
        frozenList[_stockholder][numberId].balanceOfcirculation=0;
        frozenList[_stockholder][numberId].balanceOfrestriction=0;
        frozenList[_stockholder][numberId].date=TimeUtil.getNowDateForUint();
        frozenIds.remove(numberId);
        delete frozenMapping[numberId];
        //该笔冻结存在的轮候冻结解冻：该冻结业务存在一笔轮候冻结，连同轮候冻结一起解冻
        if(frozenList[_stockholder][numberId].numberNext>0){
          uint _waitingFrozenId=frozenList[_stockholder][numberId].numberNext;
          waitingFrozenList[_stockholder][_waitingFrozenId].balance=0;
          waitingFrozenList[_stockholder][_waitingFrozenId].date=TimeUtil.getNowDateForUint();
          waitingFrozenIds.remove(_waitingFrozenId);
          delete waitingFrozenMapping[_waitingFrozenId];
        }

        // 存在轮候冻结记录，转为冻结
        if(balanceOfwaitingFrozen[_stockholder]>0){
          for(uint i=0;i<waitingFrozenIds.length();i++){
            uint _frozenId=waitingFrozenIds.at(i);
            uint _amount=waitingFrozenList[_stockholder][_frozenId].balance;
            //轮候冻结的金额小于解押的金额
            if(_amount>0 && _amount<=_balance){
              _balance-=_amount;
              balanceOffrozen[_stockholder].balance+=_amount;
              frozenList[_stockholder][_frozenId].number=_frozenId;
              frozenList[_stockholder][_frozenId].types=LAWFROZEN;
              frozenList[_stockholder][_frozenId].balance=_amount;
              frozenList[_stockholder][_frozenId].date=waitingFrozenList[_stockholder][_frozenId].date;
              frozenMapping[_frozenId]=_stockholder;
              frozenIds.add(_frozenId);
              //董监高的冻结
              if(managerAddress.contains(_stockholder)){
                uint _restriction=_amount.mul(ratio).div(100);
                balanceOffrozen[_stockholder].balanceOfcirculation+=_amount.sub(_restriction);
                balanceOffrozen[_stockholder].balanceOfrestriction+=_restriction;
                frozenList[_stockholder][_frozenId].balanceOfcirculation=_amount.sub(_restriction);
                frozenList[_stockholder][_frozenId].balanceOfrestriction=_restriction;
                _balanceOfrestriction-=_restriction;
                _balanceOfcirculation-=_amount.sub(_restriction);
              }
              waitingFrozenIds.remove(_frozenId);
              delete waitingFrozenMapping[_frozenId];
            }else{
                //轮候冻结的金额大于解押的金额
                uint number_tmp=_number++;
                frozenList[_stockholder][number_tmp].number=number_tmp;
                frozenList[_stockholder][number_tmp].types=LAWFROZEN;
                frozenList[_stockholder][number_tmp].balance=_balance;
                frozenList[_stockholder][number_tmp].date=waitingFrozenList[_stockholder][_frozenId].date;
                frozenList[_stockholder][numberId].numberNext=_frozenId;
                frozenMapping[number_tmp]=_stockholder;
                frozenIds.add(number_tmp);
                //董监高的冻结
                balanceOffrozen[_stockholder].balance+=_balance;
                if(managerAddress.contains(_stockholder)){
                  uint _restrictionTmp=_balance.mul(ratio).div(100);
                  balanceOffrozen[_stockholder].balanceOfcirculation+=_balance.sub(_restrictionTmp);
                  balanceOffrozen[_stockholder].balanceOfrestriction+=_restrictionTmp;
                  frozenList[_stockholder][number_tmp].balanceOfcirculation=_balance.sub(_restrictionTmp);
                  frozenList[_stockholder][number_tmp].balanceOfrestriction=_restrictionTmp;
                  _balanceOfrestriction-=_restrictionTmp;
                  _balanceOfcirculation-=_balance.sub(_restrictionTmp);
                }
                waitingFrozenList[_stockholder][_frozenId].balance-=_balance;
                _balance=0;
                break;
            }
          }
        }

        emit UnfrozenStock(_stockholder,numberId,_balance);
        //更新可用金额并返回
        return _computerBalanceOfUsable(_stockholder);
    }

    /**
     * 计算可用份额
     */
    function _computerBalanceOfUsable(address _stockholder) internal returns(uint) {
      uint _usableForFrozen=balanceOfcirculation[_stockholder].sub(balanceOffrozen[_stockholder].balanceOfcirculation);
      uint _usableForPledge=balanceOfcirculation[_stockholder].sub(balanceOfpledge[_stockholder].balanceOfcirculation);
      uint _usable;
      if(_usableForFrozen>=_usableForPledge){
        _usable=_usableForPledge;
      }else{
        _usable=_usableForFrozen;
      }
      balanceOfUsable[_stockholder]=_usable;
      return _usable;
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
      //冻结的股份不能质押,不能重复质押，规则：总股-已冻结额>=已质押额+待质押额
      //可质押数量
      uint CanPledgeAmounts=balanceOfHolder.balanceOf[msg.sender].sub(balanceOffrozen[msg.sender].balance.add(balanceOfwaitingFrozen[msg.sender]));
      require(CanPledgeAmounts>balanceOfpledge[msg.sender].balance.add(_amount),"可质押的数量不够");
      uint _balanceOfrestriction;
      uint _balanceOfcirculation;
      uint number_tmp=_number++;
      //董监高的质押
      if(managerAddress.contains(msg.sender)){
        //已冻结的限售额>0，说明流通股被全部冻结，只能对限售股进行质押
        if(balanceOffrozen[msg.sender].balanceOfrestriction>0){
          //已质押的限售额=已质押的限售额+待质押额
          balanceOfpledge[msg.sender].balance+=_amount;
          balanceOfpledge[msg.sender].balanceOfrestriction+=_amount;
          _balanceOfrestriction=_amount;
        }else{
          //待质押额+已质押的限售额<限售股，对限售部分进行质押操作
          if(balanceOfpledge[msg.sender].balanceOfrestriction.add(_amount)<=manamgerMap.salesOfrestriction[msg.sender]){
            balanceOfpledge[msg.sender].balanceOfrestriction+=_amount;
            _balanceOfrestriction=_amount;
            //可用份额不变
          }else{
              //已质押的流通额=已质押的流通额+(待质押额-(限售股-已质押的限售额))
              uint _circulationAmount=_amount.sub(manamgerMap.salesOfrestriction[msg.sender].sub(balanceOfpledge[msg.sender].balanceOfrestriction));
              balanceOfpledge[msg.sender].balanceOfcirculation+=_circulationAmount;
              balanceOfpledge[msg.sender].balanceOfrestriction=manamgerMap.salesOfrestriction[msg.sender];
              //可用额=可用额-(待质押额-(限售股-已质押的限售额))
              balanceOfUsable[msg.sender]-=_circulationAmount;
              _balanceOfrestriction=manamgerMap.salesOfrestriction[msg.sender].sub(balanceOfpledge[msg.sender].balanceOfrestriction);
              _balanceOfcirculation=_circulationAmount;
          }
        }
      }else{
        balanceOfpledge[msg.sender].balance+=_amount;
        balanceOfpledge[msg.sender].balanceOfcirculation+=_amount;
        balanceOfUsable[msg.sender]-=_amount;
        _balanceOfcirculation=_amount;
      }

      //质押明细
      pledgeList[msg.sender][number_tmp].number=number_tmp;
      pledgeList[msg.sender][number_tmp].types=PLEDGE;
      pledgeList[msg.sender][number_tmp].pledgee=_pledgee;
      pledgeList[msg.sender][number_tmp].balance=_amount;
      pledgeList[msg.sender][number_tmp].balanceOfrestriction=_balanceOfrestriction;
      pledgeList[msg.sender][number_tmp].balanceOfcirculation=_balanceOfcirculation;
      pledgeList[msg.sender][number_tmp].date=_date;
      pledgeMapping[number_tmp]=msg.sender;
      pledgeIds.add(number_tmp);
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
    function allowPledgeStock(uint pledgeNumber,uint _date)public returns(uint){
      require(pledgeIds.contains(pledgeNumber),"该质押编号不存在");
      require(pledgeList[pledgeMapping[pledgeNumber]][pledgeNumber].types==PLEDGE,"该pledgeNumber对应的业务不是质押业务");
      require(pledgeList[pledgeMapping[pledgeNumber]][pledgeNumber].balance>0,"该质押编号的质押业务已经解押");
      uint number_tmp=_number++;
      allowReleaselist[msg.sender][number_tmp].allowNumber=number_tmp;
      allowReleaselist[msg.sender][number_tmp].number=pledgeNumber;
      allowReleaselist[msg.sender][number_tmp].types=RELEASE;
      allowReleaselist[msg.sender][number_tmp].date=_date;
      allowReleaseMapping[number_tmp]=msg.sender;
      allowReleaseIds.add(number_tmp);
      return number_tmp;
    }

    /**
     * 出质人解押股份
     *@param _pledgee      质权人地址
     *@param _number      同意解押的编号
     * @return            返回可用份额
     */
     function startUnPledgeStock(address _pledgee,uint allowUnPledgeNumber)public returns(uint){
       require(!allowReleaselist[_pledgee][allowUnPledgeNumber].isdo,"该笔解押押已经处理");
       require(allowReleaselist[_pledgee][allowUnPledgeNumber].types==RELEASE,"该笔解押未经得质权人同意");
       require(allowReleaselist[_pledgee][allowUnPledgeNumber].date>TimeUtil.getNowDateForUint(),"该笔解押未到解押时间");
       //获取质押编号
       uint pledgeNumber=allowReleaselist[_pledgee][allowUnPledgeNumber].number;
        //减少质押数量
       balanceOfpledge[msg.sender].balance-=pledgeList[msg.sender][pledgeNumber].balance;
       balanceOfpledge[msg.sender].balanceOfrestriction-=pledgeList[msg.sender][pledgeNumber].balanceOfrestriction;
       balanceOfpledge[msg.sender].balanceOfcirculation-=pledgeList[msg.sender][pledgeNumber].balanceOfcirculation;

       pledgeList[msg.sender][pledgeNumber].balance=0;
       pledgeList[msg.sender][pledgeNumber].balanceOfrestriction=0;
       pledgeList[msg.sender][pledgeNumber].balanceOfcirculation=0;

       allowReleaselist[_pledgee][allowUnPledgeNumber].isdo=true;
       emit ReleaseStock(_pledgee,allowUnPledgeNumber);
       //计算可用份额
       return _computerBalanceOfUsable(msg.sender);
     }


     /**
      * 计算限售，每年统一计算一次
      *
      */
   function computerSalesOfrestriction() public onlyAuthorizedCaller returns(int8){
       uint newYear=TimeUtil.getNowYear();
         if(computerSalesDate<newYear){
           computerSalesDate=newYear;
             for(uint i=0;i<manamgerMap.managerList.length();i++){
                 address address_tmp=manamgerMap.managerList.at(i);
                 //限售数量不为零而且上次计算限售的年份早于当前年份
                 uint _balances=balanceOfHolder.balanceOf[address_tmp];
                 uint salesOfrestriction_new=_balances.mul(ratio).div(100);
                 uint circulation_new=_balances.sub(salesOfrestriction_new);
                 uint salesOfrestriction_old=manamgerMap.salesOfrestriction[address_tmp];
                 uint circulation_old=balanceOfcirculation[address_tmp];
                 //更新限售和流通
                 manamgerMap.salesOfrestriction[address_tmp]=salesOfrestriction_new;
                 balanceOfcirculation[address_tmp]=circulation_new;
                 //当有转出，则新的限售额会变小，需重新计算质押和冻结的限售额与流通额
                 if(salesOfrestriction_old>salesOfrestriction_new){
                   //质押部分的限售额或流通额大于了新的限售或流通
                   if(balanceOfpledge[address_tmp].balanceOfrestriction>salesOfrestriction_new){
                     //1.总质押份额>新的限售份额,以优先质押限售为原则进行调整
                       balanceOfpledge[address_tmp].balanceOfrestriction=salesOfrestriction_new;
                       balanceOfpledge[address_tmp].balanceOfcirculation=balanceOfpledge[address_tmp].balance.sub(salesOfrestriction_new);
                       //调整质押的明细：
                       uint _balanceOfrestriction=0;
                      for(uint j=0;j<pledgeIds.length();j++){
                        uint numberTmp=pledgeIds.at(j);
                        //累计的质押限售额<新的限售额
                        if(_balanceOfrestriction<salesOfrestriction_new){
                          //继续累计质押限售额之后，大于了新的限售额
                          if(_balanceOfrestriction.add(pledgeList[address_tmp][numberTmp].balanceOfrestriction)>salesOfrestriction_new){
                            pledgeList[address_tmp][numberTmp].balanceOfrestriction=salesOfrestriction_new.sub(_balanceOfrestriction);
                            pledgeList[address_tmp][numberTmp].balanceOfcirculation=pledgeList[address_tmp][numberTmp].balance.sub(pledgeList[address_tmp][numberTmp].balanceOfrestriction);
                            _balanceOfrestriction=salesOfrestriction_new;
                          }else{
                            //继续累计质押限售额之后，仍然小于新的限售额，则质押的限售额/流通额不变
                            _balanceOfrestriction+=pledgeList[address_tmp][numberTmp].balanceOfrestriction;
                          }
                        }else{
                          pledgeList[address_tmp][numberTmp].balanceOfrestriction=0;
                          pledgeList[address_tmp][numberTmp].balanceOfcirculation=pledgeList[address_tmp][numberTmp].balance;
                        }
                      }
                   }


                    //冻结部分的限售额大于零
                  if(balanceOffrozen[address_tmp].balance>0 && balanceOffrozen[address_tmp].balanceOfrestriction>0){
                      //已冻结总额<新的流通股：已冻结的流通额=新的流通股、已冻结的限售额=0；
                    if(balanceOffrozen[address_tmp].balance<=circulation_new){
                      balanceOffrozen[address_tmp].balanceOfcirculation=balanceOffrozen[address_tmp].balance;
                      balanceOffrozen[address_tmp].balanceOfrestriction=0;
                    }else{
                      //已冻结总额>新的流通股：已冻结的限售额=已冻结总额-新的流通股、已冻结的流通额=新的流通股
                      balanceOffrozen[address_tmp].balanceOfcirculation=circulation_new;
                      balanceOffrozen[address_tmp].balanceOfrestriction=balanceOffrozen[address_tmp].balance.sub(circulation_new);
                    }
                    //调整冻结的明细：
                   uint _balanceOfcirculation=0;
                   for(uint x=0;x<frozenIds.length();x++){
                     uint _frozenNumber=frozenIds.at(x);
                     //累计的冻结限售额<新的限售额
                     if(_balanceOfcirculation<circulation_new){
                       //继续累计质押流通额之后，小于了新的流通额
                       if(_balanceOfcirculation.add(frozenList[address_tmp][_frozenNumber].balanceOfcirculation)<circulation_new){
                         frozenList[address_tmp][_number].balanceOfcirculation=frozenList[address_tmp][_number].balance;
                         frozenList[address_tmp][_number].balanceOfrestriction=0;
                         _balanceOfcirculation+=frozenList[address_tmp][_number].balance;
                       }else{
                         frozenList[address_tmp][_number].balanceOfcirculation=circulation_new.sub(_balanceOfcirculation);
                         frozenList[address_tmp][_number].balanceOfrestriction=frozenList[address_tmp][_number].balance.sub(frozenList[address_tmp][_number].balanceOfcirculation);
                         _balanceOfcirculation=circulation_new;
                       }
                     }else{
                       frozenList[address_tmp][_number].balanceOfrestriction=pledgeList[address_tmp][_number].balance;
                       frozenList[address_tmp][_number].balanceOfcirculation=0;
                     }
                   }
                  }
                  //计算可用余额
                  _computerBalanceOfUsable(address_tmp);
                 }
             }
         }
         return SUCCESS_RETURN;
     }



        /**
         * 根据股东账户查询股权数量
         *@param _holder      股东账户地址
         * @return            股权总数量
         * @return            持股总数量，流通股份额、限售股份额、可用数量，交易冻结数量，冻结数量，质押数量
         */
      function getStockAmountForJson(address _holder)public view returns(string memory){
            string memory _balances=StringUtil.strConcat3("{\"balances\":",TypeConvertUtil.uintToString(balanceOfHolder.balanceOf[_holder]),",");
            string memory _balanceOfcirculation=StringUtil.strConcat3("\"balanceOfcirculation\":",TypeConvertUtil.uintToString(balanceOfcirculation[_holder]),",");
            string memory _salesOfrestriction=StringUtil.strConcat3("\"salesOfrestriction\":",TypeConvertUtil.uintToString(manamgerMap.salesOfrestriction[_holder]),",");
            string memory _balanceOfUsable=StringUtil.strConcat3("\"balanceOfUsable\":",TypeConvertUtil.uintToString(balanceOfUsable[_holder]),",");
            string memory _tranferFrozen=StringUtil.strConcat3("\"tranferFrozen\":",TypeConvertUtil.uintToString(balanceOftranferFrozen[_holder]),",");
            string memory _balanceOffrozen=StringUtil.strConcat3("\"balanceOfFrozen\":",TypeConvertUtil.uintToString(balanceOffrozen[_holder].balance),",");
            string memory _balanceOfpledge=StringUtil.strConcat3("\"balanceOfPledge\":",TypeConvertUtil.uintToString(balanceOfpledge[_holder].balance),"}");
            string memory result=StringUtil.strConcat4(_balances,_balanceOfcirculation,_salesOfrestriction,_balanceOfUsable);
            result=StringUtil.strConcat4(result,_tranferFrozen,_balanceOffrozen,_balanceOfpledge);
            return result;
        }

        /**
         * 根据股东账户查询股权数量
         *@param _holder      股东账户地址
         * @return            股权总数量
         * @return            持股总数量，流通股份额、限售股份额、可用数量，交易冻结数量，冻结数量，质押数量
         */
      function getStockAmountForArray(address _holder)public view returns(uint256,uint256,uint256,uint256,uint256,uint256,uint256){
             return (balanceOfHolder.balanceOf[_holder],balanceOfcirculation[_holder],manamgerMap.salesOfrestriction[_holder],balanceOfUsable[_holder],balanceOftranferFrozen[_holder],balanceOffrozen[_holder].balance,balanceOfpledge[_holder].balance);
        }
        /**
         * 查询所有股东的持股信息
         * @return            账户地址数组和份额数组
         */
      function getAllStockAmounttoArray() public view onlyAuthorizedCaller returns(address[] memory,uint256[] memory){
          uint length=balanceOfHolder.holderList.length();
          address[] memory _address= new address[](length);
          uint256[] memory _values= new uint256[](length);
          for(uint i=0;i<length;i++){
              _address[i]=balanceOfHolder.holderList.at(i);
              _values[i]=balanceOfHolder.balanceOf[_address[i]];
          }
           return(_address,_values);
        }

        /**
         * 查询发起人的冻结明细
         * @return    冻结信息JSON串
         */
    function getFrozenStock() public returns(string memory){
        bool start=false;
        string memory result="[";
        uint256 number;
        address _holder;
        for(uint i=0;i<frozenIds.length();i++){
            number=frozenIds.at(i);
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
              string memory _balanceOfrestriction=StringUtil.strConcat3("\"balanceOfrestriction\":",TypeConvertUtil.uintToString(frozenList[_holder][number].balanceOfrestriction),",");
              string memory _balanceOfcirculation=StringUtil.strConcat3("\"balanceOfcirculation\":",TypeConvertUtil.uintToString(frozenList[_holder][number].balanceOfcirculation),",");
              string memory _date=StringUtil.strConcat3("\"date\":",TypeConvertUtil.uintToString(frozenList[_holder][number].date),"}");
              string memory _res=StringUtil.strConcat6(_num,_types,_balance,_balanceOfrestriction,_balanceOfcirculation,_date);
              result= StringUtil.strConcat2(result,_res);
            }
        }
        result= StringUtil.strConcat2(result,"]");
        return result;
    }

    /**
     * 查询指定人的冻结明细
     *@param         持有人地址
     * @return       冻结信息JSON串
     */
    function getFrozenStock(address holder) public view onlyAuthorizedCaller returns(string memory){
        bool start=false;
        string memory result="[";
        uint256 number;
        address _holder;
        for(uint i=0;i<frozenIds.length();i++){
            number=frozenIds.at(i);
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
              string memory _balanceOfrestriction=StringUtil.strConcat3("\"balanceOfrestriction\":",TypeConvertUtil.uintToString(frozenList[_holder][number].balanceOfrestriction),",");
              string memory _balanceOfcirculation=StringUtil.strConcat3("\"balanceOfcirculation\":",TypeConvertUtil.uintToString(frozenList[_holder][number].balanceOfcirculation),",");
              string memory _date=StringUtil.strConcat3("\"date\":",TypeConvertUtil.uintToString(frozenList[_holder][number].date),"}");
              string memory _res=StringUtil.strConcat6(_num,_types,_balance,_balanceOfrestriction,_balanceOfcirculation,_date);
              result= StringUtil.strConcat2(result,_res);
            }
        }
        result= StringUtil.strConcat2(result,"]");
        return result;
    }


    /**
     * 查询运行某质押人解押的信息
     *@param         出质人地址
     * @return        同意解押信息JSON串
     */
    function getAllowPledgeStock(address _pledgee) public view onlyAuthorizedCaller returns(string memory){
        bool start=false;
        string memory result="[";
        uint256 number;
        address _holder;
        for(uint i=0;i<allowReleaseIds.length();i++){
            number=allowReleaseIds.at(i);
            _holder=allowReleaseMapping[number];
            if(_holder == _pledgee){
               if(!start){
                   start=true;
               }else{
                  result= StringUtil.strConcat2(result,",");
               }
               string memory _allownum=StringUtil.strConcat3("{\"allowNumber\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].allowNumber),",");
               string memory _num=StringUtil.strConcat3("\"pledgeNumber\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].number),",");
               string memory _types=StringUtil.strConcat3("\"pledgeNumber\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].types),",");
               string memory _balance=StringUtil.strConcat3("\"balance\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].balance),",");
               string memory _date=StringUtil.strConcat3("\"date\":",TypeConvertUtil.uintToString(allowReleaselist[_holder][number].date),",");
               string memory _res=StringUtil.strConcat5(_allownum,_num,_types,_balance,_date);
               if(allowReleaselist[_holder][number].isdo){
                 _res=StringUtil.strConcat4(_res,"\"isdo\":","1","}");
               }else{
                 _res=StringUtil.strConcat4(_res,"\"isdo\":","0","}");
               }
               result= StringUtil.strConcat2(result,_res);
            }
        }
        result= StringUtil.strConcat2(result,"]");
        return result;
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
        for(uint i=0;i<pledgeIds.length();i++){
            number=pledgeIds.at(i);
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
               string memory _balanceOfrestriction=StringUtil.strConcat3("\"balanceOfrestriction\":",TypeConvertUtil.uintToString(pledgeList[_holder][number].balanceOfrestriction),",");
               string memory _balanceOfcirculation=StringUtil.strConcat3("\"balanceOfcirculation\":",TypeConvertUtil.uintToString(pledgeList[_holder][number].balanceOfcirculation),",");
               string memory _date=StringUtil.strConcat3("\"date\":",TypeConvertUtil.uintToString(pledgeList[_holder][number].date),"}");
               string memory _res=StringUtil.strConcat6(_num,_types,_balance,_balanceOfrestriction,_balanceOfcirculation,_date);
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
        balanceOfcirculation[_from]-=_value;
        balanceOfUsable[_from]-=_value;
        //如果全部卖出，则持股人数减一
        if(balanceOfHolder.balanceOf[_from]==0){
            numberShareholders--;
        }
        // Add the same to the recipient
        balanceOfHolder.balanceOf[_to] = balanceOfHolder.balanceOf[_to].add(_value);

        uint restriction=0;
        if(managerAddress.contains(_to)){
          restriction=_value.mul(ratio).div(100);
          manamgerMap.salesOfrestriction[_to]+=restriction;
        }
        uint circulation=_value.sub(restriction);
        balanceOfcirculation[_to]+=circulation;

        //将转让记录加入转让列表中，对流通部分进行T+5日限制的计算
        uint transferTime=TimeUtil.getNowDateForUint();
        uint endTime=transferTime.add(T_DAYS);
        transferList[_to][endTime]+=circulation;
        transferAddressList[_to]=endTime;
        transferTimeSet.add(endTime);
        transferAddressSet.add(_to);
        balanceOftranferFrozen[_to]+=circulation;

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
