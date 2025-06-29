local uci = require "luci.model.uci".cursor()
local dispatcher = require "luci.dispatcher"
local fs = require "nixio.fs"
local json = require "luci.jsonc"



m = Map("sms_daemon", translate("SMS Forward Advanced Configuration"))
m.redirect = dispatcher.build_url("admin", "modem", "qmodem", "sms_forward")

-- 添加说明信息
m.description = translate("Advanced SMS Forward configuration with type-specific options.")

-- SMS转发实例配置
s2 = m:section(NamedSection, arg[1], "sms_forward_instance",translate("SMS Forward Instances"))
s2.addremove = true
s2.anonymous = false

-- 实例启用开关
instance_enable = s2:option(Flag, "enable", translate("Enable"))
instance_enable.default = "0"

-- 监听端口
listen_port = s2:option(ListValue, "listen_port", translate("Modem Port"))
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
poll_interval.datatype = "range(15,600)"
poll_interval.default = "30"
poll_interval.description = translate("Polling interval in seconds (15-600)")

-- API类型
api_type = s2:option(ListValue, "api_type", translate("API Type"))
api_type:value("tgbot", translate("Telegram Bot"))
api_type:value("webhook", translate("Webhook"))
api_type:value("serverchan", translate("ServerChan"))
api_type:value("pushdeer", translate("PushDeer"))
api_type:value("custom_script", translate("Custom Script"))
api_type:value("feishu", translate("Feishu Bot"))

-- 删除已转发短信选项
delete_after_forward = s2:option(Flag, "delete_after_forward", translate("Delete After Forward"))
delete_after_forward.default = "0"
delete_after_forward.description = translate("Delete SMS messages from modem after successful forwarding. This helps keep the modem's SMS storage clean but messages will be permanently removed.")

-- Telegram Bot 配置
tg_bot_token = s2:option(Value, "tg_bot_token", translate("Bot Token"))
tg_bot_token:depends("api_type", "tgbot")
tg_bot_token.placeholder = "123456:ABC-DEF1234ghIkl"

tg_chat_id = s2:option(Value, "tg_chat_id", translate("Chat ID"))
tg_chat_id:depends("api_type", "tgbot")
tg_chat_id.placeholder = "123456789"

-- Webhook 配置
webhook_url = s2:option(Value, "webhook_url", translate("Webhook URL"))
webhook_url:depends("api_type", "webhook")
webhook_url.placeholder = "https://example.com/webhook"
webhook_url.description = translate("URL of the webhook endpoint(Also supports placeholders:" ) .. "{SENDER}, {CONTENT}, {TIME})" .. translate(" and need to be URL encoded)")

webhook_headers = s2:option(Value, "webhook_headers", translate("Headers (optional)"))
webhook_headers:depends("api_type", "webhook")
webhook_headers.placeholder = "Authorization: Bearer token"

webhook_format = s2:option(Value, "webhook_format", translate("Message Format (optional)"))
webhook_format:depends("api_type", "webhook")
webhook_format.placeholder = "{SENDER}/{CONTENT}({TIME})"
webhook_format.description = translate("Custom message format using placeholders:") .. " {SENDER}, {CONTENT}, {TIME}"
webhook_request_method = s2:option(ListValue, "webhook_request_method", translate("Request Method"))
webhook_request_method:depends("api_type", "webhook")
webhook_request_method:value("GET", "GET")
webhook_request_method:value("POST", "POST")

-- ServerChan 配置
serverchan_token = s2:option(Value, "serverchan_token", translate("Token"))
serverchan_token:depends("api_type", "serverchan")
serverchan_token.placeholder = "SCT123456TCxyz..."
serverchan_token.description = translate("ServerChan API token from https://sctapi.ftqq.com")

serverchan_channel = s2:option(Value, "serverchan_channel", translate("Channel (optional)"))
serverchan_channel:depends("api_type", "serverchan")
serverchan_channel.placeholder = "9|66"
serverchan_channel.description = translate("Message channel, use | to separate multiple channels")

serverchan_noip = s2:option(Flag, "serverchan_noip", translate("Hide IP"))
serverchan_noip:depends("api_type", "serverchan")
serverchan_noip.description = translate("Hide caller IP address")

serverchan_openid = s2:option(Value, "serverchan_openid", translate("OpenID (optional)"))
serverchan_openid:depends("api_type", "serverchan")
serverchan_openid.placeholder = "openid1,openid2"
serverchan_openid.description = translate("OpenID for message forwarding, use comma to separate multiple IDs")

-- PushDeer 配置
pushdeer_push_key = s2:option(Value, "pushdeer_push_key", translate("Push Key"))
pushdeer_push_key:depends("api_type", "pushdeer")
pushdeer_push_key.placeholder = "PDU123456T..."
pushdeer_push_key.description = translate("PushDeer Push Key from http://pushdeer.com")

pushdeer_endpoint = s2:option(Value, "pushdeer_endpoint", translate("API Endpoint (optional)"))
pushdeer_endpoint:depends("api_type", "pushdeer")
pushdeer_endpoint.placeholder = "https://api2.pushdeer.com"
pushdeer_endpoint.description = translate("Custom PushDeer API endpoint, leave empty to use default")

feishu_webhook_key = s2:option(Value, "feishu_webhook_key", translate("Feishu Webhook Key"))
feishu_webhook_key:depends("api_type", "feishu")
feishu_webhook_key.placeholder = "xxxxxx"
feishu_webhook_key.description = translate("Feishu Webhook Key from your Feishu bot configuration")


-- Custom Script 配置
custom_script_path = s2:option(Value, "custom_script_path", translate("Script Path"))
custom_script_path:depends("api_type", "custom_script")
custom_script_path.placeholder = "/usr/bin/my_sms_script.sh"

return m
