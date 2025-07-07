#!/bin/sh
. /lib/functions.sh
. /usr/share/qmodem/modem_util.sh
sim_gpio="/sys/class/gpio/sim/value"
modem_gpio="/sys/class/gpio/4g/value"
debug=0
debug_log()
{
    [ "$debug" -eq 1 ] && echo $1
}
# get detect config
load_detect_config()
{
    config_load qmodem_hc_sim
    config_get ping_dest main ping_dest
    config_get judge_time main judge_time 5
    config_get detect_interval main detect_interval 10
    config_get modem_config main modem_config
    [ -z "$modem_config" ] && get_first_avalible_config
    debug_log "ping_dest:$ping_dest"
    debug_log "judge_time:$judge_time"
    debug_log "detect_interval:$detect_interval"
    debug_log "modem_config:$modem_config"
}

_enabled_config()
{
    cfg=$1
    local state
    config_get state $cfg state
    [ -n "$state" ] && [ "$state" != "disabled" ] && modem_config=$cfg
}

get_first_avalible_config()
{
    config_load qmodem
    config_foreach _enabled_config modem-device
}

reboot_modem() {
    echo 0 > $modem_gpio
    sleep 1
    echo 1 > $modem_gpio
}

switch_sim() {
    if [ -f $sim_gpio ]; then
        sim_status=$(cat $sim_gpio)
        if [ "$sim_status" -eq 0 ]; then
            echo 1 > $sim_gpio
        else
            echo 0 > $sim_gpio
        fi
        reboot_modem
        logger -t modem_sim "switch sim from $sim_status to $(cat $sim_gpio)"
    fi
}

_get_netdev() {
    local modemconfig
    config_load modemconfig $1 modem_config
    [ "$modemconfig" != "$target_modemconfig" ] && return 1
    config_get netdev $1 ifname
}

get_associa_netdev() {
    config_load network
    target_modemconfig=$1
    config_foreach _get_netdev interface
    unset target_modemconfig
}


ping_monitor() {
    #ping_dest为空则不进行ping检测 ，如果有多个，用空格隔开
    has_success=0
    for dest in $ping_dest; do
        ping -c 1 -W 1 $dest -I $netdev > /dev/null
        if [ $? -eq 0 ]; then
            return 1
        fi
    done
    return 0
}

at_sim_monitor() {
    ttydev=$1
    #检查sim卡状态，有sim卡则返回1
    expect="+CPIN: READY"
    result=$(at $ttydev "AT+CPIN?" | grep -o "$expect")
    debug_log $result
    if [ -n "$result" ]; then
        return 1
    fi
    return 0
}

at_dial_monitor() {
    ttydev=$1
    define_connect=$2
    #检查拨号状况,有v4或v6地址则返回1
    at_cmd="AT+CGPADDR=1"
    [ "$define_connect" == "3" ] && at_cmd="AT+CGPADDR=3"
    expect="+CGPADDR:"
    result=$(at $ttydev $at_cmd | grep "$expect")
    debug_log $result
    if [ -n "$result" ];then
            ipv6=$(echo $result | grep -oE "\b([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\b")
            ipv4=$(echo $result | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
            disallow_ipv4="0.0.0.0"
            #remove the disallow ip
            if [ "$ipv4" == "$disallow_ipv4" ];then
                ipv4=""
            fi
            if [ -n "$ipv4" ] || [ -n "$ipv6" ];then
                return 1
            fi
    fi
    return 0
}

precheck()
{
    config_load qmodem
    modem_config=$1
    config_get state $modem_config state
    # is empty or is disabled
    config_get at_port $modem_config at_port
    config_get enable_dial $modem_config enable_dial 0
    config_get define_connect $modem_config define_connect 1
    config_get global_en main enable_dial 0
    debug_log "state:$state"
    debug_log "at_port:$at_port"
    debug_log "enable_dial:$enable_dial"
    debug_log "define_connect:$define_connect"
    debug_log "global_en:$global_en"
    [ -z "$state" ] || [ "$state" == "disabled" ] && return 1
    [ "$global_en" == "0" ] && return 1
    [ -z "$enable_dial" ] || [ "$enable_dial" == "0" ] && return 1
    [ -z "$at_port" ] && return 1
    [ ! -e "$at_port" ] && return 1
    return 0
}

main_loop()
{
    while true;do
        precheck $modem_config
        if [ $? -eq 1 ];then 
            sleep $detect_interval
            continue
        fi
        get_associa_netdev $modem_config
        
        if [ -n "$ping_dest" ]; then
             ping_monitor
             ping_result=$?
        fi
        if [ -n "$at_port" ] && [ -n "$define_connect" ];then
             at_dial_monitor $at_port $define_connect
             dial_result=$?
        fi
        if [ -n "$at_port" ]; then
            at_sim_monitor $at_port
            sim_result=$?
        fi

        debug_log "ping_result:$ping_result dial_result:$dial_result sim_result:$sim_result"

        if [ -n "$ping_dest" ];then
            #策略：ping成功则重置fail_times，否则fail_times累加
            [ -z "$dial_result" ] && dial_result=1
            [ -z "$sim_result" ] && sim_result=1
            fail_total=$((3 - $ping_result - $dial_result - $sim_result))
            if [ $ping_result -eq 1 ]; then
                fail_times=0
            else
                fail_times=$(($fail_times + $fail_total))
            fi
            
            #如果失败次数超过judge_time * 3则切卡 切卡后等待3分钟
        else
            #策略 无ping则检测拨号和sim卡状态，拨号成功则重置fail_times，否则fail_times累加
            [ -z "$dial_result" ] && dial_result=1
            [ -z "$sim_result" ] && sim_result=1
            fail_total=$((2 - $dial_result - $sim_result))
            if [ $dial_result -eq 1 ]; then
                fail_times=0
            else
                fail_times=$(($fail_times + $fail_total))
            fi
        fi
        logger -t modem_sim "ping_result:$ping_result dial_result:$dial_result sim_result:$sim_result fail_times:$fail_times fail_total:$fail_total fail_times:$fail_times"
        if [ $fail_times -ge $(($judge_time * 2)) ]; then
            switch_sim
            fail_times=0
            sleep 240
        fi
        sleep $detect_interval
    done
}
if [ ! "$debug" -eq 1 ]; then
    sleep 180
fi
load_detect_config
main_loop
