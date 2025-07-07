module("luci.controller.qmodem_sms", package.seeall)
local http = require "luci.http"
local fs = require "nixio.fs"
local json = require("luci.jsonc")
local modem_ctrl = "/usr/share/qmodem/modem_ctrl.sh "

function shell(command)
	local odpall = io.popen(command)
	local odp = odpall:read("*a")
	odpall:close()
	return odp
end

function index()
    --sim卡配置
	entry({"admin", "modem", "qmodem", "modem_sms"},template("modem_sms/modem_sms"), luci.i18n.translate("SMS"), 11).leaf = true
	entry({"admin", "modem", "qmodem", "send_sms"}, call("sendSMS"), nil).leaf = true
	entry({"admin", "modem", "qmodem", "get_sms"}, call("getSMS"), nil).leaf = true
	entry({"admin", "modem", "qmodem", "delete_sms"}, call("delSMS"), nil).leaf = true
end

function getSMS()
    local cfg_id = http.formvalue("cfg")
    response = shell(modem_ctrl .. "get_sms " .. cfg_id)
    http.prepare_content("application/json")
    http.write(response)
end

function sendSMS()
	local cfg_id = http.formvalue("cfg")
	local pdu = http.formvalue("pdu")
	if pdu then
		response = shell(modem_ctrl .. "send_raw_pdu " .. cfg_id .. " \"" .. pdu .. "\"")
	else
		local phone_number = http.formvalue("phone_number")
		local message_content = http.formvalue("message_content")
		json_cmd = string.format('{\\"phone_number\\":\\"%s\\",\\"message_content\\":\\"%s\\"}', phone_number, message_content)
		response = shell(modem_ctrl .. "send_sms " .. cfg_id .." \"".. json_cmd .. "\"")
		
	end
	http.prepare_content("application/json")
		http.write(response)
end

function delSMS()
	local cfg_id = http.formvalue("cfg")
	local index = http.formvalue("index")
	response = shell(modem_ctrl .. "delete_sms " .. cfg_id .. " \"" ..index.."\"")
	http.prepare_content("application/json")
	http.write(response)
end
