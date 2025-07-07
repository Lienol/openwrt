#!/bin/sh
. /lib/functions.sh

config_name="qmodem"
config_section=$1
init_type=$2

case $init_type in
    post_init)
        # pre-add at commands
        cfg_prefix="post_init"
        debug_subject="post_init"
        ;;
    pre_dial)
        # pre-dial at commands
        cfg_prefix="pre_dial"
        debug_subject="pre_dial"
        ;;
    *)
        m_debug "init_type error"
        exit 1
        ;;
esac

_execute_ats(){
    command=$1
    res=$(at $at_port $command | tr -d '\r')
    m_debug "execute_ats $config_section: $command $at_port"
    m_debug "execute_ats_result $config_section: $res"
}

. /usr/share/qmodem/modem_util.sh
config_load ${config_name}

config_get ${cfg_prefix}_delay $config_section delay

config_get at_port $config_section  at_port

if [ -f "$at_port" ] || [ -z "$at_port" ]; then
    m_debug "$config_section:at_port is not set or not a file"
    m_debug "at_port $config_section: $at_port"
    exit 1
fi

if [ -n "$delay"  ]; then
    sleep $delay
fi



config_list_foreach $config_section ${cfg_prefix}_at_cmds   _execute_ats
