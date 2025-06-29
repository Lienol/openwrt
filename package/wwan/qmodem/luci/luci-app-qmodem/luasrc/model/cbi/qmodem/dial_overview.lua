local d = require "luci.dispatcher"
local sys  = require "luci.sys"

m = Map("qmodem")
m.title = translate("Dial Overview")

--全局配置
s = m:section(NamedSection, "main", "main", translate("Global Config"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enable_dial", translate("Enable Dial")..translate("(Global)"))
o.rmempty = false

o = s:option(Button, "reload_dial", translate("Restart Dial Service"))
o.inputstyle = "apply"
o.write = function()
    sys.call("/etc/init.d/qmodem_network restart  > /dev/null 2>&1")
    luci.http.redirect(d.build_url("admin", "modem", "qmodem", "dial_overview"))
end

s = m:section(TypedSection, "modem-device", translate("Config List"))
s.addremove = ture
s.template = "cbi/tblsection"
s.extedit = d.build_url("admin", "modem", "qmodem", "dial_config", "%s")

o = s:option(Flag, "enable_dial", translate("Enable Dial"))
o.width = "5%"
o.rmempty = false

restart_btn = s:option(Button, "_redial", translate("ReDial"))
restart_btn.inputstyle = "remove"
function restart_btn.write(self, section)
    sys.call("/etc/init.d/qmodem_network redial "..section.." > /dev/null 2>&1")
    luci.http.redirect(d.build_url("admin", "modem", "qmodem", "dial_overview"))
end

o = s:option(DummyValue, "name", translate("Modem Model"))
o.cfgvalue = function(t, n)
    local name = (Value.cfgvalue(t, n) or "")
    return name:upper()
end

o = s:option(DummyValue, "alias", translate("Modem Alias"))
o.cfgvalue = function(t, n)
    local alias = (Value.cfgvalue(t, n) or "-")
    return alias
    
end

o = s:option(DummyValue, "state", translate("Modem Status"))
o.cfgvalue = function(t, n)
    if Value.cfgvalue(t,n) == nil then
        return translate("Unknown")
    end
    return translate(Value.cfgvalue(t, n):upper() or "-")
end


o = s:option(DummyValue, "pdp_type", translate("PDP Type"))
o.cfgvalue = function(t, n)
    local pdp_type = (Value.cfgvalue(t, n) or "")
    if pdp_type == "ipv4v6" then
        pdp_type = translate("IPv4/IPv6")
    else
        pdp_type = pdp_type:gsub("_","/"):upper():gsub("V","v")
    end
    return pdp_type
end


o = s:option(DummyValue, "apn", translate("APN"))
o.cfgvalue = function(t, n)
    local apn = (Value.cfgvalue(t, n) or "")
    if apn == "" then
        apn = translate("Auto Choose")
    end
    return apn
end

remove_btn = s:option(Button, "_remove", translate("Remove Modem"))
remove_btn.inputstyle = "remove"
function remove_btn.write(self, section)
    local shell
    shell="/usr/share/qmodem/modem_scan.sh remove "..section
    luci.sys.call(shell)
    --refresh the page
    luci.http.redirect(d.build_url("admin", "modem", "qmodem", "dial_overview"))
end
-- 添加模块拨号日志
m:append(Template("qmodem/dial_overview"))
m.on_after_commit = function(self)
    sys.call("/etc/init.d/qmodem_network reload  > /dev/null 2>&1")
end

return m
