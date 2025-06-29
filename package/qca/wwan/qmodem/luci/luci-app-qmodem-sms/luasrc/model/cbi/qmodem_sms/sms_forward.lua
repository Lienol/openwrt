local uci = require "luci.model.uci".cursor()
local dispatcher = require "luci.dispatcher"
local fs = require "nixio.fs"

m = Map("sms_daemon", translate("SMS Forward Configuration"))
m.redirect = dispatcher.build_url("admin", "modem", "qmodem", "sms_forward")

-- 添加说明信息
m.description = translate("SMS Forward Daemon allows automatic forwarding of SMS messages to various APIs.")


-- 检查sms_forwarder守护进程是否存在
local daemon_exists = fs.access("/usr/bin/sms_forwarder")
if not daemon_exists then
    s_warning = m:section(SimpleSection)
    s_warning.template = "cbi/nullsection" 
    local warning_html = "<div class='alert-message warning'>" ..
        "<strong>" .. translate("Warning") .. ":</strong> " ..
        translate("SMS Forwarder binary not found at /usr/bin/sms_forwarder. Please install the sms_forwarder package.") ..
        "</div>"
    s_warning.render = function(self, section)
        return warning_html
    end
end

-- SMS转发总开关
s = m:section(NamedSection, "sms_forward", "sms_forward", translate("SMS Forward Service"))
s.addremove = false

enable = s:option(Flag, "enable", translate("Enable SMS Forward Service"))
enable.default = "0"
enable.rmempty = false
enable.description = translate("Enable the SMS forward daemon service. When enabled, the daemon will start automatically.")

-- 全局配置选项
log_level = s:option(ListValue, "log_level", translate("Log Level"))
log_level:value("error", translate("Error"))
log_level:value("warning", translate("Warning"))  
log_level:value("info", translate("Information"))
log_level:value("debug", translate("Debug"))
log_level.default = "info"
log_level.description = translate("Set the logging verbosity level for the SMS daemon.")

-- SMS转发实例配置
s2 = m:section(TypedSection, "sms_forward_instance", translate("SMS Forward Instances"))
s2.addremove = true
s2.anonymous = false
s2.template = "cbi/tblsection"
s2.extedit = dispatcher.build_url("admin", "modem", "qmodem", "sms_forward_extedit", "%s")
s2.description = translate("Configure multiple SMS forward instances. Each instance can monitor a different modem port and forward to different APIs.")

-- 实例启用开关
instance_enable = s2:option(Flag, "enable", translate("Enable"))
instance_enable.width = "8%"
instance_enable.default = "0"

-- 监听端口
listen_port = s2:option(ListValue, "listen_port", translate("Modem Port"))
listen_port.width = "18%"
listen_port.rmempty = false

-- 获取可用的AT端口
uci:foreach("qmodem", "modem-device", function(section)
    local ports = section.ports or {}
    local valid_ports = section.valid_at_ports or {}
    
    if type(ports) == "table" then
        for _, port in ipairs(ports) do
            local valid = false
            if type(valid_ports) == "table" then
                for _, valid_port in ipairs(valid_ports) do
                    if port == valid_port then
                        valid = true
                        break
                    end
                end
            end
            
            local display_name = port
            if valid then
                display_name = port .. " (" .. translate("VALID") .. ")"
            else
                display_name = port .. " (" .. translate("INVALID") .. ")"
            end
            listen_port:value(port, display_name)
        end
    end
end)

-- 如果没有找到端口，添加常见的端口选项
if next(listen_port.keylist) == nil then
    for i = 0, 7 do
        listen_port:value("/dev/ttyUSB" .. i, "/dev/ttyUSB" .. i)
    end
    for i = 0, 3 do
        listen_port:value("/dev/ttyACM" .. i, "/dev/ttyACM" .. i)
    end
end

-- 轮询间隔
poll_interval = s2:option(Value, "poll_interval", translate("Poll Interval"))
poll_interval.width = "12%"
poll_interval.datatype = "range(15,600)"
poll_interval.default = "30"
poll_interval.description = translate("Polling interval in seconds (15-600)")

-- API类型
api_type = s2:option(ListValue, "api_type", translate("API Type"))
api_type.width = "15%"
api_type:value("tgbot", translate("Telegram Bot"))
api_type:value("webhook", translate("Webhook"))
api_type:value("serverchan", translate("ServerChan"))
api_type:value("pushdeer", translate("PushDeer"))
api_type:value("custom_script", translate("Custom Script"))
api_type:value("feishu", translate("Feishu Bot"))

-- 删除已转发短信选项
delete_after_forward = s2:option(Flag, "delete_after_forward", translate("Delete After Forward"))
delete_after_forward.width = "12%"
delete_after_forward.default = "0"
delete_after_forward.description = translate("Delete SMS messages from modem after successful forwarding")

if fs.stat("/tmp/sms_forwarder_combined.json") then
--读取 /tmp/sms_forwarder_combined.json 的内容并展示（只读）
    c = s:option(TextValue, "_c", translate("SMS Forwarder Configuration"))
    c.readonly = true
    c.rows = 15

    v = fs.readfile("/tmp/sms_forwarder_combined.json")
    c.cfgvalue = function()
        return v
    end
end
return m
