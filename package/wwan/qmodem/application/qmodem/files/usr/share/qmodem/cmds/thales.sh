#!/bin/sh
# Thales (Cinterion/Gemalto) AT command wrappers.
# Vendor scripts must send AT commands only through these cmd_* interfaces.
# Convention: $1 is the AT port, remaining args are command parameters.
#
# Command set verified against TC_MV32-W_AT_Command_Reference_Guide_r2.pdf:
#   AT+SETCONFIG   15.50  USB RMNET/MBIM data mode switch
#   AT+MODESWITCH  15.49  USB/PCIe mode switch
#   AT^SLMODE      15.24  network preference (AT^ form documented)
#   AT+BAND_PREF   15.32  band lock
#   AT^DEBUG       15.33  serving cell info (AT^ form documented)
#   AT+SWITCH_SLOT 15.41  SIM slot switch
#   AT^TEMP        15.13  temperature (AT^ form documented)
#   AT+ICCID       15.10  ICCID

#query product info (IMEI / manufacturer / model / revision)
cmd_ati()
{
    at "$1" "ATI"
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

#query USB data mode (0=MBIM, 1=RmNet)
cmd_setconfig_query()
{
    at "$1" "AT+SETCONFIG?"
}

#set USB data mode
#$2: 0 (MBIM) / 1 (RmNet)
cmd_setconfig_set()
{
    at "$1" "AT+SETCONFIG=$2"
}

#query USB/PCIe mode switch state
cmd_modeswitch_query()
{
    at "$1" "AT+MODESWITCH?"
}

#set USB/PCIe mode switch
#$2: mode value
cmd_modeswitch_set()
{
    at "$1" "AT+MODESWITCH=$2"
}

#query network preference
#   ^SLMODE:1,<pref>: 0 auto, 1 WCDMA, 2 LTE, 3 WCDMA+LTE, 4 NR5G,
#                    5 WCDMA+NR5G, 6 LTE+NR5G, 7 WCDMA+LTE+NR5G
cmd_slmode_query()
{
    at "$1" "AT^SLMODE?"
}

#set network preference
#$2: mode value (see cmd_slmode_query)
cmd_slmode_set()
{
    at "$1" "AT^SLMODE=1,$2"
}

#query SIM slot switch state
cmd_switch_slot_query()
{
    at "$1" "AT+SWITCH_SLOT?"
}

#set SIM slot
#$2: 0 (SIM1) / 1 (SIM2)
cmd_switch_slot_set()
{
    at "$1" "AT+SWITCH_SLOT=$2"
}

#query band preference
cmd_band_pref_query()
{
    at "$1" "AT+BAND_PREF?"
}

#lock bands for a RAT
#$2: RAT (WCDMA/LTE/NR5G)  $3: band list
cmd_band_pref_lock()
{
    at "$1" "AT+BAND_PREF=$2,2,$3"
}

#query temperature (AT^ form documented)
cmd_temp_query()
{
    at "$1" "AT^TEMP?"
}

#query debug / serving cell info (AT^ form documented)
cmd_debug_query()
{
    at "$1" "AT^DEBUG?"
}

#restart module
cmd_reset()
{
    at "$1" "AT+RESET"
}
