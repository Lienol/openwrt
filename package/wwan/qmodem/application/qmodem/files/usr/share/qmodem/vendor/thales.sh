#!/bin/sh
# Copyright (C) 2026 x-shark
_Vendor="thales"
_Author="ArlongLi"
_Maintainer="arlong2693@gmail.com"
# Thales MV32-W / MV32-W-B (Gemalto Cinterion / Telit Cinterion) 5G M.2 module
# - USB VID:PID 1e2d:00f2 (Gemalto M2M GmbH / Thales DIS)
# - Qualcomm X65 (SDX65) platform, Foxconn-built firmware (revision prefix "FDE")
# - Self-contained vendor script based on the generic template. The command set
#   below is verified against TC_MV32-W_AT_Command_Reference_Guide_r2.pdf:
#     AT+SETCONFIG   15.50  USB RMNET/MBIM data mode switch
#     AT+MODESWITCH  15.49  USB/PCIe mode switch (manual uses AT+ only)
#     AT^SLMODE      15.24  network preference (AT^ form documented)
#     AT+BAND_PREF   15.32  band lock (manual uses AT+ only)
#     AT^DEBUG       15.33  serving cell info (AT^ form documented)
#     AT+SWITCH_SLOT 15.41  SIM slot switch (manual uses AT+ only)
#     AT^TEMP        15.13  temperature (AT^ form documented)
#     AT+ICCID       15.10  ICCID
# - IMEI modification is NOT supported (only AT+GSN/AT+CGSN/AT+GETIMEI read).
# - No voltage query command is exposed by this module.
source "${QMODEM_HOME:-/usr/share/qmodem}/generic.sh"
source "${QMODEM_HOME:-/usr/share/qmodem}/cmds/thales.sh"
debug_subject="thales_ctrl"

get_imei()
{
    imei=$(cmd_ati "$at_port" | awk -F': ' '/^IMEI:/ {print $2}' | xargs)
    json_add_string imei $imei
}

# Parse ATI output:
#   Manufacturer: Thales
#   Model: MV32-W-B
#   Revision: FDE.F0.0.0.1.3.GC.001  1  [Sep 05 2022 08:00:00]
base_info()
{
    baseinfos=$(cmd_ati "$at_port")
    manufacturer=$(echo "$baseinfos" | awk -F': ' '/^Manufacturer:/ {print $2}' | xargs)
    name=$(echo "$baseinfos" | awk -F': ' '/^Model:/ {print $2}' | xargs)
    revision=$(echo "$baseinfos" | awk -F': ' '/^Revision:/ {print $2}' | xargs)
    class="Base Information"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "model" "$name" "Model"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_connect_status
    _get_temperature
}

# MV32-W switches the USB data path with AT+SETCONFIG (section 15.50):
#   AT+SETCONFIG?  -> +SETCONFIG:0  (Now is MBIM mode)
#                 -> +SETCONFIG:1  (Now is RmNet mode)
get_mode()
{
    local mode_num
    local mode
    ucfg=$(cmd_setconfig_query "$at_port")
    config_type=$(echo "$ucfg" | grep -o '+SETCONFIG: *[0-9]' | grep -o '[0-9]' | xargs)
    if [ "$config_type" = "0" ]; then
        mode_num="0"
    elif [ "$config_type" = "1" ]; then
        mode_num="1"
    fi
    case "$platform" in
        "qualcomm")
            case "$mode_num" in
                "0") mode="mbim" ;;
                "1") mode="rmnet" ;;
                *) mode="${mode_num}" ;;
            esac
        ;;
        *)
            mode="${mode_num}"
        ;;
    esac
    available_modes=$(uci -q get qmodem.$config_section.modes)
    json_add_object "mode"
    for available_mode in $available_modes; do
        if [ "$mode" = "$available_mode" ]; then
            json_add_string "$available_mode" "1"
        else
            json_add_string "$available_mode" "0"
        fi
    done
    json_close_object
}

set_mode()
{
    local mode=$1
    case "$platform" in
        "qualcomm")
            case "$mode" in
                "mbim") mode_num="0" ;;
                "rmnet") mode_num="1" ;;
                *) mode_num="0" ;;
            esac
        ;;
        *)
            mode_num="0"
        ;;
    esac
    #set modem
    res=$(cmd_setconfig_set "$at_port" "$mode_num")
    json_select "result"
    json_add_string "set_mode" "$res"
    json_close_object
}

# Network preference via AT^SLMODE (manual 15.24):
#   AT^SLMODE?  -> ^SLMODE:1,<pref_mode>
#   <pref_mode>: 0 auto, 1 WCDMA, 2 LTE, 3 WCDMA+LTE, 4 NR5G,
#                5 WCDMA+NR5G, 6 LTE+NR5G, 7 WCDMA+LTE+NR5G
get_network_prefer()
{
    res=$(cmd_slmode_query "$at_port" | grep -o '[0-9]\+' | tr -d '\n' | tr -d ' ')
    local network_prefer_3g="0"
    local network_prefer_4g="0"
    local network_prefer_5g="0"
    case $res in
        "10"|"17")
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        "11")
            network_prefer_3g="1"
            ;;
        "12")
            network_prefer_4g="1"
            ;;
        "14")
            network_prefer_5g="1"
            ;;
        "13")
            network_prefer_3g="1"
            network_prefer_4g="1"
            ;;
        "15")
            network_prefer_3g="1"
            network_prefer_5g="1"
            ;;
        "16")
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        *)
            network_prefer_3g="0"
            network_prefer_4g="0"
            network_prefer_5g="0"
            ;;
    esac
    json_add_object network_prefer
    json_add_string 3G $network_prefer_3g
    json_add_string 4G $network_prefer_4g
    json_add_string 5G $network_prefer_5g
    json_close_object
}

set_network_prefer()
{
    local network_prefer_3g=$(echo $1 | jq -r 'contains(["3G"])')
    local network_prefer_4g=$(echo $1 | jq -r 'contains(["4G"])')
    local network_prefer_5g=$(echo $1 | jq -r 'contains(["5G"])')
    count=$(echo $1 | jq -r 'length')
    case "$count" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                code="1"
            elif [ "$network_prefer_4g" = "true" ]; then
                code="2"
            elif [ "$network_prefer_5g" = "true" ]; then
                code="4"
            fi
            ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                code="3"
            elif [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                code="6"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                code="5"
            fi
            ;;
        *)
            code="7"
            ;;
    esac
    res=$(cmd_slmode_set "$at_port" "$code")
    json_add_string "code" "$code"
    json_add_string "result" "$res"
}

# Band lock via AT+BAND_PREF (manual 15.32):
#   AT+BAND_PREF?  ->
#     WCDMA,Enable Bands :1,2,4,5,8,
#     WCDMA,Disable Bands:
#     LTE,Enable Bands : 1,2,3,4,5,7,8,12,
#     LTE,Disable Bands:
#     NR5G_NSA,Enable Bands :
#     NR5G_SA,Enable Bands :
get_lockband()
{
    json_add_object "lockband"
    get_lockband_nr
    json_close_object
}

get_lockband_nr()
{
    get_lockbans=$(cmd_band_pref_query "$at_port")

    # WCDMA
    wcdma_enable=$(echo "$get_lockbans" | grep "WCDMA,Enable Bands" | cut -d':' -f2 | tr -d ' ' | tr ',' ' ')
    wcdma_disable=$(echo "$get_lockbans" | grep "WCDMA,Disable Bands" | cut -d':' -f2 | tr -d ' ' | tr ',' ' ')
    wcdma_enable=$(echo "$wcdma_enable" | tr ' ' '\n' | grep -v '^$')
    wcdma_disable=$(echo "$wcdma_disable" | tr ' ' '\n' | grep -v '^$')
    wcdma_all=$(echo "$wcdma_enable $wcdma_disable" | tr ' ' '\n' | grep -v '^$' | sort -n | uniq)

    # LTE
    lte_enable=$(echo "$get_lockbans" | grep "LTE,Enable Bands" | cut -d':' -f2 | tr -d ' ' | tr ',' ' ')
    lte_disable=$(echo "$get_lockbans" | grep "LTE,Disable Bands" | cut -d':' -f2 | tr -d ' ' | tr ',' ' ')
    lte_enable=$(echo "$lte_enable" | tr ' ' '\n' | grep -v '^$')
    lte_disable=$(echo "$lte_disable" | tr ' ' '\n' | grep -v '^$')
    lte_all=$(echo "$lte_enable $lte_disable" | tr ' ' '\n' | grep -v '^$' | sort -n | uniq)

    # NR NSA
    nr_nsa_enable=$(echo "$get_lockbans" | grep "NR5G_NSA,Enable Bands" | cut -d':' -f2 | tr -d ' ' | tr ',' ' ')
    nr_nsa_disable=$(echo "$get_lockbans" | grep "NR5G_NSA,Disable Bands" | cut -d':' -f2 | tr -d ' ' | tr ',' ' ')
    nr_nsa_enable=$(echo "$nr_nsa_enable" | tr ' ' '\n' | grep -v '^$')
    nr_nsa_disable=$(echo "$nr_nsa_disable" | tr ' ' '\n' | grep -v '^$')
    nr_nsa_all=$(echo "$nr_nsa_enable $nr_nsa_disable" | tr ' ' '\n' | grep -v '^$' | sort -n | uniq)

    # NR SA
    nr_sa_enable=$(echo "$get_lockbans" | grep "NR5G_SA,Enable Bands" | cut -d':' -f2 | tr -d ' ' | tr ',' ' ')
    nr_sa_disable=$(echo "$get_lockbans" | grep "NR5G_SA,Disable Bands" | cut -d':' -f2 | tr -d ' ' | tr ',' ' ')
    nr_sa_enable=$(echo "$nr_sa_enable" | tr ' ' '\n' | grep -v '^$')
    nr_sa_disable=$(echo "$nr_sa_disable" | tr ' ' '\n' | grep -v '^$')
    nr_sa_all=$(echo "$nr_sa_enable $nr_sa_disable" | tr ' ' '\n' | grep -v '^$' | sort -n | uniq)
    # AT+BAND_PREF can only set a single NR5G RAT, so merge the NR5G_NSA and
    # NR5G_SA band lists into one NR class that set_lockband() can actually lock.
    nr_enable=$(echo "$nr_nsa_enable $nr_sa_enable" | tr ' ' '\n' | grep -v '^$' | sort -n | uniq)
    nr_all=$(echo "$nr_nsa_all $nr_sa_all" | tr ' ' '\n' | grep -v '^$' | sort -n | uniq)

    # UMTS
    json_add_object "UMTS"
    json_add_array "available_band"
    for i in $wcdma_all; do
        echo "$i" | grep -Eq '^[0-9]+$' && add_avalible_band_entry "$i" "UMTS_$i"
    done
    json_close_array
    json_add_array "lock_band"
    for i in $wcdma_enable; do
        echo "$i" | grep -Eq '^[0-9]+$' && json_add_string "" "$i"
    done
    json_close_array
    json_close_object

    # LTE
    json_add_object "LTE"
    json_add_array "available_band"
    for i in $lte_all; do
        echo "$i" | grep -Eq '^[0-9]+$' && add_avalible_band_entry "$i" "LTE_B$i"
    done
    json_close_array
    json_add_array "lock_band"
    for i in $lte_enable; do
        echo "$i" | grep -Eq '^[0-9]+$' && json_add_string "" "$i"
    done
    json_close_array
    json_close_object

    # NR
    json_add_object "NR"
    json_add_array "available_band"
    for i in $nr_all; do
        echo "$i" | grep -Eq '^[0-9]+$' && add_avalible_band_entry "$i" "NR_N$i"
    done
    json_close_array
    json_add_array "lock_band"
    for i in $nr_enable; do
        echo "$i" | grep -Eq '^[0-9]+$' && json_add_string "" "$i"
    done
    json_close_array
    json_close_object
}

set_lockband()
{
    config=$1
    band_class=$(echo $config | jq -r '.band_class')
    lock_band=$(echo $config | jq -r '.lock_band')
    case "$band_class" in
        "UMTS")
            res=$(cmd_band_pref_lock "$at_port" WCDMA "$lock_band")
            ;;
        "LTE")
            res=$(cmd_band_pref_lock "$at_port" LTE "$lock_band")
            ;;
        "NR")
            res=$(cmd_band_pref_lock "$at_port" NR5G "$lock_band")
            ;;
        *)
            res="ERROR: unsupported band_class $band_class"
            ;;
    esac
    json_select "result"
    json_add_string "set_lockband" "$res"
    json_add_string "config" "$config"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$lock_band"
    json_close_object
}

sim_info()
{
    class="SIM Information"

    # SIM Status
    sim_status=$(cmd_cpin_query "$at_port" | grep "+CPIN:")
    sim_status=${sim_status:7:-1}
    #lowercase
    sim_status=$(echo $sim_status | tr A-Z a-z)

    # SIM Slot
    sim_slot=$(cmd_switch_slot_query "$at_port" | grep ENABLE | grep -o 'SIM[0-9]' | grep -o '[0-9]')

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    add_plain_info_entry "SIM Status" "$sim_status" "SIM Status"
    [ -n "$sim_slot" ] && add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"

    # IMEI
    imei=$(cmd_ati "$at_port" | awk -F': ' '/^IMEI:/ {print $2}' | xargs)
    [ -n "$imei" ] && add_plain_info_entry "IMEI" "$imei" "IMEI"

    # Operator
    cmd_cops_numeric "$at_port" > /dev/null 2>&1
    isp=$(cmd_cops_query "$at_port" | sed -n '2p' | awk -F'"' '{print $2}')
    if [ "$isp" = "CHN-CMCC" ] || [ "$isp" = "CMCC" ] || [ "$isp" = "46000" ]; then
        isp="中国移动"
    elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "CUCC" ] || [ "$isp" = "46001" ]; then
        isp="中国联通"
    elif [ "$isp" = "CHN-CT" ] || [ "$isp" = "CT" ] || [ "$isp" = "46011" ]; then
        isp="中国电信"
    fi
    [ -n "$isp" ] && add_plain_info_entry "ISP" "$isp" "ISP"

    # ICCID
    iccid=$(cmd_iccid "$at_port" | grep "ICCID:" | grep -o '[0-9]\{19,20\}' | head -n 1)
    [ -n "$iccid" ] && add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity"

    # Phone Number
    sim_number=$(cmd_cnum "$at_port" | awk -F'"' '{print $2}' | head -n 1)
    [ -n "$sim_number" ] && add_plain_info_entry "Phone Number" "$sim_number" "Phone Number"
}

network_info()
{
    class="Network Information"
    [ -z "$network_type" ] && {
        local rat_num=$(cmd_cops_query "$at_port" | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
}

# Serving cell info via AT^DEBUG (manual 15.33):
#   RAT: WCDMA | LTE | LTE+NR | NR5G_SA
cell_info()
{
    class="Cell Information"
    response=$(cmd_debug_query "$at_port")
    network_mode=$(echo "$response" | awk -F'RAT:' '{print $2}' | xargs)

    case $network_mode in
        "WCDMA")
            wcdma_mcc=$(echo "$response" | awk -F'mcc:' '{print $2}' | awk -F',' '{print $1}' | xargs)
            wcdma_mnc=$(echo "$response" | awk -F'mnc:' '{print $2}' | xargs)
            wcdma_band=$(echo "$response" | awk -F'band:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            wcdma_channel=$(echo "$response" | awk -F'channel:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            wcdma_cell_id=$(echo "$response" | awk -F'cell_id:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            wcdma_lac=$(echo "$response" | awk -F'lac:' '{print $2}' | xargs)
            wcdma_rssi=$(echo "$response" | awk -F'rssi:' '{print $2}' | xargs)
            add_plain_info_entry "Network Mode" "$network_mode" "Network Mode"
            add_plain_info_entry "MCC" "$wcdma_mcc" "Mobile Country Code"
            add_plain_info_entry "MNC" "$wcdma_mnc" "Mobile Network Code"
            add_plain_info_entry "Cell ID" "$wcdma_cell_id" "Cell ID"
            add_plain_info_entry "LAC" "$wcdma_lac" "Location Area Code"
            add_plain_info_entry "UARFCN" "$wcdma_channel" "UTRA Absolute Radio Frequency Channel Number"
            add_plain_info_entry "Band" "$wcdma_band" "Band"
            add_bar_info_entry "RSSI" "$wcdma_rssi" "Received Signal Strength Indicator" -120 -20 dBm
            ;;
        "LTE"|"LTE+NR")
            lte_mcc=$(echo "$response" | awk -F'mcc:' '{print $2}' | awk -F',' '{print $1}' | xargs)
            lte_mnc=$(echo "$response" | awk -F'mnc:' '{print $2}' | xargs)
            lte_earfcn=$(echo "$response" | awk -F'channel:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            lte_physical_cell_id=$(echo "$response" | awk -F'pci:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            lte_cell_id=$(echo "$response" | awk -F'lte_cell_id:' '{print $2}' | xargs)
            lte_band=$(echo "$response" | awk -F'lte_band:' '{print $2}' | awk -F',' '{print $1}' | xargs)
            lte_band_width=$(echo "$response" | awk -F'lte_band_width:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            lte_sinr=$(echo "$response" | awk -F'lte_snr:' '{print $2}' | awk '{print $1}' | xargs)
            lte_sinr=$(process_signal_value "$lte_sinr")
            lte_rsrq=$(echo "$response" | awk -F'rsrq:' '{print $2}' | xargs)
            lte_rsrq=$(process_signal_value "$lte_rsrq")
            lte_rsrp=$(echo "$response" | awk -F'lte_rsrp:' '{print $2}' | awk '{print $1}' | xargs)
            lte_rsrp=$(process_signal_value "$lte_rsrp")
            lte_rssi=$(echo "$response" | awk -F'lte_rssi:' '{print $2}' | awk -F',' '{print $1}' | xargs)
            lte_rssi=$(process_signal_value "$lte_rssi")
            lte_tac=$(echo "$response" | awk -F'lte_tac:' '{print $2}' | xargs)
            lte_tx_power=$(echo "$response" | awk -F'lte_tx_pwr:' '{print $2}' | xargs)
            add_plain_info_entry "Network Mode" "$network_mode" "Network Mode"
            add_plain_info_entry "MCC" "$lte_mcc" "Mobile Country Code"
            add_plain_info_entry "MNC" "$lte_mnc" "Mobile Network Code"
            add_plain_info_entry "Cell ID" "$lte_cell_id" "Cell ID"
            add_plain_info_entry "Physical Cell ID" "$lte_physical_cell_id" "Physical Cell ID"
            add_plain_info_entry "EARFCN" "$lte_earfcn" "E-UTRA Absolute Radio Frequency Channel Number"
            add_plain_info_entry "Band" "$lte_band" "Band"
            add_plain_info_entry "Bandwidth" "$lte_band_width" "Bandwidth"
            add_plain_info_entry "TAC" "$lte_tac" "Tracking area code of cell served by neighbor Enb"
            add_bar_info_entry "RSRQ" "$lte_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
            add_bar_info_entry "RSRP" "$lte_rsrp" "Reference Signal Received Power" -140 -44 dBm
            add_bar_info_entry "RSSI" "$lte_rssi" "Received Signal Strength Indicator" -120 -20 dBm
            add_bar_info_entry "SINR" "$lte_sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
            add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power"
            ;;
        "NR5G_SA")
            nr_mcc=$(echo "$response" | awk -F'mcc:' '{print $2}' | awk -F',' '{print $1}' | xargs)
            nr_mnc=$(echo "$response" | awk -F'mnc:' '{print $2}' | xargs)
            nr_earfcn=$(echo "$response" | awk -F'channel:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            nr_physical_cell_id=$(echo "$response" | awk -F'pci:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            nr_cell_id=$(echo "$response" | awk -F'nr_cell_id:' '{print $2}' | xargs)
            nr_band=$(echo "$response" | awk -F'nr_band:' '{print $2}' | awk -F',' '{print $1}' | xargs)
            nr_band_width=$(echo "$response" | awk -F'nr_band_width:' '{print $2}' | awk -F' ' '{print $1}' | xargs)
            nr_sinr=$(echo "$response" | awk -F'nr_snr:' '{print $2}' | awk '{print $1}' | xargs)
            nr_sinr=$(process_signal_value "$nr_sinr")
            nr_rsrq=$(echo "$response" | awk -F'rsrq:' '{print $2}' | xargs)
            nr_rsrq=$(process_signal_value "$nr_rsrq")
            nr_rsrp=$(echo "$response" | awk -F'rsrp:' '{print $2}' | awk '{print $1}' | xargs)
            nr_rsrp=$(process_signal_value "$nr_rsrp")
            nr_tac=$(echo "$response" | awk -F'nr_tac:' '{print $2}' | xargs)
            nr_tx_power=$(echo "$response" | awk -F'nr_tx_pwr:' '{print $2}' | xargs)
            add_plain_info_entry "Network Mode" "$network_mode" "Network Mode"
            add_plain_info_entry "MCC" "$nr_mcc" "Mobile Country Code"
            add_plain_info_entry "MNC" "$nr_mnc" "Mobile Network Code"
            add_plain_info_entry "Cell ID" "$nr_cell_id" "Cell ID"
            add_plain_info_entry "Physical Cell ID" "$nr_physical_cell_id" "Physical Cell ID"
            add_plain_info_entry "ARFCN" "$nr_earfcn" "NR Absolute Radio Frequency Channel Number"
            add_plain_info_entry "Band" "$nr_band" "Band"
            add_plain_info_entry "Bandwidth" "$nr_band_width" "Bandwidth"
            add_plain_info_entry "TAC" "$nr_tac" "Tracking area code of cell served by neighbor Enb"
            add_bar_info_entry "RSRQ" "$nr_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
            add_bar_info_entry "RSRP" "$nr_rsrp" "Reference Signal Received Power" -140 -44 dBm
            add_bar_info_entry "SINR" "$nr_sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
            add_plain_info_entry "TX Power" "$nr_tx_power" "TX Power"
            ;;
    esac
}

process_signal_value()
{
    local value="$1"
    local numbers=$(echo "$value" | grep -oE '[-+]?[0-9]+(\.[0-9]+)?')
    local count=0
    local total=0
    for num in $numbers; do
        total=$(echo "$total + $num" | bc -l)
        count=$((count+1))
    done
    if [ $count -gt 0 ]; then
        echo "scale=2; $total / $count" | bc -l | sed 's/^\./0./' | sed 's/^-\./-0./'
    else
        echo ""
    fi
}

# Temperature via AT^TEMP (manual 15.13): "TSENS: 33C"
_get_temperature()
{
    temperature=$(cmd_temp_query "$at_port" | sed -n 's/.*TSENS: \([0-9]*\)C.*/\1/p')
    [ -n "$temperature" ] && {
        add_plain_info_entry "temperature" "$temperature C" "Temperature"
    }
}

# SIM slot switch via AT+SWITCH_SLOT (manual 15.41):
#   AT+SWITCH_SLOT?  -> SIM1 ENABLE | SIM2 ENABLE
#   AT+SWITCH_SLOT=<mode>  (0=SIM1, 1=SIM2)
get_sim_switch_capabilities()
{
    json_add_string "supportSwitch" "1"
}

get_sim_slot()
{
    sim_slot=$(cmd_switch_slot_query "$at_port" | grep ENABLE | grep -o 'SIM[0-9]' | grep -o '[0-9]')
    json_add_string "sim_slot" "$sim_slot"
}

set_sim_slot()
{
    local sim_slot_param="$1"
    case "$sim_slot_param" in
        1) mode="0" ;;
        2) mode="1" ;;
        *)
            json_add_string "result" "Invalid SIM slot: $sim_slot_param"
            return 1
            ;;
    esac
    response=$(cmd_switch_slot_set "$at_port" "$mode")
    json_add_string "result" "$response"
    printf '%s\n' "$response" | grep -q '^OK' || return 1
}

# The MV32-W AT command reference only exposes IMEI *read* commands
# (AT+GSN / AT+CGSN / AT+GETIMEI); there is no NV-write based set-IMEI.
set_imei()
{
    json_select "result"
    json_add_string "set_imei" "ERROR: IMEI modification not supported on MV32-W"
    json_close_object
}

# MV32-W exposes no voltage query command (AT!PCVOLT? is not supported).
_get_voltage()
{
    return 0
}

vendor_get_disabled_features()
{
    json_add_string "" "IMEI"
    json_add_string "" "NeighborCell"
}
