#!/bin/sh
SCRIPT_DIR="/usr/share/qmodem"
source /usr/share/libubox/jshn.sh
source "${SCRIPT_DIR}/modem_util.sh"
add_plain_info_entry()
{
    key=$1
    value=$2
    key_full_name=$3
    class_overwrite=$4
    if [ -n "$class_overwrite" ]; then
        class="$class_overwrite"
    fi
    json_add_object ""
    json_add_string  key "$key"
    json_add_string  value "$value"
    json_add_string "full_name" "$key_full_name"
    json_add_string "type" "plain_text"
    if [ -n "$class" ]; then
        json_add_string "class" "$class"
        json_add_string "class_origin" "$class"
    fi
    json_close_object
}

add_warning_message_entry()
{
    key=$1
    value=$2
    key_full_name=$3
    class_overwrite=$4
    if [ -n "$class_overwrite" ]; then
        class="$class_overwrite"
    fi
    json_add_object ""
    json_add_string  key "$key"
    json_add_string  value "$value"
    json_add_string "full_name" "$key_full_name"
    json_add_string "type" "warning_message"
    json_add_string "class" "warning"
    json_add_string "class_origin" "warning"
    json_close_object
}

add_bar_info_entry()
{
    key=$1
    value=$2
    key_full_name=$3
    min_value=$4
    max_value=$5
    unit=$6
    class_overwrite=$7
    if [ -n "$class_overwrite" ]; then
        class="$class_overwrite"
    fi
    json_add_object ""
    json_add_string  key "$key"
    json_add_string  value "$value"
    json_add_string  min_value "$min_value"
    json_add_string  max_value "$max_value"
    json_add_string "full_name" "$key_full_name"
    json_add_string "unit" "$unit"
    json_add_string "type" "progress_bar"
    if [ -n "$class" ]; then
        json_add_string "class" "$class"
        json_add_string "class_origin" "$class"
    fi
    json_close_object
}

add_speed_entry()
{
    rate=$1
    type=$2
    if [ -z "$rate" ]; then
        return
    fi
    rate=`rate_convert $rate`
    case $type in
        "rx")
            add_plain_info_entry "Rx Rate" "$rate" "Transmit Rate"
            ;;
        "tx")
            add_plain_info_entry "Tx Rate" "$rate" "Receive Rate"
            ;;
        *)
            return
            ;;
    esac

}

add_avalible_band_entry()
{
    band_id=$1
    band_name=$2
    json_add_object ""
    json_add_string  band_id "$band_id"
    json_add_string  band_name "$band_name"
    json_add_string "type" "avalible_band"
    json_close_object
}

get_driver()
{
    for i in $(find $modem_path -name driver);do
        lsfile=$(ls -l $i)
        type=${lsfile:0:1}
        if [ "$type" == "l" ];then
            link=$(basename $(ls -l $i | awk '{print $11}'))
            case $link in
                "mtk_t7xx")
                    mode="mtk_pcie"
                    break
                    ;;
                "qmi_wwan"*) 
                    mode="qmi"
                    break
                ;;
                "cdc_mbim")
                    mode="mbim"
                    break
                    ;;
                "cdc_ncm")
                    mode="ncm"
                    break
                    ;;
                "cdc_ether")
                    mode="ecm"
                    break
                    ;;
                "rndis_host")
                    mode="rndis"
                    break
                    ;;
                "mhi_netdev")
                    mode="mhi"
                    break
                    ;;
                *)
                    if [ -z "$mode" ]; then
                        mode="unknown"
                    fi
                ;;
            esac
        fi
    done
    echo $mode
}

get_dns()
{
    [ -z "$define_connect" ] && {
        define_connect="1"
    }

    local public_dns1_ipv4="223.5.5.5"
    local public_dns2_ipv4="119.29.29.29"
    local public_dns1_ipv6="2400:3200::1" #下一代互联网北京研究中心：240C::6666，阿里：2400:3200::1，腾讯：2402:4e00::
    local public_dns2_ipv6="2402:4e00::"

    #获取DNS地址
    at_command="AT+GTDNS=${define_connect}"
    local response=$(at ${at_port} ${at_command} | grep "+GTDNS: ")

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
    json_add_object "dns"
    json_add_string "ipv4_dns1" "$ipv4_dns1"
    json_add_string "ipv4_dns2" "$ipv4_dns2"
    json_add_string "ipv6_dns1" "$ipv6_dns1"
    json_add_string "ipv6_dns2" "$ipv6_dns2"
    json_close_object
}

get_sim_status()
{
    local sim_status
    case $1 in
        "") 
            sim_status="miss"
            sim_state_code=0
            ;;
        *"ERROR"*) 
            sim_status="miss"
            sim_state_code=0
            ;;
        *"READY"*) 
            sim_status="ready" 
            sim_state_code=1
            ;;
        *"SIM PIN"*) 
            sim_status="MT is waiting SIM PIN to be given"
            sim_state_code=2
             ;;
        *"SIM PUK"*) 
            sim_status="MT is waiting SIM PUK to be given"
            sim_state_code=3
            ;;
        *"PH-FSIM PIN"*)
            sim_status="MT is waiting phone-to-SIM card password to be given"
            sim_state_code=4
            ;;
        *"PH-FSIM PIN"*) 
            sim_status="MT is waiting phone-to-very first SIM card password to be given"
            sim_state_code=5
            ;;
        *"PH-FSIM PUK"*) 
            sim_status="MT is waiting phone-to-very first SIM card unblocking password to be given"
            sim_state_code=6
            ;;
        *"SIM PIN2"*) 
            sim_status="MT is waiting SIM PIN2 to be given"
            sim_state_code=7
            ;;
        *"SIM PUK2"*) 
            sim_status="MT is waiting SIM PUK2 to be given" 
            sim_state_code=8
            ;;
        *"PH-NET PIN"*) 
            sim_status="MT is waiting network personalization password to be given" 
            sim_state_code=9
            ;;
        *"PH-NET PUK"*) 
            sim_status="MT is waiting network personalization unblocking password to be given" 
            sim_state_code=10
            ;;
        *"PH-NETSUB PIN"*) 
            sim_status="MT is waiting network subset personalization password to be given" 
            sim_state_code=11
            ;;
        *"PH-NETSUB PUK"*) 
            sim_status="MT is waiting network subset personalization unblocking password to be given" 
            sim_state_code=12
            ;;
        *"PH-SP PIN"*) 
            sim_status="MT is waiting service provider personalization password to be given" 
            sim_state_code=13
            ;;
        *"PH-SP PUK"*)
            sim_status="MT is waiting service provider personalization unblocking password to be given"
            sim_state_code=14
            ;;
        *"PH-CORP PIN"*) 
            sim_status="MT is waiting corporate personalization password to be given" 
            sim_state_code=16
            ;;

        *"PH-CORP PUK"*) 
            sim_status="MT is waiting corporate personalization unblocking password to be given" 
            sim_state_code=17
            ;;
        *) 
            sim_status="unknown" 
            sim_state_code=99
            ;;
    esac
    echo "$sim_status"
}

#获取信号强度指示
# $1:信号强度指示数字
get_rssi()
{
    local rssi
    case $1 in
		"99") rssi="unknown" ;;
		* )  rssi=$((2 * $1 - 113)) ;;
	esac
    echo "$rssi"
}

#获取网络类型
# $1:网络类型数字
get_rat()
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

#获取连接状态
#return raw data
get_connect_status()
{
    connect_status="No"
    driver=$(get_driver)
    if [ "$driver" = "mtk_pcie" ]; then
        mbim_port=$(echo "$at_port" | sed 's/at/mbim/g')
        local config=$(umbim -d $mbim_port config)
        local ipv4=$(echo "$config" | grep "ipv4address:" | awk '{print $2}' | cut -d'/' -f1)
        local ipv6=$(echo "$config" | grep "ipv6address:" | awk '{print $2}' | cut -d'/' -f1)

        disallow_ipv4="0.0.0.0"
        if [ -n "$ipv4" ] && [ "$ipv4" != "$disallow_ipv4" ] || [ -n "$ipv6" ] && [ "$ipv6" != "::" ]; then
            connect_status="Yes"
        fi
    else
        at_cmd="AT+CGACT?"
        expect="+CGACT:"
        result=`at  $at_port $at_cmd | grep $expect|tr '\r' '\n'`
        
        for pdp_index in `echo  "$result" | tr -d "\r" | awk -F'[,:]' '$3 == 1 {print $2}'`; do
            at_cmd="AT+CGPADDR=%s"
            at_cmd=$(printf "$at_cmd" "$pdp_index")
            expect="+CGPADDR:"
            result=$(at  $at_port $at_cmd | grep $expect)
            if [ -n "$result" ];then
                ipv6=$(echo $result | grep -oE "\b([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\b")
                ipv4=$(echo $result | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
                disallow_ipv4="0.0.0.0"
                #remove the disallow ip
                if [ "$ipv4" == "$disallow_ipv4" ];then
                    ipv4=""
                fi
            fi
            if [ -n "$ipv4" ] || [ -n "$ipv6" ];then
                connect_status="Yes"
                break
            else
                connect_status="No"
            fi
        done
    fi
    add_plain_info_entry "connect_status" "$connect_status" "Connect Status"
}

#获取移远模组信息
# $1:AT串口
# $2:平台
# $3:连接定义
get_info()
{
    #基本信息
    base_info

	#SIM卡信息
    sim_info
    if [ "$sim_status" != "ready" ]; then
        add_warning_message_entry "sim_status" "$sim_status" "SIM Error,Error code:" "warning"
        return
    fi

    #网络信息
    network_info
    if [ "$connect_status" != "Yes" ]; then
        return
    fi

    #小区信息
    cell_info

    return

}

soft_reboot()
{
    at_command="AT+CFUN=1,1"
    at $at_port $at_command
}

hard_reboot()
{
    #get power_gpio_pin
    source /lib/functions.sh
    config_load qmodem
    config_foreach get_gpio_by_slot modem-slot
    gpio="/sys/class/gpio/$gpio/value"
    [ ! -f "$gpio" ] || [ -z "$gpio_up" ] || [ -z "$gpio_down" ] && {
        soft_reboot
        m_debug "gpio not found, failback to soft reboot"
        return
    }
    echo $gpio_down > $gpio
    sleep 1
    echo $gpio_up > $gpio
    
}

get_gpio_by_slot()
{
    local cfg="$1"
    config_get slot "$cfg" slot
    if [ "$modem_slot" = "$slot" ];then
        config_get gpio "$cfg" gpio
        config_get gpio_up "$cfg" gpio_up
        config_get gpio_down "$cfg" gpio_down
    fi
}

get_reboot_caps()
{
    source /lib/functions.sh
    config_load qmodem
    config_foreach get_gpio_by_slot modem-slot
    json_init
    json_add_object "reboot_caps"
    json_add_int "soft_reboot_caps" "1"
    if [ -n "$gpio" ] && [ -n "$gpio_up" ] && [ -n "$gpio_down" ];then
         json_add_int "hard_reboot_caps" "1" 
    else
        json_add_int "hard_reboot_caps" "0"
    fi
    json_close_object
    json_dump
}

rate_convert()
{
    #check if bc is installed
    is_bc_installed=$(which bc)
    local rate=$1
    rate_units="bps Kbps Mbps Gbps"
    if [ -z "$is_bc_installed" ]; then
        for i in $(seq 0 3); do
            if [ $rate -lt 1024 ]; then
                break
            fi
            rate=$(($rate / 1024))
        done
    else
        for i in $(seq 0 3); do
            if [ $(echo "$rate < 1024" | bc) -eq 1 ]; then
                break
            fi
            rate=$(echo "scale=2; $rate / 1024" | bc)
        done
    fi
    echo "$rate `echo $rate_units | cut -d ' ' -f $(($i+1))`"
}

get_modem_disabled_features()
{
    . /lib/functions.sh
    config_load qmodem 
    config_list_foreach $config_section disabled_features _add_disabled_features
}

get_sms_capabilities() {
    local res sms_cap
    res=$(at $at_port "AT+CPMS?" | grep "CPMS:" | xargs)
    [ -z "$res" ] && return

    sms_cap=${res##*+CPMS:}
    set -- $(echo "$sms_cap" | tr ',' ' ')
    local mem1=$1 used1=$2 total1=$3
    local mem2=$4 used2=$5 total2=$6
    local mem3=$7 used3=$8 total3=$9

    json_add_object "sms_capabilities"
    json_add_string "mem1" "$mem1"
    json_add_string "mem2" "$mem2"
    json_add_string "mem3" "$mem3"
    json_add_object "ME"
    json_close_object
    json_add_object "SM"
    json_close_object

    for idx in 1 2 3; do
        eval "mem=\$mem$idx"
        eval "used=\$used$idx"
        eval "total=\$total$idx"

        case "$mem" in
            "SM")
                json_select "SM"
                ;;
            "MT"|"ME")
                json_select "ME"
                ;;
            *)
                continue
                ;;
        esac

        json_add_string "used" "$used"
        json_add_string "total" "$total"
        json_close_object
    done
}

set_sms_storage()
{
    mem1=$(echo $1 | jq -r '.mem1')
    mem2=$(echo $1 | jq -r '.mem2')
    mem3=$(echo $1 | jq -r '.mem3')
    json_add_string "raw" "$1"
    if [ -z "$mem1" ] || [ -z "$mem2" ]; then
        return
    fi
    if [ "$mem3" == "Loading" ];then
        res=$(at $at_port "AT+CPMS=\"$mem1\",\"$mem2\"")
    else
        res=$(at $at_port "AT+CPMS=\"$mem1\",\"$mem2\",\"$mem3\"")
    fi
    
    json_select "result"
    json_add_string "result" "$res"
}


get_global_disabled_features()
{
    . /lib/functions.sh
    config_load qmodem 
    config_list_foreach main disabled_features _add_disabled_features
}

_add_disabled_features()
{
    json_add_string "" "$1"
}

_copyright()
{
    json_add_object "copyright"
    json_add_string "Vendor" "${_Vendor}"
    json_add_string "Author" "${_Author}"
    json_add_string "Maintainer" "${_Maintainer}"
    json_close_object
}
