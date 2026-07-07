#!/bin/sh

. /usr/share/libubox/jshn.sh

QMODEM_UBUS_OBJECT="qmodem"
QMODEM_UBUS_METHOD="save_stats"

is_valid_interval()
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

build_payload()
{
    local config_section="$1"

    json_init
    json_add_string config_section "$config_section"
    json_dump
}

save_usage_stats()
{
    local config_section="$1"
    local payload response status

    payload=$(build_payload "$config_section")
    response=$(ubus call "$QMODEM_UBUS_OBJECT" "$QMODEM_UBUS_METHOD" "$payload" 2>/dev/null) || {
        logger -t qmodem_usage_stats "ubus call failed for $config_section"
        return 1
    }

    status=$(jsonfilter -s "$response" -e '@.result.status' 2>/dev/null)
    if [ "$status" != "1" ]; then
        logger -t qmodem_usage_stats "failed to persist usage stats for $config_section"
        return 1
    fi
}

loop()
{
    local interval="$1"
    local config_section="$2"

    is_valid_interval "$interval" || exit 1
    [ -n "$config_section" ] || exit 1

    while true; do
        save_usage_stats "$config_section"
        sleep "$interval"
    done
}

run_once()
{
    local config_section="$1"

    [ -n "$config_section" ] || exit 1

    save_usage_stats "$config_section"
}

case "$1" in
    loop)
        shift
        loop "$@"
        ;;
    run_once)
        shift
        run_once "$@"
        ;;
    *)
        echo "Usage: $0 {loop <interval> <config_section>|run_once <config_section>}" >&2
        exit 1
        ;;
esac
