#!/bin/sh
# Neoway AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

#query IMEI
cmd_cgsn()
{
    at "$1" "AT+CGSN"
}

#set IMEI
#$2: imei
cmd_spimei_set()
{
    at "$1" "AT+SPIMEI=0,\"$2\""
}

#query system info (mode etc.)
cmd_mysysinfo_query()
{
    at "$1" 'AT$MYSYSINFO'
}

#set system mode
#$2: config mode
cmd_mysysinfo_set()
{
    at "$1" "AT\$MYSYSINFO=$2"
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

#query product info (revision etc.)
cmd_ati()
{
    at "$1" "ATI"
}

#query SIM slot
cmd_simcross_query()
{
    at "$1" "AT+SIMCROSS?"
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
cmd_myccid()
{
    at "$1" 'AT$MYCCID'
}

#query signal quality
cmd_csq()
{
    at "$1" "AT+CSQ"
}

#query 5G QoS
cmd_c5gqosrdp()
{
    at "$1" 'AT+C5GQOSRDP'
}

#query current band config
cmd_nwsetband_query()
{
    at "$1" "AT+NWSETBAND?"
}

#query supported bands
cmd_nwsetband_list_query()
{
    at "$1" "AT+NWSETBAND=?"
}

#reset band lock
cmd_nwsetband_reset()
{
    at "$1" "AT+NWSETBAND=0"
}

#lock bands
#$2: act  $3: band count  $4: band suffix (",b1,b2,...")
cmd_nwsetband_set()
{
    at "$1" "AT+NWSETBAND=$2,$3$4"
}

#query cell info
cmd_netdmsgex()
{
    at "$1" 'AT+NETDMSGEX'
}
