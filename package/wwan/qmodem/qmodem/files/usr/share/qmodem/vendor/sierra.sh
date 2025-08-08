#!/bin/sh
# Copyright (C) 2025 Fujr <fjrcn@outlook.com>
_Vendor="sierra"
_Author="Fujr"
_Maintainer="Fujr <fjrcn@outlook.com>"
source /usr/share/qmodem/generic.sh
debug_subject="quectel_ctrl"
function unlock_advance(){
    [ -z "$sierra_pass" ] && sierra_pass="A710"
    at $at_port "AT!ENTERCND=\"$sierra_pass\"" > /dev/null
}

function get_imei(){
    imei=$(at $at_port "AT+CGSN" | grep -o '[0-9]\{15\}')
    json_add_string imei $imei
}

function set_imei(){
    imei=$1
    at $at_port "AT+EGMR=1,7,\"$imei\""
}

function get_mode(){
    cfg=$(at $at_port "AT!USBCOMP?")
    config_type=`echo -e "$cfg" | grep -o 'Config Type:  [0-9]'`
    config_type=${config_type:14}
    interface_mask=`echo -e "$cfg" | grep -o 'Interface bitmask: [0-9a-fA-F]*'`
    interface_mask=${interface_mask:18}
    _mask_to_mode $interface_mask
    if [ "$mbim_port" = "1" ]; then
        mode="mbim"
    elif [ "$rmnet_port" = "1" ]; then
        mode="rmnet"
    fi
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

function set_mode(){
    local mode=$1
    case $mode in
        "mbim")
            interface_mask=0x00001009
            ;;
        "rmnet")
            interface_mask=0x00000109
            ;;
        *)
            echo "Invalid mode"
            return 1
            ;;
    esac
    at $at_port "AT!USBCOMP=1,4,$interface_mask"
}

function get_network_prefer(){
    res=$(at $at_port "at!SELRAT?"| grep -o "!SELRAT: [0-9A-Fa-f]*")
# (RAT index): 
# • 00 – Automatic 
# • 01 – UMTS 3G only 
# • 04 – LTE only 
# • 05 – 5G only 
# • 0E – UMTS and LTE only 
# • 0F – LTE and NR5G only 
# • 10 – WCDMA and NR5G only 
   code=${res:9}
    local network_prefer_3g="0"
    local network_prefer_4g="0"
    local network_prefer_5g="0"
   case $code in
        "00")
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        "01")
            network_prefer_3g="1"
            ;;
        "06")
            network_prefer_4g="1"
            ;;
        "20")
            network_prefer_5g="1"
            ;;
        "11")
            network_prefer_3g="1"
            network_prefer_4g="1"
            ;;
        "21")
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        "22")
            network_prefer_3g="1"
            network_prefer_5g="1"
            ;;
        *)
            network_prefer_3g="0"
            network_prefer_4g="0"
            network_prefer_5g="0"
            ;;
    esac
    json_add_object network_prefer
    json_add_string 3G $network_prefer_3g
    json_add_string 4G $network_prefer_4g
    json_add_string 5G $network_prefer_5g
    json_close_array
}

function set_network_prefer(){
    local network_prefer_3g=$(echo $1 |jq -r 'contains(["3G"])')
    local network_prefer_4g=$(echo $1 |jq -r 'contains(["4G"])')
    local network_prefer_5g=$(echo $1 |jq -r 'contains(["5G"])')
    count=$(echo $1 | jq -r 'length')
    case "$count" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                code="01"
            elif [ "$network_prefer_4g" = "true" ]; then
                code="06"
            elif [ "$network_prefer_5g" = "true" ]; then
                code="20"
            fi
            ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                code="11"
            elif [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                code="21"
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                code="22"
            fi
            ;;
        "3")
            code="00"
            ;;
        *)
            code="00"
            ;;
    esac
    res=$(at $at_port "AT!SELRAT=$code")
    json_add_string "code" "$code"
    json_add_string "result" "$res"
}

function get_lockband(){
    json_add_object "lockband"
    case $platform in
        "qualcomm")
            _get_lockband_nr
            ;;
        *)
            _get_lockband_nr
            ;;
    esac
    json_close_object
}

function set_lockband(){
    config=$1
    band_class=$(echo $config | jq -r '.band_class')
    lock_band=$(echo $config | jq -r '.lock_band')
    case $platform in
        "qualcomm")
            _set_lockband_nr
            ;;
        *)
            _set_lockband_nr
            ;;
    esac
}

function sim_info()
{
    class="SIM Information"
    
    at_command="AT!UIMS?"
	slot=$(at $at_port $at_command | grep -o '!UIMS: [0-9]*' | grep -o '[0-9]*')
    sim_slot=$(($slot+1))

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status=$(at $at_port $at_command | grep "+CPIN:")
    sim_status=${sim_status:7:-1}
    #lowercase
    sim_status=$(echo $sim_status | tr  A-Z a-z)
    add_plain_info_entry "SIM Status" "$sim_status" "SIM Status" 
    add_plain_info_entry "SIM Slot" "$sim_slot" "SIM Slot"
}

function base_info(){
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
    get_connect_status
    _get_temperature
    _get_voltage
}

function network_info() {
    class="Network Information"
    at_command="AT!GSTATUS?"
    res=$(at $at_port $at_command  |grep -i -v "!GSTATUS"| grep -v "OK")
    _parse_gstatus "$res"
}

function vendor_get_disabled_features(){
    json_add_string "" "IMEI"
    json_add_string "" "NeighborCell"
}

function _get_lockband_nr(){
    local bandcfg=$(at $at_port "AT!BAND?")
    local bandtemplate=$(at $at_port "AT!BAND=?")
    local start_flag=0
    IFS=$'\n'
    for line in $bandtemplate; do
        if [ "$start_flag" = 0 ];then
            if [ "${line:0:10}" == "Available:" ];then
                start_flag=1
            fi
            continue
        else
            
            if [  "${line:0:2}" == "OK" ];then
                break
            fi
        fi
        type_line=$(echo $line | grep '[0-9]* - .*:')
        if [ -n "$type_line" ]; then
            type=$(echo $line | grep -o '[0-9]* - .*:')
            type=${type:4:-1}
            json_add_object $type
            json_add_array "available_band"
            json_close_array
            json_add_array "lock_band"
            json_close_array
            json_close_object
        elif [ -n "$line" ]; then
            band_name=${line##*-}
            band_name=$(echo $band_name | xargs)
            [ -z "$band_name" ] && continue
            case $type in
            "GW")
                band_hex=${line%%-*}
                band_bin=$(echo "obase=2; ibase=16; $band_hex" | bc)
                band_id=$(echo $band_bin | wc -c)
                band_id=$(($band_id - 1))
                ;;
            *)
                band_id=$(echo $band_name |grep -o '^[BbNn][0-9]*' | grep -o '[0-9]*')
                ;;
            esac
            json_select $type
            json_select "available_band"
            add_avalible_band_entry $band_id  ${type}_${band_name} 
            json_close_array
            json_close_object
        fi

    done
    for line in $bandcfg; do
        cfg_line=$(echo $line | grep '[0-9]* - ')
        if [ -n "$cfg_line" ]; then
            type=$(echo $cfg_line | cut -d' ' -f3)
            type=${type:0:-1}
            low_band=${cfg_line:11:16}
            high_band=${cfg_line:28:16}
            json_select $type
            json_select "lock_band"
            _mask_to_band _add_lock_band  $low_band $high_band
            json_select ".."
            json_select ".."
        fi
    done

    unset IFS
}

function _set_lockband_nr(){
    case $band_class in
        "GW")
            band_class=0
            ;;
        "LTE")
            band_class=1
            ;;
        "NRNSA")
            band_class=3
            ;;
        "NRSA")
            band_class=4
            ;;
    esac
    bandlist=$(_band_list_to_mask $lock_band)
    [ "$band_class" -eq 0 ] && bandlist=${bandlist:0:16}
    cmd="AT!BAND=0F,1,\"Custom\",$band_class,${bandlist}"
    res=$(at $at_port "$cmd" | xargs)
    if [ "$res" == "OK" ]; then
        set_lockband="AT!BAND=0F"
    else
        set_lockband="AT!BAND=00"
    fi
    r=$(at $at_port "$set_lockband")
    json_add_string "result" "$res"
    json_add_string "cmd" "$cmd"
}

function _get_voltage(){
    voltage=$(at $at_port "AT!PCVOLT?" | grep -o 'Power supply voltage: [0-9]* mV'|grep -o '[0-9]*' )
    [ -n "$voltage" ] && {
        add_plain_info_entry "voltage" "$voltage mV" "Voltage" 
    }
}

function _get_temperature(){
    temperature=$(at $at_port "AT!PCTEMP?" | grep -o 'Temperature: [0-9]*\.[0-9]*'|grep -o '[0-9]*\.[0-9]*' )
    [ -n "$temperature" ] && {
        add_plain_info_entry "temperature" "$temperature C" "Temperature" 
    }
}

function _add_avalible_band(){
    add_avalible_band_entry $1 $1
}

function _add_lock_band(){
    json_add_string "" $1
}

function _mask_to_band()
{
    func=$1
    low_band=$2
    high_band=$3
    low_band=$(echo "obase=2; ibase=16; $low_band" | bc)
    low_band=$(printf "%064s" $low_band)
    for i in $(seq 1 64); do
        if [ "${low_band: -$i:1}" = "1" ]; then
            band=$i
            $func $band
        fi
    done
    [ -z "$high_band" ] && return
    high_band=$(echo "obase=2; ibase=16; $high_band" | bc)
    high_band=$(printf "%064s" $high_band)
    for i in $(seq 1 64); do
        if [ "${high_band: -$i:1}" = "1" ]; then
            band=$((64+i))
            $func $band
        fi
    done

}

function _band_list_to_mask()
{
    local band_list=$1
    local low=0
    local high=0
    #以逗号分隔
    IFS=","
    for band in $band_list;do
        if [ "$band" -le 64 ]; then
            #使用bc计算2的band次方
            res=$(echo "2^($band-1)" | bc)
            low=$(echo "$low+$res" | bc)

        else
            tmp_band=$((band-64))
            res=$(echo "2^($tmp_band-1)" | bc)
            high=$(echo "$high+$res" | bc)
        fi
    done
    #十六进制输出，padding到16位
    low=$(printf "%016x" $low)
    high=$(printf "%016x" $high)
    echo "$low,$high"
}

function _mask_to_mode()
{
    mask=$1
# RmNet – 0x00000100 bin: 000100000000
# MBIM – 0x00001000 bin: 0001000000000000
    hex_to_bin=$(echo "obase=2; ibase=16; $mask" | bc)
    #paddding to 16 bits
    hex_to_bin=$(printf "%016d" $hex_to_bin)
    adb_port=${hex_to_bin: -1}
    diag_port=${hex_to_bin: -2:1}
    modem_port=${hex_to_bin: -4:1}
    rmnet_port=${hex_to_bin: -9:1}
    mbim_port=${hex_to_bin: -13:1}
}

function _parse_gstatus(){
data=$1
IFS=$'\t\r\n'
for line in $data;do
    line=${line//[$'\t\r\n']}
    key=${line%%:*}
    value=${line##*:}
    key=${key}
    #trim space at value
    value=$(echo $value | xargs)
    if [ -z "$value" ] || [ "$value" = "---" ]; then
        continue
    fi
   
    
    case $key in
    OK)
        continue
        ;;
    *SINR*)
        add_bar_info_entry "SINR" "$value" "$key" 0 30 dB
        ;;
    *RSRP*)
        add_bar_info_entry "RSRP" "$value" "$key" -140 -44 dBm
        ;;
    *RSRQ*)
            add_bar_info_entry "RSRQ" "$value" "$key" -19.5 -3 dB
        ;;
    *RSSI*)
            add_bar_info_entry "RSSI" "$value" "$key" -120 -20 dBm
            ;;
    *)
        add_plain_info_entry $key $value $key
        ;;
    esac
    
done
unset IFS
}



unlock_advance
