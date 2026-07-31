#!/bin/sh

state_file="$1"
poll_interval="${2:-5}"

while sleep "$poll_interval"; do
	current_state="$(/etc/init.d/qmodem_led resolved_state 2>/dev/null)"
	saved_state="$(cat "$state_file" 2>/dev/null)"
	[ "$current_state" = "$saved_state" ] && continue
	logger -t qmodem_led 'LED binding state changed; reloading service'
	/etc/init.d/qmodem_led reload
	exit $?
done
