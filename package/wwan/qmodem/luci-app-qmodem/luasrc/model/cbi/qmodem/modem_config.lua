local modem_cfg = require "luci.model.cbi.qmodem.modem_cfg"

-- Helper function to load slot paths
local function load_slots(path, exclude_pattern)
    local slots = {}
    local handle = io.popen("ls " .. path)
    for line in handle:lines() do
        if not exclude_pattern or not line:match(exclude_pattern) then
            table.insert(slots, line)
        end
    end
    handle:close()
    return slots
end

-- Helper function to populate options dynamically from a table
local function populate_options(option, values)
    for key, value in pairs(values) do
        option:value(key, value)
    end
end

-- Map and Section setup
m = Map("qmodem", translate("Modem Configuration"))
m.redirect = luci.dispatcher.build_url("admin", "modem", "qmodem", "settings")

s = m:section(NamedSection, arg[1], "modem-device", "")
local slot_name = arg[1]

-- Load slot paths
local usb_slot_list = load_slots("/sys/bus/usb/devices/", "usb%d+")
local pcie_slot_list = load_slots("/sys/bus/pci/devices/")

-- Fixed Device Flag
is_fixed_device = s:option(Flag, "is_fixed_device", translate("Fixed Device"))
is_fixed_device.description = translate("If the device is fixed, it will not update when the device is connected or disconnected.")
is_fixed_device.default = "0"

-- Slot Path
path = s:option(ListValue, "slot", translate("Slot Path"))
for _, v in ipairs(usb_slot_list) do
    local uci_name = v:gsub("[%.:%-]", "_")
    if uci_name == slot_name then
        path:value("/sys/bus/usb/devices/" .. v .. "/", v .. "[usb]")
    end
end
for _, v in ipairs(pcie_slot_list) do
    local uci_name = v:gsub("[%.:%-]", "_")
    if uci_name == slot_name then
        path:value("/sys/bus/pci/devices/" .. v .. "/", v .. "[pcie]")
    end
end

-- Interface Type
data_interface = s:option(ListValue, "data_interface", translate("Interface Type"))
data_interface:value("usb", translate("USB"))
data_interface:value("pcie", translate("PCIe"))

-- Alias
alias = s:option(Value, "alias", translate("Alias"))
alias.description = translate("Alias for the modem, used for identification.")
alias.rmempty = true
alias.default = ""
alias.placeholder = translate("Enter alias name")

-- Modem Model
name = s:option(Value, "name", translate("Modem Model"))
name.cfgvalue = function(t, n)
    return Value.cfgvalue(t, n) or "-"
end

-- Soft Reboot
soft_reboot = s:option(Flag, "soft_reboot", translate("Soft Reboot"))
soft_reboot.default = "0"

-- Connect Check
connect_check = s:option(Flag, "connect_check", translate("V4/V6 Connect Check"))
connect_check.description = translate("Only for AT dial modem.")
connect_check.default = "0"

-- PDP Context Index
define_connect = s:option(Value, "define_connect", translate("PDP Context Index"))
define_connect.default = "1"

-- Manufacturer (Loaded from modem_cfg.lua)
manufacturer = s:option(ListValue, "manufacturer", translate("Manufacturer"))
populate_options(manufacturer, modem_cfg.manufacturers)

-- Platform (Loaded from modem_cfg.lua)
platform = s:option(ListValue, "platform", translate("Platform"))
populate_options(platform, modem_cfg.platforms)

-- AT Port
at_port = s:option(Value, "at_port", translate("AT Port"))
at_port.description = translate("AT command port for modem communication.")

-- Supported Modes (Loaded from modem_cfg.lua)
modes = s:option(DynamicList, "modes", translate("Supported Modes"))
populate_options(modes, modem_cfg.modes)

-- Enable Flag
enabled = s:option(Flag, "enabled", translate("Enable"))
enabled.default = "1"

disabled_features = s:option(DynamicList, "disabled_features", translate("Disabled Features"))
disabled_features.description = translate("Select features to disable for this modem.")
populate_options(disabled_features, modem_cfg.disabled_features)

-- Band Configurations
local band_options = {
    { name = "wcdma_band", label = "WCDMA Band", placeholder = "Enter WCDMA band" },
    { name = "lte_band", label = "LTE Band", placeholder = "Enter LTE band" },
    { name = "nsa_band", label = "NSA Band", placeholder = "Enter NSA band" },
    { name = "sa_band", label = "SA Band", placeholder = "Enter SA band" },
}

for _, band in ipairs(band_options) do
    local option = s:option(Value, band.name, translate(band.label))
    option.description = translate(band.label .. " configuration, e.g., 1/2/3")
    option.placeholder = translate(band.placeholder)
    option.cfgvalue = function(t, n)
        return Value.cfgvalue(t, n) or "null"
    end
end

pre_dial_delay = s:option(Value, "pre_dial_delay", translate("Pre Dial Delay")..translate(" (beta)"))
pre_dial_delay.description = translate("Delay of executing AT command before dialing, in seconds."..translate("(still in beta))"))
pre_dial_delay.placeholder = translate("Enter delay in seconds")
pre_dial_delay.default = "0"
pre_dial_delay.datatype = "uinteger"
pre_dial_delay.rmempty = true

pre_add_delay = s:option(Value, "post_init_delay", translate("Post Init Delay")..translate(" (beta)"))
pre_add_delay.description = translate("Delay of executing AT command after modem initialization, in seconds."..translate("(still in beta))"))
pre_add_delay.placeholder = translate("Enter delay in seconds")
pre_add_delay.default = "0"
pre_add_delay.datatype = "uinteger"
pre_add_delay.rmempty = true

pre_add_at_cmds = s:option(DynamicList, "post_init_at_cmds", translate("Post Init AT Commands")..translate(" (beta)"))
pre_add_at_cmds.description = translate("AT commands to execute after modem initialization."..translate("(still in beta))"))
pre_add_at_cmds.placeholder = translate("Enter AT commands")
pre_add_at_cmds.datatype = "string"
pre_add_at_cmds.rmempty = true

pre_dial_at_cmds = s:option(DynamicList, "pre_dial_at_cmds", translate("Pre Dial AT Commands")..translate(" (beta)"))
pre_dial_at_cmds.description = translate("AT commands to execute before dialing."..translate("(still in beta))"))
pre_dial_at_cmds.placeholder = translate("Enter AT commands")
pre_dial_at_cmds.datatype = "string"
pre_dial_at_cmds.rmempty = true

return m
