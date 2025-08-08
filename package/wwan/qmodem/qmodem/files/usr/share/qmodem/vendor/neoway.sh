#!/bin/sh
# Copyright (C) 2025 sfwtw
_Vendor="neoway"
_Author="sfwtw"
_Maintainer="sfwtw <unknown>"
source /usr/share/qmodem/generic.sh
debug_subject="neoway_ctrl"

vendor_get_disabled_features(){
    json_add_string "" "NeighborCell"
    json_add_string "" "DialMode"
}

get_imei(){
    at_command="AT+CGSN"
    imei=$(at $at_port $at_command | grep -o "[0-9]\{15\}")
    json_add_string "imei" "$imei"
}

set_imei(){
    local imei="$1"
    at_command="AT+SPIMEI=0,\"$imei\""
    res=$(at $at_port $at_command)
    json_select "result"
    json_add_string "set_imei" "$res"
    json_close_object
    get_imei
}

#获取网络偏好
# $1:AT串口
get_network_prefer()
{
    at_command='AT$MYSYSINFO'
    local response=$(at ${at_port} ${at_command} | grep '$MYSYSINFO:' | awk -F',' '{print $1}' | awk '{print $2}' | sed 's/\r//g')

    network_prefer_3g="0";
    network_prefer_4g="0";
    network_prefer_5g="0";

    case "$response" in
        "3")
            # 3G
            network_prefer_3g="1"
            ;;
        "4")
            # 4G
            network_prefer_4g="1"
            ;;
        "5")
            # 5G
            network_prefer_5g="1"
            ;;
        "7")
            # 3G + 4G
            network_prefer_3g="1"
            network_prefer_4g="1"
            ;;
        "9")
            # 5G
            network_prefer_5g="1"
            ;;
        "11")
            # 3G + 5G
            network_prefer_3g="1"
            network_prefer_5g="1"
            ;;
        "12")
            # 4G + 5G
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        "14")
            # 3G + 4G + 5G
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
        "*")
            # AUTO
            network_prefer_3g="1"
            network_prefer_4g="1"
            network_prefer_5g="1"
            ;;
    esac
    json_add_object network_prefer
    json_add_string 2G "$network_prefer_2g"
    json_add_string 3G "$network_prefer_3g"
    json_add_string 4G "$network_prefer_4g"
    json_add_string 5G "$network_prefer_5g"
    json_close_object
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

    local config_mode="1"
    
    case "$length" in
        "1")
            if [ "$network_prefer_3g" = "true" ]; then
                config_mode="3" # 仅3G
            elif [ "$network_prefer_4g" = "true" ]; then
                config_mode="4" # 仅4G
            elif [ "$network_prefer_5g" = "true" ]; then
                config_mode="9" # 仅5G
            fi
        ;;
        "2")
            if [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_4g" = "true" ]; then
                config_mode="7" # 3G + 4G
            elif [ "$network_prefer_3g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                config_mode="11" # 3G + 5G
            elif [ "$network_prefer_4g" = "true" ] && [ "$network_prefer_5g" = "true" ]; then
                config_mode="12" # 4G + 5G
            fi
        ;;
        "3") 
            config_mode="14" # 3G + 4G + 5G
        ;;
        *) 
            config_mode="1" # AUTO
        ;;
    esac

    at_command='AT$MYSYSINFO='${config_mode}
    res=$(at "${at_port}" "${at_command}")

    json_select "result"
    json_add_string "set_network_prefer" "$res"
    json_close_object
}

#基本信息
base_info()
{
    m_debug  "Neoway base info"

    #Name（名称）
    at_command="AT+CGMM"
    name=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    #Manufacturer（制造商）
    at_command="AT+CGMI"
    manufacturer=$(at $at_port $at_command | grep "+CGMI:" | sed 's/+CGMI: //g' | sed 's/\r//g')
    #Revision（固件版本）
    at_command="ATI"
    revision=$(at $at_port $at_command | sed -n '5p' | sed 's/\r//g')
    # at_command="AT+CGMR"
    # revision=$(at $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    class="Base Information"
    add_plain_info_entry "manufacturer" "$manufacturer" "Manufacturer"
    add_plain_info_entry "revision" "$revision" "Revision"
    add_plain_info_entry "at_port" "$at_port" "AT Port"
    get_connect_status
}

#SIM卡信息
sim_info()
{
    m_debug  "Neoway sim info"
    
    #SIM Slot（SIM卡卡槽）
    at_command="AT+SIMCROSS?"
    sim_slot=$(at $at_port $at_command | grep "+SIMCROSS:" | awk -F'[ ,]' '{print $2}' | sed 's/\r//g')
    # m_debug "SIM Slot: $sim_slot"
    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN"
	imei=$(at $at_port $at_command | sed -n '3p' | awk -F'"' '{print $2}')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status_flag=$(at $at_port $at_command | sed -n '3p')
    sim_status=$(get_sim_status "$sim_status_flag")

    [ "$sim_status" != "ready" ] && return

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
	sim_number=$(at $at_port $at_command | sed -n '3p' | awk -F'"' '{print $4}')

    #IMSI（国际移动用户识别码）
    at_command="AT+CIMI"
	imsi=$(at $at_port $at_command | sed -n '3p' | sed 's/\r//g')

    #ICCID（集成电路卡识别码）
    iccid=$(at $at_port 'AT$MYCCID' | grep '$MYCCID:' | awk -F' "' '{print $2}' | sed 's/"//g')
    [ -n "$iccid" ] || return
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

rate_convert()
{
    #check if bc is installed
    is_bc_installed=$(which bc)
    local rate=$1
    rate_units="Kbps Mbps Gbps Tbps"
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

#网络信息
network_info()
{
    m_debug  "Neoway network info"

    #CSQ（信号强度）
    at_command="AT+CSQ"
    response=$(at ${at_port} ${at_command} | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    #最大比特率，信道质量指示
    at_command='AT+C5GQOSRDP'
    response=$(at $at_port $at_command | grep "+C5GQOSRDP:")

    if [ -n "$response" ]; then
        # Parse 5G QoS parameters
        # Format: +C5GQOSRDP: <cid>,<5QI>[,<DL_GFBR>,<UL_GFBR>[,<DL_MFBR>,<UL_MFBR>[,<DL_SAMBR>,<UL_SAMBR>[,<Averaging_window>]]]]] 

        # Extract DL_SAMBR (downlink session AMBR) and UL_SAMBR (uplink session AMBR) in kbit/s
        ambr_dl=$(echo "$response" | awk -F',' '{print $7}' | sed 's/\r//g')
        ambr_ul=$(echo "$response" | awk -F',' '{print $8}' | sed 's/\r//g')

        # Convert kbit/s to Mbit/s for display if values exist
        [ -n "$ambr_dl" ] && ambr_dl=$(rate_convert $ambr_dl)
        [ -n "$ambr_ul" ] && ambr_ul=$(rate_convert $ambr_ul)
    fi

    class="Network Information"
    add_plain_info_entry "AMBR UL" "$ambr_ul" "Access Maximum Bit Rate for Uplink"
    add_plain_info_entry "AMBR DL" "$ambr_dl" "Access Maximum Bit Rate for Downlink"
}

convert_neoway_band_to_readable() {
    local act=$1
    local band_value=$2
    case "$act" in
        "2") echo "WB$band_value" ;; # UTRAN
        "3") echo "B$band_value" ;; # E-UTRAN
        "6") echo "N$band_value" ;; # NR
        *) echo "$band_value" ;;
    esac
}

convert_readable_band_to_neoway() {
    local band=$1

    local prefix=${band:0:1}
    local band_value
    
    case "$prefix" in
        "W")
            band_value=${band:2}
            echo "2 $band_value"
            ;;
        "B")
            band_value=${band:1}
            echo "3 $band_value"
            ;;
        "N")
            band_value=${band:1}
            echo "6 $band_value"
            ;;
        *)
            echo "3 $band"
            ;;
    esac
}

get_lockband() {
    json_add_object "lockband"
    
    at_command="AT+NWSETBAND?"
    response=$(at $at_port $at_command)
    
    local band_num=$(echo "$response" | grep "+NWSETBAND:" | awk '{print $2}' | sed 's/\r//g')
    m_debug "Band number: $band_num"

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

    at_command="AT+NWSETBAND=?"
    available_bands=$(at $at_port $at_command | grep "+" | awk -F',' '{for(i=2;i<=NF;i++) print $i}' | sed 's/\r//g')
    m_debug "Available bands: $available_bands"
    for band in $available_bands; do
        if [[ "$band" == WB* ]]; then
            band_value=${band:2}
            json_select "UMTS"
            json_select "available_band"
            add_avalible_band_entry "$band_value" "$band"
            json_select ..
            json_select ..
        elif [[ "$band" == B* ]]; then
            band_value=${band:1}
            json_select "LTE"
            json_select "available_band"
            add_avalible_band_entry "$band_value" "$band"
            json_select ..
            json_select ..
        elif [[ "$band" == N* ]]; then
            band_value=${band:1}
            json_select "NR"
            json_select "available_band"
            add_avalible_band_entry "$band_value" "$band"
            json_select ..
            json_select ..
        fi
    done

    if [ "$band_num" != "0" ]; then
        IFS=$'\n'
        for line in $(echo "$response" | grep -v "+NWSETBAND:" | grep -v "OK"); do
            set -- $(echo $line | tr ',' ' ')
            act=$1
            num=$2
            shift 2
            for band_value in "$@"; do
                if [[ "$band" == WB* ]]; then
                    act="2"
                elif [[ "$band" == B* ]]; then
                    act="3"
                elif [[ "$band" == N* ]]; then
                    act="6"
                fi
                band_value=$(echo "$band_value" | awk -F' ' '{print $3}' | sed 's/\r//g')
                m_debug "Processing band: $band_value for act: $act"
                if [ -n "$band_value" ]; then
                    case "$act" in
                        "2")
                            json_select "UMTS"
                            json_select "lock_band"
                            band_value=${band_value:2}
                            json_add_string "" "$band_value"
                            json_select ..
                            json_select ..
                            ;;
                        "3")
                            json_select "LTE"
                            json_select "lock_band"
                            band_value=${band_value:1}
                            json_add_string "" "$band_value"
                            json_select ..
                            json_select ..
                            ;;
                        "6")
                            json_select "NR"
                            json_select "lock_band"
                            band_value=${band_value:1}
                            json_add_string "" "$band_value"
                            json_select ..
                            json_select ..
                            ;;
                    esac
                fi
            done
        done
        unset IFS
    fi
    
    json_close_object
}

set_lockband() {
    m_debug "neoway set lockband info"
    config=$1

    band_class=$(echo $config | jq -r '.band_class')
    lock_band=$(echo $config | jq -r '.lock_band')

    if [ -z "$lock_band" ] || [ "$lock_band" = "null" ]; then
        at_command="AT+NWSETBAND=0"
        res=$(at $at_port $at_command)
        json_select "result"
        json_add_string "set_lockband" "$res"
        json_close_object
        return
    fi

    local act
    case "$band_class" in
        "UMTS") act=2 ;;
        "LTE") act=3 ;;
        "NR") act=6 ;;
        *) act=3 ;; # 默认LTE
    esac

    IFS=','; set -- $lock_band
    band_num=$#
    at_command="AT+NWSETBAND=$act,$band_num"
    for band in "$@"; do
        at_command="$at_command,$band"
    done
    unset IFS

    res=$(at $at_port $at_command)
    
    json_select "result"
    json_add_string "set_lockband" "$res"
    json_add_string "config" "$config"
    json_add_string "band_class" "$band_class"
    json_add_string "lock_band" "$lock_band"
    json_close_object
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

#小区信息
cell_info()
{
    m_debug "Neoway cell info"

    at_command='AT+NETDMSGEX'
    response=$(at $at_port $at_command)
    
    if [ -n "$(echo "$response" | grep "+NETDMSGEX:")" ]; then

        net_mode=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $1}' | sed 's/+NETDMSGEX: "//g' | sed 's/"//g')
        network_mode=$(get_network_mode "$net_mode")

        mcc_mnc=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $2}' | sed 's/"//g')
        mcc=$(echo "$mcc_mnc" | cut -d'+' -f1)
        mnc=$(echo "$mcc_mnc" | cut -d'+' -f2)

        band=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $3}' | sed 's/"//g')

        arfcn=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $4}' | sed 's/\r//g')
        
        case "$net_mode" in
            "NR to 5GCN"|"NR to EPS"|"NR-LTE ENDC"|"NR-LTE NEDC")

                gnbid=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $5}' | sed 's/\r//g')
                pci=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $6}' | sed 's/\r//g')
                ss_rsrp=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $7}' | sed 's/\r//g')
                ss_rsrq=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $8}' | sed 's/\r//g')
                ss_sinr=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $9}' | sed 's/\r//g')

                [ -n "$ss_rsrp" ] && ss_rsrp_actual=$(printf "%.1f" $(echo "$ss_rsrp / 10" | bc -l 2>/dev/null))
                
                [ -n "$ss_rsrq" ] && ss_rsrq_actual=$(printf "%.1f" $(echo "$ss_rsrq / 10" | bc -l 2>/dev/null))
                
                [ -n "$ss_sinr" ] && ss_sinr_actual=$(printf "%.1f" $(echo "$ss_sinr / 10" | bc -l 2>/dev/null))

                network_mode="NR5G-SA Mode"
                nr_mcc="$mcc"
                nr_mnc="$mnc"
                nr_cell_id="$gnbid"
                nr_physical_cell_id="$pci"
                nr_arfcn="$arfcn"
                nr_band="$band"
                nr_rsrp="$ss_rsrp_actual"
                nr_rsrq="$ss_rsrq_actual"
                nr_sinr="$ss_sinr_actual"
                ;;
                
            "TDD LTE"|"FDD LTE")

                tac=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $5}')
                cell_id=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $6}')
                pci=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $7}')
                rx_dbm=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $8}')
                tx_dbm=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $9}')
                rsrp=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $10}')
                rsrq=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $11}')
                sinr=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $12}')
                rssi=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $13}')

                if [ "$(echo "$response" | grep -o ',' | wc -l)" -ge 17 ]; then
                    dl_bw_num=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $17}')
                    ul_bw_num=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $18}' | sed 's/\r//g')

                    dl_bandwidth=$(get_bandwidth "LTE" "$dl_bw_num")
                    ul_bandwidth=$(get_bandwidth "LTE" "$ul_bw_num")
                fi

                [ -n "$rsrp" ] && rsrp_actual=$(printf "%.1f" $(echo "$rsrp / 10" | bc -l 2>/dev/null))
                
                [ -n "$rsrq" ] && rsrq_actual=$(printf "%.1f" $(echo "$rsrq / 10" | bc -l 2>/dev/null))
                
                [ -n "$sinr" ] && sinr_actual=$(printf "%.1f" $(echo "$sinr / 10" | bc -l 2>/dev/null))
                
                [ -n "$rssi" ] && rssi_actual=$(printf "%.1f" $(echo "$rssi / 10" | bc -l 2>/dev/null))

                network_mode="LTE Mode"
                lte_mcc="$mcc"
                lte_mnc="$mnc"
                lte_cell_id="$cell_id"
                lte_physical_cell_id="$pci"
                lte_earfcn="$arfcn"
                lte_freq_band_ind="$band"
                lte_tac="$tac"
                lte_rsrp="$rsrp_actual"
                lte_rsrq="$rsrq_actual"
                lte_sinr="$sinr_actual"
                lte_rssi="$rssi_actual"
                lte_cql="$cqi"
                lte_srxlev="$srxlev"
                lte_dl_bandwidth="$dl_bandwidth"
                lte_ul_bandwidth="$ul_bandwidth"
                lte_tx_power="$tx_dbm"
                lte_rx_power="$rx_dbm"
                ;;
                
            "WCDMA"|"HSDPA"|"HSUPA"|"HSDPA and HSUPA"|"HSDPA+"|"HSDPA+ and HSUPA")

                lac=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $5}')
                cell_id=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $6}')
                psc=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $7}')
                rac=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $8}')
                rx_dbm=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $9}')
                tx_dbm=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $10}')
                rscp=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $11}')
                ecio=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $12}')
                rssi=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $13}')

                if [ "$(echo "$response" | grep -o ',' | wc -l)" -ge 17 ]; then
                    srxlev=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $14}')
                    squal=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $15}')
                    phych_num=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $16}')
                    sf_num=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $17}')
                    slot_num=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $18}')
                    is_commod=$(echo "$response" | grep "+NETDMSGEX:" | awk -F',' '{print $19}' | sed 's/\r//g')

                    phych=$(get_phych "$phych_num")
                    sf=$(get_sf "$sf_num")
                    slot=$(get_slot "$slot_num")
                fi

                [ -n "$rscp" ] && rscp_actual=$(printf "%.1f" $(echo "$rscp / 10" | bc -l 2>/dev/null))
                
                [ -n "$ecio" ] && ecio_actual=$(printf "%.1f" $(echo "$ecio / 10" | bc -l 2>/dev/null))

                network_mode="WCDMA Mode"
                wcdma_mcc="$mcc"
                wcdma_mnc="$mnc"
                wcdma_lac="$lac"
                wcdma_cell_id="$cell_id"
                wcdma_uarfcn="$arfcn"
                wcdma_psc="$psc"
                wcdma_rac="$rac"
                wcdma_band="$band"
                wcdma_rscp="$rscp_actual"
                wcdma_ecio="$ecio_actual"
                wcdma_phych="$phych"
                wcdma_sf="$sf"
                wcdma_slot="$slot"
                wcdma_com_mod="$is_commod"
                wcdma_rx_dbm="$rx_dbm"
                wcdma_tx_dbm="$tx_dbm"
                ;;
                
            *)
                network_mode="Unknown Mode"
                ;;
        esac

        class="Cell Information"
        add_plain_info_entry "network_mode" "$network_mode" "Network Mode"
        
        case $network_mode in
            "NR5G-SA Mode")
                add_plain_info_entry "MCC" "$mcc" "Mobile Country Code"
                add_plain_info_entry "MNC" "$mnc" "Mobile Network Code"
                add_plain_info_entry "Cell ID" "$nr_cell_id" "Cell ID"
                add_plain_info_entry "Physical Cell ID" "$nr_physical_cell_id" "Physical Cell ID"
                add_plain_info_entry "ARFCN" "$nr_arfcn" "Absolute Radio-Frequency Channel Number"
                add_plain_info_entry "Band" "$nr_band" "Band"
                add_bar_info_entry "RSRP" "$nr_rsrp" "Reference Signal Received Power" -140 -44 dBm
                add_bar_info_entry "RSRQ" "$nr_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
                add_bar_info_entry "SINR" "$nr_sinr" "Signal to Interference plus Noise Ratio" 0 30 dB
                ;;
            "LTE Mode")
                add_plain_info_entry "MCC" "$lte_mcc" "Mobile Country Code"
                add_plain_info_entry "MNC" "$lte_mnc" "Mobile Network Code"
                add_plain_info_entry "Cell ID" "$lte_cell_id" "Cell ID"
                add_plain_info_entry "Physical Cell ID" "$lte_physical_cell_id" "Physical Cell ID"
                add_plain_info_entry "EARFCN" "$lte_earfcn" "E-UTRA Absolute Radio Frequency Channel Number"
                add_plain_info_entry "Band" "$lte_freq_band_ind" "Band"
                add_plain_info_entry "TAC" "$lte_tac" "Tracking Area Code"
                add_plain_info_entry "RX Power" "$lte_rx_power" "RX Power (dBm)"
                add_plain_info_entry "TX Power" "$lte_tx_power" "TX Power (dBm)"
                add_bar_info_entry "RSRP" "$lte_rsrp" "Reference Signal Received Power" -140 -44 dBm
                add_bar_info_entry "RSRQ" "$lte_rsrq" "Reference Signal Received Quality" -19.5 -3 dB
                add_bar_info_entry "SINR" "$lte_sinr" "Signal to Interference plus Noise Ratio" 0 30 dB
                add_bar_info_entry "RSSI" "$lte_rssi" "Received Signal Strength Indicator" -120 -20 dBm
                
                if [ -n "$lte_cql" ]; then
                    add_plain_info_entry "CQI" "$lte_cql" "Channel Quality Indicator"
                    add_plain_info_entry "DL Bandwidth" "$lte_dl_bandwidth" "DL Bandwidth"
                    add_plain_info_entry "UL Bandwidth" "$lte_ul_bandwidth" "UL Bandwidth"
                    add_plain_info_entry "Srxlev" "$lte_srxlev" "Serving Cell Receive Level"
                fi
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
                add_plain_info_entry "RX Power" "$wcdma_rx_dbm" "RX Power (dBm)"
                add_plain_info_entry "TX Power" "$wcdma_tx_dbm" "TX Power (dBm)"
                add_bar_info_entry "RSCP" "$wcdma_rscp" "Received Signal Code Power" -120 -25 dBm
                add_plain_info_entry "Ec/Io" "$wcdma_ecio" "Ec/Io"
                
                if [ -n "$wcdma_phych" ]; then
                    add_plain_info_entry "Physical Channel" "$wcdma_phych" "Physical Channel"
                    add_plain_info_entry "Spreading Factor" "$wcdma_sf" "Spreading Factor"
                    add_plain_info_entry "Slot" "$wcdma_slot" "Slot"
                    add_plain_info_entry "Compression Mode" "$wcdma_com_mod" "Compression Mode"
                fi
                ;;
                
            *)
                add_plain_info_entry "Network Type" "$net_mode" "Network Type"
                add_plain_info_entry "MCC" "$mcc" "Mobile Country Code"
                add_plain_info_entry "MNC" "$mnc" "Mobile Network Code"
                add_plain_info_entry "ARFCN" "$arfcn" "Absolute Radio-Frequency Channel Number"
                add_plain_info_entry "Band" "$band" "Band"
                ;;
        esac
    fi
}

get_network_mode()
{
    local mode="$1"
    case "$mode" in
        "NR to 5GCN"|"NR-LTE ENDC"|"NR-LTE NEDC") echo "NR5G-SA Mode" ;;
        "NR to EPS") echo "NR5G-SA Mode" ;;
        "TDD LTE"|"FDD LTE") echo "LTE Mode" ;;
        "WCDMA"|"HSDPA"|"HSUPA"|"HSDPA and HSUPA"|"HSDPA+"|"HSDPA+ and HSUPA") echo "WCDMA Mode" ;;
        "GSM"|"GPRS"|"EDGE") echo "GSM Mode" ;;
        *) echo "$mode Mode" ;;
    esac
}
