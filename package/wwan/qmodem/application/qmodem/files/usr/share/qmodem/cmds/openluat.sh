#!/bin/sh
# OpenLuat AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

cmd_openluat_identity_query()
{
    case "$2" in
        AT+CGMM|AT+CGMI|AT+CGMR) at "$1" "$2" ;;
        *) return 1 ;;
    esac
}

cmd_openluat_cced_serving() { at "$1" 'AT+CCED=0,1'; }
cmd_openluat_cced_neighbors() { at "$1" 'AT+CCED=0,2'; }
cmd_openluat_eem_enable() { at "$1" 'AT+EEMOPT=1'; }
cmd_openluat_eem_info() { at "$1" 'AT+EEMGINFO?'; }
cmd_openluat_ctec_query() { at "$1" 'AT+CTEC?'; }
cmd_openluat_ctec_set() { at "$1" "AT+CTEC=$2,$2"; }
cmd_openluat_band_query() { at "$1" 'AT*BAND?'; }
cmd_openluat_band_set() { at "$1" "AT*BAND=$2"; }
cmd_openluat_cgsn() { at "$1" 'AT+CGSN'; }
cmd_openluat_setusb_query() { at "$1" 'AT+SETUSB?'; }
cmd_openluat_setusb_set() { at "$1" "AT+SETUSB=$2"; }
cmd_openluat_rndiscall_stop() { at "$1" 'AT+RNDISCALL=0,0'; }
cmd_openluat_cbc() { at "$1" 'AT+CBC'; }
cmd_openluat_cpin_query() { at "$1" 'AT+CPIN?'; }
cmd_openluat_cops_query() { at "$1" 'AT+COPS?'; }
cmd_openluat_cnum() { at "$1" 'AT+CNUM'; }
cmd_openluat_cimi() { at "$1" 'AT+CIMI'; }
cmd_openluat_iccid() { at "$1" 'AT+ICCID'; }
cmd_openluat_ccid() { at "$1" 'AT+CCID'; }
cmd_openluat_csq() { at "$1" 'AT+CSQ'; }
cmd_openluat_cesq() { at "$1" 'AT+CESQ'; }
cmd_openluat_cgcontrdp() { at "$1" "AT+CGCONTRDP=$2"; }
