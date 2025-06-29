#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"

source "${SCRIPT_DIR}/quectel.sh"
source "${SCRIPT_DIR}/fibocom.sh"
source "${SCRIPT_DIR}/meig.sh"
source "${SCRIPT_DIR}/huawei.sh"
# source "${SCRIPT_DIR}/simcom.sh"

#调试开关
# 0关闭
# 1打开
# 2输出到文件
switch=0
out_file="/tmp/modem.log"	#输出文件
#日志信息
debug()
{
	time=$(date "+%Y-%m-%d %H:%M:%S")	#获取系统时间
	if [ $switch = 1 ]; then
		echo $time $1					#打印输出
	elif [ $switch = 2 ]; then
		echo $time $1 >> $outfile		#输出到文件
	fi
}

#发送at命令
# $1 AT串口
# $2 AT命令
at()
{
	local at_port="$1"
	local new_str="${2/[$]/$}"
	local at_command="${new_str/\"/\"}"

	#echo
	# echo -e "${at_command}"" > "${at_port}" 2>&1

	#sms_tool
	sms_tool -d "${at_port}" at "${at_command}" 2>&1
}

#测试时打开
# debug $1
# at $1 $2

#获取快捷命令
# $1:快捷选项
# $2:制造商
get_quick_commands()
{
	local quick_option="$1"
	local manufacturer="$2"

	local quick_commands
	case "$quick_option" in
		"auto") quick_commands=$(cat ${SCRIPT_DIR}/${manufacturer}_at_commands.json) ;;
		"custom") quick_commands=$(cat /etc/modem/custom_at_commands.json) ;;
		*) quick_commands=$(cat ${SCRIPT_DIR}/${manufacturer}_at_commands.json) ;;
	esac
	echo "$quick_commands"
}

#拨号日志
# $1:AT命令
# $2:日志路径
dial_log()
{
	local at_command="$1"
	local path="$2"

	#打印日志
    local update_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${update_time}] Send AT command ${at_command} to modem" >> "${path}"
}