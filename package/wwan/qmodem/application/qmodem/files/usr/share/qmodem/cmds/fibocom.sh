#!/bin/sh
# Fibocom AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

#query USB mode
cmd_gtusbmode_query()
{
    at "$1" "AT+GTUSBMODE?"
}

#set USB mode
#$2: mode number
cmd_gtusbmode_set()
{
    at "$1" "AT+GTUSBMODE=$2"
}

#query network preference / band config
cmd_gtact_query()
{
    at "$1" "AT+GTACT?"
}

#query supported band configs
cmd_gtact_list_query()
{
    at "$1" "AT+GTACT=?"
}

#set network preference / band config
#$2: parameter tail after AT+GTACT=
cmd_gtact_set()
{
    at "$1" "AT+GTACT=$2"
}

#query battery
cmd_cbc()
{
    at "$1" "AT+CBC"
}

#query temperature (MTSM extended)
cmd_mtsm_1_6()
{
    at "$1" "AT+MTSM=1,6"
}

#query ADC (cpu voltage etc.)
cmd_gtladc()
{
    at "$1" "AT+GTLADC"
}

#query sensor temperature
cmd_gtsenrdtemp()
{
    at "$1" "AT+GTSENRDTEMP=1"
}

#query temperature
cmd_mtsm()
{
    at "$1" "AT+MTSM=1"
}

#query model name
cmd_cgmm()
{
    at "$1" "AT+CGMM?"
}

#query manufacturer
cmd_cgmi()
{
    at "$1" "AT+CGMI?"
}

#query revision
cmd_cgmr()
{
    at "$1" "AT+CGMR?"
}

#query dual SIM slot
cmd_gtdualsim_query()
{
    at "$1" "AT+GTDUALSIM?"
}

#switch SIM slot
#$2: sim slot param
cmd_gtdualsim_set()
{
    at "$1" "AT+GTDUALSIM=$2"
}

#query IMEI
cmd_cgsn()
{
    at "$1" "AT+CGSN?"
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

#query current carrier (MediaTek)
cmd_gtcurcar_query()
{
    at "$1" "AT+GTCURCAR?"
}

#query subscriber number
cmd_cnum()
{
    at "$1" "AT+CNUM"
}

#query IMSI
cmd_cimi()
{
    at "$1" "AT+CIMI?"
}

#query ICCID
cmd_iccid()
{
    at "$1" "AT+ICCID"
}

#query CCID
cmd_ccid()
{
    at "$1" "AT+CCID"
}

#set IMEI (qualcomm/unisoc/default)
#$2: imei
cmd_gtsn_set_imei()
{
    at "$1" "AT+GTSN=1,7,\"$2\""
}

#set IMEI (mediatek)
#$2: imei
cmd_egmrext_set_imei()
{
    at "$1" "AT+EGMREXT=1,7,\"$2\""
}

#set IMEI (lte platform)
#$2: imei
cmd_lctsn_set_imei()
{
    at "$1" "AT+LCTSN=1,7,\"$2\""
}

#query packet service RAT
cmd_psrat_query()
{
    at "$1" "AT+PSRAT?"
}

#query data statistics
cmd_gtstatis_query()
{
    at "$1" "AT+GTSTATIS?"
}

#query cell info
cmd_gtccinfo_query()
{
    at "$1" 'AT+GTCCINFO?'
}

#query CA info
cmd_gtcainfo_query()
{
    at "$1" 'AT+GTCAINFO?'
}

#query cell lock state
cmd_gtcelllock_query()
{
    at "$1" "AT+GTCELLLOCK?"
}

#set cell lock state
#$2: parameter tail after AT+GTCELLLOCK=
cmd_gtcelllock_set()
{
    at "$1" "AT+GTCELLLOCK=$2"
}

#query signal quality
cmd_csq()
{
    at "$1" "AT+CSQ"
}

#query usage records
cmd_gtusagerec_query()
{
    at "$1" "AT+GTUSAGEREC?"
}

#control usage records (clear etc.)
cmd_gtusagerec()
{
    at "$1" "AT+GTUSAGEREC"
}
