#!/bin/sh

set -eu

QMODEM_PACKAGE_DIR="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
dial_script="${QMODEM_PACKAGE_DIR}/files/usr/share/qmodem/modem_dial.sh"

extract_function()
{
	awk -v name="$1" '
		$0 == name "()" { capture = 1 }
		capture { print }
		capture && $0 == "}" { exit }
	' "$dial_script"
}

eval "$(extract_function update_config)"

config_load() { :; }
config_foreach() { :; }
get_platform_suggest_pdp_index() { printf '1\n'; }
get_driver() { printf 'qmi\n'; }
update_sim_slot() { sim_slot=1; }
find() { printf '/tmp/qmodem-test/net\n'; }
ls() { printf 'wwan0\n'; }

config_get()
{
	local target="$1"
	local section="$2"
	local option="$3"
	local value="${4-}"

	case "${section}:${option}" in
	modem0:path) value='/tmp/qmodem-test' ;;
	modem0:en_bridge) value="$TEST_BRIDGE" ;;
	modem0:donot_nat) value="$TEST_DONOT_NAT" ;;
	modem0:do_not_add_dns) value="${TEST_DNS-$value}" ;;
	main:enable_dial) value='1' ;;
	esac

	eval "$target=\$value"
}

modem_config=modem0

TEST_BRIDGE=1
TEST_DONOT_NAT=0
update_config
[ "$bridge_enabled:$donot_nat" = '1:1' ]
[ "$do_not_add_dns" = '1' ]

TEST_DNS=0
update_config
[ "$do_not_add_dns" = '0' ]
unset TEST_DNS

TEST_BRIDGE=0
TEST_DONOT_NAT=0
update_config
[ "$bridge_enabled:$donot_nat" = '0:0' ]

TEST_BRIDGE=0
TEST_DONOT_NAT=1
update_config
[ "$bridge_enabled:$donot_nat" = '0:1' ]

network_handlers="$(extract_function set_if)
$(extract_function flush_if)"
[ "$(printf '%s\n' "$network_handlers" | grep -cF '/etc/init.d/network restart')" -eq 2 ]
if printf '%s\n' "$network_handlers" | grep -qF '/etc/init.d/network reload'; then
	exit 1
fi

echo 'bridge passthrough tests passed'
