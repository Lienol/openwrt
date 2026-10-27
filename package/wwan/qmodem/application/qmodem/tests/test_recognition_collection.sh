#!/usr/bin/env bash
# Recognition exchanges are staged separately, then resolved at pack time.
set -euo pipefail

PACKAGE_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
QMODEM_HOME="$PACKAGE_DIR/files/usr/share/qmodem"
QMODEM_LIB_FUNCTIONS="$PACKAGE_DIR/tests/lib/functions_stub.sh"
QMODEM_COLLECT_TESTCASE=1
QMODEM_COLLECT_DIR=$(mktemp -d)
fake_bin=$(mktemp -d)
archive=
cleanup()
{
    rm -rf "$QMODEM_COLLECT_DIR" "$fake_bin"
    [ -z "$archive" ] || rm -f "$archive"
}
trap cleanup EXIT

vendor=core
platform=unknown
config_section=fixture
clear_buffer=0
options=
use_ubus_flag=
export QMODEM_HOME QMODEM_LIB_FUNCTIONS QMODEM_COLLECT_TESTCASE QMODEM_COLLECT_DIR
export vendor platform config_section clear_buffer options use_ubus_flag

uci()
{
    case "$*" in
        *qmodem.fixture.name*) printf '%s\n' air724ug ;;
        *) return 1 ;;
    esac
}
tom_modem() { printf 'Air724UG\r\n\r\nOK\r\n'; }

. "$QMODEM_HOME/modem_util.sh"
at /dev/ttyUSB2 'AT+CGMM' >/dev/null
fixture=$(find "$QMODEM_COLLECT_DIR/recognition/pending/fixture" -name '*.json')
[ "$(jq -r '.phase' "$fixture")" = recognition ]
[ "$(jq -r '.config_section' "$fixture")" = fixture ]

cat > "$fake_bin/uci" <<'EOF'
#!/bin/sh
case "$*" in
    *qmodem.main.testcase_collect*) echo 1 ;;
    *qmodem.fixture.manufacturer*) echo openluat ;;
    *qmodem.fixture.platform*) echo unisoc ;;
    *qmodem.fixture.name*) echo air724ug ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/uci"

output=$(PATH="$fake_bin:$PATH" QMODEM_SEAL_BIN=missing-qmodem-seal \
    "$PACKAGE_DIR/files/usr/sbin/qmodem_collect" pack --raw --unencrypted)
archive=$(printf '%s\n' "$output" | sed -n 's/^packed .* -> //p')
[ -f "$archive" ]
resolved_path='recognition/openluat/unisoc/air724ug-c9340434/AT_CGMM-bb33552b.json'
tar -tzf "$archive" > "$QMODEM_COLLECT_DIR/archive-list"
grep -q "./$resolved_path" "$QMODEM_COLLECT_DIR/archive-list"
tar -xOzf "$archive" "./$resolved_path" | jq -e '
    .phase == "recognition" and
    .expected_identity == {vendor:"openluat", platform:"unisoc", model:"air724ug"}' >/dev/null

echo 'recognition fixture collection tests passed'
