#!/bin/sh
# AT commands used by modem_util.sh before a vendor implementation is loaded.

cmd_util_quimslot_query() { at "$1" 'AT+QUIMSLOT?'; }
cmd_util_gtdualsim_query() { at "$1" 'AT+GTDUALSIM?'; }
cmd_util_smsimcfg_query() { at "$1" 'AT+SMSIMCFG?'; }
cmd_util_simslot_query() { at "$1" 'AT^SIMSLOT?'; }
cmd_util_simcross_query() { at "$1" 'AT+SIMCROSS?'; }
cmd_util_qss_query() { at "$1" 'AT#QSS?'; }
cmd_util_qsimdet_query() { at "$1" 'AT+QSIMDET?'; }
