#!/bin/sh
# Copyright (C) 2024 Tom <fjrcn@outlook.com>
. /lib/functions.sh

at()
{
  local at_port=$1
  local new_str="${2/[$]/$}"
  local atcmd="${new_str/\"/\"}"
  [ "$clear_buffer" == "1" ] && options="$options -M"
  #过滤空行
  if [ "$(uci get qmodem.main.at_tool 2>/dev/null)" == "1" ]; then
   sms_tool_q -d $at_port at "$atcmd"
  else
   tom_modem $use_ubus_flag  -d $at_port -o a -c "$atcmd" $options
  fi
}

fastat()
{
  local at_port=$1
  local new_str="${2/[$]/$}"
  local atcmd="${new_str/\"/\"}"
  #过滤空行
  if [ "$(uci get qmodem.main.at_tool 2>/dev/null)" == "1" ]; then
   sms_tool_q -t 1 -d $at_port at "$atcmd"
  else
   tom_modem -d $at_port -o a -c "$atcmd" -t 1
  fi
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

qmodem_bool_enabled()
{
	case "$1" in
		1|true|TRUE|True|yes|YES|on|ON)
			return 0
			;;
	esac
	return 1
}

qmodem_lockcell_boot_hook_clear()
{
	local section="$1"

	[ -z "$section" ] && return 1
	uci -q delete "qmodem.${section}.lockcell_boot_hook_enabled"
	uci -q delete "qmodem.${section}.lockcell_boot_hook_delay"
	uci -q delete "qmodem.${section}.lockcell_boot_hook_at_cmds"
	uci commit qmodem >/dev/null 2>&1
}

qmodem_lockcell_boot_hook_save()
{
	local section="$1"
	local delay="$2"
	local cmd

	shift 2
	[ -z "$section" ] && return 1
	[ -z "$delay" ] && delay="15"

	uci -q delete "qmodem.${section}.lockcell_boot_hook_at_cmds"
	uci -q set "qmodem.${section}.lockcell_boot_hook_enabled=1" || return 1
	uci -q set "qmodem.${section}.lockcell_boot_hook_delay=${delay}" || return 1

	for cmd in "$@"; do
		if [ -n "$cmd" ]; then
			uci -q add_list "qmodem.${section}.lockcell_boot_hook_at_cmds=${cmd}" || return 1
		fi
	done

	uci commit qmodem >/dev/null 2>&1
}

qmodem_lockcell_boot_hook_add_json()
{
	local section="$1"
	local enabled delay
	local has_cmds=0

	enabled=$(uci -q get "qmodem.${section}.lockcell_boot_hook_enabled")
	delay=$(uci -q get "qmodem.${section}.lockcell_boot_hook_delay")
	[ -z "$delay" ] && delay="15"
	config_load qmodem
	config_list_foreach "$section" lockcell_boot_hook_at_cmds qmodem_lockcell_mark_list_cmd

	json_add_object "lockcell_boot_hook"
	if qmodem_bool_enabled "$enabled" && [ "$has_cmds" = "1" ]; then
		json_add_boolean "enabled" 1
	else
		json_add_boolean "enabled" 0
	fi
	json_add_string "delay" "$delay"
	json_add_array "at_cmds"
	config_list_foreach "$section" lockcell_boot_hook_at_cmds qmodem_json_add_list_string
	json_close_array
	json_close_object
}

qmodem_lockcell_mark_list_cmd()
{
	[ -n "$1" ] && has_cmds=1
}

qmodem_json_add_list_string()
{
	[ -n "$1" ] && json_add_string "" "$1"
}

qmodem_lockcell_boot_hook_sync()
{
	local section="$1"
	local en_boot_hook="$2"

	shift 2
	if qmodem_bool_enabled "$en_boot_hook"; then
		[ -z "$*" ] && qmodem_lockcell_boot_hook_clear "$section" && return
		qmodem_lockcell_boot_hook_save "$section" 15 "$@"
	else
		qmodem_lockcell_boot_hook_clear "$section"
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
			at_res=$(at "$at_port" "AT+QUIMSLOT?" | awk -F':' '/\+(QUIMSLOT|QUSIMSLOT):/ {
				value=$2
				gsub(/[^0-9]/, "", value)
				print value
				exit
			}')
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
