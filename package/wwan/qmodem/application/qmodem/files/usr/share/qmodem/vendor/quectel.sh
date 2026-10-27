#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>
# Copyright (C) 2025 Fujr <fjrcn@outlook.com>
_Vendor="quectel"
_Author="Siriling,Fujr"
_Maintainer="Fujr <fjrcn@outlook.com>"
source "${QMODEM_HOME:-/usr/share/qmodem}/generic.sh"
source "${QMODEM_HOME:-/usr/share/qmodem}/cmds/quectel.sh"
debug_subject="quectel_ctrl"

get_5g_lan()
{
    local response enabled
    response=$(cmd_qcfg_5glan_query "$at_port")
    enabled=$(printf '%s\n' "$response" | sed -n 's/.*+QCFG: *"5glan",1,\([01]\).*/\1/p' | head -n 1)

    json_add_boolean supported 1
    if [ -n "$enabled" ]; then
        json_add_boolean enabled "$enabled"
    else
        json_add_string error "Unable to read 5G LAN state"
    fi
}

set_5g_lan()
{
    local enabled="$1" response ret

    case "$enabled" in
        0|1) ;;
        *)
            json_add_boolean supported 1
            json_add_string error "Invalid 5G LAN state"
            return 1
            ;;
    esac

    response=$(cmd_qcfg_5glan_set "$at_port" "$enabled")
    ret=$?
    json_add_boolean supported 1
    json_add_string response "$response"
    if [ "$ret" -ne 0 ] || ! printf '%s\n' "$response" | grep -q '^OK\r*$'; then
        json_add_string error "The modem rejected the 5G LAN setting"
        return 1
    fi

    json_add_boolean enabled "$enabled"
}
#return raw data
get_imei(){
    imei=$(cmd_cgsn "$at_port" | grep -o "[0-9]\{15\}")
    json_add_string "imei" "$imei"
}

#return raw data
set_imei(){
    local imei="$1"
    res=$(cmd_egmr_set_imei "$at_port" "$imei")
    json_select "result"
    json_add_string "set_imei" "$res"
    json_close_object
    get_imei
}

#获取拨号模式
# $1:AT串口
# $2:平台
get_mode()
{
    local mode_num=$(cmd_qcfg_usbnet_query "$at_port" | grep "+QCFG:" | sed 's/+QCFG: "usbnet",//g' | sed 's/\r//g')
    local mode
    case "$platform" in
        "qualcomm")
            case "$mode_num" in
                "0") mode="qmi" ;;
                # "0") mode="gobinet" ;;
                "1") mode="ecm" ;;
                "2") mode="mbim" ;;
                "3") mode="rndis" ;;
                "5") mode="ncm" ;;
                *) mode="${mode_num}" ;;
            esac
        ;;
        "unisoc")
            case "$mode_num" in
                "1") mode="ecm" ;;
                "2") mode="mbim" ;;
                "3") mode="rndis" ;;
                "5") mode="ncm" ;;
                *) mode="${mode_num}" ;;
            esac
        ;;
        "hisilicon")
            case "$mode_num" in
                "1") mode="ecm" ;;
                "3") mode="rndis" ;;
                "4") mode="ncm" ;;
                "5") mode="ncm" ;;
                *) mode="ncm" ;;
            esac
        ;;
        "lte12"|\
        "lte")
            case "$mode_num" in
                "0") mode="qmi" ;;
                # "0") mode="gobinet" ;;
                "1") mode="ecm" ;;
                "2") mode="mbim" ;;
                "3") mode="rndis" ;;
                "5") mode="ncm" ;;
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

#设置拨号模式
set_mode()
{
    #获取拨号模式配置
    local mode=$1
    case "$platform" in
        "qualcomm")
            case "$mode" in
                "qmi") mode_num="0" ;;
                # "gobinet")  mode_num="0" ;;
                "ecm") mode_num="1" ;;
                "mbim") mode_num="2" ;;
                "rndis") mode_num="3" ;;
                "ncm") mode_num="5" ;;
                *) mode_num="0" ;;
            esac
        ;;
        "unisoc")
            case "$mode" in
                "ecm") mode_num="1" ;;
                "mbim") mode_num="2" ;;
                "rndis") mode_num="3" ;;
                "ncm") mode_num="5" ;;
                *) mode_num="0" ;;
            esac
        ;;
        "lte12"|\
        "lte")
            case "$mode" in
                "qmi") mode_num="0" ;;
                # "gobinet")  mode_num="0" ;;
                "ecm") mode_num="1" ;;
                "mbim") mode_num="2" ;;
                "rndis") mode_num="3" ;;
                "ncm") mode_num="5" ;;
                *) mode_num="0" ;;
            esac
        ;;
        *)
            mode_num="0"
        ;;

    esac

    #设置模组
    res=$(cmd_qcfg_usbnet_set "$at_port" "$mode_num")
    json_select "result"
    json_add_string "set_mode" "$res"
    json_close_object
}

#获取网络偏好
# $1:AT串口
get_network_prefer()
{
    case "$platform" in
        "lte12"|\
        "qualcomm")
            get_network_prefer_nr
        ;;
        "unisoc")
            get_network_prefer_nr
        ;;
        "hisilicon")
            get_network_prefer_nr
        ;;
        "lte")
            get_network_prefer_lte
        ;;
        *)
            get_network_prefer_nr
        ;;
    esac
    json_add_object network_prefer
    json_add_string 3G $network_prefer_3g
    json_add_string 4G $network_prefer_4g
    case $platform in
        "qualcomm")
            json_add_string 5G $network_prefer_5g
        ;;
        "unisoc")
            json_add_string 5G $network_prefer_5g
        ;;
        "hisilicon")
            json_add_string 5G $network_prefer_5g
        ;;
    esac
    json_close_array
    
}

get_network_prefer_lte()
{
    response=$(cmd_qcfg_nwscanmode_query "$at_port" | grep "+QCFG:" | awk -F'",' '{print $2}' | sed 's/\r//g' |grep -o "[0-9]")
    network_prefer_3g="0";
    network_prefer_4g="0";
    case "$response" in
        "0") network_prefer_3g="1"; network_prefer_4g="1" ;;
        "3") network_prefer_4g="1" ;;
    esac
}

get_network_prefer_nr()
{
    local response=$(cmd_qnwprefcfg_mode_pref_query "$at_port" | grep "+QNWPREFCFG:" | awk -F',' '{print $2}' | sed 's/\r//g')
    
    network_prefer_3g="0";
    network_prefer_4g="0";
    network_prefer_5g="0";

    #匹配不同的网络类型
    local auto=$(echo "${response}" | grep "AUTO")
    if [ -n "$auto" ]; then
        network_prefer_3g="1"
        network_prefer_4g="1"
        network_prefer_5g="1"
    else
        local wcdma=$(echo "${response}" | grep "WCDMA")
        local lte=$(echo "${response}" | grep "LTE")
        local nr=$(echo "${response}" | grep "NR5G")
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
}

#设置网络偏好
# $1:AT串口
# $2:网络偏好配置
set_network_prefer()
{
    network_prefer_3g=$(echo $1 |jq -r 'contains(["3G"])')
    network_prefer_4g=$(echo $1 |jq -r 'contains(["4G"])')
    network_prefer_5g=$(echo $1 |jq -r 'contains(["5G"])')
    length=$(echo $1 |jq -r 'length')

    case "$platform" in
        "lte12"|\
        "qualcomm")
            set_network_prefer_nr $at_port $network_prefer
        ;;
        "unisoc")
            set_network_prefer_nr $at_port $network_prefer
        ;;
        "lte")
            set_network_prefer_lte $at_port $network_prefer
        ;;
        *)
            set_network_prefer_nr $at_port $network_prefer
        ;;
    esac
}

set_network_prefer_lte()
{
    case "$length" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                network_prefer_config="0"
            elif [ "$network_prefer_4g" = "true" ]; then
                network_prefer_config="3"
            fi
        ;;
        "2")
            network_prefer_config="0"
    esac

    #设置模组
    cmd_qcfg_nwscanmode_set "$at_port" "$network_prefer_config"

}


set_network_prefer_nr()
{
    case "$length" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                network_prefer_config="WCDMA"
            elif [ "$network_prefer_4g" = "true" ]; then
                network_prefer_config="LTE"
            elif [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="NR5G"
            fi
        ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                network_prefer_config="WCDMA:LTE"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="WCDMA:NR5G"
            elif [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="LTE:NR5G"
            fi
        ;;
        "3") network_prefer_config="AUTO" ;;
        *) network_prefer_config="AUTO" ;;
    esac

    #设置模组
    cmd_qnwprefcfg_mode_pref_set "$at_port" "$network_prefer_config"
}

#获取电压
# $1:AT串口
get_voltage()
{
	local voltage=$(cmd_cbc "$at_port" | grep "+CBC:" | awk -F',' '{print $3}' | sed 's/\r//g')
    [ -n "$voltage" ] && {
        add_plain_info_entry "voltage" "$voltage mV" "Voltage" 
    }
}

#获取温度
#return raw data
get_temperature()
{   
    #Temperature（温度）
    local temp
    local line=1
    QTEMP=$(cmd_qtemp "$at_port" | grep "+QTEMP:")
    for line in $( echo -e "$QTEMP" ); do
        templine=$(echo $line | grep -o "[0-9]\{1,3\}")
        for tmp in $(echo $templine); do
            [ "$tmp" -gt 10 ] && [ "$tmp" -lt 110 ] && temp=$tmp
            if [ -n "$temp" ]; then
                break
            fi
        done
    done
	if [ -n "$temp" ]; then
		temp="${temp}$(printf "\xc2\xb0")C"
	fi
    add_plain_info_entry "temperature" "$temp" "Temperature"
}



#基本信息
base_info()
{
    m_debug  "Quectel base info"

    #Name（名称）
    name=$(cmd_cgmm "$at_port" | sed -n '2p' | sed 's/\r//g')
    #Manufacturer（制造商）
    manufacturer=$(cmd_cgmi "$at_port" | sed -n '2p' | sed 's/\r//g')
    #Revision（固件版本）
    revision=$(cmd_ati "$at_port" | grep "Revision:" | sed 's/Revision: //g' | sed 's/\r//g')
    # at_command="AT+CGMR"
    # revision=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    class="Base Information"
    add_plain_info_entry "name" "$name" "Name"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_temperature
    get_voltage
    get_connect_status
}


# Accept the documented response and the +QUSIMSLOT spelling shown in the
# RM500U command manual example.
quectel_parse_sim_slot()
{
    awk -F':' '/\+(QUIMSLOT|QUSIMSLOT):/ {
        value=$2
        gsub(/[^0-9]/, "", value)
        if (value == "1" || value == "2") {
            print value
            exit
        }
    }'
}

quectel_get_sim_slot_value()
{
    cmd_quimslot_query "$at_port" | quectel_parse_sim_slot
}

#SIM卡信息
sim_info()
{
    m_debug  "Quectel sim info"
    
    #SIM Slot（SIM卡卡槽）
    sim_slot=$(quectel_get_sim_slot_value)

    #IMEI（国际移动设备识别码）
	imei=$(cmd_cgsn "$at_port" | sed -n '2p' | sed 's/\r//g')

    #SIM Status（SIM状态）
	sim_status_flag=$(cmd_cpin_query "$at_port" | sed -n '2p')
    sim_status=$(get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #ISP（互联网服务提供商）
    cmd_cops_numeric "$at_port" > /dev/null 2>&1
    isp=$(cmd_cops_query "$at_port" | sed -n '2p' | awk -F'"' '{print $2}')
    # if [ "$isp" = "CHN-CMCC" ] || [ "$isp" = "CMCC" ]|| [ "$isp" = "46000" ]; then
    #     isp="中国移动"
    # # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "UNICOM" ] || [ "$isp" = "46001" ]; then
    # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "CUCC" ] || [ "$isp" = "46001" ]; then
    #     isp="中国联通"
    # # elif [ "$isp" = "CHN-CT" ] || [ "$isp" = "CT" ] || [ "$isp" = "46011" ]; then
    # elif [ "$isp" = "CHN-TELECOM" ] || [ "$isp" = "CTCC" ] || [ "$isp" = "46011" ]; then
    #     isp="中国电信"
    # fi

    #SIM Number（SIM卡号码，手机号）
	sim_number=$(cmd_cnum "$at_port" | sed -n '2p' | awk -F'"' '{print $4}')

    #IMSI（国际移动用户识别码）
	imsi=$(cmd_cimi "$at_port" | sed -n '2p' | sed 's/\r//g')

    #ICCID（集成电路卡识别码）
	iccid=$(cmd_iccid "$at_port" | grep -o "+ICCID:[ ]*[-0-9A-F]\+" | cut -d " " -f 2 )
    [ -n "$iccid" ] || iccid=$(cmd_ccid "$at_port" | grep -o "+CCID:[ ]*[-0-9A-F]\+" | cut -d " " -f 2)
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

#网络信息
network_info()
{
    m_debug  "Quectel network info"

    #Connect Status（连接状态）

    #Network Type（网络类型）
    network_type=$(cmd_qnwinfo "$at_port" | grep "+QNWINFO:" | awk -F'"' '{print $2}')

    [ -z "$network_type" ] && {
        local rat_num=$(cmd_cops_query "$at_port" | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }

    #CSQ（信号强度）
    response=$(cmd_csq "$at_port" | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    #RSSI（信号强度指示）
    # rssi_num=$(echo $response | awk -F',' '{print $1}')
    # rssi=$(get_rssi $rssi_num)
    #Ber（信道误码率）
    # ber=$(echo $response | awk -F',' '{print $2}')

    #PER（信号强度）
    # if [ -n "$csq" ]; then
    #     per=$((csq * 100/31))"%"
    # fi

    #最大比特率，信道质量指示
    response=$(cmd_qnwcfg_nr5g_ambr_query "$at_port" | grep "+QNWCFG:")
    for context in $response; do
        local apn=$(echo "$context" | awk -F'"' '{print $4}' | tr 'a-z' 'A-Z')
        if [ -n "$apn" ] && [ "$apn" != "IMS" ]; then
            #CQL UL（上行信道质量指示）
            cqi_ul=$(echo "$context" | awk -F',' '{print $5}')
            #CQI DL（下行信道质量指示）
            cqi_dl=$(echo "$context" | awk -F',' '{print $3}')
            #AMBR UL（上行签约速率，单位，Mbps）
            ambr_ul=$(echo "$context" | awk -F',' '{print $6}' | sed 's/\r//g')
            #AMBR DL（下行签约速率，单位，Mbps）
            ambr_dl=$(echo "$context" | awk -F',' '{print $4}')
            break
        fi
    done

    #速率统计
    response=$(cmd_qnwcfg_updown_query "$at_port" | grep "+QNWCFG:" | sed 's/+QNWCFG: "up\/down",//g' | sed 's/\r//g')

    #当前上传速率（单位，Byte/s）
    tx_rate=$(echo $response | awk -F',' '{print $1}')

    #当前下载速率（单位，Byte/s）
    rx_rate=$(echo $response | awk -F',' '{print $2}')
    class="Network Information"
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
    add_plain_info_entry "CQI UL" "$cqi_ul" "Channel Quality Indicator for Uplink"
    add_plain_info_entry "CQI DL" "$cqi_dl" "Channel Quality Indicator for Downlink"
    add_plain_info_entry "AMBR UL" "$ambr_ul" "Access Maximum Bit Rate for Uplink"
    add_plain_info_entry "AMBR DL" "$ambr_dl" "Access Maximum Bit Rate for Downlink"
    add_speed_entry rx $rx_rate
    add_speed_entry tx $tx_rate
}

#获取频段
# $1:网络类型
# $2:频段数字
get_band()
{
    local band
    case $1 in
        "WCDMA") band="$2" ;;
        "LTE") band="$2" ;;
        "NR") band="$2" ;;
	esac
    echo "$band"
}

get_lockband_nr()
{
    local at_port="$1"
    m_debug  "Quectel sdx55 get lockband info"
    wcdma_avalible_band="1,2,3,4,5,6,7,8,9,19"
    lte_avalible_band="1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,34,38,39,40,41,42,66,71"
    nsa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79,257,258,260,261"
    sa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79"
    [ -n $(uci -q get qmodem.$config_section.sa_band) ] && sa_nr_avalible_band=$(uci -q get qmodem.$config_section.sa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.nsa_band) ] && nsa_nr_avalible_band=$(uci -q get qmodem.$config_section.nsa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.lte_band) ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.wcdma_band) ] && wcdma_avalible_band=$(uci -q get qmodem.$config_section.wcdma_band | tr '/' ',')
    gw_band=$(cmd_qnwprefcfg_band_query "$at_port" "gw_band" |grep -e "+QNWPREFCFG: " )
    lte_band=$(cmd_qnwprefcfg_band_query "$at_port" "lte_band"|grep -e "+QNWPREFCFG: ")
    nsa_nr_band=$(cmd_qnwprefcfg_band_query "$at_port" "nsa_nr5g_band"|grep -e "+QNWPREFCFG: ")
    sa_nr_band=$(cmd_qnwprefcfg_band_query "$at_port" "nr5g_band"|grep -e "+QNWPREFCFG: ")
    json_add_object "UMTS"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_object
    json_close_object
    json_add_object "LTE"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object

    json_add_object "NR"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    json_add_object "NR_NSA"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    for i in $(echo "$wcdma_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "UMTS"
        json_select "available_band"
        add_avalible_band_entry  "$i" "UMTS_$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$lte_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "LTE"
        json_select "available_band"
        add_avalible_band_entry  "$i" "LTE_B$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$nsa_nr_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "NR_NSA"
        json_select "available_band"
        add_avalible_band_entry  "$i" "NSA_NR_N$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$sa_nr_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "NR"
        json_select "available_band"
        add_avalible_band_entry  "$i" "SA_NR_N$i"
        json_select ..
        json_select ..
    done
    #+QNWPREFCFG: "nr5g_band",1:3:7:20:28:40:41:71:77:78:79
    for i in $(echo "$gw_band" | cut -d, -f2 |tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "UMTS"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$lte_band" | cut -d, -f2|tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "LTE"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$nsa_nr_band" | cut -d, -f2|tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "NR_NSA"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$sa_nr_band" | cut -d, -f2|tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "NR"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    json_close_array
}

get_lockband_lte12()
{
    m_debug  "Quectel sdx55 get lockband info"
    wcdma_avalible_band="1,2,3,4,5,6,7,8,9,19"
    lte_avalible_band="1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,34,38,39,40,41,42,66,71"
    nsa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79,257,258,260,261"
    sa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79"
    [ -n $(uci -q get qmodem.$config_section.sa_band) ] && sa_nr_avalible_band=$(uci -q get qmodem.$config_section.sa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.nsa_band) ] && nsa_nr_avalible_band=$(uci -q get qmodem.$config_section.nsa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.lte_band) ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.wcdma_band) ] && wcdma_avalible_band=$(uci -q get qmodem.$config_section.wcdma_band | tr '/' ',')
    gw_band=$(cmd_qnwprefcfg_band_query "$at_port" "gw_band" |grep -e "+QNWPREFCFG: " )
    lte_band=$(cmd_qnwprefcfg_band_query "$at_port" "lte_band"|grep -e "+QNWPREFCFG: ")
    nsa_nr_band=$(cmd_qnwprefcfg_band_query "$at_port" "nsa_nr5g_band"|grep -e "+QNWPREFCFG: ")
    sa_nr_band=$(cmd_qnwprefcfg_band_query "$at_port" "nr5g_band"|grep -e "+QNWPREFCFG: ")
    json_add_object "UMTS"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_object
    json_close_object
    json_add_object "LTE"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    for i in $(echo "$wcdma_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "UMTS"
        json_select "available_band"
        add_avalible_band_entry  "$i" "UMTS_$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$lte_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "LTE"
        json_select "available_band"
        add_avalible_band_entry  "$i" "LTE_B$i"
        json_select ..
        json_select ..
    done
    #+QNWPREFCFG: "nr5g_band",1:3:7:20:28:40:41:71:77:78:79
    for i in $(echo "$gw_band" | cut -d, -f2 |tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "UMTS"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$lte_band" | cut -d, -f2|tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "LTE"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    json_close_array
}

get_lockband_unisoc()
{
    local at_port="$1"
    m_debug  "Quectel sdx55 get lockband info"
    wcdma_avalible_band="1,2,3,4,5,6,7,8,9,19"
    lte_avalible_band="1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,34,38,39,40,41,42,66,71"
    nsa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79,257,258,260,261"
    sa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79"
    [ -n $(uci -q get qmodem.$config_section.sa_band) ] && sa_nr_avalible_band=$(uci -q get qmodem.$config_section.sa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.nsa_band) ] && nsa_nr_avalible_band=$(uci -q get qmodem.$config_section.nsa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.lte_band) ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.wcdma_band) ] && wcdma_avalible_band=$(uci -q get qmodem.$config_section.wcdma_band | tr '/' ',')
    gw_band=$(cmd_qnwprefcfg_band_query "$at_port" "gw_band" |grep -e "+QNWPREFCFG: " )
    lte_band=$(cmd_qnwprefcfg_band_query "$at_port" "lte_band"|grep -e "+QNWPREFCFG: ")
    nsa_nr_band=$(cmd_qnwprefcfg_band_query "$at_port" "nsa_nr5g_band"|grep -e "+QNWPREFCFG: ")
    sa_nr_band=$(cmd_qnwprefcfg_band_query "$at_port" "nr5g_band"|grep -e "+QNWPREFCFG: ")
    json_add_object "UMTS"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_object
    json_close_object
    json_add_object "LTE"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    json_add_object "NR"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    for i in $(echo "$wcdma_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "UMTS"
        json_select "available_band"
        add_avalible_band_entry  "$i" "UMTS_$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$lte_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "LTE"
        json_select "available_band"
        add_avalible_band_entry  "$i" "LTE_B$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$sa_nr_avalible_band" | awk -F"," '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "NR"
        json_select "available_band"
        add_avalible_band_entry  "$i" "NR_N$i"
        json_select ..
        json_select ..
    done
    #+QNWPREFCFG: "nr5g_band",1:3:7:20:28:40:41:71:77:78:79
    for i in $(echo "$gw_band" | cut -d, -f2 |tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "UMTS"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$lte_band" | cut -d, -f2|tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "LTE"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$sa_nr_band" | cut -d, -f2|tr -d '\r' | awk -F":" '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "NR"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    json_close_array
}

convert2band()
{
    hex_band=$1
    hex=$(echo $hex_band | grep -o "[0-9A-F]\{1,16\}")
    if [ -z "$hex" ]; then
        retrun
    fi
    band_list=""
    bin=$(echo "ibase=16;obase=2;$hex" | bc)
    len=${#bin}
    for i in $(seq 1 ${#bin}); do
        if [ ${bin:$i-1:1} = "1" ]; then
            band_list=$band_list"\n"$((len - i + 1))
        fi
    done
    echo -e $band_list | sort -n | tr '\n' ' '
}

convert2hex()
{
    band_list=$1
    #splite band_list
    band_list=$(echo $band_list | tr ',' '\n' | sort -n | uniq)
    hex="0"
    for band in $band_list; do
        add_hex=$(echo "obase=16;2^($band - 1 )" | bc)
        hex=$(echo "obase=16;ibase=16;$hex + $add_hex" | bc)
    done
    if [ -n $hex ]; then
        echo $hex
    else
        echo Invalid band
    fi
}

get_lockband_lte()
{
    local at_port="$1"
    LTE_LOCK=$(cmd_qcfg_band_query "$at_port" |grep '+QCFG:'| awk -F, '{print $3}' | sed 's/"//g' | tr '[:a-z:]' '[:A-Z:]')
    if [ -z "$LOCK_BAND" ]; then
        LOCK_BAND="Unknown"
    fi
    LOCK_BAND=$(convert2band $LTE_LOCK)
    json_add_object "Lte"
    json_add_array available_band
    add_avalible_band_entry "1" "B01" 
    add_avalible_band_entry "3" "B03"
    add_avalible_band_entry "5" "B05" 
    json_adadd_avalible_band_entryd_string "7" "B07"
    add_avalible_band_entry "8" "B08"
    add_avalible_band_entry "20" "B20"
    add_avalible_band_entry "34" "B34"
    add_avalible_band_entry "38" "B38"
    add_avalible_band_entry "39" "B39"
    json_addadd_avalible_band_entry_string "40" "B40"
    add_avalible_band_entry "41" "B41"
    json_close_array
    json_add_array "lock_band"
    for band in $(echo $LOCK_BAND | tr ',' '\n' | sort -n | uniq); do
        json_add_string "" $band
    done
    json_close_array
    json_close_object
    json_close_object
}

get_lockband()
{
    json_add_object "lockband"
    case "$platform" in
        "qualcomm")
            get_lockband_nr $at_port
        ;;
        "unisoc")
            get_lockband_unisoc $at_port
        ;;
        'lte')
            get_lockband_lte $at_port
        ;;
        "lte12")
            get_lockband_lte12
            ;;
        *)
            get_lockband_lte $at_port
        ;;
    esac
    json_close_object
}


set_lockband_lte()
{
    hex=$(convert2hex $lock_band)
    res=$(cmd_qcfg_band_reset "$at_port" "$hex"   2>&1 > /dev/null)
}

set_lockband_nr(){
    lock_band=$(echo $lock_band | tr ',' ':')
    case "$band_class" in
        "UMTS") 
            res=$(cmd_qnwprefcfg_band_set "$at_port" "gw_band" "$lock_band")
            ;;
        "LTE") 
            res=$(cmd_qnwprefcfg_band_set "$at_port" "lte_band" "$lock_band")
            ;;
        "NR_NSA")
            res=$(cmd_qnwprefcfg_band_set "$at_port" "nsa_nr5g_band" "$lock_band")
            ;;
        "NR")
            res=$(cmd_qnwprefcfg_band_set "$at_port" "nr5g_band" "$lock_band")
            ;;
    esac
}

#设置锁频
set_lockband()
{
    m_debug  "quectel set lockband info"
    config=$1
    #{"band_class":"NR","lock_band":"41,78,79"}
    band_class=$(echo $config | jq -r '.band_class')
    lock_band=$(echo $config | jq -r '.lock_band')
    case "$platform" in
        "lte")
            set_lockband_lte
        ;;
        *)
            set_lockband_nr
        ;;
    esac
    json_select "result"
    json_add_string "set_lockband" "$res"
    json_add_string "config" "$config"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$lock_band"
    json_close_object
}

get_neighborcell_qualcomm(){
    lte_status=$(cmd_qnwlock_query "$at_port" "common/4g" | grep "+QNWLOCK:")
    lte_lock_status=$(echo $lte_status | awk -F',' '{print $2}' | sed 's/\r//g')
    lte_lock_freq=$(echo $lte_status | awk -F',' '{print $3}' | sed 's/\r//g')
    lte_lock_pci=$(echo $lte_status | awk -F',' '{print $4}' | sed 's/\r//g')
    nr_status=$(cmd_qnwlock_query "$at_port" "common/5g" | grep "+QNWLOCK:")
    nr_lock_status=$(echo $nr_status | awk -F',' '{print $2}' | sed 's/\r//g')
    nr_lock_pci=$(echo $nr_status | awk -F',' '{print $2}' | sed 's/\r//g')
    nr_lock_freq=$(echo $nr_status | awk -F',' '{print $3}' | sed 's/\r//g')
    nr_lock_scs=$(echo $nr_status | awk -F',' '{print $4}' | sed 's/\r//g')
    nr_lock_band=$(echo $nr_status | awk -F',' '{print $5}' | sed 's/\r//g')
    if [ "$lte_lock_status" != "0" ]; then
        lte_lock_status="locked"
    else
        lte_lock_status=""
    fi
    if [ "$nr_lock_status" != "0" ]; then
        nr_lock_status="locked"
    else
        nr_lock_status=""
    fi


    cmd_qeng_neighbourcell "$at_port" > /tmp/neighborcell
    json_add_object "Feature"
    json_add_string "Unlock" "2"
    json_add_string "Lock PCI" "1"
    json_add_string "Reboot Modem" "4"
    json_add_string "Manually Search" "3"
    json_close_object
    json_add_array "NR"
    json_close_array
    json_add_array "LTE"
    json_close_array
    json_add_object "lockcell_status"
    if [ -n "$lte_lock_status" ]; then
        json_add_string "LTE" "$lte_lock_status"
        json_add_string "LTE_Freq" "$lte_lock_freq"
        json_add_string "LTE_PCI" "$lte_lock_pci"
    else
        json_add_string "LTE" "unlock"
    fi
    if [ -n "$nr_lock_status" ]; then
        json_add_string "NR" "$nr_lock_status"
        json_add_string "NR_Freq" "$nr_lock_freq"
        json_add_string "NR_PCI" "$nr_lock_pci"
        json_add_string "NR_SCS" "$nr_lock_scs"
        json_add_string "NR_Band" "$nr_lock_band"
    else
        json_add_string "NR" "unlock"
    fi
    json_close_object
    while read line; do
        if [ -n "$(echo $line | grep "+QENG:")" ]; then
            # +QENG: "neighbourcell intra","LTE",<earfcn>,<PCID>,<
            # RSRQ>,<RSRP>,<RSSI>,<SINR>,<srxlev>,<cell_resel_pri
            # ority>,<s_non_intra_search>,<thresh_serving_low>,<s_i
            # ntra_search>
            # …]
            # [+QENG: "neighbourcell inter","LTE",<earfcn>,<PCID>,<
            # RSRQ>,<RSRP>,<RSSI>,<SINR>,<srxlev>,<cell_resel_pri
            # ority>,<threshX_low>,<threshX_high>
            # …]
            # [+QENG:"neighbourcell","WCDMA",<uarfcn>,<cell_resel
            # _priority>,<thresh_Xhigh>,<thresh_Xlow>,<PSC>,<RSC
            # P><eccno>,<srxlev>
            # …]
            line=$(echo $line | sed 's/+QENG: //g')
            case $line in
                *WCDMA*)
                    type="WCDMA"
                    
                    arfcn=$(echo $line | awk -F',' '{print $3}')
                    pci=$(echo $line | awk -F',' '{print $4}')
                    rscp=$(echo $line | awk -F',' '{print $6}')
                    ecno=$(echo $line | awk -F',' '{print $7}')
                    ;;
                *LTE*)
                    type="LTE"
                    neighbourcell=$(echo $line | awk -F',' '{print $1}' | tr -d '"')
                    arfcn=$(echo $line | awk -F',' '{print $3}')
                    pci=$(echo $line | awk -F',' '{print $4}')
                    rsrp=$(echo $line | awk -F',' '{print $5}')
                    rsrq=$(echo $line | awk -F',' '{print $6}')

                    ;;
                *NR*)
                    type="NR"
                    arfcn=$(echo $line | awk -F',' '{print $3}')
                    pci=$(echo $line | awk -F',' '{print $4}')
                    rsrp=$(echo $line | awk -F',' '{print $5}')
                    rsrq=$(echo $line | awk -F',' '{print $6}')
                    ;;
            esac
            json_select $type
            json_add_object ""
            json_add_string "neighbourcell" "$neighbourcell"
            json_add_string "arfcn" "$arfcn"
            json_add_string "pci" "$pci"
            json_add_string "rscp" "$rscp"
            json_add_string "ecno" "$ecno"
            json_add_string "rsrp" "$rsrp"
            json_add_string "rsrq" "$rsrq"
            json_close_object
            json_select ".."
        fi
    done < /tmp/neighborcell
}

get_neighborcell_lte(){
    lte_status=$(cmd_qnwlock_query "$at_port" "common/lte" | grep "+QNWLOCK:")
    lte_lock_status=$(echo $lte_status | awk -F',' '{print $2}')
    lte_lock_freq=$(echo $lte_status | awk -F',' '{print $3}')
    lte_lock_pci=$(echo $lte_status | awk -F',' '{print $4}')
    lte_lock_finish=$(echo $lte_status | awk -F',' '{print $5}' | sed 's/\r//g')
    if [ "$lte_lock_finish" == "0" ]; then
        lte_lock_finish="finish"
    else
        lte_lock_finish="not finish"
    fi
    if [ "$lte_lock_status" == "1" ]; then
        lte_lock_status="locked arfcn,$lte_lock_finish"
    elif [ "$lte_lock_status" == "2" ]; then
        lte_lock_status="lock pci,$lte_lock_finish"
    else
        lte_lock_status=""
    fi
    cmd_qeng_neighbourcell "$at_port" > /tmp/neighborcell
    json_add_array "NR"
    json_close_array
    json_add_array "LTE"
    json_close_array
    json_add_object "lockcell_status"
    if [ -n "$lte_lock_status" ]; then
        json_add_string "lockcell_status" "$lte_lock_status"
        json_add_string "arfcn" "$lte_lock_freq"
        json_add_string "pci" "$lte_lock_pci"
    else
        json_add_string "lockcell_status" "unlock"
    fi
    json_close_object
    while read line; do
        if [ -n "$(echo $line | grep "+QENG:")" ]; then
            # +QENG: "neighbourcell intra","LTE",<earfcn>,<PCID>,<
            # RSRQ>,<RSRP>,<RSSI>,<SINR>,<srxlev>,<cell_resel_pri
            # ority>,<s_non_intra_search>,<thresh_serving_low>,<s_i
            # ntra_search>
            # …]
            # [+QENG: "neighbourcell inter","LTE",<earfcn>,<PCID>,<
            # RSRQ>,<RSRP>,<RSSI>,<SINR>,<srxlev>,<cell_resel_pri
            # ority>,<threshX_low>,<threshX_high>
            # …]
            # [+QENG:"neighbourcell","WCDMA",<uarfcn>,<cell_resel
            # _priority>,<thresh_Xhigh>,<thresh_Xlow>,<PSC>,<RSC
            # P><eccno>,<srxlev>
            # …]
            line=$(echo $line | sed 's/+QENG: //g')
            case $line in
                *LTE*)
                    type="LTE"
                    neighbourcell=$(echo $line | awk -F',' '{print $1}' | tr -d '"')
                    arfcn=$(echo $line | awk -F',' '{print $3}')
                    pci=$(echo $line | awk -F',' '{print $4}')
                    rsrq=$(echo $line | awk -F',' '{print $5}')
                    rsrp=$(echo $line | awk -F',' '{print $6}')

                    ;;
            esac
            json_select $type
            json_add_object ""
            json_add_string "neighbourcell" "$neighbourcell"
            json_add_string "arfcn" "$arfcn"
            json_add_string "pci" "$pci"
            json_add_string "rsrp" "$rsrp"
            json_add_string "rsrq" "$rsrq"
            json_close_object
            json_select ".."
        fi
    done < /tmp/neighborcell
}

get_neighborcell_unisoc(){
    lte_lock_status=""
    nr_lock_status=""
    lte_status=$(cmd_qnwlock_query "$at_port" "common/lte" | grep "+QNWLOCK:")
    lte_lock_freq=$(echo $lte_status | awk -F',' '{print $2}')
    lte_lock_pci=$(echo $lte_status | awk -F',' '{print $3}')
    nr_status=$(cmd_qnwlock_query "$at_port" "common/5g" | grep "+QNWLOCK:")
    nr_lock_pci=$(echo $nr_status | awk -F',' '{print $2}')
    nr_lock_freq=$(echo $nr_status | awk -F',' '{print $3}')
    [ -n "$lte_lock_freq" ] && lte_lock_status="locked"
    [ -n "$nr_lock_freq" ] && nr_lock_status="locked"


    cmd_qeng_neighbourcell "$at_port" > /tmp/neighborcell
    json_add_array "NR"
    json_close_array
    json_add_array "LTE"
    json_close_array
    json_add_object "lockcell_status"
    if [ -n "$lte_lock_status" ]; then
        json_add_string "LTE" "$lte_lock_status"
        json_add_string "LTE_Freq" "$lte_lock_freq"
        json_add_string "LTE_PCI" "$lte_lock_pci"
    else
        json_add_string "LTE" "unlock"
    fi
    if [ -n "$nr_lock_status" ]; then
        json_add_string "NR" "$nr_lock_status"
        json_add_string "NR_Freq" "$nr_lock_freq"
        json_add_string "NR_PCI" "$nr_lock_pci"
    else
        json_add_string "NR" "unlock"
    fi
    json_close_object
    while read line; do
        if [ -n "$(echo $line | grep "+QENG:")" ]; then
            type=""
            neighbourcell=""
            arfcn=""
            pci=""
            rscp=""
            ecno=""
            rsrp=""
            rsrq=""
            # +QENG: "neighbourcell intra","LTE",<earfcn>,<PCID>,<
            # RSRQ>,<RSRP>,<RSSI>,<SINR>,<srxlev>,<cell_resel_pri
            # ority>,<s_non_intra_search>,<thresh_serving_low>,<s_i
            # ntra_search>
            # …]
            # [+QENG: "neighbourcell inter","LTE",<earfcn>,<PCID>,<
            # RSRQ>,<RSRP>,<RSSI>,<SINR>,<srxlev>,<cell_resel_pri
            # ority>,<threshX_low>,<threshX_high>
            # …]
            # [+QENG:"neighbourcell","WCDMA",<uarfcn>,<cell_resel
            # _priority>,<thresh_Xhigh>,<thresh_Xlow>,<PSC>,<RSC
            # P><eccno>,<srxlev>
            # …]
            line=$(echo $line | sed 's/+QENG: //g')
            case $line in
                *WCDMA*)
                    type="WCDMA"
                    
                    arfcn=$(echo $line | awk -F',' '{print $3}')
                    pci=$(echo $line | awk -F',' '{print $4}')
                    rscp=$(echo $line | awk -F',' '{print $6}')
                    ecno=$(echo $line | awk -F',' '{print $7}')
                    ;;
                *LTE*)
                    type="LTE"
                    neighbourcell=$(echo $line | awk -F',' '{print $1}' | tr -d '"')
                    arfcn=$(echo $line | awk -F',' '{print $3}')
                    pci=$(echo $line | awk -F',' '{print $4}')
                    rsrp=$(echo $line | awk -F',' '{print $5}')
                    rsrq=$(echo $line | awk -F',' '{print $6}')

                    ;;
                *NR*)
                    type="NR"
                    arfcn=$(echo $line | awk -F',' '{print $3}')
                    pci=$(echo $line | awk -F',' '{print $4}')
                    rsrp=$(echo $line | awk -F',' '{print $5}')
                    rsrq=$(echo $line | awk -F',' '{print $6}')
                    ;;
            esac
            json_select $type
            json_add_object ""
            json_add_string "neighbourcell" "$neighbourcell"
            json_add_string "arfcn" "$arfcn"
            json_add_string "pci" "$pci"
            json_add_string "rscp" "$rscp"
            json_add_string "ecno" "$ecno"
            json_add_string "rsrp" "$rsrp"
            json_add_string "rsrq" "$rsrq"
            json_close_object
            json_select ".."
        fi
    done < /tmp/neighborcell
}

get_neighborcell(){
    m_debug  "quectel set lockband info"
    json_add_object "neighborcell"
    case "$platform" in
        "lte12"|\
        "qualcomm")
            get_neighborcell_qualcomm
        ;;
        "unisoc")
            get_neighborcell_unisoc
        ;;
        "lte")
            get_neighborcell_lte
        ;;
    esac
    qmodem_lockcell_boot_hook_add_json "$config_section"
    json_close_object
}



set_neighborcell(){
    #at_port,func,celltype,arfcn,pci,scs,nrband
    #  "lockpci" "1"
    #  "unlockcell" "2"
    #  "manually search" "3"
    #  "reboot modem" "4"
    json_param=$1
# {\"rat\":1,\"pci\":\"113\",\"arfcn\":\"627264\",\"band\":\"\",\"scs\":0}"
    rat=$(echo $json_param | jq -r '.rat')
    pci=$(echo $json_param | jq -r '.pci')
    arfcn=$(echo $json_param | jq -r '.arfcn')
    band=$(echo $json_param | jq -r '.band')
    scs=$(echo $json_param | jq -r '.scs')
    en_boot_hook=$(echo $json_param | jq -r '.en_boot_hook // empty')
    case $platform in
        "lte12"|\
        "qualcomm")
            lockcell_qualcomm
            ;;
        "unisoc")
            lockcell_unisoc
            ;;
        "lte")
            lockcell_lte
            ;;
    esac
    json_select "result"
    json_add_string "setlockcell" "$res"
    json_add_string "rat" "$rat"
    json_add_string "pci" "$pci"
    json_add_string "arfcn" "$arfcn"
    json_add_string "band" "$band"
    json_add_string "scs" "$scs"
    if qmodem_bool_enabled "$(uci -q get "qmodem.${config_section}.lockcell_boot_hook_enabled")"; then
        json_add_boolean "boot_hook_enabled" 1
    else
        json_add_boolean "boot_hook_enabled" 0
    fi
    json_close_object
}

lockcell_qualcomm(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        res1=$(cmd_qnwlock_unlock "$at_port" "common/5g")
        res2=$(cmd_qnwlock_unlock "$at_port" "common/4g")
        res=$res1,$res2
        qmodem_lockcell_boot_hook_clear "$config_section"
    else
        lock4g="AT+QNWLOCK=\"common/4g\",1,$arfcn,$pci"
        locknr="AT+QNWLOCK=\"common/5g\",$pci,$arfcn,$(get_scs $scs),$band"
        if [ $rat = "1" ]; then
            lockcell_boot_cmd="$locknr"
            res=$(cmd_qnwlock_set "$at_port" "common/5g" "$pci,$arfcn,$(get_scs $scs),$band")
        else
            lockcell_boot_cmd="$lock4g"
            res=$(cmd_qnwlock_set "$at_port" "common/4g" "1,$arfcn,$pci")
        fi
        qmodem_lockcell_boot_hook_sync "$config_section" "$en_boot_hook" "$lockcell_boot_cmd"
    fi
   
}

lockcell_unisoc(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        res1=$(cmd_qnwlock_unlock "$at_port" "common/5g")
        res2=$(cmd_qnwlock_unlock "$at_port" "common/lte")
        res=$res1,$res2
        qmodem_lockcell_boot_hook_clear "$config_section"
    else
        lock4g="AT+QNWLOCK=\"common/lte\",1,$arfcn,$pci"
        locknr="AT+QNWLOCK=\"common/5g\",1,$arfcn,$pci"
        if [ $rat = "1" ]; then
            lockcell_boot_cmd="$locknr"
            res=$(cmd_qnwlock_set "$at_port" "common/5g" "1,$arfcn,$pci")
        else
            lockcell_boot_cmd="$lock4g"
            res=$(cmd_qnwlock_set "$at_port" "common/lte" "1,$arfcn,$pci")
        fi
        qmodem_lockcell_boot_hook_sync "$config_section" "$en_boot_hook" "$lockcell_boot_cmd"
    fi
}

lockcell_lte(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        res1=$(cmd_qnwlock_unlock "$at_port" "common/lte")
        res=$res1
        qmodem_lockcell_boot_hook_clear "$config_section"
    else
        if [ -z $pci ] && [ -n $arfcn ]; then
            locklte="AT+QNWLOCK=\"common/lte\",1,$arfcn,0"
            res=$(cmd_qnwlock_set "$at_port" "common/lte" "1,$arfcn,0")
        elif [ -n $pci ] && [ -n $arfcn ]; then
            locklte="AT+QNWLOCK=\"common/lte\",2,$arfcn,$pci"
            res=$(cmd_qnwlock_set "$at_port" "common/lte" "2,$arfcn,$pci")
        fi
        qmodem_lockcell_boot_hook_sync "$config_section" "$en_boot_hook" "$locklte"
    fi
}

unlockcell(){
    res2=$(cmd_qnwlock_unlock "$1" "common/5g")
    res3=$(cmd_qnwlock_unlock "$1" "common/4g")
}

unlockcell_unisoc(){
    res2=$(cmd_qnwlock_unlock "$1" "common/5g")
    res3=$(cmd_qnwlock_unlock "$1" "common/lte")
}

unlockcell_lte(){
    res1=$(cmd_qnwlock_unlock "$1" "common/lte")
}

lockpci_unisoc(){
    local at_port="$1"
    local cell_type="$2"
    local arfcn="$3"
    local pci="$4"
    echo 1:$cell_type 2:$arfcn 3:$pci
    case $cell_type in
    0)
        lock4g="AT+QNWLOCK=\"common/lte\",1,$arfcn,$pci"
        res=$(cmd_qnwlock_set "$at_port" "common/lte" "1,$arfcn,$pci")
        echo $lock4g res:$res
        ;;
    1)
        locknr="AT+QNWLOCK=\"common/5g\",1,$arfcn,$pci"
        res=$(cmd_qnwlock_set "$at_port" "common/5g" "1,$arfcn,$pci")
        echo $locknr res:$res
        ;;
    esac
}

lockpci_nr(){
    local at_port="$1"
    local cell_type="$2"
    local arfcn="$3"
    local pci="$4"
    local scs="$5"
    local nrband="$6"
    case $scs in
    0)
        scs=15;;
    1)
        scs=30;;
    2)
        scs=60;;
    esac

    if [ "$cell_type" = "0" ]; then
        lock4g="AT+QNWLOCK=\"common/4g\",1,$arfcn,$pci"
        res=$(cmd_qnwlock_set "$at_port" "common/4g" "1,$arfcn,$pci")
    elif [ "$cell_type" = "1" ]; then
        locknr="AT+QNWLOCK=\"common/5g\",1,$pci,$arfcn,$scs,$nrband"
        echo $locknr
        res=$(cmd_qnwlock_set "$at_port" "common/5g" "1,$pci,$arfcn,$scs,$nrband")
    fi
}

lockpci_lte(){
    local at_port="$1"
    local cell_type="$2"
    local arfcn="$3"
    local pci="$4"
    local scs="$5"
    local nrband="$6"
    locklte="AT+QNWLOCK=\"common/lte\",2,$arfcn,$pci"
    res=$(cmd_qnwlock_set "$at_port" "common/lte" "2,$arfcn,$pci")
}

lockarfn_lte(){
    local at_port="$1"
    local cell_type="$2"
    local arfcn="$3"
    local pci="$4"
    local scs="$5"
    local nrband="$6"
    locklte="AT+QNWLOCK=\"common/lte\",1,$arfcn,0"
    res=$(cmd_qnwlock_set "$at_port" "common/lte" "1,$arfcn,0")
}


#UL_bandwidth
# $1:上行带宽数字
get_bandwidth()
{
    local network_type="$1"
    local bandwidth_num="$2"

    local bandwidth=""
    case $network_type in
		"LTE")
            case $bandwidth_num in
                "0") bandwidth="1.4" ;;
                "1") bandwidth="3" ;;
                "2"|"3"|"4"|"5") bandwidth=$((($bandwidth_num - 1) * 5)) ;;
            esac
        ;;
        "NR")
            case $bandwidth_num in
                "0"|"1"|"2"|"3"|"4"|"5") bandwidth=$((($bandwidth_num + 1) * 5)) ;;
                "6"|"7"|"8"|"9"|"10"|"11"|"12") bandwidth=$((($bandwidth_num - 2) * 10)) ;;
                "13") bandwidth="200" ;;
                "14") bandwidth="400" ;;
            esac
        ;;
	esac
    echo "$bandwidth"
}

#获取NR子载波间隔
# $1:NR子载波间隔数字
get_scs()
{
    local scs
	case $1 in
		"0") scs="15" ;;
		"1") scs="30" ;;
        "2") scs="60" ;;
        "3") scs="120" ;;
        "4") scs="240" ;;
        *) scs=$(awk "BEGIN{ print 2^$1 * 15 }") ;;
	esac
    echo "$scs"
}

#获取物理信道
# $1:物理信道数字
get_phych()
{
    local phych
	case $1 in
		"0") phych="DPCH" ;;
        "1") phych="FDPCH" ;;
	esac
    echo "$phych"
}

#获取扩频因子
# $1:扩频因子数字
get_sf()
{
    local sf
	case $1 in
		"0"|"1"|"2"|"3"|"4"|"5"|"6"|"7") sf=$(awk "BEGIN{ print 2^$(($1+2)) }") ;;
        "8") sf="UNKNOWN" ;;
	esac
    echo "$sf"
}

#获取插槽格式
# $1:插槽格式数字
get_slot()
{
    local slot=$1
	# case $1 in
		# "0"|"1"|"2"|"3"|"4"|"5"|"6"|"7"|"8"|"9"|"10"|"11"|"12"|"13"|"14"|"15"|"16") slot=$1 ;;
        # "0"|"1"|"2"|"3"|"4"|"5"|"6"|"7"|"8"|"9") slot=$1 ;;
	# esac
    echo "$slot"
}

#小区信息
cell_info()
{
    m_debug  "Quectel cell info"

    response=$(cmd_qeng_servingcell "$at_port")
    
    local lte=$(echo "$response" | grep "+QENG: \"LTE\"")
    local nr5g_nsa=$(echo "$response" | grep "+QENG: \"NR5G-NSA\"")
    if [ -n "$lte" ] && [ -n "$nr5g_nsa" ] ; then
        #EN-DC模式
        network_mode="EN-DC Mode"
        #LTE
        endc_lte_duplex_mode=$(echo "$lte" | awk -F',' '{print $2}' | sed 's/"//g')
        endc_lte_mcc=$(echo "$lte" | awk -F',' '{print $3}')
        endc_lte_mnc=$(echo "$lte" | awk -F',' '{print $4}')
        endc_lte_cell_id=$(echo "$lte" | awk -F',' '{print $5}')
        endc_lte_physical_cell_id=$(echo "$lte" | awk -F',' '{print $6}')
        endc_lte_earfcn=$(echo "$lte" | awk -F',' '{print $7}')
        endc_lte_freq_band_ind_num=$(echo "$lte" | awk -F',' '{print $8}')
        endc_lte_band=$(get_band "LTE" $endc_lte_freq_band_ind_num)
        ul_bandwidth_num=$(echo "$lte" | awk -F',' '{print $9}')
        endc_lte_ul_bandwidth=$(get_bandwidth "LTE" $ul_bandwidth_num)
        dl_bandwidth_num=$(echo "$lte" | awk -F',' '{print $10}')
        endc_lte_dl_bandwidth=$(get_bandwidth "LTE" $dl_bandwidth_num)
        endc_lte_tac=$(echo "$lte" | awk -F',' '{print $11}')
        endc_lte_rsrp=$(echo "$lte" | awk -F',' '{print $12}')
        endc_lte_rsrq=$(echo "$lte" | awk -F',' '{print $13}')
        endc_lte_rssi=$(echo "$lte" | awk -F',' '{print $14}')
        endc_lte_sinr=$(echo "$lte" | awk -F',' '{print $15}')
        endc_lte_cql=$(echo "$lte" | awk -F',' '{print $16}')
        endc_lte_tx_power=$(echo "$lte" | awk -F',' '{print $17}')
        endc_lte_srxlev=$(echo "$lte" | awk -F',' '{print $18}' | sed 's/\r//g')
        #NR5G-NSA
        endc_nr_mcc=$(echo "$nr5g_nsa" | awk -F',' '{print $2}')
        endc_nr_mnc=$(echo "$nr5g_nsa" | awk -F',' '{print $3}')
        endc_nr_physical_cell_id=$(echo "$nr5g_nsa" | awk -F',' '{print $4}')
        endc_nr_rsrp=$(echo "$nr5g_nsa" | awk -F',' '{print $5}')
        endc_nr_sinr=$(echo "$nr5g_nsa" | awk -F',' '{print $6}')
        endc_nr_rsrq=$(echo "$nr5g_nsa" | awk -F',' '{print $7}')
        endc_nr_arfcn=$(echo "$nr5g_nsa" | awk -F',' '{print $8}')
        endc_nr_band_num=$(echo "$nr5g_nsa" | awk -F',' '{print $9}')
        endc_nr_band=$(get_band "NR" $endc_nr_band_num)
        nr_dl_bandwidth_num=$(echo "$nr5g_nsa" | awk -F',' '{print $10}')
        endc_nr_dl_bandwidth=$(get_bandwidth "NR" $nr_dl_bandwidth_num)
        scs_num=$(echo "$nr5g_nsa" | awk -F',' '{print $16}' | sed 's/\r//g')
        endc_nr_scs=$(get_scs $scs_num)
    else
        #SA，LTE，WCDMA模式
        response=$(echo "$response" | grep "+QENG:")
        local rat=$(echo "$response" | awk -F',' '{print $3}' | sed 's/"//g')
        case $rat in
            "NR5G-SA")
                network_mode="NR5G-SA Mode"
                ca_response=$(cmd_qcainfo "$at_port")
                ca_scc_info=$(echo "$ca_response" | grep "+QCAINFO:" | grep "SCC")
                ca_scc_arfcn=""
                scc_nr_dl_bandwidth=""
                ca_scc_band_num=""
                ca_scc_pci=""

                if [ -n "$ca_scc_info" ]; then
                    scc_count=1

                    while IFS= read -r scc_line; do
                        [ -z "$scc_line" ] && continue
                        scc_count=$((scc_count + 1))
                        # +QCAINFO: "SCC",627264,12,"NR5G BAND 78",1,293,0,-,-
                        arfcn=$(echo "$scc_line" | awk -F',' '{print $2}')
                        bandwidth=$(get_bandwidth "NR" $(echo "$scc_line" | awk -F',' '{print $3}'))
                        band_info=$(echo "$scc_line" | awk -F',' '{print $4}' | sed 's/"//g')
                        band=$(echo "$band_info" | awk -F'BAND ' '{print $2}')
                        pci=$(echo "$scc_line" | awk -F',' '{print $6}')
                        if [ -n "$arfcn" ] && [ "$arfcn" != "-" ]; then
                            [ -n "$ca_scc_arfcn" ] && ca_scc_arfcn="$ca_scc_arfcn / "
                            ca_scc_arfcn="$ca_scc_arfcn$arfcn"
                        fi
                        if [ -n "$bandwidth" ] && [ "$bandwidth" != "-" ]; then
                            [ -n "$scc_nr_dl_bandwidth" ] && scc_nr_dl_bandwidth="$scc_nr_dl_bandwidth / "
                            scc_nr_dl_bandwidth="$scc_nr_dl_bandwidth$bandwidth"
                        fi
                        if [ -n "$band" ] && [ "$band" != "-" ]; then
                            [ -n "$ca_scc_band_num" ] && ca_scc_band_num="$ca_scc_band_num / "
                            ca_scc_band_num="$ca_scc_band_num$band"
                        fi
                        if [ -n "$pci" ] && [ "$pci" != "-" ]; then
                            [ -n "$ca_scc_pci" ] && ca_scc_pci="$ca_scc_pci / "
                            ca_scc_pci="$ca_scc_pci$pci"
                        fi
                    done <<EOF
$(echo "$ca_scc_info")
EOF
                    [ $scc_count -gt 1 ] && network_mode="$network_mode with $scc_count CA"
                fi
                nr_duplex_mode=$(echo "$response" | awk -F',' '{print $4}' | sed 's/"//g')
                nr_mcc=$(echo "$response" | awk -F',' '{print $5}')
                nr_mnc=$(echo "$response" | awk -F',' '{print $6}')
                nr_cell_id=$(echo "$response" | awk -F',' '{print $7}')
                nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                [ -n "$ca_scc_pci" ] && nr_physical_cell_id="$nr_physical_cell_id / $ca_scc_pci"
                nr_tac=$(echo "$response" | awk -F',' '{print $9}')
                nr_arfcn=$(echo "$response" | awk -F',' '{print $10}')
                [ -n "$ca_scc_arfcn" ] && nr_arfcn="$nr_arfcn / $ca_scc_arfcn"
                nr_band_num=$(echo "$response" | awk -F',' '{print $11}')
                nr_band=$(get_band "NR" $nr_band_num)
                [ -n "$ca_scc_band_num" ] && nr_band="$nr_band / $ca_scc_band_num"
                nr_dl_bandwidth_num=$(echo "$ca_response" | grep "+QCAINFO:" | grep "PCC" | awk -F',' '{print $3}')
                nr_dl_bandwidth=$(get_bandwidth "NR" $nr_dl_bandwidth_num)
                nr_ul_bandwidth=$nr_dl_bandwidth
                [ -n "$scc_nr_dl_bandwidth" ] && nr_dl_bandwidth="$nr_dl_bandwidth / $scc_nr_dl_bandwidth"
                nr_rsrp=$(echo "$response" | awk -F',' '{print $13}')
                nr_rsrq=$(echo "$response" | awk -F',' '{print $14}')
                nr_sinr=$(echo "$response" | awk -F',' '{print $15}')
                nr_scs_num=$(echo "$response" | awk -F',' '{print $16}')
                nr_scs=$(get_scs $nr_scs_num)
                nr_srxlev=$(echo "$response" | awk -F',' '{print $17}' | sed 's/\r//g')
            ;;
            "LTE"|"CAT-M"|"CAT-NB")
                network_mode="LTE Mode"
                lte_duplex_mode=$(echo "$response" | awk -F',' '{print $4}' | sed 's/"//g')
                lte_mcc=$(echo "$response" | awk -F',' '{print $5}')
                lte_mnc=$(echo "$response" | awk -F',' '{print $6}')
                lte_cell_id=$(echo "$response" | awk -F',' '{print $7}')
                lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                lte_earfcn=$(echo "$response" | awk -F',' '{print $9}')
                lte_freq_band_ind_num=$(echo "$response" | awk -F',' '{print $10}')
                lte_freq_band_ind=$(get_band "LTE" $lte_freq_band_ind_num)
                ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $11}')
                lte_ul_bandwidth=$(get_bandwidth "LTE" $ul_bandwidth_num)
                dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $12}')
                lte_dl_bandwidth=$(get_bandwidth "LTE" $dl_bandwidth_num)
                lte_tac=$(echo "$response" | awk -F',' '{print $13}')
                lte_rsrp=$(echo "$response" | awk -F',' '{print $14}')
                lte_rsrq=$(echo "$response" | awk -F',' '{print $15}')
                lte_rssi=$(echo "$response" | awk -F',' '{print $16}')
                lte_sinr=$(echo "$response" | awk -F',' '{print $17}')
                lte_cql=$(echo "$response" | awk -F',' '{print $18}')
                lte_tx_power=$(echo "$response" | awk -F',' '{print $19}')
                lte_srxlev=$(echo "$response" | awk -F',' '{print $20}' | sed 's/\r//g')
            ;;
            "WCDMA")
                network_mode="WCDMA Mode"
                wcdma_mcc=$(echo "$response" | awk -F',' '{print $4}')
                wcdma_mnc=$(echo "$response" | awk -F',' '{print $5}')
                wcdma_lac=$(echo "$response" | awk -F',' '{print $6}')
                wcdma_cell_id=$(echo "$response" | awk -F',' '{print $7}')
                wcdma_uarfcn=$(echo "$response" | awk -F',' '{print $8}')
                wcdma_psc=$(echo "$response" | awk -F',' '{print $9}')
                wcdma_rac=$(echo "$response" | awk -F',' '{print $10}')
                wcdma_rscp=$(echo "$response" | awk -F',' '{print $11}')
                wcdma_ecio=$(echo "$response" | awk -F',' '{print $12}')
                wcdma_phych_num=$(echo "$response" | awk -F',' '{print $13}')
                wcdma_phych=$(get_phych $wcdma_phych_num)
                wcdma_sf_num=$(echo "$response" | awk -F',' '{print $14}')
                wcdma_sf=$(get_sf $wcdma_sf_num)
                wcdma_slot_num=$(echo "$response" | awk -F',' '{print $15}')
                wcdma_slot=$(get_slot $wcdma_slot_num)
                wcdma_speech_code=$(echo "$response" | awk -F',' '{print $16}')
                wcdma_com_mod=$(echo "$response" | awk -F',' '{print $17}' | sed 's/\r//g')
            ;;
        esac
    fi
    class="Cell Information"
    add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
    case $network_mode in
    "NR5G-SA Mode"*)
        add_plain_info_entry "Duplex Mode" "$nr_duplex_mode" "Duplex Mode"
        set_5g_cell_info "$nr_mcc" "$nr_mnc" "$nr_tac" "$nr_cell_id" "$nr_arfcn" \
            "$nr_physical_cell_id" "$nr_band" "$nr_ul_bandwidth" "$nr_dl_bandwidth" \
            "$nr_rsrp" "$nr_rsrq" "$nr_sinr" "" ""
        add_plain_info_entry "SCS" "$nr_scs" "SCS"
        add_plain_info_entry "Srxlev" "$nr_srxlev" "Serving Cell Receive Level"
        # Add CA info if present
        if [ -n "$ca_scc_arfcn" ] || [ -n "$ca_scc_pci" ] || [ -n "$ca_scc_band_num" ]; then
            add_ca_info "5G" "$ca_scc_arfcn" "$ca_scc_pci" "$ca_scc_band_num" "" "$scc_nr_dl_bandwidth"
        fi
        ;;
    "EN-DC Mode")
        # LTE part
        add_plain_info_entry "LTE" "LTE" ""
        add_plain_info_entry "Duplex Mode" "$endc_lte_duplex_mode" "Duplex Mode"
        extra_info="LTE"
        set_4g_cell_info "$endc_lte_mcc" "$endc_lte_mnc" "$endc_lte_tac" "$endc_lte_cell_id" \
            "$endc_lte_earfcn" "$endc_lte_physical_cell_id" "$endc_lte_band" \
            "$endc_lte_ul_bandwidth" "$endc_lte_dl_bandwidth" "$endc_lte_rsrp" "$endc_lte_rsrq" \
            "$endc_lte_sinr" "$endc_lte_rssnr" "$endc_lte_rxlev"
        add_bar_info_entry "RSSI" "$endc_lte_rssi" "Received Signal Strength Indicator" -120 -20 dBm
        add_plain_info_entry "CQI" "$endc_lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$endc_lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$endc_lte_srxlev" "Serving Cell Receive Level"
        # NR5G-NSA part
        add_plain_info_entry "NR5G-NSA" "NR5G-NSA" ""
        extra_info="NR"
        set_5g_cell_info "$endc_nr_mcc" "$endc_nr_mnc" "" "" "$endc_nr_arfcn" \
            "$endc_nr_physical_cell_id" "$endc_nr_band" "" "$endc_nr_dl_bandwidth" \
            "$endc_nr_rsrp" "$endc_nr_rsrq" "$endc_nr_sinr" "" ""
        add_plain_info_entry "SCS" "$endc_nr_scs" "SCS"
        ;;
    "LTE Mode")
        add_plain_info_entry "Duplex Mode" "$lte_duplex_mode" "Duplex Mode"
        extra_info="LTE"
        set_4g_cell_info "$lte_mcc" "$lte_mnc" "$lte_tac" "$lte_cell_id" "$lte_earfcn" \
            "$lte_physical_cell_id" "$lte_band" "$lte_ul_bandwidth" "$lte_dl_bandwidth" \
            "$lte_rsrp" "$lte_rsrq" "$lte_sinr" "$lte_rssnr" "$lte_rxlev"
        add_bar_info_entry "RSSI" "$lte_rssi" "Received Signal Strength Indicator" -120 -20 dBm
        add_plain_info_entry "CQI" "$lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$lte_srxlev" "Serving Cell Receive Level"
        ;;
    "WCDMA Mode")
        set_3g_cell_info "$wcdma_mcc" "$wcdma_mnc" "$wcdma_lac" "$wcdma_cell_id" \
            "$wcdma_uarfcn" "$wcdma_psc" "" "" "" "$wcdma_rscp" "" "$wcdma_ecio" "" "$wcdma_rac"
        add_plain_info_entry "Ec/No" "$wcdma_ecno" "Ec/No"
        add_plain_info_entry "Physical Channel" "$wcdma_phych" "Physical Channel"
        add_plain_info_entry "Spreading Factor" "$wcdma_sf" "Spreading Factor"
        add_plain_info_entry "Slot" "$wcdma_slot" "Slot"
        add_plain_info_entry "Speech Code" "$wcdma_speech_code" "Speech Code"
        add_plain_info_entry "Compression Mode" "$wcdma_com_mod" "Compression Mode"
        ;;
    esac
}

get_current_band()
{
    local response lte nr5g_nsa rat ca_response ca_scc_info
    local network_mode status

    response=$(cmd_qeng_servingcell "$at_port")
    lte=$(echo "$response" | grep '+QENG: "LTE"')
    nr5g_nsa=$(echo "$response" | grep '+QENG: "NR5G-NSA"')
    status="ok"

    json_add_object "current_band"
    json_add_string "vendor" "$_Vendor"

    if [ -n "$lte" ] && [ -n "$nr5g_nsa" ]; then
        network_mode="EN-DC"
        json_add_string "status" "$status"
        json_add_string "network_mode" "$network_mode"
        json_add_array "cells"

        qmodem_add_current_band_cell "pcc" "LTE" \
            "$(get_band "LTE" "$(echo "$lte" | awk -F',' '{print $8}')")" \
            "$(echo "$lte" | awk -F',' '{print $7}')" \
            "EARFCN" \
            "$(echo "$lte" | awk -F',' '{print $6}')" \
            "$(get_bandwidth "LTE" "$(echo "$lte" | awk -F',' '{print $9}')")" \
            "$(get_bandwidth "LTE" "$(echo "$lte" | awk -F',' '{print $10}')")" \
            ""

        qmodem_add_current_band_cell "nsa" "NR" \
            "$(get_band "NR" "$(echo "$nr5g_nsa" | awk -F',' '{print $9}')")" \
            "$(echo "$nr5g_nsa" | awk -F',' '{print $8}')" \
            "NR-ARFCN" \
            "$(echo "$nr5g_nsa" | awk -F',' '{print $4}')" \
            "" \
            "$(get_bandwidth "NR" "$(echo "$nr5g_nsa" | awk -F',' '{print $10}')")" \
            "$(get_scs "$(echo "$nr5g_nsa" | awk -F',' '{print $16}' | sed 's/\r//g')")"

        json_close_array
    else
        response=$(echo "$response" | grep "+QENG:" | head -n 1)
        rat=$(echo "$response" | awk -F',' '{print $3}' | sed 's/"//g')

        case "$rat" in
            "NR5G-SA")
                network_mode="NR5G-SA"
                ;;
            "LTE"|"CAT-M"|"CAT-NB")
                network_mode="LTE"
                ;;
            "WCDMA")
                network_mode="WCDMA"
                ;;
            *)
                status="not_registered"
                network_mode="$rat"
                ;;
        esac

        json_add_string "status" "$status"
        json_add_string "network_mode" "$network_mode"
        json_add_array "cells"

        case "$rat" in
            "NR5G-SA")
                ca_response=$(cmd_qcainfo "$at_port")
                qmodem_add_current_band_cell "pcc" "NR" \
                    "$(get_band "NR" "$(echo "$response" | awk -F',' '{print $11}')")" \
                    "$(echo "$response" | awk -F',' '{print $10}')" \
                    "NR-ARFCN" \
                    "$(echo "$response" | awk -F',' '{print $8}')" \
                    "$(get_bandwidth "NR" "$(echo "$ca_response" | grep "+QCAINFO:" | grep "PCC" | awk -F',' '{print $3}' | head -n 1)")" \
                    "$(get_bandwidth "NR" "$(echo "$ca_response" | grep "+QCAINFO:" | grep "PCC" | awk -F',' '{print $3}' | head -n 1)")" \
                    "$(get_scs "$(echo "$response" | awk -F',' '{print $16}')")"

                ca_scc_info=$(echo "$ca_response" | grep "+QCAINFO:" | grep "SCC")
                while IFS= read -r scc_line; do
                    [ -z "$scc_line" ] && continue
                    qmodem_add_current_band_cell "scc" "NR" \
                        "$(echo "$scc_line" | awk -F',' '{print $4}' | sed 's/"//g' | awk -F'BAND ' '{print $2}')" \
                        "$(echo "$scc_line" | awk -F',' '{print $2}')" \
                        "NR-ARFCN" \
                        "$(echo "$scc_line" | awk -F',' '{print $6}')" \
                        "" \
                        "$(get_bandwidth "NR" "$(echo "$scc_line" | awk -F',' '{print $3}')")" \
                        ""
                done <<EOF
$ca_scc_info
EOF
                ;;
            "LTE"|"CAT-M"|"CAT-NB")
                qmodem_add_current_band_cell "pcc" "LTE" \
                    "$(get_band "LTE" "$(echo "$response" | awk -F',' '{print $10}')")" \
                    "$(echo "$response" | awk -F',' '{print $9}')" \
                    "EARFCN" \
                    "$(echo "$response" | awk -F',' '{print $8}')" \
                    "$(get_bandwidth "LTE" "$(echo "$response" | awk -F',' '{print $11}')")" \
                    "$(get_bandwidth "LTE" "$(echo "$response" | awk -F',' '{print $12}')")" \
                    ""
                ;;
            "WCDMA")
                qmodem_add_current_band_cell "pcc" "WCDMA" \
                    "" \
                    "$(echo "$response" | awk -F',' '{print $8}')" \
                    "UARFCN" \
                    "$(echo "$response" | awk -F',' '{print $9}')" \
                    "" \
                    "" \
                    ""
                ;;
        esac

        json_close_array
    fi

    json_close_object
}

get_current_band_capabilities()
{
    json_add_object "current_band_capabilities"
    json_add_boolean "supported" 1
    json_add_string "vendor" "$_Vendor"
    json_add_string "method" "AT+QENG=\"servingcell\""
    json_add_string "schema" "current_band"
    json_close_object
}

# get sim switch capabilities
sim_switch_capabilities(){
    local response slots slot

    response=$(cmd_quimslot_list_query "$at_port")
    slots=$(printf '%s\n' "$response" | awk -F':' '/\+(QUIMSLOT|QUSIMSLOT):/ {
        value=$2
        gsub(/[(),]/, " ", value)
        print value
        exit
    }')

    json_add_string "supportSwitch" "$([ -n "$slots" ] && echo 1 || echo 0)"
    json_add_array "simSlots"
    for slot in $slots; do
        case "$slot" in
            1|2) json_add_string "" "$slot" ;;
        esac
    done
    json_close_array
}

get_sim_slot(){
    sim_slot=$(quectel_get_sim_slot_value)
    json_add_string "sim_slot" "$sim_slot"
}

set_sim_slot(){
    local sim_slot_param="$1"
    local response current_slot attempt

    case "$sim_slot_param" in
        1|2) ;;
        *)
            json_add_string "result" "Invalid SIM slot: $sim_slot_param"
            return 1
            ;;
    esac

    response=$(cmd_quimslot_set "$at_port" "$sim_slot_param")
    json_add_string "result" "$response"
    printf '%s\n' "$response" | grep -q '^OK' || return 1

    attempt=0
    while [ "$attempt" -lt 5 ]; do
        current_slot=$(quectel_get_sim_slot_value)
        [ "$current_slot" = "$sim_slot_param" ] && {
            json_add_string "sim_slot" "$current_slot"
            return 0
        }
        attempt=$((attempt + 1))
        sleep 1
    done

    json_add_string "sim_slot" "$current_slot"
    return 1
}

get_usage_stats()
{
    local response marker tx_bytes rx_bytes updated_at

    if [ "$platform" = "unisoc" ]; then
        marker="+QGDCNT:"
        response=$(cmd_qgdcnt_query "$at_port")
        rx_bytes=$(echo "$response" | awk -F'[:, ]+' '/\+QGDCNT:/ {gsub(/\r/, "", $2); print $2; exit}')
        tx_bytes=$(echo "$response" | awk -F'[:, ]+' '/\+QGDCNT:/ {gsub(/\r/, "", $3); print $3; exit}')
    else
        marker="+QGDNRCNT:"
        response=$(cmd_qgdnrcnt_query "$at_port")
        tx_bytes=$(echo "$response" | awk -F'[:, ]+' '/\+QGDNRCNT:/ {gsub(/\r/, "", $2); print $2; exit}')
        rx_bytes=$(echo "$response" | awk -F'[:, ]+' '/\+QGDNRCNT:/ {gsub(/\r/, "", $3); print $3; exit}')
    fi

    case "$tx_bytes" in
        ''|*[!0-9]*)
            tx_bytes=0
            ;;
    esac
    case "$rx_bytes" in
        ''|*[!0-9]*)
            rx_bytes=0
            ;;
    esac

    if echo "$response" | grep -q "$marker"; then
        updated_at=$(date +%s)
        json_add_boolean "available" 1
        json_add_int "updated_at" "$updated_at"
        json_add_int "total_rx_bytes" "$rx_bytes"
        json_add_int "total_tx_bytes" "$tx_bytes"
    else
        json_add_boolean "available" 0
        json_add_int "updated_at" 0
        json_add_int "total_rx_bytes" 0
        json_add_int "total_tx_bytes" 0
    fi
}

write_usage_stats()
{
    local response

    if [ "$platform" = "unisoc" ]; then
        response=$(cmd_qaugdcnt_set "$at_port" "30")
    else
        response=$(cmd_qgdnrcnt_set "$at_port" "1")
    fi
    echo "$response" | grep -qi "OK"
}

clear_usage_stats()
{
    local response

    if [ "$platform" = "unisoc" ]; then
        response=$(cmd_qgdcnt_set "$at_port" "0")
    else
        response=$(cmd_qgdnrcnt_set "$at_port" "0")
    fi
    if echo "$response" | grep -qi "OK"; then
        json_add_boolean "result" 1
    else
        json_add_boolean "result" 0
    fi
}
