#!/bin/sh

. /usr/share/qmodem/modem_util.sh
. /usr/share/qmodem/led_scripts/misectel_led.sh
. /lib/functions.sh

MODEM_CFG="$1"
ON_OFF="$2"
last_siminserted=
last_netstat=
last_is_nr=0

update_cfg()
{
	config_load qmodem
	config_get AT_PORT "$MODEM_CFG" at_port
	config_get ALIAS "$MODEM_CFG" alias
	config_get USE_UBUS "$MODEM_CFG" use_ubus
	use_ubus_flag=
	[ "$USE_UBUS" != 1 ] || use_ubus_flag=-u
}

update_netdev()
{
	config_load network
	if [ -n "$ALIAS" ]; then
		config_get NET_DEV "$ALIAS" ifname
	else
		config_get NET_DEV "$MODEM_CFG" ifname
	fi
}

sim_inserted()
{
	if at "$AT_PORT" 'AT+CPIN?' | grep -q 'CPIN: READY'; then
		echo 1
	else
		echo 0
	fi
}

get_mode()
{
	local cell_info="$1"
	local network_mode rat_code

	network_mode="$(printf '%s\n' "$cell_info" | jq -r '.modem_info[]? | select(.key == "network_mode") | .value' | head -n 1)"
	case "$network_mode" in
		*EN-DC*|*NR5G*|*NR*|*5G*) echo 1; return ;;
		*LTE*|*4G*) echo 0; return ;;
	esac

	rat_code="$(at "$AT_PORT" 'AT+COPS?' | grep '+COPS:' | awk -F, '{print $4}' | tr -d '"')"
	case "$rat_code" in
		''|*[!0-9]*) echo "$last_is_nr" ;;
		*) [ "$rat_code" -le 7 ] && echo 0 || echo 1 ;;
	esac
}

get_rsrp()
{
	local cell_info="$1"
	local rsrp

	rsrp="$(printf '%s\n' "$cell_info" | jq -r '.modem_info[]? | select(.key == "RSRP") | .value' | head -n 1)"
	case "$rsrp" in
		-*) ;;
		*) rsrp=0 ;;
	esac
	[ "$rsrp" -ge -140 ] 2>/dev/null && [ "$rsrp" -le 0 ] 2>/dev/null || rsrp=0
	echo "$rsrp"
}

update_modem_leds()
{
	local siminserted cell_info is_nr rsrp signal netstat active_led

	siminserted="$(sim_inserted)"
	if [ "$siminserted" = 0 ] && [ "$siminserted" = "$last_siminserted" ]; then
		return
	fi
	last_siminserted="$siminserted"
	if [ "$siminserted" = 0 ]; then
		modem_leds_off
		led_heartbeat "$LED_4G_POOR"
		led_heartbeat "$LED_5G_POOR"
		last_netstat=
		return
	fi

	cell_info="$(/usr/share/qmodem/modem_ctrl.sh cell_info "$MODEM_CFG")"
	is_nr="$(get_mode "$cell_info")"
	last_is_nr="$is_nr"
	rsrp="$(get_rsrp "$cell_info")"
	if [ "$rsrp" -ge -95 ] && [ "$rsrp" -lt 0 ]; then
		signal=2
	elif [ "$rsrp" -ge -110 ] && [ "$rsrp" -lt -95 ]; then
		signal=1
	else
		signal=0
	fi

	netstat="${NET_DEV}_${is_nr}_${signal}"
	[ "$netstat" != "$last_netstat" ] || return
	last_netstat="$netstat"
	modem_leds_off
	case "${is_nr}_${signal}" in
		0_0) led_heartbeat "$LED_4G_POOR" ;;
		1_0) led_heartbeat "$LED_5G_POOR" ;;
		0_1) active_led="$LED_4G_POOR" ;;
		1_1) active_led="$LED_5G_POOR" ;;
		0_2) active_led="$LED_4G_GOOD" ;;
		1_2) active_led="$LED_5G_GOOD" ;;
	esac
	[ -z "$active_led" ] || led_netdev "$active_led" "$NET_DEV"
}

misectel_led_init || exit 1
update_cfg
if [ "$ON_OFF" = off ]; then
	modem_leds_off
	exit 0
fi

while true; do
	update_cfg
	update_netdev
	update_modem_leds
	sleep 5
done
