#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"

#预设
meig_presets()
{
    #关闭自动上报系统模式变化
	at_command='AT^MODE=0'
	sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"

    #关闭自动上报DS流量
	at_command='AT^DSFLOWRPT=0,0,1'
	sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"
}

#获取DNS
# $1:AT串口
# $2:连接定义
meig_get_dns()
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
    at_command="AT+CGCONTRDP=${define_connect}"
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CGCONTRDP: " | grep -E '[0-9]+.[0-9]+.[0-9]+.[0-9]+' | sed -n '1p')

    local ipv4_dns1=$(echo "${response}" | awk -F',' '{print $7}' | awk -F' ' '{print $1}')
    [ -z "$ipv4_dns1" ] && {
        ipv4_dns1="${public_dns1_ipv4}"
    }

    local ipv4_dns2=$(echo "${response}" | awk -F',' '{print $8}' | awk -F' ' '{print $1}')
    [ -z "$ipv4_dns2" ] && {
        ipv4_dns2="${public_dns2_ipv4}"
    }

    local ipv6_dns1=$(echo "${response}" | awk -F',' '{print $7}' | awk -F' ' '{print $2}')
    [ -z "$ipv6_dns1" ] && {
        ipv6_dns1="${public_dns1_ipv6}"
    }

    local ipv6_dns2=$(echo "${response}" | awk -F',' '{print $8}' | awk -F' ' '{print $2}' | sed 's/\r//g')
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
meig_get_mode()
{
    local at_port="$1"
    local platform="$2"

    at_command="AT+SER?"
    local mode_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+SER:" | sed 's/+SER: //g' | sed 's/\r//g')

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
                "1") mode="qmi" ;;
                # "1") mode="gobinet" ;;
                "2") mode="ecm" ;;
                "7") mode="mbim" ;;
                "3") mode="rndis" ;;
                "2") mode="ncm" ;;
                "8") mode="unknown" ;;
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
meig_set_mode()
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
                "qmi") mode_num="1" ;;
                # "gobinet")  mode_num="1" ;;
                "ecm") mode_num="2" ;;
                "mbim") mode_num="7" ;;
                "rndis") mode_num="3" ;;
                "ncm") mode_num="2" ;;
                *) mode_num="1" ;;
            esac
        ;;
        *)
            mode_num="1"
        ;;
    esac

    #设置模组
    at_command="AT+SER=${mode_num},1"
    sh ${SCRIPT_DIR}/modem_at.sh ${at_port} "${at_command}"
}

#获取位
# $1:频段名称
meig_get_bit()
{
    local band_name="$1"

    local bit
    case "$band_name" in
        "DCS_1800") bit="8" ;;
        "E-GSM_900") bit="9" ;;
        "P-GSM_900") bit="10" ;;
        "GSM_450") bit="17" ;;
        "GSM_480") bit="18" ;;
        "GSM_750") bit="19" ;;
        "GSM_850") bit="20" ;;
        "R-GSM_900") bit="21" ;;
        "PCS_1900") bit="22" ;;
    esac

    echo "${bit}"
}

#获取频段信息
# $1:频段二进制数
# $2:支持的频段
# $3:频段类型（2G，3G，4G，5G）
meig_get_band_info()
{
    local band_bin="$1"
    local support_band="$2"
    local band_type="$3"

    local band_info=""
    local support_band=$(echo "$support_band" | sed 's/,/ /g')
    if [ "$band_type" = "2G" ]; then

        for band in $support_band; do
            #获取bit位
            local bit=$(meig_get_bit ${band})
            #获取值
            local enable="${band_bin: $((-bit)):1}"
            [ -z "$enable" ] && enable="0"
            #设置频段信息
            # band_info=$(echo ${band_info} | jq '. += [{"'$band'":'$enable'}]')
            band_info="${band_info},{\"$band\":$enable}"
        done
    else
        #频段频段起始，前缀位置
        local start_bit
        local band_prefix
        case "$band_type" in
            "3G")
                start_bit="23"
                band_prefix="WCDMA_B"
            ;;
            "4G")
                start_bit="1"
                band_prefix="LTE_BC"
            ;;
            "5G")
                start_bit="1"
                band_prefix="NR5G_N"
            ;;
        esac

        for band in $support_band; do
            #获取值（从start_bit位开始）
            local enable="${band_bin: $((-band-start_bit+1)):1}"
            [ -z "$enable" ] && enable="0"
            #设置频段信息
            # band_info=$(echo ${band_info} | jq '. += [{'$band_prefix$band':'$enable'}]')
            band_info="${band_info},{\"$band_prefix$band\":$enable}"
        done
    fi
    #去掉第一个,
    band_info="["${band_info/,/}"]"
    # band_info="[${band_info%?}]"

    echo "${band_info}"
}

#获取网络偏好
# $1:AT串口
# $2:数据接口
# $3:模组名称
meig_get_network_prefer()
{
    local at_port="$1"
    local data_interface="$2"
    local modem_name="$3"

    at_command="AT^SYSCFGEX?"
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "\^SYSCFGEX:" | sed 's/\^SYSCFGEX://g')
    local network_type_num=$(echo "$response" | awk -F'"' '{print $2}')

    #获取网络类型
    local network_prefer_2g="0";
    local network_prefer_3g="0";
    local network_prefer_4g="0";
    local network_prefer_5g="0";

    #匹配不同的网络类型
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

	#获取模组信息
    local modem_info=$(jq '.modem_support.'$data_interface'."'$modem_name'"' ${SCRIPT_DIR}/modem_support.json)

    #获取模组支持的频段
    local support_2g_band=$(echo "$modem_info" | jq -r '.band_2g')
    local support_3g_band=$(echo "$modem_info" | jq -r '.band_3g')
    local support_4g_band=$(echo "$modem_info" | jq -r '.band_4g')
    local support_5g_band=$(echo "$modem_info" | jq -r '.band_5g')

    #获取2G，3G频段信息
    local band_hex_2g_3g=$(echo "$response" | awk -F',' '{print $2}')
    #十六进制转二进制
    local bin_2g_3g=$(echo "obase=2; ibase=16; $band_hex_2g_3g" | bc)
    local band_2g_info=$(meig_get_band_info "${bin_2g_3g}" "${support_2g_band}" "2G")
    local band_3g_info=$(meig_get_band_info "${bin_2g_3g}" "${support_3g_band}" "3G")

    #获取4G频段信息
    local band_hex_4g_1=$(echo "$response" | awk -F',' '{print $5}' | sed 's/\r//g')
    local band_hex_4g_2=$(echo "$response" | awk -F',' '{print $7}' | sed 's/\r//g')
    #十六进制转二进制
    local bin_4g=$(echo "obase=2; ibase=16; $band_hex_4g_1 + $band_hex_4g_2" | bc)
    local band_4g_info=$(meig_get_band_info "${bin_4g}" "${support_4g_band}" "4G")
    
    #获取5G频段信息
    local band_hex_5g_1=$(echo "$response" | awk -F',' '{print $8}' | sed 's/\r//g')
    local band_hex_5g_2=$(echo "$response" | awk -F',' '{print $9}' | sed 's/\r//g')
    #十六进制转二进制
    local bin_5g=$(echo "obase=2; ibase=16; $band_hex_5g_1 + $band_hex_5g_2" | bc)
    local band_5g_info=$(meig_get_band_info "${bin_5g}" "${support_5g_band}" "5G")

    #生成网络偏好
    local network_prefer="{
        \"network_prefer\":[
            {\"2G\":{
                \"enable\":$network_prefer_2g,
                \"band\":$band_2g_info
            }},
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
meig_set_network_prefer()
{
    local at_port="$1"
    local network_prefer="$2"

    #获取网络偏好配置
    local network_prefer_config

    #获取启用的网络偏好
    local enable_5g=$(echo "$network_prefer" | jq -r '.["5G"].enable')
    local enable_4g=$(echo "$network_prefer" | jq -r '.["4G"].enable')
    local enable_3g=$(echo "$network_prefer" | jq -r '.["3G"].enable')

    #获取网络偏好配置
    local network_prefer_config
    [ "$enable_5g" = "1" ] && network_prefer_config="${network_prefer_config}04"
    [ "$enable_4g" = "1" ] && network_prefer_config="${network_prefer_config}03"
    [ "$enable_3g" = "1" ] && network_prefer_config="${network_prefer_config}02"

    [ -z "$network_prefer_config" ] && network_prefer_config="00"

    #设置模组
    at_command='AT^SYSCFGEX="'${network_prefer_config}'",all,0,2,all,all,all,all,1'
    sh ${SCRIPT_DIR}/modem_at.sh "${at_port}" "${at_command}"
}

#获取电压
# $1:AT串口
meig_get_voltage()
{
    local at_port="$1"
    
    # #Voltage（电压）
    # at_command="AT+ADCREAD=0"
	# local voltage=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+ADCREAD:" | awk -F' ' '{print $2}' | sed 's/\r//g')
    # voltage=$(awk "BEGIN{ printf \"%.2f\", $voltage / 1000000 }" | sed 's/\.*0*$//')
    # echo "${voltage}"
}

#获取温度
# $1:AT串口
meig_get_temperature()
{
    local at_port="$1"
    
    #Temperature（温度）
    at_command="AT+TEMP"
	response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep 'TEMP: "cpu0-0-usr"' | awk -F'"' '{print $4}')

    local temperature
	if [ -n "$response" ]; then
		temperature="${response}$(printf "\xc2\xb0")C"
    else
        temperature="NaN $(printf "\xc2\xb0")C"
	fi

    echo "${temperature}"
}

#获取连接状态
# $1:AT串口
# $2:连接定义
meig_get_connect_status()
{
    local at_port="$1"
    local define_connect="$2"

    #默认值为1
    [ -z "$define_connect" ] && {
        define_connect="1"
    }

    at_command="AT+CGPADDR=${define_connect}"
    local ipv4=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CGPADDR: " | awk -F',' '{print $2}')
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
meig_base_info()
{
    debug "Meig base info"

    #Name（名称）
    at_command="AT+CGMM"
    name=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGMM: " | awk -F': ' '{print $2}' | sed 's/\r//g')
    #Manufacturer（制造商）
    at_command="AT+CGMI"
    manufacturer=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGMI: " | awk -F': ' '{print $2}' | sed 's/\r//g')
    #Revision（固件版本）
    at_command="AT+CGMR"
    revision=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGMR: " | awk -F': ' '{print $2}' | sed 's/\r//g')

    #Mode（拨号模式）
    mode=$(meig_get_mode ${at_port} ${platform} | tr 'a-z' 'A-Z')

    #Temperature（温度）
    temperature=$(meig_get_temperature ${at_port})
}

#获取SIM卡状态
# $1:SIM卡状态标志
meig_get_sim_status()
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
meig_sim_info()
{
    debug "Meig sim info"
    
    #SIM Slot（SIM卡卡槽）
    at_command="AT^SIMSLOT?"
	response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "\^SIMSLOT:" | awk -F': ' '{print $2}' | awk -F',' '{print $2}')

    if [ "$response" != "0" ]; then
        sim_slot="1"
    else
        sim_slot="2"
    fi
    
    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN"
	imei=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | sed -n '2p' | sed 's/\r//g')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status_flag=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CPIN: ")
    sim_status=$(meig_get_sim_status "$sim_status_flag")

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
    at_command="AT+CIMI"
	imsi=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #ICCID（集成电路卡识别码）
    at_command="AT+ICCID"
	iccid=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep -o "+ICCID:[ ]*[-0-9]\+" | grep -o "[-0-9]\{1,4\}")
}

#获取网络类型
# $1:网络类型数字
meig_get_rat()
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
meig_get_rssi()
{
    local rssi
    case $1 in
		"99") rssi="unknown" ;;
		* )  rssi=$((2 * $1 - 113)) ;;
	esac
    echo "$rssi"
}

#获取4G签约速率
# $1:AT响应
# $2:上行或下行标志
meig_get_lte_ambr()
{
    local response="$1"
    local flag="$2"

    local ambr
    case $flag in
		"ul")
            #使用awk拆分字符串
            ambr=$(echo "$response" | awk -F',' '{
                #使用split()函数将字符串拆分为数组
                n = split($0, arr, ",")
                
                #循环遍历每个值
                for (i = 1; i <= n-2; i=i+2)
                {
                    if (arr[i] != "0") {
                        tmp = arr[i]
                    }
                    else {
                        break
                    }
                }
                print tmp
            }')
        ;;
        "dl")
            #使用awk拆分字符串
            ambr=$(echo "$response" | awk -F',' '{
                #使用split()函数将字符串拆分为数组
                n = split($0, arr, ",")
                
                #循环遍历每个值
                for (i = 2; i <= n-2; i=i+2)
                {
                    if (arr[i] != "0") {
                        tmp = arr[i]
                    }
                    else {
                        break
                    }
                }
                print tmp
            }')
        ;;
		* )
            #使用awk拆分字符串
            ambr=$(echo "$response" | awk -F',' '{
                #使用split()函数将字符串拆分为数组
                n = split($0, arr, ",")
                
                #循环遍历每个值
                for (i = 2; i <= n-2; i=i+2)
                {
                    if (arr[i] != "0") {
                        tmp = arr[i]
                    }
                    else {
                        break
                    }
                }
                print tmp
            }')
        ;;
	esac
    echo "$ambr"
}

#网络信息
meig_network_info()
{
    debug "Meig network info"

    #Connect Status（连接状态）
    connect_status=$(meig_get_connect_status ${at_port} ${define_connect})
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #Network Type（网络类型）
    at_command="AT^SYSINFOEX"
    network_type=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "\^SYSINFOEX:" | awk -F'"' '{print $4}')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(meig_get_rat ${rat_num})
    }

    #设置网络类型为5G时，信号强度指示用RSRP代替
    # at_command="AT+GTCSQNREN=1"
    # sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command

    #CSQ（信号强度）
    at_command="AT+CSQ"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    #RSSI（4G信号强度指示）
    # rssi_num=$(echo $response | awk -F',' '{print $1}')
    # rssi=$(meig_get_rssi $rssi_num)
    #BER（4G信道误码率）
    # ber=$(echo $response | awk -F',' '{print $2}')

    # #PER（信号强度）
    # if [ -n "$csq" ]; then
    #     per=$(($csq * 100/31))"%"
    # fi

    #最大比特率，信道质量指示
    at_command="AT^DSAMBR=${define_connect}"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "\^DSAMBR:" | awk -F': ' '{print $2}')

    at_command='AT+COPS?'
    local rat_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
    local network_type_tmp=$(meig_get_rat ${rat_num})
    case $network_type_tmp in
        "LTE")
            ambr_ul_tmp=$(meig_get_lte_ambr ${response} "ul")
            ambr_dl_tmp=$(meig_get_lte_ambr ${response} "dl")
        ;;
        "NR")
            ambr_ul_tmp=$(echo "$response" | awk -F',' '{print $9}')
            ambr_dl_tmp=$(echo "$response" | awk -F',' '{print $10}' | sed 's/\r//g')
        ;;
        *)
            ambr_ul_tmp=$(meig_get_lte_ambr ${response} "ul")
            ambr_dl_tmp=$(meig_get_lte_ambr ${response} "dl")
        ;;
	esac

    #AMBR UL（上行签约速率，单位，Mbps）
    ambr_ul=$(awk "BEGIN{ printf \"%.2f\", $ambr_ul_tmp / 1024 }" | sed 's/\.*0*$//')
    #AMBR DL（下行签约速率，单位，Mbps）
    ambr_dl=$(awk "BEGIN{ printf \"%.2f\", $ambr_dl_tmp / 1024 }" | sed 's/\.*0*$//')

    # #速率统计
    # at_command='AT^DSFLOWQRY'
    # response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "\^DSFLOWRPT:" | sed 's/\^DSFLOWRPT: //g' | sed 's/\r//g')

    # #当前上传速率（单位，Byte/s）
    # tx_rate=$(echo $response | awk -F',' '{print $1}')

    # #当前下载速率（单位，Byte/s）
    # rx_rate=$(echo $response | awk -F',' '{print $2}')
}

#获取频段
# $1:网络类型
# $2:频段数字
meig_get_band()
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
meig_get_bandwidth()
{
    local network_type="$1"
    local bandwidth_num="$2"

    local bandwidth
    case $network_type in
		"LTE") bandwidth=$(( $bandwidth_num / 5 )) ;;
        "NR") bandwidth="$bandwidth_num" ;;
	esac
    echo "$bandwidth"
}

#获取参考信号接收功率
# $1:网络类型
# $2:参考信号接收功率数字
meig_get_rsrp()
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
meig_get_rsrq()
{
    local rsrq
    case $1 in
        "LTE") rsrq=$(awk "BEGIN{ printf \"%.2f\", $2 * 0.5 - 20 }" | sed 's/\.*0*$//') ;;
        "NR") rsrq=$(awk -v num="$2" "BEGIN{ printf \"%.2f\", (num+1) * 0.5 - 44 }" | sed 's/\.*0*$//') ;;
	esac
    echo "$rsrq"
}

#获取信噪比
# $1:信噪比数字
meig_get_sinr()
{
    local sinr=$(awk "BEGIN{ printf \"%.2f\", $1 / 10 }" | sed 's/\.*0*$//')
    echo "$sinr"
}

#小区信息
meig_cell_info()
{
    debug "Meig cell info"

    at_command="AT^CELLINFO=${define_connect}"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "\^CELLINFO:" | sed 's/\^CELLINFO://')
    
    local rat=$(echo "$response" | awk -F',' '{print $1}')

    case $rat in
        "5G")
            network_mode="NR5G-SA Mode"
            nr_duplex_mode=$(echo "$response" | awk -F',' '{print $2}')
            nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
            nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
            nr_cell_id=$(echo "$response" | awk -F',' '{print $5}')
            nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}')
            nr_tac=$(echo "$response" | awk -F',' '{print $7}')
            nr_band_num=$(echo "$response" | awk -F',' '{print $8}')
            nr_band=$(meig_get_band "NR" ${nr_band_num})
            nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $9}')
            nr_dl_bandwidth=$(meig_get_bandwidth "NR" ${nr_dl_bandwidth_num})
            nr_scs=$(echo "$response" | awk -F',' '{print $10}')
            nr_fr_type=$(echo "$response" | awk -F',' '{print $11}')
            nr_dl_channel=$(echo "$response" | awk -F',' '{print $12}')
            nr_ul_channel=$(echo "$response" | awk -F',' '{print $13}')
            nr_rssi=$(echo "$response" | awk -F',' '{print $14}')
            nr_rsrp=$(echo "$response" | awk -F',' '{print $15}')
            nr_rsrq=$(echo "$response" | awk -F',' '{print $16}')
            nr_sinr_num=$(echo "$response" | awk -F',' '{print $17}')
            nr_sinr=$(meig_get_sinr ${nr_sinr_num})
            nr_vonr=$(echo "$response" | awk -F',' '{print $18}' | sed 's/\r//g')
        ;;
        "LTE-NR")
            network_mode="EN-DC Mode"
            #LTE
            endc_lte_duplex_mode=$(echo "$response" | awk -F',' '{print $2}')
            endc_lte_mcc=$(echo "$response" | awk -F',' '{print $3}')
            endc_lte_mnc=$(echo "$response" | awk -F',' '{print $4}')
            endc_lte_global_cell_id=$(echo "$response" | awk -F',' '{print $5}')
            endc_lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}')
            # endc_lte_eNBID=$(echo "$response" | awk -F',' '{print $7}')
            endc_lte_cell_id=$(echo "$response" | awk -F',' '{print $8}')
            endc_lte_tac=$(echo "$response" | awk -F',' '{print $9}')
            endc_lte_band_num=$(echo "$response" | awk -F',' '{print $10}')
            endc_lte_band=$(meig_get_band "LTE" ${endc_lte_band_num})
            ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $11}')
            endc_lte_ul_bandwidth=$(meig_get_bandwidth "LTE" ${ul_bandwidth_num})
            endc_lte_dl_bandwidth="$endc_lte_ul_bandwidth"
            endc_lte_dl_channel=$(echo "$response" | awk -F',' '{print $12}')
            endc_lte_ul_channel=$(echo "$response" | awk -F',' '{print $13}')
            endc_lte_rssi=$(echo "$response" | awk -F',' '{print $14}')
            endc_lte_rsrp=$(echo "$response" | awk -F',' '{print $15}')
            endc_lte_rsrq=$(echo "$response" | awk -F',' '{print $16}')
            endc_lte_sinr_num=$(echo "$response" | awk -F',' '{print $17}')
            endc_lte_sinr=$(meig_get_sinr ${endc_lte_sinr_num})
            endc_lte_rssnr=$(echo "$response" | awk -F',' '{print $18}')
            # endc_lte_ue_category=$(echo "$response" | awk -F',' '{print $19}')
            # endc_lte_pathloss=$(echo "$response" | awk -F',' '{print $20}')
            # endc_lte_cqi=$(echo "$response" | awk -F',' '{print $21}')
            endc_lte_tx_power=$(echo "$response" | awk -F',' '{print $22}')
            # endc_lte_tm=$(echo "$response" | awk -F',' '{print $23}')
            # endc_lte_qci=$(echo "$response" | awk -F',' '{print $24}')
            # endc_lte_volte=$(echo "$response" | awk -F',' '{print $25}')
            # endc_lte_ims_sms=$(echo "$response" | awk -F',' '{print $26}')
            # endc_lte_sib2_plmn_r15_info_present=$(echo "$response" | awk -F',' '{print $27}')
            # endc_lte_sib2_upr_layer_ind=$(echo "$response" | awk -F',' '{print $28}')
            # endc_lte_restrict_dcnr=$(echo "$response" | awk -F',' '{print $29}')
            #NR5G-NSA
            endc_nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
            endc_nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
            endc_nr_global_cell_id=$(echo "$response" | awk -F',' '{print $5}')
            endc_nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}')
            endc_nr_cell_id=$(echo "$response" | awk -F',' '{print $8}')
            endc_nr_tac=$(echo "$response" | awk -F',' '{print $9}')
            endc_nr_rsrp=$(echo "$response" | awk -F',' '{print $30}')
            endc_nr_rsrq=$(echo "$response" | awk -F',' '{print $31}')
            endc_nr_sinr_num=$(echo "$response" | awk -F',' '{print $32}')
            endc_nr_sinr=$(meig_get_sinr ${endc_nr_sinr_num})
            endc_nr_band_num=$(echo "$response" | awk -F',' '{print $33}')
            endc_nr_band=$(meig_get_band "NR" ${endc_nr_band_num})
            endc_nr_freq=$(echo "$response" | awk -F',' '{print $34}')
            nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $35}')
            endc_nr_dl_bandwidth=$(meig_get_bandwidth "NR" ${nr_dl_bandwidth_num})
            # endc_nr_pci=$(echo "$response" | awk -F',' '{print $36}')
            endc_nr_scs=$(echo "$response" | awk -F',' '{print $37}' | sed 's/\r//g')
            ;;
        "LTE"|"eMTC"|"NB-IoT")
            network_mode="LTE Mode"
            lte_duplex_mode=$(echo "$response" | awk -F',' '{print $2}')
            lte_mcc=$(echo "$response" | awk -F',' '{print $3}')
            lte_mnc=$(echo "$response" | awk -F',' '{print $4}')
            lte_global_cell_id=$(echo "$response" | awk -F',' '{print $5}')
            lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $6}')
            lte_eNBID=$(echo "$response" | awk -F',' '{print $7}')
            lte_cell_id=$(echo "$response" | awk -F',' '{print $8}')
            let_tac=$(echo "$response" | awk -F',' '{print $9}')
            # lte_earfcn=$(echo "$response" | awk -F',' '{print $7}')
            lte_band_num=$(echo "$response" | awk -F',' '{print $10}')
            lte_band=$(meig_get_band "LTE" ${lte_band_num})
            ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $11}')
            lte_ul_bandwidth=$(meig_get_bandwidth "LTE" ${ul_bandwidth_num})
            lte_dl_bandwidth="$lte_ul_bandwidth"
            lte_dl_channel=$(echo "$response" | awk -F',' '{print $12}')
            lte_ul_channel=$(echo "$response" | awk -F',' '{print $13}')
            lte_rssi=$(echo "$response" | awk -F',' '{print $14}')
            lte_rsrp=$(echo "$response" | awk -F',' '{print $15}')
            lte_rsrq=$(echo "$response" | awk -F',' '{print $16}')
            lte_sinr_num=$(echo "$response" | awk -F',' '{print $17}')
            lte_sinr=$(meig_get_sinr ${lte_sinr_num})
            lte_rssnr=$(echo "$response" | awk -F',' '{print $18}')
            # lte_ue_category=$(echo "$response" | awk -F',' '{print $19}')
            # lte_pathloss=$(echo "$response" | awk -F',' '{print $20}')
            # lte_cqi=$(echo "$response" | awk -F',' '{print $21}')
            lte_tx_power=$(echo "$response" | awk -F',' '{print $22}')
            # lte_tm=$(echo "$response" | awk -F',' '{print $23}')
            # lte_qci=$(echo "$response" | awk -F',' '{print $24}')
            # lte_volte=$(echo "$response" | awk -F',' '{print $25}')
            # lte_ims_sms=$(echo "$response" | awk -F',' '{print $26}')
            # lte_sib2_plmn_r15_info_present=$(echo "$response" | awk -F',' '{print $27}')
            # lte_sib2_upr_layer_ind=$(echo "$response" | awk -F',' '{print $28}')
            # lte_restrict_dcnr=$(echo "$response" | awk -F',' '{print $29}' | sed 's/\r//g')
        ;;
        "WCDMA"|"UMTS")
            network_mode="WCDMA Mode"
            wcdma_mcc=$(echo "$response" | awk -F',' '{print $2}')
            wcdma_mnc=$(echo "$response" | awk -F',' '{print $3}')
            wcdma_global_cell_id=$(echo "$response" | awk -F',' '{print $4}')
            wcdma_psc=$(echo "$response" | awk -F',' '{print $5}')
            wcdma_NodeB=$(echo "$response" | awk -F',' '{print $6}')
            wcdma_cell_id=$(echo "$response" | awk -F',' '{print $7}')
            wcdma_lac=$(echo "$response" | awk -F',' '{print $8}')
            wcdma_band_num=$(echo "$response" | awk -F',' '{print $9}')
            wcdma_band=$(meig_get_band "WCDMA" ${wcdma_band_num})
            wcdma_dl_channel=$(echo "$response" | awk -F',' '{print $10}')
            wcdma_ul_channel=$(echo "$response" | awk -F',' '{print $11}')
            wcdma_rssi=$(echo "$response" | awk -F',' '{print $12}')
            wcdma_ecio=$(echo "$response" | awk -F',' '{print $13}')
            # wcdma_sir=$(echo "$response" | awk -F',' '{print $14}')
            wcdma_rscp=$(echo "$response" | awk -F',' '{print $15}' | sed 's/\r//g')
        ;;
        "GSM")
            network_mode="GSM Mode"
            gsm_mcc=$(echo "$response" | awk -F',' '{print $3}')
            gsm_mnc=$(echo "$response" | awk -F',' '{print $4}')
        ;;
    esac
}

#获取美格模组信息
# $1:AT串口
# $2:平台
# $3:连接定义
get_meig_info()
{
    debug "get meig info"
    #设置AT串口
    at_port="$1"
    platform="$2"
    define_connect="$3"

    #基本信息
    meig_base_info

	#SIM卡信息
    meig_sim_info
    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #网络信息
    meig_network_info
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #小区信息
    meig_cell_info
}