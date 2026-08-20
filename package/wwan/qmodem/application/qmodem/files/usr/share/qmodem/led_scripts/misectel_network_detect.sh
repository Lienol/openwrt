#!/bin/sh

. /usr/share/qmodem/led_scripts/connectivity.sh
. /usr/share/qmodem/led_scripts/misectel_led.sh

ON_OFF="$1"

misectel_led_init || exit 1
if [ "$ON_OFF" = off ]; then
	internet_leds_off
	exit 0
fi

internet_led_disconnected
last_connected=0
failed_probes=0
while true; do
	if qmodem_connectivity_probe 1; then
		connected=1
		failed_probes=0
	else
		failed_probes=$((failed_probes + 1))
		if [ "$last_connected" = 1 ] && [ "$failed_probes" -lt 3 ]; then
			connected=1
		else
			connected=0
		fi
	fi
	if [ "$connected" = 1 ]; then
		internet_led_connected
	else
		internet_led_disconnected
	fi
	last_connected="$connected"
	sleep 5
done
