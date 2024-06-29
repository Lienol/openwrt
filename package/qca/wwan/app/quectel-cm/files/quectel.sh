#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_quectel_init_config() {
	available=1
	no_device=1
	proto_config_add_string "device:device"
	proto_config_add_string "apn"
	proto_config_add_string "auth"
	proto_config_add_string "username"
	proto_config_add_string "password"
	proto_config_add_string "pincode"
	proto_config_add_int "delay"
	proto_config_add_string "pdptype"
	proto_config_add_boolean "dhcp"
	proto_config_add_boolean "dhcpv6"
	proto_config_add_boolean "sourcefilter"
	proto_config_add_boolean "delegate"
	proto_config_add_int "mtu"
	proto_config_add_defaults
}

proto_quectel_setup() {
	local interface="$1"
	local device apn auth username password pincode delay pdptype
	local dhcp dhcpv6 sourcefilter delegate mtu $PROTO_DEFAULT_OPTIONS
	local ip4table ip6table
	local pid zone

	json_get_vars device apn auth username password pincode delay
	json_get_vars pdptype dhcp dhcpv6 sourcefilter delegate ip4table
	json_get_vars ip6table mtu $PROTO_DEFAULT_OPTIONS

	[ -n "$delay" ] && sleep "$delay"

	[ -n "$metric" ] || metric="0"
	[ -z "$ctl_device" ] || device="$ctl_device"

	[ -n "$device" ] || {
		echo "No control device specified"
		proto_notify_error "$interface" NO_DEVICE
		proto_set_available "$interface" 0
		return 1
	}

	device="$(readlink -f "$device")"
	[ -c "$device" ] || {
		echo "The specified control device does not exist"
		proto_notify_error "$interface" NO_DEVICE
		proto_set_available "$interface" 0
		return 1
	}

	devname="$(basename "$device")"
	devpath="$(readlink -f "/sys/class/usbmisc/$devname/device/")"
	ifname="$(ls "$devpath/net" 2>"/dev/null")"
	[ -n "$ifname" ] || {
		echo "The interface could not be found."
		proto_notify_error "$interface" NO_IFACE
		proto_set_available "$interface" 0
		return 1
	}

	[ "$pdptype" = "ip" -o "$pdptype" = "ipv4v6" ] && ipv4opt="-4"
	[ "$pdptype" = "ipv6" -o "$pdptype" = "ipv4v6" ] && ipv6opt="-6"
	[ -n "$auth" ] || auth="none"

	eval "proto_run_command '$interface' /usr/bin/quectel-cm -i '$ifname' $ipv4opt $ipv6opt ${pincode:+-p $pincode} -s '$apn' '$username' '$password' '$auth'"
	sleep 5

	ifconfig "$ifname" up
	ifconfig "${ifname}_1" &>"/dev/null" && ifname="${ifname}_1"

	if [ -n "$mtu" ]; then
		echo "Setting MTU to $mtu"
		/sbin/ip link set dev "$ifname" mtu "$mtu"
	fi

	echo "Setting up $ifname"
	proto_init_update "$ifname" 1
	proto_set_keep 1
	proto_send_update "$interface"

	zone="$(fw3 -q network "$interface" 2>/dev/null)"

	if [ "$pdptype" = "ipv6" ] || [ "$pdptype" = "ipv4v6" ]; then
		json_init
		json_add_string name "${interface}_6"
		json_add_string ifname "@$interface"
		[ "$pdptype" = "ipv4v6" ] && json_add_string iface_464xlat "0"
		json_add_string proto "dhcpv6"
		proto_add_dynamic_defaults
		[ -z "$ip6table" ] || json_add_string ip6table "$ip6table"
		# RFC 7278: Extend an IPv6 /64 Prefix to LAN
		json_add_string extendprefix 1
		[ "$delegate" = "0" ] && json_add_boolean delegate "0"
		[ "$sourcefilter" = "0" ] && json_add_boolean sourcefilter "0"
		[ -z "$zone" ] || json_add_string zone "$zone"
		json_close_object
		ubus call network add_dynamic "$(json_dump)"
	fi

	if [ "$pdptype" = "ip" ] || [ "$pdptype" = "ipv4v6" ]; then
		json_init
		json_add_string name "${interface}_4"
		json_add_string ifname "@$interface"
		json_add_string proto "dhcp"
		[ -z "$ip4table" ] || json_add_string ip4table "$ip4table"
		proto_add_dynamic_defaults
		[ -z "$zone" ] || json_add_string zone "$zone"
		json_close_object
		ubus call network add_dynamic "$(json_dump)"
	fi
}

proto_quectel_teardown() {
	local interface="$1"

	local device
	json_get_vars device
	[ -z "$ctl_device" ] || device="$ctl_device"

	echo "Stopping network $interface"

	proto_kill_command "$interface"

	proto_init_update "*" 0
	proto_send_update "$interface"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol quectel
}
