#!/bin/sh
# Huawei AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

#query IMEI
cmd_cgsn()
{
    at "$1" "AT+CGSN"
}

#set IMEI
#$2: imei
cmd_phynum_set_imei()
{
    at "$1" "at^phynum=IMEI,$2"
}

#query network mode
cmd_setmode_query()
{
    at "$1" "AT^SETMODE?"
}

#set network mode
#$2: mode number
cmd_setmode_set()
{
    at "$1" "AT^SETMODE=$2"
}

#query network preference config
cmd_syscfgex_query()
{
    at "$1" "AT^SYSCFGEX?"
}

#set network preference config
#$2: rat preference code
cmd_syscfgex_set()
{
    at "$1" "AT^SYSCFGEX=\"$2\",40000000,1,2,40000000,,"
}

#query SIM status
cmd_cpin_query()
{
    at "$1" "AT+CPIN?"
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

#query serving cell monitor
cmd_monsc()
{
    at "$1" "AT^MONSC"
}

#query cell RSSI
cmd_cserssi_query()
{
    at "$1" "AT^CSERSSI?"
}

#query frequency info
cmd_hfreqinfo_query()
{
    at "$1" "AT^HFREQINFO?"
}

#query current band config
cmd_band_query()
{
    at "$1" "AT!BAND?"
}

#query supported band templates
cmd_band_list_query()
{
    at "$1" "AT!BAND=?"
}

#set a custom band template
#$2: band class  $3: band list mask
cmd_band_set_custom()
{
    at "$1" "AT!BAND=0F,1,\"Custom\",$2,$3"
}

#reset band template
#$2: template index (0F on success, 00 on failure)
cmd_band_reset()
{
    at "$1" "AT!BAND=$2"
}

#query chip temperature
cmd_chiptemp_query()
{
    at "$1" "AT^CHIPTEMP?"
}

#switch SIM slot (unisoc)
#$2: sim slot
cmd_simswitch_set()
{
    at "$1" "AT^SIMSWITCH=$2"
}

#switch SIM slot (hisilicon)
#$2: first arg  $3: second arg
cmd_scichg()
{
    at "$1" "AT^SCICHG=$2,$3"
}
