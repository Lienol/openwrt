#!/bin/sh
# Quectel AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.

#query 5G LAN state
cmd_qcfg_5glan_query()
{
    at "$1" 'AT+QCFG="5glan"'
}

#set 5G LAN state
#$2: enabled (0/1)
cmd_qcfg_5glan_set()
{
    at "$1" "AT+QCFG=\"5glan\",1,$2"
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

#query USB network mode
cmd_qcfg_usbnet_query()
{
    at "$1" 'AT+QCFG="usbnet"'
}

#set USB network mode
#$2: mode number
cmd_qcfg_usbnet_set()
{
    at "$1" "AT+QCFG=\"usbnet\",$2"
}

#query network scan mode
cmd_qcfg_nwscanmode_query()
{
    at "$1" 'AT+QCFG="nwscanmode"'
}

#set network scan mode
#$2: network prefer config
cmd_qcfg_nwscanmode_set()
{
    at "$1" "AT+QCFG=\"nwscanmode\",$2"
}

#query network preference
cmd_qnwprefcfg_mode_pref_query()
{
    at "$1" 'AT+QNWPREFCFG="mode_pref"'
}

#set network preference
#$2: network prefer config
cmd_qnwprefcfg_mode_pref_set()
{
    at "$1" "AT+QNWPREFCFG=\"mode_pref\",$2"
}

#query battery
cmd_cbc()
{
    at "$1" "AT+CBC"
}

#query temperature
cmd_qtemp()
{
    at "$1" "AT+QTEMP"
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
cmd_quimslot_query()
{
    at "$1" "AT+QUIMSLOT?"
}

#query supported SIM slots
cmd_quimslot_list_query()
{
    at "$1" "AT+QUIMSLOT=?"
}

#switch SIM slot
#$2: sim slot param
cmd_quimslot_set()
{
    at "$1" "AT+QUIMSLOT=$2"
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

#query CCID
cmd_ccid()
{
    at "$1" "AT+CCID"
}

#query network info
cmd_qnwinfo()
{
    at "$1" "AT+QNWINFO"
}

#query signal quality
cmd_csq()
{
    at "$1" "AT+CSQ"
}

#query 5G AMBR
cmd_qnwcfg_nr5g_ambr_query()
{
    at "$1" 'AT+QNWCFG="nr5g_ambr"'
}

#query up/down speed
cmd_qnwcfg_updown_query()
{
    at "$1" 'AT+QNWCFG="up/down"'
}

#query band config for a RAT
#$2: band type (gw_band/lte_band/nsa_nr5g_band/nr5g_band)
cmd_qnwprefcfg_band_query()
{
    at "$1" "AT+QNWPREFCFG=\"$2\""
}

#set band config for a RAT
#$2: band type  $3: band list
cmd_qnwprefcfg_band_set()
{
    at "$1" "AT+QNWPREFCFG=\"$2\",$3"
}

#query band lock config
cmd_qcfg_band_query()
{
    at "$1" "AT+QCFG=\"band\""
}

#reset LTE band lock to a hex mask
#$2: hex band mask
cmd_qcfg_band_reset()
{
    at "$1" "AT+QCFG=\"band\",0,$2,0"
}

#query neighbor cells
cmd_qeng_neighbourcell()
{
    at "$1" 'AT+QENG="neighbourcell"'
}

#query serving cell
cmd_qeng_servingcell()
{
    at "$1" 'AT+QENG="servingcell"'
}

#query CA info
cmd_qcainfo()
{
    at "$1" "AT+QCAINFO"
}

#query cell lock state
#$2: scope (common/4g, common/5g, common/lte)
cmd_qnwlock_query()
{
    at "$1" "AT+QNWLOCK=\"$2\""
}

#unlock cell lock
#$2: scope (common/4g, common/5g, common/lte)
cmd_qnwlock_unlock()
{
    at "$1" "AT+QNWLOCK=\"$2\",0"
}

#set cell lock
#$2: scope (common/4g, common/5g, common/lte)
#$3: parameter tail after the scope (e.g. 1,arfcn,pci)
cmd_qnwlock_set()
{
    at "$1" "AT+QNWLOCK=\"$2\",$3"
}

#query LTE data counter
cmd_qgdcnt_query()
{
    at "$1" "AT+QGDCNT?"
}

#query NR data counter
cmd_qgdnrcnt_query()
{
    at "$1" "AT+QGDNRCNT?"
}

#set data counter auto-save interval
#$2: interval seconds
cmd_qaugdcnt_set()
{
    at "$1" "AT+QAUGDCNT=$2"
}

#set NR data counter state
#$2: state (0/1)
cmd_qgdnrcnt_set()
{
    at "$1" "AT+QGDNRCNT=$2"
}

#set LTE data counter state
#$2: state (0/1)
cmd_qgdcnt_set()
{
    at "$1" "AT+QGDCNT=$2"
}
