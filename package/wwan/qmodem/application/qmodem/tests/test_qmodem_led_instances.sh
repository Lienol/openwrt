#!/bin/sh

set -eu

QMODEM_PACKAGE_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
initscript=qmodem_led
extra_command() { :; }
. "${QMODEM_PACKAGE_DIR}/files/etc/init.d/qmodem_led"

LED_SCRIPT_DIR="${QMODEM_PACKAGE_DIR}/files/usr/share/qmodem/led_scripts"
INSTANCES=
COMMANDS=
LOG_COUNT=0

config_get()
{
	local value=
	case "$2:$3" in
		net_a:script|net_b:script) value=misectel_network_detect ;;
		any_a:script|any_b:script|port_a:script|port_dup:script|port_b:script) value=misectel_modem_status ;;
		any_a:bind|any_b:bind) value=any ;;
		port_a:bind|port_dup:bind|port_b:bind) value=port ;;
		port_a:port|port_dup:port) value=2-1 ;;
		port_b:port) value=2-1.1 ;;
	esac
	eval "$1=\$value"
}

config_get_bool()
{
	eval "$1=1"
}

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
	return 0
}

procd_open_instance()
{
	CURRENT_INSTANCE="$1"
	INSTANCES="${INSTANCES} $1"
}

procd_set_param()
{
	[ "$1" = command ] || return 0
	shift
	COMMANDS="${COMMANDS}${CURRENT_INSTANCE}:$*\n"
}

procd_close_instance() { :; }

logger()
{
	LOG_COUNT=$((LOG_COUNT + 1))
}

start_network_detect_instance net_a
start_network_detect_instance net_b

reset_modem_registry
start_modem_status_instance any_a
start_modem_status_instance any_b
start_modem_status_instance port_a
start_modem_status_instance port_dup
start_modem_status_instance port_b

for instance in network_detect_net_a network_detect_net_b modem_status_any modem_status_port_port_a modem_status_port_port_b; do
	case " $INSTANCES " in
		*" $instance "*) ;;
		*) printf 'missing instance %s:%s\n' "$instance" "$INSTANCES" >&2; exit 1 ;;
	esac
done
case " $INSTANCES " in
	*'any_b'*|*'port_dup'*) exit 1 ;;
esac
[ "$LOG_COUNT" = 2 ]
printf '%b' "$COMMANDS" | grep -q 'modem_status_any:.* modem_b$'
printf '%b' "$COMMANDS" | grep -q 'modem_status_port_port_a:.* modem_a$'
printf '%b' "$COMMANDS" | grep -q 'modem_status_port_port_b:.* modem_b$'

echo 'qmodem_led instance tests passed'
