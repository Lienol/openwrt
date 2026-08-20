#!/bin/sh

_ucidef_qmodem_add_fields()
{
	while [ "$#" -ge 2 ]; do
		[ -n "$1" ] && [ -n "$2" ] && json_add_string "$1" "$2"
		shift 2
	done
}

ucidef_set_qmodem_main()
{
	json_select_object qmodem
	json_select_object main
	_ucidef_qmodem_add_fields "$@"
	json_select ..
	json_select ..
}

ucidef_add_qmodem_slot()
{
	local name="$1"
	shift

	[ -n "$name" ] || return 1
	json_select_object qmodem
	json_select_object slots
	json_select_object "$name"
	_ucidef_qmodem_add_fields "$@"
	json_select ..
	json_select ..
	json_select ..
}

_ucidef_add_qmodem_led_entry()
{
	local entry="$1"
	local name="$2"
	shift 2

	[ -n "$name" ] || return 1
	json_select_object qmodem_led
	json_select_object "$entry"
	json_select_object "$name"
	_ucidef_qmodem_add_fields "$@"
	json_select ..
	json_select ..
	json_select ..
}

ucidef_add_qmodem_network_detect()
{
	_ucidef_add_qmodem_led_entry network_detect "$@"
}

ucidef_add_qmodem_modem_status()
{
	_ucidef_add_qmodem_led_entry modem_status "$@"
}
