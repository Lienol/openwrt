#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>
# Copyright (C) 2025 Fujr <fjrcn@outlook.com>
_Vendor="quectel"
_Author="Siriling,Fujr"
_Maintainer="Fujr <fjrcn@outlook.com>"
source /usr/share/qmodem/generic.sh
debug_subject="quectel_ctrl"
#return raw data
get_imei(){
    at_command="AT+CGSN"
    imei=$(at $at_port $at_command | grep -o "[0-9]\{15\}")
    json_add_string "imei" "$imei"
}

#return raw data
set_imei(){
    local imei="$1"
    at_command="AT+EGMR=1,7,\"$imei\""
    res=$(at $at_port $at_command)
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
    at_command='AT+QCFG="usbnet"'
    local mode_num=$(at ${at_port} ${at_command} | grep "+QCFG:" | sed 's/+QCFG: "usbnet",//g' | sed 's/\r//g')
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
    at_command='AT+QCFG="usbnet",'${mode_num}
    res=$(at "${at_port}" "${at_command}")
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
    at_command='AT+QCFG="nwscanmode"'
    response=$(at ${at_port} ${at_command} | grep "+QCFG:" | awk -F'",' '{print $2}' | sed 's/\r//g' |grep -o "[0-9]")
    network_prefer_3g="0";
    network_prefer_4g="0";
    case "$response" in
        "0") network_prefer_3g="1"; network_prefer_4g="1" ;;
        "3") network_prefer_4g="1" ;;
    esac
}

get_network_prefer_nr()
{
    at_command='AT+QNWPREFCFG="mode_pref"'
    local response=$(at ${at_port} ${at_command} | grep "+QNWPREFCFG:" | awk -F',' '{print $2}' | sed 's/\r//g')
    
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
    at_command='AT+QCFG="nwscanmode",'${network_prefer_config}
    at "${at_port}" "${at_command}"

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
    at_command='AT+QNWPREFCFG="mode_pref",'${network_prefer_config}
    at "${at_port}" "${at_command}"
}

#获取电压
# $1:AT串口
get_voltage()
{
    at_command="AT+CBC"
	local voltage=$(at ${at_port} ${at_command} | grep "+CBC:" | awk -F',' '{print $3}' | sed 's/\r//g')
    [ -n "$voltage" ] && {
        add_plain_info_entry "voltage" "$voltage mV" "Voltage" 
    }
}

#获取温度
#return raw data
get_temperature()
{   
    #Temperature（温度）
    at_command="AT+QTEMP"
    local temp
    local line=1
    QTEMP=$(at ${at_port} ${at_command} | grep "+QTEMP:")
    for line in $( echo -e "$QTEMP" ); do
        templine=$(echo $line | grep -o "[0-9]\{1,3\}")
        for tmp in $(echo $templine); do
            [ "$tmp" -gt 0 ] && [ "$tmp" -lt 255 ] && temp=$tmp
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
    at_command="AT+CGMM"
    name=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    #Manufacturer（制造商）
    at_command="AT+CGMI"
    manufacturer=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    #Revision（固件版本）
    at_command="ATI"
    revision=$(at $at_port $at_command | grep "Revision:" | sed 's/Revision: //g' | sed 's/\r//g')
    # at_command="AT+CGMR"
    # revision=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    class="Base Information"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_temperature
    get_voltage
    get_connect_status
}


#SIM卡信息
sim_info()
{
    m_debug  "Quectel sim info"
    
    #SIM Slot（SIM卡卡槽）
    at_command="AT+QUIMSLOT?"
	sim_slot=$(at $at_port $at_command | grep "+QUIMSLOT:" | awk -F' ' '{print $2}' | sed 's/\r//g')

    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN"
	imei=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status_flag=$(at $at_port $at_command | sed -n '2p')
    sim_status=$(get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #ISP（互联网服务提供商）
    at_command="AT+COPS?"
    isp=$(at $at_port $at_command | sed -n '2p' | awk -F'"' '{print $2}')
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
    at_command="AT+CNUM"
	sim_number=$(at $at_port $at_command | sed -n '2p' | awk -F'"' '{print $4}')

    #IMSI（国际移动用户识别码）
    at_command="AT+CIMI"
	imsi=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #ICCID（集成电路卡识别码）
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

#网络信息
network_info()
{
    m_debug  "Quectel network info"

    #Connect Status（连接状态）

    #Network Type（网络类型）
    at_command="AT+QNWINFO"
    network_type=$(at ${at_port} ${at_command} | grep "+QNWINFO:" | awk -F'"' '{print $2}')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(at ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }

    #CSQ（信号强度）
    at_command="AT+CSQ"
    response=$(at ${at_port} ${at_command} | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

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
    at_command='AT+QNWCFG="nr5g_ambr"'
    response=$(at $at_port $at_command | grep "+QNWCFG:")
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
    at_command='AT+QNWCFG="up/down"'
    response=$(at $at_port $at_command | grep "+QNWCFG:" | sed 's/+QNWCFG: "up\/down",//g' | sed 's/\r//g')

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
    get_wcdma_config_command='AT+QNWPREFCFG="gw_band"'
    get_lte_config_command='AT+QNWPREFCFG="lte_band"'
    get_nsa_nr_config_command='AT+QNWPREFCFG="nsa_nr5g_band"'
    get_sa_nr_config_command='AT+QNWPREFCFG="nr5g_band"'
    wcdma_avalible_band="1,2,3,4,5,6,7,8,9,19"
    lte_avalible_band="1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,34,38,39,40,41,42,66,71"
    nsa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79,257,258,260,261"
    sa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79"
    [ -n $(uci -q get qmodem.$config_section.sa_band) ] && sa_nr_avalible_band=$(uci -q get qmodem.$config_section.sa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.nsa_band) ] && nsa_nr_avalible_band=$(uci -q get qmodem.$config_section.nsa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.lte_band) ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.wcdma_band) ] && wcdma_avalible_band=$(uci -q get qmodem.$config_section.wcdma_band | tr '/' ',')
    gw_band=$(at $at_port  $get_wcdma_config_command |grep -e "+QNWPREFCFG: " )
    lte_band=$(at $at_port $get_lte_config_command|grep -e "+QNWPREFCFG: ")
    nsa_nr_band=$(at $at_port $get_nsa_nr_config_command|grep -e "+QNWPREFCFG: ")
    sa_nr_band=$(at $at_port  $get_sa_nr_config_command|grep -e "+QNWPREFCFG: ")
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
    get_wcdma_config_command='AT+QNWPREFCFG="gw_band"'
    get_lte_config_command='AT+QNWPREFCFG="lte_band"'
    get_nsa_nr_config_command='AT+QNWPREFCFG="nsa_nr5g_band"'
    get_sa_nr_config_command='AT+QNWPREFCFG="nr5g_band"'
    wcdma_avalible_band="1,2,3,4,5,6,7,8,9,19"
    lte_avalible_band="1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,34,38,39,40,41,42,66,71"
    nsa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79,257,258,260,261"
    sa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79"
    [ -n $(uci -q get qmodem.$config_section.sa_band) ] && sa_nr_avalible_band=$(uci -q get qmodem.$config_section.sa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.nsa_band) ] && nsa_nr_avalible_band=$(uci -q get qmodem.$config_section.nsa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.lte_band) ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.wcdma_band) ] && wcdma_avalible_band=$(uci -q get qmodem.$config_section.wcdma_band | tr '/' ',')
    gw_band=$(at $at_port  $get_wcdma_config_command |grep -e "+QNWPREFCFG: " )
    lte_band=$(at $at_port $get_lte_config_command|grep -e "+QNWPREFCFG: ")
    nsa_nr_band=$(at $at_port $get_nsa_nr_config_command|grep -e "+QNWPREFCFG: ")
    sa_nr_band=$(at $at_port  $get_sa_nr_config_command|grep -e "+QNWPREFCFG: ")
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
    get_wcdma_config_command='AT+QNWPREFCFG="gw_band"'
    get_lte_config_command='AT+QNWPREFCFG="lte_band"'
    get_nsa_nr_config_command='AT+QNWPREFCFG="nsa_nr5g_band"'
    get_sa_nr_config_command='AT+QNWPREFCFG="nr5g_band"'
    wcdma_avalible_band="1,2,3,4,5,6,7,8,9,19"
    lte_avalible_band="1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,34,38,39,40,41,42,66,71"
    nsa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79,257,258,260,261"
    sa_nr_avalible_band="1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79"
    [ -n $(uci -q get qmodem.$config_section.sa_band) ] && sa_nr_avalible_band=$(uci -q get qmodem.$config_section.sa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.nsa_band) ] && nsa_nr_avalible_band=$(uci -q get qmodem.$config_section.nsa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.lte_band) ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.wcdma_band) ] && wcdma_avalible_band=$(uci -q get qmodem.$config_section.wcdma_band | tr '/' ',')
    gw_band=$(at $at_port  $get_wcdma_config_command |grep -e "+QNWPREFCFG: " )
    lte_band=$(at $at_port $get_lte_config_command|grep -e "+QNWPREFCFG: ")
    nsa_nr_band=$(at $at_port $get_nsa_nr_config_command|grep -e "+QNWPREFCFG: ")
    sa_nr_band=$(at $at_port  $get_sa_nr_config_command|grep -e "+QNWPREFCFG: ")
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
    local commamd="AT+QCFG=\"band\""
    LTE_LOCK=$(at $at_port  "$commamd" |grep '+QCFG:'| awk -F, '{print $3}' | sed 's/"//g' | tr '[:a-z:]' '[:A-Z:]')
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
    res=$(at $at_port 'AT+QCFG="band",0,'${hex}',0'   2>&1 > /dev/null)
}

set_lockband_nr(){
    lock_band=$(echo $lock_band | tr ',' ':')
    case "$band_class" in
        "UMTS") 
            at_command="AT+QNWPREFCFG=\"gw_band\",$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "LTE") 
            at_command="AT+QNWPREFCFG=\"lte_band\",$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "NR_NSA")
            at_command="AT+QNWPREFCFG=\"nsa_nr5g_band\",$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "NR")
            at_command="AT+QNWPREFCFG=\"nr5g_band\",$lock_band"
            res=$(at $at_port $at_command)
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
    local at_command='AT+QENG="neighbourcell"'
    nr_lock_check="AT+QNWLOCK=\"common/5g\""
    lte_lock_check="AT+QNWLOCK=\"common/4g\""
    lte_status=$(at $at_port $lte_lock_check | grep "+QNWLOCK:")
    lte_lock_status=$(echo $lte_status | awk -F',' '{print $2}' | sed 's/\r//g')
    lte_lock_freq=$(echo $lte_status | awk -F',' '{print $3}' | sed 's/\r//g')
    lte_lock_pci=$(echo $lte_status | awk -F',' '{print $4}' | sed 's/\r//g')
    nr_status=$(at $at_port $nr_lock_check | grep "+QNWLOCK:")
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


    at $at_port $at_command > /tmp/neighborcell
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
    local at_command='AT+QENG="neighbourcell"'
    lte_lock_check="AT+QNWLOCK=\"common/lte\""
    lte_status=$(at $at_port $lte_lock_check | grep "+QNWLOCK:")
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
    at $at_port $at_command > /tmp/neighborcell
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
    local at_command='AT+QENG="neighbourcell"'
    nr_lock_check="AT+QNWLOCK=\"common/5g\""
    lte_lock_check="AT+QNWLOCK=\"common/lte\""
    lte_status=$(at $at_port $lte_lock_check | grep "+QNWLOCK:")
    lte_lock_freq=$(echo $lte_status | awk -F',' '{print $2}')
    lte_lock_pci=$(echo $lte_status | awk -F',' '{print $3}')
    nr_status=$(at $at_port $nr_lock_check | grep "+QNWLOCK:")
    nr_lock_pci=$(echo $nr_status | awk -F',' '{print $2}')
    nr_lock_freq=$(echo $nr_status | awk -F',' '{print $3}')
    [ -n "$lte_lock_freq" ] && lte_lock_status="locked"
    [ -n "$nr_lock_freq" ] && nr_lock_status="locked"


    at $at_port $at_command > /tmp/neighborcell
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
    json_close_object
}

lockcell_qualcomm(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        unlock4g="AT+QNWLOCK=\"common/4g\",0"
        unlocknr="AT+QNWLOCK=\"common/5g\",0"
        res1=$(at $at_port $unlocknr)
        res2=$(at $at_port $unlock4g)
        res=$res1,$res2
    else
        lock4g="AT+QNWLOCK=\"common/4g\",1,$arfcn,$pci"
        locknr="AT+QNWLOCK=\"common/5g\",$pci,$arfcn,$(get_scs $scs),$band"
        if [ $rat = "1" ]; then
            res=$(at $at_port $locknr)
        else
            res=$(at $at_port $lock4g)
        fi
    fi
   
}

lockcell_unisoc(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        unlock4g="AT+QNWLOCK=\"common/lte\",0"
        unlocknr="AT+QNWLOCK=\"common/5g\",0"
        res1=$(at $at_port $unlocknr)
        res2=$(at $at_port $unlock4g)
        res=$res1,$res2
    else
        lock4g="AT+QNWLOCK=\"common/lte\",1,$arfcn,$pci"
        locknr="AT+QNWLOCK=\"common/5g\",1,$arfcn,$pci"
        if [ $rat = "1" ]; then
            res=$(at $at_port $locknr)
        else
            res=$(at $at_port $lock4g)
        fi
    fi
}

lockcell_lte(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        unlocklte="AT+QNWLOCK=\"common/lte\",0"
        res1=$(at $at_port $unlocklte)
        res=$res1
    else
        if [ -z $pci ] && [ -n $arfcn ]; then
            locklte="AT+QNWLOCK=\"common/lte\",1,$arfcn,0"
        elif [ -n $pci ] && [ -n $arfcn ]; then
            locklte="AT+QNWLOCK=\"common/lte\",2,$arfcn,$pci"
        fi
        res=$(at $at_port $locklte)
    fi
}

unlockcell(){
    unlock4g="AT+QNWLOCK=\"common/4g\",0"
    unlocknr="AT+QNWLOCK=\"common/5g\",0"
    res2=$(at $1 $unlocknr)
    res3=$(at $1 $unlock4g)
}

unlockcell_unisoc(){
    unlock4g="AT+QNWLOCK=\"common/lte\",0"
    unlocknr="AT+QNWLOCK=\"common/5g\",0"
    res2=$(at $1 $unlocknr)
    res3=$(at $1 $unlock4g)
}

unlockcell_lte(){
    unlocklte="AT+QNWLOCK=\"common/lte\",0"
    res1=$(at $1 $unlocklte)
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
        res=$(at $at_port $lock4g)
        echo $lock4g res:$res
        ;;
    1)
        locknr="AT+QNWLOCK=\"common/5g\",1,$arfcn,$pci"
        res=$(at $at_port $locknr)
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
        res=$(at $at_port $locklte)
    elif [ "$cell_type" = "1" ]; then
        locknr="AT+QNWLOCK=\"common/5g\",1,$pci,$arfcn,$scs,$nrband"
        echo $locknr
        res=$(at $at_port $locknr)
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
    res=$(at $at_port $locklte)
}

lockarfn_lte(){
    local at_port="$1"
    local cell_type="$2"
    local arfcn="$3"
    local pci="$4"
    local scs="$5"
    local nrband="$6"
    locklte="AT+QNWLOCK=\"common/lte\",1,$arfcn,0"
    res=$(at $at_port $locklte)
}


#UL_bandwidth
# $1:上行带宽数字
get_bandwidth()
{
    local network_type="$1"
    local bandwidth_num="$2"

    local bandwidth
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

    at_command='AT+QENG="servingcell"'
    response=$(at $at_port $at_command)
    
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
        endc_lte_freq_band_ind=$(get_band "LTE" $endc_lte_freq_band_ind_num)
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
                nr_duplex_mode=$(echo "$response" | awk -F',' '{print $4}' | sed 's/"//g')
                nr_mcc=$(echo "$response" | awk -F',' '{print $5}')
                nr_mnc=$(echo "$response" | awk -F',' '{print $6}')
                nr_cell_id=$(echo "$response" | awk -F',' '{print $7}')
                nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                nr_tac=$(echo "$response" | awk -F',' '{print $9}')
                nr_arfcn=$(echo "$response" | awk -F',' '{print $10}')
                nr_band_num=$(echo "$response" | awk -F',' '{print $11}')
                nr_band=$(get_band "NR" $nr_band_num)
                nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $12}')
                nr_dl_bandwidth=$(get_bandwidth "NR" $nr_dl_bandwidth_num)
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
    "NR5G-SA Mode")
        add_plain_info_entry "MMC" "$nr_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$nr_mnc" "Mobile Network Code"
        add_plain_info_entry "Duplex Mode" "$nr_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$nr_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$nr_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "TAC" "$nr_tac" "Tracking area code of cell served by neighbor Enb"
        add_plain_info_entry "ARFCN" "$nr_arfcn" "Absolute Radio-Frequency Channel Number"
        add_plain_info_entry "Band" "$nr_band" "Band"
        add_plain_info_entry "DL Bandwidth" "$nr_dl_bandwidth" "DL Bandwidth"
        add_bar_info_entry "RSRP" "$nr_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$nr_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "SINR" "$nr_sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
        add_plain_info_entry "RxLev" "$nr_rxlev" "Received Signal Level"
        add_plain_info_entry "SCS" "$nr_scs" "SCS"
        add_plain_info_entry "Srxlev" "$nr_srxlev" "Serving Cell Receive Level"
        
        ;;
    "EN-DC Mode")
        add_plain_info_entry "LTE" "LTE" ""
        add_plain_info_entry "MCC" "$endc_lte_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$endc_lte_mnc" "Mobile Network Code"
        add_plain_info_entry "Duplex Mode" "$endc_lte_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$endc_lte_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$endc_lte_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "EARFCN" "$endc_lte_earfcn" "E-UTRA Absolute Radio Frequency Channel Number"
        add_plain_info_entry "Freq band indicator" "$endc_lte_freq_band_ind" "Freq band indicator"
        add_plain_info_entry "Band" "$endc_lte_band" "Band"
        add_plain_info_entry "UL Bandwidth" "$endc_lte_ul_bandwidth" "UL Bandwidth"
        add_plain_info_entry "DL Bandwidth" "$endc_lte_dl_bandwidth" "DL Bandwidth"
        add_plain_info_entry "TAC" "$endc_lte_tac" "Tracking area code of cell served by neighbor Enb"
        add_bar_info_entry "RSRP" "$endc_lte_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$endc_lte_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "RSSI" "$endc_lte_rssi" "Received Signal Strength Indicator" -120 -20 dBm
        add_bar_info_entry "SINR" "$endc_lte_sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
        add_plain_info_entry "RxLev" "$endc_lte_rxlev" "Received Signal Level"
        add_plain_info_entry "RSSNR" "$endc_lte_rssnr" "Radio Signal Strength Noise Ratio"
        add_plain_info_entry "CQI" "$endc_lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$endc_lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$endc_lte_srxlev" "Serving Cell Receive Level"
        add_plain_info_entry NR5G-NSA "NR5G-NSA" ""
        add_plain_info_entry "MCC" "$endc_nr_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$endc_nr_mnc" "Mobile Network Code"
        add_plain_info_entry "Physical Cell ID" "$endc_nr_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "ARFCN" "$endc_nr_arfcn" "Absolute Radio-Frequency Channel Number"
        add_plain_info_entry "Band" "$endc_nr_band" "Band"
        add_plain_info_entry "DL Bandwidth" "$endc_nr_dl_bandwidth" "DL Bandwidth"
        add_bar_info_entry "RSRP" "$endc_nr_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$endc_nr_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "SINR" "$endc_nr_sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
        add_plain_info_entry "SCS" "$endc_nr_scs" "SCS"
        ;;
    "LTE Mode")
        add_plain_info_entry "MCC" "$lte_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$lte_mnc" "Mobile Network Code"
        add_plain_info_entry "Duplex Mode" "$lte_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$lte_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$lte_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "EARFCN" "$lte_earfcn" "E-UTRA Absolute Radio Frequency Channel Number"
        add_plain_info_entry "Freq band indicator" "$lte_freq_band_ind" "Freq band indicator"
        add_plain_info_entry "Band" "$lte_band" "Band"
        add_plain_info_entry "UL Bandwidth" "$lte_ul_bandwidth" "UL Bandwidth"
        add_plain_info_entry "DL Bandwidth" "$lte_dl_bandwidth" "DL Bandwidth"
        add_plain_info_entry "TAC" "$lte_tac" "Tracking area code of cell served by neighbor Enb"
        add_bar_info_entry "RSRQ" "$lte_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "RSSI" "$lte_rssi" "Received Signal Strength Indicator" -120 -20 dBm
        add_bar_info_entry "SINR" "$lte_sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
        add_plain_info_entry "RxLev" "$lte_rxlev" "Received Signal Level"
        add_plain_info_entry "RSSNR" "$lte_rssnr" "Radio Signal Strength Noise Ratio"
        add_plain_info_entry "CQI" "$lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$lte_srxlev" "Serving Cell Receive Level"
        
        ;;
    "WCDMA Mode")
        add_plain_info_entry "MCC" "$wcdma_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$wcdma_mnc" "Mobile Network Code"
        add_plain_info_entry "LAC" "$wcdma_lac" "Location Area Code"
        add_plain_info_entry "Cell ID" "$wcdma_cell_id" "Cell ID"
        add_plain_info_entry "UARFCN" "$wcdma_uarfcn" "UTRA Absolute Radio Frequency Channel Number"
        add_plain_info_entry "PSC" "$wcdma_psc" "Primary Scrambling Code"
        add_plain_info_entry "RAC" "$wcdma_rac" "Routing Area Code"
        add_plain_info_entry "Band" "$wcdma_band" "Band"
        add_bar_info_entry "RSCP" "$wcdma_rscp" "Received Signal Code Power" -120 -25 dBm
        add_plain_info_entry "Ec/Io" "$wcdma_ecio" "Ec/Io"
        add_plain_info_entry "Ec/No" "$wcdma_ecno" "Ec/No"
        add_plain_info_entry "Physical Channel" "$wcdma_phych" "Physical Channel"
        add_plain_info_entry "Spreading Factor" "$wcdma_sf" "Spreading Factor"
        add_plain_info_entry "Slot" "$wcdma_slot" "Slot"
        add_plain_info_entry "Speech Code" "$wcdma_speech_code" "Speech Code"
        add_plain_info_entry "Compression Mode" "$wcdma_com_mod" "Compression Mode"
        add_plain_info_entry "RxLev" "$wcdma_rxlev" "RxLev"
        
        ;;
    esac
}
