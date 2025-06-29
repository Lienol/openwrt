#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"
source "${SCRIPT_DIR}/modem_util.sh"

#################################################################################旧扫描方法#################################################################################

#获取设备物理地址
# $1:网络设备或串口
get_device_physical_path()
{
    local device_name="$(basename "$1")"
    local device_path="$(find /sys/class/ -name $device_name)"
    local device_physical_path="$(readlink -f $device_path/device/)"
    echo "$device_physical_path"
}

#设置模组配置
# $1:网络设备
# $2:网络设备系统路径
set_modem_config()
{
    local network="$(basename $sys_network)"
    local network_path="$(readlink -f $sys_network)"

    #只处理最上级的网络设备
    local count=$(echo "${network_path}" | grep -o "/net" | wc -l)
    [ "$count" -ge "2" ] && return

    #判断路径是否带有usb（排除其他eth网络设备）
    if [[ "$network" = *"eth"* ]] && [[ "$network_path" != *"usb"* ]]; then
        return
    fi

    #获取物理路径
    local device_physical_path=$(m_get_device_physical_path ${network_path})
    #设置物理设备
    m_set_physical_device "scan" "${device_physical_path}"

    #启用拨号
    m_enable_dial "${network}"
}

#设置系统网络设备
# $1:系统网络设备列表
set_sys_network_config()
{
    local sys_networks="$1"

    for sys_network in $sys_networks; do
        local network="$(basename $sys_network)"
        set_modem_config "${network}" "${sys_network}"
    done
}

#通过网络扫描模组
modem_scan_by_network()
{
    #模组配置初始化
    sh "${SCRIPT_DIR}/modem_init.sh"

    #发起模组添加事件
    #USB
    local sys_network
    sys_network="$(find /sys/class/net -name usb*)" #ECM RNDIS NCM
    set_sys_network_config "$sys_network"
    sys_network="$(find /sys/class/net -name wwan*)" #QMI MBIM
    set_sys_network_config "$sys_network"
    sys_network="$(find /sys/class/net -name eth*)" #RNDIS
    set_sys_network_config "$sys_network"

    #PCI
    sys_network="$(find /sys/class/net -name mhi_hwip*)" #（通用mhi驱动）
    set_sys_network_config "$sys_network"
    sys_network="$(find /sys/class/net -name rmnet_mhi*)" #（制造商mhi驱动）
    set_sys_network_config "$sys_network"

    echo "modem scan complete"
}

#################################################################################新扫描方法#################################################################################

#扫描USB设备
scan_usb_device()
{
    echo "scan USB device"
    local devices_path="/sys/bus/usb/devices"

    for device in ${devices_path}/*; do
        # 跳过非目录文件
        [[ ! -d "$device" ]] && continue
        
        local device_name=$(basename "$device")
        # 跳过USB总线控制器 (以usb开头)
        [[ "$device_name" == usb* ]] && continue

        # 设置物理设备
        m_set_physical_device "scan" "${device}"

        # 启用拨号
        # m_enable_dial "${network}"
    done
}

#扫描PCI设备
scan_pci_device()
{
    echo "scan PCI device"
    local devices_path="/sys/bus/pci/devices"

    for device in ${devices_path}/*; do
        # 跳过非目录文件
        [[ ! -d "$device" ]] && continue

        # 设置物理设备
        m_set_physical_device "scan" "${device}"

        # 启用拨号
        # m_enable_dial "${network}"
    done
}

#扫描模组
modem_scan()
{
    # 模组配置初始化
    sh "${SCRIPT_DIR}/modem_init.sh"

    #USB
    local usb_scan=$(uci -q get modem.@global[0].usb_scan)
    [ "${usb_scan}" = "1" ] && scan_usb_device

    #PCI
    local pci_scan=$(uci -q get modem.@global[0].pci_scan)
    [ "${pci_scan}" = "1" ] && scan_pci_device

    echo "modem scan complete"
}

#测试时打开
# modem_scan
# modem_scan_by_network