local sys  = require "luci.sys"
local d = require "luci.dispatcher"
m = Map("qmodem")
m.title = translate("QModem Setting")

this_page = d.build_url("admin", "modem", "qmodem", "settings")
s = m:section(NamedSection, "main", "main", translate("Modem Probe setting"))

at_tool = s:option(Flag, "at_tool", translate("Alternative AT Tools"))
at_tool.description = translate("If enabled, using alternative AT Tools")

start_delay = s:option(Value, "start_delay", translate("Delay Start"))
start_delay.description = translate("Units:seconds")
start_delay.datatype = "and(uinteger,min(0),max(99))"
start_delay.default = "0"

block_auto_probe = s:option(Flag, "block_auto_probe", translate("Block Auto Probe/Remove"))
block_auto_probe.description = translate("If enabled, the modem auto scan will be blocked.")

enable_pcie_scan = s:option(Flag, "enable_pcie_scan", translate("Enable PCIE Scan"))
enable_pcie_scan.description = translate("Once enabled, the PCIe ports will be scanned on every boot.")

enable_usb_scan = s:option(Flag, "enable_usb_scan",translate("Enable USB Scan"))
enable_usb_scan.description = translate("Once enabled, the USB ports will be scanned on every boot.")

scan_log_level = s:option(ListValue, "scan_log_level", translate("Scan Log Level"))
scan_log_level:value("debug", "Debug")
scan_log_level:value("info", "Info")
scan_log_level:value("notice", "Notice")
scan_log_level:value("warn", "Warning")
scan_log_level:value("err", "Error")
scan_log_level.default = "info"

scan_workers = s:option(Value, "scan_workers", translate("Scan Workers"))
scan_workers.datatype = "and(uinteger,min(1),max(16))"
scan_workers.default = "4"

at_probe_workers = s:option(Value, "at_probe_workers", translate("AT Probe Workers"))
at_probe_workers.datatype = "and(uinteger,min(1),max(16))"
at_probe_workers.default = "4"

at_timeout_fast = s:option(Value, "at_timeout_fast", translate("Fast AT Timeout"))
at_timeout_fast.description = translate("Units: seconds")
at_timeout_fast.datatype = "and(uinteger,min(1),max(30))"
at_timeout_fast.default = "2"

at_timeout_model = s:option(Value, "at_timeout_model", translate("Model AT Timeout"))
at_timeout_model.description = translate("Units: seconds")
at_timeout_model.datatype = "and(uinteger,min(1),max(60))"
at_timeout_model.default = "8"

hotplug_add_delay = s:option(Value, "hotplug_add_delay", translate("Hotplug Add Delay"))
hotplug_add_delay.description = translate("Units: seconds")
hotplug_add_delay.datatype = "and(uinteger,min(0),max(60))"
hotplug_add_delay.default = "8"

add_retry_delay = s:option(Value, "add_retry_delay", translate("Add Retry Delay"))
add_retry_delay.description = translate("Units: seconds")
add_retry_delay.datatype = "and(uinteger,min(0),max(60))"
add_retry_delay.default = "8"

add_retry_max = s:option(Value, "add_retry_max", translate("Add Retry Max"))
add_retry_max.datatype = "and(uinteger,min(0),max(20))"
add_retry_max.default = "5"

try_vendor_preset_usb = s:option(Flag,"try_preset_usb",translate("Try Preset USB Port"))
try_vendor_preset_usb.description = translate("Attempt to use pre-configured USB settings from the cpe vendor.") 

try_vendor_preset_pcie = s:option(Flag,"try_preset_pcie",translate("Try Preset PCIE Port"))
try_vendor_preset_pcie.description = translate("Attempt to use pre-configured PCIE settings from the cpe vendor.")

o = s:option(Button, "scan_pcie", translate("Scan PCIE Manually"))
o.inputstyle = "apply"
o.write = function()
    sys.call("/usr/share/qmodem/modem_scan.sh scan 0 pcie  > /dev/null 2>&1")
    luci.http.redirect(this_page)
end

o = s:option(Button, "scan_usb", translate("Scan USB Manually"))
o.inputstyle = "apply"
o.write = function()
    sys.call("/usr/share/qmodem/modem_scan.sh scan 0 usb  > /dev/null 2>&1")
    luci.http.redirect(this_page)
end

o = s:option(Button, "scan_all", translate("Scan ALL Manually"))
o.inputstyle = "apply"
o.write = function()
    sys.call("/usr/share/qmodem/modem_scan.sh scan  > /dev/null 2>&1")
    luci.http.redirect(this_page)
end


s = m:section(TypedSection, "modem-slot", translate("Modem Slot Config List"))
s.addremove = true
s.template = "cbi/tblsection"
s.extedit = d.build_url("admin", "modem", "qmodem", "slot_config", "%s")
s.sectionhead = translate("Config Name")
slot_type = s:option(DummyValue, "type", translate("Slot Type"))
slot_type.cfgvalue = function(t, n)
    local name = translate(Value.cfgvalue(t, n) or "-")
    return name:upper()
end

slot_path = s:option(DummyValue, "slot", translate("Slot Path"))
slot_path.cfgvalue = function(t, n)
    local path = (Value.cfgvalue(t, n) or "-")
    return path
end

default_alias = s:option(DummyValue, "alias", translate("Default Alias"))
default_alias.cfgvalue = function(t, n)
    local alias = (Value.cfgvalue(t, n) or "-")
    return alias
end


s = m:section(TypedSection, "modem-device", translate("Modem Config List"))
s.addremove = true
s.template = "cbi/tblsection"
s.template_addremove = "qmodem/modem_config_add"
s.extedit = d.build_url("admin", "modem", "qmodem", "modem_config", "%s")
s.sectionhead = translate("Config Name")
local pcie_slots = io.popen("ls /sys/bus/pci/devices/")
local pcie_slot_list = {}
for line in pcie_slots:lines() do
    table.insert(pcie_slot_list, line)
end
pcie_slots:close()
local usb_slots = io.popen("ls /sys/bus/usb/devices/")
local usb_slot_list = {}
for line in usb_slots:lines() do
    if not line:match("usb%d+") then
        table.insert(usb_slot_list, line)
    end
end
usb_slots:close()
local avalibale_name_list = {}
for i,v in ipairs(pcie_slot_list) do
    local uci_name = v:gsub("%.", "_"):gsub(":", "_"):gsub("-", "_")
    avalibale_name_list[uci_name] = v.."[pcie]"
end
for i,v in ipairs(usb_slot_list) do
    local uci_name = v:gsub("%.", "_"):gsub(":", "_"):gsub("-", "_")
    avalibale_name_list[uci_name] = v.."[usb]"
end
s.avalibale_name = avalibale_name_list
slot_type = s:option(DummyValue, "name", translate("Modem Model"))
slot_type.cfgvalue = function(t, n)
    local name = translate(Value.cfgvalue(t, n) or "-")
    return name:upper()
end

path = s:option(DummyValue, "path", translate("Slot Path"))

default_alias = s:option(DummyValue, "alias", translate("Alias"))
default_alias.cfgvalue = function(t, n)
    local alias = (Value.cfgvalue(t, n) or "-")
    return alias
end
return m
