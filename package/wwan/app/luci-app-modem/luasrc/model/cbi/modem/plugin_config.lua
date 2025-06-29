local d = require "luci.dispatcher"
local uci = luci.model.uci.cursor()
local sys  = require "luci.sys"
local script_path="/usr/share/modem/"

m = Map("modem")
m.title = translate("Plugin Config")
m.description = translate("Check and modify the plugin configuration")

font_red = [[<b style=color:red>]]
font_off = [[</b>]]
bold_on  = [[<strong>]]
bold_off = [[</strong>]]

--全局配置
s = m:section(TypedSection, "global", translate("Global Config"))
s.anonymous = true
s.addremove = false

-- 模组扫描
o = s:option(Button, "modem_scan", translate("Modem Scan"))
o.template = "modem/modem_scan"

-- 启用手动配置
o = s:option(Flag, "manual_configuration", font_red..bold_on..translate("Manual Configuration")..bold_off..font_off)
o.rmempty = false
o.description = translate("Enable the manual configuration of modem information").." "..font_red..bold_on.. translate("(After enable, the automatic scanning and configuration function for modem information will be disabled)")..bold_off..font_off

-- 启用网络接口别名
o = s:option(Flag, "network_interface_alias", translate("Network Interface Alias"))
o.rmempty = false
o.description = translate("Enable automatic creation of network interface alias (Effective upon reinstatement of dialing configuration)")

-- 配置模组信息
s = m:section(TypedSection, "modem-device", translate("Modem Config"))
s.anonymous = true
s.addremove = true
-- s.sortable = true
s.template = "modem/tblsection"
s.extedit = d.build_url("admin", "network", "modem", "modem_config", "%s")

function s.create(uci, t)
    -- 获取模组序号
    -- local modem_no=tonumber(uci.map:get("@global[0]","modem_number")) -- 将字符串转换为数字类型
    local modem_no=0
    local uci_tmp=luci.model.uci.cursor()
    uci_tmp:foreach("modem", "modem-device", function (modem_device)
		modem_no=modem_no+1
	end)

    t="modem"..modem_no
    TypedSection.create(uci, t)
    -- 设置手动配置
    -- uci.map:set(t,"manual","1")
    luci.http.redirect(uci.extedit:format(t))
end

function s.remove(uci, t)
    uci.map.proceed = true
    uci.map:del(t)
    luci.http.redirect(d.build_url("admin", "network", "modem","plugin_config"))
end

-- 移动网络
o = s:option(DummyValue, "network", translate("Network"))

-- 模组名称
o = s:option(DummyValue, "name", translate("Modem Name"))
o.cfgvalue = function(t, n)
    local name = (Value.cfgvalue(t, n) or "")
    return translate(name:upper())
end

-- AT串口
o = s:option(DummyValue, "at_port", translate("AT Port"))
-- o = s:option(Value, "at_port", translate("AT Port"))
-- o.placeholder = translate("Not null")
-- o.rmempty = false
-- o.optional = false

return m
