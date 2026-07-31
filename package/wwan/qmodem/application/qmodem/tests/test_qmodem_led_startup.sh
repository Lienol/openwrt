#!/bin/sh

set -eu

QMODEM_PACKAGE_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"

grep -q '^START=79$' "${QMODEM_PACKAGE_DIR}/files/etc/init.d/qmodem_led"
grep -q 'failed_probes.*-lt 3' "${QMODEM_PACKAGE_DIR}/files/usr/share/qmodem/led_scripts/misectel_network_detect.sh"
! grep -q 'connected.*!=.*last_connected' "${QMODEM_PACKAGE_DIR}/files/usr/share/qmodem/led_scripts/misectel_network_detect.sh"

network_script="${QMODEM_PACKAGE_DIR}/files/usr/share/qmodem/led_scripts/misectel_network_detect.sh"
led_helper="${QMODEM_PACKAGE_DIR}/files/usr/share/qmodem/led_scripts/misectel_led.sh"
blue_line="$(grep -n 'internet_led_disconnected' "$network_script" | head -n 1 | cut -d: -f1)"
probe_line="$(grep -n 'qmodem_connectivity_probe 1' "$network_script" | head -n 1 | cut -d: -f1)"
connected_red_line="$(sed -n '/^internet_led_connected()/,/^}/p' "$led_helper" | grep -n 'LED_INTERNET_RED.* 0' | cut -d: -f1)"
connected_blue_line="$(sed -n '/^internet_led_connected()/,/^}/p' "$led_helper" | grep -n 'LED_INTERNET_BLUE.* 1' | cut -d: -f1)"
disconnected_blue_line="$(sed -n '/^internet_led_disconnected()/,/^}/p' "$led_helper" | grep -n 'LED_INTERNET_BLUE.* 0' | cut -d: -f1)"
disconnected_red_line="$(sed -n '/^internet_led_disconnected()/,/^}/p' "$led_helper" | grep -n 'LED_INTERNET_RED.* 1' | cut -d: -f1)"

[ -n "$blue_line" ]
[ -n "$probe_line" ]
[ "$blue_line" -lt "$probe_line" ]
[ "$connected_red_line" -lt "$connected_blue_line" ]
[ "$disconnected_blue_line" -lt "$disconnected_red_line" ]

echo 'qmodem_led startup tests passed'
