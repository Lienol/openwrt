#!/bin/sh

qmodem_connectivity_wget_bin()
{
	if command -v wget-ssl >/dev/null 2>&1; then
		echo "wget-ssl"
	elif command -v wget >/dev/null 2>&1; then
		echo "wget"
	else
		return 1
	fi
}

qmodem_connectivity_wget()
{
	local url="$1"
	local timeout="${2:-3}"
	local wget_bin

	wget_bin="$(qmodem_connectivity_wget_bin)" || return 1
	"$wget_bin" --spider --quiet --tries=1 --timeout="$timeout" "$url" >/dev/null 2>&1
}

qmodem_connectivity_ping()
{
	local target="$1"
	local timeout="${2:-3}"

	command -v ping >/dev/null 2>&1 || return 1
	ping -c 1 -W "$timeout" "$target" >/dev/null 2>&1
}

qmodem_connectivity_probe()
{
	local timeout="${1:-3}"
	local url
	local target

	for url in \
		"http://connect.rom.miui.com/generate_204" \
		"http://connectivitycheck.gstatic.com/generate_204" \
		"http://cp.cloudflare.com/generate_204" \
		"http://www.baidu.com/"
	do
		qmodem_connectivity_wget "$url" "$timeout" && return 0
	done

	for target in \
		"1.1.1.1" \
		"1.0.0.1" \
		"208.67.222.222" \
		"208.67.220.220" \
		"119.29.29.29"
	do
		qmodem_connectivity_ping "$target" "$timeout" && return 0
	done

	return 1
}
