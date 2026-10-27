#!/bin/sh
# Ensure modem_dial/modem_util wrappers pass the exact final command to at().
set -eu

PACKAGE_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
QMODEM_DIR="$PACKAGE_DIR/files/usr/share/qmodem"
GENERIC_FILE="$QMODEM_DIR/generic.sh"
FIBOCOM_FILE="$QMODEM_DIR/vendor/fibocom.sh"
observed=

at()
{
    observed_port=$1
    observed=$2
    export observed_port observed
}

. "$QMODEM_DIR/cmds/modem_util.sh"
. "$QMODEM_DIR/cmds/modem_dial.sh"
. "$QMODEM_DIR/cmds/fibocom.sh"

cmd_util_quimslot_query /dev/ttyUSB2
[ "$observed_port" = /dev/ttyUSB2 ]
[ "$observed" = 'AT+QUIMSLOT?' ]

cmd_dial_cpin_unlock /dev/ttyUSB3 1234
[ "$observed_port" = /dev/ttyUSB3 ]
[ "$observed" = 'AT+CPIN="1234"' ]

dynamic='AT+CGDCONT=3,"IPV4V6","internet"'
cmd_dial_command /dev/ttyUSB4 "$dynamic"
[ "$observed_port" = /dev/ttyUSB4 ]
[ "$observed" = "$dynamic" ]

cmd_dial_neoway_simcross_iccid /dev/ttyUSB5
[ "$observed" = 'AT+SIMCROSS=1,1;$MYCCID' ]

cmd_gtcurcar_query /dev/ttyUSB6
[ "$observed_port" = /dev/ttyUSB6 ]
[ "$observed" = 'AT+GTCURCAR?' ]

get_function()
{
    awk -v name="$1" '
        $0 ~ "^" name "\\(\\)[[:space:]]*(\\{)?$" { capture = 1 }
        capture { print }
        capture && $0 == "}" { exit }
    ' "$2"
}

eval "$(get_function get_cgpaddr_ipv4 "$GENERIC_FILE")"
fm350_cgpaddr='+CGPADDR: 2,"10.3.4.136","0.0.0.0.0.0.0.0.24.141.77.91.197.17.80.76"'
[ "$(get_cgpaddr_ipv4 "$fm350_cgpaddr")" = '10.3.4.136' ]
[ -z "$(get_cgpaddr_ipv4 '+CGPADDR: 1,"0.0.0.0",""')" ]

eval "$(get_function fibocom_get_carrier "$FIBOCOM_FILE")"
platform=mediatek
at_port=/dev/ttyUSB6
cmd_gtcurcar_query() { printf '%s\n' '+GTCURCAR: 117,"China Telecom"'; }
cmd_cops_query() { printf '%s\n' '+COPS: 0,2,"garbled",7'; }
[ "$(fibocom_get_carrier)" = 'China Telecom' ]
cmd_gtcurcar_query() { :; }
[ "$(fibocom_get_carrier)" = 'garbled' ]

eval "$(get_function fibocom_gtact_params "$FIBOCOM_FILE")"
eval "$(get_function fibocom_uses_empty_gtact_fields "$FIBOCOM_FILE")"
eval "$(get_function fibocom_normalize_band_list "$FIBOCOM_FILE")"
eval "$(get_function fibocom_gtact_network_prefer_from_bands "$FIBOCOM_FILE")"
eval "$(get_function fibocom_gtact_lock_params "$FIBOCOM_FILE")"
platform=qualcomm
QMODEM_TESTCASE_MODEL=fm160-cn
band_class=NR
umts_bands='1,5,8'
lte_bands='101,105'
nr_bands='5041,5078'
ALL_LTE_CODES='101,103,105'
ALL_NR_CODES='5041,5075,5078'
GTACT_PARAM2=6
GTACT_PARAM3=3
[ "$(fibocom_gtact_lock_params)" = '17,,,101,105,5041,5078' ]
platform=mediatek
QMODEM_TESTCASE_MODEL=fm350-gl
[ "$(fibocom_gtact_lock_params)" = '17,6,6,101,105,5041,5078' ]
platform=qualcomm
QMODEM_TESTCASE_MODEL=fm150-ae
[ "$(fibocom_gtact_lock_params)" = '20,6,3,1,5,8,101,105,5041,5078' ]
platform=unisoc
QMODEM_TESTCASE_MODEL=fm650-cn
[ "$(fibocom_gtact_lock_params)" = '20,6,3,1,5,8,101,105,5041,5078' ]

cmd_gtcelllock_query /dev/ttyUSB7
[ "$observed_port" = /dev/ttyUSB7 ]
[ "$observed" = 'AT+GTCELLLOCK?' ]

eval "$(get_function fibocom_is_uint "$FIBOCOM_FILE")"
eval "$(get_function fibocom_normalize_nr_band "$FIBOCOM_FILE")"
eval "$(get_function lockcell_all "$FIBOCOM_FILE")"
cmd_gtcelllock_set() { printf '%s|%s\n' "$1" "$2"; }
qmodem_lockcell_boot_hook_clear() { :; }
qmodem_lockcell_boot_hook_sync() { :; }
at_port=/dev/ttyUSB7
config_section=modem1
rat=1
pci=347
arfcn=504990
band=41
scs=1
en_boot_hook=0
lockcell_all
[ "$res" = '/dev/ttyUSB7|1,1,0,504990,347,1,5041' ]
rat=0
pci=221
arfcn=2452
band=
scs=
lockcell_all
[ "$res" = '/dev/ttyUSB7|1,0,0,2452,221' ]

echo 'core cmds tests passed'
