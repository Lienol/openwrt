

local d = require "luci.dispatcher"
local uci = luci.model.uci.cursor()
local sys  = require "luci.sys"
local script_path="/usr/share/qmodem/"

m = Map("qmodem_mwan")
m.title = translate("Mwan Config")
m.description = translate("Check and modify the mwan configuration")
s = m:section(NamedSection, "global", "global")
s.anonymous = true
s.addremove = false
enable_mwan = s:option(Flag, "enable_mwan", translate("Enable MWAN"))
sticky = s:option(Flag,"sticky_mode",translate("sticky mode"))
sticky.default = 0
sticky.description = translate("same source ip address will always use the same wan interface")
sticky_timeout = s:option(Value,"sticky_timeout",translate("sticky timeout"))
sticky_timeout.default = 300
sticky_timeout.datatype = "uinteger"
sticky_timeout:depends("sticky_mode",1)

s = m:section(TypedSection, "ipv4", translate("IPV4 Config"))
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"
member_interface = s:option(Value, "member_interface", translate("Interface"))
member_interface.rmempty = true
uci:foreach("network", "interface", function(s)
    if s[".name"] ~= "loopback" and s[".name"] ~= "lan" then
        member_interface:value(s[".name"])
    end
end)


o = s:option(DynamicList, 'member_track_ip', translate('Track IP'))
o.datatype = 'host'
member_priority = s:option(Value, "member_priority", translate("Priority"))
member_priority.rmempty = true
member_priority.datatype = "range(1, 255)"
member_priority.default = 1
member_priority.description = translate("Set the priority for the load balancing member. A higher priority value gives precedence to this member when distributing traffic. The range is from 1 to 255. 1 is the highest priority")

-- member_priority:depends("member_interface", "")

member_weight = s:option(Value, "member_weight", translate("Weight"))
member_weight.rmempty = true
member_weight.datatype = "range(1, 255)"
member_weight.default = 1
member_weight.description = translate("Set the weight for the load balancing member. A higher weight means more traffic will be assigned to this member. The default value is 1, with a range from 1 to 255.")
-- member_weight:depends("member_interface", "")


return m
