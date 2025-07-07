#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>
# Copyright (C) 2025 Fujr <fjrcn@outlook.com>
_Vendor="fibocom"
_Author="Siriling Fujr"
_Maintainer="Fujr <fjrcn@outlook.com>"
source /usr/share/qmodem/generic.sh

vendor_get_disabled_features(){
    json_add_string "" ""
}

debug_subject="fibocom_ctrl"
#获取拨号模式
# $1:AT串口
# $2:平台
get_mode()
{
    local at_command="AT+GTUSBMODE?"
    local mode_num=$(at ${at_port} ${at_command} | grep "+GTUSBMODE:" | sed 's/+GTUSBMODE: //g' | sed 's/\r//g')

    local mode
    case "$platform" in
        "lte"|\
        "qualcomm")
            case "$mode_num" in
                "17") mode="qmi" ;; #-
                "31") mode="qmi" ;; #-
                "32") mode="qmi" ;;
                "34") mode="qmi" ;;
                # "32") mode="gobinet" ;;
                "18") mode="ecm" ;;
                "23") mode="ecm" ;; #-
                "33") mode="ecm" ;; #-
                "35") mode="ecm" ;; #-
                "29") mode="mbim" ;; #-
                "30") mode="mbim" ;;
                "24") mode="rndis" ;;
                "18") mode="ncm" ;;
                *) mode="$mode_num" ;;
            esac
        ;;
        "unisoc")
            case "$mode_num" in
                "34") mode="ecm" ;;
                "35") mode="ecm" ;; #-
                "40") mode="mbim" ;;
                "41") mode="mbim" ;; #-
                "38") mode="rndis" ;;
                "39") mode="rndis" ;; #-
                "36") mode="ncm" ;;
                "37") mode="ncm" ;; #-
                *) mode="$mode_num" ;;
            esac
        ;;
        "mediatek")
            case "$mode_num" in
                "29") mode="mbim" ;;
                "40") mode="rndis" ;; #-
                "41") mode="rndis" ;;
                *) mode="$mode_num" ;;
            esac
            driver=$(get_driver)
            case "$driver" in
                "mtk_pcie")
                    mode="mbim" ;;
            esac
        ;;
        *)
            mode="$mode_num"
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
    local mode_config=$1
    case "$platform" in
        "qualcomm")
            case "$mode_config" in
                "qmi") mode_num="32" ;;
                # "gobinet")  mode_num="32" ;;
                "ecm") mode_num="18" ;;
                "mbim") mode_num="30" ;;
                "rndis") mode_num="24" ;;
                "ncm") mode_num="18" ;;
                *) mode_num="32" ;;
            esac
        ;;
        "unisoc")
            case "$mode_config" in
                "ecm") mode_num="34" ;;
                "mbim") mode_num="40" ;;
                "rndis") mode_num="38" ;;
                "ncm") mode_num="36" ;;
                *) mode_num="34" ;;
            esac
        ;;
        "mediatek")
            case "$mode_config" in
                # "mbim") mode_num="40" ;;
                # "rndis") mode_num="40" ;;
                "rndis") mode_num="41" ;;
                *) mode_num="41" ;;
            esac
        ;;
        "lte")
            case "$mode_config" in
                    "qmi") mode_num="17" ;;
                    "ecm") mode_num="18" ;;
                    "rndis") mode_num="24" ;;
                    "ncm") mode_num="18" ;;
                    *) mode_num="32" ;;
                esac
            ;;
        *)
            mode_num="32"
        ;;
    esac

    #设置模组
    at_command="AT+GTUSBMODE=${mode_num}"
    res=$(at "${at_port}" "${at_command}")
    json_select "result"
    json_add_string "set_mode" "$res"
    json_add_string "mode" "$mode_config"
    json_close_object
}

#获取网络偏好
get_network_prefer_nr()
{
    at_command="AT+GTACT?"
    local network_prefer_num=$(at $at_port $at_command | grep "+GTACT:" | awk -F',' '{print $1}' | sed 's/+GTACT: //g')
    
    local network_prefer_3g="0";
    local network_prefer_4g="0";
    local network_prefer_5g="0";

    #匹配不同的网络类型
    case "$network_prefer_num" in
        "1") network_prefer_3g="1" ;;
        "2") network_prefer_4g="1" ;;
        "4")
            network_prefer_3g="1"
            network_prefer_4g="1"
        ;;
        "10")
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
        ;;
        "14") network_prefer_5g="1" ;;
        "16")
            network_prefer_3g="1"
            network_prefer_5g="1"
        ;;
        "17")
            network_prefer_4g="1"
            network_prefer_5g="1"
        ;;
        "20")
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
        ;;
        *)
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
        ;;
    esac

    json_add_object network_prefer
    json_add_string 3G $network_prefer_3g
    json_add_string 4G $network_prefer_4g
    json_add_string 5G $network_prefer_5g
    json_close_array
}

#设置网络偏好
# $1:网络偏好配置
set_network_prefer_nr()
{
    network_prefer_3g=$(echo $1 |jq -r 'contains(["3G"])')
    network_prefer_4g=$(echo $1 |jq -r 'contains(["4G"])')
    network_prefer_5g=$(echo $1 |jq -r 'contains(["5G"])')
    count=$(echo $1 |jq -r 'length')
    case "$count" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                network_prefer_num="true"
            elif [ "$network_prefer_4g" = "true" ]; then
                network_prefer_num="2"
            elif [ "$network_prefer_5g" = "true" ]; then
                network_prefer_num="14"
            fi
        ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                network_prefer_num="4"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_num="16"
            elif [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_num="17"
            fi
        ;;
        "3") network_prefer_num="20" ;;
        *) network_prefer_num="10" ;;
    esac

    #设置模组
    at_command="AT+GTACT=$network_prefer_num,6,3"
    res=$(at $at_port "$at_command")
    json_select_object "result"
    json_add_string "status" "$res"
    json_close_object
}

#获取网络偏好
get_network_prefer_lte()
{
    at_command="AT+GTACT?"
    local network_prefer_num=$(at $at_port $at_command | grep "+GTACT:" | awk -F',' '{print $1}' | sed 's/+GTACT: //g')
    
    local network_prefer_3g="0";
    local network_prefer_4g="0";

    #匹配不同的网络类型
    case "$network_prefer_num" in
        "1") network_prefer_3g="1" ;;
        "2") network_prefer_4g="1" ;;
        "4")
            network_prefer_3g="1"
            network_prefer_4g="1"
        ;;
        "10")
            network_prefer_3g="1"
            network_prefer_4g="1"
        ;;
        *)
            network_prefer_3g="1"
            network_prefer_4g="1"
        ;;
    esac

    json_add_object network_prefer
    json_add_string 3G $network_prefer_3g
    json_add_string 4G $network_prefer_4g
    json_close_array
}

#设置网络偏好
# $1:网络偏好配置
set_network_prefer_lte()
{
    network_prefer_3g=$(echo $1 |jq -r 'contains(["3G"])')
    network_prefer_4g=$(echo $1 |jq -r 'contains(["4G"])')
    count=$(echo $1 |jq -r 'length')
    case "$count" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                network_prefer_num="1"
            elif [ "$network_prefer_4g" = "true" ]; then
                network_prefer_num="2"
            fi
        ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                network_prefer_num="10"
            fi
        ;;
        *) network_prefer_num="10" ;;
    esac

    #设置模组
    at_command="AT+GTACT=$network_prefer_num"
    res=$(at $at_port "$at_command")
    json_select_object "result"
    json_add_string "status" "$res"
    json_add_string raw "$1"
    json_add_string "network_prefer_num" "$network_prefer_num"
    json_add_string "network_prefer_3g" "$network_prefer_3g"
    json_add_string "network_prefer_4g" "$network_prefer_4g"
    json_close_object
}

get_network_prefer()
{
    case $platform in
        "qualcomm")
            get_network_prefer_nr
            ;;
        "unisoc")
            get_network_prefer_nr
            ;;
        "mediatek")
            get_network_prefer_nr
            ;;
        "lte")
            get_network_prefer_lte
            ;;
        *)
            get_network_prefer_nr
            ;;
    esac
}

set_network_prefer()
{
    case $platform in
        "qualcomm")
            set_network_prefer_nr $1
            ;;
        "unisoc")
            set_network_prefer_nr $1
            ;;
        "mediatek")
            set_network_prefer_nr $1
            ;;
        "lte")
            set_network_prefer_lte $1
            ;;
        *)
            set_network_prefer_nr $1
            ;;
    esac
}
#获取电压
# $1:AT串口
get_voltage()
{
    at_command="AT+CBC"
	local voltage=$(at $at_port $at_command | grep "+CBC:" | awk -F',' '{print $2}' | sed 's/\r//g')
    [ -n $voltage ] && {
        voltage="${voltage}mV"
    }
    add_plain_info_entry "voltage" "$voltage" "Voltage"
}

#获取温度
# $1:AT串口
get_temperature()
{
    #Temperature（温度）
    at_command="AT+MTSM=1,6"
	response=$(at $at_port $at_command | grep "+MTSM: " | sed 's/+MTSM: //g' | sed 's/\r//g')

    [ -z "$response" ] && {
        #Fx160及以后型号
        at_command="AT+GTLADC"
	    response=$(at $at_port $at_command | grep "cpu" | awk -F' ' '{print $2}' | sed 's/\r//g')
        response="${response:0:2}"
    }

    [ -z "$response" ] && {
        #联发科平台
        at_command="AT+GTSENRDTEMP=1"
        response=$(at $at_port $at_command | grep "+GTSENRDTEMP: " | awk -F',' '{print $2}' | sed 's/\r//g')
        response="${response:0:2}"
    }

    local temperature
    [ -n "$response" ] && {
        temperature="${response}$(printf "\xc2\xb0")C"
    }

    add_plain_info_entry "temperature" "$temperature" "Temperature"
}



#基本信息
base_info()
{
    m_debug "Fibocom base info"

    #Name（名称）
    at_command="AT+CGMM?"
    name=$(at $at_port $at_command | grep "+CGMM: " | awk -F'"' '{print $2}')
    #Manufacturer（制造商）
    at_command="AT+CGMI?"
    manufacturer=$(at $at_port $at_command | grep "+CGMI: " | awk -F'"' '{print $2}')
    #Revision（固件版本）
    at_command="AT+CGMR?"
    revision=$(at $at_port $at_command | grep "+CGMR: " | awk -F'"' '{print $2}')

    class="Base Information"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_temperature
    get_voltage
    get_connect_status
}

#获取SIM卡状态
# $1:SIM卡状态标志


#SIM卡信息
sim_info()
{
    m_debug "Fibocom sim info"
    
    #SIM Slot（SIM卡卡槽）
    at_command="AT+GTDUALSIM?"
	sim_slot=$(at ${at_port} ${at_command} | grep "+GTDUALSIM" | awk -F'"' '{print $2}' | sed 's/SUB//g')

    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN?"
	imei=$(at ${at_port} ${at_command} | grep "+CGSN: " | awk -F'"' '{print $2}')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status_flag=$(at ${at_port} ${at_command} | grep "+CPIN: ")
    [ -z "$sim_status_flag" ] && {
        sim_status_flag=$(at ${at_port} ${at_command} | grep "+CME")
    }
    sim_status=$(get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #ISP（互联网服务提供商）
    at_command="AT+COPS?"
    isp=$(at ${at_port} ${at_command} | grep "+COPS" | awk -F'"' '{print $2}')
    # if [ "$isp" = "CHN-CMCC" ] || [ "$isp" = "CMCC" ]|| [ "$isp" = "46000" ]; then
    #     isp="中国移动"
    # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "UNICOM" ] || [ "$isp" = "46001" ]; then
    #     isp="中国联通"
    # elif [ "$isp" = "CHN-CT" ] || [ "$isp" = "CT" ] || [ "$isp" = "46011" ]; then
    #     isp="中国电信"
    # fi

    #SIM Number（SIM卡号码，手机号）
    at_command="AT+CNUM"
	sim_number=$(at ${at_port} ${at_command} | grep "+CNUM: " | awk -F'"' '{print $2}')
    [ -z "$sim_number" ] && {
        sim_number=$(at ${at_port} ${at_command} | grep "+CNUM: " | awk -F'"' '{print $4}')
    }
	
    #IMSI（国际移动用户识别码）
    at_command="AT+CIMI?"
    imsi=$(at ${at_port} ${at_command} | grep "+CIMI: " | awk -F' ' '{print $2}' | sed 's/"//g' | sed 's/\r//g')
	[ -z "$sim_number" ] && {
        imsi=$(at ${at_port} ${at_command} | grep "+CIMI: " | awk -F'"' '{print $2}')
    }

    #ICCID（集成电路卡识别码）
    at_command="AT+ICCID"
	iccid=$(at ${at_port} ${at_command} | grep -o "+ICCID:[ ]*[-0-9]\+" | grep -o "[-0-9]\{1,4\}")
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

get_imei()
{
    at_command="AT+CGSN?"
    imei=$(at ${at_port} ${at_command} | grep "+CGSN: " | awk -F'"' '{print $2}'| grep -E '[0-9]+')
    json_add_string "imei" "$imei"
}

set_imei()
{
    imei="$1"
    case "$platform" in
        "qualcomm")
            at_command="AT+GTSN=1,7,\"$imei\""
            ;;
        "unisoc")
            at_command="AT+GTSN=1,7,\"$imei\""
            ;;
        "mediatek")
            at_command="AT+EGMREXT=1,7,\"$imei\""
            ;;
        "lte")
            at_command="AT+LCTSN=1,7,\"$imei\""
            ;;
        *)
            at_command="AT+GTSN=1,7,\"$imei\""
            ;;
    esac
    #重定向stderr
    res=$(at ${at_port} "${at_command}") 2>&1
    json_select "result"
    json_add_string "set_imei" "$res"
    json_close_object
    get_imei

}




#网络信息
network_info()
{
    m_debug "Fibocom network info"

    #Network Type（网络类型）
    at_command="AT+PSRAT?"
    network_type=$(at ${at_port} ${at_command} | grep "+PSRAT:" | sed 's/+PSRAT: //g' | sed 's/\r//g')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(at ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }

    #设置网络类型为5G时，信号强度指示用RSRP代替
    # at_command="AT+GTCSQNREN=1"
    # at $at_port $at_command

    #CSQ（信号强度）
    at_command="AT+CSQ"
    response=$(at $at_port $at_command | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    #RSSI（4G信号强度指示）
    # rssi_num=$(echo $response | awk -F',' '{print $1}')
    # rssi=$(get_rssi $rssi_num)
    #BER（4G信道误码率）
    # ber=$(echo $response | awk -F',' '{print $2}')

    # #PER（信号强度）
    # if [ -n "$csq" ]; then
    #     per=$(($csq * 100/31))"%"
    # fi

    #速率统计
    at_command="AT+GTSTATIS?"
    response=$(at $at_port $at_command | grep "+GTSTATIS:" | sed 's/+GTSTATIS: //g' | sed 's/\r//g')

    #当前上传速率（单位，Byte/s）
    tx_rate=$(echo $response | awk -F',' '{print $2}')

    #当前下载速率（单位，Byte/s）
    rx_rate=$(echo $response | awk -F',' '{print $1}')
    class="Network Information"
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
    add_plain_info_entry "CQI UL" "$cqi_ul" "Channel Quality Indicator for Uplink"
    add_plain_info_entry "CQI DL" "$cqi_dl" "Channel Quality Indicator for Downlink"
    add_plain_info_entry "AMBR UL" "$ambr_ul" "Access Maximum Bit Rate for Uplink"
    add_plain_info_entry "AMBR DL" "$ambr_dl" "Access Maximum Bit Rate for Downlink"
    add_speed_entry rx $rx_rate
    add_speed_entry tx $tx_rate
}

get_lockband(){
    json_add_object "lockband"
    case $platform in
        "qualcomm")
            get_lockband_nr
            ;;
        "unisoc")
            get_lockband_nr
            ;;
        "mediatek")
            get_lockband_nr
            ;;
        "lte")
            get_lockband_lte
            ;;
        *)
            get_lockband_nr
            ;;
    esac
    json_close_object
}

#锁频信息
get_lockband_nr()
{
    m_debug "Fibocom get lockband info"
    get_lockband_config_command="AT+GTACT?"
    get_available_band_command="AT+GTACT=?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command)
    get_available_band_res=$(at $at_port $get_available_band_command)
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
    json_close_object
    json_close_object
    json_add_object "NR"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    index=0
    for i in $(echo "$get_available_band_res"| sed 's/\r//g' | awk -F"[()]" '{for(j=8; j<NF;j+=2) if ($j) print $j; else print 0;}' ); do
        case $index in
            0) 
            #"gsm"
            ;;
            1) 
            #"umts_band" 
            for j in $(echo "$i" | awk -F"," '{for(k=1; k<=NF; k++) print $k}'); do
                json_select "UMTS"
                json_select "available_band"
                add_avalible_band_entry  "$j" "UMTS_$j"
                json_select ".."
                json_select ".."
            done
            ;;
            2) 
            #"LTE" "$i" 
            for j in $(echo "$i" | awk -F"," '{for(k=1; k<=NF; k++) print $k}'); do
                trim_first_letter=$(echo "$j" | sed 's/^.//')
                json_select "LTE"
                json_select "available_band"
                add_avalible_band_entry  "$j" "LTE_$trim_first_letter"
                json_select ".."
                json_select ".."
            done
            ;;
            3)  
            #"cdma_band"
            ;;
            4) 
            #"evno"
            ;;
            5)
            #"nr5g"
            for j in $(echo "$i" | awk -F"," '{for(k=1; k<=NF; k++) print $k}'); do
                trim_first_letter=$(echo "$j" | sed 's/^.//')
                json_select "NR"
                json_select "available_band"
                add_avalible_band_entry  "$j" "NR_$trim_first_letter"
                json_select ".."
                json_select ".."
            done
            ;;
        esac
        index=$((index+1))
    done
    
    for i in $(echo "$get_lockband_config_res" | sed 's/\r//g' | awk -F"," '{for(k=4; k<=NF; k++) print $k}' ); do
        # i 0,100 UMTS
        # i 100,5000 LTE
        # i 5000,10000 NR
        if [ -z "$i" ]; then
            continue
        fi
        if [ $i -lt 100 ]; then
            json_select "UMTS"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ".."
            json_select ".."
        elif [ $i -lt 500 ]; then
            json_select "LTE"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ".."
            json_select ".."
        else
            json_select "NR"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ".."
            json_select ".."
        fi
    done
    json_close_array
}

#锁频信息
get_lockband_lte()
{
    m_debug "Fibocom get lockband info"
    get_lockband_config_command="AT+GTACT?"
    get_available_band_command="AT+GTACT=?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command |grep GTACT: | sed 's/\r//g')
    get_available_band_res=$(at $at_port $get_available_band_command |grep GTACT: | sed 's/\r//g')
    json_add_object "UMTS"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    json_add_object "LTE"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    #+GTACT: (1,2,4,10),(2,3),(),0,1,3,5,8,101,103,105,107,108,120,128,132,138,140,141
    #means avalible band = 1,3,5,8,101,103,105,107,108,120,128,132,138,140,141
    lockband_type=$(echo "$get_lockband_config_res" | cut -d: -f2 | cut -d, -f1|tr -d ' ')
    first_bandcfg=$(echo "$get_lockband_config_res" | cut -d, -f2)
    [ "$first_bandcfg" -eq 0 ] && select_all_band=1 || select_all_band=0
    [ "$lockband_type" -lt 10 ] && seq=2 || seq=4
    for i in $(echo "$get_available_band_res"| sed 's/\r//g' | awk -F"," '{for(j=9; j<=NF;j+=1) if ($j) print $j; else print 0;}' ); do
        if [ -z "$i" ]; then
            continue
        fi
        # $i < 100 UMTS, i >= 100 LTE
        if [ $i -lt 100 ]; then
            json_select "UMTS"
            json_select "available_band"
            add_avalible_band_entry  "$i" "UMTS_$i"
            json_select ".."
            json_select ".."
            if [ $select_all_band -eq 1 ]; then
                json_select "UMTS"
                json_select "lock_band"
                json_add_string "" "$i"
                json_select ".."
                json_select ".."
            fi
        else
            json_select "LTE"
            json_select "available_band"
            trim_first_letter=$(echo "$i" | sed 's/^.//')
            add_avalible_band_entry  "$i" "LTE_$trim_first_letter"
            json_select ".."
            json_select ".."
            if [ $select_all_band -eq 1 ]; then
                json_select "LTE"
                json_select "lock_band"
                json_add_string "" "$i"
                json_select ".."
                json_select ".."
            fi
        fi
    done
    
    for i in $(echo "$get_lockband_config_res" | sed 's/\r//g' | awk -F"," '{for(k='$seq'; k<=NF; k++) print $k}' ); do
        # i 0,100 UMTS
        # i 100,5000 LTE
        # i 5000,10000 NR
        if [ -z "$i" ]; then
            continue
        fi
        if [ $i -lt 100 ]; then
            json_select "UMTS"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ".."
            json_select ".."
        elif [ $i -lt 500 ]; then
            json_select "LTE"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ".."
            json_select ".."
        fi
    done
    json_close_array
}

set_lockband()
{
    config=$1
    band_class=$(echo $config | jq -r '.band_class')
    lock_band=$(echo $config | jq -r '.lock_band')
    case $platform in
        "qualcomm")
            set_lockband_nr
            ;;
        "unisoc")
            set_lockband_nr
            ;;
        "mediatek")
            set_lockband_nr
            ;;
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
#设置锁频
set_lockband_nr()
{
    m_debug "Fibocom set lockband info"
    get_lockband_config_command="AT+GTACT?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command)
    network_prefer_config=$(echo $get_lockband_config_res |cut -d : -f 2| awk -F"," '{print $1}' |tr -d ' ')
    local lock_band="$network_prefer_config,6,3,$lock_band"
    local set_lockband_command="AT+GTACT=$lock_band"
    res=$(at $at_port $set_lockband_command)
}

set_lockband_lte()
{
    m_debug "Fibocom set lte lockband"
    get_lockband_config_command="AT+GTACT?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command)
    network_prefer_config=$(echo $get_lockband_config_res |cut -d : -f 2| awk -F"," '{ print $1}' |tr -d ' ')
    local lock_band="$network_prefer_config,,,$lock_band"
    local set_lockband_command="AT+GTACT=$lock_band"
    res=$(at $at_port $set_lockband_command)
}

get_neighborcell()
{
    m_debug "Fibocom get neighborcell info"
    get_neighborcell_command="AT+GTCCINFO?"
    get_lockcell_command="AT+GTCELLLOCK?"
    cell_type="undefined"
    json_add_object "neighborcell"
    json_add_array "NR"
    json_close_array
    json_add_array "LTE"
    json_close_array
    at $at_port $get_neighborcell_command > /tmp/neighborcell
     while IFS= read -r line; do
        #跳过空行
        line=$(echo $line | sed 's/\r//g')
        if [ -z "$line" ]; then
            continue
        fi
        case $line in
            *"NR neighbor cell"*)
                cell_type="NR"
                continue
                ;;
            *"LTE neighbor cell"*)
                cell_type="LTE"
                continue
                ;;
            *"service cell"*|*"GTCELLINFO"*|*"OK"*)
                cell_type="undefined"
                continue
                ;;
        esac
        case $cell_type in
            "NR")
                tac=$(echo "$line" | awk -F',' '{print $5}')
                cellid=$(echo "$line" | awk -F',' '{print $6}')
                arfcn=$(echo "$line" | awk -F',' '{print $7}')
                pci=$(echo "$line" | awk -F',' '{print $8}')
                ss_sinr=$(echo "$line" | awk -F',' '{print $9}')
                rxlev=$(echo "$line" | awk -F',' '{print $10}')
                ss_rsrp=$(echo "$line" | awk -F',' '{print $11}')
                ss_rsrq=$(echo "$line" | awk -F',' '{print $12}')
                arfcn=$(echo 'ibase=16;' "$arfcn"  | bc)
                pci=$(echo 'ibase=16;' "$pci"  | bc)
                json_select "NR"
                json_add_object ""
                json_add_string "tac" "$tac"
                json_add_string "cellid" "$cellid"
                json_add_string "arfcn" "$arfcn"
                json_add_string "pci" "$pci"
                json_add_string "ss_sinr" "$ss_sinr"
                json_add_string "rxlev" "$rxlev"
                json_add_string "ss_rsrp" "$ss_rsrp"
                json_add_string "ss_rsrq" "$ss_rsrq"
                json_close_object
                json_select ".."
                ;;
            "LTE")
                tac=$(echo "$line" | awk -F',' '{print $5}')
                cellid=$(echo "$line" | awk -F',' '{print $6}')
                arfcn=$(echo "$line" | awk -F',' '{print $7}')
                pci=$(echo "$line" | awk -F',' '{print $8}')
                bandwidth=$(echo "$line" | awk -F',' '{print $9}')
                rxlev=$(echo "$line" | awk -F',' '{print $10}')
                rsrp=$(echo "$line" | awk -F',' '{print $11}')
                rsrq=$(echo "$line" | awk -F',' '{print $12}')
                arfcn=$(echo 'ibase=16;' "$arfcn"   | bc)
                pci=$(echo 'ibase=16;' "$pci"  | bc)
                json_select "LTE"
                json_add_object ""
                json_add_string "tac" "$tac"
                json_add_string "cellid" "$cellid"
                json_add_string "arfcn" "$arfcn"
                json_add_string "pci" "$pci"
                json_add_string "bandwidth" "$bandwidth"
                json_add_string "rxlev" "$rxlev"
                json_add_string "rsrp" "$rsrp"
                json_add_string "rsrq" "$rsrq"
                json_close_object
                json_select ".."
                ;;
        esac
    done < "/tmp/neighborcell"

    result=`at $at_port $get_lockcell_command | grep "+GTCELLLOCK:" | sed 's/+GTCELLLOCK: //g' | sed 's/\r//g'`
    #$1:lockcell_status $2:cell_type $3:lock_type $4:arfcn $5:pci $6:scs $7:nr_band
    json_add_object "lockcell_status"
    if [ -n "$result" ]; then
        lockcell_status=$(echo "$result" | awk -F',' '{print $1}')
        if [ "$lockcell_status" = "1" ]; then
            lockcell_status="lock"
        else
            lockcell_status="unlock"
        fi
        cell_type=$(echo "$result" | awk -F',' '{print $2}')
        if [ "$cell_type" = "1" ]; then
            cell_type="NR"
        elif [ "$cell_type" = "0" ]; then
            cell_type="LTE"
        fi
        lock_type=$(echo "$result" | awk -F',' '{print $3}')
        if [ "$lock_type" = "1" ]; then
            lock_type="arfcn"
        elif [ "$lock_type" = "0" ]; then
            lock_type="pci"
        fi
        arfcn=$(echo "$result" | awk -F',' '{print $4}')
        pci=$(echo "$result" | awk -F',' '{print $5}')
        scs=$(echo "$result" | awk -F',' '{print $6}')
        nr_band=$(echo "$result" | awk -F',' '{print $7}')
        json_add_string "Status" "$lockcell_status"
        json_add_string "Rat" "$cell_type"
        json_add_string "Lock Type" "$lock_type"
        json_add_string "ARFCN" "$arfcn"
        json_add_string "PCI" "$pci"
        json_add_string "SCS" "$scs"
        json_add_string "NR BAND" "$nr_band"
    fi
    json_close_object
    json_close_object
}


set_neighborcell(){
    json_param=$1
    rat=$(echo $json_param | jq -r '.rat')
    pci=$(echo $json_param | jq -r '.pci')
    arfcn=$(echo $json_param | jq -r '.arfcn')
    band=$(echo $json_param | jq -r '.band')
    scs=$(echo $json_param | jq -r '.scs')
    lockcell_all
    json_select "result"
    json_add_string "setlockcell" "$res"
    json_add_string "rat" "$rat"
    json_add_string "pci" "$pci"
    json_add_string "arfcn" "$arfcn"
    json_add_string "band" "$band"
    json_add_string "scs" "$scs"
    json_close_object
}

lockcell_all(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        local unlockcell="AT+GTCELLLOCK=0"
        res1=$(at $at_port $unlockcell)
        res=$res1
    else
        if [ -z $pci ] && [ -n $arfcn ]; then
            lockpci_nr="AT+GTCELLLOCK=1,1,1,$arfcn"
            lockpci_lte="AT+GTCELLLOCK=1,0,1,$arfcn"
            
        elif [ -n $pci ] && [ -n $arfcn ]; then
            lockpci_nr="AT+GTCELLLOCK=1,1,0,$arfcn,$pci,$scs,50$band"
            lockpci_lte="AT+GTCELLLOCK=1,0,0,$arfcn,$pci"
        fi
        if [ "$pci" -eq 0 ] && [ "$arfcn" -eq 0 ]; then
            lockpci_nr="AT+GTCELLLOCK=1"
            lockpci_lte="AT+GTCELLLOCK=1"
        fi
        if [ "$rat" -eq 1 ]; then
            res=$(at $at_port $lockpci_nr)
        elif [ "$rat" -eq 0 ]; then
            res=$(at $at_port $lockpci_lte)
        fi
    fi
}

get_band()
{
    local band
    case $1 in
		"WCDMA") band="$2" ;;
		"LTE") band="$(($2-100))" ;;
        "NR") band="$2" band="${band#*50}" ;;
	esac
    echo "$band"
}

#获取带宽
# $1:网络类型
# $2:带宽数字
get_bandwidth()
{
    local network_type="$1"
    local bandwidth_num="$2"

    local bandwidth
    case $network_type in
		"LTE")
            case $bandwidth_num in
                "6") bandwidth="1.4" ;;
                "15"|"25"|"50"|"75"|"100") bandwidth=$(( $bandwidth_num / 5 )) ;;
            esac
        ;;
        "NR")
            case $bandwidth_num in
                "0") bandwidth="5" ;;
                *) bandwidth=$(( $bandwidth_num / 5 )) ;;
            esac
        ;;
	esac
    echo "$bandwidth"
}

#获取信噪比
# $1:网络类型
# $2:信噪比数字
get_sinr()
{
    local sinr
    case $1 in
        "LTE") sinr=$(awk "BEGIN{ printf \"%.2f\", $2 * 0.5 - 23.5 }" | sed 's/\.*0*$//') ;;
        "NR") sinr=$(awk "BEGIN{ printf \"%.2f\", $2 * 0.5 - 23.5 }" | sed 's/\.*0*$//') ;;
	esac
    echo "$sinr"
}

#获取接收信号功率
# $1:网络类型
# $2:接收信号功率数字
get_rxlev()
{
    local rxlev
    case $1 in
        "GSM") rxlev=$(($2-110)) ;;
        "WCDMA") rxlev=$(($2-121)) ;;
        "LTE") rxlev=$(($2-141)) ;;
        "NR") rxlev=$(($2-157)) ;;
	esac
    echo "$rxlev"
}

#获取参考信号接收功率
# $1:网络类型
# $2:参考信号接收功率数字
get_rsrp()
{
    local rsrp
    case $1 in
        "LTE") rsrp=$(($2-141)) ;;
        "NR") rsrp=$(($2-157)) ;;
	esac
    echo "$rsrp"
}

#获取参考信号接收质量
# $1:网络类型
# $2:参考信号接收质量数字
get_rsrq()
{
    local rsrq
    case $1 in
        "LTE") rsrq=$(awk "BEGIN{ printf \"%.2f\", $2 * 0.5 - 20 }" | sed 's/\.*0*$//') ;;
        "NR") rsrq=$(awk -v num="$2" "BEGIN{ printf \"%.2f\", (num+1) * 0.5 - 44 }" | sed 's/\.*0*$//') ;;
	esac
    echo "$rsrq"
}

#获取信号干扰比
# $1:信号干扰比数字
get_rssnr()
{
    #去掉小数点后的0
    local rssnr=$(awk "BEGIN{ printf \"%.2f\", $1 / 2 }" | sed 's/\.*0*$//')
    echo "$rssnr"
}

#获取Ec/Io
# $1:Ec/Io数字
get_ecio()
{
    local ecio=$(awk "BEGIN{ printf \"%.2f\", $1 * 0.5 - 24.5 }" | sed 's/\.*0*$//')
    echo "$ecio"
}

#小区信息
cell_info()
{
    m_debug "Fibocom cell info"

    at_command='AT+GTCCINFO?'
    response=$(at $at_port $at_command)
    
    local rat=$(echo "$response" | grep "service" | awk -F' ' '{print $1}')

    #适配联发科平台（FM350-GL）
    [ -z "$rat" ] && {
        at_command='AT+COPS?'
        rat_num=$(at $at_port $at_command | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        rat=$(get_rat ${rat_num})
    }

    for response in $response; do
        #排除+GTCCINFO:、NR service cell:还有空行
        [ -n "$response" ] && [[ "$response" = *","* ]] && {

            case $rat in
                "NR")
                    at_command='AT+GTCAINFO?'
                    ca_response=$(at $at_port $at_command)
                    if echo "$ca_response" | grep -q "SCC"; then
                        has_ca=1
                        scc_info=$(echo "$ca_response" | grep "SCC" | sed 's/\r//g')
                        scc_band_num=$(echo "$scc_info" | awk -F',' '{print $3}')
                        scc_arfcn=$(echo "$scc_info" | awk -F',' '{print $5}')
                        scc_band=$(get_band "NR" ${scc_band_num})
                        nr_scc_dl_bandwidth_num=$(echo "$scc_info" | awk -F',' '{print $6}')
                        nr_scc_dl_bandwidth=$(get_bandwidth "NR" ${nr_scc_dl_bandwidth_num})
                    fi
                    if [ $has_ca -eq 1 ]; then
                        network_mode="NR5G-SA CA Mode"
                    else
                        network_mode="NR5G-SA Mode"
                    fi
                    nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    nr_tac=$(echo "$response" | awk -F',' '{print $5}')
                    nr_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    nr_arfcn=$(echo "$response" | awk -F',' '{print $7}')
                    nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    nr_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    nr_band=$(get_band "NR" ${nr_band_num})
                    nr_dl_bandwidth_num=$(echo "$ca_response" | grep "PCC" | sed 's/\r//g' | awk -F',' '{print $4}')
                    nr_dl_bandwidth=$(get_bandwidth "NR" ${nr_dl_bandwidth_num})
                    nr_ul_bandwidth_num=$(echo "$ca_response" | grep "PCC" | sed 's/\r//g' | awk -F',' '{print $5}')
                    nr_ul_bandwidth=$(get_bandwidth "NR" ${nr_ul_bandwidth_num})
                    nr_sinr_num=$(echo "$response" | awk -F',' '{print $11}')
                    nr_sinr=$(get_sinr "NR" ${nr_sinr_num})
                    nr_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    nr_rxlev=$(get_rxlev "NR" ${nr_rxlev_num})
                    nr_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    nr_rsrp=$(get_rsrp "NR" ${nr_rsrp_num})
                    nr_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    nr_rsrq=$(get_rsrq "NR" ${nr_rsrq_num})
                ;;
                "LTE-NR")
                    network_mode="EN-DC Mode"
                    #LTE
                    endc_lte_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    endc_lte_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    endc_lte_tac=$(echo "$response" | awk -F',' '{print $5}')
                    endc_lte_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    endc_lte_earfcn=$(echo "$response" | awk -F',' '{print $7}')
                    endc_lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    endc_lte_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    endc_lte_band=$(get_band "LTE" ${endc_lte_band_num})
                    ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    endc_lte_ul_bandwidth=$(get_bandwidth "LTE" ${ul_bandwidth_num})
                    endc_lte_dl_bandwidth="$endc_lte_ul_bandwidth"
                    endc_lte_rssnr_num=$(echo "$response" | awk -F',' '{print $11}')
                    endc_lte_rssnr=$(get_rssnr ${endc_lte_rssnr_num})
                    endc_lte_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    endc_lte_rxlev=$(get_rxlev "LTE" ${endc_lte_rxlev_num})
                    endc_lte_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    endc_lte_rsrp=$(get_rsrp "LTE" ${endc_lte_rsrp_num})
                    endc_lte_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    endc_lte_rsrq=$(get_rsrq "LTE" ${endc_lte_rsrq_num})
                    #NR5G-NSA
                    endc_nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    endc_nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    endc_nr_tac=$(echo "$response" | awk -F',' '{print $5}')
                    endc_nr_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    endc_nr_arfcn=$(echo "$response" | awk -F',' '{print $7}')
                    endc_nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    endc_nr_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    endc_nr_band=$(get_band "NR" ${endc_nr_band_num})
                    nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    endc_nr_dl_bandwidth=$(get_bandwidth "NR" ${nr_dl_bandwidth_num})
                    endc_nr_sinr_num=$(echo "$response" | awk -F',' '{print $11}')
                    endc_nr_sinr=$(get_sinr "NR" ${endc_nr_sinr_num})
                    endc_nr_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    endc_nr_rxlev=$(get_rxlev "NR" ${endc_nr_rxlev_num})
                    endc_nr_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    endc_nr_rsrp=$(get_rsrp "NR" ${endc_nr_rsrp_num})
                    endc_nr_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    endc_nr_rsrq=$(get_rsrq "NR" ${endc_nr_rsrq_num})
                    ;;
                "LTE"|"eMTC"|"NB-IoT")
                    network_mode="LTE Mode"
                    lte_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    lte_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    lte_tac=$(echo "$response" | awk -F',' '{print $5}')
                    lte_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    lte_earfcn=$(echo "$response" | awk -F',' '{print $7}')
                    lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    lte_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    lte_band=$(get_band "LTE" ${lte_band_num})
                    ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    lte_ul_bandwidth=$(get_bandwidth "LTE" ${ul_bandwidth_num})
                    lte_dl_bandwidth="$lte_ul_bandwidth"
                    lte_rssnr=$(echo "$response" | awk -F',' '{print $11}')
                    lte_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    lte_rxlev=$(get_rxlev "LTE" ${lte_rxlev_num})
                    lte_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    lte_rsrp=$(get_rsrp "LTE" ${lte_rsrp_num})
                    lte_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    lte_rsrq=$(get_rsrq "LTE" ${lte_rsrq_num})
                ;;
                "WCDMA"|"UMTS")
                    network_mode="WCDMA Mode"
                    wcdma_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    wcdma_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    wcdma_lac=$(echo "$response" | awk -F',' '{print $5}')
                    wcdma_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    wcdma_uarfcn=$(echo "$response" | awk -F',' '{print $7}')
                    wcdma_psc=$(echo "$response" | awk -F',' '{print $8}')
                    wcdma_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    wcdma_band=$(get_band "WCDMA" ${wcdma_band_num})
                    wcdma_ecno=$(echo "$response" | awk -F',' '{print $10}')
                    wcdma_rscp=$(echo "$response" | awk -F',' '{print $11}')
                    wcdma_rac=$(echo "$response" | awk -F',' '{print $12}')
                    wcdma_rxlev_num=$(echo "$response" | awk -F',' '{print $13}')
                    wcdma_rxlev=$(get_rxlev "WCDMA" ${wcdma_rxlev_num})
                    wcdma_reserved=$(echo "$response" | awk -F',' '{print $14}')
                    wcdma_ecio_num=$(echo "$response" | awk -F',' '{print $15}' | sed 's/\r//g')
                    wcdma_ecio=$(get_ecio ${wcdma_ecio_num})
                ;;
            esac

            #联发科平台特殊处理（FM350-GL）
            [[ "$name" = "FM350-GL" ]] && {
                nr_sinr="${nr_sinr_num}"
                endc_nr_sinr="${endc_nr_sinr_num}"
            }

            #只选择第一个，然后退出
            break
        }
        
    done
    class="Cell Information"
    add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
    case $network_mode in
    "NR5G-SA Mode"|"NR5G-SA CA Mode")
        add_plain_info_entry "MMC" "$nr_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$nr_mnc" "Mobile Network Code"
        add_plain_info_entry "Duplex Mode" "$nr_duplex_mode" "Duplex Mode"
        add_plain_info_entry "Cell ID" "$nr_cell_id" "Cell ID"
        add_plain_info_entry "Physical Cell ID" "$nr_physical_cell_id" "Physical Cell ID"
        add_plain_info_entry "TAC" "$nr_tac" "Tracking area code of cell served by neighbor Enb"
        if [ $has_ca -eq 1 ]; then
            add_plain_info_entry "ARFCN" "$nr_arfcn / $scc_arfcn" "Absolute Radio-Frequency Channel Number"
            add_plain_info_entry "Band" "$nr_band / $scc_band" "Band"
            add_plain_info_entry "DL Bandwidth" "${nr_dl_bandwidth}M / ${nr_scc_dl_bandwidth}M" "DL Bandwidth"
        else
            add_plain_info_entry "ARFCN" "$nr_arfcn" "Absolute Radio-Frequency Channel Number"
            add_plain_info_entry "Band" "$nr_band" "Band"
            add_plain_info_entry "DL Bandwidth" "${nr_dl_bandwidth}M" "DL Bandwidth"
        fi
        add_plain_info_entry "UL Bandwidth" "${nr_ul_bandwidth}M" "UL Bandwidth"
        add_bar_info_entry "RSRP" "$nr_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$nr_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "SINR" "$nr_sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
        add_bar_info_entry "RxLev" "$nr_rxlev" "Received Signal Level" -140 -20 dBm
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
        add_bar_info_entry "RSRP" "$lte_rsrp" "Reference Signal Received Power" -140 -44 dBm
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
