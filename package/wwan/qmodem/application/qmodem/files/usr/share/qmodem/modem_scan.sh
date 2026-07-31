#!/bin/sh

action="$1"
config="$2"
slot_type="$3"
delay="$4"

case "$slot_type" in
    --delay)
        delay="$4"
        slot_type=""
        ;;
esac

scanc()
{
    /usr/bin/modem_scanc "$@"
    rc=$?
    if [ "$rc" -eq 2 ] && [ -x /etc/init.d/qmodem_init ]; then
        /etc/init.d/qmodem_init start >/dev/null 2>&1
        sleep 1
        /usr/bin/modem_scanc "$@"
        rc=$?
    fi
    return "$rc"
}

case "$action" in
    add)
        [ -n "$config" ] && [ -n "$slot_type" ] || exit 1
        scanc add "$config" "$slot_type" "${delay:-0}"
        exit $?
        ;;
    remove)
        [ -n "$config" ] || exit 1
        scanc remove "$config" "${delay:-0}"
        exit $?
        ;;
    disable)
        [ -n "$config" ] || exit 1
        scanc disable "$config" "${delay:-0}"
        exit $?
        ;;
    scan)
        # Old format: modem_scan.sh scan [delay] [usb|pcie]
        # Also accept: modem_scan.sh scan [usb|pcie|all]
        case "$config" in
            usb|pcie|all)
                scanc scan "$config" "${delay:-0}"
                exit $?
                ;;
        esac
        if [ -n "$config" ] && [ "$config" -gt 0 ] 2>/dev/null; then
            delay="$config"
        fi
        case "$slot_type" in
            usb|pcie)
                scanc scan "$slot_type" "${delay:-0}"
                exit $?
                ;;
            *)
                scanc scan all "${delay:-0}"
                exit $?
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 add <slot> <usb|pcie> [delay] | remove <section> [delay] | disable <slot> [delay] | scan [delay] [usb|pcie]" >&2
        exit 1
        ;;
esac
