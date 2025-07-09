#!/bin/sh
# Copyright (C) 2025 sfwtw <sfwtw@qq.com>
_Vendor="telit"
_Author="sfwtw"
_Maintainer="sfwtw <sfwtw@qq.com>"
source /usr/share/qmodem/generic.sh
debug_subject="telit_ctrl"

vendor_get_disabled_features()
{
    json_add_string "" "IMEI"
    json_add_string "" "NeighborCell"
}

get_mode()
{
    at_command='AT#USBCFG?'
    local mode_num=$(at ${at_port} ${at_command} | grep -o "#USBCFG:" | awk -F': ' '{print $2}')
    case "$mode_num" in
        "0") mode="rndis" ;;
        "1") mode="qmi" ;;
        "2") mode="mbim" ;;
        "3") mode="ecm" ;;
        *) mode="${mode_num}" ;;
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

set_mode()
{
    local mode=$1
    case $mode in
        "rndis") mode="0" ;;
        "qmi") mode="1" ;;
        "mbim") mode="2" ;;
        "ecm") mode="3" ;;
        *) echo "Invalid mode" && return 1;;
    esac
    at_command='AT#USBCFG='${mode}
    res=$(at "${at_port}" "${at_command}")
    json_select "result"
    json_add_string "set_mode" "$res"
    json_close_object
}

get_network_prefer()
{
    at_command='AT+WS46?'
    local response=$(at ${at_port} ${at_command} | grep "+WS46:" | awk -F': ' '{print $2}' | sed 's/\r//g')
    
    network_prefer_3g="0";
    network_prefer_4g="0";
    network_prefer_5g="0";

    #匹配不同的网络类型
    local auto=$(echo "${response}" | grep "38")
    if [ -n "$auto" ]; then
        network_prefer_3g="1"
        network_prefer_4g="1"
        network_prefer_5g="1"
    else
        local wcdma=$(echo "${response}" | grep "22" || echo "${response}" | grep "31" || echo "${response}" | grep "38" || echo "${response}" | grep "40")
        local lte=$(echo "${response}" | grep "28" || echo "${response}" | grep "31" || echo "${response}" | grep "37" || echo "${response}" | grep "38")
        local nr=$(echo "${response}" | grep "36" || echo "${response}" | grep "37" || echo "${response}" | grep "38" || echo "${response}" | grep "40")
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
    json_add_object network_prefer
    json_add_string 3G $network_prefer_3g
    json_add_string 4G $network_prefer_4g
    json_add_string 5G $network_prefer_5g
    json_close_object
}

set_network_prefer()
{
    network_prefer_3g=$(echo $1 |jq -r 'contains(["3G"])')
    network_prefer_4g=$(echo $1 |jq -r 'contains(["4G"])')
    network_prefer_5g=$(echo $1 |jq -r 'contains(["5G"])')
    length=$(echo $1 |jq -r 'length')

    case "$length" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                network_prefer_config="22"
            elif [ "$network_prefer_4g" = "true" ]; then
                network_prefer_config="28"
            elif [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="36"
            fi
        ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                network_prefer_config="31"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="40"
            elif [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                network_prefer_config="37"
            fi
        ;;
        "3") network_prefer_config="38" ;;
        *) network_prefer_config="38" ;;
    esac

    at_command='AT+WS46='${network_prefer_config}
    at "${at_port}" "${at_command}"
}

get_voltage()
{
    at_command="AT#CBC"
    local voltage=$(at ${at_port} ${at_command} | grep "#CBC:" | awk -F',' '{print $2}' | sed 's/\r//g')
    [ -n "$voltage" ] && {
        voltage=$(awk "BEGIN {printf \"%.2f\", $voltage / 100}")
        add_plain_info_entry "voltage" "$voltage V" "Voltage" 
    }
}

get_temperature()
{   
    at_command="AT#TEMPSENS=2"
    local temp
    QTEMP=$(at ${at_port} ${at_command} | grep "#TEMPSENS: TSENS,")
    temp=$(echo $QTEMP | awk -F',' '{print $2}' | sed 's/\r//g')
    if [ -n "$temp" ]; then
        temp="${temp}$(printf "\xc2\xb0")C"
    fi
    add_plain_info_entry "temperature" "$temp" "Temperature"
}

base_info()
{
    m_debug  "Telit base info"

    #Name（名称）
    at_command="AT+CGMM"
    name=$(at $at_port $at_command | sed -n '3p' | sed 's/\r//g')
    #Manufacturer（制造商）
    at_command="AT+CGMI"
    manufacturer=$(at $at_port $at_command | sed -n '3p' | sed 's/\r//g')
    #Revision（固件版本）
    at_command="AT+CGMR"
    revision=$(at $at_port $at_command | sed -n '3p' | sed 's/\r//g')
    class="Base Information"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_temperature
    get_voltage
    get_connect_status
}

sim_info()
{
    m_debug  "Telit sim info"
    
    #SIM Slot（SIM卡卡槽）
    at_command="AT#QSS?"
    sim_slot=$(at $at_port $at_command | grep "#QSS:" | awk -F',' '{print $3}' | sed 's/\r//g')
    if [ "$sim_slot" = "0" ]; then
        sim_slot="1"
    elif [ "$sim_slot" = "1" ]; then
        sim_slot="2"
    fi
    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN"
    imei=$(at $at_port $at_command | sed -n '3p' | sed 's/\r//g')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
    sim_status_flag=$(at $at_port $at_command | sed -n '3p')
    sim_status=$(get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #ISP（互联网服务提供商）
    at_command="AT+COPS?"
    isp=$(at $at_port $at_command | sed -n '3p' | awk -F'"' '{print $2}')
    # if [ "$isp" = "CHN-CMCC" ] || [ "$isp" = "CMCC" ]|| [ "$isp" = "46000" ]; then
    #     isp="中国移动"
    # # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "UNICOM" ] || [ "$isp" = "46001" ]; then
    # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "CUCC" ] || [ "$isp" = "46001" ]; then
    #     isp="中国联通"
    # # elif [ "$isp" = "CHN-CT" ] || [ "$isp" = "CT" ] || [ "$isp" = "46011" ]; then
    # elif [ "$isp" = "CHN-TELECOM" ] || [ "$isp" = "CTCC" ] || [ "$isp" = "46011" ]; then
    #     isp="中国电信"
    # fi

    #IMSI（国际移动用户识别码）
    at_command="AT+CIMI"
    imsi=$(at $at_port $at_command | sed -n '3p' | sed 's/\r//g')

    #ICCID（集成电路卡识别码）
    at_command="AT+ICCID"
    iccid=$(at $at_port $at_command | grep -o "+ICCID:[ ]*[-0-9]\+" | grep -o "[-0-9]\{1,4\}")
    class="SIM Information"
    case "$sim_status" in
        "ready")
            add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
            add_plain_info_entry "ISP" "$isp" "Internet Service Provider"
            add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"
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

network_info()
{
    m_debug  "Telit network info"

    at_command="AT#CAMETRICS=1;#CAMETRICS?"
    network_type=$(at ${at_port} ${at_command} | grep "#CAMETRICS:" | awk -F',' '{print $3}')

    at_command="AT#CQI"
    response=$(at ${at_port} ${at_command} | grep "#CQI:" | sed 's/#CQI: //g' | sed 's/\r//g')

    if [ -n "$response" ]; then
        cqi=$(echo "$response" | cut -d',' -f1)
        second_value=$(echo "$response" | cut -d',' -f2)
        [ "$cqi" = "31" ] && cqi="$second_value"
    fi

    class="Network Information"
    add_plain_info_entry "Network Type" "$network_type" "Network Type"
    add_plain_info_entry "CQI DL" "$cqi" "Channel Quality Indicator for Downlink"
}

lte_hex_to_bands() {
    local hex_value="$1"
    local result=""
    hex_value=$(echo "$hex_value" | tr 'a-z' 'A-Z')
    local decimal=$(echo "ibase=16; $hex_value" | bc)
    local i=1
    while [ "$decimal" != "0" ]; do
        local bit=$(echo "$decimal % 2" | bc)
        if [ "$bit" -eq 1 ]; then
            result="$result B$i"
        fi
        decimal=$(echo "$decimal / 2" | bc)
        i=$(expr $i + 1)
    done
    result=$(echo "$result" | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')
    echo "$result"
}

lte_bands_to_hex() {
    local bands="$1"
    local decimal_value=0
    for band in $bands; do
        local band_num=$(echo "$band" | sed 's/^B//')
        local bit_value=$(echo "2^($band_num-1)" | bc)
        decimal_value=$(echo "$decimal_value + $bit_value" | bc)
    done
    local hex_value=$(echo "obase=16; $decimal_value" | bc)
    echo "$hex_value"
}

nr_hex_to_bands() {
    local hex_value="$1"
    local result=""
    hex_value=$(echo "$hex_value" | tr 'a-z' 'A-Z')
    local decimal=$(echo "ibase=16; $hex_value" | bc)
    local j=1
    [ "$2" = "65_128" ] && j=65
    while [ "$decimal" != "0" ]; do
        local bit=$(echo "$decimal % 2" | bc)
        if [ "$bit" -eq 1 ]; then
            result="$result N$j"
        fi
        decimal=$(echo "$decimal / 2" | bc)
        j=$(expr $j + 1)
    done
    result=$(echo "$result" | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//')
    echo "$result"
}

nr_bands_to_hex() {
    local bands="$1"
    local decimal_value=0
    local decimal_value_ext=0
    for band in $bands; do
        local band_num=$(echo "$band" | sed 's/^N//')
        if expr "$band_num" : '[0-9][0-9]*$' >/dev/null; then
            if [ $band_num -lt 65 ]; then
                local bit_value=$(echo "2^($band_num-1)" | bc)
                decimal_value=$(echo "$decimal_value + $bit_value" | bc)
            else
                local bit_value=$(echo "2^($band_num-65)" | bc)
                decimal_value_ext=$(echo "$decimal_value_ext + $bit_value" | bc)
            fi
        fi
    done
    local hex_value=$(echo "obase=16; $decimal_value" | bc)
    if [ "$decimal_value_ext" != "0" ]; then
        local hex_value_ext=$(echo "obase=16; $decimal_value_ext" | bc)
        echo "${hex_value_ext}"
    else
        echo "$hex_value"
    fi
}

get_lockband()
{
    json_add_object "lockband"
    m_debug "Telit get lockband info"
    get_lockband_config_command="AT#BND?"
    get_available_band_command="AT#BND=?"
    get_lockband_config_res=$(at $at_port $get_lockband_config_command)
    get_available_band_res=$(at $at_port $get_available_band_command)
    json_add_object "LTE"
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
    json_add_object "NR"
    json_add_array "available_band"
    json_close_array
    json_add_array "lock_band"
    json_close_array
    json_close_object
    lte_avalible_band=$(echo $get_available_band_res | grep -o "#BND: ([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*)" | sed 's/#BND: (\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\))/\3/')
    lte_avalible_band=$(lte_hex_to_bands "$lte_avalible_band")
    nsa_nr_avalible_band_1_64=$(echo $get_available_band_res | grep -o "#BND: ([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*)" | sed 's/#BND: (\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\))/\5/')
    nsa_nr_avalible_band_65_128=$(echo $get_available_band_res | grep -o "#BND: ([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*)" | sed 's/#BND: (\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\))/\6/')
    nsa_nr_avalible_band="$(nr_hex_to_bands "$nsa_nr_avalible_band_1_64" "1_64") $(nr_hex_to_bands "$nsa_nr_avalible_band_65_128" "65_128")"
    sa_nr_avalible_band_1_64=$(echo $get_available_band_res | grep -o "#BND: ([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*)" | sed 's/#BND: (\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\))/\7/')
    sa_nr_avalible_band_65_128=$(echo $get_available_band_res | grep -o "#BND: ([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*),([^)]*)" | sed 's/#BND: (\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\)),(\([^)]*\))/\8/')
    sa_nr_avalible_band="$(nr_hex_to_bands "$sa_nr_avalible_band_1_64" "1_64") $(nr_hex_to_bands "$sa_nr_avalible_band_65_128" "65_128")"
    for i in $(echo "$lte_avalible_band" | awk -F" " '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "LTE"
        json_select "available_band"
        add_avalible_band_entry  "$i" "$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$nsa_nr_avalible_band" | awk -F" " '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "NR_NSA"
        json_select "available_band"
        add_avalible_band_entry  "$i" "$i"
        json_select ..
        json_select ..
    done
    for i in $(echo "$sa_nr_avalible_band" | awk -F" " '{for(j=1; j<=NF; j++) print $j}'); do
        json_select "NR"
        json_select "available_band"
        add_avalible_band_entry  "$i" "$i"
        json_select ..
        json_select ..
    done

    lte_band=$(echo $get_lockband_config_res | awk -F "," '{print $3}')
    lte_band=$(lte_hex_to_bands "$lte_band")
    nsa_nr_band_1_64=$(echo $get_lockband_config_res | awk -F "," '{print $5}')
    nsa_nr_band_65_128=$(echo $get_lockband_config_res | awk -F "," '{print $6}')
    nsa_nr_band="$(nr_hex_to_bands "$nsa_nr_band_1_64" "1_64") $(nr_hex_to_bands "$nsa_nr_band_65_128" "65_128")"
    sa_nr_band_1_64=$(echo $get_lockband_config_res | awk -F "," '{print $7}')
    sa_nr_band_65_128=$(echo $get_lockband_config_res | awk -F "," '{print $8}' | sed 's/\r//g' | sed 's/ OK//g')
    sa_nr_band="$(nr_hex_to_bands "$sa_nr_band_1_64" "1_64") $(nr_hex_to_bands "$sa_nr_band_65_128" "65_128")"
    for i in $(echo "$lte_band" | cut -d, -f2|tr -d '\r' | awk -F" " '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "LTE"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$nsa_nr_band" | cut -d, -f2|tr -d '\r' | awk -F" " '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "NR_NSA"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    for i in $(echo "$sa_nr_band" | cut -d, -f2|tr -d '\r' | awk -F" " '{for(j=1; j<=NF; j++) print $j}'); do
        if [ -n "$i" ]; then
            json_select "NR"
            json_select "lock_band"
            json_add_string "" "$i"
            json_select ..
            json_select ..
        fi
    done
    json_close_array
    json_close_object
}

set_lockband()
{
    m_debug  "telit set lockband info"
    config=$1
    #{"band_class":"NR","lock_band":"41,78,79"}
    band_class=$(echo $config | jq -r '.band_class')
    lock_band=$(echo $config | jq -r '.lock_band')
    lock_band=$(echo $lock_band | tr ',' ' ')
    case "$band_class" in
        "LTE") 
            lock_band=$(lte_bands_to_hex "$lock_band")
            at_command="AT#BND=0,22,$lock_band"
            res=$(at $at_port $at_command)
            ;;
        "NR_NSA")
            orig=$(at $at_port "AT#BND?")
            orig_lte=$(echo $orig | awk -F "," '{print $3}')
            orig_lte_ext=$(echo $orig | awk -F "," '{print $4}')

            nr_bands_1_64=""
            nr_bands_65_128=""
            for band in $lock_band; do
                band_num=$(echo "$band" | sed 's/^N//')
                if [ "$band_num" -lt 65 ]; then
                    nr_bands_1_64="$nr_bands_1_64 N$band_num"
                else
                    nr_bands_65_128="$nr_bands_65_128 N$band_num"
                fi
            done

            nsa_nr_1_64=$(nr_bands_to_hex "$nr_bands_1_64" | cut -d',' -f1)
            nsa_nr_65_128=$(nr_bands_to_hex "$nr_bands_65_128" | cut -d',' -f2)

            [ -z "$nsa_nr_1_64" ] && nsa_nr_1_64=$orig_nsa_nr_1_64
            [ -z "$nsa_nr_65_128" ] && nsa_nr_65_128=$orig_nsa_nr_65_128
            
            at_command="AT#BND=0,22,$orig_lte,$orig_lte_ext,$nsa_nr_1_64,$nsa_nr_65_128"
            res=$(at $at_port $at_command)
            ;;
        "NR")
            orig=$(at $at_port "AT#BND?")
            orig_lte=$(echo $orig | awk -F "," '{print $3}')
            orig_lte_ext=$(echo $orig | awk -F "," '{print $4}')
            orig_nsa_nr_1_64=$(echo $orig | awk -F "," '{print $5}')
            orig_nsa_nr_65_128=$(echo $orig | awk -F "," '{print $6}')
            orig_sa_nr_1_64=$(echo $orig | awk -F "," '{print $7}')
            orig_sa_nr_65_128=$(echo $orig | awk -F "," '{print $8}' | sed 's/\r//g' | sed 's/ OK//g')
            nr_bands_1_64=""
            nr_bands_65_128=""
            for band in $lock_band; do
                band_num=$(echo "$band" | sed 's/^N//')
                if [ "$band_num" -lt 65 ]; then
                    nr_bands_1_64="$nr_bands_1_64 N$band_num"
                else
                    nr_bands_65_128="$nr_bands_65_128 N$band_num"
                fi
            done

            nr_1_64=$(nr_bands_to_hex "$nr_bands_1_64")
            nr_65_128=$(nr_bands_to_hex "$nr_bands_65_128")

            [ -z "$nr_1_64" ] && nr_1_64=$orig_sa_nr_1_64
            [ -z "$nr_65_128" ] && nr_65_128=$orig_sa_nr_65_128
            at_command="AT#BND=0,22,$orig_lte,$orig_lte_ext,$orig_nsa_nr_1_64,$orig_nsa_nr_65_128,$nr_1_64,$nr_65_128"
            res=$(at $at_port $at_command)
            ;;
    esac
    json_select "result"
    json_add_string "set_lockband" "$res"
    json_add_string "config" "$config"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$lock_band"
    json_close_object
}

calc_average() {
    local values="$1"
    local sum=0
    local count=0
    
    for val in $values; do
        if [ -n "$val" ] && [ "$val" != "NA" ]; then
            sum=$(echo "$sum + $val" | bc -l)
            count=$((count + 1))
        fi
    done
    
    if [ $count -gt 0 ]; then
        printf "%.1f" $(echo "$sum / $count" | bc -l)
    else
        echo "NA"
    fi
}

convert_band_number() {
    local band_num=$1
    case "$band_num" in
        120) echo "B1" ;;
        121) echo "B2" ;;
        122) echo "B3" ;;
        123) echo "B4" ;;
        124) echo "B5" ;;
        125) echo "B6" ;;
        126) echo "B7" ;;
        127) echo "B8" ;;
        128) echo "B9" ;;
        129) echo "B10" ;;
        130) echo "B11" ;;
        131) echo "B12" ;;
        132) echo "B13" ;;
        133) echo "B14" ;;
        134) echo "B17" ;;
        135) echo "B33" ;;
        136) echo "B34" ;;
        137) echo "B35" ;;
        138) echo "B36" ;;
        139) echo "B37" ;;
        140) echo "B38" ;;
        141) echo "B39" ;;
        142) echo "B40" ;;
        143) echo "B18" ;;
        144) echo "B19" ;;
        145) echo "B20" ;;
        146) echo "B21" ;;
        147) echo "B24" ;;
        148) echo "B25" ;;
        149) echo "B41" ;;
        150) echo "B42" ;;
        151) echo "B43" ;;
        152) echo "B23" ;;
        153) echo "B26" ;;
        154) echo "B32" ;;
        155) echo "B125" ;;
        156) echo "B126" ;;
        157) echo "B127" ;;
        158) echo "B28" ;;
        159) echo "B29" ;;
        160) echo "B30" ;;
        161) echo "B66" ;;
        162) echo "B250" ;;
        163) echo "B46" ;;
        166) echo "B71" ;;
        167) echo "B47" ;;
        168) echo "B48" ;;
        250) echo "N1" ;;
        251) echo "N2" ;;
        252) echo "N3" ;;
        253) echo "N5" ;;
        254) echo "N7" ;;
        255) echo "N8" ;;
        256) echo "N20" ;;
        257) echo "N28" ;;
        258) echo "N38" ;;
        259) echo "N41" ;;
        260) echo "N50" ;;
        261) echo "N51" ;;
        262) echo "N66" ;;
        263) echo "N70" ;;
        264) echo "N71" ;;
        265) echo "N74" ;;
        266) echo "N75" ;;
        267) echo "N76" ;;
        268) echo "N77" ;;
        269) echo "N78" ;;
        270) echo "N79" ;;
        271) echo "N80" ;;
        272) echo "N81" ;;
        273) echo "N82" ;;
        274) echo "N83" ;;
        275) echo "N84" ;;
        276) echo "N85" ;;
        277) echo "N257" ;;
        278) echo "N258" ;;
        279) echo "N259" ;;
        280) echo "N260" ;;
        281) echo "N261" ;;
        282) echo "N12" ;;
        283) echo "N25" ;;
        284) echo "N34" ;;
        285) echo "N39" ;;
        286) echo "N40" ;;
        287) echo "N65" ;;
        288) echo "N86" ;;
        289) echo "N48" ;;
        290) echo "N14" ;;
        291) echo "N13" ;;
        292) echo "N18" ;;
        293) echo "N26" ;;
        294) echo "N30" ;;
        295) echo "N29" ;;
        296) echo "N53" ;;
        *) echo "$band_num" ;;
    esac
}

cell_info()
{
    m_debug  "Telit cell info"

    at_command="AT#CAINFOEXT?"
    ca_response=$(at ${at_port} ${at_command})

    info_line=$(echo "$ca_response" | grep -o "#CAINFOEXT: [^$]*" | head -1)
    ca_count=$(echo "$info_line" | awk -F',' '{print $1}' | awk -F': ' '{print $2}')
    network_type_raw=$(echo "$info_line" | awk -F',' '{print $2}')
    network_mode=$(echo "$network_type_raw" | tr -d ' ')

    [ "$ca_count" -gt 1 ] && network_mode="$network_mode with $ca_count CA"
    pcc_line=$(echo "$ca_response" | grep "PCC-")
    band_number=$(echo "$pcc_line" | grep -o "BandClass: [^,]*" | awk -F': ' '{print $2}')
    band=$(convert_band_number "$band_number")
    bw=$(echo "$pcc_line" | grep -o "BW: [^,]*" | awk -F': ' '{print $2}')
    if [ -z "$bw" ]; then
        dl_bw_raw=$(echo "$pcc_line" | grep -o "DL_BW: [^,]*" | awk -F': ' '{print $2}')
        case "$dl_bw_raw" in
            "0") bw="1.4 MHz" ;;
            "1") bw="3 MHz" ;;
            "2") bw="5 MHz" ;;
            "3") bw="10 MHz" ;;
            "4") bw="15 MHz" ;;
            "5") bw="20 MHz" ;;
            *) bw="$dl_bw_raw" ;;
        esac
    fi
    arfcn=$(echo "$pcc_line" | grep -o "CH: [^,]*" | awk -F': ' '{print $2}')
    [ -z "$arfcn" ] && arfcn=$(echo "$pcc_line" | grep -o "RX_CH: [^,]*" | awk -F': ' '{print $2}')
    pci=$(echo "$pcc_line" | grep -o "PCI: [^,]*" | awk -F': ' '{print $2}')
    rsrp=$(echo "$pcc_line" | grep -o "RSRP: [^,]*" | awk -F': ' '{print $2}')
    rsrq=$(echo "$pcc_line" | grep -o "RSRQ: [^,]*" | awk -F': ' '{print $2}')
    rssi=$(echo "$pcc_line" | grep -o "RSSI: [^,]*" | awk -F': ' '{print $2}')
    sinr_raw=$(echo "$pcc_line" | grep -o "SINR: [^,]*" | awk -F': ' '{print $2}')
    sinr=$(printf "%.1f" $(echo "-20 + ($sinr_raw * 0.2)" | bc -l))
    tac=$(echo "$pcc_line" | grep -o "TAC: [^,]*" | awk -F': ' '{print $2}')
    tx_power=$(echo "$pcc_line" | grep -o "TX_PWR: [^,]*" | awk -F': ' '{print $2}')
    [ -n "$tx_power" ] && tx_power=$(printf "%.1f" $(echo "$tx_power / 10" | bc -l))
    [ -z "$tx_power" ] && tx_power="0"
    ul_mod=$(echo "$pcc_line" | grep -o "UL_MOD: [^,]*" | awk -F': ' '{print $2}')
    dl_mod=$(echo "$pcc_line" | grep -o "DL_MOD: [^,]*" | awk -F': ' '{print $2}' | sed 's/[^0-9]//g')
    case "$ul_mod" in
        "0") ul_mod="BPSK" ;;
        "1") ul_mod="QPSK" ;;
        "2") ul_mod="16QAM" ;;
        "3") ul_mod="64QAM" ;;
        "4") ul_mod="256QAM" ;;
        *) ul_mod="$ul_mod" ;;
    esac

    case "$dl_mod" in
        "0") dl_mod="BPSK" ;;
        "1") dl_mod="QPSK" ;;
        "2") dl_mod="16QAM" ;;
        "3") dl_mod="64QAM" ;;
        "4") dl_mod="256QAM" ;;
        *) dl_mod="$dl_mod" ;;
    esac

    if [ "$ca_count" -gt 1 ]; then
        scc_band=""
        scc_bw=""
        scc_arfcn=""
        scc_pci=""
        scc_rsrp=""
        scc_rssi=""
        scc_rsrq=""
        scc_sinr=""
        for i in $(seq 0 $((ca_count-2))); do
            scc_line=$(echo "$ca_response" | grep -A 1 "SCC$i-" | tr '\r\n' ' ')
            if [ -n "$scc_line" ]; then
                scc_band_number=$(echo "$scc_line" | grep -o "BandClass: [^,]*" | awk -F': ' '{print $2}')
                scc_band_new=$(convert_band_number "$scc_band_number")
                if [ -z "$scc_band" ]; then
                    scc_band="$scc_band_new"
                else
                    scc_band="$scc_band / $scc_band_new"
                fi
                scc_bw_new=$(echo "$scc_line" | grep -o "BW: [^,]*" | awk -F': ' '{print $2}')
                if [ -z "$scc_bw_new" ]; then
                    scc_dl_bw=$(echo "$scc_line" | grep -o "DL_BW: [^,]*" | awk -F': ' '{print $2}')
                    case "$scc_dl_bw" in
                        "0") scc_bw_new="1.4 MHz" ;;
                        "1") scc_bw_new="3 MHz" ;;
                        "2") scc_bw_new="5 MHz" ;;
                        "3") scc_bw_new="10 MHz" ;;
                        "4") scc_bw_new="15 MHz" ;;
                        "5") scc_bw_new="20 MHz" ;;
                        *) scc_bw_new="$scc_dl_bw" ;;
                    esac
                fi
                if [ -z "$scc_bw" ]; then
                    scc_bw="$scc_bw_new"
                else
                    scc_bw="$scc_bw / $scc_bw_new"
                fi
                scc_arfcn_new=$(echo "$scc_line" | grep -o "CH: [^,]*" | awk -F': ' '{print $2}')
                [ -z "$scc_arfcn_new" ] && scc_arfcn_new=$(echo "$scc_line" | grep -o "RX_CH: [^,]*" | awk -F': ' '{print $2}')
                if [ -z "$scc_arfcn" ]; then
                    scc_arfcn="$scc_arfcn_new"
                else
                    scc_arfcn="$scc_arfcn / $scc_arfcn_new"
                fi
                scc_pci_new=$(echo "$scc_line" | grep -o "PCI: [^,]*" | awk -F': ' '{print $2}')
                if [ -z "$scc_pci" ]; then
                    scc_pci="$scc_pci_new"
                else
                    scc_pci="$scc_pci / $scc_pci_new"
                fi
                scc_rsrp_new=$(echo "$scc_line" | grep -o "RSRP: [^,]*" | awk -F': ' '{print $2}')
                scc_rsrp="$scc_rsrp $scc_rsrp_new"
                scc_rssi_new=$(echo "$scc_line" | grep -o "RSSI: [^,]*" | awk -F': ' '{print $2}')
                scc_rssi="$scc_rssi $scc_rssi_new"
                scc_rsrq_new=$(echo "$scc_line" | grep -o "RSRQ: [^,]*" | awk -F': ' '{print $2}')
                scc_rsrq="$scc_rsrq $scc_rsrq_new"
                scc_sinr_raw=$(echo "$scc_line" | grep -o "SINR: [^,]*" | awk -F': ' '{print $2}')
                scc_sinr_new=$(printf "%.1f" $(echo "-20 + ($scc_sinr_raw * 0.2)" | bc -l))
                scc_sinr="$scc_sinr $scc_sinr_new"
            fi
        done
        arfcn="$arfcn / $scc_arfcn"
        band="$band / $scc_band"
        bw="$bw / $scc_bw"
        pci="$pci / $scc_pci"
        # rsrp=$(calc_average "$rsrp $scc_rsrp")
        # rssi=$(calc_average "$rssi $scc_rssi")
        # rsrq=$(calc_average "$rsrq $scc_rsrq")
        # sinr=$(calc_average "$sinr $scc_sinr")
    fi

    class="Cell Information"
    add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
    add_plain_info_entry "Band" "$band" "Band"
    add_plain_info_entry "Bandwidth" "$bw" "Bandwidth"
    add_plain_info_entry "ARFCN" "$arfcn" "Absolute Radio-Frequency Channel Number"
    add_plain_info_entry "Physical Cell ID" "$pci" "Physical Cell ID"
    add_plain_info_entry "TAC" "$tac" "Tracking Area Code"
    add_plain_info_entry "DL/UL MOD" "$dl_mod / $ul_mod" "DL/UL MOD"
    add_plain_info_entry "TX Power" "$tx_power" "TX Power"
    add_bar_info_entry "RSRP" "$rsrp" "Reference Signal Received Power" -140 -44 dBm
    add_bar_info_entry "RSRQ" "$rsrq" "Reference Signal Received Quality" -19.5 -3 dB
    add_bar_info_entry "RSSI" "$rssi" "Received Signal Strength Indicator" -120 -20 dBm
    add_bar_info_entry "SINR" "$sinr" "Signal to Interference plus Noise Ratio Bandwidth" 0 30 dB
}
