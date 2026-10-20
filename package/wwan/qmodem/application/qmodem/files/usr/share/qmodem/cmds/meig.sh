#!/bin/sh
# Meig AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

#query IMEI
cmd_cgsn()
{
    at "$1" "AT+CGSN"
}

#set IMEI
#$2: imei
cmd_lctsn_set_imei()
{
    at "$1" "AT+LCTSN=1,7,\"$2\""
}

#query network mode
cmd_ser_query()
{
    at "$1" 'AT+SER?'
}

#set network mode
#$2: mode number
cmd_ser_set()
{
    at "$1" "AT+SER=$2,1"
}

#query network preference config
cmd_syscfgex_query()
{
    at "$1" 'AT^SYSCFGEX?'
}

#set network preference config
#$2: network preference config string
cmd_syscfgex_set()
{
    at "$1" "AT^SYSCFGEX=\"$2\",all,0,2,all,all,all,all,1"
}

#query temperature
cmd_temp()
{
    at "$1" "AT+TEMP"
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
cmd_sims_slot_query()
{
    at "$1" 'AT^SIMSLOT?'
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
cmd_iccid()
{
    at "$1" "AT+ICCID"
}

#query system info
cmd_sysinfoex()
{
    at "$1" "AT^SYSINFOEX"
}

#query signal quality
cmd_csq()
{
    at "$1" "AT+CSQ"
}

#query AMBR
#$2: pdp index
cmd_dsambr()
{
    at "$1" "AT^DSAMBR=$2"
}

#query flow report config
cmd_dsflowqry()
{
    at "$1" 'AT^DSFLOWQRY'
}

#query cell info
#$2: pdp index
cmd_cellinfo()
{
    at "$1" "AT^CELLINFO=$2"
}
