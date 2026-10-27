#!/bin/sh
# Vendor implementations must not bypass cmds/*.sh when sending AT commands.
set -eu

PACKAGE_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
QMODEM_DIR="$PACKAGE_DIR/files/usr/share/qmodem"
failed=0

for vendor_file in "$QMODEM_DIR"/vendor/*.sh; do
    vendor=$(basename "$vendor_file" .sh)
    if [ ! -f "$QMODEM_DIR/cmds/$vendor.sh" ]; then
        echo "missing command layer: cmds/$vendor.sh" >&2
        failed=1
    elif ! grep -qE "^[[:space:]]*(source|\.)[[:space:]]+\"?\\\$\{QMODEM_HOME:-/usr/share/qmodem\}/cmds/$vendor\\.sh\"?" "$vendor_file"; then
        echo "vendor does not load command layer: vendor/$vendor.sh" >&2
        failed=1
    fi
done

for source_file in \
    "$QMODEM_DIR/generic.sh" \
    "$QMODEM_DIR/modem_dial.sh" \
    "$QMODEM_DIR/modem_util.sh" \
    "$QMODEM_DIR"/vendor/*.sh; do
    violations=$(sed '/^[[:space:]]*#/d' "$source_file" \
        | grep -nE '(^|[;&|({])[[:space:]]*(fast)?at[[:space:]]+' || true)
    if [ -n "$violations" ]; then
        echo "direct AT call outside cmds layer: $source_file" >&2
        printf '%s\n' "$violations" >&2
        failed=1
    fi
done

[ "$failed" -eq 0 ] || exit 1
echo 'vendor cmds boundary tests passed'
