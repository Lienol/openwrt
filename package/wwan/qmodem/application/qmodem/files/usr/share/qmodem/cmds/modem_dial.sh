#!/bin/sh
# AT command boundary for modem_dial.sh. Some dial commands are assembled at
# runtime from vendor/platform/PDP settings; cmd_dial_command is their sole
# transport interface so collection and replay still observe the final command.

cmd_dial_command() { at "$1" "$2"; }
cmd_dial_cpin_unlock() { at "$1" "AT+CPIN=\"$2\""; }
cmd_dial_cpin_query() { at "$1" 'AT+CPIN?'; }
cmd_dial_neoway_simcross_iccid() { at "$1" 'AT+SIMCROSS=1,1;$MYCCID'; }
cmd_dial_cfun_enable() { at "$1" 'AT+CFUN=1'; }
cmd_dial_cgpaddr() { at "$1" "AT+CGPADDR=$2"; }
cmd_dial_cops_numeric_query() { at "$1" 'AT+COPS=3,2;+COPS?'; }
cmd_dial_cnmp_query() { at "$1" 'AT+CNMP?'; }
cmd_dial_gtdns() { at "$1" "AT+GTDNS=$2"; }
