#!/bin/sh
source /lib/functions.sh
#运行目录
MODEM_RUNDIR="/var/run/qmodem"
SCRIPT_DIR="/usr/share/qmodem"

modem_config=$1
mkdir -p "${MODEM_RUNDIR}/${modem_config}_dir"
log_file="${MODEM_RUNDIR}/${modem_config}_dir/dial_log"
debug_subject="modem_dial"
source "${SCRIPT_DIR}/generic.sh"
touch $log_file

exec_pre_dial()
{
    section=$1
    /usr/share/qmodem/modem_hook.sh $section pre_dial
}

get_led()
{
    config_foreach get_led_by_slot modem-slot
}

get_led_by_slot()
{
    local cfg="$1"
    config_get slot "$cfg" slot
    if [ "$modem_slot" = "$slot" ];then
        config_get sim_led "$cfg" sim_led
        config_get net_led "$cfg" net_led
    fi
}

get_associate_ethernet_by_path()
{
    local cfg="$1"
    config_get slot "$cfg" slot
    config_get ethernet "$cfg" ethernet
    if [ "$modem_slot" = "$slot" ];then
        config_get ethernet_5g "$cfg" ethernet_5g
    fi
}

set_led()
{
    local type=$1
    local modem_config=$2
    local value=$3
    get_led "$modem_slot"
    case $type in
        sim)
            [ -z "$sim_led" ] && return
            echo $value > /sys/class/leds/$sim_led/brightness
            ;;
        net)
            [ -z "$net_led" ] && return
            cfg_name=$(echo $net_led |tr ":" "_") 
            uci batch << EOF
set system.n${cfg_name}=led
set system.n${cfg_name}.name=${modem_slot}_net_indicator
set system.n${cfg_name}.sysfs=${net_led}
set system.n${cfg_name}.trigger=netdev
set system.n${cfg_name}.dev=${modem_netcard}
set system.n${cfg_name}.mode="tx rx"
commit system
EOF

            /etc/init.d/led restart
            ;;
    esac
}

unlock_sim()
{
    pin=$1
    sim_lock_file="/var/run/qmodem/${modem_config}_dir/pincode"
    lock ${sim_lock_file}.lock
    if [ -f $sim_lock_file ] && [ "$pin" == "$(cat $sim_lock_file)"];then
        m_debug "pin code is already try"
    else
        
        res=$(at "$at_port" "AT+CPIN=\"$pin\"")
        case "$?" in
            0)
                m_debug "unlock sim card with pin code $pin success"
                ;;
            *)
                echo $pin > $sim_lock_file
                m_debug "info" "unlock sim card with pin code $pin failed,block try until nextboot"
                ;;
        esac
    fi
    lock -u ${sim_lock_file}.lock

}

update_config()
{
    config_load qmodem
    config_get state $modem_config state
    config_get enable_dial $modem_config enable_dial
    config_get modem_path $modem_config path
    config_get dial_tool $modem_config dial_tool
    config_get pdp_type $modem_config pdp_type
    config_get network_bridge $modem_config network_bridge
    config_get metric $modem_config metric
    config_get at_port $modem_config at_port
    config_get manufacturer $modem_config manufacturer
    config_get platform $modem_config platform
    config_get define_connect $modem_config define_connect
    config_get ra_master $modem_config ra_master
    config_get extend_prefix $modem_config extend_prefix
    config_get en_bridge $modem_config en_bridge
    config_get do_not_add_dns $modem_config do_not_add_dns
    config_get dns_list $modem_config dns_list
    config_get connect_check $modem_config connect_check
    config_get global_dial main enable_dial
    # config_get ethernet_5g u$modem_config ethernet 转往口获取命令更新，待测试
    config_foreach get_associate_ethernet_by_path modem-slot
    modem_slot=$(basename $modem_path)
    config_get alias $modem_config alias
    driver=$(get_driver)
    update_sim_slot
    case $sim_slot in
        1)
        config_get apn $modem_config apn "auto"
        config_get username $modem_config username
        config_get password $modem_config password
        config_get auth $modem_config auth
        config_get pincode $modem_config pincode
        ;;
        2)
        config_get apn $modem_config apn2
        config_get username $modem_config username2
        config_get password $modem_config password2
        config_get auth $modem_config auth2
        config_get pincode $modem_config pincode2
        [ -z "$apn" ] && config_get apn $modem_config apn "auto"
        [ -z "$username" ] && config_get username $modem_config username
        [ -z "$password" ] && config_get password $modem_config password
        [ -z "$auth" ] && config_get auth $modem_config auth
        [ -z "$pin" ] && config_get pincode $modem_config pincode
        ;;
        *)
            config_get apn $modem_config apn
            config_get username $modem_config username
            config_get password $modem_config password
            config_get auth $modem_config auth
            config_get pincode $modem_config pincode
            ;;
    esac
    modem_net=$(find $modem_path -name net |tail -1)
    modem_netcard=$(ls $modem_net)
    interface_name=$modem_config
    [ -n "$alias" ] && interface_name=$alias
    interface6_name=${interface_name}v6
}

check_dial_prepare()
{
    cpin=$(at "$at_port" "AT+CPIN?")
    get_sim_status "$cpin"
    [ "$manufacturer" = "neoway" ] && {
        local res
        res=$(at $at_port 'AT+SIMCROSS=1,1;$MYCCID' | grep -q "ERROR")
        if [ $? -ne 0 ]; then
            sim_state_code="1"
        else
            sim_state_code="0"
        fi
    }
    case $sim_state_code in
        "0")
            m_debug "info sim card is miss"
            ;;
        "1")
            m_debug "info sim card is ready"
            sim_fullfill=1
            ;;
        "2")
            m_debug "pin code required"
            [ -n "$pincode" ] && unlock_sim $pincode
            ;;
        *)
            m_debug "info sim card state is $sim_state_code"
            ;;
    esac
    
    if [ "$sim_fullfill" = "1" ];then
        set_led "sim" $modem_config 255
    else
        set_led "sim" $modem_config 0
    fi
    if [ -n "$modem_netcard" ] && [ -d "/sys/class/net/$modem_netcard" ];then
        netdev_fullfill=1
    else
        netdev_fullfill=0
    fi

    if [ "$enable_dial" = "1" ] && [ "$sim_fullfill" = "1" ] && [ "$state" != "disabled" ] ;then
        config_fullfill=1
    fi
    if [ "$config_fullfill" = "1" ] && [ "$sim_fullfill" = "1" ] && [ "$netdev_fullfill" = "1" ] ;then
        at "$at_port" "AT+CFUN=1"
        return 1
    else
        return 0
    fi
}

check_ip()
{
    case $manufacturer in
            "quectel")
                case $platform in
                    "qualcomm")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "unisoc")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "lte")
                        if [ "$define_connect" = "3" ];then
                            check_ip_command="AT+CGPADDR=3"
                        else
                            check_ip_command="AT+CGPADDR=1"
                        fi
                        ;;
                    
                esac
                ;;
            "fibocom")
                case $platform in
                    "qualcomm")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "unisoc")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "lte")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "mediatek")
                        check_ip_command="AT+CGPADDR=3"
                        ;;
                esac
                ;;
            "simcom")
                case $platform in
                    "qualcomm")
                        check_ip_command="AT+CGPADDR=6"
                        ;;
                esac
                ;;
            "meig")
                case $platform in
                    "qualcomm")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                    "unisoc")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                esac
                ;;
            "neoway")
                case $platform in
                    "unisoc")
                        check_ip_command="AT+CGPADDR=1"
                        ;;
                esac
                ;;
            *)
                check_ip_command="AT+CGPADDR=1"
                ;;
        esac

        if [ "$driver" = "mtk_pcie" ]; then
            mbim_port=$(echo "$at_port" | sed 's/at/mbim/g')
            local config=$(umbim -d $mbim_port config)
            ipaddr=$(echo "$config" | grep "ipv4address:" | awk '{print $2}' | cut -d'/' -f1)
            ipaddr="$ipaddr $(echo "$config" | grep "ipv6address:" | awk '{print $2}' | cut -d'/' -f1)"
        else
            ipaddr=$(at "$at_port" "$check_ip_command" | grep +CGPADDR:)
        fi

        if [ -n "$ipaddr" ];then
            ipv6=$(echo $ipaddr | grep -oE "\b([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}\b")
            ipv4=$(echo $ipaddr | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
            if [ "$manufacturer" = "simcom" ];then
                ipv4=$(echo $ipaddr | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | grep -v "0\.0\.0\.0" | head -n 1)
                ipv6=$(echo $ipaddr | grep -oE "\b([0-9a-fA-F]{0,4}.){2,7}[0-9a-fA-F]{0,4}\b")
            fi
            disallow_ipv4="0.0.0.0"
            #remove the disallow ip
            if [ "$ipv4" == *"$disallow_ipv4"* ];then
                ipv4=""
            fi
            connection_status=0
            if [ -n "$ipv4" ];then
                connection_status=1
            fi
            if [ -n "$ipv6" ];then
                connection_status=2
            fi
            if [ -n "$ipv4" ] && [ -n "$ipv6" ];then
                connection_status=3
            fi
        else
            connection_status="-1"
            m_debug "at port response unexpected $ipaddr"
        fi
}

check_connection()
{
    [ "$connection_status" = "0" ] || [ "$connection_status" = "-1" ] && return 0
    if [ -n "$ipv4" ] && [ -n "$modem_netcard" ]; then
        for i in 1 2; do
            if ping -I "$modem_netcard" -w 1 1.1.1.1 >/dev/null 2>&1 || 
               ping -I "$modem_netcard" -w 2 8.8.8.8 >/dev/null 2>&1; then
                break
            fi
            if [ $i -eq 2 ]; then
                m_debug "IPv4 connection test failed, will redial"
                return 1
            fi
            sleep 1
        done
        local ifup_time=$(ubus call network.interface.$interface6_name status 2>/dev/null | jsonfilter -e '@.uptime' 2>/dev/null || echo 0)
        if [ "$ifup_time" -gt 5 ] && [ "$pdp_type" = "ipv4v6" ]; then
            rdisc6 $origin_device &
            ndisc6 fe80::1 $origin_device &
        fi
    fi
    return 0
}

append_to_fw_zone()
{
    local fw_zone=$1
    local if_name=$2
    source /etc/os-release
    local os_version=${VERSION_ID:0:2}
    if [ "$os_version" -le 21 ];then
        has_ifname=0
        origin_line=$(uci -q get firewall.@zone[${fw_zone}].network)
        for i in $origin_line
        do
            if [ "$i" = "$if_name" ];then
                has_ifname=1
            fi
        done
        if [ -n "$origin_line" ] && [ "$has_ifname" -eq 0 ];then
            uci set firewall.@zone[${fw_zone}].network="${origin_line} ${if_name}"
        elif [ -z "$origin_line" ];then
            uci set firewall.@zone[${fw_zone}].network="${if_name}"
        fi
    else
        uci add_list firewall.@zone[${fw_zone}].network=${if_name}
    fi
}

set_if()
{
    fw_reload_flag=0
    dhcp_reload_flag=0
    network_reload_flag=0
    #check if exist
    proto="dhcp"
    protov6="dhcpv6"
    case $manufacturer in
        "quectel")
            case $platform in
                "unisoc")
                    case $driver in
                        "mbim")
                            proto="none"
                            protov6="none"
                            ;;
                        esac
                    ;;
            esac
            ;; 
        "fibocom")
            case $platform in
                "mediatek")
                    proto="static"
                    protov6="dhcpv6"
                    ;;
                esac
            ;;
    esac
    case $pdp_type in
        "ip")
            env4="1"
            env6="0"
            ;;
        "ipv6")
            env4="0"
            env6="1"
            ;;
        "ipv4v6")
            env4="1"
            env6="1"
            ;;
    esac
    interface=$(uci -q get network.$interface_name)
    interfacev6=$(uci -q get network.$interface6_name)
    if [ "$env4" -eq 1 ];then
        if [ -z "$inetrface" ];then
            uci set network.${interface_name}=interface
            uci set network.${interface_name}.modem_config="${modem_config}"
            uci set network.${interface_name}.proto="${proto}"
            uci set network.${interface_name}.defaultroute='1'
            uci set network.${interface_name}.metric="${metric}"
            uci del network.${interface_name}.dns
            if [ -n "$dns_list" ];then
                uci set network.${interface_name}.peerdns='0'
                for dns in $dns_list;do
                    uci add_list network.${interface_name}.dns="${dns}"
                done
            else
                uci del network.${interface_name}.peerdns
            fi
            local num=$(uci show firewall | grep "name='wan'" | wc -l)
            local wwan_num=$(uci -q get firewall.@zone[$num].network | grep -w "${interface_name}" | wc -l)
            if [ "$wwan_num" = "0" ]; then
                append_to_fw_zone $num ${interface_name}
            fi
            network_reload_flag=1
            firewall_reload_flag=1
            m_debug "create interface $interface_name with proto $proto and metric $metric"
        fi
    else
        if [ -n "$interface" ];then
            uci delete network.${interface_name}
            network_reload_flag=1
            m_debug "delete interface $interface_name"
        fi
    fi
    if [ "$env6" -eq 1 ];then
        if [ -z "$interfacev6" ];then
            uci set network.lan.ipv6='1'
            uci set network.lan.ip6assign='64'
            uci set network.${interface6_name}='interface'
            uci set network.${interface6_name}.modem_config="${modem_config}"
            uci set network.${interface6_name}.proto="${protov6}"
            uci set network.${interface6_name}.ifname="@${interface_name}"
            uci set network.${interface6_name}.device="@${interface_name}"
            uci set network.${interface6_name}.metric="${metric}"
            
            local wwan6_num=$(uci -q get firewall.@zone[$num].network | grep -w "${interface6_name}" | wc -l)
            if [ "$wwan6_num" = "0" ]; then
                append_to_fw_zone $num ${interface6_name}
            fi
            network_reload_flag=1
            firewall_reload_flag=1
            m_debug "create interface $interface6_name with proto $protov6 and metric $metric"
        fi
        if [ "$ra_master" = "1" ];then
            uci set dhcp.${interface6_name}='dhcp'
            uci set dhcp.${interface6_name}.interface="${interface6_name}"
            uci set dhcp.${interface6_name}.ra='relay'
            uci set dhcp.${interface6_name}.ndp='relay'
            uci set dhcp.${interface6_name}.master='1'
            uci set dhcp.${interface6_name}.ignore='1'
            uci set dhcp.lan.ra='relay'
            uci set dhcp.lan.ndp='relay'
            uci set dhcp.lan.dhcpv6='relay'
            dhcp_reload_flag=1
        elif [ "$extend_prefix" = "1" ];then
            uci set network.${interface6_name}.extendprefix=1
            dhcpv6=$(uci -q get dhcp.${interface6_name})
            if [ -n "$dhcpv6" ];then
                uci delete dhcp.${interface6_name}
                dhcp_reload_flag=1
            fi
        else
            dhcpv6=$(uci -q get dhcp.${interface6_name})
            if [ -n "$dhcpv6" ];then
                uci delete dhcp.${interface6_name}
                dhcp_reload_flag=1
            fi
        fi
    else
        if [ -n "$interfacev6" ];then
            uci delete network.${interface6_name}
            network_reload_flag=1
            dhcpv6=$(uci -q get dhcp.${interface6_name})
            if [ -n "$dhcpv6" ];then
                dhcp_reload_flag=1
            fi
            m_debug "delete interface $interface6_name"
        fi
    fi
    
    if [ "$network_reload_flag" -eq 1 ];then
        uci commit network
        ifup ${interface_name}
        ifup ${interface6_name}
        m_debug "network reload"
    fi
    if [ "$firewall_reload_flag" -eq 1 ];then
        uci commit firewall
        /etc/init.d/firewall restart
        m_debug "firewall reload"
    fi
    if [ "$dhcp_reload_flag" -eq 1 ];then
        uci commit dhcp
        /etc/init.d/dhcp restart
        m_debug "dhcp reload"
    fi


    set_modem_netcard=$modem_netcard
    if [ -z "$set_modem_netcard" ];then
        m_debug "no netcard found"
    fi
    ethernet_check=$(handle_5gethernet)
    if [ -n "$ethernet_check" ] && [ -n "/sys/class/net/$ethernet_5g" ] && [ -n "$ethernet_5g" ];then
        set_modem_netcard=$ethernet_5g
    fi
    #set led
    set_led "net" $modem_config $set_modem_netcard
    origin_netcard=$(uci -q get network.$interface_name.ifname)
    origin_device=$(uci -q get network.$interface_name.device)
    origin_metric=$(uci -q get network.$interface_name.metric)
    origin_proto=$(uci -q get network.$interface_name.proto)
    if [ "$origin_netcard" == "$set_modem_netcard" ] && [ "$origin_device" == "$set_modem_netcard" ] && [ "$origin_metric" == "$metric" ] && [ "$origin_proto" == "$proto" ];then
        m_debug "interface $interface_name already set to $set_modem_netcard"
    else
        uci set network.${interface_name}.ifname="${set_modem_netcard}"
        uci set network.${interface_name}.device="${set_modem_netcard}"
        uci set network.${interface_name}.modem_config="${modem_config}"
        if [ "$env4" -eq 1 ];then
            uci set network.${interface_name}.proto="${proto}"
            uci set network.${interface_name}.metric="${metric}"
        fi
        if [ "$env6" -eq 1 ];then
            uci set network.${interface6_name}.proto="${protov6}"
            uci set network.${interface6_name}.metric="${metric}"
        fi
        uci commit network
        ifup ${interface_name}
        m_debug "set interface $interface_name to $set_modem_netcard"
    fi
}

flush_if()
{
    # uci delete network.${interface_name}
    # uci delete network.${interface6_name}
    # uci delete dhcp.${interface6_name}
    # uci commit network
    # uci commit dhcp
    # set_led "net" $modem_config
    # set_led "sim" $modem_config 0
    # m_debug "delete interface $interface_name"
    config_load network
    remove_target="$modem_config"
    config_foreach flush_ip_cb "interface"
    set_led "net" $modem_config
    set_led "sim" $modem_config 0
    m_debug "delete interface $interface_name"
    uci commit network
    uci commit dhcp
}

flush_ip_cb()
{
    local network_cfg=$1
    local bind_modem_config
    config_get bind_modem_config "$network_cfg" modem_config
    if [ "$remove_target" = "$bind_modem_config" ];then
        uci delete network.$network_cfg
    fi
    
}


dial(){
    update_config
    m_debug "modem_path=$modem_path,driver=$driver,interface=$interface_name,at_port=$at_port,using_sim_slot:$sim_slot,dns_list:$dns_list"
    while [ "$dial_prepare" != 1 ] ; do
        sleep 5
        update_config
        check_dial_prepare
        dial_prepare=$?
    done
    set_if
    m_debug "dialing $modem_path driver $driver"
    exec_pre_dial $modem_config
    case $driver in
        "qmi")
            qmi_dial
            ;;
        "mbim")
            mbim_dial
            ;;
        "mhi")
            mhi_dial
            ;;
        "ncm")
            at_dial_monitor
            ;;
        "ecm")
            at_dial_monitor
            ;;
        "rndis")
            at_dial_monitor
            ;;
        "mtk_pcie")
            at_dial_monitor
            ;;
        *)
            mbim_dial
            ;;
    esac
}

wwan_hang()
{
    m_debug "wwan_hang"
}


ecm_hang()
{
    case "$manufacturer" in
        "quectel")
            at_command="AT+QNETDEVCTL=1,2,1"
            ;;
        "fibocom")
            case "$platform" in
                "mediatek")
                    at_command="AT+CGACT=0,3"
                    ;;
                *)
                    at_command="AT+GTRNDIS=0,1"
                    ;;
            esac
            ;;
        "meig")
            at_command='AT$QCRMCALL=0,0,1,2,1'
            ;;
        "huawei")
            at_command="AT^NDISDUP=0,0"
            ;;
        "neoway")
            delay=3
            at_command='AT$MYUSBNETACT=0,0'
            ;;
        *)
            at_command="ATI"
            ;;
    esac
    fastat "${at_port}" "${at_command}"
    [ -n "$delay" ] && sleep "$delay"
}

hang()
{
    m_debug "hang up $modem_path driver $driver"
    case $driver in
        "ncm")
            ecm_hang
            ;;
        "ecm")
            ecm_hang
            ;;
        "rndis")
            ecm_hang
            ;;
        "qmi")
            wwan_hang
            ;;
        "mbim")
            wwan_hang
            ;;
        "mhi")
            wwan_hang
            ;;
    esac
    flush_if
}

mbim_dial(){
    if [ -z "$apn" ];then
        apn="auto"
    fi
    qmi_dial
}

mhi_dial()
{
    qmi_dial
}
qmi_dial()
{
    cmd_line="quectel-CM"
    [ -e "/usr/bin/quectel-CM-M" ] && cmd_line="quectel-CM-M"
    case $pdp_type in
        "ip") cmd_line="$cmd_line -4" ;;
        "ipv6") cmd_line="$cmd_line -6" ;;
        "ipv4v6") cmd_line="$cmd_line -4 -6" ;;
        *) cmd_line="$cmd_line -4 -6" ;;
    esac

    if [ "$network_bridge" = "1" ]; then
        cmd_line="$cmd_line -b"
    fi
    if [ -n "$apn" ]; then
        cmd_line="$cmd_line -s $apn"
    fi
    if [ -n "$username" ]; then
        cmd_line="$cmd_line $username"
    fi
    if [ -n "$password" ]; then
        cmd_line="$cmd_line $password"
    fi
    if [ "$auth" != "none" ]; then
        cmd_line="$cmd_line $auth"
    fi
    if [ -n "$modem_netcard" ]; then
    qmi_if=$modem_netcard
    #if is wwan* ,use the first part of the name
    if  [[ "$modem_netcard" = "wwan"* ]];then
        qmi_if=$(echo "$modem_netcard" | cut -d_ -f1)
    fi
    #if is rmnet* ,use the first part of the name
    if [[ "$modem_netcard" = "rmnet"* ]];then
        qmi_if=$(echo "$modem_netcard" | cut -d. -f1)
    fi
        cmd_line="${cmd_line} -i ${qmi_if}"
    fi
    if [ "$en_bridge" = "1" ];then
        cmd_line="${cmd_line} -b"
    fi
    if [ "$do_not_add_dns" = "1" ];then
        cmd_line="${cmd_line} -D"
    fi
    if [ -e "/usr/bin/quectel-CM-M" ];then
        [ -n "$metric" ] && cmd_line="$cmd_line -d -M $metric"
    else
        [ -n "$metric" ] && cmd_line="$cmd_line"
    fi
    cmd_line="$cmd_line -f $log_file"
    m_debug "dialing $cmd_line"
    exec $cmd_line
    
    
}

at_dial()
{
    if [ -z "$apn" ];then
        apn="auto"
    fi
    if [ -z "$pdp_type" ];then
        pdp_type="IP"
    fi
    local at_command='AT+COPS=0,0'
    tmp=$(at "${at_port}" "${at_command}")
    pdp_type=$(echo $pdp_type | tr 'a-z' 'A-Z')
    case $manufacturer in
        "quectel")
            case $platform in
                "qualcomm")
                    at_command="AT+QNETDEVCTL=1,3,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "unisoc")
                    at_command="AT+QNETDEVCTL=1,3,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "hisilicon")
                    at_command="AT+QNETDEVCTL=1,1,1"
                    cgdcont_command=""
                    ;;
                "lte")
                    if [ "$define_connect" = "3" ];then
                        at_command="AT+QNETDEVCTL=3,3,1"
                        cgdcont_command="AT+CGDCONT=3,\"$pdp_type\",\"$apn\""
                    else
                        at_command="AT+QNETDEVCTL=1,3,1"
                        cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    fi
                    ;;
                *)
                    at_command="AT+QNETDEVCTL=1,3,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
            esac
            ;;
        "fibocom")
            case $platform in
                "qualcomm")
                    at_command="AT+GTRNDIS=1,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "unisoc")
                    at_command="AT+GTRNDIS=1,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "lte")
                    at_command="AT+GTRNDIS=1,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
                "mediatek")
                    delay=3
                    if [ "$apn" = "auto" ];then
                        apn="cbnet"
                    fi
                    at_command="AT+CGACT=1,3"
                    cgdcont_command="AT+CGDCONT=3,\"$pdp_type\",\"$apn\""
                    ;;
            esac
            ;;
        "huawei")
            case $platform in
                "hisilicon")
                    at_command="AT^NDISDUP=1,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\""
                    ;;
            esac
            ;;
        "simcom")
            case $platform in
                "qualcomm")
                    local cnmp=$(at ${at_port} "AT+CNMP?" | grep "+CNMP:" | sed 's/+CNMP: //g' | sed 's/\r//g')
                    at_command="AT+CNMP=$cnmp;+CNWINFO=1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
            esac
            ;;
        "meig")
            case $platform in
                "qualcomm")
                    at_command='AT$QCRMCALL=1,0,1,2,1'
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
            esac
            ;;
        "neoway")
            case $platform in
                "unisoc")
                    at_command='AT$MYUSBNETACT=0,1'
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
            esac
            ;;
        "telit")
            case $platform in
                "qualcomm")
                    at_command="AT#ICMAUTOCONN=1,1"
                    cgdcont_command="AT+CGDCONT=1,\"$pdp_type\",\"$apn\""
                    ;;
            esac
            ;;
    esac
    m_debug "dialing vendor:$manufacturer;platform:$platform; $cgdcont_command ; $at_command"
    at "${at_port}" "${cgdcont_command}"
    fastat "$at_port" "$at_command"
    [ -n "$delay" ] && sleep "$delay"
    if [ "$driver" = "mtk_pcie" ];then
        fastat "$at_port" "AT+CGACT=0,3"
        mbim_port=$(echo "$at_port" | sed 's/at/mbim/g')
        umbim -d $mbim_port disconnect
        sleep 1
        umbim -d $mbim_port connect 0
    fi
}

ip_change_fm350()
{
    m_debug "ip_change_fm350"
    local public_dns1_ipv4="223.5.5.5"
    local public_dns2_ipv4="119.29.29.29"
    local netmask="255.255.255.0"

    if [ "$driver" = "mtk_pcie" ]; then
        mbim_port=$(echo "$at_port" | sed 's/at/mbim/g')

        local config=$(umbim -d $mbim_port config)
        ipv4_config=$(echo "$config" | grep "ipv4address:" | awk '{print $2}' | cut -d'/' -f1)
        gateway=$(echo "$config" | grep "ipv4gateway:" | awk '{print $2}')

        ipv4_dns1=$(echo "$config" | grep "ipv4dnsserver:" | head -n 1 | awk '{print $2}')
        ipv4_dns2=$(echo "$config" | grep "ipv4dnsserver:" | tail -n 1 | awk '{print $2}')
        [ -z "$ipv4_dns1" ] && ipv4_dns1="$public_dns1_ipv4"
        [ -z "$ipv4_dns2" ] && ipv4_dns2="$public_dns2_ipv4"
        # m_debug "umbim config: ipv4=$ipv4_config, gateway=$gateway, netmask=$netmask, dns1=$ipv4_dns1, dns2=$ipv4_dns2"
    else
        at_command="AT+CGPADDR=3"
        response=$(at ${at_port} ${at_command})
        ipv4_config=$(echo "$response" | grep "+CGPADDR:" | grep -o '"[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+"' | head -1 | tr -d '"')
        gateway="${ipv4_config%.*}.1"

        response=$(at ${at_port} "AT+GTDNS=3")
        ipv4_dns=$(echo "$response" | grep "+GTDNS:" | head -1)
        ipv4_dns1=$(echo "$ipv4_dns" | grep -o '"[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+"' | head -1 | tr -d '"')
        ipv4_dns2=$(echo "$ipv4_dns" | grep -o '"[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+"' | tail -1 | tr -d '"')
        [ -z "$ipv4_dns1" ] && ipv4_dns1="$public_dns1_ipv4"
        [ -z "$ipv4_dns2" ] && ipv4_dns2="$public_dns2_ipv4"
        uci_ipv4=$(uci -q get network.$interface_name.ipaddr)
    fi
    uci set network.${interface_name}.proto='static'
    uci set network.${interface_name}.ipaddr="${ipv4_config}"
    uci set network.${interface_name}.netmask="${netmask}"
    uci set network.${interface_name}.gateway="${gateway}"
    uci set network.${interface_name}.peerdns='0'
    uci -q del network.${interface_name}.dns
    uci add_list network.${interface_name}.dns="${ipv4_dns1}"
    uci add_list network.${interface_name}.dns="${ipv4_dns2}"
    uci commit network
    ifdown ${interface_name}
    ifup ${interface_name}
    m_debug "set interface $interface_name to $ipv4_config"

}

handle_5gethernet()
{
    case $manufacturer in
        "quectel")
            case $platform in
                "qualcomm")
                    quectel_qualcomm_ethernet
                    ;;
                "unisoc")
                    quectel_unisoc_ethernet
                    ;;
            esac
            ;;
    esac
}

quectel_unisoc_ethernet()
{
    case "$driver" in
        "ncm"|\
        "ecm"|\
        "rndis")
            check_ethernet_cmd="AT+QCFG=\"ethernet\""
            time=0
            while [ $time -lt 5 ]; do
                result=$(at $at_port $check_ethernet_cmd | grep "+QCFG:")
                if [ -n "$result" ]; then
                    if [ -n "$(echo $result | grep "ethernet\",1")" ]; then
                        echo "1"
                        m_debug "5G Ethernet mode is enabled"
                        break
                    fi
                fi
                sleep 5
                time=$((time+1))
            done
        ;;
    esac
}

quectel_qualcomm_ethernet()
{
     case "$driver" in
        "mbim")
            eth_driver_at="AT+QETH=\"eth_driver\""
            data_interface_at="AT+QCFG=\"data_interface\""
            ehter_driver_expect="\"r8125\",1"
            data_interface_expect="\"data_interface\",1"

            time=0
            while [ $time -lt 5 ]; do
                eth_driver_result=$(at $at_port $eth_driver_at | grep "+QETH:")
                time=$(($time+1))
                sleep 1
                if [ -n "$eth_driver_result" ];then
                    break
                fi
            done
            time=0
            while [ $time -lt 5 ]; do
                data_interface_result=$(at $at_port $data_interface_at | grep "+QCFG:")
                time=$(($time+1))
                sleep 1
                if [ -n "$data_interface_result" ];then
                    break
                fi
            done
            eth_driver_pass=$(echo $eth_driver_result | grep "$ehter_driver_expect")
            data_interface_pass=$(echo $data_interface_result | grep "$data_interface_expect")
            if  [ -n "$eth_driver_pass" ] && [ -n "$data_interface_pass" ];then
                echo "1"
                m_debug "5G Ethernet mode is enabled"
            fi
            ;;
    esac
}

handle_ip_change()
{
    export ipv4
    export ipv6
    export connection_status
    m_debug  "ip changed from $ipv6_cache,$ipv4_cache to $ipv6,$ipv4"
    case $manufacturer in
        "fibocom")
            case $platform in
                "mediatek")
                    ip_change_fm350
                    ;;
            esac
            ;;
    esac
}

check_logfile_line()
{
    local line=$(wc -l $log_file | awk '{print $1}')
    if [ $line -gt 300 ];then
        echo "" > $log_file
        m_debug  "log file line is over 300,clear it"
    fi
}

unexpected_response_count=0
at_dial_monitor()
{
    at_dial
    ipv4_cache=$ipv4
    ipv6_cache=$ipv6
    sleep 5
    while true; do
        check_ip
        case $connection_status in
            0)
                at_dial
                sleep 3
                ;;
            -1)
                unexpected_response_count=$((unexpected_response_count+1))
                if [ $unexpected_response_count -gt 3 ]; then
                    at_dial
                    unexpected_response_count=0
                fi
                sleep 5
                ;;
            *)
                if [ "$ipv4" != "$ipv4_cache" ] || [ "$ipv6" != "$ipv6_cache" ]; then
                    handle_ip_change
                    ipv4_cache=$ipv4
                    ipv6_cache=$ipv6
                fi
                [ "$connect_check" -eq 1 ] && { sleep 5; check_connection || { hang && at_dial; }; } || sleep 15
                ;;
        esac
        check_logfile_line
    done
}

case "$2" in
    "hang")
        debug_subject="modem_hang"
        update_config
        hang;;
    "dial")
        case "$state" in
            "disabled")
                debug_subject="modem_hang"
                hang;;
            *)
                dial;;
        esac
esac
