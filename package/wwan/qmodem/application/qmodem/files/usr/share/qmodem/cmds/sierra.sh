#!/bin/sh
# Sierra Wireless AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is always the AT port, remaining args are command parameters.

#unlock advanced commands
#$2: password (default A710 handled by caller)
cmd_entercnd()
{
    at "$1" "AT!ENTERCND=\"$2\""
}

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

#query USB composition
cmd_usbcomp_query()
{
    at "$1" "AT!USBCOMP?"
}

#set USB composition
#$2: interface mask
cmd_usbcomp_set()
{
    at "$1" "AT!USBCOMP=1,4,$2"
}

#query RAT preference
cmd_selrat_query()
{
    at "$1" "at!SELRAT?"
}

#set RAT preference
#$2: rat code
cmd_selrat_set()
{
    at "$1" "AT!SELRAT=$2"
}

#query SIM slot
cmd_uims_query()
{
    at "$1" "AT!UIMS?"
}

#query SIM status
cmd_cpin_query()
{
    at "$1" "AT+CPIN?"
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

#query modem status
cmd_gstatus_query()
{
    at "$1" "AT!GSTATUS?"
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

#query supply voltage
cmd_pcvolt_query()
{
    at "$1" "AT!PCVOLT?"
}

#query temperature
cmd_pctemp_query()
{
    at "$1" "AT!PCTEMP?"
}
