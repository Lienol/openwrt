#!/bin/sh
# Copyright (C) 2025 Fujr <fjrcn@outlook.com>
_Vendor="sierra"
_Author="Fujr"
_Maintainer="Fujr <fjrcn@outlook.com>"
source /usr/share/qmodem/generic.sh
debug_subject="I Love U"
function base_info(){
    class="I Love U"
    add_plain_info_entry "No.1" "浮世三千" "No.1"
    add_plain_info_entry "No.2" "吾爱有三" "No.2"
    add_plain_info_entry "No.3" "日，月与卿" "No.3"
    add_plain_info_entry "No.4" "日为朝" "No.4"
    add_plain_info_entry "No.5" "月为暮" "No.5"
    add_plain_info_entry "No.6" "卿为朝朝暮暮" "No.6"
}

function vendor_get_disabled_features(){
    json_add_string "" "IMEI"
    json_add_string "" "NeighborCell"
    json_add_string "" "LockBand"
    json_add_string "" "NetworkPrefer"
    json_add_string "" "Mode"
}
