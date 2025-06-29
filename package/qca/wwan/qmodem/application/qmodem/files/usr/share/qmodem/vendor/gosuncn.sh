#!/bin/sh
# Copyright (C) 2025 Fujr <fjrcn@outlook.com>
_Vendor="Gosuncn"
_Author="Fujr"
_Maintainer="Fujr <fjrcn@outlook.com>"
source /usr/share/qmodem/generic.sh
debug_subject="gosuncn_ctrl"

#获取LTE带宽
# $1:带宽数字
get_lte_bw() {
    local bw_num="$1"
    local bw
    case "$bw_num" in
        "0") bw="1.4" ;;
        "1") bw="3" ;;
        "2"|"3"|"4"|"5") bw="$(((bw_num - 1) * 5))" ;;
        *) bw="" ;;
    esac
    echo "$bw"
}

#将十六进制频段掩码转换为频段号列表
convert2band()
{
    local hex_band="$1"
    local hex=$(echo "$hex_band" | grep -o "[0-9A-Fa-f]\{1,16\}" | tr 'a-f' 'A-F')
    if [ -z "$hex" ]; then
        return
    fi
    local band_list=""
    local bin=$(echo "ibase=16;obase=2;$hex" | bc)
    local len=${#bin}
    local i
    for i in $(seq 1 ${#bin}); do
        if [ "${bin:$((i-1)):1}" = "1" ]; then
            band_list="$band_list $((len - i + 1))"
        fi
    done
    echo "$band_list" | tr ' ' '\n' | sort -n | tr '\n' ' '
}

#将频段号列表转换为十六进制掩码
convert2hex()
{
    local band_list="$1"
    band_list=$(echo "$band_list" | tr ',' '\n' | sort -n | uniq)
    local hex="0"
    local band
    for band in $band_list; do
        local add_hex=$(echo "obase=16;2^($band - 1)" | bc)
        hex=$(echo "obase=16;ibase=16;$hex + $add_hex" | bc)
    done
    if [ -n "$hex" ]; then
        echo "$hex"
    fi
}

get_imei(){
    imei=$(at $at_port "AT+CGSN" | grep -o '[0-9]\{15\}')
    json_add_string imei "$imei"
}

set_imei(){
    local imei="$1"
    at $at_port "AT+EGMR=1,7,\"$imei\""
}

#获取拨号模式
get_mode()
{
    case "$platform" in
        "qualcomm")
            local mode_raw=$(at $at_port "AT+ZSWITCH?" | grep -o "+ZSWITCH: [a-zA-Z]" | cut -d' ' -f2)
            case "$mode_raw" in
                "e") mode="mbim" ;;
                "x") mode="rmnet" ;;
                "r") mode="rndis" ;;
                "E") mode="ecm" ;;
                *) mode="$mode_raw" ;;
            esac
        ;;
        "lte")
            local mode_raw=$(at $at_port "AT+ZSWITCH?" | grep -o "+ZSWITCH: [a-zA-Z]" | cut -d' ' -f2)
            case "$mode_raw" in
                "e") mode="mbim" ;;
                "x") mode="rmnet" ;;
                "r") mode="rndis" ;;
                "l") mode="ecm" ;;
                *) mode="$mode_raw" ;;
            esac
        ;;
        *)
            local mode_raw=$(at $at_port "AT+ZSWITCH?" | grep -o "+ZSWITCH: [a-zA-Z]" | cut -d' ' -f2)
            case "$mode_raw" in
                "e") mode="mbim" ;;
                "x") mode="rmnet" ;;
                "r") mode="rndis" ;;
                "E") mode="ecm" ;;
                *) mode="$mode_raw" ;;
            esac
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

#设置拨号模式
set_mode()
{
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

#获取网络偏好
get_network_prefer()
{
    case "$platform" in
        "qualcomm")
            get_network_prefer_qualcomm
        ;;
        "lte")
            get_network_prefer_lte
        ;;
        *)
            get_network_prefer_lte
        ;;
    esac
}

get_network_prefer_lte()
{
    # AT+ZSNT? 返回格式: +ZSNT: cm_mode,net_sel_mode,pref_acq
    # cm_mode: 0=自动, 2=WCDMA, 6=LTE
    local res=$(at $at_port "AT+ZSNT?" | grep -o "+ZSNT: [0-9,]*" | cut -d' ' -f2)
    local cm_mode=$(echo $res | cut -d',' -f1)

    network_prefer_3g="0"
    network_prefer_4g="0"

    case "$cm_mode" in
        "0") network_prefer_3g="1"; network_prefer_4g="1" ;;
        "2") network_prefer_3g="1" ;;
        "6") network_prefer_4g="1" ;;
    esac

    json_add_object network_prefer
    json_add_string 3G "$network_prefer_3g"
    json_add_string 4G "$network_prefer_4g"
    json_close_object
}

get_network_prefer_qualcomm()
{
    local res=$(at $at_port "AT+ZSNT?" | grep -o "+ZSNT: [0-9,]*" | cut -d' ' -f2)
    local cm_mode=$(echo $res | cut -d',' -f1)

    network_prefer_3g="0"
    network_prefer_4g="0"
    network_prefer_5g="0"

    case "$cm_mode" in
        "0") network_prefer_3g="1"; network_prefer_4g="1"; network_prefer_5g="1" ;;
        "2") network_prefer_3g="1" ;;
        "6") network_prefer_4g="1" ;;
    esac

    json_add_object network_prefer
    json_add_string 3G "$network_prefer_3g"
    json_add_string 4G "$network_prefer_4g"
    json_add_string 5G "$network_prefer_5g"
    json_close_object
}

#设置网络偏好
set_network_prefer()
{
    network_prefer_3g=$(echo $1 | jq -r 'contains(["3G"])')
    network_prefer_4g=$(echo $1 | jq -r 'contains(["4G"])')
    network_prefer_5g=$(echo $1 | jq -r 'contains(["5G"])')
    local length=$(echo $1 | jq -r 'length')

    case "$platform" in
        "qualcomm")
            set_network_prefer_qualcomm "$length"
        ;;
        "lte")
            set_network_prefer_lte "$length"
        ;;
        *)
            set_network_prefer_lte "$length"
        ;;
    esac
}

set_network_prefer_lte()
{
    local length="$1"
    local zsnt_mode

    case "$length" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                zsnt_mode="2,0,0"
            elif [ "$network_prefer_4g" = "true" ]; then
                zsnt_mode="6,0,0"
            fi
            ;;
        "2")
            zsnt_mode="0,0,0"
            ;;
        *)
            zsnt_mode="0,0,0"
            ;;
    esac

    at $at_port "AT+ZSNT=$zsnt_mode"
}

set_network_prefer_qualcomm()
{
    local length="$1"
    local zsnt_mode

    case "$length" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                zsnt_mode="2,0,0"
            elif [ "$network_prefer_4g" = "true" ]; then
                zsnt_mode="6,0,0"
            fi
            ;;
        *)
            zsnt_mode="0,0,0"
            ;;
    esac

    at $at_port "AT+ZSNT=$zsnt_mode"
}

#获取温度
get_temperature()
{
    local temp=$(at $at_port "AT+MTSM=1" | grep '+MTSM:' | cut -d: -f2 | tr -d ' \r')
    if [ -n "$temp" ]; then
        temp="${temp}$(printf "\xc2\xb0")C"
    fi
    add_plain_info_entry "temperature" "$temp" "Temperature"
}

#获取锁频信息
get_lockband()
{
    json_add_object "lockband"
    case "$platform" in
        "qualcomm")
            get_lockband_qualcomm
        ;;
        "lte")
            get_lockband_lte
        ;;
        *)
            get_lockband_lte
        ;;
    esac
    json_close_object
}

get_lockband_lte()
{
    m_debug "Gosuncn LTE get lockband info"
    # AT+ZBAND? 返回当前锁定的LTE频段
    # AT+ZBAND=? 返回支持的LTE频段
    local modem_info=$(at $at_port 'AT+ZBAND?' | grep -i 'LTE' | cut -d: -f2 | tr -d '\r ')
    local LTE_LOCK_SUPPORTBAND=$(at $at_port 'AT+ZBAND=?' | grep -i 'LTE' | cut -d: -f2 | tr -d '() \r')

    local lte_avalible_band=""
    [ -n "$(uci -q get qmodem.$config_section.lte_band)" ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')

    json_add_object "LTE"
    json_add_array "available_band"
    if [ -n "$lte_avalible_band" ]; then
        for band in $(echo "$lte_avalible_band" | tr ',' '\n' | sort -n | uniq); do
            add_avalible_band_entry "$band" "LTE_B$band"
        done
    elif [ -n "$LTE_LOCK_SUPPORTBAND" ]; then
        for band in $(echo "$LTE_LOCK_SUPPORTBAND" | tr ',' '\n' | sort -n | uniq); do
            add_avalible_band_entry "$band" "LTE_B$band"
        done
    fi
    json_close_array

    json_add_array "lock_band"
    if [ -n "$modem_info" ]; then
        for band in $(echo "$modem_info" | tr ',' '\n' | sort -n | uniq); do
            json_add_string "" "$band"
        done
    fi
    json_close_array
    json_close_object
}

get_lockband_qualcomm()
{
    m_debug "Gosuncn qualcomm get lockband info"
    local modem_info=$(at $at_port 'AT+ZBAND?' | grep -i 'LTE' | cut -d: -f2 | tr -d '\r ')
    local LTE_LOCK_SUPPORTBAND=$(at $at_port 'AT+ZBAND=?' | grep -i 'LTE' | cut -d: -f2 | tr -d '() \r')

    local lte_avalible_band=""
    [ -n "$(uci -q get qmodem.$config_section.lte_band)" ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')

    json_add_object "LTE"
    json_add_array "available_band"
    if [ -n "$lte_avalible_band" ]; then
        for band in $(echo "$lte_avalible_band" | tr ',' '\n' | sort -n | uniq); do
            add_avalible_band_entry "$band" "LTE_B$band"
        done
    elif [ -n "$LTE_LOCK_SUPPORTBAND" ]; then
        for band in $(echo "$LTE_LOCK_SUPPORTBAND" | tr ',' '\n' | sort -n | uniq); do
            add_avalible_band_entry "$band" "LTE_B$band"
        done
    fi
    json_close_array

    json_add_array "lock_band"
    if [ -n "$modem_info" ]; then
        for band in $(echo "$modem_info" | tr ',' '\n' | sort -n | uniq); do
            json_add_string "" "$band"
        done
    fi
    json_close_array
    json_close_object
}

#设置锁频
set_lockband()
{
    m_debug "Gosuncn set lockband info"
    local config="$1"
    local band_class=$(echo "$config" | jq -r '.band_class')
    local lock_band=$(echo "$config" | jq -r '.lock_band')

    case "$platform" in
        "qualcomm")
            set_lockband_qualcomm "$band_class" "$lock_band"
        ;;
        "lte")
            set_lockband_lte "$band_class" "$lock_band"
        ;;
        *)
            set_lockband_lte "$band_class" "$lock_band"
        ;;
    esac

    json_select "result"
    json_add_string "set_lockband" "$res"
    json_add_string "config" "$config"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$lock_band"
    json_close_object
}

set_lockband_lte()
{
    local band_class="$1"
    local lock_band="$2"

    if [ -z "$lock_band" ] || [ "$lock_band" = "null" ]; then
        # 解锁所有频段
        res=$(at $at_port "AT+ZBAND=all,all,all,all")
    else
        local hex=$(convert2hex "$lock_band")
        m_debug "Lock LTE band hex: $hex"
        res=$(at $at_port "AT+ZBAND=all,all,all,${hex}")
    fi
}

set_lockband_qualcomm()
{
    local band_class="$1"
    local lock_band="$2"

    if [ -z "$lock_band" ] || [ "$lock_band" = "null" ]; then
        res=$(at $at_port "AT+ZBAND=all,all,all,all")
    else
        local hex=$(convert2hex "$lock_band")
        m_debug "Lock LTE band hex: $hex"
        res=$(at $at_port "AT+ZBAND=all,all,all,${hex}")
    fi
}

#SIM卡信息
sim_info()
{
    m_debug "Gosuncn sim info"
    class="SIM Information"

    #IMEI
    at_command="AT+CGSN"
    imei=$(at $at_port $at_command | grep -o "[0-9]\{15\}")

    #SIM Status
    at_command="AT+CPIN?"
    sim_status_flag=$(at $at_port $at_command | sed -n '2p')
    sim_status=$(get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        add_plain_info_entry "SIM Status" "$sim_status" "SIM Status"
        add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity"
        return
    fi

    #ISP
    at $at_port "AT+COPS=3,2" > /dev/null 2>&1
    at_command="AT+COPS?"
    isp=$(at $at_port $at_command | sed -n '2p' | awk -F'"' '{print $2}')

    #SIM Number
    at_command="AT+CNUM"
    sim_number=$(at $at_port $at_command | grep "+CNUM:" | grep -o "[0-9]\{9,\}")

    #IMSI
    at_command="AT+CIMI"
    imsi=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #ICCID
    at_command="AT+ICCID"
    iccid=$(at $at_port $at_command | grep -o "+ICCID:[ ]*[-0-9A-Fa-f]\+" | awk -F': ' '{print $2}' | tr -d ' ')

    add_plain_info_entry "SIM Status" "$sim_status" "SIM Status"
    add_plain_info_entry "ISP" "$isp" "Internet Service Provider"
    add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"
    add_plain_info_entry "SIM Number" "$sim_number" "SIM Number"
    add_plain_info_entry "IMEI" "$imei" "International Mobile Equipment Identity"
    add_plain_info_entry "IMSI" "$imsi" "International Mobile Subscriber Identity"
    add_plain_info_entry "ICCID" "$iccid" "Integrate Circuit Card Identity"
}

#基本信息
base_info()
{
    m_debug "Gosuncn base info"
    class="Base Information"

    #Name
    at_command="AT+CGMM"
    name=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #Manufacturer
    at_command="AT+CGMI"
    manufacturer=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #Revision
    at_command="AT+CGMR"
    revision=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    add_plain_info_entry "name" "$name" "Name"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_temperature
    get_connect_status
}

#网络信息
network_info()
{
    m_debug "Gosuncn network info"

    #Network Type（网络类型）
    at_command="AT+COPS?"
    local cops_response=$(at $at_port $at_command | grep "+COPS:")
    local carrier=$(echo "$cops_response" | awk -F'"' '{print $2}')
    local rat_num=$(echo "$cops_response" | awk -F',' '{print $4}' | sed 's/\r//g')
    local network_type=$(get_rat $rat_num)

    #CSQ
    at_command="AT+CSQ"
    response=$(at $at_port $at_command | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    class="Network Information"
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
    add_plain_info_entry "Carrier" "$carrier" "Carrier"
}

#小区信息
cell_info()
{
    m_debug "Gosuncn cell info"

    case "$platform" in
        "qualcomm")
            cell_info_qualcomm
        ;;
        "lte")
            cell_info_lte
        ;;
        *)
            cell_info_lte
        ;;
    esac
}

cell_info_lte()
{
    # AT+ZCELLINFO? 返回 +ZCELLINFO: <TAC>,cellid:<CellID>,pci:<PCI>,band:<Band>
    local zcellinfo=$(at $at_port "AT+ZCELLINFO?" | grep '+ZCELLINFO:' | cut -d: -f2-)
    local cops_response=$(at $at_port "AT+COPS?" | grep "+COPS:")
    local rat_num=$(echo "$cops_response" | awk -F',' '{print $4}' | sed 's/\r//g')
    local network_type=$(get_rat $rat_num)

    if [ -z "$zcellinfo" ]; then
        return
    fi

    # 解析 ZCELLINFO 字段
    local tac=$(echo "$zcellinfo" | cut -d',' -f1 | tr -d ' ')
    local cell_id=$(echo "$zcellinfo" | cut -d',' -f2 | tr -d ' ')
    local pci=$(echo "$zcellinfo" | cut -d',' -f3 | tr -d ' ')
    local lband=$(echo "$zcellinfo" | cut -d',' -f4 | tr -d '\r' | tr -d '\n')

    # 获取信号质量
    local cesq_response=$(at $at_port "AT+CESQ" | grep "+CESQ:")
    local rsrp="" rsrq="" sinr=""
    if [ -n "$cesq_response" ]; then
        # +CESQ: rxlev,ber,rscp,ecno,rsrq,rsrp
        rsrq=$(echo "$cesq_response" | awk -F',' '{print $5}' | tr -d ' ')
        rsrp=$(echo "$cesq_response" | awk -F',' '{print $6}' | tr -d ' \r')
        # 转换 RSRP: 实际值 = 报告值 - 141
        if [ -n "$rsrp" ] && [ "$rsrp" != "255" ]; then
            rsrp=$(($rsrp - 141))
        else
            rsrp=""
        fi
        # 转换 RSRQ: 实际值 = (报告值 / 2) - 19.5
        if [ -n "$rsrq" ] && [ "$rsrq" != "255" ]; then
            rsrq=$(echo "$rsrq" | awk '{printf "%.1f", ($1 / 2) - 19.5}')
        else
            rsrq=""
        fi
    fi

    # 获取 RSSI/SINR（通过CSQ）
    local csq_response=$(at $at_port "AT+CSQ" | grep "+CSQ:")
    local rssi=""
    if [ -n "$csq_response" ]; then
        local csq_num=$(echo "$csq_response" | awk -F'[:,]' '{print $2}' | tr -d ' ')
        if [ "$csq_num" != "99" ] && [ -n "$csq_num" ]; then
            rssi="$((2 * csq_num - 113))"
        fi
    fi

    # 获取MCC/MNC
    at $at_port "AT+COPS=3,2" > /dev/null 2>&1
    local cops_num=$(at $at_port "AT+COPS?" | grep "+COPS:" | awk -F'"' '{print $2}')
    local mcc="" mnc=""
    if [ -n "$cops_num" ] && [ ${#cops_num} -ge 5 ]; then
        mcc=${cops_num:0:3}
        mnc=${cops_num:3}
    fi

    class="Cell Information"
    case "$network_type" in
        "LTE")
            network_mode="LTE Mode"
            add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
            set_4g_cell_info "$mcc" "$mnc" "$tac" "$cell_id" "" "$pci" "$lband" "" "" "$rsrp" "$rsrq" "" "" ""
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            ;;
        "WCDMA")
            network_mode="WCDMA Mode"
            add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
            add_plain_info_entry "LAC" "$tac" "Location Area Code"
            add_plain_info_entry "Cell ID" "$cell_id" "Cell ID"
            add_plain_info_entry "PSC" "$pci" "Primary Scrambling Code"
            add_plain_info_entry "Band" "$lband" "Band"
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            ;;
        *)
            network_mode="${network_type} Mode"
            add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
            add_plain_info_entry "TAC" "$tac" "Tracking Area Code"
            add_plain_info_entry "Cell ID" "$cell_id" "Cell ID"
            add_plain_info_entry "PCI" "$pci" "Physical Cell ID"
            add_plain_info_entry "Band" "$lband" "Band"
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            ;;
    esac
}

cell_info_qualcomm()
{
    local zcellinfo=$(at $at_port "AT+ZCELLINFO?" | grep '+ZCELLINFO:' | cut -d: -f2-)
    local cops_response=$(at $at_port "AT+COPS?" | grep "+COPS:")
    local rat_num=$(echo "$cops_response" | awk -F',' '{print $4}' | sed 's/\r//g')
    local network_type=$(get_rat $rat_num)

    if [ -z "$zcellinfo" ]; then
        return
    fi

    local tac=$(echo "$zcellinfo" | cut -d',' -f1 | tr -d ' ')
    local cell_id=$(echo "$zcellinfo" | grep -o 'cellid:[^,]*' | cut -d: -f2)
    local pci=$(echo "$zcellinfo" | grep -o 'pci:[^,]*' | cut -d: -f2)
    local lband=$(echo "$zcellinfo" | grep -o 'band:[^,]*' | cut -d: -f2 | tr -d '\r ')

    local cesq_response=$(at $at_port "AT+CESQ" | grep "+CESQ:")
    local rsrp="" rsrq=""
    if [ -n "$cesq_response" ]; then
        rsrq=$(echo "$cesq_response" | awk -F',' '{print $5}' | tr -d ' ')
        rsrp=$(echo "$cesq_response" | awk -F',' '{print $6}' | tr -d ' \r')
        if [ -n "$rsrp" ] && [ "$rsrp" != "255" ]; then
            rsrp=$(($rsrp - 141))
        else
            rsrp=""
        fi
        if [ -n "$rsrq" ] && [ "$rsrq" != "255" ]; then
            rsrq=$(echo "$rsrq" | awk '{printf "%.1f", ($1 / 2) - 19.5}')
        else
            rsrq=""
        fi
    fi

    local csq_response=$(at $at_port "AT+CSQ" | grep "+CSQ:")
    local rssi=""
    if [ -n "$csq_response" ]; then
        local csq_num=$(echo "$csq_response" | awk -F'[:,]' '{print $2}' | tr -d ' ')
        if [ "$csq_num" != "99" ] && [ -n "$csq_num" ]; then
            rssi="$((2 * csq_num - 113))"
        fi
    fi

    at $at_port "AT+COPS=3,2" > /dev/null 2>&1
    local cops_num=$(at $at_port "AT+COPS?" | grep "+COPS:" | awk -F'"' '{print $2}')
    local mcc="" mnc=""
    if [ -n "$cops_num" ] && [ ${#cops_num} -ge 5 ]; then
        mcc=${cops_num:0:3}
        mnc=${cops_num:3}
    fi

    class="Cell Information"
    case "$network_type" in
        "LTE")
            network_mode="LTE Mode"
            add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
            set_4g_cell_info "$mcc" "$mnc" "$tac" "$cell_id" "" "$pci" "$lband" "" "" "$rsrp" "$rsrq" "" "" ""
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            ;;
        "WCDMA")
            network_mode="WCDMA Mode"
            add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
            add_plain_info_entry "LAC" "$tac" "Location Area Code"
            add_plain_info_entry "Cell ID" "$cell_id" "Cell ID"
            add_plain_info_entry "PSC" "$pci" "Primary Scrambling Code"
            add_plain_info_entry "Band" "$lband" "Band"
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            ;;
        *)
            network_mode="${network_type} Mode"
            add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
            add_plain_info_entry "TAC" "$tac" "Tracking Area Code"
            add_plain_info_entry "Cell ID" "$cell_id" "Cell ID"
            add_plain_info_entry "PCI" "$pci" "Physical Cell ID"
            add_plain_info_entry "Band" "$lband" "Band"
            add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
            ;;
    esac
}

#邻区信息（Gosuncn LTE平台暂不支持）
get_neighborcell()
{
    json_add_object "neighborcell"
    json_add_array "LTE"
    json_close_array
    json_add_object "lockcell_status"
    json_add_string "LTE" "unlock"
    json_close_object
    json_close_object
}

set_neighborcell()
{
    json_select "result"
    json_add_string "setlockcell" "not supported"
    json_close_object
}

vendor_get_disabled_features()
{
    json_add_string "" "NeighborCell"
}

#重启模组
soft_reboot()
{
    at $at_port "AT+CFUN=1,1"
}

#重置模组
reset_module()
{
    at $at_port "AT+ZSNT=0,0,0" 2>&1 > /dev/null
    at $at_port "AT+ZBAND=all,all,all,all" 2>&1 > /dev/null
    at $at_port "AT&F" 2>&1 > /dev/null
}
