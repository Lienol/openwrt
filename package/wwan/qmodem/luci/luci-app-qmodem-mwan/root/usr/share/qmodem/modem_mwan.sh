#! /bin/sh
. /lib/functions.sh






append_if(){
    interface=$1
    track_ip=$2
    uci batch <<EOF
set mwan3.$interface=interface
set mwan3.$interface.enabled=1
set mwan3.$interface.family="$family"
set mwan3.$interface.track_method=ping
set mwan3.$interface.reliability='1'
set mwan3.$interface.count='1'
set mwan3.$interface.size='56'
set mwan3.$interface.max_ttl='60'
set mwan3.$interface.timeout='4'
set mwan3.$interface.interval='10'
set mwan3.$interface.failure_interval='5'
set mwan3.$interface.recovery_interval='5'
set mwan3.$interface.down='5'
set mwan3.$interface.up='5'
set mwan3.$interface.keep_failure_interval='1'
set mwan3.$interface.add_by=modem
delete mwan3.$interface.track_ip
EOF
    if [ -n "$track_ip" ]; then
        for ip in $track_ip; do
            uci add_list mwan3.$interface.track_ip=$ip
        done
    fi
}




add_mwan3_member()
{
    interface=$1
    metric=$2
    weight=$3
    member_name=$4
    uci batch <<EOF
set mwan3.$member_name=member
set mwan3.$member_name.interface=$interface
set mwan3.$member_name.metric=$metric
set mwan3.$member_name.weight=$weight
set mwan3.$member_name.add_by=modem
EOF

}

remove_member()
{
    config_load mwan3
    config_foreach remove_member_cb member
}

remove_member_cb()
{
    local add_by
    config_get add_by $1 add_by
    if [ "$add_by" = "modem" ]; then
        uci delete mwan3.$1
    fi
}

append_mwan3_policy_member()
{
    uci add_list mwan3.$1.use_member=$2
}

init_mwan3_policy()
{
    policy_name=$1
    uci batch <<EOF
set mwan3.$policy_name=policy
set mwan3.$policy_name.last_resort='default'
set mwan3.$policy_name.add_by=modem
delete mwan3.$policy_name.use_member
EOF

}


flush_config(){
    config_load mwan3
    config_foreach remove_cb interface
    config_foreach remove_cb member
    config_foreach remove_cb policy
    config_foreach remove_cb rule
}

remove_cb(){
    local add_by
    config_get add_by $1 add_by
    if [ "$add_by" = "modem" ]; then
        uci delete mwan3.$1
    fi
}



gen_rule()
{   
    use_policy=$1
    rule_name=${family}_rule
    uci batch <<EOF
set mwan3.$rule_name=rule
set mwan3.$rule_name.family="$family"
set mwan3.$rule_name.sticky=$sticky_mode
set mwan3.$rule_name.proto='all'
set mwan3.$rule_name.use_policy=$use_policy
set mwan3.$rule_name.add_by=modem
EOF
    if [ -n "$sticky_timeout" ]; then
        uci set mwan3.$rule_name.timeout=$sticky_timeout
    fi
}

handle_config()
{
    config_get interface $1 member_interface
    config_get priority $1 member_priority
    config_get weight $1 member_weight
    config_get track_ip $1 member_track_ip
    echo $1
    append_if $interface "$track_ip"
    add_mwan3_member $interface $priority $weight m$interface
    append_mwan3_policy_member $family m$interface
}



/etc/init.d/mwan3 stop
flush_config
uci commit mwan3
config_load qmodem_mwan
family=$1
case $2 in
    "start")
        config_get sticky_mode global sticky_mode 0
        config_get sticky_timeout global sticky_timeout
        echo $sticky_mode $sticky_timeout
        init_mwan3_policy $family
        config_foreach handle_config $family
        gen_rule $family
        ;;
    "stop")
        rule_name=${family}_rule
        uci delete mwan3.$rule_name
        ;;
esac
uci commit mwan3
/etc/init.d/mwan3 start
