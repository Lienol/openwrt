#!/bin/sh
# Copyright (C) 2025 sfwtw <sfwtw@qq.com>
_Vendor="simcom"
_Author="sfwtw"
_Maintainer="sfwtw <sfwtw@qq.com>"
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
    at_command="AT+SIMEI=$imei"
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
    at_command='AT+CUSBCFG?'
    local mode_num=$(at ${at_port} ${at_command} | grep "USBID: " | sed 's/USBID: 0X1E0E,0X//g' | sed 's/\r//g')
    local mode
    pcie_cfg=$(at ${at_port} "AT+CPCIEMODE?")
    pcie_mode=$(echo "$pcie_cfg"|grep +CPCIEMODE: |cut -d':' -f2|xargs)
    if [ "$pcie_mode" = "EP" ] && [ "$mode_num" = "902B" ]; then
        mode_num="9001"
    json_add_int disable_mode_btn 1
    fi
    case "$platform" in
        "qualcomm")
            case "$mode_num" in
                "9001") mode="qmi" ;;
                "9011") mode="rndis" ;;
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
                "qmi") mode_num="9001" ;;
                "rndis") mode_num="9011" ;;
                *) mode_num="0" ;;
            esac
        ;;
        *)
            mode_num="0"
        ;;

    esac

    #设置模组
    at_command='AT+CUSBCFG=usbid,1e0e,'${mode_num}
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
        "qualcomm")
            get_network_prefer_nr
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
    esac
    json_close_array
    
}

get_network_prefer_nr()
{
    at_command='AT+CNMP?'
    local response=$(at ${at_port} ${at_command} | grep "+CNMP:" | awk -F': ' '{print $2}' | sed 's/\r//g')
    
    network_prefer_3g="0";
    network_prefer_4g="0";
    network_prefer_5g="0";

    #匹配不同的网络类型
    local auto=$(echo "${response}" | grep "2")
    if [ -n "$auto" ]; then
        network_prefer_3g="1"
        network_prefer_4g="1"
        network_prefer_5g="1"
    else
        local wcdma=$(echo "${response}" | grep "14" || echo "${response}" | grep "54" || echo "${response}" | grep "55")
        local lte=$(echo "${response}" | grep "38" || echo "${response}" | grep "54" || echo "${response}" | grep "109")
        local nr=$(echo "${response}" | grep "71" || echo "${response}" | grep "55" || echo "${response}" | grep "109")
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
        "qualcomm")
            set_network_prefer_nr $at_port $network_prefer
        ;;
        *)
            set_network_prefer_nr $at_port $network_prefer
        ;;
    esac
}

set_network_prefer_nr()
{
    case "$length" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                network_prefer_config="14"
            elif [ "$network_prefer_4g" = "true" ]; then
                network_prefer_config="38"
            elif [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="71"
            fi
        ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                network_prefer_config="54"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="55"
            elif [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="109"
            fi
        ;;
        "3") network_prefer_config="2" ;;
        *) network_prefer_config="2" ;;
    esac

    #设置模组
    at_command='AT+CNMP='${network_prefer_config}
    at "${at_port}" "${at_command}"
}

#获取电压
# $1:AT串口
get_voltage()
{
    at_command="AT+CBC"
    local voltage=$(at ${at_port} ${at_command} | grep "+CBC:" | sed 's/+CBC: //g' | sed 's/V//g' | sed 's/\r//g')
    [ -n "$voltage" ] && {
        add_plain_info_entry "voltage" "$voltage V" "Voltage" 
    }
}

#获取温度
#return raw data
get_temperature()
{   
    #Temperature（温度）
    at_command="AT+CPMUTEMP"
    local temp
    local line=1
    QTEMP=$(at ${at_port} ${at_command} | grep "+CPMUTEMP:")
    temp=$(echo $QTEMP | awk -F': ' '{print $2}' | sed 's/\r//g')
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
    at_command="AT+SIMCOMATI"
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
    at_command="AT+SMSIMCFG?"
    sim_slot=$(at $at_port $at_command | grep "+SMSIMCFG:" | awk -F',' '{print $2}' | sed 's/\r//g')

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
    m_debug  "Simcom network info"

    at_command="AT+CPSI?"
    network_type=$(at ${at_port} ${at_command} | grep "+CPSI:" | awk -F',' '{print $1}' | sed 's/+CPSI: //g')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(at ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }

    class="Network Information"
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
}

#获取频段
# $1:网络类型
# $2:频段数字
get_band()
{
    local band
    band=$(echo $1 | sed 's/^0-9//g')
    echo "$band"
}

get_lockband_nr()
{
    local at_port="$1"
    m_debug  "Quectel sdx55 get lockband info"
    get_wcdma_config_command='AT+CSYSSEL="w_band"'
    get_lte_config_command='AT+CSYSSEL="lte_band"'
    get_nsa_nr_config_command='AT+CSYSSEL="nsa_nr5g_band"'
    get_sa_nr_config_command='AT+CSYSSEL="nr5g_band"'
    wcdma_avalible_band="1,2,3,4,5,6,8,9,19"
    lte_avalible_band="1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,34,38,39,40,41,42,43,48,66,71"
    nsa_nr_avalible_band="1,2,3,5,7,8,12,20,28,38,40,41,48,66,71,77,78,79"
    sa_nr_avalible_band="1,2,3,5,7,8,12,20,28,38,40,41,48,66,71,77,78,79"
    [ -n $(uci -q get qmodem.$config_section.sa_band) ] && sa_nr_avalible_band=$(uci -q get qmodem.$config_section.sa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.nsa_band) ] && nsa_nr_avalible_band=$(uci -q get qmodem.$config_section.nsa_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.lte_band) ] && lte_avalible_band=$(uci -q get qmodem.$config_section.lte_band | tr '/' ',')
    [ -n $(uci -q get qmodem.$config_section.wcdma_band) ] && wcdma_avalible_band=$(uci -q get qmodem.$config_section.wcdma_band | tr '/' ',')
    gw_band=$(at $at_port  $get_wcdma_config_command |grep -e "+CSYSSEL: " )
    lte_band=$(at $at_port $get_lte_config_command|grep -e "+CSYSSEL: ")
    nsa_nr_band=$(at $at_port $get_nsa_nr_config_command|grep -e "+CSYSSEL: ")
    sa_nr_band=$(at $at_port  $get_sa_nr_config_command|grep -e "+CSYSSEL: ")
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

get_lockband()
{
    json_add_object "lockband"
    case "$platform" in
        "qualcomm")
            get_lockband_nr $at_port
        ;;
        *)
            get_lockband_nr $at_port
        ;;
    esac
    json_close_object
}

set_lockband_nr(){
    lock_band=$(echo $lock_band | tr ',' ':')
    case "$band_class" in
        "UMTS") 
            at_command="AT+CSYSSEL=\"w_band\",$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "LTE") 
            at_command="AT+CSYSSEL=\"lte_band\",$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "NR_NSA")
            at_command="AT+CSYSSEL=\"nsa_nr5g_band\",$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "NR")
            at_command="AT+CSYSSEL=\"nr5g_band\",$lock_band"
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
    local at_command='AT+CPSI?'
    nr_lock_check="AT+C5GCELLCFG?"
    lte_lock_check="AT+CCELLCFG?"
    lte_status=$(at $at_port $lte_lock_check | grep "+CCELLCFG:")    
    if [ ! -z "$lte_status" ]; then
        lte_lock_status="locked"
    else
        lte_lock_status=""
    fi
    lte_lock_freq=$(echo $lte_status | awk -F',' '{print $2}' | sed 's/\r//g')
    lte_lock_pci=$(echo $lte_status | awk -F',' '{print $1}' | sed 's/+CCELLCFG: //g' | sed 's/\r//g')
    nr_status=$(at $at_port $nr_lock_check | grep "+C5GCELLCFG:")
    nr_lock_status=$(echo "$nr_status" | awk -F': ' '{print $2}' | xargs)
    nr_lock_pci=$(echo "$nr_status" | awk -F',' '{print $2}' | xargs)
    nr_lock_freq=$(echo "$nr_status" | awk -F',' '{print $3}' | xargs)
    nr_lock_scs=$(echo "$nr_status" | awk -F',' '{print $4}' | xargs)
    nr_lock_band=$(echo "$nr_status" | awk -F',' '{print $5}' | xargs)
    if [ "$nr_lock_status" != "0" ]; then
        nr_lock_status="locked"
    else
        nr_lock_status=""
    fi

    modem_status=$(at $at_port $at_command)
    modem_status_net=$(echo "$modem_status"|grep "+CPSI:"|awk -F',' '{print $1}'|awk -F':' '{print $2}'|xargs)
    modem_status_band=$(echo "$modem_status"|grep "+CPSI:"|awk -F',' '{print $7}'|awk -F'_' '{print $2}'|sed 's/BAND//g'|xargs)
    if [ $modem_status_net == "NR5G_SA" ];then
        scans=$(at $at_port "AT+CNWSEARCH=\"nr5g\"")
        sleep 10
        at $at_port "AT+CNWSEARCH=\"nr5g\",3" > /tmp/neighborcell
    elif [ $modem_status_net == "LTE" ];then
        at $at_port "AT+CNWSEARCH=\"lte\",1" > /tmp/neighborcell
        sleep 5
    fi
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
        if [ -n "$(echo $line | grep "+NR_NGH_CELL:")" ] || [ -n "$(echo $line | grep "+LTE_CELL:")" ]; then
            # CPSI: NR5G_SA,Online,460-01,0x6F4700,29869309958,95,NR5G_BAND78,627264,-800,-110,14
        
            case $line in
                *WCDMA*)
                    type="WCDMA"
                    
                    arfcn=$(echo $line | awk -F',' '{print $4}')
                    pci=$(echo $line | awk -F',' '{print $7}')
                    rscp=$(echo $line | awk -F',' '{print $11}')
                    ecno=$(echo $line | awk -F',' '{print $10}')
                    ;;
                *LTE_CELL*)
                    type="LTE"
                    arfcn=$(echo $line | awk -F',' '{print $6}')
                    pci=$(echo $line | awk -F',' '{print $7}')
                    rsrp=$(echo $line | awk -F',' '{print $8}')
                    rsrq=$(echo $line | awk -F',' '{print $9}')
            band=$(echo $line | awk -F',' '{print $5}')
            mnc=$(echo $line | awk -F',' '{print $2}')
                    ;;
                *NR_NGH_CELL*)
                    type="NR"
                    arfcn=$(echo $line | awk -F',' '{print $1}'| awk -F':' '{print $2}'| xargs)
                    pci=$(echo $line | awk -F',' '{print $2}')
                    rsrp=$(echo $line | awk -F',' '{print $3}')
                    rsrq=$(echo $line | awk -F',' '{print $4}')
            band=$modem_status_band
                    ;;
            esac
            json_select $type
            json_add_object ""
        json_add_string "mnc" "$mnc"
            json_add_string "arfcn" "$arfcn"
            json_add_string "pci" "$pci"
            json_add_string "rscp" "$rscp"
            json_add_string "ecno" "$ecno"
            json_add_string "rsrp" "$rsrp"
            json_add_string "rsrq" "$rsrq"
            json_add_string "band" "$band"
            json_close_object
            json_select ".."
        fi
    done < /tmp/neighborcell
}

get_neighborcell(){
    m_debug  "quectel set lockband info"
    json_add_object "neighborcell"
    case "$platform" in
        "qualcomm")
            get_neighborcell_qualcomm
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
        "qualcomm")
            lockcell_qualcomm
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
        unlock4g="AT+CCELLCFG=0"
        unlocknr='AT+C5GCELLCFG="unlock"'
        res1=$(at $at_port $unlocknr)
        res2=$(at $at_port $unlock4g)
        res=$res1,$res2
    else
        lock4g="AT+CCELLCFG=1,$pci,$arfcn;+CNMP=38"
        locknr="AT+C5GCELLCFG=\"pci\",$pci,$arfcn,$scs,$band;+CNMP=71"
        if [ $rat = "1" ]; then
            res=$(at $at_port $locknr)
        else
            res=$(at $at_port $lock4g)
        fi
    fi
   
}

unlockcell(){
    unlock4g="AT+CCELLCFG=0"
        unlocknr='AT+C5GCELLCFG="unlock"'
    res2=$(at $1 $unlocknr)
    res3=$(at $1 $unlock4g)
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

process_signal_value() {
    local value="$1"
    echo "scale=1; $value / 10" | bc | awk '{printf("%g", $0)}'
}
#小区信息
cell_info()
{
    m_debug  "Quectel cell info"

    at_command1='AT+CPSI?'
    at_command2='AT+CNWINFO?'
    response1=$(at $at_port $at_command1)
    response2=$(at $at_port $at_command2)

    local lte=$(echo "$response1" | grep "LTE")
    local nr5g_nsa=$(echo "$response1" | grep "NR5G_NSA")
    local CNWINFO=$(echo "$response2" | grep "+CNWINFO:")
    if [ -n "$lte" ] && [ -n "$nr5g_nsa" ] ; then
        #EN-DC模式
        network_mode="EN-DC Mode"
        #LTE
        # +CPSI: LTE,Online,460-01,0x7496,251941991,203,EUTRAN-BAND8,3740,3,3,-92,-672,-418,14
        # +CPSI: LTE,<OperationMode>[,<MCC>-<MNC>,<TAC>,<SCellID>,<PCellID>,<FrequencyBand>,<earfcn>,<dlbw>,<ulbw>,<RSRQ>,<RSRP>,<RSSI>,<RSSNR>]
        endc_lte_duplex_mode=""
        endc_lte_mcc=$(echo "$lte" | awk -F',' '{print $3}' | awk -F'-' '{print $1}')
        endc_lte_mnc=$(echo "$lte" | awk -F',' '{print $3}' | awk -F'-' '{print $2}')
        endc_lte_cell_id=$(echo "$lte" | awk -F',' '{print $5}')
        endc_lte_physical_cell_id=$(echo "$lte" | awk -F',' '{print $6}')
        endc_lte_earfcn=$(echo "$lte" | awk -F',' '{print $8}')
        endc_lte_freq_band_ind_num=$(echo "$lte" | awk -F',' '{print $7}')
        endc_lte_freq_band_ind=$(get_band $endc_lte_freq_band_ind_num)
        ul_bandwidth_num=$(echo "$lte" | awk -F',' '{print $10}')
        endc_lte_ul_bandwidth=$(get_bandwidth "LTE" $ul_bandwidth_num)
        dl_bandwidth_num=$(echo "$lte" | awk -F',' '{print $9}')
        endc_lte_dl_bandwidth=$(get_bandwidth "LTE" $dl_bandwidth_num)
        endc_lte_tac=$(echo "$lte" | awk -F',' '{print $4}')
        endc_lte_rsrp=$(echo "$lte" | awk -F',' '{print $12}')
        endc_lte_rsrp=$(process_signal_value $endc_lte_rsrp)
        endc_lte_rsrq=$(echo "$lte" | awk -F',' '{print $11}')
        endc_lte_rsrq=$(process_signal_value $endc_lte_rsrq)
        endc_lte_rssi=$(echo "$lte" | awk -F',' '{print $13}')
        endc_lte_rssi=$(process_signal_value $endc_lte_rssi)
        endc_lte_sinr=$(echo "$lte" | awk -F',' '{print $14}')
        endc_lte_cql=$(echo "$CNWINFO" | awk -F',' '{print $8}')
        endc_lte_tx_power=""
        endc_lte_srxlev=""
        #NR5G-NSA
        # +CPSI: NR5G_NSA,[<PCellID>,<FrequencyBand>,<earfcn/ssb>,<RSRP>,<RSRQ>,<SNR>,<scs>,<NR_dl_bw>]
        endc_nr_mcc=""
        endc_nr_mnc=""
        endc_nr_physical_cell_id=$(echo "$nr5g_nsa" | awk -F',' '{print $2}')
        endc_nr_rsrp=$(echo "$nr5g_nsa" | awk -F',' '{print $5}')
        endc_nr_rsrp=$(process_signal_value $endc_nr_rsrp)
        endc_nr_sinr=$(echo "$nr5g_nsa" | awk -F',' '{print $7}')
        endc_nr_sinr=$(process_signal_value $endc_nr_sinr)
        endc_nr_rsrq=$(echo "$nr5g_nsa" | awk -F',' '{print $6}')
        endc_nr_rsrq=$(process_signal_value $endc_nr_rsrq)
        endc_nr_arfcn=$(echo "$nr5g_nsa" | awk -F',' '{print $4}')
        endc_nr_band_num=$(echo "$nr5g_nsa" | awk -F',' '{print $3}')
        endc_nr_band=$(get_band $endc_nr_band_num)
        nr_dl_bandwidth_num=$(echo "$nr5g_nsa" | awk -F',' '{print $9}')
        endc_nr_dl_bandwidth=$(get_bandwidth "NR" $nr_dl_bandwidth_num)
        scs_num=$(echo "$nr5g_nsa" | awk -F',' '{print $8}' | sed 's/\r//g')
        endc_nr_scs=$(get_scs $scs_num)
    else
        #SA，LTE，WCDMA模式
        #+CPSI: NR5G_SA,<OperationMode>[,<MCC>-<MNC>,<TAC>,<SCellID>,<PCellID>,<FrequencyBand>,<earfcn>,<RSRP>,<RSRQ>,<SNR>]
        response=$(echo "$response1" | grep "+CPSI:")
        local rat=$(echo "$response" | awk -F',' '{print $1}' | sed 's/+CPSI: //g')
        case $rat in
            "NR5G_SA")
                network_mode="NR5G-SA Mode"
                nr_duplex_mode=$(echo "$response" | awk -F',' '{print $2}')
                nr_mcc=$(echo "$response" | awk -F',' '{print $3}' | awk -F'-' '{print $1}')
                nr_mnc=$(echo "$response" | awk -F',' '{print $3}' | awk -F'-' '{print $2}')
                nr_cell_id=$(echo "$response" | awk -F',' '{print $5}')
                nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                nr_tac=$(echo "$response" | awk -F',' '{print $4}')
                nr_arfcn=$(echo "$response" | awk -F',' '{print $8}')
                nr_band_num=$(echo "$response" | awk -F',' '{print $7}')
                nr_band=$(get_band $nr_band_num)
                nr_dl_bandwidth=$(echo $CNWINFO | awk -F',' '{print $11}')
                nr_rsrp=$(echo "$response" | awk -F',' '{print $9}')
                nr_rsrp=$(process_signal_value $nr_rsrp)
                nr_rsrq=$(echo "$response" | awk -F',' '{print $10}')
                nr_rsrq=$(process_signal_value $nr_rsrq)
                nr_sinr=$(echo "$response" | awk -F',' '{print $11}')
                nr_scs_num=""
                nr_scs=$(get_scs $nr_scs_num)
                nr_rxlev=$(echo "$CNWINFO" | awk -F',' '{print $5}')
                nr_cql=$(echo "$CNWINFO" | awk -F',' '{print $14}')
                nr_dlmod=$(echo "$CNWINFO" | awk -F',' '{print $8}')
                nr_ulmod=$(echo "$CNWINFO" | awk -F',' '{print $9}')
                nr_tx_power=$(echo "$CNWINFO" | awk -F',' '{print $12}')
                nr_rssi=$(echo "$CNWINFO" | awk -F',' '{print $13}')
                nr_rssi=$(process_signal_value $nr_rssi)
            ;;
            "LTE")
                # +CPSI: LTE,Online,460-01,0x7496,251941991,203,EUTRAN-BAND8,3740,3,3,-92,-672,-418,14
                # +CPSI: LTE,<OperationMode>[,<MCC>-<MNC>,<TAC>,<SCellID>,<PCellID>,<FrequencyBand>,<earfcn>,<dlbw>,<ulbw>,<RSRQ>,<RSRP>,<RSSI>,<RSSNR>]
                network_mode="LTE Mode"
                lte_mcc=$(echo "$response" | awk -F',' '{print $3}' | awk -F'-' '{print $1}')
                lte_mnc=$(echo "$response" | awk -F',' '{print $3}' | awk -F'-' '{print $2}')
                lte_cell_id=$(echo "$response" | awk -F',' '{print $5}')
                lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                lte_earfcn=$(echo "$response" | awk -F',' '{print $8}')
                lte_freq_band_ind_num=$(echo "$response" | awk -F',' '{print $7}')
                lte_freq_band_ind=$(get_band $lte_freq_band_ind_num)
                ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                lte_ul_bandwidth=$(get_bandwidth "LTE" $ul_bandwidth_num)
                dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $9}')
                lte_dl_bandwidth=$(get_bandwidth "LTE" $dl_bandwidth_num)
                lte_tac=$(echo "$response" | awk -F',' '{print $4}')
                lte_rsrp=$(echo "$response" | awk -F',' '{print $12}')
                lte_rsrp=$(process_signal_value $lte_rsrp)
                lte_rsrq=$(echo "$response" | awk -F',' '{print $11}')
                lte_rsrq=$(process_signal_value $lte_rsrq)
                lte_rssi=$(echo "$response" | awk -F',' '{print $13}')
                lte_rssi=$(process_signal_value $lte_rssi)
                lte_sinr=$(echo "$response" | awk -F',' '{print $14}')
                lte_cql=$(echo "$CNWINFO" | awk -F',' '{print $8}')
                lte_tx_power=$(echo "$CNWINFO" | awk -F',' '{print $9}')
                lte_srxlev=$(echo "$CNWINFO" | awk -F',' '{print $4}')
            ;;
            "WCDMA")
                # +CPSI: <SystemMode>,<OperationMode>,<MCC>-<MNC>,<LAC>,<Cell ID>,<FrequencyBand>,<PSC>,<Freq>,<SSC>,<EC/IO>,<RSCP>,<Qual>,<RxLev>,<TXPWR>
                # +CPSI: WCDMA,Online,460-01,0xA809,11122855,WCDMAIMT2000,279,10663,0,1.5,62,33,52,500
                network_mode="WCDMA Mode"
                wcdma_mcc=$(echo "$response" | awk -F',' '{print $3}' | awk -F'-' '{print $1}')
                wcdma_mnc=$(echo "$response" | awk -F',' '{print $3}' | awk -F'-' '{print $2}')
                wcdma_lac=$(echo "$response" | awk -F',' '{print $4}')
                wcdma_cell_id=$(echo "$response" | awk -F',' '{print $5}')
                wcdma_uarfcn=$(echo "$response" | awk -F',' '{print $8}')
                wcdma_psc=$(echo "$response" | awk -F',' '{print $7}')
                wcdma_rscp=$(echo "$response" | awk -F',' '{print $11}')
                wcdma_rscp=$(process_signal_value $wcdma_rscp)
                wcdma_ecio=$(echo "$response" | awk -F',' '{print $10}')
                wcdma_tx_power=$(echo "$response" | awk -F',' '{print $14}')
                wcdma_rxlev=$(echo "$CNWINFO" | awk -F',' '{print $13}')
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
        add_plain_info_entry "CQI" "$nr_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$nr_tx_power" "TX Power"
        add_plain_info_entry "DL/UL MOD" "$nr_dlmod / $nr_ulmod" "DL/UL MOD"
        add_bar_info_entry "RSRP" "$nr_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$nr_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "RSSI" "$nr_rssi" "Received Signal Strength Indicator" -120 -20 dBm
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
        add_plain_info_entry "UL Bandwidth" "$lte_ul_bandwidth" "UL Bandwidth"
        add_plain_info_entry "DL Bandwidth" "$lte_dl_bandwidth" "DL Bandwidth"
        add_plain_info_entry "TAC" "$lte_tac" "Tracking area code of cell served by neighbor Enb"
        add_bar_info_entry "RSRP" "$lte_rsrp" "Reference Signal Received Power" -140 -44 dBm
        add_bar_info_entry "RSRQ" "$lte_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
        add_bar_info_entry "RSSI" "$lte_rssi" "Received Signal Strength Indicator" -120 -22 dBm
        add_bar_info_entry "SINR" "$lte_sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
        add_plain_info_entry "CQI" "$lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$lte_srxlev" "Serving Cell Receive Level"
        ;;
    "WCDMA Mode")
        add_plain_info_entry "MCC" "$wcdma_mcc" "Mobile Country Code"
        add_plain_info_entry "MNC" "$wcdma_mnc" "Mobile Network Code"
        add_plain_info_entry "LAC" "$wcdma_lac" "Location Area Code"
        add_plain_info_entry "Cell ID" "$wcdma_cell_id" "Cell ID"
        add_plain_info_entry "UARFCN" "$wcdma_uarfcn" "Uplink Absolute Radio Frequency Channel Number"
        add_plain_info_entry "PSC" "$wcdma_psc" "Primary Scrambling Code"
        add_bar_info_entry "RSCP" "$wcdma_rscp" "Received Signal Code Power" -120 -24 dBm
        add_bar_info_entry "EC/IO" "$wcdma_ecio" "Ec/Io" -30 -5 dB
        add_plain_info_entry "Tx Power" "$wcdma_tx_power" "Tx Power"
        add_plain_info_entry "RxLev" "$wcdma_rxlev" "Received Signal Level"
        ;;
    esac
}

