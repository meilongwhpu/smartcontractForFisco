pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import "./TableDefTools.sol";


/*
* EnterpriseInfoAdmin实现企业的链上信息管理，
* 以Table的形式进行存储。
*
*/
contract EnterpriseInfoAdmin is TableDefTools{

   /*
    * 构造函数，初始化使用到的表结构
    *
    * @param    无
    *
    * @return   无
    */
    constructor() public{

        initTableStruct(t_enterpriseInfo_struct, TABLE_ENTERPRISE_NAME, TABLE_ENTERPRISE_PRIMARYKEY, TABLE_ENTERPRISE_FIELDS);

    }
    
    
   /*
    * 新增企业
    *
    * @param _enterpriseId  企业ID
    * @param _fields 企业信息表各字段值拼接成的字符串，包括如下：
    *                   企业名称name
    *                   企业简称abbreviation
    *                   股权代码stock_code
    *                   统一社会信用代码 unified_social_code
    *                   企业性质 type(0-有限公司，1-股份公司）
    *                   注册时间 reg_time
    *                   注册地址 reg_address
    *                   办公地址 office_address
    *                   网址 website
    * @return 执行状态码
    *
    * 测试举例  参数一："QY00001"  参数二："测试有限公司,测试,999999,90000U1231,1,1998-03-13,中国重庆解放碑,中国重庆解放碑交易大厦,www.chn-cstc.com"
    */
    function insertEnterpriseInfo(string memory _enterpriseId, string memory _fields) public returns(int8){

        return insertOneRecord(t_enterpriseInfo_struct, _enterpriseId, _fields, false);
    }
    
    /*
     * 更新企业名称
     *
     */
    function updateEnterpriseName(string memory _enterpriseId, string memory _name) public returns(int8){
        // 查询企业信息返回状态
        int8 queryRetCode;
        // 更新企业信息返回状态
        int8 updateRetCode;
        // 数据表返回信息
        string[] memory retArray;
        
        // 查看该企业记录信息
        (queryRetCode, retArray) = selectOneRecordToArray(t_enterpriseInfo_struct, _enterpriseId, ["enterprise_id", _enterpriseId]);
        // 若存在该企业记录
        if(queryRetCode == SUCCESS_RETURN){
           // 更新企业信息表
           string memory changedFieldsStr = updateFieldsValue(retArray, 0, _name);
        	 updateRetCode= updateOneRecord(t_enterpriseInfo_struct, _enterpriseId, changedFieldsStr);
        	 // 若更新成功
           if(updateRetCode == SUCCESS_RETURN){
           		return SUCCESS_RETURN;
           }
        }
         // 若更新失败
         return FAIL_RETURN;      
    }    
    
    /*
     * 更新企业字段的值
     *
     */    
    function updateEnterpriseInfo(string memory _enterpriseId, string memory _field, string memory _value) public returns(int8){
        if(StringUtil.compareTwoString(_field,t_enterpriseInfo_struct.primaryKey)){
            emit UpdateRecordError(t_enterpriseInfo_struct.tableName,t_enterpriseInfo_struct.primaryKey,_field,"不能修改主键的值");
               // 若更新失败
           return FAIL_RETURN;     
        }
        // 查询企业信息返回状态
        int8 queryRetCode;
        // 更新企业信息返回状态
        int8 updateRetCode;
        // 数据表返回信息
        string[] memory retArray;
        //更新后的企业信息
        string memory changedFieldsStr;
        //字段位置
        uint fieldIndex=0;
        // 查看该企业记录信息
        (queryRetCode, retArray) = selectOneRecordToArray(t_enterpriseInfo_struct, _enterpriseId, ["enterprise_id", _enterpriseId]);
        // 若存在该企业记录
        if(queryRetCode == SUCCESS_RETURN){
            fieldIndex=fieldsIndex[t_enterpriseInfo_struct.tableName][_field];
            
            if(fieldIndex==0){
                 emit UpdateRecordError(t_enterpriseInfo_struct.tableName,t_enterpriseInfo_struct.primaryKey,_field,"拟修改的field值不存在");
                  // 若更新失败
            return FAIL_RETURN;
            }
            emit Debug(StringUtil.uint2str(fieldIndex));
            changedFieldsStr = updateFieldsValue(retArray, fieldIndex-1, _value);
            updateRetCode= updateOneRecord(t_enterpriseInfo_struct, _enterpriseId, changedFieldsStr); 
        }
        	 // 若更新成功
           if(updateRetCode == SUCCESS_RETURN){
           		return SUCCESS_RETURN;
           }
         // 若更新失败
         return FAIL_RETURN;      
    }  
    
        
   /*
    * 修改各字段中某一个字段，字符串格式输出
    *
    * @param _fields  各字段值的字符串数组
    * @param index    待修改字段的位置
    * @param values   修改后的值
    *
    * @return         修改后的各字段值，并以字符串格式输出
    *
    */
    function updateFieldsValue(string[] memory _fields, uint index, string values) internal returns (string){
        string[] memory fieldsArray = _fields;
        fieldsArray[index] = values;
        return StringUtil.strConcatWithComma(fieldsArray);
    }
    

   /*
    * 查询企业信息并以字符串数组方式输出
    *
    * @param enterpriseId  企业ID
    *
    * @return 执行状态码
    * @return 该企业信息的字符串数组
    *
    * 测试举例  参数一："QY00001"
    */
    function getEnterpriseRecordArray(string enterpriseId) public view returns(int8, string[]){

        return selectOneRecordToArray(t_enterpriseInfo_struct, enterpriseId, ["enterprise_id",enterpriseId]);
    }


   /*
    * 查询企业信息并以Json字符串方式输出
    *
    * @param enterpriseId  企业ID
    *
    * @return 执行状态码
    * @return 该企业信息的Json字符串
    *
    * 测试举例  参数一："QY00001"
    */
    function getEnterpriseRecordJson(string enterpriseId) public view returns(int8, string){

        return selectOneRecordToJson(t_enterpriseInfo_struct, enterpriseId);
    }


}
