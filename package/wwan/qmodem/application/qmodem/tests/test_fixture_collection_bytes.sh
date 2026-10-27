#!/usr/bin/env bash
# Collection must not alter stdout bytes or the AT tool exit status.
set -u

PACKAGE_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
QMODEM_HOME="$PACKAGE_DIR/files/usr/share/qmodem"
QMODEM_LIB_FUNCTIONS="$PACKAGE_DIR/tests/lib/functions_stub.sh"
QMODEM_COLLECT_TESTCASE=1
QMODEM_COLLECT_DIR=$(mktemp -d)
vendor=quectel
platform=qualcomm
QMODEM_TESTCASE_MODEL=RM500Q-AE
clear_buffer=0
options=
use_ubus_flag=
export QMODEM_HOME QMODEM_LIB_FUNCTIONS QMODEM_COLLECT_TESTCASE QMODEM_COLLECT_DIR
export vendor platform QMODEM_TESTCASE_MODEL clear_buffer options use_ubus_flag

cleanup() { rm -rf "$QMODEM_COLLECT_DIR" "$expected" "$actual" "$recorded"; }
expected=$(mktemp)
actual=$(mktemp)
recorded=$(mktemp)
trap cleanup EXIT

uci() { return 1; }
tom_modem()
{
    case " $* " in
        *' -t 1 '*) printf 'FAST\r\n\r\n\r\n'; return 9 ;;
        *) printf 'NORMAL\r\n\r\n\r\n'; return 7 ;;
    esac
}

. "$QMODEM_HOME/modem_util.sh"
. "$PACKAGE_DIR/tests/lib/hex.sh"

printf 'NORMAL\r\n\r\n\r\n' > "$expected"
at /dev/ttyUSB2 'AT+BYTECHECK' > "$actual"
rc=$?
[ "$rc" -eq 7 ]
cmp "$expected" "$actual"
fixture=$(find "$QMODEM_COLLECT_DIR/quectel" -name '*BYTECHECK*.json')
fixture_hex_decode "$(jq -r '.response_hex' "$fixture")" > "$recorded"
cmp "$expected" "$recorded"
[ "$(jq -r '.rc' "$fixture")" -eq 7 ]
[ "$(jq -r '.platform' "$fixture")" = qualcomm ]
[ "$(jq -r '.model' "$fixture")" = RM500Q-AE ]
case "$fixture" in */quectel/qualcomm/rm500q-ae-9f94df3c/*) ;; *) exit 1 ;; esac

printf 'FAST\r\n\r\n\r\n' > "$expected"
fastat /dev/ttyUSB2 'AT+FASTBYTECHECK' > "$actual"
rc=$?
[ "$rc" -eq 9 ]
cmp "$expected" "$actual"
fixture=$(find "$QMODEM_COLLECT_DIR/quectel" -name '*FASTBYTECHECK*.json')
fixture_hex_decode "$(jq -r '.response_hex' "$fixture")" > "$recorded"
cmp "$expected" "$recorded"
[ "$(jq -r '.rc' "$fixture")" -eq 9 ]

echo 'fixture collection byte tests passed'
