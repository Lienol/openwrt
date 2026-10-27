#!/bin/sh
# Gosuncn AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

#query IMEI
cmd_cgsn()
{
    at "$1" "AT+CGSN"
}

#set IMEI
#$2: imei
cmd_egmr_set_imei()
{
    at "$1" "AT+EGMR=1,7,\"$2\""
}

#query network mode
cmd_zswitch_query()
{
    at "$1" "AT+ZSWITCH?"
}

#set network mode
#$2: mode letter (e/x/r/E)
cmd_zswitch_set()
{
    at "$1" "AT+ZSWITCH=$2"
}

#query network selection
cmd_zsnt_query()
{
    at "$1" "AT+ZSNT?"
}

#set network selection
#$2: zsnt mode
cmd_zsnt_set()
{
    at "$1" "AT+ZSNT=$2"
}

#reset network selection
cmd_zsnt_reset()
{
    at "$1" "AT+ZSNT=0,0,0"
}

#query temperature
cmd_mtsm()
{
    at "$1" "AT+MTSM=1"
}

#query current band config
cmd_zband_query()
{
    at "$1" 'AT+ZBAND?'
}

#query supported bands
cmd_zband_list_query()
{
    at "$1" 'AT+ZBAND=?'
}

#reset bands to all
cmd_zband_reset_all()
{
    at "$1" "AT+ZBAND=all,all,all,all"
}

#lock NR bands
#$2: hex band mask
cmd_zband_set_nr()
{
    at "$1" "AT+ZBAND=all,all,all,$2"
}

#query SIM status
cmd_cpin_query()
{
    at "$1" "AT+CPIN?"
}

#set COPS numeric format
cmd_cops_numeric()
{
    at "$1" "AT+COPS=3,2"
}

#query operator selection
cmd_cops_query()
{
    at "$1" "AT+COPS?"
}

#query subscriber number
cmd_cnum()
{
    at "$1" "AT+CNUM"
}

#query IMSI
cmd_cimi()
{
    at "$1" "AT+CIMI"
}

#query ICCID
cmd_iccid()
{
    at "$1" "AT+ICCID"
}

#query model name
cmd_cgmm()
{
    at "$1" "AT+CGMM"
}

#query manufacturer
cmd_cgmi()
{
    at "$1" "AT+CGMI"
}

#query revision
cmd_cgmr()
{
    at "$1" "AT+CGMR"
}

#query signal quality
cmd_csq()
{
    at "$1" "AT+CSQ"
}

#query cell info
cmd_zcellinfo_query()
{
    at "$1" "AT+ZCELLINFO?"
}

#query extended signal info
cmd_cesq()
{
    at "$1" "AT+CESQ"
}

#factory reset
cmd_atf_factory()
{
    at "$1" "AT&F"
}
