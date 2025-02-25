#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"

#预设
fibocom_presets()
{
    #设置IPv6地址格式
	at_command='AT+CGPIAF=1,0,0,0'
	sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"

    #自动DHCP
	at_command='AT+GTAUTODHCP=1'
	sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"

	#启用IP直通
	at_command='AT+GTIPPASS=1,1'
	sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"

	#启用自动拨号
	at_command='AT+GTAUTOCONNECT=1'
	sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"
}

#获取DNS
# $1:AT串口
# $2:连接定义
fibocom_get_dns()
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
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+GTDNS: " | grep -E '[0-9]+.[0-9]+.[0-9]+.[0-9]+' | sed -n '1p')

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
fibocom_get_mode()
{
    local at_port="$1"
    local platform="$2"

    at_command="AT+GTUSBMODE?"
    local mode_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+GTUSBMODE:" | sed 's/+GTUSBMODE: //g' | sed 's/\r//g')

    if [ -z "$mode_num" ]; then
        echo "unknown"
        return
    fi

    #获取芯片平台
	if [ -z "$platform" ]; then
		local modem_number=$(uci -q get modem.@global[0].modem_number)
        for i in $(seq 0 $((modem_number-1))); do
            local at_port_tmp=$(uci -q get modem.modem$i.at_port)
            if [ "$at_port" = "$at_port_tmp" ]; then
                platform=$(uci -q get modem.modem$i.platform)
                break
            fi
        done
	fi

    local mode
    case "$platform" in
        "qualcomm")
            case "$mode_num" in
                "17"|"31"|"32"|"34") mode="qmi" ;;
                # "32") mode="gobinet" ;;
                "18"|"23"|"33"|"35") mode="ecm" ;;
                "29"|"30") mode="mbim" ;;
                "24") mode="rndis" ;;
                "18") mode="ncm" ;;
                *) mode="$mode_num" ;;
            esac
        ;;
        "unisoc")
            case "$mode_num" in
                "34"|"35") mode="ecm" ;;
                "40"|"41") mode="mbim" ;;
                "38"|"39") mode="rndis" ;;
                "36"|"37") mode="ncm" ;;
                *) mode="$mode_num" ;;
            esac
        ;;
        "mediatek")
            case "$mode_num" in
                "29") mode="mbim" ;;
                "40"|"41") mode="rndis" ;;
                *) mode="$mode_num" ;;
            esac
        ;;
        *)
            mode="$mode_num"
        ;;
    esac
    echo "${mode}"
}

#设置拨号模式
# $1:AT串口
# $2:拨号模式配置
fibocom_set_mode()
{
    local at_port="$1"
    local mode_config="$2"

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
        *)
            mode_num="32"
        ;;
    esac

    #设置模组
    at_command="AT+GTUSBMODE=${mode_num}"
    sh ${SCRIPT_DIR}/modem_at.sh ${at_port} "${at_command}"
}

#获取网络偏好
# $1:AT串口
# $2:数据接口
# $3:模组名称
fibocom_get_network_prefer()
{
    local at_port="$1"
    local data_interface="$2"
    local modem_name="$3"
    
    at_command="AT+GTACT?"
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+GTACT:" | sed 's/+GTACT: //g')
    local network_type_num=$(echo "$response" | awk -F',' '{print $1}')

    #获取网络类型
    # local network_prefer_2g="0";
    local network_prefer_3g="0";
    local network_prefer_4g="0";
    local network_prefer_5g="0";

    #匹配不同的网络类型
    case "$network_type_num" in
        "1") network_prefer_3g="1" ;;
        "2") network_prefer_4g="1" ;;
        "4")
            network_prefer_3g="1"
            network_prefer_4g="1"
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
        "10"|"20"|*)
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
        ;;
    esac

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
fibocom_set_network_prefer()
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
                network_prefer_config="1"
            elif [ "$enable_4g" = "1" ]; then
                network_prefer_config="2"
            elif [ "$enable_5g" = "1" ]; then
                network_prefer_config="14"
            fi
        ;;
        "2")
            if [ "$enable_3g" = "1" ] && [ "$enable_4g" = "1" ]; then
                network_prefer_config="4"
            elif [ "$enable_3g" = "1" ] && [ "$enable_5g" = "1" ]; then
                network_prefer_config="16"
            elif [ "$enable_4g" = "1" ] && [ "$enable_5g" = "1" ]; then
                network_prefer_config="17"
            fi
        ;;
        "3") network_prefer_config="20" ;;
        *) network_prefer_config="10" ;;
    esac
echo "$network_prefer_config" >> /root/a
    #设置模组
    at_command="AT+GTACT=${network_prefer_config}"
    sh ${SCRIPT_DIR}/modem_at.sh $at_port "$at_command"
}

#获取电压
# $1:AT串口
fibocom_get_voltage()
{
    local at_port="$1"
    
    #Voltage（电压）
    at_command="AT+CBC"
	local voltage=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CBC:" | awk -F',' '{print $2}' | sed 's/\r//g')
    echo "${voltage}"
}

#获取温度
# $1:AT串口
fibocom_get_temperature()
{
    local at_port="$1"
    
    #Temperature（温度）
    at_command="AT+MTSM=1,6"
	response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+MTSM: " | sed 's/+MTSM: //g' | sed 's/\r//g')

    [ -z "$response" ] && {
        #Fx160及以后型号
        at_command="AT+GTLADC"
	    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "cpu" | awk -F' ' '{print $2}' | sed 's/\r//g')
        response="${response:0:2}"
    }

    [ -z "$response" ] && {
        #联发科平台
        at_command="AT+GTSENRDTEMP=1"
        response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+GTSENRDTEMP: " | awk -F',' '{print $2}' | sed 's/\r//g')
        response="${response:0:2}"
    }

    local temperature
    [ -n "$response" ] && {
        temperature="${response}$(printf "\xc2\xb0")C"
    }

    echo "${temperature}"
}

#获取连接状态
# $1:AT串口
# $2:连接定义
fibocom_get_connect_status()
{
    local at_port="$1"
    local define_connect="$2"

    #默认值为1
    [ -z "$define_connect" ] && {
        define_connect="1"
    }

    at_command="AT+CGPADDR=${define_connect}"
    local ipv4=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CGPADDR: " | awk -F'"' '{print $2}')
    local not_ip="0.0.0.0"

    #设置连接状态
    local connect_status
    if [ -z "$ipv4" ] || [[ "$ipv4" = *"$not_ip"* ]]; then
        connect_status="disconnect"
    else
        connect_status="connect"
    fi

    echo "${connect_status}"
}

#基本信息
fibocom_base_info()
{
    debug "Fibocom base info"

    #Name（名称）
    at_command="AT+CGMM?"
    name=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGMM: " | awk -F'"' '{print $2}')
    #Manufacturer（制造商）
    at_command="AT+CGMI?"
    manufacturer=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGMI: " | awk -F'"' '{print $2}')
    #Revision（固件版本）
    at_command="AT+CGMR?"
    revision=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGMR: " | awk -F'"' '{print $2}')

    #Mode（拨号模式）
    mode=$(fibocom_get_mode ${at_port} ${platform} | tr 'a-z' 'A-Z')

    #Temperature（温度）
    temperature=$(fibocom_get_temperature $at_port)
}

#获取SIM卡状态
# $1:SIM卡状态标志
fibocom_get_sim_status()
{
    local sim_status
    case $1 in
        "") sim_status="miss" ;;
        *"ERROR"*) sim_status="miss" ;;
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
    echo "${sim_status}"
}

#SIM卡信息
fibocom_sim_info()
{
    debug "Fibocom sim info"
    
    #SIM Slot（SIM卡卡槽）
    at_command="AT+GTDUALSIM?"
	sim_slot=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+GTDUALSIM" | awk -F'"' '{print $2}' | sed 's/SUB//g')

    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN?"
	imei=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CGSN: " | awk -F'"' '{print $2}')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status_flag=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CPIN: ")
    [ -z "$sim_status_flag" ] && {
        sim_status_flag=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CME")
    }
    sim_status=$(fibocom_get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #ISP（互联网服务提供商）
    at_command="AT+COPS?"
    isp=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+COPS" | awk -F'"' '{print $2}')
    # if [ "$isp" = "CHN-CMCC" ] || [ "$isp" = "CMCC" ]|| [ "$isp" = "46000" ]; then
    #     isp="中国移动"
    # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "UNICOM" ] || [ "$isp" = "46001" ]; then
    #     isp="中国联通"
    # elif [ "$isp" = "CHN-CT" ] || [ "$isp" = "CT" ] || [ "$isp" = "46011" ]; then
    #     isp="中国电信"
    # fi

    #SIM Number（SIM卡号码，手机号）
    at_command="AT+CNUM"
	sim_number=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CNUM: " | awk -F'"' '{print $2}')
    [ -z "$sim_number" ] && {
        sim_number=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CNUM: " | awk -F'"' '{print $4}')
    }
	
    #IMSI（国际移动用户识别码）
    at_command="AT+CIMI?"
    imsi=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CIMI: " | awk -F' ' '{print $2}' | sed 's/"//g' | sed 's/\r//g')
	[ -z "$sim_number" ] && {
        imsi=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CIMI: " | awk -F'"' '{print $2}')
    }

    #ICCID（集成电路卡识别码）
    at_command="AT+ICCID"
	iccid=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep -o "+ICCID:[ ]*[-0-9]\+" | grep -o "[-0-9]\{1,4\}")
}

#获取网络类型
# $1:网络类型数字
fibocom_get_rat()
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

#获取信号强度指示（4G）
# $1:信号强度指示数字
fibocom_get_rssi()
{
    local rssi
    case $1 in
		"99") rssi="unknown" ;;
		* )  rssi=$((2 * $1 - 113)) ;;
	esac
    echo "$rssi"
}

#网络信息
fibocom_network_info()
{
    debug "Fibocom network info"

    #Connect Status（连接状态）
    connect_status=$(fibocom_get_connect_status ${at_port} ${define_connect})
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #Network Type（网络类型）
    at_command="AT+PSRAT?"
    network_type=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+PSRAT:" | sed 's/+PSRAT: //g' | sed 's/\r//g')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(fibocom_get_rat ${rat_num})
    }

    #设置网络类型为5G时，信号强度指示用RSRP代替
    # at_command="AT+GTCSQNREN=1"
    # sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command

    #CSQ（信号强度）
    at_command="AT+CSQ"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    #RSSI（4G信号强度指示）
    # rssi_num=$(echo $response | awk -F',' '{print $1}')
    # rssi=$(fibocom_get_rssi $rssi_num)
    #BER（4G信道误码率）
    # ber=$(echo $response | awk -F',' '{print $2}')

    # #PER（信号强度）
    # if [ -n "$csq" ]; then
    #     per=$(($csq * 100/31))"%"
    # fi

    #速率统计
    at_command="AT+GTSTATIS?"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+GTSTATIS:" | sed 's/+GTSTATIS: //g' | sed 's/\r//g')

    #当前上传速率（单位，Byte/s）
    tx_rate=$(echo $response | awk -F',' '{print $2}')

    #当前下载速率（单位，Byte/s）
    rx_rate=$(echo $response | awk -F',' '{print $1}')
}

#获取频段
# $1:网络类型
# $2:频段数字
fibocom_get_band()
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
fibocom_get_bandwidth()
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
                "10"|"15"|"20"|"25"|"30"|"40"|"50"|"60"|"70"|"80"|"90"|"100"|"200"|"400") bandwidth="$bandwidth_num" ;;
            esac
        ;;
	esac
    echo "$bandwidth"
}

#获取信噪比
# $1:网络类型
# $2:信噪比数字
fibocom_get_sinr()
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
fibocom_get_rxlev()
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
fibocom_get_rsrp()
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
fibocom_get_rsrq()
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
fibocom_get_rssnr()
{
    #去掉小数点后的0
    local rssnr=$(awk "BEGIN{ printf \"%.2f\", $1 / 2 }" | sed 's/\.*0*$//')
    echo "$rssnr"
}

#获取Ec/Io
# $1:Ec/Io数字
fibocom_get_ecio()
{
    local ecio=$(awk "BEGIN{ printf \"%.2f\", $1 * 0.5 - 24.5 }" | sed 's/\.*0*$//')
    echo "$ecio"
}

#小区信息
fibocom_cell_info()
{
    debug "Fibocom cell info"

    at_command='AT+GTCCINFO?'
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command)
    
    local rat=$(echo "$response" | grep "service" | awk -F' ' '{print $1}')

    #适配联发科平台（FM350-GL）
    [ -z "$rat" ] && {
        at_command='AT+COPS?'
        rat_num=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        rat=$(fibocom_get_rat ${rat_num})
    }

    for response in $response; do
        #排除+GTCCINFO:、NR service cell:还有空行
        [ -n "$response" ] && [[ "$response" = *","* ]] && {

            case $rat in
                "NR")
                    network_mode="NR5G-SA Mode"
                    nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    nr_tac=$(echo "$response" | awk -F',' '{print $5}')
                    nr_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    nr_arfcn=$(echo "$response" | awk -F',' '{print $7}')
                    nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    nr_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    nr_band=$(fibocom_get_band "NR" ${nr_band_num})
                    nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    nr_dl_bandwidth=$(fibocom_get_bandwidth "NR" ${nr_dl_bandwidth_num})
                    nr_sinr_num=$(echo "$response" | awk -F',' '{print $11}')
                    nr_sinr=$(fibocom_get_sinr "NR" ${nr_sinr_num})
                    nr_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    nr_rxlev=$(fibocom_get_rxlev "NR" ${nr_rxlev_num})
                    nr_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    nr_rsrp=$(fibocom_get_rsrp "NR" ${nr_rsrp_num})
                    nr_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    nr_rsrq=$(fibocom_get_rsrq "NR" ${nr_rsrq_num})
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
                    endc_lte_band=$(fibocom_get_band "LTE" ${endc_lte_band_num})
                    ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    endc_lte_ul_bandwidth=$(fibocom_get_bandwidth "LTE" ${ul_bandwidth_num})
                    endc_lte_dl_bandwidth="$endc_lte_ul_bandwidth"
                    endc_lte_rssnr_num=$(echo "$response" | awk -F',' '{print $11}')
                    endc_lte_rssnr=$(fibocom_get_rssnr ${endc_lte_rssnr_num})
                    endc_lte_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    endc_lte_rxlev=$(fibocom_get_rxlev "LTE" ${endc_lte_rxlev_num})
                    endc_lte_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    endc_lte_rsrp=$(fibocom_get_rsrp "LTE" ${endc_lte_rsrp_num})
                    endc_lte_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    endc_lte_rsrq=$(fibocom_get_rsrq "LTE" ${endc_lte_rsrq_num})
                    #NR5G-NSA
                    endc_nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    endc_nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    endc_nr_tac=$(echo "$response" | awk -F',' '{print $5}')
                    endc_nr_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    endc_nr_arfcn=$(echo "$response" | awk -F',' '{print $7}')
                    endc_nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    endc_nr_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    endc_nr_band=$(fibocom_get_band "NR" ${endc_nr_band_num})
                    nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    endc_nr_dl_bandwidth=$(fibocom_get_bandwidth "NR" ${nr_dl_bandwidth_num})
                    endc_nr_sinr_num=$(echo "$response" | awk -F',' '{print $11}')
                    endc_nr_sinr=$(fibocom_get_sinr "NR" ${endc_nr_sinr_num})
                    endc_nr_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    endc_nr_rxlev=$(fibocom_get_rxlev "NR" ${endc_nr_rxlev_num})
                    endc_nr_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    endc_nr_rsrp=$(fibocom_get_rsrp "NR" ${endc_nr_rsrp_num})
                    endc_nr_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    endc_nr_rsrq=$(fibocom_get_rsrq "NR" ${endc_nr_rsrq_num})
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
                    lte_band=$(fibocom_get_band "LTE" ${lte_band_num})
                    ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    lte_ul_bandwidth=$(fibocom_get_bandwidth "LTE" ${ul_bandwidth_num})
                    lte_dl_bandwidth="$lte_ul_bandwidth"
                    lte_rssnr=$(echo "$response" | awk -F',' '{print $11}')
                    lte_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    lte_rxlev=$(fibocom_get_rxlev "LTE" ${lte_rxlev_num})
                    lte_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    lte_rsrp=$(fibocom_get_rsrp "LTE" ${lte_rsrp_num})
                    lte_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    lte_rsrq=$(fibocom_get_rsrq "LTE" ${lte_rsrq_num})
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
                    wcdma_band=$(fibocom_get_band "WCDMA" ${wcdma_band_num})
                    wcdma_ecno=$(echo "$response" | awk -F',' '{print $10}')
                    wcdma_rscp=$(echo "$response" | awk -F',' '{print $11}')
                    wcdma_rac=$(echo "$response" | awk -F',' '{print $12}')
                    wcdma_rxlev_num=$(echo "$response" | awk -F',' '{print $13}')
                    wcdma_rxlev=$(fibocom_get_rxlev "WCDMA" ${wcdma_rxlev_num})
                    wcdma_reserved=$(echo "$response" | awk -F',' '{print $14}')
                    wcdma_ecio_num=$(echo "$response" | awk -F',' '{print $15}' | sed 's/\r//g')
                    wcdma_ecio=$(fibocom_get_ecio ${wcdma_ecio_num})
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
}


# fibocom获取基站信息
Fibocom_Cellinfo()
{
    #baseinfo.gcom
    OX=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "ATI")
    OX=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+CGEQNEG=1")

    #cellinfo0.gcom
    # OX1=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+COPS=3,0;+COPS?")
    # OX2=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+COPS=3,2;+COPS?")
    OX=$OX1" "$OX2

    #cellinfo.gcom
    OY1=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+CREG=2;+CREG?;+CREG=0")
    OY2=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+CEREG=2;+CEREG?;+CEREG=0")
    OY3=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+C5GREG=2;+C5GREG?;+C5GREG=0")
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

#获取广和通模组信息
# $1:AT串口
# $2:平台
# $3:连接定义
get_fibocom_info()
{
    debug "get fibocom info"
    #设置AT串口
    at_port="$1"
    platform="$2"
    define_connect="$3"

    #基本信息
    fibocom_base_info

	#SIM卡信息
    fibocom_sim_info
    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #网络信息
    fibocom_network_info
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #小区信息
    fibocom_cell_info

    return

    # Fibocom_Cellinfo

    #基站信息
	OX=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+CPSI?")
	rec=$(echo "$OX" | grep "+CPSI:")
	w=$(echo $rec |grep "NO SERVICE"| wc -l)
	if [ $w -ge 1 ];then
		debug "NO SERVICE"
		return
	fi
	w=$(echo $rec |grep "NR5G_"| wc -l)
	if [ $w -ge 1 ];then

		w=$(echo $rec |grep "32768"| wc -l)
		if [ $w -ge 1 ];then
			debug "-32768"
			return
		fi

		debug "$rec"
		rec1=${rec##*+CPSI:}
		#echo "$rec1"
		MODE="${rec1%%,*}" # MODE="NR5G"
		rect1=${rec1#*,}
		rect1s="${rect1%%,*}" #Online
		rect2=${rect1#*,}
		rect2s="${rect2%%,*}" #460-11
		rect3=${rect2#*,}
		rect3s="${rect3%%,*}" #0xCFA102
		rect4=${rect3#*,}
		rect4s="${rect4%%,*}" #55744245764
		rect5=${rect4#*,}
		rect5s="${rect5%%,*}" #196
		rect6=${rect5#*,}
		rect6s="${rect6%%,*}" #NR5G_BAND78
		rect7=${rect6#*,}
		rect7s="${rect7%%,*}" #627264
		rect8=${rect7#*,}
		rect8s="${rect8%%,*}" #-940
		rect9=${rect8#*,}
		rect9s="${rect9%%,*}" #-110
		# "${rec1##*,}" #最后一位
		rect10=${rect9#*,}
		rect10s="${rect10%%,*}" #最后一位
		PCI=$rect5s
		LBAND="n"$(echo $rect6s | cut -d, -f0 | grep -o "BAND[0-9]\{1,3\}" | grep -o "[0-9]\+")
		CHANNEL=$rect7s
		RSCP=$(($(echo $rect8s | cut -d, -f0) / 10))
		ECIO=$(($(echo $rect9s | cut -d, -f0) / 10))
		if [ "$CSQ_PER" = "-" ]; then
			CSQ_PER=$((100 - (($RSCP + 31) * 100/-125)))"%"
		fi
		SINR=$(($(echo $rect10s | cut -d, -f0) / 10))" dB"
	fi
	w=$(echo $rec |grep "LTE"|grep "EUTRAN"| wc -l)
	if [ $w -ge 1 ];then
		rec1=${rec#*EUTRAN-}
		lte_band=${rec1%%,*} #EUTRAN-BAND
		rec1=${rec1#*,}
		rec1=${rec1#*,}
		rec1=${rec1#*,}
		rec1=${rec1#*,}
		#rec1=${rec1#*,}
		rec1=${rec1#*,}
		lte_rssi=${rec1%%,*} #LTE_RSSI
		lte_rssi=`expr $lte_rssi / 10` #LTE_RSSI
		debug "LTE_BAND=$lte_band LTE_RSSI=$lte_rssi"
		if [ $rssi == 0 ];then
			rssi=$lte_rssi
		fi
	fi
	w=$(echo $rec |grep "WCDMA"| wc -l)
	if [ $w -ge 1 ];then
		w=$(echo $rec |grep "UNKNOWN"|wc -l)
		if [ $w -ge 1 ];then
			debug "UNKNOWN BAND"
			return
		fi
	fi

	#CNMP
	OX=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+CNMP?")
	CNMP=$(echo "$OX" | grep -o "+CNMP:[ ]*[0-9]\{1,3\}" | grep -o "[0-9]\{1,3\}")
	if [ -n "$CNMP" ]; then
		case $CNMP in
		"2"|"55" )
			NETMODE="1" ;;
		"13" )
			NETMODE="3" ;;
		"14" )
			NETMODE="5" ;;
		"38" )
			NETMODE="7" ;;
		"71" )
			NETMODE="9" ;;
		"109" )
			NETMODE="8" ;;
		* )
			NETMODE="0" ;;
		esac
	fi
	
	# CMGRMI 信息
	OX=$( sh ${SCRIPT_DIR}/modem_at.sh $at_port "AT+CMGRMI=4")
	CAINFO=$(echo "$OX" | grep -o "$REGXz" | tr ' ' ':')
	if [ -n "$CAINFO" ]; then
		for CASV in $(echo "$CAINFO"); do
			LBAND=$LBAND"<br />B"$(echo "$CASV" | cut -d, -f4)
			BW=$(echo "$CASV" | cut -d, -f5)
			decode_bw
			LBAND=$LBAND" (CA, Bandwidth $BW MHz)"
			CHANNEL="$CHANNEL, "$(echo "$CASV" | cut -d, -f2)
			PCI="$PCI, "$(echo "$CASV" | cut -d, -f7)
		done
	fi
}