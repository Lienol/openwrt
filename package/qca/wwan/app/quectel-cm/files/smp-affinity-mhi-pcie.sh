#!/bin/sh

[ "$ACTION" = add ] || exit
echo "$INTERFACE" | grep -q "rmnet_mhi" || exit

core_count="$(grep -c "processor" "/proc/cpuinfo")"
irq_path="/sys/class/net/$INTERFACE/queues"

devnum="$(echo "${INTERFACE%.*}" | grep -Eo "[0-9]+")"
core="$(( devnum % (core_count - 1) + 1))"
if [ "$INTERFACE" != "${INTERFACE%.*}" ]; then
	if [ "$core" -lt "$(( core_count - 1 ))" ]; then
		let core++
	else
		core="1"
	fi
fi
irq="$(printf "%x" "$((1 << core))")"

echo "$irq" > "$irq_path/rx-0/rps_cpus"
echo "4096" > "$irq_path/rx-0/rps_flow_cnt"
echo "2000" > "/proc/sys/net/core/netdev_max_backlog"

exit 0
