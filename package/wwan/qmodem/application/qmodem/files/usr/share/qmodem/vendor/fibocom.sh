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

fibocom_is_uint()
{
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

fibocom_hex_to_dec()
{
    local value=$(echo "$1" | tr -d '\r" ')

    [ -z "$value" ] && return

    case "$value" in
        0x*|0X*)
            value="${value#0x}"
            value="${value#0X}"
            ;;
    esac

    case "$value" in
        *[!0-9A-Fa-f]*)
            echo "$1"
            return
            ;;
    esac

    printf "%d" "0x$value" 2>/dev/null || echo "$1"
}

fibocom_normalize_nr_band()
{
    local band=$(echo "$1" | tr -d '\r" ')

    [ -z "$band" ] && return
    band="${band#n}"
    band="${band#N}"

    if fibocom_is_uint "$band"; then
        if [ "$band" -ge 5000 ]; then
            echo "$band"
        else
            echo "50$band"
        fi
    else
        echo "$1"
    fi
}

fibocom_normalize_band_list()
{
    echo "$1" | tr ':' ',' | tr ' ' ',' | awk -F',' '
        {
            for (i = 1; i <= NF; i++) {
                gsub(/^[ \t\r"]+|[ \t\r"]+$/, "", $i)
                if ($i != "" && $i != "null")
                    print $i
            }
        }' | sort -n | uniq | tr '\n' ',' | sed 's/,$//'
}

fibocom_gtact_band_code()
{
    local rat="$1"
    local band=$(echo "$2" | tr -d '\r" nNB ')

    [ -z "$band" ] && return

    case "$rat" in
        "LTE")
            if fibocom_is_uint "$band" && [ "$band" -lt 100 ]; then
                band=$((band + 100))
            fi
            ;;
        "NR")
            if fibocom_is_uint "$band" && [ "$band" -lt 5000 ]; then
                for nr_code in $(echo "$ALL_NR_CODES" | tr ',' ' '); do
                    if [ "$(fibocom_gtact_band_display "NR" "$nr_code")" = "$band" ]; then
                        echo "$nr_code"
                        return
                    fi
                done
                if [ "$band" -lt 10 ]; then
                    band=$((band + 500))
                else
                    band=$((band + 5000))
                fi
            fi
            ;;
    esac

    echo "$band"
}

fibocom_gtact_band_display()
{
    local rat="$1"
    local band=$(echo "$2" | tr -d '\r" ')

    [ -z "$band" ] && return

    case "$rat" in
        "LTE")
            if fibocom_is_uint "$band" && [ "$band" -ge 100 ]; then
                band=$((band - 100))
            fi
            ;;
        "NR")
            if fibocom_is_uint "$band"; then
                if [ "$band" -ge 5000 ]; then
                    band=$((band - 5000))
                elif [ "$band" -ge 500 ]; then
                    band=$((band - 500))
                fi
            fi
            ;;
    esac

    echo "$band"
}

fibocom_gtact_encode_list()
{
    local rat="$1"
    local list="$2"
    local out="" code

    for band in $(echo "$list" | tr ',' ' '); do
        code=$(fibocom_gtact_band_code "$rat" "$band")
        [ -n "$code" ] && out="${out},${code}"
    done

    fibocom_normalize_band_list "${out#,}"
}

fibocom_gtact_add_available_band()
{
    local rat="$1"
    local raw_band="$2"
    local band

    [ -z "$raw_band" ] && return

    band=$(fibocom_gtact_band_display "$rat" "$raw_band")
    [ -z "$band" ] && return

    json_select "$rat"
    json_select "available_band"
    case "$rat" in
        "UMTS")
            add_avalible_band_entry "$band" "UMTS_$band"
            ;;
        "LTE")
            add_avalible_band_entry "$band" "LTE_B$band"
            ;;
        "NR")
            add_avalible_band_entry "$band" "NR_N$band"
            ;;
    esac
    json_select ".."
    json_select ".."
}

fibocom_gtact_add_lock_band()
{
    local raw_band=$(echo "$1" | tr -d '\r" ')
    local rat band

    [ -z "$raw_band" ] && return
    fibocom_is_uint "$raw_band" || return

    if [ "$raw_band" -lt 100 ]; then
        rat="UMTS"
    elif [ "$raw_band" -lt 500 ]; then
        rat="LTE"
    else
        rat="NR"
    fi

    band=$(fibocom_gtact_band_display "$rat" "$raw_band")
    [ -z "$band" ] && return

    json_select "$rat"
    json_select "lock_band"
    json_add_string "" "$band"
    json_select ".."
    json_select ".."
}

fibocom_gtact_parse_current_bands()
{
    local band_params=$(echo "$1" | grep "+GTACT:" | head -n1 | sed 's/+GTACT:[ ]*//' | tr -d '\r')
    local first second third rest has_explicit_bands=0

    first=$(echo "$band_params" | cut -d',' -f1 | tr -d ' ')
    second=$(echo "$band_params" | cut -d',' -f2 | tr -d ' ')
    third=$(echo "$band_params" | cut -d',' -f3 | tr -d ' ')
    GTACT_PARAM2="$second"
    GTACT_PARAM3="$third"
    rest=$(echo "$band_params" | cut -d',' -f4- | tr -d '\r')
    [ -z "$rest" ] || [ "$rest" = "$band_params" ] && rest=""

    for b in $(echo "$rest" | tr ',' ' '); do
        b=$(echo "$b" | tr -d '\r" ')
        if fibocom_is_uint "$b"; then
            has_explicit_bands=1
            break
        fi
    done

    if [ "$has_explicit_bands" = "0" ]; then
        case "$first" in
            "1") umts_bands="$ALL_UMTS_CODES"; lte_bands=""; nr_bands="" ;;
            "2") umts_bands=""; lte_bands="$ALL_LTE_CODES"; nr_bands="" ;;
            "4") umts_bands="$ALL_UMTS_CODES"; lte_bands="$ALL_LTE_CODES"; nr_bands="" ;;
            "14") umts_bands=""; lte_bands=""; nr_bands="$ALL_NR_CODES" ;;
            "16") umts_bands="$ALL_UMTS_CODES"; lte_bands=""; nr_bands="$ALL_NR_CODES" ;;
            "17") umts_bands=""; lte_bands="$ALL_LTE_CODES"; nr_bands="$ALL_NR_CODES" ;;
            "10"|"20") umts_bands="$ALL_UMTS_CODES"; lte_bands="$ALL_LTE_CODES"; nr_bands="$ALL_NR_CODES" ;;
        esac
    fi

    for b in $(echo "$rest" | tr ',' ' '); do
        b=$(echo "$b" | tr -d '\r" ')
        [ -z "$b" ] && continue
        fibocom_is_uint "$b" || continue

        if [ "$b" -lt 100 ]; then
            umts_bands="${umts_bands},$b"
        elif [ "$b" -lt 500 ]; then
            lte_bands="${lte_bands},$b"
        else
            nr_bands="${nr_bands},$b"
        fi
    done

    umts_bands=$(fibocom_normalize_band_list "$umts_bands")
    lte_bands=$(fibocom_normalize_band_list "$lte_bands")
    nr_bands=$(fibocom_normalize_band_list "$nr_bands")
}

fibocom_gtact_extract_available_group()
{
    local response="$1"
    local group="$2"

    echo "$response" | grep "+GTACT:" | head -n1 | awk -v group="$group" -F'[()]' '
        {
            count = 0
            for (i = 2; i <= NF; i += 2) {
                count++
                if (count == group) {
                    print $i
                    exit
                }
            }
        }' | tr -d ' '
}

fibocom_gtact_load_available_bands()
{
    local response="$1"

    ALL_UMTS_CODES=$(fibocom_normalize_band_list "$(fibocom_gtact_extract_available_group "$response" 5)")
    ALL_LTE_CODES=$(fibocom_normalize_band_list "$(fibocom_gtact_extract_available_group "$response" 6)")
    ALL_NR_CODES=$(fibocom_normalize_band_list "$(fibocom_gtact_extract_available_group "$response" 9)")

    [ -z "$ALL_UMTS_CODES" ] && ALL_UMTS_CODES="1,2,4,5,6,8,19"
    [ -z "$ALL_LTE_CODES" ] && ALL_LTE_CODES="101,103,105,107,108,120,128,132,138,140,141,142,143,148,166"
    [ -z "$ALL_NR_CODES" ] && ALL_NR_CODES="5001,5003,5005,5007,5008,5020,5028,5038,5040,5041,5048,5066,5077,5078,5079"
}

fibocom_gtact_network_prefer_from_bands()
{
    local has_umts=0 has_lte=0 has_nr=0

    [ -n "$umts_bands" ] && has_umts=1
    [ -n "$lte_bands" ] && has_lte=1
    [ -n "$nr_bands" ] && has_nr=1

    if [ "$has_umts" = "1" ] && [ "$has_lte" = "1" ] && [ "$has_nr" = "1" ]; then
        echo "20"
    elif [ "$has_umts" = "1" ] && [ "$has_lte" = "1" ]; then
        echo "4"
    elif [ "$has_umts" = "1" ] && [ "$has_nr" = "1" ]; then
        echo "16"
    elif [ "$has_lte" = "1" ] && [ "$has_nr" = "1" ]; then
        echo "17"
    elif [ "$has_nr" = "1" ]; then
        echo "14"
    elif [ "$has_lte" = "1" ]; then
        echo "2"
    elif [ "$has_umts" = "1" ]; then
        echo "1"
    else
        echo "20"
    fi
}

fibocom_gtact_command()
{
    local network_prefer_num="$1"
    local bands_str="$2"
    local rat_count=0

    [ -n "$umts_bands" ] && rat_count=$((rat_count + 1))
    [ -n "$lte_bands" ] && rat_count=$((rat_count + 1))
    [ -n "$nr_bands" ] && rat_count=$((rat_count + 1))

    if [ -z "$bands_str" ]; then
        echo "AT+GTACT=${network_prefer_num}"
    elif [ "$rat_count" -gt 1 ]; then
        echo "AT+GTACT=${network_prefer_num},${GTACT_PARAM2:-6},${GTACT_PARAM3:-3},$bands_str"
    else
        echo "AT+GTACT=${network_prefer_num},,,$bands_str"
    fi
}

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
                "31") mode="ncm" ;;
                "32") mode="ecm" ;;
                "33") mode="rndis" ;;
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
    json_add_object "result"
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
    json_close_object
}

#设置网络偏好
# $1:网络偏好配置
set_network_prefer_nr()
{
    local bands_str

    network_prefer_3g=$(echo $1 |jq -r 'contains(["3G"])')
    network_prefer_4g=$(echo $1 |jq -r 'contains(["4G"])')
    network_prefer_5g=$(echo $1 |jq -r 'contains(["5G"])')
    count=$(echo $1 |jq -r 'length')
    case "$count" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                network_prefer_num="1"
            elif [ "$network_prefer_4g" = "true" ]; then
                network_prefer_num="2"
            elif [ "$network_prefer_5g" = "true" ]; then
                network_prefer_num="14"
            fi
        ;;
        "2")
            if [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_num="17"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_num="16"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                network_prefer_num="4"
            elif [ "$network_prefer_4g" = "true" ]; then
                network_prefer_num="2"
            elif [ "$network_prefer_5g" = "true" ]; then
                network_prefer_num="14"
            else
                network_prefer_num="20"
            fi
        ;;
        "3") network_prefer_num="20" ;;
        *) network_prefer_num="20" ;;
    esac

    get_lockband_config_res=$(at $at_port "AT+GTACT?" | grep "+GTACT:" | head -n1)
    get_available_band_res=$(at $at_port "AT+GTACT=?" | grep "+GTACT:" | head -n1)
    fibocom_gtact_load_available_bands "$get_available_band_res"
    umts_bands=""
    lte_bands=""
    nr_bands=""
    fibocom_gtact_parse_current_bands "$get_lockband_config_res"

    [ "$network_prefer_3g" = "true" ] || umts_bands=""
    [ "$network_prefer_4g" = "true" ] || lte_bands=""
    [ "$network_prefer_5g" = "true" ] || nr_bands=""

    [ "$network_prefer_3g" = "true" ] && [ -z "$umts_bands" ] && umts_bands="$ALL_UMTS_CODES"
    [ "$network_prefer_4g" = "true" ] && [ -z "$lte_bands" ] && lte_bands="$ALL_LTE_CODES"
    [ "$network_prefer_5g" = "true" ] && [ -z "$nr_bands" ] && nr_bands="$ALL_NR_CODES"

    bands_str=$(fibocom_normalize_band_list "$umts_bands,$lte_bands,$nr_bands")
    at_command=$(fibocom_gtact_command "${network_prefer_num:-20}" "$bands_str")

    res=$(at $at_port "$at_command")
    json_add_object "result"
    json_add_string "status" "$res"
    json_add_string "command" "$at_command"
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
    json_close_object
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
    json_add_object "result"
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
    
    [ -z "$response" ] && {
        #紫光平台
        at_command="AT+MTSM=1"
        response=$(at $at_port $at_command | grep "+MTSM: " | sed 's/+MTSM: //g' | sed 's/\r//g')
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
    add_plain_info_entry "name" "$name" "Name"
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
		[ -z "$iccid" ] && {
        iccid=$(at ${at_port} "AT+CCID" | grep -o "+CCID:[ ]*[-0-9]\+" | awk -F' ' '{print $2}')
    }
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
    class="Network Information"
    #Network Type（网络类型）
    at_command="AT+PSRAT?"
    network_type=$(at ${at_port} ${at_command} | grep "+PSRAT:" | sed 's/+PSRAT: //g' | sed 's/\r//g')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(at ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(get_rat ${rat_num})
    }
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
    case $platform in
        #qualcomm only command
        "qualcomm")
            #CSQ（信号强度）
            #速率统计
            at_command="AT+GTSTATIS?"
            response=$(at $at_port $at_command | grep "+GTSTATIS:" | sed 's/+GTSTATIS: //g' | sed 's/\r//g')

            #当前上传速率（单位，Byte/s）
            tx_rate=$(echo $response | awk -F',' '{print $2}')

            #当前下载速率（单位，Byte/s）
            rx_rate=$(echo $response | awk -F',' '{print $1}')
            if [ -z "$tx_rate" ] || [ -z "$rx_rate" ]; then
                return
            fi
            add_speed_entry rx $rx_rate
            add_speed_entry tx $tx_rate
        ;;
    esac
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
    m_debug "Fibocom get lockband info nr"
    get_lockband_config_command="AT+GTACT?"
    get_available_band_command="AT+GTACT=?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command)
    get_available_band_res=$(at $at_port $get_available_band_command)
    fibocom_gtact_load_available_bands "$get_available_band_res"
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
    json_add_object "NR"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object

    for i in $(echo "$ALL_UMTS_CODES" | tr ',' ' '); do
        fibocom_gtact_add_available_band "UMTS" "$i"
    done
    for i in $(echo "$ALL_LTE_CODES" | tr ',' ' '); do
        fibocom_gtact_add_available_band "LTE" "$i"
    done
    for i in $(echo "$ALL_NR_CODES" | tr ',' ' '); do
        fibocom_gtact_add_available_band "NR" "$i"
    done

    umts_bands=""
    lte_bands=""
    nr_bands=""
    fibocom_gtact_parse_current_bands "$get_lockband_config_res"

    for i in $(echo "$umts_bands" | tr ',' ' '); do
        fibocom_gtact_add_lock_band "$i"
    done
    for i in $(echo "$lte_bands" | tr ',' ' '); do
        fibocom_gtact_add_lock_band "$i"
    done
    for i in $(echo "$nr_bands" | tr ',' ' '); do
        fibocom_gtact_add_lock_band "$i"
    done
}

#锁频信息
get_lockband_lte()
{
    m_debug "Fibocom get lockband info lte"
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
            trim_first_letter=$(get_band "LTE" "$i")
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
            set_lockband_nr_mediatek
            ;;
        "lte")
            set_lockband_lte
            ;;
        *)
            set_lockband_nr
            ;;
    esac
    json_add_object "result"
    [ -n "$set_lockband_command" ] && json_add_string "command" "$set_lockband_command"
    json_add_string "set_lockband" "$res"
    json_add_string "config" "$config"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$lock_band"
    json_close_object
}

#设置锁频
set_lockband_nr_mediatek()
{
    m_debug "Fibocom set lockband info"
    get_lockband_config_command="AT+GTACT?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command)
    network_prefer_config=$(echo $get_lockband_config_res |cut -d : -f 2| awk -F"," '{print $1}' |tr -d ' ')
    local lock_band="$network_prefer_config,6,3,$lock_band"
    set_lockband_command="AT+GTACT=$lock_band"
    res=$(at $at_port $set_lockband_command)
}

set_lockband_nr()
{
    m_debug "Fibocom set lockband info nr"

    local network_prefer_num bands_str

    get_lockband_config_command="AT+GTACT?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command | grep "+GTACT:" | head -n1)
    get_available_band_res=$(at $at_port "AT+GTACT=?" | grep "+GTACT:" | head -n1)
    fibocom_gtact_load_available_bands "$get_available_band_res"

    band_class=$(echo "$config" | jq -r '.band_class')

    umts_bands=""
    lte_bands=""
    nr_bands=""
    fibocom_gtact_parse_current_bands "$get_lockband_config_res"

    case "$band_class" in
        "UMTS")
            umts_bands=$(fibocom_gtact_encode_list "UMTS" "$lock_band")
            ;;
        "LTE")
            lte_bands=$(fibocom_gtact_encode_list "LTE" "$lock_band")
            ;;
        "NR")
            nr_bands=$(fibocom_gtact_encode_list "NR" "$lock_band")
            ;;
    esac

    bands_str=$(fibocom_normalize_band_list "$umts_bands,$lte_bands,$nr_bands")
    network_prefer_num=$(fibocom_gtact_network_prefer_from_bands)

    set_lockband_command=$(fibocom_gtact_command "$network_prefer_num" "$bands_str")

    res=$(at $at_port "$set_lockband_command")
}

set_lockband_lte()
{
    m_debug "Fibocom set lte lockband"
    get_lockband_config_command="AT+GTACT?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command)
    network_prefer_config=$(echo $get_lockband_config_res |cut -d : -f 2| awk -F"," '{ print $1}' |tr -d ' ')
    local lock_band="$network_prefer_config,,,$lock_band"
    set_lockband_command="AT+GTACT=$lock_band"
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
            "1,9"*|"2,9"*)
                m_debug "NR line:$line"
                tac=$(echo "$line" | awk -F',' '{print $5}')
                cellid=$(echo "$line" | awk -F',' '{print $6}')
                arfcn=$(echo "$line" | awk -F',' '{print $7}')
                pci=$(echo "$line" | awk -F',' '{print $8}')
                band_num=$(echo "$line" | awk -F',' '{print $9}')
                ss_sinr=$(echo "$line" | awk -F',' '{print $10}')
                rxlev=$(echo "$line" | awk -F',' '{print $11}')
                ss_rsrp=$(echo "$line" | awk -F',' '{print $12}')
                tac=$(fibocom_hex_to_dec "$tac")
                cellid=$(fibocom_hex_to_dec "$cellid")
                arfcn=$(fibocom_hex_to_dec "$arfcn")
                pci=$(fibocom_hex_to_dec "$pci")
                band=$(get_band "NR" "$band_num")
                json_select "NR"
                json_add_object ""
                json_add_string "tac" "$tac"
                json_add_string "cellid" "$cellid"
                json_add_string "arfcn" "$arfcn"
                json_add_string "pci" "$pci"
                json_add_string "band" "$band"
                json_add_string "ss_sinr" "$ss_sinr"
                json_add_string "rxlev" "$rxlev"
                json_add_string "ss_rsrp" "$ss_rsrp"
                json_close_object
                json_select ".."
                ;;
            "1,4"*|"2,4"*)
                tac=$(echo "$line" | awk -F',' '{print $5}')
                cellid=$(echo "$line" | awk -F',' '{print $6}')
                arfcn=$(echo "$line" | awk -F',' '{print $7}')
                pci=$(echo "$line" | awk -F',' '{print $8}')
                bandwidth=$(echo "$line" | awk -F',' '{print $9}')
                rxlev=$(echo "$line" | awk -F',' '{print $10}')
                rsrp=$(echo "$line" | awk -F',' '{print $11}')
                rsrq=$(echo "$line" | awk -F',' '{print $12}')
                tac=$(fibocom_hex_to_dec "$tac")
                cellid=$(fibocom_hex_to_dec "$cellid")
                arfcn=$(fibocom_hex_to_dec "$arfcn")
                pci=$(fibocom_hex_to_dec "$pci")
                bandwidth=$(get_bandwidth "LTE" "$bandwidth")
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
    qmodem_lockcell_boot_hook_add_json "$config_section"
    json_close_object
}

set_neighborcell(){
    json_param=$1
    rat=$(echo $json_param | jq -r '.rat')
    pci=$(echo $json_param | jq -r '.pci')
    arfcn=$(echo $json_param | jq -r '.arfcn')
    band=$(echo $json_param | jq -r '.band')
    scs=$(echo $json_param | jq -r '.scs')
    en_boot_hook=$(echo $json_param | jq -r '.en_boot_hook // empty')
    lockcell_all
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

lockcell_all(){
    if [ -z "$pci" ] && [ -z "$arfcn" ]; then
        local unlockcell="AT+GTCELLLOCK=0"
        res1=$(at $at_port $unlockcell)
        res=$res1
        qmodem_lockcell_boot_hook_clear "$config_section"
    else
        if [ -z "$pci" ] && [ -n "$arfcn" ]; then
            lockpci_nr="AT+GTCELLLOCK=1,1,1,$arfcn"
            lockpci_lte="AT+GTCELLLOCK=1,0,1,$arfcn"
            
        elif [ -n "$pci" ] && [ -n "$arfcn" ]; then
            nr_band=$(fibocom_normalize_nr_band "$band")
            [ -z "$scs" ] && scs="1"
            lockpci_nr="AT+GTCELLLOCK=1,1,0,$arfcn,$pci,$scs,$nr_band"
            lockpci_lte="AT+GTCELLLOCK=1,0,0,$arfcn,$pci"
        fi
        if [ "$pci" = "0" ] && [ "$arfcn" = "0" ]; then
            lockpci_nr="AT+GTCELLLOCK=1"
            lockpci_lte="AT+GTCELLLOCK=1"
        fi
        if [ "$rat" = "1" ]; then
            lockcell_boot_cmd="$lockpci_nr"
        elif [ "$rat" = "0" ]; then
            lockcell_boot_cmd="$lockpci_lte"
        fi
        res=$(at $at_port "$lockcell_boot_cmd")
        qmodem_lockcell_boot_hook_sync "$config_section" "$en_boot_hook" "$lockcell_boot_cmd"
    fi
}

get_band()
{
    local band=$(echo "$2" | tr -d '\r" ')
    case $1 in
		"WCDMA") ;;
		"LTE")
            if fibocom_is_uint "$band" && [ "$band" -ge 100 ]; then
                band=$((band - 100))
            fi
            ;;
        "NR")
            if fibocom_is_uint "$band"; then
                if [ "$band" -ge 5000 ]; then
                    band="${band#50}"
                elif [ "$band" -ge 500 ]; then
                    band=$((band - 500))
                fi
            fi
            ;;
	esac
    echo "$band"
}

#获取带宽
# $1:网络类型
# $2:带宽数字
get_bandwidth()
{
    local network_type="$1"
    local bandwidth_num=$(echo "$2" | tr -d '\r" ')

    local bandwidth
    [ -z "$bandwidth_num" ] && return
    case $network_type in
		"LTE")
            case $bandwidth_num in
                "0") bandwidth="1.4" ;;
                "1") bandwidth="3" ;;
                "2") bandwidth="5" ;;
                "3") bandwidth="10" ;;
                "4") bandwidth="15" ;;
                "5") bandwidth="20" ;;
                "6") bandwidth="1.4" ;;
                "15"|"25"|"50"|"75"|"100") bandwidth=$((bandwidth_num / 5)) ;;
                *) bandwidth="$bandwidth_num" ;;
            esac
        ;;
        "NR")
            case $bandwidth_num in
                "0") bandwidth="5" ;;
                "1") bandwidth="10" ;;
                "2") bandwidth="15" ;;
                "3") bandwidth="20" ;;
                "4") bandwidth="25" ;;
                "5") bandwidth="30" ;;
                "6") bandwidth="40" ;;
                "7") bandwidth="50" ;;
                "8") bandwidth="60" ;;
                "9") bandwidth="70" ;;
                "10") bandwidth="80" ;;
                "11") bandwidth="90" ;;
                "12") bandwidth="100" ;;
                "25"|"50"|"75"|"100"|"125"|"150"|"200"|"250"|"300"|"400"|"500") bandwidth=$((bandwidth_num / 5)) ;;
                *) bandwidth="$bandwidth_num" ;;
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

    at_command='AT+GTCAINFO?'
    ca_response=$(at $at_port $at_command)

    local rat=$(echo "$response" | grep "service" | awk -F' ' '{print $1}')

    #适配联发科平台（FM350-GL）
    [ -z "$rat" ] && {
        at_command='AT+COPS?'
        rat_num=$(at $at_port $at_command | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        rat=$(get_rat ${rat_num})
    }
    
    #CSQ（信号强度）
    at_command="AT+CSQ"
    csqinfo=$(at ${at_port} ${at_command} | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')
    
    #RSSI（信号强度指示）
    rssi_num=$(echo $csqinfo | awk -F',' '{print $1}')
    rssi=$(get_rssi $rssi_num)
    [ -n "$rssi" ] && rssi_actual=$(printf "%.1f" $(echo "$rssi / 10" | bc -l 2>/dev/null))
    ca_count=1
    scc_pci=""
    scc_arfcn=""
    scc_band=""
    scc_dl_bandwidth=""
    scc_ul_bandwidth=""
    for response in $response; do
        #排除+GTCCINFO:、NR service cell:还有空行
        [ -n "$response" ] && [[ "$response" = *","* ]] && {

            case $rat in
                "NR")
                    network_mode="NR5G-SA Mode"
                    IFS=$'\n'
                    for ca_res in $ca_response; do
                        if echo "$ca_res" | grep -q "SCC"; then
                            ca_count=$((ca_count+1))
                            scc_ul_ca=$(echo "$ca_res" | awk -F',' '{print $2}')
                            scc_band_num=$(echo "$ca_res" | awk -F',' '{print $3}')
                            scc_pci_new=$(echo "$ca_res" | awk -F',' '{print $4}')
                            scc_pci_new=$(fibocom_hex_to_dec "$scc_pci_new")
                            if [ -z "$scc_pci" ]; then
                                scc_pci="$scc_pci_new"
                            else
                                scc_pci="$scc_pci / $scc_pci_new"
                            fi
                            scc_arfcn_new=$(echo "$ca_res" | awk -F',' '{print $5}')
                            scc_arfcn_new=$(fibocom_hex_to_dec "$scc_arfcn_new")
                            if [ -z "$scc_arfcn" ]; then
                                scc_arfcn="$scc_arfcn_new"
                            else
                                scc_arfcn="$scc_arfcn / $scc_arfcn_new"
                            fi
                            scc_band_new=$(get_band "NR" ${scc_band_num})
                            if [ -z "$scc_band" ]; then
                                scc_band="$scc_band_new"
                            else
                                scc_band="$scc_band / $scc_band_new"
                            fi
                            scc_dl_bandwidth_num=$(echo "$ca_res" | awk -F',' '{print $6}')
                            scc_dl_bandwidth_new=$(get_bandwidth "NR" ${scc_dl_bandwidth_num})
                            if [ -z "$scc_dl_bandwidth" ]; then
                                scc_dl_bandwidth="$scc_dl_bandwidth_new"
                            else
                                scc_dl_bandwidth="$scc_dl_bandwidth / $scc_dl_bandwidth_new"
                            fi
                            if [ "$scc_ul_ca" = "1" ]; then
                                scc_ul_bandwidth_new=$scc_dl_bandwidth_new
                            else
                                scc_ul_bandwidth_num="-"
                            fi
                            if [ -z "$scc_ul_bandwidth" ]; then
                                scc_ul_bandwidth="$scc_ul_bandwidth_new"
                            else
                                scc_ul_bandwidth="$scc_ul_bandwidth / $scc_ul_bandwidth_new"
                            fi
                        fi
                    done
                    IFS=' '
                    [ $ca_count -gt 1 ] && network_mode="$network_mode with $ca_count CA"
                    nr_mcc=$(echo "$response" | awk -F',' '{print $3}')
                    nr_mnc=$(echo "$response" | awk -F',' '{print $4}')
                    nr_tac=$(echo "$response" | awk -F',' '{print $5}')
                    nr_tac=$(fibocom_hex_to_dec "$nr_tac")
                    nr_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    nr_cell_id=$(fibocom_hex_to_dec "$nr_cell_id")
                    nr_arfcn=$(echo "$response" | awk -F',' '{print $7}')
                    nr_arfcn=$(fibocom_hex_to_dec "$nr_arfcn")
                    nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    nr_physical_cell_id=$(fibocom_hex_to_dec "$nr_physical_cell_id")
                    nr_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    nr_band=$(get_band "NR" ${nr_band_num})
                    nr_serving_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    nr_dl_bandwidth_num=$(echo "$ca_response" | grep "PCC" | sed 's/\r//g' | awk -F',' '{print $4}')
                    [ -z "$nr_dl_bandwidth_num" ] && nr_dl_bandwidth_num="$nr_serving_bandwidth_num"
                    nr_dl_bandwidth=$(get_bandwidth "NR" ${nr_dl_bandwidth_num})
                    nr_ul_bandwidth_num=$(echo "$ca_response" | grep "PCC" | sed 's/\r//g' | awk -F',' '{print $5}')
                    [ -z "$nr_ul_bandwidth_num" ] && nr_ul_bandwidth_num="$nr_serving_bandwidth_num"
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
                    endc_lte_tac=$(fibocom_hex_to_dec "$endc_lte_tac")
                    endc_lte_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    endc_lte_cell_id=$(fibocom_hex_to_dec "$endc_lte_cell_id")
                    endc_lte_earfcn=$(echo "$response" | awk -F',' '{print $7}')
                    endc_lte_earfcn=$(fibocom_hex_to_dec "$endc_lte_earfcn")
                    endc_lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    endc_lte_physical_cell_id=$(fibocom_hex_to_dec "$endc_lte_physical_cell_id")
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
                    endc_nr_tac=$(fibocom_hex_to_dec "$endc_nr_tac")
                    endc_nr_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    endc_nr_cell_id=$(fibocom_hex_to_dec "$endc_nr_cell_id")
                    endc_nr_arfcn=$(echo "$response" | awk -F',' '{print $7}')
                    endc_nr_arfcn=$(fibocom_hex_to_dec "$endc_nr_arfcn")
                    endc_nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    endc_nr_physical_cell_id=$(fibocom_hex_to_dec "$endc_nr_physical_cell_id")
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
                    lte_tac=$(fibocom_hex_to_dec "$lte_tac")
                    lte_cell_id=$(echo "$response" | awk -F',' '{print $6}')
                    lte_cell_id=$(fibocom_hex_to_dec "$lte_cell_id")
                    lte_earfcn=$(echo "$response" | awk -F',' '{print $7}')
                    lte_earfcn=$(fibocom_hex_to_dec "$lte_earfcn")
                    lte_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                    lte_physical_cell_id=$(fibocom_hex_to_dec "$lte_physical_cell_id")
                    lte_band_num=$(echo "$response" | awk -F',' '{print $9}')
                    lte_band=$(get_band "LTE" ${lte_band_num})
                    ul_bandwidth_num=$(echo "$response" | awk -F',' '{print $10}')
                    lte_ul_bandwidth=$(get_bandwidth "LTE" ${ul_bandwidth_num})
                    lte_dl_bandwidth="$lte_ul_bandwidth"
                    lte_rssnr=$(echo "$response" | grep "," | head -n1 | awk -F',' '{print $11}')
                    lte_rxlev_num=$(echo "$response" | awk -F',' '{print $12}')
                    lte_rxlev=$(get_rxlev "LTE" ${lte_rxlev_num})
                    lte_rsrp_num=$(echo "$response" | awk -F',' '{print $13}')
                    lte_rsrp=$(get_rsrp "LTE" ${lte_rsrp_num})
                    lte_rsrq_num=$(echo "$response" | awk -F',' '{print $14}' | sed 's/\r//g')
                    lte_rsrq=$(get_rsrq "LTE" ${lte_rsrq_num})
                    lte_rssi="$rssi_actual"
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
            [[ "$platform" = "mediatek" ]] && {
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
    "NR5G-SA Mode"*)
        # Use helper function for 5G
        extra_info="NR5G-SA"
        set_5g_cell_info "$nr_mcc" "$nr_mnc" "$nr_tac" "$nr_cell_id" "$nr_arfcn" \
            "$nr_physical_cell_id" "$nr_band" "${nr_ul_bandwidth}M" "${nr_dl_bandwidth}M" \
            "$nr_rsrp" "$nr_rsrq" "$nr_sinr" "" "$nr_rxlev"
        add_plain_info_entry "SCS" "$nr_scs" "SCS"
        add_plain_info_entry "Srxlev" "$nr_srxlev" "Serving Cell Receive Level"
        # Add CA info if present
        if [ $ca_count -gt 1 ]; then
            add_ca_info "5G" "$scc_arfcn" "$scc_pci" "$scc_band" "${scc_ul_bandwidth}M" "${scc_dl_bandwidth}M"
            [ -n "$scc_ul_bandwidth" ] && add_plain_info_entry "UL CA" "Yes" "UL CA"
        fi
        ;;
    "EN-DC Mode"*)
        # LTE part
        add_plain_info_entry "LTE" "LTE" ""
        extra_info="LTE"
        set_4g_cell_info "$endc_lte_mcc" "$endc_lte_mnc" "$endc_lte_tac" "$endc_lte_cell_id" \
            "$endc_lte_earfcn" "$endc_lte_physical_cell_id" "$endc_lte_band" \
            "${endc_lte_ul_bandwidth}M" "${endc_lte_dl_bandwidth}M" "$endc_lte_rsrp" "$endc_lte_rsrq" \
            "" "$endc_lte_rssnr" "$endc_lte_rxlev"
        add_plain_info_entry "CQI" "$endc_lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$endc_lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$endc_lte_srxlev" "Serving Cell Receive Level"
        # NR5G-NSA part
        add_plain_info_entry "NR5G-NSA" "NR5G-NSA" ""
        extra_info="NR5G-NSA"
        set_5g_cell_info "$endc_nr_mcc" "$endc_nr_mnc" "$endc_nr_tac" "$endc_nr_cell_id" \
            "$endc_nr_arfcn" "$endc_nr_physical_cell_id" "$endc_nr_band" "" "${endc_nr_dl_bandwidth}M" \
            "$endc_nr_rsrp" "$endc_nr_rsrq" "$endc_nr_sinr" "" "$endc_nr_rxlev"
        add_plain_info_entry "SCS" "$endc_nr_scs" "SCS"
        ;;
    "LTE Mode"*)
        extra_info="LTE"
        set_4g_cell_info "$lte_mcc" "$lte_mnc" "$lte_tac" "$lte_cell_id" "$lte_earfcn" \
            "$lte_physical_cell_id" "$lte_band" "${lte_ul_bandwidth}M" "${lte_dl_bandwidth}M" \
            "$lte_rsrp" "$lte_rsrq" "" "$lte_rssnr" "$lte_rxlev"
        add_bar_info_entry "RSSI" "$lte_rssi" "Received Signal Strength Indicator" -120 -20 dBm
        add_plain_info_entry "CQI" "$lte_cql" "Channel Quality Indicator"
        add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power"
        add_plain_info_entry "Srxlev" "$lte_srxlev" "Serving Cell Receive Level"
        ;;
    "WCDMA Mode")
        extra_info="WCDMA"
        set_3g_cell_info "$wcdma_mcc" "$wcdma_mnc" "$wcdma_lac" "$wcdma_cell_id" \
            "$wcdma_uarfcn" "$wcdma_psc" "$wcdma_band" "" "" "$wcdma_rscp" "" "$wcdma_ecio" \
            "$wcdma_rxlev" "$wcdma_rac"
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
    local response ca_response rat network_mode status line

    response=$(at "$at_port" 'AT+GTCCINFO?')
    ca_response=$(at "$at_port" 'AT+GTCAINFO?')
    rat=$(echo "$response" | grep "service" | awk -F' ' '{print $1}' | head -n 1)

    [ -z "$rat" ] && {
        local rat_num
        rat_num=$(at "$at_port" 'AT+COPS?' | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        rat=$(get_rat "$rat_num")
    }

    case "$rat" in
        "NR")
            network_mode="NR5G-SA"
            ;;
        "LTE-NR")
            network_mode="EN-DC"
            ;;
        "LTE"|"eMTC"|"NB-IoT")
            network_mode="LTE"
            ;;
        "WCDMA"|"UMTS")
            network_mode="WCDMA"
            ;;
        *)
            network_mode="$rat"
            status="not_registered"
            ;;
    esac
    [ -z "$status" ] && status="ok"

    json_add_object "current_band"
    json_add_string "status" "$status"
    json_add_string "vendor" "$_Vendor"
    json_add_string "network_mode" "$network_mode"
    json_add_array "cells"

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [[ "$line" = *","* ]] || continue

        case "$rat" in
            "NR")
                qmodem_add_current_band_cell "pcc" "NR" \
                    "$(get_band "NR" "$(echo "$line" | awk -F',' '{print $9}')")" \
                    "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $7}')")" \
                    "NR-ARFCN" \
                    "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $8}')")" \
                    "$(get_bandwidth "NR" "$(echo "$ca_response" | grep "PCC" | awk -F',' '{print $5}' | head -n 1)")" \
                    "$(get_bandwidth "NR" "$(echo "$ca_response" | grep "PCC" | awk -F',' '{print $4}' | head -n 1)")" \
                    ""
                ;;
            "LTE-NR")
                case "$(echo "$line" | awk -F',' '{print $2}')" in
                    "4")
                        qmodem_add_current_band_cell "pcc" "LTE" \
                            "$(get_band "LTE" "$(echo "$line" | awk -F',' '{print $9}')")" \
                            "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $7}')")" \
                            "EARFCN" \
                            "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $8}')")" \
                            "$(get_bandwidth "LTE" "$(echo "$line" | awk -F',' '{print $10}')")" \
                            "$(get_bandwidth "LTE" "$(echo "$line" | awk -F',' '{print $10}')")" \
                            ""
                        ;;
                    "9")
                        qmodem_add_current_band_cell "nsa" "NR" \
                            "$(get_band "NR" "$(echo "$line" | awk -F',' '{print $9}')")" \
                            "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $7}')")" \
                            "NR-ARFCN" \
                            "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $8}')")" \
                            "" \
                            "$(get_bandwidth "NR" "$(echo "$line" | awk -F',' '{print $10}')")" \
                            ""
                        ;;
                esac
                continue
                ;;
            "LTE"|"eMTC"|"NB-IoT")
                qmodem_add_current_band_cell "pcc" "LTE" \
                    "$(get_band "LTE" "$(echo "$line" | awk -F',' '{print $9}')")" \
                    "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $7}')")" \
                    "EARFCN" \
                    "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $8}')")" \
                    "$(get_bandwidth "LTE" "$(echo "$line" | awk -F',' '{print $10}')")" \
                    "$(get_bandwidth "LTE" "$(echo "$line" | awk -F',' '{print $10}')")" \
                    ""
                ;;
            "WCDMA"|"UMTS")
                qmodem_add_current_band_cell "pcc" "WCDMA" \
                    "$(get_band "WCDMA" "$(echo "$line" | awk -F',' '{print $9}')")" \
                    "$(echo "$line" | awk -F',' '{print $7}')" \
                    "UARFCN" \
                    "$(echo "$line" | awk -F',' '{print $8}')" \
                    "" \
                    "" \
                    ""
                ;;
        esac

        break
    done <<EOF
$(echo "$response")
EOF

    case "$rat" in
        "NR"|"LTE-NR")
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                echo "$line" | grep -q "SCC" || continue

                qmodem_add_current_band_cell "scc" "NR" \
                    "$(get_band "NR" "$(echo "$line" | awk -F',' '{print $3}')")" \
                    "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $5}')")" \
                    "NR-ARFCN" \
                    "$(fibocom_hex_to_dec "$(echo "$line" | awk -F',' '{print $4}')")" \
                    "" \
                    "$(get_bandwidth "NR" "$(echo "$line" | awk -F',' '{print $6}')")" \
                    ""
            done <<EOF
$(echo "$ca_response")
EOF
            ;;
    esac

    json_close_array
    json_close_object
}

get_current_band_capabilities()
{
    json_add_object "current_band_capabilities"
    json_add_boolean "supported" 1
    json_add_string "vendor" "$_Vendor"
    json_add_string "method" "AT+GTCCINFO?"
    json_add_string "schema" "current_band"
    json_close_object
}

# get sim switch capabilities
sim_switch_capabilities(){
    case $platform in
        "qualcomm") sim_switch="1" ;;
        "mediatek") sim_switch="1" ;;
        *) sim_switch="0" ;;
    esac
    json_add_string "supportSwitch" "$sim_switch"
    json_add_array "simSlots"
    json_add_string "" "0"
    json_add_string "" "1"
    json_close_array
}

get_sim_slot(){
    local at_command="AT+GTDUALSIM?"
	local expect_response="+GTDUALSIM"
    response=$(at $at_port $at_command |grep $expect_response)
    case $platform in
        "qualcomm")
            sim_slot=$(echo "$response" | awk -F': ' '{print $2}' | awk -F',' '{print $1}' | tr -d '\r')
            ;;
        "mediatek")
            sim_slot=$(echo "$response" | awk -F': ' '{print $2}' | awk -F',' '{print $1}' | xargs)
            ;;
        *)
            sim_slot="unknown"
            ;;
    esac
    json_add_string "sim_slot" "$sim_slot"
}

set_sim_slot(){
    local sim_slot_param=$1
    local at_command="AT+GTDUALSIM=$sim_slot_param"
    response=$(at $at_port $at_command)
    json_add_string "result" "$response"
}

fibocom_usage_to_bytes()
{
    local value="$1"
    local unit="$2"

    case "$value" in
        ''|*[!0-9.]*)
            echo 0
            return
            ;;
    esac

    case "$unit" in
        0) multiplier=1 ;;
        1) multiplier=1024 ;;
        2) multiplier=1048576 ;;
        3) multiplier=1073741824 ;;
        4) multiplier=1099511627776 ;;
        *) multiplier=1 ;;
    esac

    awk -v value="$value" -v multiplier="$multiplier" 'BEGIN { printf "%.0f", value * multiplier }'
}

fibocom_get_netdev_usage_stats()
{
    local netdev rx_bytes tx_bytes updated_at

    netdev=$(uci -q get "qmodem.${config_section}.network")
    [ -z "$netdev" ] && [ -n "$modem_path" ] && netdev=$(ls "$(find "$modem_path" -name net 2>/dev/null | tail -n1)" 2>/dev/null | head -n1)
    [ -z "$netdev" ] && return 1

    rx_bytes=$(cat "/sys/class/net/${netdev}/statistics/rx_bytes" 2>/dev/null)
    tx_bytes=$(cat "/sys/class/net/${netdev}/statistics/tx_bytes" 2>/dev/null)

    case "$rx_bytes" in ''|*[!0-9]*) rx_bytes=0 ;; esac
    case "$tx_bytes" in ''|*[!0-9]*) tx_bytes=0 ;; esac

    [ "$rx_bytes" = "0" ] && [ "$tx_bytes" = "0" ] && return 1

    updated_at=$(date +%s)
    json_add_boolean "available" 1
    json_add_int "updated_at" "$updated_at"
    json_add_int "total_rx_bytes" "$rx_bytes"
    json_add_int "total_tx_bytes" "$tx_bytes"
    json_add_string "source" "netdev"
    json_add_string "netdev" "$netdev"
    return 0
}

get_usage_stats()
{
    local response usage_value usage_unit total_bytes updated_at

    response=$(at "$at_port" "AT+GTUSAGEREC?")
    usage_value=$(echo "$response" | awk -F'[:, ]+' '/\+GTUSAGEREC:/ {gsub(/\r/, "", $2); print $2; exit}')
    usage_unit=$(echo "$response" | awk -F'[:, ]+' '/\+GTUSAGEREC:/ {gsub(/\r/, "", $3); print $3; exit}')
    total_bytes=$(fibocom_usage_to_bytes "$usage_value" "$usage_unit")

    if echo "$response" | grep -q "+GTUSAGEREC:"; then
        updated_at=$(date +%s)
        json_add_boolean "available" 1
        json_add_int "updated_at" "$updated_at"
        json_add_int "total_rx_bytes" "$total_bytes"
        json_add_int "total_tx_bytes" 0
        json_add_string "total_bytes" "$total_bytes"
        json_add_string "raw_value" "$usage_value"
        json_add_string "raw_unit" "$usage_unit"
        json_add_string "source" "modem"
    else
        fibocom_get_netdev_usage_stats && return
        json_add_boolean "available" 0
        json_add_int "updated_at" 0
        json_add_int "total_rx_bytes" 0
        json_add_int "total_tx_bytes" 0
        json_add_string "error" "$response"
    fi
}

write_usage_stats()
{
    local response

    response=$(at "$at_port" "AT+GTUSAGEREC")
    echo "$response" | grep -qi "OK"
}

clear_usage_stats()
{
    local response

    response=$(at "$at_port" "AT+GTUSAGEREC")
    if echo "$response" | grep -qi "OK"; then
        json_add_boolean "result" 1
    else
        json_add_boolean "result" 0
    fi
}
