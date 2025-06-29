local util = require "luci.util"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local http = require "luci.http"
local dispatcher = require "luci.dispatcher"
local http = require "luci.http"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local USSD_FILE_PATH = "/etc/config/ussd.user"
local PHB_FILE_PATH = "/etc/config/phonebook.user"
local SMSC_FILE_PATH = "/etc/config/smscommands.user"
local AT_FILE_PATH = "/etc/config/atcmds.user"

local led = tostring(uci:get("sms_tool", "general", "smsled"))
local dsled = tostring(uci:get("sms_tool", "general", "ledtype"))
local ledtime = tostring(uci:get("sms_tool", "general", "checktime"))

local m
local s
local dev1, dev2, dev3, dev4, leds
local try_devices1 = nixio.fs.glob("/dev/tty[A-Z][A-Z]*")
local try_devices2 = nixio.fs.glob("/dev/tty[A-Z][A-Z]*")
local try_devices3 = nixio.fs.glob("/dev/tty[A-Z][A-Z]*")
local try_devices4 = nixio.fs.glob("/dev/tty[A-Z][A-Z]*")
local try_leds = nixio.fs.glob("/sys/class/leds/*")


local devv = tostring(uci:get("sms_tool", "general", "readport"))

local smsmem = tostring(uci:get("sms_tool", "general", "storage"))

local statusb = luci.util.exec("sms_tool -s".. smsmem .. " -d ".. devv .. " status")

local smsnum = string.sub (statusb, 23, 27)

local smscount = string.match(smsnum, '%d+')

m = Map("sms_tool", translate("配置短信工具"),
	translate("sms_tool和gui应用程序的配置面板。"))

s = m:section(NamedSection, 'general' , "sms_tool" , "" .. translate(""))
s.anonymous = true
s:tab("sms", translate("SMS 设置"))
s:tab("ussd", translate("USSD 代码设置"))
s:tab("at", translate("AT 命令设置"))
s:tab("info", translate("通知设置"))

this_tab = "sms"

dev1 = s:taboption(this_tab, Value, "readport", translate("短信读取端口"))
if try_devices1 then
local node
for node in try_devices1 do
dev1:value(node, node)
end
end

mem = s:taboption(this_tab, ListValue, "storage", translate("信息存储区"), translate("信息存储在一个特定的位置（例如，在SIM卡或调制解调器内存），但根据设备的类型，其他区域也可能是可用的。"))
mem.default = "SM"
mem:value("SM", translate("SIM 卡"))
mem:value("ME", translate("调制解调器内存"))
mem.rmempty = true

local msm = s:taboption(this_tab, Flag, "mergesms", translate("合并分割的信息"), translate("勾选这个选项会使阅读信息更容易，但会导致显示和接收的信息数量不一致。"))
msm.rmempty = false

dev2 = s:taboption(this_tab, Value, "sendport", translate("短信发送端口"))
if try_devices2 then
local node
for node in try_devices2 do
dev2:value(node, node)
end
end

local t = s:taboption(this_tab, Value, "pnumber", translate("前缀号码"), translate("电话号码的前面应该有国家的前缀（波兰是48，没有'+'）。如果号码是5个、4个或3个字符，它将被视为 '短'，不应该在前面加上国家前缀。"))
t.rmempty = true
t.default = 48

local f = s:taboption(this_tab, Flag, "prefix", translate("为电话号码添加前缀"), translate("自动添加电话号码字段的前缀。"))
f.rmempty = false


local i = s:taboption(this_tab, Flag, "information", translate("号码和前缀的解释"), translate("在发送短信的标签中，显示前缀的解释和正确的电话号码。"))
i.rmempty = false

local ta = s:taboption(this_tab, TextValue, "user_phonebook", translate("用户电话簿"), translate("每一行必须有以下格式。'联系人姓名;电话号码'。保存到文件'/etc/config/phonebook.user'。"))
ta.rows = 7
ta.rmempty = false

function ta.cfgvalue(self, section)
    return fs.readfile(PHB_FILE_PATH)
end

function ta.write(self, section, value)
    		value = value:gsub("\r\n", "\n")
    		fs.writefile(PHB_FILE_PATH, value)
end

this_taba = "ussd"

dev3 = s:taboption(this_taba, Value, "ussdport", translate("USSD发送端口"))
if try_devices3 then
local node
for node in try_devices3 do
dev3:value(node, node)
end
end

local u = s:taboption(this_taba, Flag, "ussd", translate("以纯文本发送USSD代码"), translate("以纯文本发送USSD代码。命令没有被编码到PDU中。"))
u.rmempty = false

local p = s:taboption(this_taba, Flag, "pdu", translate("接收没有PDU解码的信息"), translate("接收并显示消息，而不将其解码为PDU。"))
p.rmempty = false

local tb = s:taboption(this_taba, TextValue, "user_ussd", translate("用户USSD代码"), translate("每一行必须有以下格式。'代码名称;代码'。保存到文件'/etc/config/ussd.user'。"))
tb.rows = 7
tb.rmempty = true

function tb.cfgvalue(self, section)
    return fs.readfile(USSD_FILE_PATH)
end

function tb.write(self, section, value)
    		value = value:gsub("\r\n", "\n")
    		fs.writefile(USSD_FILE_PATH, value)
end

this_tabc = "at"

dev4 = s:taboption(this_tabc, Value, "atport", translate("AT命令的发送端口"))
if try_devices4 then
local node
for node in try_devices4 do
dev4:value(node, node)
end
end

local tat = s:taboption(this_tabc, TextValue, "user_at", translate("用户AT命令"), translate("每一行必须有以下格式。'AT命令名称;AT命令'。保存到文件'/etc/config/atcmds.user'。"))
tat.rows = 20
tat.rmempty = true

function tat.cfgvalue(self, section)
    return fs.readfile(AT_FILE_PATH)
end

function tat.write(self, section, value)
    		value = value:gsub("\r\n", "\n")
    		fs.writefile(AT_FILE_PATH, value)
end

this_tabb = "info"

local uw = s:taboption(this_tabb, Flag, "lednotify", translate("通知新消息"), translate("LED通知有新的信息。在激活这个功能之前，请配置并保存短信阅读端口，检查短信收件箱的时间，并选择通知LED。"))
uw.rmempty = false

function uw.write(self, section, value)
if devv ~= nil or devv ~= '' then
if ( smscount ~= nil and led ~= nil ) then
    if value == '1' then

       luci.sys.call("echo " .. smscount .. " > /etc/config/sms_count")
	luci.sys.call("uci set sms_tool.general.lednotify=" .. 1 .. ";/etc/init.d/smsled enable;/etc/init.d/smsled start")
	luci.sys.call("/sbin/cronsync.sh")

    elseif value == '0' then
       luci.sys.call("uci set sms_tool.general.lednotify=" .. 0 .. ";/etc/init.d/smsled stop;/etc/init.d/smsled disable")
	    if dsled == 'D' then
		luci.sys.call("echo 0 > '/sys/class/leds/" .. led .. "/brightness'")
	    end
	luci.sys.call("/sbin/cronsync.sh")

    end
return Flag.write(self, section ,value)
  end
end
end

local time = s:taboption(this_tabb, Value, "checktime", translate("每(几)分钟检查一次收件箱"), translate("指定你想在多少分钟内检查你的收件箱。"))
time.rmempty = false
time.maxlength = 2
time.default = 5

function time.validate(self, value)
	if ( tonumber(value) < 60 and tonumber(value) > 0 ) then
	return value
	end
end

sync = s:taboption(this_tabb, ListValue, "prestart", translate("每隔一段时间重新启动收件箱检查程序"), translate("该过程将在选定的时间间隔内重新启动。这将消除检查收件箱的延迟。"))
sync.default = "6"
sync:value("4", translate("4h"))
sync:value("6", translate("6h"))
sync:value("8", translate("8h"))
sync:value("12", translate("12h"))
sync.rmempty = true


leds = s:taboption(this_tabb, Value, "smsled", translate("通知LED"), translate("选择通知LED。"))
if try_leds then
local node
local status
for node in try_leds do
local status = node
local all = string.sub (status, 17)
leds:value(all, all)
end
end

oled = s:taboption(this_tabb, ListValue, "ledtype", translate("该二极管只专门用于这些通知"), translate("如果路由器只有一个LED，或者LED是多任务的，就选'No'。"))
oled.default = "D"
oled:value("S", translate("No"))
oled:value("D", translate("Yes"))
oled.rmempty = true

local timeon = s:taboption(this_tabb, Value, "ledtimeon", translate("每(几)秒打开LED灯"), translate("指定LED应该亮多长时间。"))
timeon.rmempty = false
timeon.maxlength = 3
timeon.default = 1

local timeoff = s:taboption(this_tabb, Value, "ledtimeoff", translate("每(几)秒关闭LED灯"), translate("指定LED应该关闭多长时间。"))
timeoff.rmempty = false
timeoff.maxlength = 3
timeoff.default = 5

return m
