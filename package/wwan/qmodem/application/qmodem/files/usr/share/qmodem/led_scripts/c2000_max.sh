#!/bin/sh
# Copyright (C) 2026 x-shark
_Vendor="nradio c2000-max"
_Author="x-shark"
_Maintainer="x-shark <unknown>"
# envs
# led names
# LED_4G_POOR="red:4g"
# LED_4G_GOOD="blue:4g"
# LED_5G_POOR="red:5g"
# LED_5G_GOOD="blue:5g"
# LED_INTERNET_BLUE="blue:internet"
# LED_INTERNET_RED="red:internet"
# modem_cfg
# MODEM_CFG / AT_PORT / NET_DEV / USE_UBUS_DAEMON

. /usr/share/qmodem/modem_util.sh
. /lib/functions.sh
LED_SIG1="hc:blue:sig1"
LED_SIG2="hc:blue:sig2"
LED_SIG3="hc:blue:sig3"
LED_STATUS="hc:blue:status"
LED_ERROR="hc:red:error"
MODEM_CFG=$1
ON_OFF=$2

update_cfg(){
	config_load qmodem
	config_get AT_PORT "$MODEM_CFG" at_port
	config_get ALIAS "$MODEM_CFG" alias
	config_get USE_UBUS "$MODEM_CFG" use_ubus
	[ "$USE_UBUS" = "1" ] && use_ubus_flag="-u"
}

update_netdev(){
	# if alias is set, network config name is alias else modem_cfg name
	config_load network
	if [ -n "$ALIAS" ]; then
		config_get NET_DEV "$ALIAS" ifname
	else
		config_get NET_DEV "$MODEM_CFG" ifname
	fi
}
last_siminserted=""
last_netstat=""
poll_counter=0

led_turn() {
	local path="/sys/class/leds/$1"
	local value="$2"
	max_brightness=$(cat "$path/max_brightness")
	if [ "$value" = "1" ]; then
		brightness=$max_brightness
	else
		brightness="0"
	fi
	echo "$brightness" > "$path/brightness"
}

led_heartbeat() {
	local path="/sys/class/leds/$1"
	max_brightness=$(cat "$path/max_brightness")

	echo "$max_brightness" > "$path/brightness"
	echo "heartbeat" > "$path/trigger"
}

led_netdev() {
	local path="/sys/class/leds/$1"
	local device="$2"

	echo "1" > "$path/brightness"
	echo "netdev" > "$path/trigger"
	echo "$device" > "$path/device_name"
	echo "1" > "$path/link"
	echo "1" > "$path/rx"
	echo "1" > "$path/tx"
}

led_off_all() {
	led_turn "${LED_SIG1}" "0"
	led_turn "${LED_SIG2}" "0"
	led_turn "${LED_SIG3}" "0"
}

sim_inserted() {
	sim_status=$(ubus call qmodem sim_info "{\"config_section\":\"$MODEM_CFG\"}" | jq -r '.modem_info[] | select(.key=="SIM Status") | .value')
	if [ "$sim_status" = "ready" ]; then
		echo "1"
	else
		echo "0"
	fi
}

internet_led() {
	if wget-ssl --spider --quiet --tries=1 --timeout=3 www.baidu.com; then
		led_turn "${LED_STATUS}" "1"
		led_turn "${LED_ERROR}" "0"
	else
		led_turn "${LED_STATUS}" "0"
		led_turn "${LED_ERROR}" "1"
	fi
}

get_mode() {
	local network_mode=$(ubus call qmodem cell_info "{\"config_section\":\"$MODEM_CFG\"}" | jq -r '.modem_info[] | select(.key=="network_mode") | .value')
	if [[ "$network_mode" == *"5G"* ]] || [[ "$network_mode" == *"NR"* ]]; then
		echo "1"
	else
		echo "0"
	fi
}

get_rsrq() {
	rsrq=$(ubus call qmodem cell_info "{\"config_section\":\"$MODEM_CFG\"}" | jq -r '.modem_info[] | select(.key=="RSRQ") | .value')
	# if rsrq is empty or null, return -1 to indicate no signal
	if [ -z "$rsrq" ] || [ "$rsrq" = "null" ]; then
		echo "-1"
		return
	fi
	# if rsrq out of range, return -1
	if [ "$rsrq" -gt "20" ] || [ "$rsrq" -lt "-43" ]; then
		echo "-1"
	else
		echo "$rsrq"
	fi
}

main() {
	local siminserted="$(sim_inserted)"
	if [ "$siminserted" = "0" ] && [ "$siminserted" = "$last_siminserted" ]; then
		# there's no update, return
		return
	fi

	last_siminserted="$siminserted"

	if [ "$siminserted" = "0" ]; then
		led_off_all
		led_turn "${LED_ERROR}" "1"

		last_netstat=""
		return
	fi

	local is_nr=$(get_mode)
	local rsrq=$(get_rsrq)
	local signal="0"
	
	# 根据RSRQ信号质量划分三档
	# RSRQ >= -12 dBm: 高信号
	# -19 dBm <= RSRQ < -12 dBm: 中信号
	# RSRQ < -19 dBm: 低信号
	if [ "$rsrq" = "-1" ]; then
		signal="-1"
	elif [ "$rsrq" -ge "-12" ]; then
		signal="2"
	elif [ "$rsrq" -ge "-19" ]; then
		signal="1"
	else
		signal="0"
	fi
	
	netstat="${NET_DEV}_${is_nr}_${signal}"
	
	# 非轮询模式才检查是否有更新
	if [ "$signal" != "-1" ] && [ "$netstat" = "$last_netstat" ]; then
		# there's no update, return
		return
	fi
	last_netstat="$netstat"

	case "$signal" in
	"0")
		led_off_all
		led_turn "${LED_SIG3}" "1"
		;;
	"1")
		led_off_all
		led_turn "${LED_SIG2}" "1"
		;;
	"2")
		led_off_all
		led_turn "${LED_SIG1}" "1"
		;;
	esac
}

polling_display() {
	local count=$1
	led_off_all
	case $((poll_counter % 3)) in
		"0")
			led_turn "${LED_SIG1}" "1"
			;;
		"1")
			led_turn "${LED_SIG2}" "1"
			;;
		"2")
			led_turn "${LED_SIG3}" "1"
			;;
	esac
	poll_counter=$((poll_counter + 1))
}

# Loop forever
update_cfg
if [ "$ON_OFF" = "off" ]; then
	led_off_all
	exit 0
fi
while true; do
	update_netdev
	
	# 检查是否进入轮询模式
	siminserted="$(sim_inserted)"
	if [ "$siminserted" = "1" ]; then
		rsrq=$(ubus call qmodem cell_info "{\"config_section\":\"$MODEM_CFG\"}" | jq -r '.modem_info[] | select(.key=="RSRQ") | .value')
		# 当rsrq为空时进入轮询模式
		if [ -z "$rsrq" ] || [ "$rsrq" = "null" ]; then
			# 进入轮询模式：在5秒内以1秒间隔轮询显示
			for i in 1 2 3 4 5; do
				polling_display
				sleep 1s
			done
		else
			# 正常模式：执行主程序并等待5秒
			main
			internet_led
			sleep 5s
		fi
	else
		# SIM卡未插入
		main
		internet_led
		sleep 5s
	fi
done
