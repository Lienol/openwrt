local d = require "luci.dispatcher"
local uci = luci.model.uci.cursor()
local sys  = require "luci.sys"

m = Map("modem")
m.title = translate("Dial Overview")
m.description = translate("Check and add modem dialing configurations")

--全局配置
s = m:section(NamedSection, "global", "global", translate("Global Config"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enable_dial", translate("Enable"))
o.rmempty = false
o.description = translate("Enable dial configurations")

-- 添加模块状态
m:append(Template("modem/modem_status"))

s = m:section(TypedSection, "dial-config", translate("Config List"))
s.anonymous = true
s.addremove = true
s.template = "modem/tblsection"
s.extedit = d.build_url("admin", "network", "modem", "dial_config", "%s")

function s.create(uci, t)
    local uuid = string.gsub(luci.sys.exec("echo -n $(cat /proc/sys/kernel/random/uuid)"), "-", "")
    t = uuid
    TypedSection.create(uci, t)
    luci.http.redirect(uci.extedit:format(t))
end
function s.remove(uci, t)
    uci.map.proceed = true
    uci.map:del(t)
    luci.http.redirect(d.build_url("admin", "network", "modem","dial_overview"))
end

o = s:option(Flag, "enable", translate("Enable"))
o.width = "5%"
o.rmempty = false

-- o = s:option(DummyValue, "status", translate("Status"))
-- o.template = "modem/status"
-- o.value = translate("Collecting data...")

o = s:option(DummyValue, "remarks", translate("Remarks"))

o = s:option(DummyValue, "network", translate("Mobile Network"))
o.cfgvalue = function(t, n)
    -- 检测移动网络是否存在
    local network = (Value.cfgvalue(t, n) or "")
    local odpall = io.popen("ls /sys/class/net/ | grep -w "..network.." | wc -l")
    local odp = odpall:read("*a"):gsub("\n","")
    odpall:close()
    if odp ~= "0" then
        return network
    else
        return translate("The network device was not found")
    end
end

o = s:option(DummyValue, "dial_tool", translate("Dial Tool"))
o.cfgvalue = function(t, n)
    local dial_tool = (Value.cfgvalue(t, n) or "")
    if dial_tool == "" then
        dial_tool = translate("Auto Choose")
    end
    return translate(dial_tool)
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

o = s:option(Flag, "network_bridge", translate("Network Bridge"))
o.width = "5%"
o.rmempty = false

o = s:option(DummyValue, "apn", translate("APN"))
o.cfgvalue = function(t, n)
    local apn = (Value.cfgvalue(t, n) or "")
    if apn == "" then
        apn = translate("Auto Choose")
    end
    return apn
end

-- 添加模块拨号日志
m:append(Template("modem/modem_dial_log"))

-- m:append(Template("modem/list_status"))

return m
