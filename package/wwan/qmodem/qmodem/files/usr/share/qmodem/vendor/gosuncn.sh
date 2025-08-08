#!/bin/sh
# Copyright (C) 2025 Fujr <fjrcn@outlook.com>
_Vendor="Godsuncn"
_Author="Fujr"
_Maintainer="Fujr <fjrcn@outlook.com>"
source /usr/share/qmodem/generic.sh


function get_imei() {
    imei=$(at $at_port "AT+CGSN" | grep -o '[0-9]\{15\}')
    json_add_string imei "$imei"
}

function set_imei() {
    imei=$1
    at $at_port "AT+EGMR=1,7,\"$imei\""
}

function get_mode() {
    mode=$(at $at_port "AT+ZSWITCH?" | grep -o "+ZSWITCH: [a-zA-Z]" | cut -d' ' -f2)
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

function set_mode() {
    local mode=$1
    case $mode in
        "mbim")
            at $at_port "AT+ZSWITCH=e"
            ;;
        "rmnet")
            at $at_port "AT+ZSWITCH=x"
            ;;
        "rndis")
            at $at_port "AT+ZSWITCH=r"
            ;;
        "ecm")
            at $at_port "AT+ZSWITCH=E"
            ;;
        *)
            echo "Invalid mode"
            return 1
            ;;
    esac
}

function get_network_prefer() {
    res=$(at $at_port "AT+ZSNT?" | grep -o "+ZSNT: [0-9,]*" | cut -d' ' -f2)
    cm_mode=$(echo $res | cut -d',' -f1)
    net_sel_mode=$(echo $res | cut -d',' -f2)
    pref_acq=$(echo $res | cut -d',' -f3)

    json_add_object network_prefer
    json_add_string "cm_mode" "$cm_mode"
    json_add_string "net_sel_mode" "$net_sel_mode"
    json_add_string "pref_acq" "$pref_acq"
    json_close_object
}

function set_network_prefer() {
    config=$1
    cm_mode=$(echo $config | jq -r '.cm_mode')
    net_sel_mode=$(echo $config | jq -r '.net_sel_mode')
    pref_acq=$(echo $config | jq -r '.pref_acq')

    if [ -z "$cm_mode" ] || [ -z "$net_sel_mode" ] || [ -z "$pref_acq" ]; then
        echo "Invalid parameters"
        return 1
    fi

    at $at_port "AT+ZSNT=$cm_mode,$net_sel_mode,$pref_acq"
}

function get_lockband() {
    json_add_object "lockband"
    lte_bands=$(at $at_port "AT+ZBAND?" | grep -o "LTE: [0-9,]*" | cut -d' ' -f2)
    supported_bands=$(at $at_port "AT+ZBAND=?" | grep -o "LTE: ([0-9,]*)" | tr -d '()' | cut -d' ' -f2)

    json_add_array "available_band"
    for band in $(echo $supported_bands | tr ',' '\n'); do
        add_avalible_band_entry "$band" "LTE_Band_$band"
    done
    json_close_array

    json_add_array "lock_band"
    for band in $(echo $lte_bands | tr ',' '\n'); do
        json_add_string "" "$band"
    done
    json_close_array
    json_close_object
}

function set_lockband() {
    config=$1
    rat=$(echo $config | jq -r '.rat')
    lock_band=$(echo $config | jq -r '.lock_band')
    lock_band_number=$(echo $lock_band | tr ',' '\n' | wc -l)

    if [ "$rat" = "unlock" ]; then
        at $at_port "AT+ZBAND=0"
    else
        at $at_port "AT+ZSNT=$rat,0,0" # Ensure RAT is set before locking bands
        at $at_port "AT+ZBAND=$rat,$lock_band_number,$lock_band"
    fi
}

function sim_info() {
    class="SIM Information"
    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status=$(at $at_port $at_command | grep "+CPIN:")
    sim_status=${sim_status:7:-1}
    #lowercase
    sim_status=$(echo $sim_status | tr  A-Z a-z)
    add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
    add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"
}

function base_info() {
    class="Base Information"
    manufacturer=$(at $at_port "AT+CGMI" | sed -n '2p' | tr -d '\r')
    model=$(at $at_port "AT+CGMM" | sed -n '2p' | tr -d '\r')
    revision=$(at $at_port "AT+CGMR" | sed -n '2p' | tr -d '\r')
    add_plain_info_entry "Manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "Model" "$model" "Model"
    add_plain_info_entry "Revision" "$revision" "Revision"
    get_connect_status
}

function network_info() {
    carrier=$(at $at_port "AT+COPS?" | grep -o "\"[^\"]*\"" | tr -d '"')
    rat=$(at $at_port "AT+RAT?" | grep -o "RAT: [a-zA-Z]*" | cut -d' ' -f2)
    add_plain_info_entry "Carrier" "$carrier" "Carrier"
    add_plain_info_entry "RAT" "$rat" "Radio Access Technology"
}

function vendor_get_disabled_features() {
    json_add_string "" "LockBand"
    json_add_string "" "NeighborCell"
}

unlock_advance
