#!/bin/sh
# Telit AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

#query USB composition
cmd_usbcfg_query()
{
    at "$1" 'AT#USBCFG?'
}

#set USB composition
#$2: mode
cmd_usbcfg_set()
{
    at "$1" "AT#USBCFG=$2"
}

#query RAT preference
cmd_ws46_query()
{
    at "$1" 'AT+WS46?'
}

#set RAT preference
#$2: network preference config
cmd_ws46_set()
{
    at "$1" "AT+WS46=$2"
}

#query battery
cmd_cbc()
{
    at "$1" "AT#CBC"
}

#query temperature sensors
cmd_tempsens()
{
    at "$1" "AT#TEMPSENS=2"
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

#query SIM slot
cmd_qss_query()
{
    at "$1" 'AT#QSS?'
}

#query IMEI
cmd_cgsn()
{
    at "$1" "AT+CGSN"
}

#query SIM status
cmd_cpin_query()
{
    at "$1" "AT+CPIN?"
}

#query operator selection
cmd_cops_query()
{
    at "$1" "AT+COPS?"
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

#enable and query CA metrics
cmd_cametrics()
{
    at "$1" "AT#CAMETRICS=1;#CAMETRICS?"
}

#query channel quality
cmd_cqi()
{
    at "$1" "AT#CQI"
}

#query current band config
cmd_bnd_query()
{
    at "$1" "AT#BND?"
}

#query supported bands
cmd_bnd_list_query()
{
    at "$1" "AT#BND=?"
}

#set band config
#$2: comma separated band list tail (after 0,22,)
cmd_bnd_set()
{
    at "$1" "AT#BND=0,22,$2"
}

#query CA info
cmd_cainfoext_query()
{
    at "$1" "AT#CAINFOEXT?"
}
