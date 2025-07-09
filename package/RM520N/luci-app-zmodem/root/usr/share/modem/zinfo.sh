#!/bin/sh 

LOCK_FILE="/tmp/zinfo.lock"
if [ -e "$LOCK_FILE" ]; then
    echo "zinfo互斥" >> /tmp/rm520n.log
    exit 1
fi
touch "$LOCK_FILE"
source /usr/share/modem/Quectel

sim_sel=$(cat /tmp/sim_sel)
SIMCard=""

case $sim_sel in
    0)
        SIMCard="外置SIM卡"
        ;;
    1)
        SIMCard="内置SIM1"
        ;;
    2)
        SIMCard="内置SIM2"
        ;;
    *)
        SIMCard="SIM状态错误"
        ;;
esac


SIM_Check=$(sendat 3 AT+CPIN?)
if [ -z "$(echo "$SIM_Check" | grep "READY")" ]; then
    {    
    echo `sendat 2 "ATI" | sed -n '3p'|sed 's/\r$//'` #'RM520N-CN'
    echo `sendat 2 "ATI" | sed -n '2p'|sed 's/\r$//'` #'Quectel'
    echo `date "+%Y-%m-%d %H:%M:%S"`
    echo ''
    echo "未检测到SIM卡!"
    echo -e "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
    } > /tmp/cpe_cell.file
    rm -rf "$LOCK_FILE"
    exit
fi

InitData(){
    Date=''
	CHANNEL="-" 
	ECIO="-"
	RSCP="-"
	ECIO1=" "
	RSCP1=" "
	NETMODE="-"
	LBAND="-"
	PCI="-"
	CTEMP="-"
	MODE="-"
	SINR="-"
	IMEI='-'
	IMSI='-'
	ICCID='-'
	phone='-'
	conntype=''
	Model=''


}

OutData(){
    {
    echo `sendat 2 "ATI" | sed -n '2p'|sed 's/\r$//'` #'Quectel'
    echo `sendat 2 "ATI" | sed -n '3p'|sed 's/\r$//'` #'RM520N-CN'
    echo `sendat 2 "ATI" | sed -n '4p' | cut -d ':' -f2 | tr -d ' '|sed 's/\r$//'` #'RM520NCNAAR03A03M4G
    echo "$CTEMP" # 设备温度 41°C
    echo `date "+%Y-%m-%d %H:%M:%S"` # 时间
    #----------------------------------
    echo "$SIMCard" # 卡槽
    echo "$ISP" #运营商
    echo "$IMEI" #imei
    echo "$IMSI" #imsi
    echo `sendat 2 AT+QCCID | awk -F': ' '/\:/{print $2}'|sed 's/\r$//'` #iccid
    echo `sendat 2 AT+CNUM | grep "+CNUM:" | sed 's/.*,"\(.*\)",.*/\1/'|sed 's/\r$//'` #phone
    #-----------------------------------
    echo "$MODE" #蜂窝网络类型 NR5G-SA "TDD"
    echo "$CSQ_PER" #CSQ_PER 信号质量
    echo "$CSQ_RSSI" #信号强度 RSSI 信号强度
    echo "$ECIO dB" #接收质量 RSRQ 
    echo "$RSCP dBm" #接收功率 RSRP
    echo "$SINR" #信噪比 SINR  rv["sinr"]
    #-----------------------------------
    echo "$COPS_MCC /$COPS_MNC" #MCC / MNC
    echo "$LAC"  #位置区编码
    echo "$CID"  #小区基站编码
    echo "$LBAND" # 频段 频宽
    echo "$CHANNEL" # 频点
    echo "$PCI" #物理小区标识
    } > /tmp/cpe_cell.file
}

InitData
Quectel_AT
ISP=""
case $COPS in
    "CHN-CT")
        ISP="中国电信"
        ;;
    "CHN-UNICOM")
        ISP="中国联通"
        ;;
    "CHINA MOBILE")
        ISP="中国移动"
        ;;
    *)
        ISP="$COPS"
        ;;
esac
OutData
rm -rf "$LOCK_FILE"