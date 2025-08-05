local sys  = require "luci.sys"
local d = require "luci.dispatcher"
m = Map("qmodem")
m.title = translate("QModem Setting")

this_page = d.build_url("admin", "modem", "qmodem", "settings")
s = m:section(NamedSection, "main", "main", translate("Modem Probe setting"))

at_tool = s:option(Flag, "at_tool", translate("Alternative AT Tools"))
at_tool.description = translate("If enabled, using alternative AT Tools")

block_auto_probe = s:option(Flag, "block_auto_probe", translate("Block Auto Probe/Remove"))
block_auto_probe.description = translate("If enabled, the modem auto scan will be blocked.")

enable_pcie_scan = s:option(Flag, "enable_pcie_scan", translate("Enable PCIE Scan"))
enable_pcie_scan.description = translate("Once enabled, the PCIe ports will be scanned on every boot.")

enable_usb_scan = s:option(Flag, "enable_usb_scan",translate("Enable USB Scan"))
enable_usb_scan.description = translate("Once enabled, the USB ports will be scanned on every boot.")

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
