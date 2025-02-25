#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"

#运行目录
MODEM_RUNDIR="/var/run/modem"
MODEM_PID_FILE="${MODEM_RUNDIR}/modem.pid"
MODEM_CDC_WDM_CACHE="${MODEM_RUNDIR}/cdc_wdm.cache"
MODEM_PHYSICAL_DEVICE_CACHE="${MODEM_RUNDIR}/physical_device.cache"
MODEM_EVENTS_CACHE="${MODEM_RUNDIR}/events.cache"

#导入组件工具
source "/lib/functions.sh"
source "/lib/netifd/netifd-proto.sh"
source "${SCRIPT_DIR}/modem_debug.sh"

#日志
# $1:日志等级
m_log()
{
	local level="$1";
	logger -p "daemon.${level}" -t "Modem[$$]" "hotplug: $*"
}

#生成16进制数
generate_hex() {
	echo "$(openssl rand -hex 1)"
}

#生成随机MAC地址
generate_mac_address() {
	local mac=""
	for i in $(seq 1 6); do
	  	mac="${mac}$(generate_hex)"
		if [[ $i != 6 ]]; then
			mac="${mac}:"
		fi
	done
	echo "$mac"
}

#上报USB事件
# $1:事件行为（add，remove，bind）
# $2:类型
# $3:名称或设备ID
# $4:路径
m_report_event()
{
	local action="$1"
	local type="$2"
	local name="$3"
	local physical_path="$4"

	#缓存事件信息
	echo "${action},${type},${name},${physical_path}" >> "${MODEM_EVENTS_CACHE}"
	#输出事件处理日志
	m_log "debug" "event reported: action=${action}, type=${type}, name=${name}"
}

#模组预设
# $1:AT串口
# $2:连接定义
# $3:制造商
m_modem_presets()
{
	local at_port="$1"
	local define_connect="$2"
	local manufacturer="$3"

	#运营商选择设置
	local at_command='AT+COPS=0,0'
	at "${at_port}" "${at_command}"

	#PDP设置
	at_command="AT+CGDCONT=${define_connect},\"IPV4V6\",\"\""
	at "${at_port}" "${at_command}"

	#制造商私有预设
	case $manufacturer in
		"quectel") quectel_presets ;;
		"fibocom") fibocom_presets ;;
		"meig") meig_presets ;;
		"simcom") simcom_presets ;;
		"huawei") huawei_presets ;;
	esac
}

#获取设备物理路径
# $1:网络设备路径
m_get_device_physical_path()
{
	local tmp_path="$1"

	while true; do
		tmp_path=$(dirname "${tmp_path}")

		#跳出循环条件
		[ -z "${tmp_path}" ] || [ "${tmp_path}" = "/" ] && return

		#USB设备
		[ -f "${tmp_path}"/idVendor ] && [ -f "${tmp_path}"/idProduct ] && {
			tmp_path=$(readlink -f "$tmp_path")
			echo "${tmp_path}"
			return
		}

		#PCIE设备
		[ -f "${tmp_path}"/vendor ] && [ -f "${tmp_path}"/device ] && {
			tmp_path=$(readlink -f "$tmp_path")
			echo "${tmp_path}"
			return
		}
	done
}

#删除物理路径状态
# $1:设备物理路径
m_del_physical_path_status()
{
	# local network="$1"
	local physical_path="$1"

	#删除网络设备
	# [ -f "${MODEM_PHYSICAL_DEVICE_CACHE}" ] && {
	# 	#删除
	# 	sed -i "/${network}/d" "${MODEM_PHYSICAL_DEVICE_CACHE}"
	# }

	#通过物理路径删除
	local escaped_physical_path
	[ -f "${MODEM_PHYSICAL_DEVICE_CACHE}" ] && {
		# escape '/', '\' and '&' for sed...
		escaped_physical_path=$(echo "$physical_path" | sed -e 's/[\/&]/\\&/g')
		#删除
		sed -i "/${escaped_physical_path}/d" "${MODEM_PHYSICAL_DEVICE_CACHE}"
	}
}

#获取设备物理路径状态
# $1:设备物理路径
m_get_physical_path_status()
{
	local physical_path="$1"

	[ -f "${MODEM_PHYSICAL_DEVICE_CACHE}" ] || return

	#获取状态（不包含注释并且包含physical_path的行，获取以,分割的第二个字符串）
	awk -v physical_path="${physical_path}" -F',' '!/^#/ && $0 ~ physical_path { print $2 }' "${MODEM_PHYSICAL_DEVICE_CACHE}"
}

#设置设备物理路径状态
# $1:设备物理路径
# $2:状态
m_set_physical_path_status()
{
	local physical_path="$1"
	local status="$2"

	#删除物理路径状态
	m_del_physical_path_status "${physical_path}"

	#缓存物理路径状态
	echo "${physical_path},${status}" >> "${MODEM_PHYSICAL_DEVICE_CACHE}"
}

#缓存cdc-wdm
# $1:网络设备
m_cdc_wdm_cache()
{
	local network="$1"

    #获取cdc-wdm
	local cdc_wdm=$(ls "/sys/class/net/${network}/device/usbmisc/")
    [ -z "${cdc_wdm}" ] && return

    #缓存
	echo "${network},${cdc_wdm}" >> "${MODEM_CDC_WDM_CACHE}"

	echo "${cdc_wdm}"
}

#取消缓存cdc-wdm
# $1:网络设备
m_cdc_wdm_del_cache()
{
	local wwan="$1"

	[ -f "${MODEM_CDC_WDM_CACHE}" ] || return

    #获取cdc-wdm（不包含注释并且包含network的行，获取以,分割的第二个字符串）
	local cdc_wdm=$(awk -v network="${network}" -F',' '!/^#/ && $0 ~ network { print $2 }' "${MODEM_CDC_WDM_CACHE}")
	[ -n "${cdc_wdm}" ] || return

	#取消缓存
	sed -i "/${network},${cdc_wdm}/d" "${MODEM_CDC_WDM_CACHE}"

	echo "${cdc_wdm}"
}

#cdc-wdm处理
# $1:事件行为（add，remove，bind）
# $2:名称
# $3:路径
m_cdc_wdm()
{
	local action="$1"
	local name="$2"
	local physical_path="$4"

	#获取cdc-wdm
    local cdc_wdm=""
    #操作缓存
    case "${action}" in
        "add") cdc_wdm=$(m_cdc_wdm_cache "${name}") ;;
        "remove") cdc_wdm=$(m_cdc_wdm_del_cache "${name}") ;;
    esac

    if [ -n "${cdc_wdm}" ]; then
        #输出cdc-wdm事件处理日志
        m_log "${action} cdc interface ${cdc_wdm}: cdc-wdm event processed"
        #上报cdc-wdm事件
        m_report_event "${action}" "usbmisc" "${cdc_wdm}" "/sys${physical_path}"
    fi
}

#添加USB模组ID
# $1:制造商ID
# $2:产品ID
m_add_usb_id()
{
	local manufacturer_id="$1"
	local product_id="$2"

	local new_id_path="/sys/bus/usb-serial/drivers/generic/new_id"

	#如果已经添加则返回
	grep -q "${manufacturer_id} ${product_id}" "${new_id_path}" && return

	while true; do
		if [ -f "$new_id_path" ]; then
			#添加ID
			echo "${manufacturer_id} ${product_id}" >> "${new_id_path}"
			break
		fi
		sleep 5s
	done
}

#设置模组硬件配置
# $1:物理路径
m_set_modem_hardware_config()
{
	local physical_path="$1"

	#获取设备数据接口
	local data_interface
	if [[ "$physical_path" = *"usb"* ]]; then
		data_interface="usb"
	else
		data_interface="pcie"
	fi

	# [ "$data_interface" = "usb" ] && {
	# 	#不存在网络接口
	# 	local net_count="$(find ${physical_path} -name net | wc -l)"
	# 	if [ "$net_count" -le "0" ]; then
	# 		#撤销
	# 		uci revert modem
	# 		return
	# 	fi
	# }

	#是否是第一次添加（初始化模组）
	local count=$(grep -o "processed" ${MODEM_PHYSICAL_DEVICE_CACHE} | wc -l)
	#是否开启手动配置
	local manual_configuration=$(uci -q get modem.@global[0].manual_configuration)
	[ "$count" = "0" ] && [ "$manual_configuration" = "0" ] && {
		#模组配置初始化
		sh "${SCRIPT_DIR}/modem_init.sh"
	}

	#设置物理路径状态
	m_set_physical_path_status "${physical_path}" "processed"

	#获取模组序号
	local modem_no=$(uci -q get modem.@global[0].modem_number)
	#增加模组计数
    local modem_number=$((modem_no + 1))
	uci set modem.@global[0].modem_number="${modem_number}"

    #设置模组硬件配置
    uci set modem.modem${modem_no}="modem-device"
    uci set modem.modem${modem_no}.data_interface="${data_interface}"
    uci set modem.modem${modem_no}.path="${physical_path}"

	uci commit modem
}

#删除模组配置
# $1:物理路径
m_del_modem_config()
{
	local physical_path="$1"

	#获取模组数量
	local modem_number=$(uci -q get modem.@global[0].modem_number)
	#获取模组序号
	local modem_no
	for i in $(seq 0 $((modem_number-1))); do
		local modem_path=$(uci -q get modem.modem${i}.path)
		if [ "$modem_path" = "$physical_path" ]; then
			modem_no="$i"
			break
		fi
	done

	[ -z "$modem_no" ] && return

	#删除该模组的配置
	uci -q del modem.modem${modem_no}
	uci -q set modem.@global[0].modem_number=$((modem_number-1))
	uci commit modem

	#删除物理路径状态
	m_del_physical_path_status "${physical_path}"

	#打印日志
	m_log "info" "Modem${modem_no} (${physical_path}) removed"
}

#设置USB设备
# $1:事件行为（add，remove，bind）
# $2:制造商ID
# $3:产品ID
# $4:物理路径
m_set_usb_device()
{
	local action="$1"
	local manufacturer_id="$2"
	local product_id="$3"
	local physical_path="$4"

	if [ "$action" = "add" ]; then
		#添加USB模组ID
		m_add_usb_id "${manufacturer_id}" "${product_id}"

		#设置模组配置
		# m_set_modem_hardware_config "${physical_path}"

	elif [ "$action" = "remove" ]; then

		#手动配置
		local manual_configuration=$(uci -q get modem.@global[0].manual_configuration)
		[ "${manual_configuration}" = "1" ] && return

		#删除模组配置
		m_del_modem_config "${physical_path}"
	fi
}

#处理特殊的模组名称
# $1:模组名称
handle_special_modem_name()
{
	local modem_name="$1"

	#FM350-GL-00 5G Module
	[[ "$modem_name" = *"fm350-gl"* ]] && {
		modem_name="fm350-gl"
	}

	#SRM825-PV
	[[ "$modem_name" = *"srm825-pv"* ]] && {
		modem_name="srm825"
	}

	echo "$modem_name"
}

#重新尝试设置模组
# $1:模组序号
# $2:AT串口
# $3:模组支持列表
retry_set_modem_config()
{
	local modem_no="$1"
	local at_port="$2"
	local modem_support="$3"

	local time=0
	while true; do

		#打印日志
		m_log "info" "Try again to configure the Modem${modem_no}"

		[ "$time" = "2" ] && break

       	#获取模组名称
		local at_command="AT+CGMM?"
		local modem_name=$(at ${at_port} ${at_command} | grep "+CGMM: " | awk -F'"' '{print $2}' | tr 'A-Z' 'a-z')

		#再一次获取模组名称
		[ -z "$modem_name" ] && {
			at_command="AT+CGMM"
			modem_name=$(at ${at_port} ${at_command} | grep "+CGMM: " | awk -F': ' '{print $2}' | sed 's/\r//g' | tr 'A-Z' 'a-z')
		}

		#再一次获取模组名称
		[ -z "$modem_name" ] && {
			at_command="AT+CGMM"
			modem_name=$(at ${at_port} ${at_command} | sed -n '2p' | sed 's/\r//g' | tr 'A-Z' 'a-z')
		}

		#处理特殊的模组名称
		[ -n "$modem_name" ] && {
			modem_name="$(handle_special_modem_name ${modem_name})"
		}

		#获取模组信息
		local data_interface=$(uci -q get modem.modem${modem_no}.data_interface)
		local modem_info=$(echo ${modem_support} | jq '.modem_support.'$data_interface'."'$modem_name'"')

		[ -n "$modem_name" ] && [ "$modem_info" != "null" ] && {

			#获取制造商
			local manufacturer=$(echo ${modem_info} | jq -r '.manufacturer')
			#获取平台
			local platform=$(echo ${modem_info} | jq -r '.platform')
			#获取连接定义
			local define_connect=$(echo ${modem_info} | jq -r '.define_connect')
			#获取支持的拨号模式
			local modes=$(echo ${modem_info} | jq -r '.modes[]')

			uci set modem.modem${modem_no}.name="${modem_name}"
			uci set modem.modem${modem_no}.manufacturer="${manufacturer}"
			uci set modem.modem${modem_no}.platform="${platform}"
			uci set modem.modem${modem_no}.define_connect="${define_connect}"
			uci -q del modem.modem${modem_no}.modes #删除原来的拨号模式列表
			for mode in $modes; do
				uci add_list modem.modem${modem_no}.modes="${mode}"
			done

			#设置模组预设
			m_modem_presets "${at_port}" "${define_connect}" "${manufacturer}"

			#打印日志
			m_log "info" "Successfully retrying to configure the Modem ${modem_name}"

			break
		}

		time=$((time+1))
        sleep 5s
    done
}

#设置模组配置
# $1:模组序号
# $2:物理路径
m_set_modem_config()
{
	local modem_no="$1"
	local physical_path="$2"

	#获取AT串口
	local at_port=$(uci -q get modem.modem${modem_no}.at_port)

	#获取模组名称
	local modem_name=$(uci -q get modem.modem${modem_no}.name)
	[ -z "$modem_name" ] && {
		local at_command="AT+CGMM?"
   		modem_name=$(at ${at_port} ${at_command} | grep "+CGMM: " | awk -F'"' '{print $2}' | tr 'A-Z' 'a-z')
	}

	#获取模组支持列表
	local modem_support=$(cat ${SCRIPT_DIR}/modem_support.json)
	#获取模组信息
	local data_interface=$(uci -q get modem.modem${modem_no}.data_interface)
    local modem_info=$(echo ${modem_support} | jq '.modem_support.'$data_interface'."'$modem_name'"')

	local manufacturer
	local platform
	local define_connect
	local modes
	local log_message
	if [ -z "$modem_name" ] || [ "$modem_info" = "null" ]; then
        modem_name="unknown"
        manufacturer="unknown"
        platform="unknown"
		define_connect="1"
        modes="qmi gobinet ecm mbim rndis ncm"
		#设置日志信息
		log_message="An unknown Modem${modem_no} (${physical_path}) was found"
	else
		#获取制造商
		manufacturer=$(echo ${modem_info} | jq -r '.manufacturer')
		#获取平台
		platform=$(echo ${modem_info} | jq -r '.platform')
		#获取连接定义
		define_connect=$(echo ${modem_info} | jq -r '.define_connect')
		#获取支持的拨号模式
		modes=$(echo ${modem_info} | jq -r '.modes[]')
		#设置日志信息
		log_message="Configuration Modem${modem_no} ${modem_name} (${physical_path}) successful"
	fi

	uci set modem.modem${modem_no}.name="${modem_name}"
	uci set modem.modem${modem_no}.manufacturer="${manufacturer}"
	uci set modem.modem${modem_no}.define_connect="${define_connect}"
	uci set modem.modem${modem_no}.platform="${platform}"
	uci -q del modem.modem${modem_no}.modes #删除原来的拨号模式列表
	for mode in $modes; do
		uci add_list modem.modem${modem_no}.modes="${mode}"
	done

	#设置模组预设
	m_modem_presets "${at_port}" "${define_connect}" "${manufacturer}"

	#打印日志
	m_log "info" "${log_message}"

	#重新尝试设置模组
	[ "$modem_name" = "unknown" ] && {
		retry_set_modem_config "${modem_no}" "${at_port}" "${modem_support}"
	}
}

#设置USB AT串口
# $1:模组序号
# $2:串口
# $3:物理路径
m_set_usb_at_port()
{
	local modem_no="$1"
	local port="$2"
	local physical_path="$3"

	local modem_at_port=$(uci -q get modem.modem${modem_no}.at_port)
	[ -z "$modem_at_port" ] && {
		local response="$(at ${port} 'ATI')"
		local str1="No" #No response from modem.
		local str2="failed"
		if [[ "$response" != *"$str1"* ]] && [[ "$response" != *"$str2"* ]] && [ -n "$response" ]; then
			#原先的AT串口会被覆盖掉（是否需要加判断）
			uci set modem.modem${modem_no}.at_port="${port}"
			
			#设置模组配置
			m_set_modem_config "${modem_no}" "${physical_path}"
			uci commit modem
		fi
	}
}

#设置PCIE AT串口
# $1:模组序号
# $2:串口
# $3:物理路径
m_set_pcie_at_port()
{
	local modem_no="$1"
	local port="$2"
	local physical_path="$3"

	#设置AT串口
	uci set modem.modem${modem_no}.at_port="${port}"

	#设置模组配置
	m_set_modem_config "${modem_no}" "${physical_path}"
	uci commit modem
}

#设置ttyUSB设备
# $1:事件行为（add，remove，bind）
# $2:物理路径
m_set_tty_device()
{
	local action="$1"
	local physical_path="$2"

	if [ "$action" = "bind" ]; then

		#获取模组数量
		local modem_number=$(uci -q get modem.@global[0].modem_number)
		#获取模组序号
		local modem_no
		for i in $(seq 0 $((modem_number-1))); do
			local modem_path=$(uci -q get modem.modem${i}.path)
			if [[ "$physical_path" = *"$modem_path"* ]]; then
				modem_no="${i}"
				break
			fi
		done

		[ -z "$modem_no" ] && return

		#获取ttyUSB
		local tty_usb=$(find ${physical_path} -type d -name ttyUSB* | sed -n '1p')
		#不存在tty，退出
		[ -z "$tty_usb" ] && return
		local port="/dev/$(basename ${tty_usb})"

		#添加串口
		uci add_list modem.modem${modem_no}.ports="${port}"
		uci commit modem

		#设置AT串口
		m_set_usb_at_port "${modem_no}" "${port}" "${physical_path}"
	fi
}

#检查USB设备
# $1:事件行为（add，remove，bind）
# $2:设备号
# $2:设备ID
# $3:物理路径
m_check_usb_device()
{
	local action="$1"
	local device_num="$2"
	local device_id="$3"
	local physical_path="$4"

	#获取制造商ID
	local manufacturer_id=$(echo "$device_id" | awk -F'/' '{printf "%04s", $1}' | tr ' ' '0')
	#获取产品ID
	local product_id=$(echo "$device_id" | awk -F'/' '{printf "%04s", $2}' | tr ' ' '0')

	#获取模组支持列表
	local modem_support=$(cat ${SCRIPT_DIR}/modem_support.json)

	[[ "$modem_support" = *"$manufacturer_id"* ]] && {
		#上报USB事件
		m_report_event "${action}" "usb" "${manufacturer_id}:${product_id}" "${physical_path}"

		if [ -n "$device_num" ]; then
			#设置USB设备
			m_set_usb_device "${action}" "${manufacturer_id}" "${product_id}" "${physical_path}"
		# else
			#设置ttyUSB设备
			# m_set_tty_device "${action}" "${physical_path}"
		fi
	}
}

#设置模组网络配置
# $1:网络设备
# $2:物理路径
m_set_network_config()
{
	local network="$1"
	local physical_path="$2"

	#获取模组数量
	local modem_number=$(uci -q get modem.@global[0].modem_number)
	#获取模组序号
	local modem_no
	for i in $(seq 0 $((modem_number-1))); do
		local modem_path=$(uci -q get modem.modem${i}.path)
		if [ "$modem_path" = "$physical_path" ]; then
			modem_no="${i}"
			break
		fi
	done

	#没有模组时跳过
	[ -z "$modem_no" ] && return

	#判断地址是否为net
    # local path=$(basename "$physical_path")
    # if [ "$path" = "net" ]; then
    #     return
    # fi

	#获取网络接口
	local net_path="$(find ${physical_path} -name net | sed -n '1p')"
	local net_net_interface_path="${net_path}"

	#子目录下存在网络接口
	local net_count="$(find ${physical_path} -name net | wc -l)"
	if [ "$net_count" = "2" ]; then
		net_net_interface_path="$(find ${physical_path} -name net | sed -n '2p')"
	fi
	local network_interface=$(ls ${net_net_interface_path})

	#设置模组网络配置
	uci set modem.modem${modem_no}.network="${network}"
	uci set modem.modem${modem_no}.network_interface="${network_interface}"
	uci commit modem

	#打印日志
	m_log "info" "Configuration Modem${modem_no} Network ${network} (${physical_path}) successful"
}

#启用拨号
# $1:网络设备
enable_dial()
{
	local network="$1"
	
	local i=0
	while true; do
		#查看该网络设备的配置是否启用
		local modem_network=$(uci -q get modem.@dial-config[${i}].network)
		[ -z "$modem_network" ] && break
		if [ "$network" = "$modem_network" ]; then
			local enable=$(uci -q get modem.@dial-config[${i}].enable)
			if [ "$enable" = "1" ]; then
				service modem reload
				break
			fi
		fi
		i=$((i+1))
	done
}

#禁用拨号
# $1:网络设备
disable_dial()
{
	local network="$1"

	local i=0
	while true; do
		#查看该网络设备的配置是否启用
		local modem_network=$(uci -q get modem.@dial-config[${i}].network)
		[ -z "$modem_network" ] && break
		if [ "$network" = "$modem_network" ]; then
			local enable=$(uci -q get modem.@dial-config[${i}].enable)
			if [ "$enable" = "1" ]; then
				uci set modem.@dial-config[${i}].enable=0
				uci commit modem
				service modem reload
				break
			fi
		fi
		i=$((i+1))
	done
}

#设置模组串口
# $1:物理路径
m_set_modem_port()
{
	local physical_path="$1"

	#获取模组数量
	local modem_number=$(uci -q get modem.@global[0].modem_number)
	#获取模组序号
	local modem_no
	for i in $(seq 0 $((modem_number-1))); do
		local modem_path=$(uci -q get modem.modem${i}.path)
		if [ "$modem_path" = "$physical_path" ]; then
			modem_no="${i}"
			break
		fi
	done

	#没有模组时跳过
	[ -z "$modem_no" ] && return

	#获取当前路径下所有的串口
	local data_interface=$(uci -q get modem.modem${modem_no}.data_interface)
	local all_port
	if [ "$data_interface" = "usb" ]; then
		all_port=$(find ${physical_path} -name ttyUSB*)
	else
		local mhi_hwip=$(find ${physical_path} -name mhi_hwip*)
		if [ -n "$mhi_hwip" ]; then
			all_port=$(find ${physical_path} -name wwan*)
			all_port=$(echo "$all_port" | sed '1,2d')
		else
			all_port=$(find ${physical_path} -name mhi_*)
		fi
	fi

	#不存在串口，返回
	[ -z "${all_port}" ] && return

	#删除原串口
	uci -q del modem.modem${modem_no}.ports
	#设置串口
	local port_cache
	for port_path in $all_port; do

		local port_tmp="$(basename ${port_path})"
		local port="/dev/${port_tmp}"

		#跳过重复的串口
		[ "$port" = "$port_cache" ] && continue
		#跳过多余串口（PCIE）
		[[ "$port" = *"mhi_uci_q"* ]] && continue
		[[ "$port" = *"mhi_cntrl_q"* ]] && continue

		#添加串口
		uci add_list modem.modem${modem_no}.ports="${port}"
		uci commit modem

		#设置AT串口
		if [ "$data_interface" = "usb" ]; then
			m_set_usb_at_port "${modem_no}" "${port}" "${physical_path}"
		elif [[ "$port" = *"at"* ]]; then
			m_set_pcie_at_port "${modem_no}" "${port}" "${physical_path}"
		elif [[ "$port" = *"DUN"* ]]; then
			m_set_pcie_at_port "${modem_no}" "${port}" "${physical_path}"
		fi

		#缓存当前串口
		port_cache="${port}"
    done
}

#设置物理设备
# $1:事件行为（add，remove，bind，scan）
# $2:网络设备
# $3:物理路径
m_set_physical_device()
{
	local action="$1"
	local network="$2"
	local physical_path="$3"

	if [ "$action" = "add" ]; then

		#已经添加过路径，退出
		local physical_path_status=$(m_get_physical_path_status ${physical_path})
		[ "$physical_path_status" = "processed" ] && return

		#设置模组硬件配置
		m_set_modem_hardware_config "${physical_path}"

		#设置模组网络配置
		m_set_network_config "${network}" "${physical_path}"

		#设置模组串口
		m_set_modem_port "${physical_path}"

	elif [ "$action" = "remove" ]; then
		#删除模组配置
		m_del_modem_config "${physical_path}"
	elif [ "$action" = "scan" ]; then
		
		#设置模组硬件配置
		m_set_modem_hardware_config "${physical_path}"

		#设置模组网络配置
		m_set_network_config "${network}" "${physical_path}"

		#设置模组串口
		m_set_modem_port "${physical_path}"
	fi
}

#设置网络设备
# $1:事件行为（add，remove，bind）
# $2:网络设备
# $3:物理路径
# $4:数据接口
m_set_network_device()
{
	local action="$1"
	local network="$2"
	local network_path="$3"
	local data_interface="$4"

	#只处理最上级的网络设备
	local count=$(echo "${network_path}" | grep -o "/net" | wc -l)
	[ "$count" -ge "2" ] && return

	#判断路径是否带有usb（排除其他eth网络设备）
	if [[ "$network" = *"eth"* ]] && [[ "$network_path" != *"usb"* ]]; then
		return
	fi

	#上报事件
    m_report_event "${action}" "net" "${network}" "${network_path}"

	#手动配置
	local manual_configuration=$(uci -q get modem.@global[0].manual_configuration)
	[ "${manual_configuration}" = "1" ] && return

	if [ "$action" = "add" ]; then

		if [ "$data_interface" = "usb" ]; then
			#获取物理路径
			local device_physical_path=$(m_get_device_physical_path ${network_path})
			#设置USB网络设备
			# m_set_network_config "${network}" "${device_physical_path}"
			#设置物理设备
			m_set_physical_device "${action}" "${network}" "${device_physical_path}"
		else
			#获取物理路径
			local device_physical_path=$(m_get_device_physical_path ${network_path})
			#设置物理设备
			m_set_physical_device "${action}" "${network}" "${device_physical_path}"
		fi
		#启用拨号
		# sleep 60s
		enable_dial "${network}"

	elif [ "$action" = "remove" ]; then
		
		#USB设备通过USB事件删除
		[ "$data_interface" = "pcie" ] && {
			#获取物理路径
			local device_physical_path=$(m_get_device_physical_path ${network_path})
			#设置物理设备
			m_set_physical_device "${action}" "${network}" "${device_physical_path}"
		}

		#停止拨号
		# disable_dial "${network}"

		#打印日志
		m_log "info" "Network ${network} (${network_path}) removed"
	fi
}

#测试Net热插拔
test_net_hotplug()
{
	echo ACTION:"$ACTION" >> /root/test
	echo DEVICENAME:"$DEVICENAME" >> /root/test
	echo PATH:"$PATH" >> /root/test
	echo DEVPATH:"$DEVPATH" >> /root/test
	echo DEVTYPE:"$DEVTYPE" >> /root/test
	echo INTERFACE:"$INTERFACE" >> /root/test
	echo PRODUCT:"$PRODUCT" >> /root/test
}

#测试USB热插拔
test_usb_hotplug()
{
	echo ACTION:"$ACTION" >> /root/test
	echo DEVICENAME:"$DEVICENAME" >> /root/test
	echo DEVPATH:"$DEVPATH" >> /root/test
	echo DEVNUM:"$DEVNUM" >> /root/test
	echo DRIVER:"$DRIVER" >> /root/test
	echo TYPE:"$TYPE" >> /root/test
	echo PRODUCT:"$PRODUCT" >> /root/test
	echo SEQNUM:"$SEQNUM" >> /root/test
	echo BUSNUM:"$BUSNUM" >> /root/test
	echo MAJOR:"$MAJOR" >> /root/test
	echo MINOR:"$MINOR" >> /root/test
}

#测试tty热插拔
test_tty_hotplug()
{
	echo ACTION:"$ACTION" >> /root/test
	echo DEVICENAME:"$DEVICENAME" >> /root/test
	echo DEVPATH:"$DEVPATH" >> /root/test
	echo DEVNUM:"$DEVNUM" >> /root/test
	echo DRIVER:"$DRIVER" >> /root/test
	echo TYPE:"$TYPE" >> /root/test
	echo PRODUCT:"$PRODUCT" >> /root/test
	echo SEQNUM:"$SEQNUM" >> /root/test
	echo BUSNUM:"$BUSNUM" >> /root/test
	echo MAJOR:"$MAJOR" >> /root/test
	echo MINOR:"$MINOR" >> /root/test
}