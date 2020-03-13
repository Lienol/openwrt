local m,s,o
local SYS  = require "luci.sys"

m = Map("flowoffload")
m.title	= translate("Turbo ACC Acceleration Settings")
m.description = translate("Opensource Linux Flow Offload driver (Fast Path or HWNAT)")
m:append(Template("flow/status"))

s = m:section(TypedSection, "flow")
s.addremove = false
s.anonymous = true

flow = s:option(Flag, "flow_offloading", translate("Enable"))
flow.default = 0
flow.rmempty = false
flow.description = translate("Enable software flow offloading for connections. (decrease cpu load / increase routing throughput)")

function flow.cfgvalue(...)
	return m.uci:get("firewall", "@defaults[0]", "flow_offloading") or "0"
end

function flow.write(self, section, value)
    m.uci:set("firewall", "@defaults[0]", "flow_offloading", value)
    m.uci:commit("firewall")
end

hw = s:option(Flag, "flow_offloading_hw", translate("HWNAT"))
hw.default = 0
hw.rmempty = true
hw.description = translate("Enable Hardware NAT (depends on hw capability like MTK 762x)")
hw:depends("flow_offloading", 1)

function hw.cfgvalue(...)
	return m.uci:get("firewall", "@defaults[0]", "flow_offloading_hw") or "0"
end

function hw.write(self, section, value)
    m.uci:set("firewall", "@defaults[0]", "flow_offloading_hw", value)
    m.uci:commit("firewall")
end

o = s:option(Flag, "fullcone", translate("Enable FullCone-NAT"))
o.default = 0
o.rmempty = false

function o.cfgvalue(...)
	return m.uci:get("firewall", "@defaults[0]", "fullcone") or "0"
end

function o.write(self, section, value)
    m.uci:set("firewall", "@defaults[0]", "fullcone", value)
    m.uci:commit("firewall")
end

bbr = s:option(Flag, "bbr", translate("Enable BBR"))
bbr.default = 0
bbr.rmempty = false
bbr.description = translate("Bottleneck Bandwidth and Round-trip propagation time (BBR)")

return m
