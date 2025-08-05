local dispatcher = require "luci.dispatcher"
local uci = require "luci.model.uci".cursor()
local http = require "luci.http"

m = Map("qmodem", translate("Modem Configuration"))
m.redirect = dispatcher.build_url("admin", "modem", "qmodem","dial_overview")

s = m:section(NamedSection, arg[1], "modem-device", "")
s.addremove = false
s.dynamic = false
s:tab("general", translate("General Settings"))
s:tab("advanced", translate("Advanced Settings"))

--------general--------

-- 是否启用
enable = s:taboption("general", Flag, "enable_dial", translate("Enable Dial"))
enable.default = "0"
enable.rmempty = false

-- 别名
alias = s:taboption("general", Value, "alias", translate("Modem Alias"))
alias.rmempty = true

-- AT串口
at_port = s:taboption("general",Value, "at_port", translate("AT Port"))
sms_at_port = s:taboption("general",Value, "sms_at_port", translate("SMS AT Port"))
sms_at_port.rmempty = true
valid_at_ports = uci:get("qmodem",arg[1],"valid_at_ports")
avalible_ports = uci:get("qmodem",arg[1],"ports")

dns_list = s:taboption("general", DynamicList, "dns_list", translate("DNS"))
dns_list.description = translate("If the DNS server is not set, it will use the DNS server leased by the operator.")

if valid_at_ports == nil then
    valid_at_ports = {}
end
if avalible_ports == nil then
    avalible_ports = {}
end
for i1,v1 in ipairs(avalible_ports) do
    valid=false
    for i2,v2 in ipairs(valid_at_ports) do
        if v1 == v2 then
            valid=true
        end
    end
    if not valid then
        msg = v1 .. translate("(Not PASS)")
    else
        msg = v1 .. translate("(PASSED)")
    end
	at_port:value(v1,msg)
    sms_at_port:value(v1,msg)
end

at_port.placeholder = translate("Not null")
at_port.rmempty = false

bridge_mode = s:taboption("advanced", Flag, "en_bridge", translate("Bridge Mode"))
bridge_mode.description = translate("Caution: Only avalible for quectel sdx 5G Modem.")
bridge_mode.default = "0"

do_not_add_dns = s:taboption("advanced", Flag, "do_not_add_dns", translate("Do Not modify resolv.conf"))
do_not_add_dns.description = translate("quectel-CM will append the DNS server to the resolv.conf file by default.if you do not want to modify the resolv.conf file, please check this option.")
do_not_add_dns.default = "0"

ra_master = s:taboption("advanced", Flag, "ra_master", translate("RA Master"))
ra_master.description = translate("Caution: Enabling this option will make it the IPV6 RA Master, and only one interface can be configured as such.")
ra_master.default = "0"

extend_prefix = s:taboption("advanced", Flag, "extend_prefix", translate("Extend Prefix"))
extend_prefix.description = translate("Once checking, the prefix will be apply to lan zone")
extend_prefix.default = "0"

-- 软重启
soft_reboot = s:taboption("advanced", Flag, "soft_reboot", translate("Soft Reboot"))
soft_reboot.description = translate("enable modem soft reboot")
soft_reboot.default = "0"

-- Connect Check
connect_check = s:taboption("advanced", Flag, "connect_check", translate("V4/V6 Connect Check"))
connect_check.description = translate("Only for AT dial modem.")
connect_check.default = "0"

-- 网络类型
pdp_type= s:taboption("advanced", ListValue, "pdp_type", translate("PDP Type"))
pdp_type.default = "ipv4v6"
pdp_type.rmempty = false
pdp_type:value("ip", translate("IPv4"))
pdp_type:value("ipv6", translate("IPv6"))
pdp_type:value("ipv4v6", translate("IPv4/IPv6"))


-- 接入点
apn = s:taboption("advanced", Value, "apn", translate("APN"))
apn.default = ""
apn.rmempty = true
apn:value("", translate("Auto Choose"))
apn:value("cmnet", translate("China Mobile (CN)"))
apn:value("3gnet", translate("China Unicom (CN)"))
apn:value("ctnet", translate("China Telecom (CN)"))
apn:value("cbnet", translate("China Broadcast (CN)"))
apn:value("5gscuiot", translate("Skytone (CN)"))

-- Switzerland (CH)
apn:value("gprs.swisscom.ch", translate("Swisscom (CH)"))
apn:value("internet", "Salt (CH), Sunrise (CH), O2 (DE), 1&1 (DE)")

-- Germany (DE)
apn:value("web.vodafone.de", translate("Vodafone (DE)"))
apn:value("internet.telekom", translate("Telekom (DE)"))
apn:value("internet.eplus.de", translate("E-Plus (DE)"))

-- Austria (AT)
apn:value("A1.net", translate("A1 (AT)"))
apn:value("drei.at", translate("Drei (AT)"))
apn:value("internet.t-mobile.at", translate("Magenta (AT)"))

-- Philippines (PH)
apn:value("http.globe.com.ph", translate("Globe Prepaid (PH)"))
apn:value("internet.globe.com.ph", translate("Globe Postpaid (PH)"))
apn:value("internet", translate("Smart Communications (PH)"))
apn:value("internet.dito.ph", translate("Dito Telecomunity (PH)"))

auth = s:taboption("advanced", ListValue, "auth", translate("Authentication Type"))
auth.default = "none"
auth.rmempty = false
auth:value("none", translate("NONE"))
auth:value("both", translate("PAP/CHAP (both)"))
auth:value("pap", "PAP")
auth:value("chap", "CHAP")

username = s:taboption("advanced", Value, "username", translate("PAP/CHAP Username"))
username.rmempty = true
username:depends("auth", "both")
username:depends("auth", "pap")
username:depends("auth", "chap")

password = s:taboption("advanced", Value, "password", translate("PAP/CHAP Password"))
password.rmempty = true
password.password = true
password:depends("auth", "both")
password:depends("auth", "pap")
password:depends("auth", "chap")

pincode = s:taboption("advanced", Value, "pincode", translate("PIN Code"))
pincode.description = translate("If the PIN code is not set, leave it blank.")

--卡2
apn = s:taboption("advanced", Value, "apn2", translate("APN").." 2")
apn.description = translate("If slot 2 config is not set,will use slot 1 config.")
apn.default = ""
apn.rmempty = true
apn:value("", translate("Auto Choose"))
apn:value("cmnet", translate("China Mobile (CN)"))
apn:value("3gnet", translate("China Unicom (CN)"))
apn:value("ctnet", translate("China Telecom (CN)"))
apn:value("cbnet", translate("China Broadcast (CN)"))
apn:value("5gscuiot", translate("Skytone (CN)"))

-- Switzerland (CH)
apn:value("gprs.swisscom.ch", translate("Swisscom (CH)"))
apn:value("internet", "Salt (CH), Sunrise (CH), O2 (DE), 1&1 (DE)")

-- Germany (DE)
apn:value("web.vodafone.de", translate("Vodafone (DE)"))
apn:value("internet.telekom", translate("Telekom (DE)"))
apn:value("internet.eplus.de", translate("E-Plus (DE)"))

-- Austria (AT)
apn:value("A1.net", translate("A1 (AT)"))
apn:value("drei.at", translate("Drei (AT)"))
apn:value("internet.t-mobile.at", translate("Magenta (AT)"))

-- Philippines (PH)
apn:value("http.globe.com.ph", translate("Globe Prepaid (PH)"))
apn:value("internet.globe.com.ph", translate("Globe Postpaid (PH)"))
apn:value("internet", translate("Smart Communications (PH)"))
apn:value("internet.dito.ph", translate("Dito Telecomunity (PH)"))


metric = s:taboption("advanced", Value, "metric", translate("Metric"))
metric.description = translate("The metric value is used to determine the priority of the route. The smaller the value, the higher the priority. Cannot duplicate.")
metric.default = "10"



return m
