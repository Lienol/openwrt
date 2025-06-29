#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"
source "${SCRIPT_DIR}/modem_debug.sh"

#初始化模组频段
init_modem_band()
{
	#2G
	DCS_1800="-"
	E-GSM_900="-"
	P-GSM_900="-"
	GSM_450="-"
	GSM_480="-"
	GSM_750="-"
	GSM_850="-"
	R-GSM_900="-"
	PCS_1900="-"

	#3G

	#4G
	B1="-"
	B2="-"
	B3="-"
	B4="-"
	B5="-"
	B6="-"
	B7="-"
	B8="-"
	B9="-"
	B10="-"
	B11="-"
	B12="-"
	B13="-"
	B14="-"
	B17="-"
	B18="-"
	B19="-"
	B20="-"
	B21="-"
	B25="-"
	B26="-"
	B28="-"
	B29="-"
	B30="-"
	B32="-"
	B34="-"
	B38="-"
	B39="-"
	B40="-"
	B41="-"
	B42="-"
	B66="-"
	B71="-"

	#5G
	N1="-"
	N2="-"
	N3="-"
	N5="-"
	N7="-"
	N8="-"
	N12="-"
	N20="-"
	N25="-"
	N28="-"
	N38="-"
	N40="-"
	N41="-"
	N48="-"
	N66="-"
	N71="-"
	N77="-"
	N78="-"
	N79="-"
}

#获取模组数据信息
# $1:AT串口
# $2:制造商
# $3:平台
# $4:连接定义
modem_band()
{
	#初始化模组频段
    debug "初始化模组频段"
    init_modem_band
    debug "初始化模组频段完成"
}

modem_band "$1" "$2" "$3" "$4"