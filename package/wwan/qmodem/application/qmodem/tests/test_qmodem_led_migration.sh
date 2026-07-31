#!/bin/bash

set -euo pipefail
shopt -s lastpipe

declare -A DB

uci()
{
	[[ "$1" == -q ]] || return 1
	local op="$2" arg="${3-}" key value config
	case "$op" in
		get)
			[[ -n "${DB[$arg]+x}" ]] || return 1
			printf '%s\n' "${DB[$arg]}"
			;;
		set)
			key="${arg%%=*}"
			value="${arg#*=}"
			DB["$key"]="$value"
			;;
		delete)
			unset 'DB['"$arg"']'
			for key in "${!DB[@]}"; do
				[[ "$key" == "$arg."* ]] && unset 'DB['"$key"']'
			done
			return 0
			;;
		commit) ;;
		show)
			config="$arg"
			for key in "${!DB[@]}"; do
				[[ "$key" == "$config."* ]] || continue
				printf "%s='%s'\n" "$key" "${DB[$key]}"
			done | sort
			;;
		*) return 1 ;;
	esac
}

logger() { :; }

QMODEM_PACKAGE_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
source <(awk 'NR >= 6 && /^board=/ {exit} NR >= 6 {print}' \
	"${QMODEM_PACKAGE_DIR}/files/etc/uci-defaults/99-qmodem-board")

DB=(
	[qmodem.usb0]=modem-slot
	[qmodem.usb0.slot]=2-1
	[qmodem.usb0.led_script]=m02k45
	[qmodem.dev0]=modem-device
	[qmodem.dev0.path]=/sys/bus/usb/devices/2-1/
	[qmodem.dev0.led_script]=m02k45
	[qmodem_led.network_detect]=led
	[qmodem_led.network_detect.enabled]=0
	[qmodem_led.network_detect.script]=network_detect
	[qmodem_led.network_detect.bind]=none
	[qmodem_led.modem_status]=led
	[qmodem_led.modem_status.enabled]=1
	[qmodem_led.modem_status.script]=m02k45
	[qmodem_led.modem_status.bind]=any
	[qmodem_led.internet]=network_detect
	[qmodem_led.internet.enabled]=1
	[qmodem_led.internet.script]=misectel_network_detect
	[qmodem_led.cellular]=modem_status
	[qmodem_led.cellular.enabled]=1
	[qmodem_led.cellular.script]=misectel_modem_status
	[qmodem_led.cellular.bind]=any
)

migrate_led_schema
migrate_misectel_leds misectel,m02k45
migrate_legacy_leds

[[ "${DB[qmodem_led.internet]}" == network_detect ]]
[[ "${DB[qmodem_led.internet.enabled]}" == 0 ]]
[[ "${DB[qmodem_led.internet.script]}" == misectel_network_detect ]]
[[ "${DB[qmodem_led.cellular]}" == modem_status ]]
[[ "${DB[qmodem_led.cellular.script]}" == misectel_modem_status ]]
[[ "${DB[qmodem_led.cellular.bind]}" == any ]]
[[ ! -v 'DB[qmodem_led.network_detect]' ]]
[[ ! -v 'DB[qmodem_led.modem_status]' ]]
[[ ! -v 'DB[qmodem.usb0.led_script]' ]]
[[ ! -v 'DB[qmodem.dev0.led_script]' ]]

for key in "${!DB[@]}"; do
	[[ "$key" != qmodem_led.legacy_* ]]
done

before="$(declare -p DB)"
migrate_led_schema
migrate_misectel_leds misectel,m02k45
migrate_legacy_leds
after="$(declare -p DB)"
[[ "$before" == "$after" ]]

echo 'qmodem_led migration tests passed'
