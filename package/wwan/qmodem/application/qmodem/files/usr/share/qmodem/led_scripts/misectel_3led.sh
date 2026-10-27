#!/bin/sh

. /usr/share/qmodem/modem_util.sh
. /usr/share/qmodem/led_scripts/misectel_led.sh
. /lib/functions.sh

MODEM_CFG="$1"
ON_OFF="$2"
last_is_nr=0

update_cfg()
{
	config_load qmodem
	config_get AT_PORT "$MODEM_CFG" at_port
	config_get USE_UBUS "$MODEM_CFG" use_ubus
	use_ubus_flag=
	[ "$USE_UBUS" != 1 ] || use_ubus_flag=-u
}

get_sim_state()
{
	local response

	[ -n "$AT_PORT" ] || {
		echo unknown
		return
	}
	response="$(at "$AT_PORT" 'AT+CPIN?' 2>/dev/null)"
	misectel_sim_state "$response"
}

get_mode()
{
	local cell_info="$1"
	local state rat_code

	state="$(misectel_cell_5g_state "$cell_info")"
	case "$state" in
		0|1) echo "$state"; return ;;
	esac

	rat_code="$(at "$AT_PORT" 'AT+COPS?' 2>/dev/null | grep '+COPS:' | awk -F, '{print $4}' | tr -d '\r" ')"
	misectel_cops_5g_state "$rat_code" 2>/dev/null || echo "$last_is_nr"
}

all_leds_off()
{
	led_turn "$LED_SIGNAL_POOR" 0
	led_turn "$LED_SIGNAL_GOOD" 0
	led_turn "$LED_SIGNAL_EXCELLENT" 0
	led_turn "$LED_SIM" 0
	led_turn "$LED_5G" 0
}

update_leds()
{
	local cell_info is_nr rsrp signal_level sim_state

	sim_state="$(get_sim_state)"
	case "$sim_state" in
		present) led_turn "$LED_SIM" 1 ;;
		absent)
			all_leds_off
			last_is_nr=0
			return
			;;
		# A temporary AT failure must not blank every modem status LED.
		unknown) ;;
	esac
	cell_info="$(/usr/share/qmodem/modem_ctrl.sh cell_info "$MODEM_CFG")"
	if ! printf '%s\n' "$cell_info" | jq -e '.modem_info | type == "array"' >/dev/null 2>&1; then
		cell_info="$(cat "/tmp/cache_cell_info_${MODEM_CFG}" 2>/dev/null)"
	fi
	is_nr="$(get_mode "$cell_info")"
	last_is_nr="$is_nr"
	led_turn "$LED_5G" "$is_nr"

	rsrp="$(misectel_rsrp_value "$cell_info" "$is_nr")"
	signal_level="$(misectel_3led_signal_level "$rsrp")"
	misectel_3led_update_signal_leds "$signal_level"
}

misectel_led_init || exit 1
update_cfg
if [ "$ON_OFF" = off ]; then
	all_leds_off
	exit 0
fi

while true; do
	update_cfg
	update_leds
	sleep 5
done
