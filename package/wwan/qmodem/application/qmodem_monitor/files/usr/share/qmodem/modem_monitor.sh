#!/bin/sh
. /lib/functions.sh
. /usr/share/qmodem/modem_util.sh
# Envs
# Modem_ID
# Modem_ID=$1
# Method=$2
# Interval=$3
# Threshold=$4
# params1=$5
# params2=$6
parse_args(){
    while [ $# -gt 0 ]; do
        case $1 in
            --modem_id)
                Modem_ID=$2
                shift 2
                ;;
            --method)
                Method=$2
                shift 2
                ;;
            --interval)
                Interval=$2
                shift 2
                ;;
            --threshold)
                Threshold=$2
                shift 2
                ;;
            --ping-type)
                Ping_Type=$2
                shift 2
                ;;
            --ping-dest)
                Ping_Dest=$2
                shift 2
                ;;
            --ping-ip-version)
                Ping_IP_Version=$2
                shift 2
                ;;
            --http-url)
                Http_Url=$2
                shift 2
                ;;
            *)
                log "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
    [ -z "$Modem_ID" ] && log "Modem_ID is empty" && exit 1
    [ -z "$Method" ] && log "Method is empty" && exit 1
    [ -z "$Interval" ] && log "Interval is empty" && Interval=12
    [ -z "$Threshold" ] && log "Threshold is empty" && Threshold=5
}


log(){
    logger -t qmodem_monitor "$Modem_ID($Method): $@"
    #echo "$Modem_ID($Method): $@"
}

update_cfg(){
	config_load qmodem
	config_get AT_PORT "$Modem_ID" at_port
	config_get ALIAS "$Modem_ID" alias
	config_get USE_UBUS "$Modem_ID" use_ubus
	[ "$USE_UBUS" = "1" ] && use_ubus_flag="-u"
    log "loaded config for modem $Modem_ID: at_port=$AT_PORT, alias=$ALIAS, use_ubus=$USE_UBUS"
}

update_netcfg(){
	# if alias is set, network config name is alias else modem_cfg name
	config_load network
	if [ -n "$ALIAS" ]; then
		config_get NET_DEV "$ALIAS" ifname
        Ifv4="$ALIAS"
	else
		config_get NET_DEV "$Modem_ID" ifname
        Ifv4="$Modem_ID"
	fi
    [ -e "/sys/class/net/$NET_DEV" ] || config_get NET_DEV "$Ifv4" device
    Ifv6="$Ifv4"v6
    v4_info=$(ifstatus "$Ifv4" 2>/dev/null)
    v6_info=$(ifstatus "$Ifv6" 2>/dev/null)
    dns_v4=$(printf '%s\n' "$v4_info" | jq -r '."dns-server"[0] // empty')
    dns_v6=$(printf '%s\n' "$v6_info" | jq -r '."dns-server"[0] // empty')
    gateway_v4=$(printf '%s\n' "$v4_info" | jq -r '.route[]? | select(.target == "0.0.0.0") | .nexthop // empty' | head -n 1)
    gateway_v6=$(printf '%s\n' "$v6_info" | jq -r '.route[]? | select(.target == "::") | .nexthop // empty' | head -n 1)
    is_up_v4=$(printf '%s\n' "$v4_info" | jq -r '.up // false')
    is_up_v6=$(printf '%s\n' "$v6_info" | jq -r '.up // false')
}

wait_until_ready(){
    #nesseary variable: NET_DEV
    if [ -z "$NET_DEV" ] || [ ! -e "/sys/class/net/$NET_DEV" ]; then
        log "Network device is not ready: $NET_DEV"
        return 1
    fi
    return 0
}

# Monitor type

# Method: ping - Ping IP address to check connectivity
# Usage: ping <Target> or ping <Modem_ID>
# Parameters:
# <Type> - The type of target to ping. Can be "ip" or "modem".
# <Target> - The IP address or V4/V6 Interface name to ping.
# <Modem_ID> - The ID of the modem to use for pinging.
_ping_target() {
    local target="$1"

    [ -n "$target" ] && [ "$target" != "null" ] || return 1
    ping -c 1 -W 3 -I "$NET_DEV" "$target" >/dev/null 2>&1
}

_ping_public() {
    local ip_version="$1"
    local target targets

    if [ "$ip_version" = "6" ]; then
        targets="2606:4700:4700::1111 2001:4860:4860::8888"
    else
        targets="1.1.1.1 223.5.5.5"
    fi

    for target in $targets; do
        _ping_target "$target" && return 0
    done
    return 1
}

_ping() {
    local Type="$1"
    local Target="$2"

    case $Type in
        ip)
            _ping_target "$Target"
            status=$?
            ;;
        gateway)
            case $Target in
                4)
                    _ping_target "$gateway_v4" || _ping_public 4
                    status=$?
                ;;
                6)
                    _ping_target "$gateway_v6" || _ping_public 6
                    status=$?
                ;;
                *)
                    log "Invalid target type $Target"
                    status=1
                ;;
            esac
        ;;
        dns)
        case $Target in
            4)
                _ping_target "$dns_v4" || _ping_public 4
                status=$?
                ;;
            6)
                _ping_target "$dns_v6" || _ping_public 6
                status=$?
                ;;
            *)
                log "Invalid target type $Target"
                status=1
                ;;
        esac
        ;;
        *)
                log "Invalid type $Type"
                status=1
        ;;
    esac
    if [ "$status" -ne 0 ]; then
        log "Ping failed"
    fi
    return $status
}


# Method curl - Download file using curl
# Usage: curl <URL>
_curl() {
  local url="$1"
  # timeout 10s
  res=$(curl --connect-timeout 10 --interface "$NET_DEV" "$url" -o /dev/null --silent --show-error)
  status=$?
  if [ "$status" -ne 0 ]; then
    log "Curl failed: $res"
  fi
  return $status
}

# Method: signal - Get signal strength
# Usage: signal <Modem_ID>

# Method: operator registion - Get operator registration status
# Usage: operator <Modem_ID>

# Actions

# Action: log - Log the output to syslog
# Usage: log <MESSAGE>

# Action: notify - Send a notification
# Usage: notify <TITLE> <MESSAGE>

# Action: run_script - Run a custom script
# Usage: run_script <SCRIPT_PATH> [ARGUMENTS...]
run_scripts(){
    config_load qmodem
    config_list_foreach "$Modem_ID" script _run_script
}

_run_script(){
    local script_path=$1
    shift
    log "Run script: $script_path $@"
    $script_path $@
}


# Action: send_at_commands - Send AT commands to modem
# Usage: send_at_commands <Modem_ID>
send_at_commands() {
  config_load qmodem
  config_list_foreach "$Modem_ID" at_command _send_at_command
}

_send_at_command(){
    local at_command
    at_command=$1
    log "Send AT command: $at_command"
    res=$(at $AT_PORT $at_command)
    log "AT command response: $res"
}

# Action: switch_sim_slot - Switch SIM slot
# Usage: switch_sim_slot <Modem_ID>
switch_sim_slot() {
  local capabilities current_slot available_slots new_slot response success redial

  capabilities=$(ubus call qmodem get_sim_switch_capabilities '{"config_section": "'$Modem_ID'"}' 2>/dev/null)
  is_supported=$(printf '%s\n' "$capabilities" | jq -r '.supportSwitch // "0"')
  if [ "$is_supported" = "1" ]; then
    current_slot=$(ubus call qmodem get_sim_slot '{"config_section": "'$Modem_ID'"}' 2>/dev/null | jq -r '.sim_slot // empty')
    available_slots=$(printf '%s\n' "$capabilities" | jq -r '.simSlots[]?')
    new_slot=""
    for slot in $available_slots; do
        if [ "$slot" != "$current_slot" ]; then
            new_slot=$slot
            break
        fi
    done
    if [ -z "$current_slot" ] || [ -z "$new_slot" ]; then
        log "Cannot determine SIM slot: current=$current_slot available=$available_slots"
        return 1
    fi
    response=$(ubus call qmodem set_sim_slot '{"config_section": "'$Modem_ID'", "slot": "'$new_slot'"}' 2>/dev/null)
    success=$(printf '%s\n' "$response" | jq -r '.success // false')
    redial=$(printf '%s\n' "$response" | jq -r '.redial // empty')
    if [ "$success" = "true" ] && [ "$redial" = "0" ]; then
        log "Switch SIM slot from $current_slot to $new_slot"
        return 0
    fi
    log "Failed to switch SIM slot from $current_slot to $new_slot: $response"
    return 1
  else
    log "Switching SIM slot is not supported for modem $Modem_ID"
    return 1
  fi
}

# Parameters:
# <Modem_ID> - The ID of the modem to perform the action on.
# <Interval> - The interval in seconds between each monitoring check.
# <Threshold> - The condition to trigger the action.


loop(){
    case $Method in
        ping)
            case $Ping_Type in
                ip)
                    _ping $Ping_Type $Ping_Dest
                    status=$?
                    ;;
                gateway|dns)
                    _ping $Ping_Type $Ping_IP_Version
                    status=$?
                    ;;
                *)
                    log "Invalid ping type: $Ping_Type"
                    status=1
                    ;;
            esac
            ;;
        curl)
            _curl $Http_Url
            status=$?
            ;;
        *)
            log "Invalid method"
            status=1
            ;;
    esac
    return $status
}

run_action(){
    Action=$1
    case $Action in
        switch_sim_slot)
            switch_sim_slot
            ;;
        send_at_commands)
            send_at_commands
            ;;
        run_scripts)
            run_scripts
            ;;
        *)
            log "Invalid action $Action"
            ;;
    esac
}

run_actions(){
    config_load qmodem
    config_list_foreach "$Modem_ID" monitor_action run_action
}

parse_args "$@"
update_cfg
update_netcfg
log "Start monitoring $Modem_ID($Method) with interval $Interval and threshold $Threshold"
failed_count=0
readiness_grace=$Threshold
while true; do
    update_netcfg
    if ! wait_until_ready && [ "$readiness_grace" -gt 0 ]; then
        readiness_grace=$((readiness_grace - 1))
        failed_count=0
        sleep "$Interval"
        continue
    fi
    readiness_grace=0
    loop
    status=$?
    if [ "$status" -ne 0 ]; then
        failed_count=$((failed_count + 1))
        log "Failed count: $failed_count Threshold: $Threshold"
    else
        failed_count=0
    fi
    sleep "$Interval"
    
    if [ "$failed_count" -ge "$Threshold" ]; then
        # log last failure time
        log "$Method failed $failed_count times"
        run_actions
        failed_count=0
        sleep 60
    fi
done
