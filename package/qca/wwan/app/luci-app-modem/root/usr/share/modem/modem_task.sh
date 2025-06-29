#!/bin/sh
# Copyright (C) 2023 Siriling <siriling@qq.com>

#脚本目录
SCRIPT_DIR="/usr/share/modem"
source "${SCRIPT_DIR}/modem_debug.sh"
source "${SCRIPT_DIR}/modem_scan.sh"

#模组扫描任务
modem_scan_task()
{
    sleep 8s #刚开机需要等待移动网络出来
	while true; do
        enable_dial=$(uci -q get modem.@global[0].enable_dial)
        if [ "$enable_dial" = "1" ]; then
            #扫描模块
            debug "开启模块扫描任务"
            modem_scan
            debug "结束模块扫描任务"
        fi
        sleep 10s
    done
}

modem_scan_task