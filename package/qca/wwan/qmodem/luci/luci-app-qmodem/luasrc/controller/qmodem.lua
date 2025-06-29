-- Copyright 2024 Siriling <siriling@qq.com>
-- Copyright 2024 FJR <fjrcn@outlook.com>
module("luci.controller.qmodem", package.seeall)
local http = require "luci.http"
local fs = require "nixio.fs"
local json = require("luci.jsonc")
uci = luci.model.uci.cursor()
local script_path="/usr/share/qmodem/"
local run_path="/tmp/run/qmodem/"
local modem_ctrl = "/usr/share/qmodem/modem_ctrl.sh "

function index()
    if not nixio.fs.access("/etc/config/qmodem") then
        return
    end
	entry({"admin", "modem"}, firstchild(), _("Modem"), 25).dependent=false
	entry({"admin", "modem", "qmodem"}, alias("admin", "modem", "qmodem", "modem_info"), luci.i18n.translate("QModem"), 100).dependent = true
	--模块信息
	entry({"admin", "modem", "qmodem", "modem_info"}, template("qmodem/modem_info"), luci.i18n.translate("QModem Information"),2).leaf = true
	entry({"admin", "modem", "qmodem", "get_modem_cfg"}, call("getModemCFG"), nil).leaf = true
	entry({"admin", "modem", "qmodem", "modem_ctrl"}, call("modemCtrl")).leaf = true
	--拨号配置
	entry({"admin", "modem", "qmodem", "dial_overview"},cbi("qmodem/dial_overview"),luci.i18n.translate("Dial Overview"),3).leaf = true
	entry({"admin", "modem", "qmodem", "dial_config"}, cbi("qmodem/dial_config")).leaf = true
	entry({"admin", "modem", "qmodem", "modems_dial_overview"}, call("getOverviews"), nil).leaf = true
	--模块调试
	entry({"admin", "modem", "qmodem", "modem_debug"},template("qmodem/modem_debug"),luci.i18n.translate("Advance Modem Settings"),4).leaf = true
	entry({"admin", "modem", "qmodem", "send_at_command"}, call("sendATCommand"), nil).leaf = true

	--Qmodem设置
	entry({"admin", "modem", "qmodem", "settings"}, cbi("qmodem/settings"), luci.i18n.translate("QModem Settings"),100).leaf = true
	entry({"admin", "modem", "qmodem", "slot_config"}, cbi("qmodem/slot_config")).leaf = true
	entry({"admin", "modem", "qmodem", "modem_config"}, cbi("qmodem/modem_config")).leaf = true
end

--[[
@Description 执行Shell脚本
@Params
	command sh命令
]]
function shell(command)
	local odpall = io.popen(command)
	local odp = odpall:read("*a")
	odpall:close()
	return odp
end

function translate_modem_info(result)
	modem_info = result["modem_info"]
	response = {}
	for k,entry in pairs(modem_info) do
		if type(entry) == "table" then
			key = entry["key"]
			full_name = entry["full_name"]
			if full_name then
				full_name = luci.i18n.translate(full_name)
			elseif key then
				full_name = luci.i18n.translate(key)
			end
			entry["full_name"] = full_name
			if entry["class"] then
				entry["class"] = luci.i18n.translate(entry["class"])
			end
			table.insert(response, entry)
		end
	end
	return response
end

function modemCtrl()
	local action = http.formvalue("action")
	local cfg_id = http.formvalue("cfg")
	local params = http.formvalue("params")
	local translate = http.formvalue("translate")
	if params then
		result = shell(modem_ctrl..action.." "..cfg_id.." ".."\""..params.."\"")
	else 
		result = shell(modem_ctrl..action.." "..cfg_id)
	end
	if translate == "1" then
		modem_more_info = json.parse(result)
		modem_more_info = translate_modem_info(modem_more_info)
		result = json.stringify(modem_more_info)
	end
	luci.http.prepare_content("application/json")
	luci.http.write(result)
end

--[[
@Description 执行AT命令
@Params
	at_port AT串口
	at_command AT命令
]]
function at(at_port,at_command)
	local command="source "..script_path.."modem_util.sh && at "..at_port.." "..at_command
	local result=shell(command)
	result=string.gsub(result, "\r", "")
	return result
end


--[[
@Description 获取模组信息
]]
function getOverviews()
	-- 获取所有模组
	local modems={}
	local logs={}
	uci:foreach("qmodem", "modem-device", function (modem_device)
		section_name = modem_device[".name"]
		modem_name = modem_device["name"] or luci.i18n.translate("Unknown")
		alias = modem_device["alias"]
		modem_state = modem_device["state"]
		if modem_state == "disabled" then
			return
		end
--模组信息部分
		cmd = modem_ctrl.."base_info "..section_name
		result = shell(cmd)
		json_result = json.parse(result) or "{}"
		modem_info = json_result["modem_info"]
		tmp_info = {}
		if alias then
			title = alias .. "("..modem_name..")"
		else
			title = modem_name
		end
		name = {
			type = "plain_text",
			key = "name",
			value = title
		}
		table.insert(tmp_info, name)
		for k,v in pairs(modem_info) do
			full_name = v["full_name"]
			if full_name then
				v["full_name"] = luci.i18n.translate(full_name)
			end
			table.insert(tmp_info, v)
		end
		table.insert(modems, tmp_info)
	--拨号日志部分
	log_path = run_path..section_name.."_dir/dial_log"
	if fs.access(log_path) then
		log_msg = fs.readfile(log_path)
		modem_log = {}
		modem_log["log_msg"] = log_msg
		modem_log["section_name"] = section_name
		if alias then
			modem_log["name"] = alias .. "("..modem_name..")"
		else
			modem_log["name"] = modem_name
		end
		table.insert(logs, modem_log)
	end
	end)
	
	-- 设置值
	local data={}
	data["modems"]=modems
	data["logs"]=logs
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

function getModemCFG()

	local cfgs={}
	local translation={}

	uci:foreach("qmodem", "modem-device", function (modem_device)
		modem_state = modem_device["state"]
		if modem_state == "disabled" then
			return
		end
		--获取模组的备注
		local network=modem_device["modem"]
		local alias=modem_device["alias"]
		local config_name=modem_device[".name"]
		--设置模组AT串口
		local cfg = modem_device[".name"]
		if modem_device["at_port"] ~= nil then
			local at_port=modem_device["at_port"]
			local name=modem_device["name"]:upper()
			local config = {}
			if alias then
				config["name"] = alias .. "("..name..")"
			else
				config["name"] = name
			end
			config["at_port"] = at_port
			config["cfg"] = cfg
			table.insert(cfgs, config)
		end
	end)

	-- 设置值
	local data={}
	data["cfgs"]=cfgs
	data["translation"]=translation

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end



function sendATCommand()
    local at_port = http.formvalue("port")
	local at_command = http.formvalue("command")

	local response={}
    if at_port and at_command then
		response["response"]=at(at_port,at_command)
		response["time"]=os.date("%Y-%m-%d %H:%M:%S")
    end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(response)
end
