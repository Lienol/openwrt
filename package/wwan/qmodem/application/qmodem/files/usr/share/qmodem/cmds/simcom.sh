#!/bin/sh
# SIMCom AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

#query IMEI
cmd_cgsn()
{
    at "$1" "AT+CGSN"
}

#set IMEI
#$2: imei
cmd_simei_set()
{
    at "$1" "AT+SIMEI=$2"
}

#query USB config
cmd_cusbcfg_query()
{
    at "$1" 'AT+CUSBCFG?'
}

#set USB id
#$2: mode number (product id hex)
cmd_cusbcfg_set_usbid()
{
    at "$1" "AT+CUSBCFG=usbid,1e0e,$2"
}

#query PCIe mode
cmd_cpciemode_query()
{
    at "$1" "AT+CPCIEMODE?"
}

#query MYCONFIG
cmd_myconfig_query()
{
    at "$1" 'AT$MYCONFIG?'
}

#set USBNETMODE
#$2: mode param
cmd_myconfig_set_usbnetmode()
{
    at "$1" "AT\$MYCONFIG=\"USBNETMODE\",$2,1"
}

#query network mode
cmd_cnmp_query()
{
    at "$1" 'AT+CNMP?'
}

#set network mode
#$2: network prefer config
cmd_cnmp_set()
{
    at "$1" "AT+CNMP=$2"
}

#query battery
cmd_cbc()
{
    at "$1" "AT+CBC"
}

#query temperature
cmd_cpmutemp()
{
    at "$1" "AT+CPMUTEMP"
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
cmd_simcomati()
{
    at "$1" "AT+SIMCOMATI"
}

#query SIM slot
cmd_smsimcfg_query()
{
    at "$1" "AT+SMSIMCFG?"
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

#query system info (in-use RAT etc.)
cmd_cpsi_query()
{
    at "$1" 'AT+CPSI?'
}

#query band config for a RAT
#$2: band type (w_band/lte_band/nsa_nr5g_band/nr5g_band)
cmd_csyssel_query()
{
    at "$1" "AT+CSYSSEL=\"$2\""
}

#set band config for a RAT
#$2: band type  $3: band list
cmd_csyssel_set()
{
    at "$1" "AT+CSYSSEL=\"$2\",$3"
}

#query band preference bitmask
cmd_cnbp_query()
{
    at "$1" "AT+CNBP?"
}

#set band preference bitmask
#$2: parameter tail after AT+CNBP=
cmd_cnbp_set()
{
    at "$1" "AT+CNBP=$2"
}

#query LTE cell lock state
cmd_ccellcfg_query()
{
    at "$1" "AT+CCELLCFG?"
}

#query NR cell lock state
cmd_c5gcellcfg_query()
{
    at "$1" "AT+C5GCELLCFG?"
}

#unlock LTE cell lock
cmd_ccellcfg_unlock()
{
    at "$1" "AT+CCELLCFG=0"
}

#unlock NR cell lock
cmd_c5gcellcfg_unlock()
{
    at "$1" 'AT+C5GCELLCFG="unlock"'
}

#lock LTE cell
#$2: pci  $3: arfcn
cmd_ccellcfg_lock()
{
    at "$1" "AT+CCELLCFG=1,$2,$3;+CNMP=38"
}

#lock NR cell
#$2: pci  $3: arfcn  $4: scs  $5: band
cmd_c5gcellcfg_lock()
{
    at "$1" "AT+C5GCELLCFG=\"pci\",$2,$3,$4,$5;+CNMP=71"
}

#query neighbor cell scan state for a RAT
#$2: rat (nr5g/lte)
cmd_cnwsearch_query()
{
    at "$1" "AT+CNWSEARCH=\"$2\""
}

#start neighbor cell scan for a RAT
#$2: rat (nr5g/lte)  $3: mode
cmd_cnwsearch_scan()
{
    at "$1" "AT+CNWSEARCH=\"$2\",$3"
}

#query network info
cmd_cnwinfo_query()
{
    at "$1" 'AT+CNWINFO?'
}
