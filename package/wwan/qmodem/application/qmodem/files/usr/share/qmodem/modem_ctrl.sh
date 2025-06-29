#!/bin/sh
source /usr/share/libubox/jshn.sh
method=$1
config_section=$2
at_port=$(uci -q get qmodem.$config_section.at_port)
override_at_port=$(uci -q get qmodem.$config_section.override_at_port)
[ -n "$override_at_port" ] && at_port=$override_at_port
uci -q get qmodem.$config_section.sms_at_port >/dev/null && sms_at_port=$(uci -q get qmodem.$config_section.sms_at_port)
vendor=$(uci -q get qmodem.$config_section.manufacturer)
platform=$(uci -q get qmodem.$config_section.platform)
pdp_index=$(uci -q get qmodem.$config_section.pdp_index)
[ -z "$pdp_index" ] && pdp_index=$(uci -q get qmodem.$config_section.suggest_pdp_index)
use_ubus=$(uci -q get qmodem.$config_section.use_ubus)
modem_path=$(uci -q get qmodem.$config_section.path)
modem_slot=$(basename $modem_path)

[ -z "$pdp_index" ] && {
    pdp_index="1"
}

[ $use_ubus -eq 1 ] && use_ubus_flag="-u"

#please update dynamic_load.json to add new vendor
vendor_script_prefix="/usr/share/qmodem/vendor"
dynamic_load_json="$vendor_script_prefix/dynamic_load.json"
vendor_file="${vendor_script_prefix}/`jq -r --arg vendor $vendor '.[$vendor]' $dynamic_load_json`"
if [ -z "$vendor" ] || [ ! -f "$vendor_file" ]; then
    logger -t modem_ctrl "vendor $vendor not support"
    . /usr/share/qmodem/generic.sh
fi
. $vendor_file

try_cache() {
    cache_timeout=$1
    cache_file=$2
    function_name=$3
    current_time=$(date +%s)
    file_time=$(stat -t $cache_file | awk '{print $14}')
    [ -z "$file_time" ] && file_time=0
    if [ ! -f $cache_file ] || [ $(($current_time - $file_time)) -gt $cache_timeout ]; then
        touch $cache_file
        json_add_array modem_info
        $function_name
        json_close_array
        json_dump > $cache_file
        return 1
    else
        cat $cache_file
        exit 0
    fi
}

get_sms(){
    [ -n "$sms_at_port" ] && at_port=$sms_at_port
    cache_timeout=$1
    cache_file=$2
    current_time=$(date +%s)
    file_time=$(stat -t $cache_file | awk '{print $14}')
    [ -z "$file_time" ] && file_time=0
    get_sms_capabilities
    if [ ! -f $cache_file ] || [ $(($current_time - $file_time)) -gt $cache_timeout ]; then
        touch $cache_file
        #sms_tool_q -d $at_port -j recv > $cache_file
        tom_modem $use_ubus_flag  -d $at_port -o r > $cache_file
        echo $(cat $cache_file ; json_dump) | jq -s 'add'
    else
        echo $(cat $cache_file ; json_dump) | jq -s 'add'
    fi
}

get_at_cfg(){
    json_add_object at_cfg
    duns=$(ls /dev/mhi_DUN*)
    ttys=$(ls /dev/ttyUSB*)
    ttyacms=$(ls /dev/ttyACM*)
    wwanNatN=$(ls /dev/wwan* |grep -E wwan[0-9]at[0-9])
    all_ttys="$duns $ttys $ttyacms $wwanNatN"
    json_add_array other_ttys
    for tty in $all_ttys; do
        [ -n "$tty" ] && json_add_string "" "$tty"
    done
    json_close_array
    json_add_array ports
    ports=$(uci -q get qmodem.$config_section.ports)
    for port in $ports; do
        json_add_string "" "$port"
    done
    json_close_array
    json_add_array valid_ports
    v_ports=$(uci -q get qmodem.$config_section.valid_at_ports)
    for port in $v_ports; do
        json_add_string "" "$port"
    done
    json_close_array
    override_at_port=$(uci -q get qmodem.$config_section.override_at_port)
    at_port=$(uci -q get qmodem.$config_section.at_port)
    [ -n "$override_at_port" ] && at_port=$override_at_port
    json_add_string using_port "$at_port"
    json_add_array cmds
    
    # Determine language and select appropriate AT commands file
    lang=$(uci -q get luci.main.lang 2>/dev/null || echo "en")
    case "$lang" in
        zh*|cn|auto)
            at_commands_file="/usr/share/qmodem/at_commands_zh.json"
            ;;
        *)
            at_commands_file="/usr/share/qmodem/at_commands_en.json"
            ;;
    esac
    
    # Fallback to default file if language-specific file doesn't exist
    [ ! -f "$at_commands_file" ] && at_commands_file="/usr/share/qmodem/at_commands.json"
    
    general_cmd=$(jq -rc '.general[]|to_entries| .[] | @sh "key=\(.key) value=\(.value)"' "$at_commands_file")
    platform_cmd=$(jq -rc ".${vendor}.${platform}[]|to_entries| .[] | @sh \"key=\(.key) value=\(.value)\"" "$at_commands_file")
    [ -z "$platform_cmd" ] && platform_cmd=$(jq -rc ".$vendor.general[]|to_entries| .[] | @sh \"key=\(.key) value=\(.value)\"" "$at_commands_file")
    cmds=$(echo -e "$general_cmd\n$platform_cmd")
    IFS=$'\n'
    for cmd in $cmds; do
        json_add_object cmd
        eval $cmd
        json_add_string "name" "$key"
        json_add_string "value" "$value"
        json_close_object
    done
    json_close_array
    json_close_object
    json_dump
    unset IFS
}

#会初始化一个json对象 命令执行结果会保存在json对象中
json_init
json_add_object result
json_close_object
case $method in
    "base_info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file base_info
        ;;
    "cell_info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file cell_info
        ;;
    "clear_dial_log")
        json_select result
        log_file="/var/run/qmodem/${config_section}_dir/dial_log"
        [ -f $log_file ] && echo "" > $log_file && json_add_string status "1" || json_add_string status "0"
        json_close_object
        ;;
    "delete_sms")
        json_select result
        index=$3
        [ -n "$sms_at_port" ] && at_port=$sms_at_port
        for i in $index; do
            tom_modem $use_ubus_flag  -d $at_port -o d -i $i
            touch /tmp/cache_sms_$2
            if [ "$?" == 0 ]; then
                json_add_string status "1"
                json_add_string "index$i" "tom_modem $use_ubus_flag  -d $at_port -o d -i $i"
            else
                json_add_string status "0"
            fi
        done
        json_close_object
        rm -rf /tmp/cache_sms_$2
        ;;
    "do_reboot")
        reboot_method=$(echo $3 |jq -r '.method')
        echo $3 > /tmp/555/reboot
        case $reboot_method in
            "hard")
                hard_reboot
                ;;
            "soft")
                soft_reboot
                ;;
        esac
        ;;
    "get_at_cfg")
        get_at_cfg
        exit
        ;;
    "get_copyright")
        _copyright
        ;;
    "get_disabled_features")
        json_add_array disabled_features
        vendor_get_disabled_features
        get_modem_disabled_features
        get_global_disabled_features
        json_close_array
        ;;
    "get_dns")
        get_dns
        ;;
    "get_imei")
        get_imei
        ;;
    "get_lockband")
        get_lockband
        ;;
    "get_mode")
        get_mode
        ;;
    "get_neighborcell")
        get_neighborcell
        ;;
    "get_network_prefer")
        get_network_prefer
        ;;
    "get_reboot_caps")
        get_reboot_caps
        exit
        ;;
    "get_sms")
        get_sms 10 /tmp/cache_sms_$2
        exit
        ;;
    "info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file get_info
        ;;
    "network_info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file network_info
        ;;
    "send_at")
        cmd=$(echo "$3" | jq -r '.at')
        port=$(echo "$3" | jq -r '.port')
        res=$(at $port $cmd)
        json_add_object at_cfg
        if [ "$?" == 0 ]; then
            json_add_string status "1"
            json_add_string cmd "at $port $cmd"
            json_add_string "res" "$res"
        else
            json_add_string status "0"
        fi
        ;;
    "send_raw_pdu")
        cmd=$3
        [ -n "$sms_at_port" ] && at_port=$sms_at_port
        res=$(tom_modem $use_ubus_flag  -d $at_port -o s -p "$cmd")
        json_select result
        if [ "$?" == 0 ]; then
            json_add_string status "1"
            json_add_string cmd "tom_modem $use_ubus_flag  -d $at_port -o s -p \"$cmd\""
            json_add_string "res" "$res"
        else
            json_add_string status "0"
        fi
        ;;
    "send_sms")
        cmd_json=$3
        phone_number=$(echo $cmd_json | jq -r '.phone_number')
        message_content=$(echo $cmd_json | jq -r '.message_content')
        [ -n "$sms_at_port" ] && at_port=$sms_at_port
        sms_tool_q -d $at_port send "$phone_number" "$message_content" > /dev/null
        json_select result
        if [ "$?" == 0 ]; then
            json_add_string status "1"
            json_add_string cmd "sms_tool_q -d $at_port send \"$phone_number\" \"$message_content\""
            json_add_string "cmd_json" "$cmd_json"
        else
            json_add_string status "0"
        fi
        json_close_object
        ;;
    "set_imei")
        set_imei $3
        ;;
    "set_lockband")
        set_lockband $3
        ;;
    "set_mode")
        set_mode $3
        ;;
    "set_neighborcell")
        set_neighborcell $3
        ;;
    "set_network_prefer")
        set_network_prefer $3
        ;;
    "set_sms_storage")
        set_sms_storage $3
        ;;
    "sim_info")
        cache_file="/tmp/cache_$1_$2"
        try_cache 10 $cache_file sim_info
        ;;
    #sim_switch
    "get_sim_switch_capabilities")
        get_sim_switch_capabilities
        ;;
    "get_sim_slot")
        get_sim_slot
        ;;
    "set_sim_slot")
        set_sim_slot $3
        ;;
esac
json_dump
