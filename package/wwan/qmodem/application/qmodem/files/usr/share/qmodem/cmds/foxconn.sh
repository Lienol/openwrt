#!/bin/sh
# Foxconn AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port; $2 is the model-dependent AT prefix
# (at_pre: AT+ or AT^) for wrappers documented as prefixed.

#query product info (IMEI etc.)
cmd_ati()
{
    at "$1" "ATI"
}

#clear nv 550 (prefixed)
cmd_nv_550_clear()
{
    at "$1" "${2}nv=550,\"0\""
}

#write nv 550 (prefixed)
#$3: formatted value
cmd_nv_550_set()
{
    at "$1" "${2}nv=550,9,\"$3\""
}

#query PCIe mode (prefixed)
cmd_pciemode_query()
{
    at "$1" "${2}PCIEMODE?"
}

#query USB switch (prefixed)
cmd_usbswitch_query()
{
    at "$1" "${2}USBSWITCH?"
}

#set USB switch (prefixed)
#$3: mode number
cmd_usbswitch_set()
{
    at "$1" "${2}USBSWITCH=$3"
}

#query SL mode (prefixed)
cmd_slmode_query()
{
    at "$1" "${2}SLMODE?"
}

#set SL mode (prefixed)
#$3: mode value (hex digit pair, comma separated)
cmd_slmode_set()
{
    at "$1" "${2}SLMODE=$3"
}

#query SIM slot switch state (prefixed)
cmd_switch_slot_query()
{
    at "$1" "${2}switch_slot?"
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

#set COPS numeric format
cmd_cops_numeric()
{
    at "$1" "AT+COPS=3,2"
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

#query band preference (prefixed)
cmd_band_pref_query()
{
    at "$1" "${2}BAND_PREF?"
}

#lock bands for a RAT (prefixed)
#$3: RAT (WCDMA/LTE/NR5G)  $4: band list
cmd_band_pref_lock()
{
    at "$1" "${2}BAND_PREF=$3,2,$4"
}

#query supply voltage
cmd_pcvolt_query()
{
    at "$1" "AT!PCVOLT?"
}

#query temperature (prefixed)
cmd_temp_query()
{
    at "$1" "${2}temp?"
}

#query debug/cell info (prefixed)
cmd_debug_query()
{
    at "$1" "${2}debug?"
}
