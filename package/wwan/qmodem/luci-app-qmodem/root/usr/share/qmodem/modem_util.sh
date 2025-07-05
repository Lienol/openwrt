#!/bin/sh
# Copyright (C) 2024 Tom <fjrcn@outlook.com>

at()
{
    local at_port=$1
    local new_str="${2/[$]/$}"
	local atcmd="${new_str/\"/\"}"
	#过滤空行
    #sms_tool_q -d $at_port at "$atcmd"
	tom_modem -d $at_port -o a -c "$atcmd"
}

fastat()
{
    local at_port=$1
    local new_str="${2/[$]/$}"
	local atcmd="${new_str/\"/\"}"
	#过滤空行
    # sms_tool_q -t 1 -d $at_port at "$atcmd"
	tom_modem -d $at_port -o a -c "$atcmd" -t 1
}

log2file()
{
	local subject="$1"
    local msg="$2"
	local path="$3"

	#打印日志
    local update_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${update_time}] ${subject}:${msg} " >> "${path}"
}

log2sys()
{
    local subject="$1"
    local msg="$2"
    logger -t "$subject" "$msg"
}

m_debug ()
{
	[ -z "$debug_subject" ] && subject="modem_util" || subject="$debug_subject"
	[ -n "$direct_debug" ] && echo "$subject" "$1"
	if [ -n "$log_file" ];then
		log2file "$subject" "$1" "$log_file"
	else
		log2sys "$subject" "$1"
	fi
}

update_sim_slot()
{
	. /lib/functions.sh
	board=$(board_name)
	case $board in
		HC,HC-G80*)
			sim_pin="/sys/class/gpio/sim/value"
			sim_pin_value=$(cat $sim_pin)
			[ "$sim_pin_value" == "0" ] && sim_slot="2" || sim_slot="1"
			#电平高表示SIM卡在卡槽1，电平低表示SIM卡在卡槽2
			debug "update_sim_slot:sim_slot=$sim_slot"
			;;
		ailf,gs2410|\
		huasifei,ws3006)
			sim_pin="/sys/class/gpio/dual_sim/value"
			#电平高则都在卡槽1，电平低则需要使用at查询
			[ "$(cat $sim_pin)" == "1" ] && sim_slot="1" || at_get_slot
			;;
		*)
			at_get_slot
			;;
	esac
}

at_get_slot()
{
	case $vendor in
		"quectel")
			at_res=$(at $at_port AT+QSIMDET? |grep +QSIMDET: |awk -F: '{print $2}')
			case "$at_res" in
				"1")
					sim_slot="1"
					;;
				"2")
					sim_slot="2"
					;;
				*)
					sim_slot="1"
					;;
			*)
				sim_slot="1"
				;;
			esac
			;;
		"fibocom")
			at_res=$(at $at_port AT+GTDUALSIM? |grep +GTDUALSIM: |awk -F: '{print $2}')
			case $at_res in
				"0")
					sim_slot="1"
					;;
				"1")
					sim_slot="2"
					;;
				*)
					sim_slot="1"
					;;
			*)
				sim_slot="1"
				;;
			esac
			;;
		"simcom")
			at_res=$(at $at_port AT+SMSIMCFG? | grep "+SMSIMCFG:" | awk -F',' '{print $2}' | sed 's/\r//g')
			case $at_res in
				"1")
					sim_slot="1"
					;;
				"2")
					sim_slot="2"
					;;
				*)
					sim_slot="1"
					;;
			*)
				sim_slot="1"
				;;
			esac
			;;
		"meig")
			at_res=$(at $at_port AT^SIMSLOT? | grep "\^SIMSLOT:" | awk -F': ' '{print $2}' | awk -F',' '{print $2}')
			case $at_res in
				"1")
					sim_slot="1"
					;;
				"0")
					sim_slot="2"
					;;
				*)
					sim_slot="1"
					;;
			*)
				sim_slot="1"
				;;
			esac
			;;
		"neoway")
			at_res=$(at $at_port 'AT+SIMCROSS?' | grep "+SIMCROSS:" | awk -F'[ ,]' '{print $2}' | sed 's/\r//g')
			case $at_res in
				"1")
					sim_slot="1"
					;;
				"2")
					sim_slot="2"
					;;
				*)
					sim_slot="1"
					;;
			*)
				sim_slot="1"
				;;
			esac
			;;
		"telit")
			at_res=$(at $at_port AT#QSS? | grep "#QSS:" | awk -F',' '{print $3}' | sed 's/\r//g')
			case $at_res in
				"0")
					sim_slot="1"
					;;
				"1")
					sim_slot="2"
					;;
				*)
					sim_slot="1"
					;;
			*)
				sim_slot="1"
				;;
			esac
			;;
		*)
			at_q_res=$(at $at_port AT+QSIMDET? |grep +QSIMDET: |awk -F: '{print $2}')
			at_f_res=$(at $at_port AT+GTDUALSIM? |grep +GTDUALSIM: |awk -F: '{print $2}')
			[ "$at_q_res" == "1" ] && sim_slot="1" && return
			[ "$at_q_res" == "2" ] && sim_slot="2" && return
			[ "$at_f_res" == "0" ] && sim_slot="1" && return
			[ "$at_f_res" == "1" ] && sim_slot="2" && return
			sim_slot="1"
		;;

	esac
}
