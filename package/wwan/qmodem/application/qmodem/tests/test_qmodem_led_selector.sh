#!/bin/sh

set -eu

QMODEM_PACKAGE_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
initscript=qmodem_led
extra_command() { :; }
. "${QMODEM_PACKAGE_DIR}/files/etc/init.d/qmodem_led"

uci()
{
	[ "$1" = -q ] || return 1
	case "$2:$3" in
		show:qmodem)
			printf '%s\n' \
				'qmodem.modem_a=modem-device' \
				'qmodem.modem_b=modem-device'
			;;
		get:qmodem.modem_a.path) echo /sys/bus/usb/devices/2-1/ ;;
		get:qmodem.modem_a.metric) echo 20 ;;
		get:qmodem.modem_b.path) echo /sys/bus/usb/devices/2-1.1/ ;;
		get:qmodem.modem_b.metric) echo 10 ;;
		*) return 1 ;;
	esac
}

modem_path_present()
{
	case "$1" in
		*/2-1/) return 0 ;;
		*/2-1.1/) [ "${MOCK_B_PRESENT:-1}" = 1 ] ;;
		*) return 1 ;;
	esac
}

resolve_modem_target any ''
[ "$LED_TARGET_FOUND:$LED_TARGET" = '1:modem_b' ]

resolve_modem_target port 2-1
[ "$LED_TARGET_FOUND:$LED_TARGET" = '1:modem_a' ]

MOCK_B_PRESENT=0
resolve_modem_target any ''
[ "$LED_TARGET_FOUND:$LED_TARGET" = '1:modem_a' ]

if resolve_modem_target none ''; then
	exit 1
fi

echo 'qmodem_led selector tests passed'
