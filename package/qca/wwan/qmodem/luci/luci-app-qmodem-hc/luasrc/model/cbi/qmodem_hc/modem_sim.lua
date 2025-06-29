m = Map("qmodem_hc_sim", translate("SIM Settings"))
uci = require "luci.model.uci".cursor()
s = m:section(NamedSection,"main","main", translate("SIM Settings"))
s.anonymous = true
s.addremove = false



sim_auto_switch = s:option(Flag, "sim_auto_switch", translate("SIM Auto Switch"))
sim_auto_switch.default = "0"

detect_interval = s:option(Value, "detect_interval", translate("Network Detect Interval"))
detect_interval.default = 15

judge_time = s:option(Value, "judge_time", translate("Network Down Judge Times"))
judge_time.default = 5

ping_dest = s:option(DynamicList, "ping_dest", translate("Ping Destination"))

o = s:option(ListValue, "modem_config", translate("Modem Config"))
uci:foreach("qmodem", "modem-device",
    function(s)
        if s then
            o:value(s['.name'])
        end
    end
)
-- o.description = translate("Please enter the WWAN interface name")
-- o.template = "cbi/network_netlist"
-- o.widget = "optional"

o.nocreate = true

m:section(SimpleSection).template = "qmodem_hc/modem_sim"

return m
