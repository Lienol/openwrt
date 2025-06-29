#!/bin/sh

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
LED_4G_POOR="red:4g"
LED_4G_GOOD="blue:4g"
LED_5G_POOR="red:5g"
LED_5G_GOOD="blue:5g"
LED_INTERNET_BLUE="blue:internet"
LED_INTERNET_RED="red:internet"
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
	led_turn "${LED_4G_POOR}" "0"
	led_turn "${LED_4G_GOOD}" "0"
	led_turn "${LED_5G_POOR}" "0"
	led_turn "${LED_5G_GOOD}" "0"
}

sim_inserted() {

	if at $AT_PORT "AT+CPIN?" | grep -q "CPIN: READY"; then
		echo "1"
	else
		echo "0"
	fi
}

internet_led() {
	if wget-ssl --spider --quiet --tries=1 --timeout=3 www.baidu.com; then
		led_turn "${LED_INTERNET_BLUE}" "1"
		led_turn "${LED_INTERNET_RED}" "0"
	else
		led_turn "${LED_INTERNET_BLUE}" "0"
		led_turn "${LED_INTERNET_RED}" "1"
	fi
}

get_mode() {
	local rat_mode="$1"
	rat_code=$(at $AT_PORT "AT+COPS?" | grep +COPS: | awk -F, '{print $4}' | tr -d '"')
	[ "$rat_code" -le "7" ] && echo "0" || echo "1"
}

get_rsrp() {
	rsrp=$(/usr/share/qmodem/modem_ctrl.sh cell_info "$MODEM_CFG" | jq -r '.modem_info[] | select(.key=="RSRP") | .value')
	# if rsrp is empty, return 0
	[ -z "$rsrp" ] && rsrp="0"
	# if rsrp out of range, return 0
	if [ "$rsrp" -gt "0" ] || [ "$rsrp" -lt "-140" ]; then
		rsrp="0"
	fi
	echo "$rsrp"
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
		led_heartbeat ${LED_4G_POOR}
		led_heartbeat ${LED_5G_POOR}

		last_netstat=""
		return
	fi

	local is_nr=$(get_mode)
	local rsrp=$(get_rsrp)
	local signal="0"
	
	#三档singal
	if [ "$rsrp" -ge "-95" ] && [ "$rsrp" -lt "0" ]; then
		signal="2"
	elif [ "$rsrp" -ge "-110" ] && [ "$rsrp" -lt "-95" ]; then
		signal="1"
	else
		signal="0"
	fi
	
	netstat="${NET_DEV}_${is_nr}_${signal}"
	if [ "$netstat" = "$last_netstat" ]; then
		# there's no update, return
		return
	fi
	last_netstat="$netstat"

	case "$signal" in
	"0")
		led_off_all
		case "$is_nr" in
			"0")
				led_heartbeat "${LED_4G_POOR}"
				;;
			"1")
				led_heartbeat "${LED_5G_POOR}"
				;;
		esac
		;;
	"1")
		led_off_all
		case "$is_nr" in
			"0")
				led_netdev "${LED_4G_POOR}" "$NET_DEV"
				;;
			"1")
				led_netdev "${LED_4G_POOR}" "$NET_DEV"
				;;
		esac
		;;
	"2")
		led_off_all
		case "$is_nr" in
			"0")
				led_netdev "${LED_4G_GOOD}" "$NET_DEV"
				;;
			"1")
				led_netdev "${LED_5G_GOOD}" "$NET_DEV"
				;;
		esac
		;;
	esac
}

# Loop forever
update_cfg
if [ "$ON_OFF" = "off" ]; then
	led_off_all
	exit 0
fi
while true; do
	update_netdev
	main
	internet_led
	sleep 5s
done
