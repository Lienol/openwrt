#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"

#预设
quectel_presets()
{
	at_command='ATI'
	# sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"
}

#获取DNS
# $1:AT串口
# $2:连接定义
quectel_get_dns()
{
    local at_port="$1"
    local define_connect="$2"

    [ -z "$define_connect" ] && {
        define_connect="1"
    }

    local public_dns1_ipv4="223.5.5.5"
    local public_dns2_ipv4="119.29.29.29"
    local public_dns1_ipv6="2400:3200::1" #下一代互联网北京研究中心：240C::6666，阿里：2400:3200::1，腾讯：2402:4e00::
    local public_dns2_ipv6="2402:4e00::"

    #获取DNS地址
    at_command="AT+GTDNS=${define_connect}"
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+GTDNS: ")

    local ipv4_dns1=$(echo "${response}" | awk -F'"' '{print $2}' | awk -F',' '{print $1}')
    [ -z "$ipv4_dns1" ] && {
        ipv4_dns1="${public_dns1_ipv4}"
    }

    local ipv4_dns2=$(echo "${response}" | awk -F'"' '{print $4}' | awk -F',' '{print $1}')
    [ -z "$ipv4_dns2" ] && {
        ipv4_dns2="${public_dns2_ipv4}"
    }

    local ipv6_dns1=$(echo "${response}" | awk -F'"' '{print $2}' | awk -F',' '{print $2}')
    [ -z "$ipv6_dns1" ] && {
        ipv6_dns1="${public_dns1_ipv6}"
    }

    local ipv6_dns2=$(echo "${response}" | awk -F'"' '{print $4}' | awk -F',' '{print $2}')
    [ -z "$ipv6_dns2" ] && {
        ipv6_dns2="${public_dns2_ipv6}"
    }

    dns="{
        \"dns\":{
            \"ipv4_dns1\":\"$ipv4_dns1\",
            \"ipv4_dns2\":\"$ipv4_dns2\",
            \"ipv6_dns1\":\"$ipv6_dns1\",
            \"ipv6_dns2\":\"$ipv6_dns2\"
	    }
    }"

    echo "$dns"
}

#获取拨号模式
# $1:AT串口
# $2:平台
quectel_get_mode()
{
    local at_port="$1"
    local platform="$2"

    at_command='AT+QCFG="usbnet"'
    local mode_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+QCFG:" | sed 's/+QCFG: "usbnet",//g' | sed 's/\r//g')

    if [ -z "$mode_num" ]; then
        echo "unknown"
        return
    fi

    #获取芯片平台
	if [ -z "$platform" ]; then
		local modem_number=$(uci -q get modem.@global[0].modem_number)
        for i in $(seq 0 $((modem_number-1))); do
            local at_port_tmp=$(uci -q get modem.modem${i}.at_port)
            if [ "$at_port" = "$at_port_tmp" ]; then
                platform=$(uci -q get modem.modem${i}.platform)
                break
            fi
        done
	fi
    
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
        *)
            mode="${mode_num}"
        ;;
    esac
    echo "${mode}"
}

#设置拨号模式
# $1:AT串口
# $2:拨号模式配置
quectel_set_mode()
{
    local at_port="$1"

    #获取芯片平台
    local platform
    local modem_number=$(uci -q get modem.@global[0].modem_number)
    for i in $(seq 0 $((modem_number-1))); do
        local at_port_tmp=$(uci -q get modem.modem$i.at_port)
        if [ "$at_port" = "$at_port_tmp" ]; then
            platform=$(uci -q get modem.modem$i.platform)
            break
        fi
    done

    #获取拨号模式配置
    local mode_num
    case "$platform" in
        "qualcomm")
            case "$2" in
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
            case "$2" in
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
    sh ${SCRIPT_DIR}/modem_at.sh "${at_port}" "${at_command}"
}

#获取网络偏好
# $1:AT串口
# $2:数据接口
# $3:模组名称
quectel_get_network_prefer()
{
    local at_port="$1"
    local data_interface="$2"
    local modem_name="$3"

    at_command='AT+QNWPREFCFG="mode_pref"'
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+QNWPREFCFG:" | sed 's/\r//g')
    local network_type_num=$(echo "$response" | awk -F',' '{print $2}')

    #获取网络类型
    # local network_prefer_2g="0";
    local network_prefer_3g="0";
    local network_prefer_4g="0";
    local network_prefer_5g="0";

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

    #获取频段信息
    # local band_2g_info="[]"
    local band_3g_info="[]"
    local band_4g_info="[]"
    local band_5g_info="[]"

    #生成网络偏好
    local network_prefer="{
        \"network_prefer\":[
            {\"3G\":{
                \"enable\":$network_prefer_3g,
                \"band\":$band_3g_info
            }},
            {\"4G\":{
                \"enable\":$network_prefer_4g,
                \"band\":$band_4g_info
            }},
            {\"5G\":{
                \"enable\":$network_prefer_5g,
                \"band\":$band_5g_info
            }}
        ]
    }"
    echo "${network_prefer}"
}

#设置网络偏好
# $1:AT串口
# $2:网络偏好配置
quectel_set_network_prefer()
{
    local at_port="$1"
    local network_prefer="$2"

     #获取网络偏好配置
    local network_prefer_config

    #获取选中的数量
    local count=$(echo "$network_prefer" | grep -o "1" | wc -l)
    #获取启用的网络偏好
    local enable_5g=$(echo "$network_prefer" | jq -r '.["5G"].enable')
    local enable_4g=$(echo "$network_prefer" | jq -r '.["4G"].enable')
    local enable_3g=$(echo "$network_prefer" | jq -r '.["3G"].enable')

    case "$count" in
        "1")
            if [ "$enable_3g" = "1" ]; then
                network_prefer_config="WCDMA"
            elif [ "$enable_4g" = "1" ]; then
                network_prefer_config="LTE"
            elif [ "$enable_5g" = "1" ]; then
                network_prefer_config="NR5G"
            fi
        ;;
        "2")
            if [ "$enable_3g" = "1" ] && [ "$enable_4g" = "1" ]; then
                network_prefer_config="WCDMA:LTE"
            elif [ "$enable_3g" = "1" ] && [ "$enable_5g" = "1" ]; then
                network_prefer_config="WCDMA:NR5G"
            elif [ "$enable_4g" = "1" ] && [ "$enable_5g" = "1" ]; then
                network_prefer_config="LTE:NR5G"
            fi
        ;;
        "3") network_prefer_config="AUTO" ;;
        *) network_prefer_config="AUTO" ;;
    esac

    #设置模组
    at_command='AT+QNWPREFCFG="mode_pref",'${network_prefer_config}
    sh ${SCRIPT_DIR}/modem_at.sh "${at_port}" "${at_command}"
}

#获取电压
# $1:AT串口
quectel_get_voltage()
{
    local at_port="$1"
    
    #Voltage（电压）
    at_command="AT+CBC"
	local voltage=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CBC:" | awk -F',' '{print $3}' | sed 's/\r//g')
    echo "${voltage}"
}

#获取温度
# $1:AT串口
quectel_get_temperature()
{
    local at_port="$1"
    
    #Temperature（温度）
    at_command="AT+QTEMP"

    local line=1
    while true; do
        response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+QTEMP:" | sed -n "${line}p" | awk -F'"' '{print $4}')
        [ $response -gt 0 ] && break
        line=$((line+1))
    done

    local temperature
	if [ -n "$response" ]; then
		temperature="${response}$(printf "\xc2\xb0")C"
	fi

    # response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+QTEMP:")
    # QTEMP=$(echo $response | grep -o -i "+QTEMP: [0-9]\{1,3\}")
    # if [ -z "$QTEMP" ]; then
    #     QTEMP=$(echo $response | grep -o -i "+QTEMP:[ ]\?\"XO[_-]THERM[_-][^,]\+,[\"]\?[0-9]\{1,3\}" | grep -o "[0-9]\{1,3\}")
    # fi
    # if [ -z "$QTEMP" ]; then
    #     QTEMP=$(echo $response | grep -o -i "+QTEMP:[ ]\?\"MDM-CORE-USR.\+[0-9]\{1,3\}\"" | cut -d\" -f4)
    # fi
    # if [ -z "$QTEMP" ]; then
    #     QTEMP=$(echo $response | grep -o -i "+QTEMP:[ ]\?\"MDMSS.\+[0-9]\{1,3\}\"" | cut -d\" -f4)
    # fi
    # if [ -n "$QTEMP" ]; then
    #     CTEMP=$(echo $QTEMP | grep -o -i "[0-9]\{1,3\}")$(printf "\xc2\xb0")"C"
    # fi

    echo "${temperature}"
}

#获取连接状态
# $1:AT串口
# $2:连接定义
quectel_get_connect_status()
{
    local at_port="$1"
    local define_connect="$2"

    #默认值为1
    [ -z "$define_connect" ] && {
        define_connect="1"
    }

    at_command="AT+CGPADDR=${define_connect}"
    local ipv4=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGPADDR: " | awk -F'"' '{print $2}')
    local not_ip="0.0.0.0"

    #设置连接状态
    local connect_status
    if [ -z "$ipv4" ] || [[ "$ipv4" = *"$not_ip"* ]]; then
        connect_status="disconnect"
    else
        connect_status="connect"
    fi
    
    #方法二
    # at_command="AT+QNWINFO"

	# local response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+QNWINFO:")

    # local connect_status
	# if [[ "$response" = *"No Service"* ]]; then
    #     connect_status="disconnect"
    # elif [[ "$response" = *"Unknown Service"* ]]; then
    #     connect_status="disconnect"
    # else
    #     connect_status="connect"
    # fi

    echo "$connect_status"
}

#基本信息
quectel_base_info()
{
    debug "Quectel base info"

    #Name（名称）
    at_command="AT+CGMM"
    name=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    #Manufacturer（制造商）
    at_command="AT+CGMI"
    manufacturer=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    #Revision（固件版本）
    at_command="ATI"
    revision=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "Revision:" | sed 's/Revision: //g' | sed 's/\r//g')
    # at_command="AT+CGMR"
    # revision=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #Mode（拨号模式）
    mode=$(quectel_get_mode ${at_port} ${platform} | tr 'a-z' 'A-Z')

    #Temperature（温度）
    temperature=$(quectel_get_temperature ${at_port})
}

#获取SIM卡状态
# $1:SIM卡状态标志
quectel_get_sim_status()
{
    local sim_status
    case $1 in
        "") sim_status="miss" ;;
        *"READY"*) sim_status="ready" ;;
        *"SIM PIN"*) sim_status="MT is waiting SIM PIN to be given" ;;
        *"SIM PUK"*) sim_status="MT is waiting SIM PUK to be given" ;;
        *"PH-FSIM PIN"*) sim_status="MT is waiting phone-to-SIM card password to be given" ;;
        *"PH-FSIM PIN"*) sim_status="MT is waiting phone-to-very first SIM card password to be given" ;;
        *"PH-FSIM PUK"*) sim_status="MT is waiting phone-to-very first SIM card unblocking password to be given" ;;
        *"SIM PIN2"*) sim_status="MT is waiting SIM PIN2 to be given" ;;
        *"SIM PUK2"*) sim_status="MT is waiting SIM PUK2 to be given" ;;
        *"PH-NET PIN"*) sim_status="MT is waiting network personalization password to be given" ;;
        *"PH-NET PUK"*) sim_status="MT is waiting network personalization unblocking password to be given" ;;
        *"PH-NETSUB PIN"*) sim_status="MT is waiting network subset personalization password to be given" ;;
        *"PH-NETSUB PUK"*) sim_status="MT is waiting network subset personalization unblocking password to be given" ;;
        *"PH-SP PIN"*) sim_status="MT is waiting service provider personalization password to be given" ;;
        *"PH-SP PUK"*) sim_status="MT is waiting service provider personalization unblocking password to be given" ;;
        *"PH-CORP PIN"*) sim_status="MT is waiting corporate personalization password to be given" ;;
        *"PH-CORP PUK"*) sim_status="MT is waiting corporate personalization unblocking password to be given" ;;
        *) sim_status="unknown" ;;
    esac
    echo "$sim_status"
}

#SIM卡信息
quectel_sim_info()
{
    debug "Quectel sim info"
    
    #SIM Slot（SIM卡卡槽）
    at_command="AT+QUIMSLOT?"
	sim_slot=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+QUIMSLOT:" | awk -F' ' '{print $2}' | sed 's/\r//g')

    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN"
	imei=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status_flag=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p')
    sim_status=$(quectel_get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #ISP（互联网服务提供商）
    at_command="AT+COPS?"
    isp=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | awk -F'"' '{print $2}')
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
	sim_number=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | awk -F'"' '{print $4}')

    #IMSI（国际移动用户识别码）
    at_command="AT+CIMI"
	imsi=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #ICCID（集成电路卡识别码）
    at_command="AT+ICCID"
	# iccid=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep -o "+ICCID:[ ]*[-0-9]\+" | grep -o "[-0-9]\{1,4\}")
}

#获取网络类型
# $1:网络类型数字
quectel_get_rat()
{
    local rat
    case $1 in
		"0"|"1"|"3"|"8") rat="GSM" ;;
		"2"|"4"|"5"|"6"|"9"|"10") rat="WCDMA" ;;
        "7") rat="LTE" ;;
        "11"|"12") rat="NR" ;;
	esac
    echo "${rat}"
}

#获取信号强度指示
# $1:信号强度指示数字
quectel_get_rssi()
{
    local rssi
    case $1 in
		"99") rssi="unknown" ;;
		* )  rssi=$((2 * $1 - 113)) ;;
	esac
    echo "$rssi"
}

#网络信息
quectel_network_info()
{
    debug "Quectel network info"

    #Connect Status（连接状态）
    connect_status=$(quectel_get_connect_status ${at_port} ${define_connect})
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #Network Type（网络类型）
    at_command="AT+QNWINFO"
    network_type=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+QNWINFO:" | awk -F'"' '{print $2}')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(quectel_get_rat ${rat_num})
    }

    #CSQ（信号强度）
    at_command="AT+CSQ"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    #RSSI（信号强度指示）
    # rssi_num=$(echo $response | awk -F',' '{print $1}')
    # rssi=$(quectel_get_rssi $rssi_num)
    #Ber（信道误码率）
    # ber=$(echo $response | awk -F',' '{print $2}')

    #PER（信号强度）
    # if [ -n "$csq" ]; then
    #     per=$((csq * 100/31))"%"
    # fi

    #最大比特率，信道质量指示
    at_command='AT+QNWCFG="nr5g_ambr"'
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+QNWCFG:")
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
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+QNWCFG:" | sed 's/+QNWCFG: "up\/down",//g' | sed 's/\r//g')

    #当前上传速率（单位，Byte/s）
    tx_rate=$(echo $response | awk -F',' '{print $1}')

    #当前下载速率（单位，Byte/s）
    rx_rate=$(echo $response | awk -F',' '{print $2}')
}

#获取频段
# $1:网络类型
# $2:频段数字
quectel_get_band()
{
    local band
    case $1 in
        "WCDMA") band="$2" ;;
        "LTE") band="$2" ;;
        "NR") band="$2" ;;
	esac
    echo "$band"
}

#获取带宽
# $1:网络类型
# $2:带宽数字
quectel_get_bandwidth()
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
quectel_get_scs()
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
quectel_get_phych()
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
quectel_get_sf()
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
quectel_get_slot()
{
    local slot=$1
	# case $1 in
		# "0"|"1"|"2"|"3"|"4"|"5"|"6"|"7"|"8"|"9"|"10"|"11"|"12"|"13"|"14"|"15"|"16") slot=$1 ;;
        # "0"|"1"|"2"|"3"|"4"|"5"|"6"|"7"|"8"|"9") slot=$1 ;;
	# esac
    echo "$slot"
}

#小区信息
quectel_cell_info()
{
    debug "Quectel cell info"

    at_command='AT+QENG="servingcell"'
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command)
    
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
        endc_lte_freq_band_ind=$(quectel_get_band "LTE" $endc_lte_freq_band_ind_num)
        ul_bandwidth_num=$(echo "$lte" | awk -F',' '{print $9}')
        endc_lte_ul_bandwidth=$(quectel_get_bandwidth "LTE" $ul_bandwidth_num)
        dl_bandwidth_num=$(echo "$lte" | awk -F',' '{print $10}')
        endc_lte_dl_bandwidth=$(quectel_get_bandwidth "LTE" $dl_bandwidth_num)
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
        endc_nr_band=$(quectel_get_band "NR" $endc_nr_band_num)
        nr_dl_bandwidth_num=$(echo "$nr5g_nsa" | awk -F',' '{print $10}')
        endc_nr_dl_bandwidth=$(quectel_get_bandwidth "NR" $nr_dl_bandwidth_num)
        scs_num=$(echo "$nr5g_nsa" | awk -F',' '{print $16}' | sed 's/\r//g')
        endc_nr_scs=$(quectel_get_scs $scs_num)
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
                nr_band=$(quectel_get_band "NR" $nr_band_num)
                nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $12}')
                nr_dl_bandwidth=$(quectel_get_bandwidth "NR" $nr_dl_bandwidth_num)
                nr_rsrp=$(echo "$response" | awk -F',' '{print $13}')
                nr_rsrq=$(echo "$response" | awk -F',' '{print $14}')
                nr_sinr=$(echo "$response" | awk -F',' '{print $15}')
                nr_scs_num=$(echo "$response" | awk -F',' '{print $16}')
                nr_scs=$(quectel_get_scs $nr_scs_num)
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
                lte_freq_band_ind=$(quectel_get_band "LTE" $lte_freq_band_ind_num)
                ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $11}')
                lte_ul_bandwidth=$(quectel_get_bandwidth "LTE" $ul_bandwidth_num)
                dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $12}')
                lte_dl_bandwidth=$(quectel_get_bandwidth "LTE" $dl_bandwidth_num)
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
                wcdma_phych=$(quectel_get_phych $wcdma_phych_num)
                wcdma_sf_num=$(echo "$response" | awk -F',' '{print $14}')
                wcdma_sf=$(quectel_get_sf $wcdma_sf_num)
                wcdma_slot_num=$(echo "$response" | awk -F',' '{print $15}')
                wcdma_slot=$(quectel_get_slot $wcdma_slot_num)
                wcdma_speech_code=$(echo "$response" | awk -F',' '{print $16}')
                wcdma_com_mod=$(echo "$response" | awk -F',' '{print $17}' | sed 's/\r//g')
            ;;
        esac
    fi

    return

    NR_NSA=$(echo $response | grep -o -i "+QENG:[ ]\?\"NR5G-NSA\",")
    NR_SA=$(echo $response | grep -o -i "+QENG: \"SERVINGCELL\",[^,]\+,\"NR5G-SA\",\"[DFT]\{3\}\",")
    if [ -n "$NR_NSA" ]; then
        QENG=",,"$(echo $response" " | grep -o -i "+QENG: \"LTE\".\+\"NR5G-NSA\"," | tr " " ",")
        QENG5=$(echo $response | grep -o -i "+QENG:[ ]\?\"NR5G-NSA\",[0-9]\{3\},[0-9]\{2,3\},[0-9]\{1,5\},-[0-9]\{2,5\},[-0-9]\{1,3\},-[0-9]\{2,3\},[0-9]\{1,7\},[0-9]\{1,3\}.\{1,6\}")
        if [ -z "$QENG5" ]; then
            QENG5=$(echo $response | grep -o -i "+QENG:[ ]\?\"NR5G-NSA\",[0-9]\{3\},[0-9]\{2,3\},[0-9]\{1,5\},-[0-9]\{2,3\},[-0-9]\{1,3\},-[0-9]\{2,3\}")
            if [ -n "$QENG5" ]; then
                QENG5=$QENG5",,"
            fi
        fi
    elif [ -n "$NR_SA" ]; then
	    QENG=$(echo $NR_SA | tr " " ",")
	    QENG5=$(echo $response | grep -o -i "+QENG: \"SERVINGCELL\",[^,]\+,\"NR5G-SA\",\"[DFT]\{3\}\",[ 0-9]\{3,4\},[0-9]\{2,3\},[0-9A-F]\{1,10\},[0-9]\{1,5\},[0-9A-F]\{2,6\},[0-9]\{6,7\},[0-9]\{1,3\},[0-9]\{1,2\},-[0-9]\{2,5\},-[0-9]\{2,3\},[-0-9]\{1,3\}")
    else
	    QENG=$(echo $response" " | grep -o -i "+QENG: [^ ]\+ " | tr " " ",")
    fi
    
    RAT=$(echo $QENG | cut -d, -f4 | grep -o "[-A-Z5]\{3,7\}")
    case $RAT in
        "GSM")
            # MODE="GSM"
            ;;
        "WCDMA")
            channel=$(echo $QENG | cut -d, -f9)
            rscp="-"$(echo $QENG | cut -d, -f12 | grep -o "[0-9]\{1,3\}")
            ecio=$(echo $QENG | cut -d, -f13)
            ecio="-"$(echo $ecio | grep -o "[0-9]\{1,3\}")
            ;;
        "LTE"|"CAT-M"|"CAT-NB")
            PCI=$(echo $QENG | cut -d, -f9)
            channel=$(echo $QENG | cut -d, -f10)
            LBAND=$(echo $QENG | cut -d, -f11 | grep -o "[0-9]\{1,3\}")
            BW=$(echo $QENG | cut -d, -f12)
            lte_bw
            BWU=$BW
            BW=$(echo $QENG | cut -d, -f13)
            lte_bw
            BWD=$BW
            if [ -z "$BWD" ]; then
                BWD="unknown"
            fi
            if [ -z "$BWU" ]; then
                BWU="unknown"
            fi
            if [ -n "$LBAND" ]; then
                LBAND="B"$LBAND" (Bandwidth $BWD MHz Down | $BWU MHz Up)"
            fi
            RSRP=$(echo $QENG | cut -d, -f15 | grep -o "[0-9]\{1,3\}")
            if [ -n "$RSRP" ]; then
                RSCP="-"$RSRP
                RSRPLTE=$RSCP
            fi
            rsrq=$(echo $QENG | cut -d, -f16 | grep -o "[0-9]\{1,3\}")
            if [ -n "$rsrq" ]; then
                ecio="-"$rsrq
            fi
            rssi=$(echo $QENG | cut -d, -f17 | grep -o "\-[0-9]\{1,3\}")
            if [ -n "$rssi" ]; then
                CSQ_RSSI=$rssi" dBm"
            fi
            sinrr=$(echo $QENG | cut -d, -f18 | grep -o "[0-9]\{1,3\}")
            if [ -n "$sinrr" ]; then
                if [ $sinrr -le 25 ]; then
                    sinrr=$((($(echo $sinrr) * 2) -20))" dB"
                fi
            fi

            if [ -n "$NR_NSA" ]; then
                if [ -n "$QENG5" ]  && [ -n "$LBAND" ] && [ "$RSCP" != "-" ] && [ "$ecio" != "-" ]; then
                    PCI="$PCI, "$(echo $QENG5 | cut -d, -f4)
                    SCHV=$(echo $QENG5 | cut -d, -f8)
                    SLBV=$(echo $QENG5 | cut -d, -f9)
                    BW=$(echo $QENG5 | cut -d, -f10 | grep -o "[0-9]\{1,3\}")
                    if [ -n "$SLBV" ]; then
                        LBAND=$LBAND"<br />n"$SLBV
                        if [ -n "$BW" ]; then
                            nr_bw
                            LBAND=$LBAND" (Bandwidth $BW MHz)"
                        fi
                        if [ "$SCHV" -ge 123400 ]; then
                            channel=$channel", "$SCHV
                        else
                            channel=$channel", -"
                        fi
                    else
                        LBAND=$LBAND"<br />nxx (unknown NR5G band)"
                        channel=$channel", -"
                    fi
                    RSCP=$RSCP" dBm<br />"$(echo $QENG5 | cut -d, -f5)
                    sinrr=$(echo $QENG5 | cut -d, -f6 | grep -o "[0-9]\{1,3\}")
                    if [ -n "$sinrr" ]; then
                        if [ $sinrr -le 30 ]; then
                            SINR=$SINR"<br />"$((($(echo $sinrr) * 2) -20))" dB"
                        fi
                    fi
                    ecio=$ecio" (4G) dB<br />"$(echo $QENG5 | cut -d, -f7)" (5G) "
                fi
            fi
            if [ -z "$LBAND" ]; then
                LBAND="-"
            else
                if [ -n "$QCA" ]; then
                    QCA=$(echo $QCA | grep -o "\"S[CS]\{2\}\"[-0-9A-Z,\"]\+")
                    for QCAL in $(echo "$QCA"); do
                        if [ $(echo "$QCAL" | cut -d, -f7) = "2" ]; then
                            SCHV=$(echo $QCAL | cut -d, -f2 | grep -o "[0-9]\+")
                            SRATP="B"
                            if [ -n "$SCHV" ]; then
                                channel="$channel, $SCHV"
                                if [ "$SCHV" -gt 123400 ]; then
                                    SRATP="n"
                                fi
                            fi
                            SLBV=$(echo $QCAL | cut -d, -f6 | grep -o "[0-9]\{1,2\}")
                            if [ -n "$SLBV" ]; then
                                LBAND=$LBAND"<br />"$SRATP$SLBV
                                BWD=$(echo $QCAL | cut -d, -f3 | grep -o "[0-9]\{1,3\}")
                                if [ -n "$BWD" ]; then
                                    UPDOWN=$(echo $QCAL | cut -d, -f13)
                                    case "$UPDOWN" in
                                        "UL" )
                                            CATYPE="CA"$(printf "\xe2\x86\x91") ;;
                                        "DL" )
                                            CATYPE="CA"$(printf "\xe2\x86\x93") ;;
                                        * )
                                            CATYPE="CA" ;;
                                    esac
                                    if [ $BWD -gt 14 ]; then
                                        LBAND=$LBAND" ("$CATYPE", Bandwidth "$(($(echo $BWD) / 5))" MHz)"
                                    else
                                        LBAND=$LBAND" ("$CATYPE", Bandwidth 1.4 MHz)"
                                    fi
                                fi
                                LBAND=$LBAND
                            fi
                            PCI="$PCI, "$(echo $QCAL | cut -d, -f8)
                        fi
                    done
                fi
            fi
            if [ $RAT = "CAT-M" ] || [ $RAT = "CAT-NB" ]; then
                LBAND="B$(echo $QENG | cut -d, -f11) ($RAT)"
            fi
            ;;
        "NR5G-SA")
            if [ -n "$QENG5" ]; then
                #AT+qnwcfg="NR5G_AMBR"  #查询速度
                PCI=$(echo $QENG5 | cut -d, -f8)
                channel=$(echo $QENG5 | cut -d, -f10)
                LBAND=$(echo $QENG5 | cut -d, -f11)
                BW=$(echo $QENG5 | cut -d, -f12)
                nr_bw
                LBAND="n"$LBAND" (Bandwidth $BW MHz)"
                RSCP=$(echo $QENG5 | cut -d, -f13)
                ecio=$(echo $QENG5 | cut -d, -f14)
                if [ "$CSQ_PER" = "-" ]; then
                    RSSI=$(rsrp2rssi $RSCP $BW)
                    CSQ_PER=$((100 - (($RSSI + 51) * 100/-62)))"%"
                    CSQ=$((($RSSI + 113) / 2))
                    CSQ_RSSI=$RSSI" dBm"
                fi
                SINRR=$(echo $QENG5 | cut -d, -f15 | grep -o "[0-9]\{1,3\}")
                if [ -n "$SINRR" ]; then
                    if [ $SINRR -le 30 ]; then
                        SINR=$((($(echo $SINRR) * 2) -20))" dB"
                    fi
                fi
            fi
            ;;
    esac
}

# Quectel获取基站信息
Quectel_Cellinfo()
{
    # return
    #cellinfo0.gcom
    OX1=$( sh modem_at.sh $at_port "AT+COPS=3,0;+COPS?")
    OX2=$( sh modem_at.sh $at_port "AT+COPS=3,2;+COPS?")
    OX=$OX1" "$OX2

    #cellinfo.gcom
    OY1=$( sh modem_at.sh $at_port "AT+CREG=2;+CREG?;+CREG=0")
    OY2=$( sh modem_at.sh $at_port "AT+CEREG=2;+CEREG?;+CEREG=0")
    OY3=$( sh modem_at.sh $at_port "AT+C5GREG=2;+C5GREG?;+C5GREG=0")
    OY=$OY1" "$OY2" "$OY3


    OXx=$OX
    OX=$(echo $OX | tr 'a-z' 'A-Z')
    OY=$(echo $OY | tr 'a-z' 'A-Z')
    OX=$OX" "$OY

    #debug "$OX"
    #debug "$OY"

    COPS="-"
    COPS_MCC="-"
    COPS_MNC="-"
    COPSX=$(echo $OXx | grep -o "+COPS: [01],0,.\+," | cut -d, -f3 | grep -o "[^\"]\+")

    if [ "x$COPSX" != "x" ]; then
        COPS=$COPSX
    fi

    COPSX=$(echo $OX | grep -o "+COPS: [01],2,.\+," | cut -d, -f3 | grep -o "[^\"]\+")

    if [ "x$COPSX" != "x" ]; then
        COPS_MCC=${COPSX:0:3}
        COPS_MNC=${COPSX:3:3}
        if [ "$COPS" = "-" ]; then
            COPS=$(awk -F[\;] '/'$COPS'/ {print $2}' $ROOTER/signal/mccmnc.data)
            [ "x$COPS" = "x" ] && COPS="-"
        fi
    fi

    if [ "$COPS" = "-" ]; then
        COPS=$(echo "$O" | awk -F[\"] '/^\+COPS: 0,0/ {print $2}')
        if [ "x$COPS" = "x" ]; then
            COPS="-"
            COPS_MCC="-"
            COPS_MNC="-"
        fi
    fi
    COPS_MNC=" "$COPS_MNC

    OX=$(echo "${OX//[ \"]/}")
    CID=""
    CID5=""
    RAT=""
    REGV=$(echo "$OX" | grep -o "+C5GREG:2,[0-9],[A-F0-9]\{2,6\},[A-F0-9]\{5,10\},[0-9]\{1,2\}")
    if [ -n "$REGV" ]; then
        LAC5=$(echo "$REGV" | cut -d, -f3)
        LAC5=$LAC5" ($(printf "%d" 0x$LAC5))"
        CID5=$(echo "$REGV" | cut -d, -f4)
        CID5L=$(printf "%010X" 0x$CID5)
        RNC5=${CID5L:1:6}
        RNC5=$RNC5" ($(printf "%d" 0x$RNC5))"
        CID5=${CID5L:7:3}
        CID5="Short $(printf "%X" 0x$CID5) ($(printf "%d" 0x$CID5)), Long $(printf "%X" 0x$CID5L) ($(printf "%d" 0x$CID5L))"
        RAT=$(echo "$REGV" | cut -d, -f5)
    fi
    REGV=$(echo "$OX" | grep -o "+CEREG:2,[0-9],[A-F0-9]\{2,4\},[A-F0-9]\{5,8\}")
    REGFMT="3GPP"
    if [ -z "$REGV" ]; then
        REGV=$(echo "$OX" | grep -o "+CEREG:2,[0-9],[A-F0-9]\{2,4\},[A-F0-9]\{1,3\},[A-F0-9]\{5,8\}")
        REGFMT="SW"
    fi
    if [ -n "$REGV" ]; then
        LAC=$(echo "$REGV" | cut -d, -f3)
        LAC=$(printf "%04X" 0x$LAC)" ($(printf "%d" 0x$LAC))"
        if [ $REGFMT = "3GPP" ]; then
            CID=$(echo "$REGV" | cut -d, -f4)
        else
            CID=$(echo "$REGV" | cut -d, -f5)
        fi
        CIDL=$(printf "%08X" 0x$CID)
        RNC=${CIDL:1:5}
        RNC=$RNC" ($(printf "%d" 0x$RNC))"
        CID=${CIDL:6:2}
        CID="Short $(printf "%X" 0x$CID) ($(printf "%d" 0x$CID)), Long $(printf "%X" 0x$CIDL) ($(printf "%d" 0x$CIDL))"

    else
        REGV=$(echo "$OX" | grep -o "+CREG:2,[0-9],[A-F0-9]\{2,4\},[A-F0-9]\{2,8\}")
        if [ -n "$REGV" ]; then
            LAC=$(echo "$REGV" | cut -d, -f3)
            CID=$(echo "$REGV" | cut -d, -f4)
            if [ ${#CID} -gt 4 ]; then
                LAC=$(printf "%04X" 0x$LAC)" ($(printf "%d" 0x$LAC))"
                CIDL=$(printf "%08X" 0x$CID)
                RNC=${CIDL:1:3}
                CID=${CIDL:4:4}
                CID="Short $(printf "%X" 0x$CID) ($(printf "%d" 0x$CID)), Long $(printf "%X" 0x$CIDL) ($(printf "%d" 0x$CIDL))"
            else
                LAC=""
            fi
        else
            LAC=""
        fi
    fi
    REGSTAT=$(echo "$REGV" | cut -d, -f2)
    if [ "$REGSTAT" == "5" -a "$COPS" != "-" ]; then
        COPS_MNC=$COPS_MNC" (Roaming)"
    fi
    if [ -n "$CID" -a -n "$CID5" ] && [ "$RAT" == "13" -o "$RAT" == "10" ]; then
        LAC="4G $LAC, 5G $LAC5"
        CID="4G $CID<br />5G $CID5"
        RNC="4G $RNC, 5G $RNC5"
    elif [ -n "$CID5" ]; then
        LAC=$LAC5
        CID=$CID5
        RNC=$RNC5
    fi
    if [ -z "$LAC" ]; then
        LAC="-"
        CID="-"
        RNC="-"
    fi
}

#获取移远模组信息
# $1:AT串口
# $2:平台
# $3:连接定义
get_quectel_info()
{
    debug "get quectel info"
    #设置AT串口
    at_port="$1"
    platform="$2"
    define_connect="$3"

    #基本信息
    quectel_base_info

	#SIM卡信息
    quectel_sim_info
    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #网络信息
    quectel_network_info
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #小区信息
    quectel_cell_info

    return
    
    # Quectel_Cellinfo

    #
    OX=$( sh modem_at.sh $at_port "AT+QCAINFO"  | grep "+QCAINFO:"  )
    QCA=$(echo $OX" " | grep -o -i "+QCAINFO: \"S[CS]\{2\}\".\+NWSCANMODE" | tr " " ",")


    #
    OX=$( sh modem_at.sh $at_port 'AT+QCFG="nwscanmode"'  | grep "+QCAINFO:"  )
    QNSM=$(echo $OX | grep -o -i "+QCFG: \"NWSCANMODE\",[0-9]")
    QNSM=$(echo "$QNSM" | grep -o "[0-9]")
    if [ -n "$QNSM" ]; then
        MODTYPE="6"
        case $QNSM in
        "0" )
            NETMODE="1" ;;
        "1" )
            NETMODE="3" ;;
        "2"|"5" )
            NETMODE="5" ;;
        "3" )
            NETMODE="7" ;;
        esac
    fi
    if [ -n "$QNWP" ]; then
        MODTYPE="6"
        case $QNWP in
        "AUTO" )
            NETMODE="1" ;;
        "WCDMA" )
            NETMODE="5" ;;
        "LTE" )
            NETMODE="7" ;;
        "LTE:NR5G" )
            NETMODE="8" ;;
        "NR5G" )
            NETMODE="9" ;;
        esac
    fi


    #
    OX=$( sh modem_at.sh $at_port 'AT+QNWPREFCFG="mode_pref"'  | grep "+QNWPREFCFG:"  )
    QNWP=$(echo $OX | grep -o -i "+QNWPREFCFG: \"MODE_PREF\",[A-Z5:]\+" | cut -d, -f2)

    #
    OX=$( sh modem_at.sh $at_port "AT+QRSRP"  | grep "+QRSRP:"  )
    QRSRP=$(echo "$OX" | grep -o -i "+QRSRP:[^,]\+,-[0-9]\{1,5\},-[0-9]\{1,5\},-[0-9]\{1,5\}[^ ]*")
    if [ -n "$QRSRP" ] && [ "$RAT" != "WCDMA" ]; then
        QRSRP1=$(echo $QRSRP | cut -d, -f1 | grep -o "[-0-9]\+")
        QRSRP2=$(echo $QRSRP | cut -d, -f2)
        QRSRP3=$(echo $QRSRP | cut -d, -f3)
        QRSRP4=$(echo $QRSRP | cut -d, -f4)
        QRSRPtype=$(echo $QRSRP | cut -d, -f5)
        if [ "$QRSRPtype" == "NR5G" ]; then
            if [ -n "$NR_SA" ]; then
                RSCP=$QRSRP1
                if [ -n "$QRPRP2" -a "$QRSRP2" != "-32768" ]; then
                    RSCP1="RxD "$QRSRP2
                fi
                if [ -n "$QRSRP3" -a "$QRSRP3" != "-32768" ]; then
                    RSCP=$RSCP" dBm<br />"$QRSRP3
                fi
                if [ -n "$QRSRP4" -a "$QRSRP4" != "-32768" ]; then
                    RSCP1="RxD "$QRSRP4
                fi
            else
                RSCP=$RSRPLTE
                if [ -n "$QRSRP1" -a "$QRSRP1" != "-32768" ]; then
                    RSCP=$RSCP" (4G) dBm<br />"$QRSRP1
                    if [ -n "$QRSRP2" -a "$QRSRP2" != "-32768" ]; then
                        RSCP="$RSCP,$QRSRP2"
                        if [ -n "$QRSRP3" -a "$QRSRP3" != "-32768" ]; then
                            RSCP="$RSCP,$QRSRP3"
                            if [ -n "$QRSRP4" -a "$QRSRP4" != "-32768" ]; then
                                RSCP="$RSCP,$QRSRP4"
                            fi
                        fi
                        RSCP=$RSCP" (5G) "
                    fi
                fi
            fi
        elif [ "$QRSRP2$QRSRP3$QRSRP4" != "-44-44-44" -a -z "$QENG5" ]; then
            RSCP=$QRSRP1
            if [ "$QRSRP3$QRSRP4" == "-140-140" -o "$QRSRP3$QRSRP4" == "-44-44" -o "$QRSRP3$QRSRP4" == "-32768-32768" ]; then
                RSCP1="RxD "$(echo $QRSRP | cut -d, -f2)
            else
                RSCP=$RSCP" dBm (RxD "$QRSRP2" dBm)<br />"$QRSRP3
                RSCP1="RxD "$QRSRP4
            fi
        fi
    fi


}