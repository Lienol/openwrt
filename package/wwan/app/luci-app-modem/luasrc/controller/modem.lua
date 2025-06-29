-- Copyright 2024 Siriling <siriling@qq.com>
module("luci.controller.modem", package.seeall)
local http = require "luci.http"
local fs = require "nixio.fs"
local json = require("luci.jsonc")
uci = luci.model.uci.cursor()
local script_path="/usr/share/modem/"
local run_path="/tmp/run/modem/"

function index()
    if not nixio.fs.access("/etc/config/modem") then
        return
    end

	entry({"admin", "network", "modem"}, alias("admin", "network", "modem", "modem_info"), translate("Modem"), 100).dependent = true

	--模块信息
	entry({"admin", "network", "modem", "modem_info"}, template("modem/modem_info"), translate("Modem Information"),10).leaf = true
	entry({"admin", "network", "modem", "get_at_port"}, call("getATPort"), nil).leaf = true
	entry({"admin", "network", "modem", "get_modem_info"}, call("getModemInfo")).leaf = true

	--拨号配置
	entry({"admin", "network", "modem", "dial_overview"},cbi("modem/dial_overview"),translate("Dial Overview"),20).leaf = true
	entry({"admin", "network", "modem", "dial_config"}, cbi("modem/dial_config")).leaf = true
	entry({"admin", "network", "modem", "get_modems"}, call("getModems"), nil).leaf = true
	entry({"admin", "network", "modem", "get_dial_log_info"}, call("getDialLogInfo"), nil).leaf = true
	entry({"admin", "network", "modem", "clean_dial_log"}, call("cleanDialLog"), nil).leaf = true
	entry({"admin", "network", "modem", "status"}, call("act_status")).leaf = true

	--模块调试
	entry({"admin", "network", "modem", "modem_debug"},template("modem/modem_debug"),translate("Modem Debug"),30).leaf = true
	entry({"admin", "network", "modem", "quick_commands_config"}, cbi("modem/quick_commands_config")).leaf = true
	entry({"admin", "network", "modem", "get_mode_info"}, call("getModeInfo"), nil).leaf = true
	entry({"admin", "network", "modem", "set_mode"}, call("setMode"), nil).leaf = true
	entry({"admin", "network", "modem", "get_network_prefer_info"}, call("getNetworkPreferInfo"), nil).leaf = true
	entry({"admin", "network", "modem", "set_network_prefer"}, call("setNetworkPrefer"), nil).leaf = true
	entry({"admin", "network", "modem", "set_band_prefer"}, call("setBandPrefer"), nil).leaf = true
	entry({"admin", "network", "modem", "get_self_test_info"}, call("getSelfTestInfo"), nil).leaf = true
	entry({"admin", "network", "modem", "get_quick_commands"}, call("getQuickCommands"), nil).leaf = true
	entry({"admin", "network", "modem", "send_at_command"}, call("sendATCommand"), nil).leaf = true
	-- entry({"admin", "network", "modem", "get_modem_debug_info"}, call("getModemDebugInfo"), nil).leaf = true

	--插件设置
	entry({"admin", "network", "modem", "plugin_config"},cbi("modem/plugin_config"),translate("Plugin Config"),40).leaf = true
	entry({"admin", "network", "modem", "modem_config"}, cbi("modem/modem_config")).leaf = true
	entry({"admin", "network", "modem", "modem_scan"}, call("modemScan"), nil).leaf = true

	--插件信息
	entry({"admin", "network", "modem", "plugin_info"},template("modem/plugin_info"),translate("Plugin Info"),50).leaf = true
	entry({"admin", "network", "modem", "get_plugin_info"}, call("getPluginInfo"), nil).leaf = true

	--AT命令旧界面
	entry({"admin", "network", "modem", "at_command_old"},template("modem/at_command_old")).leaf = true
end

--[[
@Description 判断字符串是否含有字母
@Params
	str 字符串
]]
function hasLetters(str)
    local pattern = "%a" -- 匹配字母的正则表达式
    return string.find(str, pattern) ~= nil
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

--[[
@Description 执行AT命令
@Params
	at_port AT串口
	at_command AT命令
]]
function at(at_port,at_command)
	local command="source "..script_path.."modem_debug.sh && at "..at_port.." "..at_command
	local result=shell(command)
	result=string.gsub(result, "\r", "")
	return result
end

--[[
@Description 获取制造商
@Params
	at_port AT串口
]]
function getManufacturer(at_port)

	local manufacturer
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			manufacturer=modem_device["manufacturer"]
			return true --跳出循环
		end
	end)

	return manufacturer
end

--[[
@Description 获取模组拨号模式
@Params
	at_port AT串口
	manufacturer 制造商
	platform 平台
]]
function getMode(at_port,manufacturer,platform)
	local mode="unknown"

	if at_port and manufacturer~="unknown" then
		local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_mode "..at_port.." "..platform
		local result=shell(command)
		mode=string.gsub(result, "\n", "")
	end

	return mode
end

--[[
@Description 获取模组支持的拨号模式
@Params
	at_port AT串口
]]
function getModes(at_port)

	local modes
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			modes=modem_device["modes"]
			return true --跳出循环
		end
	end)

	return modes
end

--[[
@Description 获取模组连接状态
@Params
	at_port AT串口
	manufacturer 制造商
	define_connect 连接定义
]]
function getModemConnectStatus(at_port,manufacturer,define_connect)

	local connect_status="unknown"

	if at_port and manufacturer~="unknown" then
		local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_connect_status "..at_port.." "..define_connect
		local result=shell(command)
		connect_status=string.gsub(result, "\n", "")
	end

	return connect_status
end

--[[
@Description 获取模组设备信息
@Params
	at_port AT串口
]]
function getModemDeviceInfo(at_port)
	local modem_device_info={}

	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			--获取数据接口
			local data_interface=modem_device["data_interface"]:upper()
			--获取网络驱动
			local net_driver=modem_device["net_driver"]
			--获取连接状态
			local connect_status=getModemConnectStatus(modem_device["at_port"],modem_device["manufacturer"],modem_device["define_connect"])

			--设置值
			modem_device_info=modem_device
			modem_device_info["data_interface"]=data_interface
			modem_device_info["net_driver"]=net_driver
			modem_device_info["connect_status"]=connect_status
			return true
		end
	end)

	return modem_device_info
end

--[[
@Description 获取模组更多信息
@Params
	at_port AT串口
	manufacturer 制造商
]]
function getModemMoreInfo(at_port,manufacturer,platform,define_connect)

	--获取模组信息
	local command="sh "..script_path.."modem_info.sh".." "..at_port.." "..manufacturer.." "..platform.." "..define_connect
	local result=shell(command)

	--设置值
	local modem_more_info=json.parse(result)
	return modem_more_info
end

--[[
@Description 模块状态获取
]]
function getModemInfo()

	--获取AT串口
    local at_port = http.formvalue("port")

	--获取信息
	local modem_device_info
	local modem_more_info
	if at_port then
		modem_device_info=getModemDeviceInfo(at_port)
		modem_more_info=getModemMoreInfo(at_port,modem_device_info["manufacturer"],modem_device_info["platform"],modem_device_info["define_connect"])
	end

	--设置信息
	local modem_info={}
	modem_info["device_info"]=modem_device_info
	modem_info["more_info"]=modem_more_info

	--设置翻译
	local translation={}
	--设备信息翻译
	-- if modem_device_info then
	-- 	local name=modem_device_info["name"]
	-- 	translation[name]=luci.i18n.translate(name)
	-- 	local manufacturer=modem_device_info["manufacturer"]
	-- 	translation[manufacturer]=luci.i18n.translate(manufacturer)
	-- 	local mode=modem_device_info["mode"]
	-- 	translation[mode]=luci.i18n.translate(mode)
	-- 	local data_interface=modem_device_info["data_interface"]
	-- 	translation[data_interface]=luci.i18n.translate(data_interface)
	-- 	local network=modem_device_info["network"]
	-- 	translation[network]=luci.i18n.translate(network)
	-- end

	--基本信息翻译
	-- if modem_more_info["base_info"] then
	-- 	for key in pairs(modem_more_info["base_info"]) do
	-- 		local value=modem_more_info["base_info"][key]
	-- 		--翻译值
	-- 		translation[value]=luci.i18n.translate(value)
	-- 	end
	-- end
	--SIM卡信息翻译
	if modem_more_info["sim_info"] then
		local sim_info=modem_more_info["sim_info"]
		for i = 1, #sim_info do
			local info = sim_info[i]
			for key in pairs(info) do
				--翻译键
				translation[key]=luci.i18n.translate(key)
				-- local value=info[key]
				-- if hasLetters(value) then
				-- 	--翻译值
				-- 	translation[value]=luci.i18n.translate(value)
				-- end
			end
		end
	end
	--网络信息翻译
	if modem_more_info["network_info"] then
		local network_info=modem_more_info["network_info"]
		for i = 1, #network_info do
			local info = network_info[i]
			for key in pairs(info) do
				--翻译键
				translation[key]=luci.i18n.translate(key)
				-- local value=info[key]
				-- if hasLetters(value) then
				-- 	--翻译值
				-- 	translation[value]=luci.i18n.translate(value)
				-- end
			end
		end
	end
	--小区信息翻译
	if modem_more_info["cell_info"] then
		for network_mode_key in pairs(modem_more_info["cell_info"]) do
			--翻译网络模式
			translation[network_mode_key]=luci.i18n.translate(network_mode_key)
			if network_mode_key == "EN-DC Mode" then
				local network_mode=modem_more_info["cell_info"][network_mode_key]
				for i = 1, #network_mode do
					for key in pairs(network_mode[i]) do
						--获取每个网络类型信息
						local network_type=network_mode[i][key]
						for j = 1, #network_type do
							local info = network_type[j]
							for key in pairs(info) do
								translation[key]=luci.i18n.translate(key)
							end
						end
					end
				end
			else
				--获取网络类型信息
				local network_type=modem_more_info["cell_info"][network_mode_key]
				for i = 1, #network_type do
					local info = network_type[i]
					for key in pairs(info) do
						translation[key]=luci.i18n.translate(key)
					end
				end
			end
		end
	end
	--添加额外翻译
	translation["Unknown"]=luci.i18n.translate("Unknown")
	translation["Excellent"]=luci.i18n.translate("Excellent")
	translation["Good"]=luci.i18n.translate("Good")
	translation["Fair"]=luci.i18n.translate("Fair")
	translation["Bad"]=luci.i18n.translate("Bad")

	--整合数据
	local data={}
	data["modem_info"]=modem_info
	data["translation"]=translation
	
	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 获取模组信息
]]
function getModems()
	
	-- 获取所有模组
	local modems={}
	local translation={}
	uci:foreach("modem", "modem-device", function (modem_device)
		-- 获取连接状态
		local connect_status=getModemConnectStatus(modem_device["at_port"],modem_device["manufacturer"],modem_device["define_connect"])
		-- 获取拨号模式
		local mode=getMode(modem_device["at_port"],modem_device["manufacturer"],modem_device["platform"])

		-- 获取翻译
		translation[connect_status]=luci.i18n.translate(connect_status)
		if modem_device["name"] then
			translation[modem_device["name"]]=luci.i18n.translate(modem_device["name"])
		end
		translation[mode]=luci.i18n.translate(mode)

		-- 设置值
		local modem=modem_device
		modem["connect_status"]=connect_status
		modem["mode"]=mode

		local modem_tmp={}
		modem_tmp[modem_device[".name"]]=modem
		table.insert(modems,modem_tmp)
	end)
	
	-- 设置值
	local data={}
	data["modems"]=modems
	data["translation"]=translation

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 获取拨号日志信息
]]
function getDialLogInfo()
	
	local command="find "..run_path.." -name \"modem*_dial.cache\""
	local result=shell(command)

	local log_paths=string.split(result, "\n")
	table.sort(log_paths)

	local logs={}
	local names={}
	local translation={}
	for key in pairs(log_paths) do

		local log_path=log_paths[key]

		if log_path ~= "" then
			-- 获取模组
			local tmp=string.gsub(log_path, run_path, "")
			local modem=string.gsub(tmp, "_dial.cache", "")
			local modem_name=uci:get("modem", modem, "name")

			-- 获取日志内容
			local command="cat "..log_path
			log=shell(command)

			-- 排序插入
			modem_log={}
			modem_log[modem]=log
			table.insert(logs, modem_log)

			--设置模组名
			names[modem]=modem_name
			-- 设置翻译
			translation[modem_name]=luci.i18n.translate(modem_name)
		end
	end

	-- 设置值
	local data={}
	data["dial_log_info"]=logs
	data["modem_name_info"]=names
	data["translation"]=translation

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 清空拨号日志
]]
function cleanDialLog()
	
	-- 获取拨号日志路径
    local dial_log_path = http.formvalue("path")

	-- 清空拨号日志
	local command=": > "..dial_log_path
	shell(command)

	-- 设置值
	local data={}
	data["clean_result"]="clean dial log"

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 模块列表状态函数
]]
function act_status()
	local e = {}
	e.index = luci.http.formvalue("index")
	e.status = luci.sys.call(string.format("busybox ps -w | grep -v 'grep' | grep '/var/etc/socat/%s' >/dev/null", luci.http.formvalue("id"))) == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

--[[
@Description 获取模组的备注
@Params
	network 移动网络
]]
function getModemRemarks(network)
	local remarks=""
	uci:foreach("modem", "dial-config", function (config)
		---配置启用，且备注存在
		if network == config["network"] and config["enable"] == "1" then
			if config["remarks"] then
				remarks=" ("..config["remarks"]..")" --" (备注)"
				
				return true --跳出循环
			end
		end
	end)
	return remarks
end

--[[
@Description 获取AT串口
]]
function getATPort()

	local at_ports={}
	local translation={}

	uci:foreach("modem", "modem-device", function (modem_device)
		--获取模组的备注
		local network=modem_device["network"]
		local remarks=getModemRemarks(network)

		--设置模组AT串口
		if modem_device["name"] and modem_device["at_port"] then
			
			local name=modem_device["name"]:upper()..remarks
			if modem_device["name"] == "unknown" then
				translation[modem_device["name"]]=luci.i18n.translate(modem_device["name"])
				name=modem_device["name"]..remarks
			end

			local at_port = modem_device["at_port"]
			--排序插入
			at_port_tmp={}
			at_port_tmp[at_port]=name
			table.insert(at_ports, at_port_tmp)
		end
	end)

	-- 设置值
	local data={}
	data["at_ports"]=at_ports
	data["translation"]=translation

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 获取拨号模式信息
]]
function getModeInfo()
	local at_port = http.formvalue("port")

	--获取值
	local mode_info={}
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then

			--获取制造商
			local manufacturer=modem_device["manufacturer"]
			if manufacturer=="unknown" then
				return true --跳出循环
			end

			--获取支持的拨号模式
			local modes=modem_device["modes"]

			--获取模组拨号模式
			local mode=getMode(at_port,manufacturer,modem_device["platform"])

			--设置模式信息
			mode_info["mode"]=mode
			mode_info["modes"]=modes

			return true --跳出循环
		end
	end)
	
	--设置值
	local modem_debug_info={}
	modem_debug_info["mode_info"]=mode_info

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(modem_debug_info)
end

--[[
@Description 设置拨号模式
]]
function setMode()
    local at_port = http.formvalue("port")
	local mode_config = http.formvalue("mode_config")

	--获取制造商
	local manufacturer=getManufacturer(at_port)

	--设置模组拨号模式
	local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_set_mode "..at_port.." "..mode_config
	shell(command)

	--获取设置好后的模组拨号模式
	local mode
	if at_port and manufacturer and manufacturer~="unknown" then
		local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_mode "..at_port
		local result=shell(command)
		mode=string.gsub(result, "\n", "")
	end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(mode)
end

--[[
@Description 获取网络偏好信息
]]
function getNetworkPreferInfo()
	local at_port = http.formvalue("port")
	
	--获取制造商，数据接口，模组名称
	local manufacturer
	local data_interface
	local name
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			manufacturer=modem_device["manufacturer"]
			data_interface=modem_device["data_interface"]
			name=modem_device["name"]
			return true --跳出循环
		end
	end)

	--获取值
	local network_prefer_info
	if manufacturer~="unknown" then
		--获取模组网络偏好
		local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_network_prefer "..at_port.." "..data_interface.." "..name
		local result=shell(command)
		network_prefer_info=json.parse(result)
	end

	--设置值
	local modem_debug_info={}
	modem_debug_info["network_prefer_info"]=network_prefer_info

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(modem_debug_info)
end

--[[
@Description 设置网络偏好
]]
function setNetworkPrefer()
    local at_port = http.formvalue("port")
	local network_prefer_config = json.stringify(http.formvalue("prefer_config"))

	--获取制造商，数据接口，模组名称
	local manufacturer
	local data_interface
	local name
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			manufacturer=modem_device["manufacturer"]
			data_interface=modem_device["data_interface"]
			name=modem_device["name"]
			return true --跳出循环
		end
	end)

	--设置模组网络偏好
	local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_set_network_prefer "..at_port.." "..network_prefer_config
	shell(command)

	--获取设置好后的模组网络偏好
	local network_prefer={}
	-- if at_port and manufacturer and manufacturer~="unknown" then
	-- 	local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_network_prefer "..at_port.." "..data_interface.." "..name
	-- 	local result=shell(command)
	-- 	network_prefer=json.parse(result)
	-- end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(network_prefer)
end

--[[
@Description 设置频段偏好
]]
function setBandPrefer()
    local at_port = http.formvalue("port")
	local network_prefer_config = json.stringify(http.formvalue("prefer_config"))

	--获取制造商，数据接口，模组名称
	local manufacturer
	local data_interface
	local name
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			manufacturer=modem_device["manufacturer"]
			data_interface=modem_device["data_interface"]
			name=modem_device["name"]
			return true --跳出循环
		end
	end)

	--设置模组网络偏好
	local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_set_band_prefer "..at_port.." "..network_prefer_config
	shell(command)

	--获取设置好后的模组网络偏好
	local network_prefer={}
	-- if at_port and manufacturer and manufacturer~="unknown" then
	-- 	local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_network_prefer "..at_port.." "..data_interface.." "..name
	-- 	local result=shell(command)
	-- 	network_prefer=json.parse(result)
	-- end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(network_prefer)
end

--[[
@Description 获取自检信息
]]
function getSelfTestInfo()
	local at_port = http.formvalue("port")
	
	--获取制造商
	local manufacturer=getManufacturer(at_port)

	--获取值
	local self_test_info={}
	if manufacturer~="unknown" then
		--获取模组电压
		local command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_voltage "..at_port
		local result=shell(command)
		self_test_info["voltage"]=json.parse(result)

		--获取模组温度
		command="source "..script_path..manufacturer..".sh && "..manufacturer.."_get_temperature "..at_port
		result=shell(command)
		self_test_info["temperature"]=json.parse(result)
	end

	--设置值
	local modem_debug_info={}
	modem_debug_info["self_test_info"]=self_test_info
	
	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(modem_debug_info)
end

--[[
@Description 获取快捷命令
]]
function getQuickCommands()

	--获取快捷命令选项
	local quick_option = http.formvalue("option")
	--获取AT串口
	local at_port = http.formvalue("port")

	local manufacturer
	local platform
	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			--获取制造商
			manufacturer=modem_device["manufacturer"]
			--获取平台
			platform=modem_device["platform"]
			return true --跳出循环
		end
	end)

	--未适配模组时，快捷命令选项为自定义
	if manufacturer=="unknown" or manufacturer=="unknown" then
		quick_option="custom"
	end

	local quick_commands={}
	local commands={}
	if quick_option=="auto" then

		--获取通用模组AT命令
		local command="jq '.quick_commands.general' \""..script_path.."at_commands.json\""
		local result=shell(command)
		local general_commands=json.parse(result)

		--获取特殊模组AT命令
		command="jq '.quick_commands."..manufacturer.."."..platform.."' \""..script_path.."at_commands.json\""
		result=shell(command)
		local special_commands=json.parse(result)

		--把通用命令和特殊命令整合到一起
		for i = 1, #special_commands do
			local special_command = special_commands[i]
			table.insert(general_commands,special_command)
		end

		quick_commands["quick_commands"]=general_commands
	else
		uci:foreach("custom_at_commands", "custom-commands", function (custom_commands)
			local command={}
			command[custom_commands["description"]]=custom_commands["command"]
			table.insert(commands,command)
		end)
		quick_commands["quick_commands"]=commands
	end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(quick_commands)
end

--[[
@Description 发送AT命令
]]
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

--[[
@Description 获取模组调试信息
]]
-- function getModemDebugInfo()
-- 	local at_port = http.formvalue("port")
	
-- 	--获取制造商
-- 	local manufacturer=getManufacturer(at_port)

-- 	--获取值
-- 	local mode_info={}
-- 	local network_prefer_info={}
-- 	local self_test_info={}
-- 	if manufacturer~="unknown" then
-- 		mode_info=getModeInfo(at_port,manufacturer)
-- 		network_prefer_info=getNetworkPreferInfo(at_port,manufacturer)
-- 		self_test_info=getSelfTestInfo(at_port,manufacturer)
-- 	end

--	-- 设置值
-- 	local modem_debug_info={}
-- 	modem_debug_info["mode_info"]=mode_info
-- 	modem_debug_info["network_prefer_info"]=network_prefer_info
-- 	modem_debug_info["self_test_info"]=self_test_info

-- 	-- 写入Web界面
-- 	luci.http.prepare_content("application/json")
-- 	luci.http.write_json(modem_debug_info)
-- end

--[[
@Description 模组扫描
]]
function modemScan()

	local command="source "..script_path.."modem_scan.sh && modem_scan"
	local result=shell(command)

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(result)
end

--[[
@Description 设置插件版本信息
@Params
	info 信息
]]
function setPluginVersionInfo(info)

	-- 正则表达式
	local version_regular_expression="[0-9]+.[0-9]+.[0-9]+"

	for key in pairs(info) do

		-- 获取插件版本
		local command="opkg list-installed | grep -oE '"..key.." - "..version_regular_expression.."' | awk -F' ' '{print $3}' | tr -d '\n'"
		local plugin_version=shell(command)

		if plugin_version~="" then
			info[key]=plugin_version
		end
	end

end

--[[
@Description 获取内核模块状态
@Params
	result 命令返回值
]]
function getModelStatus(result)
	local model_status="Not loaded"

	if result~="" then
		model_status="Loaded"
    end

	return model_status
end

--[[
@Description 设置内核模块状态
@Params
	info 信息
]]
function setModelStatus(info)

	for key in pairs(info) do

		-- 获取内核模块名
		local model_name=key:gsub(".ko","")

		local command="lsmod | grep -oE '"..model_name.." '"
		local result=shell(command)
		local model_status=getModelStatus(result)

		-- 修改信息表
		info[key]=model_status
	end

end

--[[
@Description 获取插件信息
]]
function getPluginInfo()

	-- 设置翻译
	translation={}
	translation["Unknown"]=luci.i18n.translate("Unknown")
	translation["Not installed"]=luci.i18n.translate("Not installed")
	translation["Loaded"]=luci.i18n.translate("Loaded")
	translation["Not loaded"]=luci.i18n.translate("Not loaded")

	-- 获取插件信息
	local plugin_info={}
	plugin_info["luci-app-modem"]="Unknown"
	setPluginVersionInfo(plugin_info)

	-- 获取拨号工具信息
	local dial_tool_info={}
	dial_tool_info["modemmanager"]="Not installed"
	dial_tool_info["quectel-CM-5G"]="Not installed"
	dial_tool_info["fibocom-dial"]="Not installed"
	dial_tool_info["meig-cm"]="Not installed"
	setPluginVersionInfo(dial_tool_info)

	-- 获取通用驱动信息
	local general_driver_info={}
	general_driver_info["usbnet.ko"]="Not loaded"
	general_driver_info["option.ko"]="Not loaded"
	-- general_driver_info["qcserial.ko"]="Not loaded"
	setModelStatus(general_driver_info)

	-- 获取模组USB驱动信息
	local usb_driver_info={}
	--通用驱动
	usb_driver_info["qmi_wwan.ko"]="Not loaded"
	usb_driver_info["GobiNet.ko"]="Not loaded"
	usb_driver_info["cdc_ether.ko"]="Not loaded"
	usb_driver_info["cdc_mbim.ko"]="Not loaded"
	usb_driver_info["rndis_host.ko"]="Not loaded"
	usb_driver_info["cdc_ncm.ko"]="Not loaded"
	--制造商私有驱动
	usb_driver_info["qmi_wwan_q.ko"]="Not loaded"
	usb_driver_info["qmi_wwan_f.ko"]="Not loaded"
	usb_driver_info["qmi_wwan_m.ko"]="Not loaded"
	usb_driver_info["qmi_wwan_t.ko"]="Not loaded"
	usb_driver_info["meig_cdc_driver.ko"]="Not loaded"
	setModelStatus(usb_driver_info)

	-- 获取模组PCI驱动信息
	local pci_driver_info={}
	--通用驱动
	pci_driver_info["mhi_net.ko"]="Not loaded"
	pci_driver_info["qrtr_mhi.ko"]="Not loaded"
	pci_driver_info["mhi_pci_generic.ko"]="Not loaded"
	pci_driver_info["mhi_wwan_mbim.ko"]="Not loaded"
	pci_driver_info["mhi_wwan_ctrl.ko"]="Not loaded"
	--制造商私有驱动
	pci_driver_info["pcie_mhi.ko"]="Not loaded"
	pci_driver_info["mtk_pcie_wwan_m80.ko"]="Not loaded"
	setModelStatus(pci_driver_info)

	-- 设置值
	local data={}
	data["translation"]=translation
	data["plugin_info"]=plugin_info
	data["dial_tool_info"]=dial_tool_info
	data["general_driver_info"]=general_driver_info
	data["usb_driver_info"]=usb_driver_info
	data["pci_driver_info"]=pci_driver_info

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end
