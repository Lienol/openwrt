#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>
# Copyright (C) 2025 sfwtw
_Vendor="meig"
_Author="Siriling,sfwtw"
_Maintainer="sfwtw <unkown>"
source /usr/share/qmodem/generic.sh
debug_subject="meig_ctrl"

vendor_get_disabled_features(){
    json_add_string "" "NeighborCell"
    json_add_string "" "LockBand"
}

# Return raw data   
get_imei(){
    at_command="AT+CGSN"
    imei=$(at $at_port $at_command | grep -o "[0-9]\{15\}")
    json_add_string "imei" "$imei"
}

set_imei(){
    local imei="$1"
    at_command="AT+LCTSN=1,7,\"$imei\""
    res=$(at $at_port $at_command)
    json_select "result"
    json_add_string "set_imei" "$res"
    json_close_object
    get_imei
}

# Get dial mode
get_mode()
{
    at_command='AT+SER?'
    local mode_num=$(at ${at_port} ${at_command} | grep "+SER:" | sed 's/+SER: //g' | sed 's/\r//g')
    local mode
    case "$platform" in
        "qualcomm")
            case "$mode_num" in
                "2") mode="ecm" ;;
                "3") mode="rndis" ;;
                "2") mode="ncm" ;;
                *) mode="${mode_num}" ;;
            esac
        ;;
        "lte12"|"lte")
            case "$mode_num" in
                "2") mode="ecm" ;;
                "3") mode="rndis" ;;
                "2") mode="ncm" ;;
                *) mode="${mode_num}" ;;
            esac
        ;;
        "unisoc")
            case "$mode_num" in
                "2") mode="ecm" ;;
                "3") mode="rndis" ;;
                "1") mode="ncm" ;;
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

# Set dial mode
set_mode()
{
    local mode=$1
    case "$platform" in
        "qualcomm"|"lte12"|"lte")
            case "$mode" in
                "ecm") mode_num="2" ;;
                "rndis") mode_num="3" ;;
                "ncm") mode_num="2" ;;
                *) mode_num="1" ;;
            esac
        ;;
        "unisoc")
            case "$mode" in
                "ecm") mode_num="2" ;;
                "rndis") mode_num="3" ;;
                "ncm") mode_num="1" ;;
                *) mode_num="1" ;;
            esac
        ;;
        *)
            mode_num="1"
        ;;
    esac
    at_command='AT+SER='${mode_num}',1'
    res=$(at "${at_port}" "${at_command}")
    json_select "result"
    json_add_string "set_mode" "$res"
    json_close_object
}

# Get network preference
get_network_prefer()
{
    at_command='AT^SYSCFGEX?'
    local response=$(at ${at_port} ${at_command} | grep "\^SYSCFGEX:" | sed 's/\^SYSCFGEX://g')
    local network_type_num=$(echo "$response" | awk -F'"' '{print $2}')
    
    network_prefer_2g="0"
    network_prefer_3g="0"
    network_prefer_4g="0"
    network_prefer_5g="0"
    
    local auto=$(echo "${network_type_num}" | grep "00")
    if [ -n "$auto" ]; then
        network_prefer_2g="1"
        network_prefer_3g="1"
        network_prefer_4g="1"
        network_prefer_5g="1"
    else
        local gsm=$(echo "${network_type_num}" | grep "01")
        local wcdma=$(echo "${network_type_num}" | grep "02")
        local lte=$(echo "${network_type_num}" | grep "03")
        local nr=$(echo "${network_type_num}" | grep "04")
        if [ -n "$gsm" ]; then
            network_prefer_2g="1"
        fi
        if [ -n "$wcdma" ]; then
            network_prefer_3g="1"
        fi
        if [ -n "$lte" ]; then
            network_prefer_4g="1"
        fi
        if [ -n "$nr" ]; then
            network_prefer_5g="1"
        fi
    fi
    json_add_object network_prefer
    json_add_string 2G "$network_prefer_2g"
    json_add_string 3G "$network_prefer_3g"
    json_add_string 4G "$network_prefer_4g"
    json_add_string 5G "$network_prefer_5g"
    json_close_object
}

# Set network preference
set_network_prefer()
{
    local networks=$1
    local network_prefer_config=""
    network_prefer_3g=$(echo $1 |jq -r 'contains(["3G"])')
    network_prefer_4g=$(echo $1 |jq -r 'contains(["4G"])')
    network_prefer_5g=$(echo $1 |jq -r 'contains(["5G"])')
    if [ "$network_prefer_5g" = "true" ]; then
        network_prefer_config="${network_prefer_config}04"
    fi
    if [ "$network_prefer_4g" = "true" ]; then
        network_prefer_config="${network_prefer_config}03"
    fi
    if [ "$network_prefer_3g" = "true" ]; then
        network_prefer_config="${network_prefer_config}02"
    fi
    if [ -z "$network_prefer_config" ]; then
        network_prefer_config="00"
    fi
    at_command='AT^SYSCFGEX="'${network_prefer_config}'",all,0,2,all,all,all,all,1'
    res=$(at "${at_port}" "${at_command}")
    json_select "result"
    json_add_string "set_network_prefer" "$res"
    json_close_object
}

get_voltage()
{
    # at_command="AT+CBC"
	# local voltage=$(at ${at_port} ${at_command} | grep "+CBC:" | awk -F',' '{print $3}' | sed 's/\r//g')
    [ -n "$voltage" ] && {
        add_plain_info_entry "voltage" "$voltage mV" "Voltage" 
    }
}

# Get temperature
get_temperature()
{   
    at_command="AT+TEMP"
    local response
    local temp
    local degree_symbol=$(printf "\xc2\xb0")C 

# 根据平台选择不同的AT命令并提取温度值
if [ "$platform" = "unisoc" ]; then
    response=$(at ${at_port} ${at_command} | grep 'TEMP: "soc-thmzone"' | awk -F'"' '{print $4}')
else
    response=$(at ${at_port} ${at_command} | grep 'TEMP: "cpu0-0-usr"' | awk -F'"' '{print $4}')
 fi

# 处理响应值
if [ -n "$response" ]; then
    if [ "$platform" = "unisoc" ]; then
        # Unisoc平台需要将原始值除以1000并保留两位小数
        temp_value=$(echo "scale=2; $response / 1000" | bc)
        temp="${temp_value}${degree_symbol}"
    else
        # 其他平台直接使用原始值
        temp="${response}${degree_symbol}"
    fi
else
    # 无响应时显示NaN
    temp="NaN ${degree_symbol}"
    fi
    add_plain_info_entry "temperature" "$temp" "Temperature"
}

# Basic information
base_info()
{
    m_debug  "Meig base info"

    at_command="AT+CGMM"
    name=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    at_command="AT+CGMI"
    manufacturer=$(at $at_port $at_command | sed -n '2p' | sed 's/+CGMI: //g' | sed 's/\r//g')
    at_command="AT+CGMR"
    revision=$(at $at_port $at_command | grep "+CGMR: " | awk -F': ' '{print $2}' | sed 's/\r//g')
    class="Base Information"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_temperature
    get_voltage
    get_connect_status
}

# SIM card information
sim_info()
{
    m_debug  "Meig sim info"
    
    at_command="AT^SIMSLOT?"
    response=$(at ${at_port} ${at_command} | grep "\^SIMSLOT:" | awk -F': ' '{print $2}' | awk -F',' '{print $2}')
    if [ "$response" != "0" ]; then
        sim_slot="1"
    else
        sim_slot="2"
    fi

    at_command="AT+CGSN"
    imei=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    at_command="AT+CPIN?"
    sim_status_flag=$(at $at_port $at_command | sed -n '2p')
    sim_status=$(get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    at_command="AT+COPS?"
    isp=$(at $at_port $at_command | sed -n '2p' | awk -F'"' '{print $2}')

    at_command="AT+CNUM"
    sim_number=$(at $at_port $at_command | sed -n '2p' | awk -F'"' '{print $4}')

    at_command="AT+CIMI"
    imsi=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    at_command="AT+ICCID"
    iccid=$(at $at_port $at_command | grep -o "+ICCID:[ ]*[-0-9]\+" | grep -o "[-0-9]\{1,4\}")
    class="SIM Information"
    case "$sim_status" in
        "ready")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
            add_plain_info_entry "ISP" "$isp" "Internet Service Provider"
            add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"
            add_plain_info_entry "SIM Number" "$sim_number" "SIM Number"
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity" 
            add_plain_info_entry "IMSI" "$imsi" "International Mobile Subscriber Identity" 
            add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity" 
        ;;
        "miss")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity" 
        ;;
        "unknown")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
        ;;
        *)
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
            add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot" 
            add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity" 
            add_plain_info_entry "IMSI" "$imsi" "International Mobile Subscriber Identity" 
            add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity" 
        ;;
    esac
}

# Network information
network_info()
{
    m_debug  "Meig network info"

    at_command="AT^SYSINFOEX"
    network_type=$(at ${at_port} ${at_command} | grep "\^SYSINFOEX:" | awk -F'"' '{print $4}')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(at ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }

    at_command="AT+CSQ"
    response=$(at ${at_port} ${at_command} | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    at_command="AT^DSAMBR=${define_connect:-1}"
    response=$(at $at_port $at_command | grep "\^DSAMBR:" | awk -F': ' '{print $2}')
    
    ambr_ul_tmp="0"
    ambr_dl_tmp="0"
    
    if [ -n "$response" ]; then
        case "$network_type" in
            "LTE")
                ambr_ul_tmp=$(echo "$response" | awk -F',' '{for(i=1;i<=NF-2;i+=2){if($i!="0")tmp=$i};if(tmp=="")tmp=0;print tmp}')
                ambr_dl_tmp=$(echo "$response" | awk -F',' '{for(i=2;i<=NF-2;i+=2){if($i!="0")tmp=$i};if(tmp=="")tmp=0;print tmp}')
            ;;
            "NR")
                ambr_ul_tmp=$(echo "$response" | awk -F',' '{print (NF>=9)?$9:"0"}')
                ambr_dl_tmp=$(echo "$response" | awk -F',' '{print (NF>=10)?$10:"0"}' | sed 's/\r//g')
            ;;
            *)
                ambr_ul_tmp=$(echo "$response" | awk -F',' '{for(i=1;i<=NF-2;i+=2){if($i!="0")tmp=$i};if(tmp=="")tmp=0;print tmp}')
                ambr_dl_tmp=$(echo "$response" | awk -F',' '{for(i=2;i<=NF-2;i+=2){if($i!="0")tmp=$i};if(tmp=="")tmp=0;print tmp}')
            ;;
        esac
    fi

    [ -z "$ambr_ul_tmp" ] || [ "$ambr_ul_tmp" = "0" ] || ! echo "$ambr_ul_tmp" | grep -q '^[0-9.]*$' && ambr_ul_tmp="0"
    [ -z "$ambr_dl_tmp" ] || [ "$ambr_dl_tmp" = "0" ] || ! echo "$ambr_dl_tmp" | grep -q '^[0-9.]*$' && ambr_dl_tmp="0"
    
    if [ "$ambr_ul_tmp" = "0" ]; then
        ambr_ul="0"
    else
        ambr_ul=$(awk "BEGIN{ printf \"%.2f\", $ambr_ul_tmp / 1024 }" 2>/dev/null || echo "0")
        ambr_ul=$(echo "$ambr_ul" | sed 's/\.*0*$//')
        [ -z "$ambr_ul" ] && ambr_ul="0"
    fi
    
    if [ "$ambr_dl_tmp" = "0" ]; then
        ambr_dl="0"
    else
        ambr_dl=$(awk "BEGIN{ printf \"%.2f\", $ambr_dl_tmp / 1024 }" 2>/dev/null || echo "0")
        ambr_dl=$(echo "$ambr_dl" | sed 's/\.*0*$//')
        [ -z "$ambr_dl" ] && ambr_dl="0"
    fi

    at_command='AT^DSFLOWQRY'
    response=$(at $at_port $at_command | grep "\^DSFLOWRPT:" | sed 's/\^DSFLOWRPT: //g' | sed 's/\r//g')
    
    tx_rate="0"
    rx_rate="0"
    
    if [ -n "$response" ]; then
        tx_rate=$(echo $response | awk -F',' '{print (NF>=1)?$1:"0"}')
        rx_rate=$(echo $response | awk -F',' '{print (NF>=2)?$2:"0"}')
    fi
    
    [ -z "$tx_rate" ] || ! echo "$tx_rate" | grep -q '^[0-9]*$' && tx_rate="0"
    [ -z "$rx_rate" ] || ! echo "$rx_rate" | grep -q '^[0-9]*$' && rx_rate="0"
    
    class="Network Information"
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
    add_plain_info_entry "AMBR UL" "$ambr_ul" "Access Maximum Bit Rate for Uplink"
    add_plain_info_entry "AMBR DL" "$ambr_dl" "Access Maximum Bit Rate for Downlink"
    add_speed_entry rx $rx_rate
    add_speed_entry tx $tx_rate
}

# Cell information
cell_info()
{
    m_debug  "Meig cell info"

    at_command="AT^CELLINFO=${define_connect:-1}"
    response=$(at $at_port $at_command | grep "\^CELLINFO:" | sed 's/\^CELLINFO://')
    
    local rat=""
    network_mode="Unknown Mode"

    [ -n "$response" ] && {
        rat=$(echo "$response" | awk -F',' '{print $1}' | tr -d ' ')
    }
    
    case $rat in
        "5G")
            network_mode="NR5G-SA Mode"
            nr_duplex_mode=$(echo "$response" | awk -F',' '{print $2}' | tr -d ' ')
            nr_mcc=$(echo "$response" | awk -F',' '{print $3}' | tr -d ' ')
            nr_mnc=$(echo "$response" | awk -F',' '{print $4}' | tr -d ' ')
            nr_cell_id=$(echo "$response" | awk -F',' '{print $5}' | tr -d ' ')
            nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}' | tr -d ' ')
            nr_tac=$(echo "$response" | awk -F',' '{print $7}' | tr -d ' ')
            nr_band_num=$(echo "$response" | awk -F',' '{print $8}' | tr -d ' ')
            nr_band=$(get_band "NR" "$nr_band_num")
            nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $9}' | tr -d ' ')
            nr_dl_bandwidth=$(get_bandwidth "NR" "$nr_dl_bandwidth_num")
            nr_scs=$(echo "$response" | awk -F',' '{print $10}' | tr -d ' ')
            nr_rsrp=$(echo "$response" | awk -F',' '{print $15}' | tr -d ' ')
            nr_rsrq=$(echo "$response" | awk -F',' '{print $16}' | tr -d ' ')
            nr_sinr_num=$(echo "$response" | awk -F',' '{print $17}' | tr -d ' ')
            
            if [ -n "$nr_sinr_num" ] && echo "$nr_sinr_num" | grep -q '^[0-9.-]*$'; then
                nr_sinr=$(awk "BEGIN{ print $nr_sinr_num / 10 }" 2>/dev/null || echo "0")
            else
                nr_sinr="0"
            fi
        ;;
        "LTE-NR")
            network_mode="EN-DC Mode"
            endc_lte_duplex_mode=$(echo "$response" | awk -F',' '{print $2}' | tr -d ' ')
            endc_lte_mcc=$(echo "$response" | awk -F',' '{print $3}' | tr -d ' ')
            endc_lte_mnc=$(echo "$response" | awk -F',' '{print $4}' | tr -d ' ')
            endc_lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}' | tr -d ' ')
            endc_lte_cell_id=$(echo "$response" | awk -F',' '{print $8}' | tr -d ' ')
            endc_lte_tac=$(echo "$response" | awk -F',' '{print $9}' | tr -d ' ')
            endc_lte_band_num=$(echo "$response" | awk -F',' '{print $10}' | tr -d ' ')
            endc_lte_band=$(get_band "LTE" "$endc_lte_band_num")
            ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $11}' | tr -d ' ')
            endc_lte_ul_bandwidth=$(get_bandwidth "LTE" "$ul_bandwidth_num")
            endc_lte_dl_bandwidth="$endc_lte_ul_bandwidth"
            endc_lte_rsrp=$(echo "$response" | awk -F',' '{print $15}' | tr -d ' ')
            endc_lte_rsrq=$(echo "$response" | awk -F',' '{print $16}' | tr -d ' ')
            endc_lte_sinr_num=$(echo "$response" | awk -F',' '{print $17}' | tr -d ' ')
            
            if [ -n "$endc_lte_sinr_num" ] && echo "$endc_lte_sinr_num" | grep -q '^[0-9.-]*$'; then
                endc_lte_sinr=$(awk "BEGIN{ print $endc_lte_sinr_num / 10 }" 2>/dev/null || echo "0")
            else
                endc_lte_sinr="0"
            fi
            
            endc_lte_tx_power=$(echo "$response" | awk -F',' '{print $22}' | tr -d ' ')
            endc_nr_mcc="$endc_lte_mcc"
            endc_nr_mnc="$endc_lte_mnc"
            field_count=$(echo "$response" | awk -F',' '{print NF}')
            
            if [ "$field_count" -ge 30 ]; then
                endc_nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $30}' | tr -d ' ')
            else
                endc_nr_physical_cell_id=""
            fi
            
            if [ "$field_count" -ge 31 ]; then
                endc_nr_rsrp=$(echo "$response" | awk -F',' '{print $30}' | tr -d ' ')
            else
                endc_nr_rsrp=""
            fi
            
            if [ "$field_count" -ge 32 ]; then
                endc_nr_rsrq=$(echo "$response" | awk -F',' '{print $31}' | tr -d ' ')
            else
                endc_nr_rsrq=""
            fi
            
            if [ "$field_count" -ge 33 ]; then
                endc_nr_sinr_num=$(echo "$response" | awk -F',' '{print $32}' | tr -d ' ')
                if [ -n "$endc_nr_sinr_num" ] && echo "$endc_nr_sinr_num" | grep -q '^[0-9.-]*$'; then
                    endc_nr_sinr=$(awk "BEGIN{ print $endc_nr_sinr_num / 10 }" 2>/dev/null || echo "0")
                else
                    endc_nr_sinr="0"
                fi
            else
                endc_nr_sinr="0"
            fi
            
            if [ "$field_count" -ge 34 ]; then
                endc_nr_band_num=$(echo "$response" | awk -F',' '{print $33}' | tr -d ' ')
                endc_nr_band=$(get_band "NR" "$endc_nr_band_num")
            else
                endc_nr_band=""
            fi
            
            if [ "$field_count" -ge 36 ]; then
                nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $35}' | tr -d ' ')
                endc_nr_dl_bandwidth=$(get_bandwidth "NR" "$nr_dl_bandwidth_num")
            else
                endc_nr_dl_bandwidth=""
            fi
            
            if [ "$field_count" -ge 38 ]; then
                endc_nr_scs=$(echo "$response" | awk -F',' '{print $37}' | tr -d ' \r')
            else
                endc_nr_scs=""
            fi
        ;;
        "LTE"|"eMTC"|"NB-IoT")
            network_mode="LTE Mode"
            lte_duplex_mode=$(echo "$response" | awk -F',' '{print $2}' | tr -d ' ')
            lte_mcc=$(echo "$response" | awk -F',' '{print $3}' | tr -d ' ')
            lte_mnc=$(echo "$response" | awk -F',' '{print $4}' | tr -d ' ')
            lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}' | tr -d ' ')
            lte_cell_id=$(echo "$response" | awk -F',' '{print $8}' | tr -d ' ')
            lte_tac=$(echo "$response" | awk -F',' '{print $9}' | tr -d ' ')
            lte_band_num=$(echo "$response" | awk -F',' '{print $10}' | tr -d ' ')
            lte_band=$(get_band "LTE" "$lte_band_num")
            ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $11}' | tr -d ' ')
            lte_ul_bandwidth=$(get_bandwidth "LTE" "$ul_bandwidth_num")
            lte_dl_bandwidth="$lte_ul_bandwidth"
            lte_rsrp=$(echo "$response" | awk -F',' '{print $15}' | tr -d ' ')
            lte_rsrq=$(echo "$response" | awk -F',' '{print $16}' | tr -d ' ')
            lte_sinr_num=$(echo "$response" | awk -F',' '{print $17}' | tr -d ' ')
            
            if [ -n "$lte_sinr_num" ] && echo "$lte_sinr_num" | grep -q '^[0-9.-]*$'; then
                lte_sinr=$(awk "BEGIN{ print $lte_sinr_num / 10 }" 2>/dev/null || echo "0")
            else
                lte_sinr="0"
            fi
            
            field_count=$(echo "$response" | awk -F',' '{print NF}')
            if [ "$field_count" -ge 23 ]; then
                lte_tx_power=$(echo "$response" | awk -F',' '{print $22}' | tr -d ' ')
            else
                lte_tx_power=""
            fi
        ;;
        "WCDMA"|"UMTS")
            network_mode="WCDMA Mode"
            wcdma_mcc=$(echo "$response" | awk -F',' '{print $2}' | tr -d ' ')
            wcdma_mnc=$(echo "$response" | awk -F',' '{print $3}' | tr -d ' ')
            wcdma_psc=$(echo "$response" | awk -F',' '{print $5}' | tr -d ' ')
            wcdma_cell_id=$(echo "$response" | awk -F',' '{print $7}' | tr -d ' ')
            wcdma_lac=$(echo "$response" | awk -F',' '{print $8}' | tr -d ' ')
            wcdma_band_num=$(echo "$response" | awk -F',' '{print $9}' | tr -d ' ')
            wcdma_band=$(get_band "WCDMA" "$wcdma_band_num")
            
            field_count=$(echo "$response" | awk -F',' '{print NF}')
            if [ "$field_count" -ge 14 ]; then
                wcdma_ecio=$(echo "$response" | awk -F',' '{print $13}' | tr -d ' ')
            else
                wcdma_ecio=""
            fi
            
            if [ "$field_count" -ge 16 ]; then
                wcdma_rscp=$(echo "$response" | awk -F',' '{print $15}' | tr -d ' \r')
            else
                wcdma_rscp=""
            fi
        ;;
    esac
    
    class="Cell Information"
    add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
    case $network_mode in
    "NR5G-SA Mode")
        add_plain_info_entry "MMC" "$nr_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$nr_mnc" "Mobile Network Code"
        add_plain_info_entry "Duplex Mode" "$nr_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$nr_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$nr_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "TAC" "$nr_tac" "Tracking area code"
        add_plain_info_entry "Band" "$nr_band" "Band"
        add_plain_info_entry "DL Bandwidth" "$nr_dl_bandwidth" "DL Bandwidth"
        add_bar_info_entry "RSRP" "$nr_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$nr_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "SINR" "$nr_sinr" "Signal to Interference plus Noise Ratio" 0 30 dB
        add_plain_info_entry "SCS" "$nr_scs" "SCS"
        ;;
    "EN-DC Mode")
        add_plain_info_entry "LTE" "LTE" ""
        add_plain_info_entry "MCC" "$endc_lte_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$endc_lte_mnc" "Mobile Network Code"
        add_plain_info_entry "Duplex Mode" "$endc_lte_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$endc_lte_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$endc_lte_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "TAC" "$endc_lte_tac" "Tracking area code"
        add_plain_info_entry "Band" "$endc_lte_band" "Band"
        add_plain_info_entry "UL Bandwidth" "$endc_lte_ul_bandwidth" "UL Bandwidth"
        add_plain_info_entry "DL Bandwidth" "$endc_lte_dl_bandwidth" "DL Bandwidth"
        add_bar_info_entry "RSRP" "$endc_lte_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$endc_lte_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "SINR" "$endc_lte_sinr" "Signal to Interference plus Noise Ratio" 0 30 dB
        add_plain_info_entry "TX Power" "$endc_lte_tx_power" "TX Power"
        if [ -n "$endc_nr_physical_cell_id" ] || [ -n "$endc_nr_band" ]; then
            add_plain_info_entry "NR5G-NSA" "NR5G-NSA" ""
            add_plain_info_entry "MCC" "$endc_nr_mcc" "Mobile Country Code"
            add_plain_info_entry "MNC" "$endc_nr_mnc" "Mobile Network Code"
            [ -n "$endc_nr_physical_cell_id" ] && add_plain_info_entry "Physical Cell ID" "$endc_nr_physical_cell_id" "Physical Cell ID"
            [ -n "$endc_nr_band" ] && add_plain_info_entry "Band" "$endc_nr_band" "Band"
            [ -n "$endc_nr_dl_bandwidth" ] && add_plain_info_entry "DL Bandwidth" "$endc_nr_dl_bandwidth" "DL Bandwidth"
            [ -n "$endc_nr_rsrp" ] && add_bar_info_entry "RSRP" "$endc_nr_rsrp" "Reference Signal Received Power" -140 -44 dBm
            [ -n "$endc_nr_rsrq" ] && add_bar_info_entry "RSRQ" "$endc_nr_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
            [ -n "$endc_nr_sinr" ] && add_bar_info_entry "SINR" "$endc_nr_sinr" "Signal to Interference plus Noise Ratio" 0 30 dB
            [ -n "$endc_nr_scs" ] && add_plain_info_entry "SCS" "$endc_nr_scs" "SCS"
        fi
        ;;
    "LTE Mode")
        add_plain_info_entry "MCC" "$lte_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$lte_mnc" "Mobile Network Code"
        add_plain_info_entry "Duplex Mode" "$lte_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$lte_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$lte_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "TAC" "$lte_tac" "Tracking area code"
        add_plain_info_entry "Band" "$lte_band" "Band"
        add_plain_info_entry "UL Bandwidth" "$lte_ul_bandwidth" "UL Bandwidth"
        add_plain_info_entry "DL Bandwidth" "$lte_dl_bandwidth" "DL Bandwidth"
        add_bar_info_entry "RSRP" "$lte_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$lte_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "SINR" "$lte_sinr" "Signal to Interference plus Noise Ratio" 0 30 dB
        [ -n "$lte_tx_power" ] && add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power"
        ;;
    "WCDMA Mode")
        add_plain_info_entry "MCC" "$wcdma_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$wcdma_mnc" "Mobile Network Code"
        add_plain_info_entry "LAC" "$wcdma_lac" "Location Area Code"
        add_plain_info_entry "Cell ID" "$wcdma_cell_id" "Cell ID"
        add_plain_info_entry "PSC" "$wcdma_psc" "Primary Scrambling Code"
        add_plain_info_entry "Band" "$wcdma_band" "Band"
        [ -n "$wcdma_rscp" ] && add_bar_info_entry "RSCP" "$wcdma_rscp" "Received Signal Code Power" -120 -25 dBm
        [ -n "$wcdma_ecio" ] && add_plain_info_entry "Ec/Io" "$wcdma_ecio" "Ec/Io"
        ;;
    esac
}

get_band()
{
    local network_type="$1"
    local band_num="$2"
    local band="0"
    
    if [ -z "$band_num" ] || ! echo "$band_num" | grep -q '^[0-9]*$'; then
        band="0"
    else
        case $network_type in
            "WCDMA"|"LTE"|"NR") band="$band_num" ;;
            *) band="0" ;;
        esac
    fi
    
    echo "$band"
}

get_bandwidth()
{
    local network_type="$1"
    local bandwidth_num="$2"
    local bandwidth="0"
    
    if [ -z "$bandwidth_num" ] || ! echo "$bandwidth_num" | grep -q '^[0-9]*$'; then
        bandwidth="0"
    else
        case $network_type in
            "LTE") 
                if [ "$bandwidth_num" -gt 0 ]; then
                    bandwidth=$((bandwidth_num / 5))
                fi
                ;;
            "NR") bandwidth="$bandwidth_num" ;;
            *) bandwidth="0" ;;
        esac
    fi
    
    echo "$bandwidth"
}
