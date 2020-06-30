
m = Map("sfe")
m.title	= translate("Turbo ACC Acceleration Settings")
m.description = translate("Opensource Qualcomm Shortcut FE driver (Fast Path)")

m:append(Template("sfe/status"))

s = m:section(TypedSection, "sfe", "")
s.addremove = false
s.anonymous = true


enable = s:option(Flag, "enabled", translate("Enable SFE Fast Path"))
enable.default = 0
enable.rmempty = false
enable.description = translate("Enable Fast Path offloading for connections. (decrease cpu load / increase routing throughput)")

wifi = s:option(Flag, "wifi", translate("Bridge Acceleration"))
wifi.default = 0
wifi.rmempty = false
wifi.description = translate("Enable Bridge Acceleration (may be functional conflict with bridge-mode VPN Server)")
wifi:depends("enabled", 1)

ipv6 = s:option(Flag, "ipv6", translate("IPv6 Acceleration"))
ipv6.default = 0
ipv6.rmempty = false
ipv6.description = translate("Enable IPv6 Acceleration")
ipv6:depends("enabled", 1)

fullcone = s:option(Flag, "fullcone", translate("Enable FullCone-NAT"))
fullcone.default = 0
fullcone.rmempty = false

function fullcone.cfgvalue(...)
	return m.uci:get("firewall", "@defaults[0]", "fullcone") or "0"
end

function fullcone.write(self, section, value)
    m.uci:set("firewall", "@defaults[0]", "fullcone", value)
    m.uci:commit("firewall")
end

bbr = s:option(Flag, "bbr", translate("Enable BBR"))
bbr.default = 0
bbr.rmempty = false
bbr.description = translate("Bottleneck Bandwidth and Round-trip propagation time (BBR)")

return m
