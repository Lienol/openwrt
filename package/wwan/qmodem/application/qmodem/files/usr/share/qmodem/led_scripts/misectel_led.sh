#!/bin/sh

misectel_led_init()
{
	local board

	board="$(cat /tmp/sysinfo/board_name 2>/dev/null)"
	case "$board" in
		misectel,m01k21)
			LED_SIGNAL_POOR='lede:blue:4gyellow'
			LED_SIGNAL_GOOD='lede:blue:5gblue'
			LED_SIGNAL_EXCELLENT='lede:blue:5gyellow'
			LED_SIM='lede:blue:4gblue'
			LED_5G='lede:blue:red'
			;;
		misectel,m01k43|misectel,m01k43-usb|misectel,m01k43-usb-p|misectel,m01k43-p)
			LED_4G_POOR='yellow:4g'
			LED_4G_GOOD='blue:4g'
			LED_5G_POOR='yellow:5g'
			LED_5G_GOOD='blue:5g'
			LED_INTERNET_BLUE='blue:wan'
			LED_INTERNET_RED='red:wan'
			;;
		misectel,m02k45)
			LED_4G_POOR='4g:yellow'
			LED_4G_GOOD='4g:blue'
			LED_5G_POOR='5g:yellow'
			LED_5G_GOOD='5g:blue'
			LED_INTERNET_BLUE='sys:blue'
			LED_INTERNET_RED='sys:red'
			;;
		*) return 1 ;;
	esac
}

misectel_3led_signal_level()
{
	local rsrp="$1"

	case "$rsrp" in
		-*) ;;
		*) echo none; return ;;
	esac
	[ "$rsrp" -ge -140 ] 2>/dev/null && [ "$rsrp" -le -30 ] 2>/dev/null || {
		echo none
		return
	}
	if [ "$rsrp" -ge -90 ]; then
		echo excellent
	elif [ "$rsrp" -gt -110 ]; then
		echo good
	else
		echo poor
	fi
}

misectel_cell_entries()
{
	local cell_info="$1"

	# The M01K21 jq 1.8.1 build aborts in regex filters. Keep jq limited to
	# structural JSON extraction and normalize the resulting fields with awk.
	printf '%s\n' "$cell_info" | jq -r '
		.modem_info[]?
		| [
			((.key // "") | tostring),
			((.value // "") | tostring),
			((.extra_info // "") | tostring)
		]
		| @tsv
	' 2>/dev/null
}

misectel_rsrp_value()
{
	local cell_info="$1"
	local prefer_nr="$2"
	local entries

	entries="$(misectel_cell_entries "$cell_info")" || return
	printf '%s\n' "$entries" | awk -F '\t' -v prefer_nr="$prefer_nr" '
		toupper($1) == "RSRP" {
			value = $2
			gsub(/[[:space:]]/, "", value)
			sub(/[dD][bB][mM]$/, "", value)
			if (value ~ /^-?[0-9]+([.][0-9]+)?$/)
				values[++count] = value + 0
		}
		END {
			if (!count)
				exit
			value = prefer_nr == "1" ? values[count] : values[1]
			integer = int(value)
			if (value < integer)
				integer--
			printf "%d\n", integer
		}
	'
}

misectel_cell_5g_state()
{
	local cell_info="$1"
	local entries

	entries="$(misectel_cell_entries "$cell_info")" || return
	printf '%s\n' "$entries" | awk -F '\t' '
		function compact(value, normalized) {
			normalized = toupper(value)
			gsub(/[^A-Z0-9]/, "", normalized)
			return normalized
		}
		function contains_5g(value, normalized) {
			normalized = compact(value)
			return index(normalized, "NR") || index(normalized, "5G") || index(normalized, "ENDC")
		}
		function contains_legacy(value, normalized) {
			normalized = compact(value)
			return index(normalized, "LTE") || index(normalized, "4G") ||
				index(normalized, "WCDMA") || index(normalized, "3G") ||
				index(normalized, "UMTS") || index(normalized, "GSM") ||
				index(normalized, "2G")
		}
		function contains_nr_band(value, normalized) {
			normalized = compact(value)
			return index(normalized, "NR") || normalized ~ /^N[0-9]+$/
		}
		{
			key = compact($1)
			value = $2
			extra = $3
			if (contains_5g(extra)) {
				found_5g = 1
				exit
			}
			if (key == "NETWORKMODE" || key == "NETWORKTYPE" || key == "RAT") {
				if (contains_5g(value)) {
					found_5g = 1
					exit
				}
				if (contains_legacy(value))
					found_legacy = 1
			}
			if (key ~ /^(NR5G|5G|ENDC)/ && contains_5g(value)) {
				found_5g = 1
				exit
			}
			if ((key == "BAND" || key == "BANDNAME") && contains_nr_band(value)) {
				found_5g = 1
				exit
			}
		}
		END {
			if (found_5g)
				print "1"
			else if (found_legacy)
				print "0"
		}
	'
}

misectel_cops_5g_state()
{
	case "$1" in
		11|12|13) echo 1 ;;
		0|1|2|3|4|5|6|7|8|9|10) echo 0 ;;
		*) return 1 ;;
	esac
}

misectel_sim_state()
{
	case "$1" in
		*'SIM not inserted'*|*'SIM NOT INSERTED'*|*'NOT INSERTED'*) echo absent ;;
		*'+CPIN:'*) echo present ;;
		*) echo unknown ;;
	esac
}

led_turn()
{
	local path="/sys/class/leds/$1"
	local value="$2"
	local brightness

	[ -e "$path/brightness" ] || return
	[ ! -e "$path/trigger" ] || echo none > "$path/trigger" 2>/dev/null
	if [ "$value" = 1 ]; then
		brightness="$(cat "$path/max_brightness")"
	else
		brightness=0
	fi
	echo "$brightness" > "$path/brightness"
}

misectel_3led_update_signal_leds()
{
	local signal_level="$1"
	local poor=0
	local good=0
	local excellent=0

	case "$signal_level" in
		poor) poor=1 ;;
		good) poor=1; good=1 ;;
		excellent) poor=1; good=1; excellent=1 ;;
	esac
	led_turn "$LED_SIGNAL_POOR" "$poor"
	led_turn "$LED_SIGNAL_GOOD" "$good"
	led_turn "$LED_SIGNAL_EXCELLENT" "$excellent"
}

led_heartbeat()
{
	local path="/sys/class/leds/$1"

	[ -e "$path/brightness" ] || return
	echo "$(cat "$path/max_brightness")" > "$path/brightness"
	echo heartbeat > "$path/trigger"
}

led_netdev()
{
	local path="/sys/class/leds/$1"
	local device="$2"

	[ -e "$path/brightness" ] || return
	[ -n "$device" ] && [ -e "/sys/class/net/$device" ] || {
		led_heartbeat "$1"
		return
	}
	echo 1 > "$path/brightness"
	echo netdev > "$path/trigger"
	echo "$device" > "$path/device_name"
	echo 1 > "$path/link"
	echo 1 > "$path/rx"
	echo 1 > "$path/tx"
}

modem_leds_off()
{
	led_turn "$LED_4G_POOR" 0
	led_turn "$LED_4G_GOOD" 0
	led_turn "$LED_5G_POOR" 0
	led_turn "$LED_5G_GOOD" 0
}

internet_leds_off()
{
	led_turn "$LED_INTERNET_BLUE" 0
	led_turn "$LED_INTERNET_RED" 0
}

internet_led_connected()
{
	led_turn "$LED_INTERNET_RED" 0
	led_turn "$LED_INTERNET_BLUE" 1
}

internet_led_disconnected()
{
	led_turn "$LED_INTERNET_BLUE" 0
	led_turn "$LED_INTERNET_RED" 1
}
