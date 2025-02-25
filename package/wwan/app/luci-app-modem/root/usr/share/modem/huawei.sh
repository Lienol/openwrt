#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"

#预设
huawei_presets()
{
    #关闭模组主动上报
	at_command='AT^CURC=0'
	sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"

    #开启5G NA NSA接入
	at_command='AT^C5GOPTION=1,3,3'
	sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"
}

#获取DNS
# $1:AT串口
# $2:连接定义
huawei_get_dns()
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

    #获取DNS地址（IPv4）
    at_command="AT^DHCP=${define_connect}"
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "\^DHCP:" | sed -n '1p')

    local ipv4_dns1=$(echo "${response}" | awk -F',' '{print $5}')
    if [ -z "$ipv4_dns1" ]; then
        ipv4_dns1="${public_dns1_ipv4}"
    else
        #按字节（byte）将十六进制拆分并转换为对应的十进制表示
        ipv4_dns1=$(echo "$ipv4_dns1" | awk '{
            for (i = length; i >= 1; i -= 2) {
                printf "%d.", "0x" substr($0, i-1, 2)
            }
        }')
        ipv4_dns1="${ipv4_dns1%?}"
    fi

    local ipv4_dns2=$(echo "${response}" | awk -F',' '{print $6}')
    if [ -z "$ipv4_dns2" ]; then
        ipv4_dns2="${public_dns1_ipv4}"
    else
        #按字节（byte）将十六进制拆分并转换为对应的十进制表示
        ipv4_dns2=$(echo "$ipv4_dns2" | awk '{
            for (i = length; i >= 1; i -= 2) {
                printf "%d.", "0x" substr($0, i-1, 2)
            }
        }')
        ipv4_dns2="${ipv4_dns2%?}"
    fi

    #获取DNS地址（IPv6）
    at_command="AT^DHCPV6=${define_connect}"
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "\^DHCPV6:" | sed -n '1p')

    local ipv6_dns1=$(echo "${response}" | awk -F',' '{print $5}')
    [ -z "$ipv6_dns1" ] && {
        ipv6_dns1="${public_dns1_ipv6}"
    }

    local ipv6_dns2=$(echo "${response}" | awk -F',' '{print $6}')
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
huawei_get_mode()
{
    local at_port="$1"
    local platform="$2"

    at_command="AT^SETMODE?"
    local mode_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "\^SETMODE:" | awk -F': ' '{print $2}' | sed 's/\r//g')

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
        "hisilicon")
            case "$mode_num" in
                "0"|"2") mode="ecm" ;;
                "1"|"3"|"4"|"5") mode="ncm" ;;
                "6") mode="rndis" ;;
                "7") mode="mbim" ;;
                "8") mode="ppp" ;;
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
huawei_set_mode()
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
        "hisilicon")
            case "$mode_config" in
                "ecm") mode_num="0" ;;
                "ncm") mode_num="4" ;;
                *) mode_num="0" ;;
            esac
        ;;
        *)
            mode_num="0"
        ;;
    esac

    #设置模组
    at_command="AT^SETMODE=${mode_num}"
    sh ${SCRIPT_DIR}/modem_at.sh ${at_port} "${at_command}"
}

#获取位
# $1:频段名称
huawei_get_bit()
{
    local band_name="$1"

    local bit
    case "$band_name" in
        "DCS_1800") bit="8" ;;
        "E-GSM_900"|"E_GSM_900") bit="9" ;;
        "P-GSM_900"|"P_GSM_900") bit="10" ;;
        "GSM_450") bit="17" ;;
        "GSM_480") bit="18" ;;
        "GSM_750") bit="19" ;;
        "GSM_850") bit="20" ;;
        "R-GSM_900"|"R_GSM_900") bit="21" ;;
        "PCS_1900") bit="22" ;;
    esac

    echo "${bit}"
}

#获取频段信息
# $1:频段二进制数
# $2:支持的频段
# $3:频段类型（2G，3G，4G，5G）
huawei_get_band_info()
{
    local band_bin="$1"
    local support_band="$2"
    local band_type="$3"

    local band_info=""
    local support_band=$(echo "$support_band" | sed 's/,/ /g')
    if [ "$band_type" = "2G" ]; then

        for band in $support_band; do
            #获取bit位
            local bit=$(huawei_get_bit ${band})
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
huawei_get_network_prefer()
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
        local nr=$(echo "${network_type_num}" | grep "08")
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

    #获取频段信息
    local band_hex_2g_3g=$(echo "$response" | awk -F',' '{print $2}')
    #十六进制转二进制
    local bin_2g_3g=$(echo "obase=2; ibase=16; $band_hex_2g_3g" | bc)
    local band_2g_info=$(huawei_get_band_info "${bin_2g_3g}" "${support_2g_band}" "2G")
    local band_3g_info=$(huawei_get_band_info "${bin_2g_3g}" "${support_3g_band}" "3G")

    local band_hex_4g_5g=$(echo "$response" | awk -F',' '{print $5}' | sed 's/\r//g')
    #十六进制转二进制
    local bin_4g_5g=$(echo "obase=2; ibase=16; $band_hex_4g_5g" | bc)
    local band_4g_info=$(huawei_get_band_info "${bin_4g_5g}" "${support_4g_band}" "4G")
    local band_5g_info=$(huawei_get_band_info "${bin_4g_5g}" "${support_5g_band}" "5G")

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
huawei_set_network_prefer()
{
    local at_port="$1"
    local network_prefer="$2"

    #获取启用的网络偏好
    local enable_5g=$(echo "$network_prefer" | jq -r '.["5G"].enable')
    local enable_4g=$(echo "$network_prefer" | jq -r '.["4G"].enable')
    local enable_3g=$(echo "$network_prefer" | jq -r '.["3G"].enable')
    local enable_2g=$(echo "$network_prefer" | jq -r '.["2G"].enable')

    #获取网络偏好配置
    local network_prefer_config
    [ "$enable_5g" = "1" ] && network_prefer_config="${network_prefer_config}08"
    [ "$enable_4g" = "1" ] && network_prefer_config="${network_prefer_config}03"
    [ "$enable_3g" = "1" ] && network_prefer_config="${network_prefer_config}02"
    [ "$enable_2g" = "1" ] && network_prefer_config="${network_prefer_config}01"

    [ -z "$network_prefer_config" ] && network_prefer_config="99"

    #设置模组
    at_command='AT^SYSCFGEX="'${network_prefer_config}'",40000000,1,2,40000000,,'
    sh ${SCRIPT_DIR}/modem_at.sh "${at_port}" "${at_command}"
}

#设置频段
# $1:AT串口
# $2:频段偏好配置
huawei_set_band_prefer()
{
    local at_port="$1"
    local network_prefer="$2"

    #获取选中的数量
    local count=$(echo "$network_prefer" | grep -o "1" | wc -l)
    #获取每个偏好的值
    local network_prefer_5g=$(echo "$network_prefer" | jq -r '.["5G"]')
    local network_prefer_4g=$(echo "$network_prefer" | jq -r '.["4G"]')
    local network_prefer_3g=$(echo "$network_prefer" | jq -r '.["3G"]')
    local network_prefer_2g=$(echo "$network_prefer" | jq -r '.["2G"]')

    #获取启用的网络偏好
    local enable_5g=$(echo "$network_prefer_5g" | jq -r '.enable')
    local enable_4g=$(echo "$network_prefer_4g" | jq -r '.enable')
    local enable_3g=$(echo "$network_prefer_3g" | jq -r '.enable')
    local enable_2g=$(echo "$network_prefer_2g" | jq -r '.enable')

    #获取网络偏好配置和频段偏好配置
    local network_prefer_config
    local band_hex_2g_3g=0
    local band_hex_4g_5g=0

    [ "$enable_5g" = "1" ] && {
        network_prefer_config="${network_prefer_config}08"
        local band_tmp=$(echo "$network_prefer_5g" | jq -r '.band[]')
        
        local i=0
        local bands=$(echo "$band_tmp" | jq -r 'to_entries | .[] | .key')
        #遍历band的值
        for band in $bands; do
            local value=$(echo "$network_prefer_5g" | jq -r '.band'"[$i].$band")
            [ "$value" = "1" ] && {
                #获取bit位
                local bit=$(echo "$band" | sed 's/NR5G_N//g')
                #获取值
                local result=$(echo "obase=16; ibase=10; 2^($bit-1)" | bc)
                band_hex_4g_5g=$(echo "obase=16; ibase=16; $band_hex_4g_5g + $result" | bc)
            }
            i=$((i+1))
        done
    }

    [ "$enable_4g" = "1" ] && {
        network_prefer_config="${network_prefer_config}03"
        local band_tmp=$(echo "$network_prefer_4g" | jq -r '.band[]')

        local i=0
        local bands=$(echo "$band_tmp" | jq -r 'to_entries | .[] | .key')
        #遍历band的值
        for band in $bands; do
            local value=$(echo "$network_prefer_4g" | jq -r '.band'"[$i].$band")
            [ "$value" = "1" ] && {
                #获取bit位
                local bit=$(echo "$band" | sed 's/LTE_BC//g')
                #获取值
                local result=$(echo "obase=16; ibase=10; 2^($bit-1)" | bc)
                band_hex_4g_5g=$(echo "obase=16; ibase=16; $band_hex_4g_5g + $result" | bc)
            }
            i=$((i+1))
        done
    }

    [ "$enable_3g" = "1" ] && {
        network_prefer_config="${network_prefer_config}02"
        local band_tmp=$(echo "$network_prefer_3g" | jq -r '.band[]')

        local i=0
        local bands=$(echo "$band_tmp" | jq -r 'to_entries | .[] | .key')
        #遍历band的值
        for band in $bands; do
            local value=$(echo "$network_prefer_3g" | jq -r '.band'"[$i].$band")
            [ "$value" = "1" ] && {
                #获取bit位
                local bit=$(echo "$band" | sed 's/WCDMA_B//g')
                #获取值
                local result=$(echo "obase=16; ibase=10; 2^($bit+22-1)" | bc)
                band_hex_2g_3g=$(echo "obase=16; ibase=16; $band_hex_2g_3g + $result" | bc)
            }
            i=$((i+1))
        done
    }

    [ "$enable_2g" = "1" ] && {
        network_prefer_config="${network_prefer_config}01"
        local band_tmp=$(echo "$network_prefer_2g" | jq -r '.band[]')

        local i=0
        local bands=$(echo "$band_tmp" | jq -r 'to_entries | .[] | .key')
        #遍历band的值
        for band in $bands; do
            # band_format=$(echo "$band" | sed 's/-/_/g')
            local value=$(echo "$network_prefer_2g" | jq -r '.band'"[$i].$band")
            [ "$value" = "1" ] && {
                #获取bit位
                local bit=$(huawei_get_bit ${band})
                #获取值
                local result=$(echo "obase=16; ibase=10; 2^($bit-1)" | bc)
                band_hex_2g_3g=$(echo "obase=16; ibase=16; $band_hex_2g_3g + $result" | bc)
            }
            i=$((i+1))
        done
    }

    [ -z "$network_prefer_config" ] && network_prefer_config="99"

    #设置模组
    at_command='AT^SYSCFGEX="'${network_prefer_config}'",'"${band_hex_2g_3g},1,2,${band_hex_4g_5g},,"
    sh ${SCRIPT_DIR}/modem_at.sh "${at_port}" "${at_command}"
}

#获取电压
# $1:AT串口
huawei_get_voltage()
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
huawei_get_temperature()
{
    local at_port="$1"
    
    #Temperature（温度）
    at_command="AT^CHIPTEMP?"
	response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "\^CHIPTEMP" | awk -F',' '{print $6}' | sed 's/\r//g')

    local temperature
	if [ -n "$response" ]; then
        response=$(awk "BEGIN{ printf \"%.2f\", $response / 10 }" | sed 's/\.*0*$//')
		temperature="${response}$(printf "\xc2\xb0")C"
    else
        temperature="NaN $(printf "\xc2\xb0")C"
	fi

    echo "${temperature}"
}

#获取连接状态
# $1:AT串口
# $2:连接定义
huawei_get_connect_status()
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
huawei_base_info()
{
    debug "Huawei base info"

    #Name（名称）
    at_command="AT+CGMM"
    name=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGMM: " | awk -F': ' '{print $2}' | sed 's/\r//g')
    #Manufacturer（制造商）
    at_command="AT+CGMI"
    manufacturer=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    #Revision（固件版本）
    at_command="AT+CGMR"
    revision=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #Mode（拨号模式）
    mode=$(huawei_get_mode ${at_port} ${platform} | tr 'a-z' 'A-Z')

    #Temperature（温度）
    temperature=$(huawei_get_temperature ${at_port})
}

#获取SIM卡状态
# $1:SIM卡状态标志
huawei_get_sim_status()
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
huawei_sim_info()
{
    debug "Huawei sim info"
    
    #SIM Slot（SIM卡卡槽）
    # at_command="AT^SIMSLOT?"
	# response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "\^SIMSLOT:" | awk -F': ' '{print $2}' | awk -F',' '{print $2}')

    # if [ "$response" != "0" ]; then
    #     sim_slot="1"
    # else
    #     sim_slot="2"
    # fi
    sim_slot="1"

    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN"
	imei=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | sed -n '2p' | sed 's/\r//g')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status_flag=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CPIN: ")
    sim_status=$(huawei_get_sim_status "$sim_status_flag")

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
huawei_get_rat()
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
huawei_get_rssi()
{
    local rssi
    case $1 in
		"99") rssi="unknown" ;;
		* )  rssi=$((2 * $1 - 113)) ;;
	esac
    echo "$rssi"
}

#网络信息
huawei_network_info()
{
    debug "Huawei network info"

    #Connect Status（连接状态）
    connect_status=$(huawei_get_connect_status ${at_port} ${define_connect})
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #Network Type（网络类型）
    at_command="AT^SYSINFOEX"
    network_type=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "\^SYSINFOEX:" | awk -F'"' '{print $4}')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(huawei_get_rat ${rat_num})
    }

    #设置网络类型为5G时，信号强度指示用RSRP代替
    # at_command="AT+GTCSQNREN=1"
    # sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command

    #CSQ（信号强度）
    at_command="AT+CSQ"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    #RSSI（4G信号强度指示）
    # rssi_num=$(echo $response | awk -F',' '{print $1}')
    # rssi=$(huawei_get_rssi $rssi_num)
    #BER（4G信道误码率）
    # ber=$(echo $response | awk -F',' '{print $2}')

    # #PER（信号强度）
    # if [ -n "$csq" ]; then
    #     per=$(($csq * 100/31))"%"
    # fi

    #AMBR（最大比特率）
    at_command="AT^DHCP?"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "\^DHCP:" | sed 's/\^DHCP: //g' | sed 's/\r//g')
    ambr_ul_tmp=$(echo "$response" | awk -F',' '{print $8}')
    ambr_dl_tmp=$(echo "$response" | awk -F',' '{print $7}')

    [ -z "$ambr_ul_tmp" ] && {
        at_command="AT^DHCPV6?"
        response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "\^DHCPV6:" | sed 's/\^DHCPV6: //g' | sed 's/\r//g')
        ambr_ul_tmp=$(echo "$response" | awk -F',' '{print $8}')
        ambr_dl_tmp=$(echo "$response" | awk -F',' '{print $7}')
    }

    #AMBR UL（上行签约速率，单位，Mbps）
    ambr_ul=$(awk "BEGIN{ printf \"%.2f\", $ambr_ul_tmp / 1000000 }" | sed 's/\.*0*$//')
    #AMBR DL（下行签约速率，单位，Mbps）
    ambr_dl=$(awk "BEGIN{ printf \"%.2f\", $ambr_dl_tmp / 1000000 }" | sed 's/\.*0*$//')

    # #速率统计
    # at_command='AT^DSFLOWQRY'
    # response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "\^DSFLOWRPT:" | sed 's/\^DSFLOWRPT: //g' | sed 's/\r//g')

    # #当前上传速率（单位，Byte/s）
    # tx_rate=$(echo $response | awk -F',' '{print $1}')

    # #当前下载速率（单位，Byte/s）
    # rx_rate=$(echo $response | awk -F',' '{print $2}')
}

#获取NR子载波间隔
# $1:NR子载波间隔数字
huawei_get_scs()
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

#获取频段
# $1:网络类型
# $2:频段数字
huawei_get_band()
{
    local band
    case $1 in
        "GSM")
            case $2 in
                "0") band="850" ;;
                "1") band="900" ;;
                "2") band="1800" ;;
                "3") band="1900" ;;
            esac
        ;;
		"WCDMA") band="$2" ;;
		"LTE") band="$(($2-100))" ;;
        "NR") band="$2" band="${band#*50}" ;;
	esac
    echo "$band"
}

#小区信息
huawei_cell_info()
{
    debug "Huawei cell info"

    at_command="AT^MONSC"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "\^MONSC:" | sed 's/\^MONSC: //')
    
    local rat=$(echo "$response" | awk -F',' '{print $1}')

    case $rat in
        "NR")
            network_mode="NR5G-SA Mode"
            nr_mcc=$(echo "$response" | awk -F',' '{print $2}')
            nr_mnc=$(echo "$response" | awk -F',' '{print $3}')
            nr_arfcn=$(echo "$response" | awk -F',' '{print $4}')
            nr_scs_num=$(echo "$response" | awk -F',' '{print $5}')
            nr_scs=$(tdtech_get_scs ${nr_scs_num})
            nr_cell_id_hex=$(echo "$response" | awk -F',' '{print $6}')
            nr_cell_id=$(echo "ibase=16; $nr_cell_id_hex" | bc)
            nr_physical_cell_id_hex=$(echo "$response" | awk -F',' '{print $7}')
            nr_physical_cell_id=$(echo "ibase=16; $nr_physical_cell_id_hex" | bc)
            nr_tac=$(echo "$response" | awk -F',' '{print $8}')
            nr_rsrp=$(echo "$response" | awk -F',' '{print $9}')
            nr_rsrq=$(echo "$response" | awk -F',' '{print $10}')
            nr_sinr=$(echo "$response" | awk -F',' '{print $11}' | sed 's/\r//g')
        ;;
        "LTE-NR")
            network_mode="EN-DC Mode"
            #LTE
            endc_lte_mcc=$(echo "$response" | awk -F',' '{print $2}')
            endc_lte_mnc=$(echo "$response" | awk -F',' '{print $3}')
            endc_lte_earfcn=$(echo "$response" | awk -F',' '{print $4}')
            endc_lte_cell_id_hex=$(echo "$response" | awk -F',' '{print $5}')
            endc_lte_cell_id=$(echo "ibase=16; $endc_lte_cell_id_hex" | bc)
            endc_lte_physical_cell_id_hex=$(echo "$response" | awk -F',' '{print $6}')
            endc_lte_physical_cell_id=$(echo "ibase=16; $endc_lte_physical_cell_id_hex" | bc)
            endc_lte_tac=$(echo "$response" | awk -F',' '{print $7}')
            endc_lte_rsrp=$(echo "$response" | awk -F',' '{print $8}')
            endc_lte_rsrq=$(echo "$response" | awk -F',' '{print $9}')
            endc_lte_rxlev=$(echo "$response" | awk -F',' '{print $10}' | sed 's/\r//g')
            #NR5G-NSA
            endc_nr_mcc=$(echo "$response" | awk -F',' '{print $2}')
            endc_nr_mnc=$(echo "$response" | awk -F',' '{print $3}')
            endc_nr_arfcn=$(echo "$response" | awk -F',' '{print $4}')
            endc_nr_scs_num=$(echo "$response" | awk -F',' '{print $5}')
            endc_nr_scs=$(tdtech_get_scs ${nr_scs_num})
            endc_nr_cell_id_hex=$(echo "$response" | awk -F',' '{print $6}')
            endc_nr_cell_id=$(echo "ibase=16; $endc_nr_cell_id_hex" | bc)
            endc_nr_physical_cell_id_hex=$(echo "$response" | awk -F',' '{print $7}')
            endc_nr_physical_cell_id=$(echo "ibase=16; $endc_nr_physical_cell_id_hex" | bc)
            endc_nr_tac=$(echo "$response" | awk -F',' '{print $8}')
            endc_nr_rsrp=$(echo "$response" | awk -F',' '{print $9}')
            endc_nr_rsrq=$(echo "$response" | awk -F',' '{print $10}')
            endc_nr_sinr=$(echo "$response" | awk -F',' '{print $11}' | sed 's/\r//g')
        ;;
        "LTE"|"eMTC"|"NB-IoT")
            network_mode="LTE Mode"
            lte_mcc=$(echo "$response" | awk -F',' '{print $2}')
            lte_mnc=$(echo "$response" | awk -F',' '{print $3}')
            lte_earfcn=$(echo "$response" | awk -F',' '{print $4}')
            lte_cell_id_hex=$(echo "$response" | awk -F',' '{print $5}')
            lte_cell_id=$(echo "ibase=16; $lte_cell_id_hex" | bc)
            lte_physical_cell_id_hex=$(echo "$response" | awk -F',' '{print $6}')
            lte_physical_cell_id=$(echo "ibase=16; $lte_physical_cell_id_hex" | bc)
            lte_tac=$(echo "$response" | awk -F',' '{print $7}')
            lte_rsrp=$(echo "$response" | awk -F',' '{print $8}')
            lte_rsrq=$(echo "$response" | awk -F',' '{print $9}')
            lte_rxlev=$(echo "$response" | awk -F',' '{print $10}' | sed 's/\r//g')
        ;;
        "WCDMA"|"TD-SCDMA"|"UMTS")
            network_mode="WCDMA Mode"
            wcdma_mcc=$(echo "$response" | awk -F',' '{print $2}')
            wcdma_mnc=$(echo "$response" | awk -F',' '{print $3}')
            wcdma_arfcn=$(echo "$response" | awk -F',' '{print $4}')
            wcdma_psc=$(echo "$response" | awk -F',' '{print $5}')
            wcdma_cell_id_hex=$(echo "$response" | awk -F',' '{print $6}')
            wcdma_cell_id=$(echo "ibase=16; $wcdma_cell_id_hex" | bc)
            wcdma_lac=$(echo "$response" | awk -F',' '{print $7}')
            wcdma_rscp=$(echo "$response" | awk -F',' '{print $8}')
            wcdma_rxlev=$(echo "$response" | awk -F',' '{print $9}')
            wcdma_ecn0=$(echo "$response" | awk -F',' '{print $10}')
            wcdma_drx=$(echo "$response" | awk -F',' '{print $11}')
            wcdma_ura=$(echo "$response" | awk -F',' '{print $12}' | sed 's/\r//g')
        ;;
        "GSM")
            network_mode="GSM Mode"
            gsm_mcc=$(echo "$response" | awk -F',' '{print $2}')
            gsm_mnc=$(echo "$response" | awk -F',' '{print $3}')
            gsm_band_num=$(echo "$response" | awk -F',' '{print $4}')
            gsm_band=$(tdtech_get_band "GSM" ${gsm_band_num})
            gsm_arfcn=$(echo "$response" | awk -F',' '{print $5}')
            gsm_bsic=$(echo "$response" | awk -F',' '{print $6}')
            gsm_cell_id_hex=$(echo "$response" | awk -F',' '{print $7}')
            gsm_cell_id=$(echo "ibase=16; $gsm_cell_id_hex" | bc)
            gsm_lac=$(echo "$response" | awk -F',' '{print $8}')
            gsm_rxlev=$(echo "$response" | awk -F',' '{print $9}')
            gsm_rx_quality=$(echo "$response" | awk -F',' '{print $10}')
            gsm_ta=$(echo "$response" | awk -F',' '{print $11}' | sed 's/\r//g')
        ;;
    esac
}

#获取华为模组信息
# $1:AT串口
# $2:平台
# $3:连接定义
get_huawei_info()
{
    debug "get huawei info"
    #设置AT串口
    at_port="$1"
    platform="$2"
    define_connect="$3"

    #基本信息
    huawei_base_info

	#SIM卡信息
    huawei_sim_info
    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #网络信息
    huawei_network_info
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #小区信息
    huawei_cell_info
}