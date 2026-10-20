#!/bin/sh

set -eu

QMODEM_PACKAGE_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
helper="${QMODEM_PACKAGE_DIR}/files/usr/share/qmodem/led_scripts/misectel_led.sh"
board_script="${QMODEM_PACKAGE_DIR}/files/etc/board.d/03_qmodem"

. "$helper"

assert_level()
{
	local expected="$1"
	local rsrp="$2"
	local actual

	actual="$(misectel_3led_signal_level "$rsrp")"
	[ "$actual" = "$expected" ] || {
		echo "RSRP ${rsrp}: expected ${expected}, got ${actual}" >&2
		exit 1
	}
}

assert_level none invalid
assert_level none 0
assert_level none -141
assert_level poor -140
assert_level poor -120
assert_level poor -110
assert_level good -109
assert_level good -100
assert_level good -91
assert_level excellent -90
assert_level excellent -30
assert_level none -29

assert_led_pattern()
{
	local expected="$1"
	local signal_level="$2"
	local actual=

	LED_SIGNAL_POOR=poor
	LED_SIGNAL_GOOD=good
	LED_SIGNAL_EXCELLENT=excellent
	led_turn()
	{
		actual="${actual}${1}=${2} "
	}
	misectel_3led_update_signal_leds "$signal_level"
	[ "$actual" = "$expected" ] || {
		echo "LED pattern ${signal_level}: expected '${expected}', got '${actual}'" >&2
		exit 1
	}
}

assert_led_pattern 'poor=0 good=0 excellent=0 ' none
assert_led_pattern 'poor=1 good=0 excellent=0 ' poor
assert_led_pattern 'poor=1 good=1 excellent=0 ' good
assert_led_pattern 'poor=1 good=1 excellent=1 ' excellent

assert_rsrp()
{
	local expected="$1"
	local prefer_nr="$2"
	local cell_info="$3"
	local actual

	actual="$(misectel_rsrp_value "$cell_info" "$prefer_nr")"
	[ "$actual" = "$expected" ] || {
		echo "RSRP selection: expected ${expected}, got ${actual}" >&2
		exit 1
	}
}

dual_rsrp='{"modem_info":[{"key":"RSRP","value":"-88","extra_info":"LTE"},{"key":"RSRP","value":"-112","extra_info":"NR5G-NSA"}]}'
assert_rsrp -88 0 "$dual_rsrp"
assert_rsrp -112 1 "$dual_rsrp"
assert_rsrp -100 0 '{"modem_info":[{"key":"rsrp","value":" -99.4 dBm "}]}'
assert_rsrp -90 0 '{"modem_info":[{"key":"RSRP","value":"-89.01dBm"}]}'
assert_rsrp '' 0 '{"modem_info":[{"key":"RSRP","value":"unknown"}]}'

assert_5g_state()
{
	local expected="$1"
	local cell_info="$2"
	local actual

	actual="$(misectel_cell_5g_state "$cell_info")"
	[ "$actual" = "$expected" ] || {
		echo "5G state: expected '${expected}', got '${actual}'" >&2
		exit 1
	}
}

assert_5g_state 1 '{"modem_info":[{"key":"network_mode","value":"EN-DC Mode"}]}'
assert_5g_state 1 '{"modem_info":[{"key":"Network Mode","value":"NR5G-SA"}]}'
assert_5g_state 1 '{"modem_info":[{"key":"Network Type","value":"5G NSA"}]}'
assert_5g_state 1 '{"modem_info":[{"key":"NR5G-NSA","value":"NR5G-NSA"}]}'
assert_5g_state 1 '{"modem_info":[{"key":"RSRP","value":"-101","extra_info":"NR5G-NSA"}]}'
assert_5g_state 1 '{"modem_info":[{"key":"Band","value":"NR n78"}]}'
assert_5g_state 1 '{"modem_info":[{"key":"Band Name","value":"N78"}]}'
assert_5g_state 0 '{"modem_info":[{"key":"Network Type","value":"FDD LTE"}]}'
assert_5g_state '' '{"modem_info":[{"key":"RSRP","value":"-101"}]}'

[ "$(misectel_cops_5g_state 7)" = 0 ]
[ "$(misectel_cops_5g_state 10)" = 0 ]
[ "$(misectel_cops_5g_state 11)" = 1 ]
if misectel_cops_5g_state invalid >/dev/null; then
	echo 'invalid COPS mode unexpectedly resolved' >&2
	exit 1
fi

[ "$(misectel_sim_state '+CPIN: READY')" = present ]
[ "$(misectel_sim_state '+CPIN: SIM PIN')" = present ]
[ "$(misectel_sim_state '+CME ERROR: SIM not inserted')" = absent ]
[ "$(misectel_sim_state '')" = unknown ]

grep -q 'misectel,m01k21)' "$board_script"
grep -q 'script misectel_3led bind any' "$board_script"
for led in \
	'lede:blue:4gyellow' \
	'lede:blue:5gblue' \
	'lede:blue:5gyellow' \
	'lede:blue:4gblue' \
	'lede:blue:red'
do
	grep -q "'$led'" "$helper"
done

echo 'misectel_3led tests passed'
