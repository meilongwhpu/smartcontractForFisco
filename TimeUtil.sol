pragma solidity ^0.4.25;

import "./DateTimeLibrary.sol";
import "./StringUtil.sol";
import "./TypeConvertUtil.sol";

/*
* 获取当前时间的工具合约
*
*/
library TimeUtil {

    using DateTimeLibrary for uint;
    using StringUtil for *;
    using TypeConvertUtil for *;

   /*
    * 得到当下的日期及时间，分别以字符串方式输出
    *
    * @param无,直接调用
    *
    * @return dateString 当前日期字符串
    * @return timeString 当前时间字符串
    *
    */
    function getNowDateTime() internal view returns(string dateString, string timeString){
        (uint year,uint month,uint day,uint hour,uint minute,uint second) = DateTimeLibrary.timestampToDateTime(now/1000);
        string memory nowDate = StringUtil.strConcat5(
                                                    TypeConvertUtil.uintToString(year),
                                                    "-" ,
                                                    TypeConvertUtil.uintToString(month),
                                                    "-" ,
                                                    TypeConvertUtil.uintToString(day));
        string memory nowTime = StringUtil.strConcat5(
                                                    TypeConvertUtil.uintToString(hour),
                                                    ":" ,
                                                    TypeConvertUtil.uintToString(minute),
                                                    ":" ,
                                                    TypeConvertUtil.uintToString(second));
        return (nowDate, nowTime);
    }


   /*
    * 得到当下的日期，以字符串方式输出
    *
    * @param无,直接调用
    *
    * @return dateString 当前日期字符串
    * @return timeString 当前时间字符串
    *
    */
    function getNowDate() internal view returns(string dateString){
        (uint year,uint month,uint day) = DateTimeLibrary.timestampToDate(now/1000);
        string memory nowDate = StringUtil.strConcat5(
                                                    TypeConvertUtil.uintToString(year),
                                                    "-" ,
                                                    TypeConvertUtil.uintToString(month),
                                                    "-" ,
                                                    TypeConvertUtil.uintToString(day));
        return nowDate;
    }

    /*
     * 得到当下的日期，以字符串方式输出
     *
     * @param无,直接调用
     *
     * @return dateString 当前日期字符串
     * @return timeString 当前时间字符串
     *
     */
     function getNowDateForUint() internal view returns(uint dateUint){
         (uint year,uint month,uint day) = DateTimeLibrary.timestampToDate(now/1000);
         string memory nowDate = StringUtil.strConcat3(
                                                     TypeConvertUtil.uintToString(year),
                                                     TypeConvertUtil.uintToString(month),
                                                     TypeConvertUtil.uintToString(day));
         return TypeConvertUtil.stringToUint(nowDate);
     }

    /*
     * 得到当下的年份
     *
     * @param无,直接调用
     *
     * @return yearString 当前年份字符串
     *
     */
     function getNowYear() internal view returns(uint yearunit){
         (uint year,uint month,uint day) = DateTimeLibrary.timestampToDate(now/1000);
         return year;
     }

}
