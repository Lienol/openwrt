local dispatcher = require "luci.dispatcher"
local uci = require "luci.model.uci".cursor()
local sys  = require "luci.sys"
local json = require("luci.jsonc")
local script_path="/usr/share/modem/"

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
@Description 获取支持的模组信息
@Params
	data_interface 数据接口
]]
function getSupportModems(data_interface)
	local command="cat "..script_path.."modem_support.json"
	local result=json.parse(shell(command))
	return result["modem_support"][data_interface]
end

--[[
@Description 按照制造商给模组分类
]]
function getManufacturers()

	local manufacturers={}
	
	-- 获取支持的模组
	local support_modem=getSupportModems("usb")
	-- USB
	for modem in pairs(support_modem) do

		local manufacturer=support_modem[modem]["manufacturer"]
		if manufacturers[manufacturer] then
			-- 直接插入
			table.insert(manufacturers[manufacturer],modem)
		else
			-- 不存在先创建一个空表
			local tmp={}
			table.insert(tmp,modem)
			manufacturers[manufacturer]=tmp
		end
	end

	-- 获取支持的模组
	local support_modem=getSupportModems("pcie")
	-- PCIE
	for modem in pairs(support_modem) do

		local manufacturer=support_modem[modem]["manufacturer"]
		if manufacturers[manufacturer] then
			-- 直接插入
			table.insert(manufacturers[manufacturer],modem)
		else
			-- 不存在先创建一个空表
			local tmp={}
			table.insert(tmp,modem)
			manufacturers[manufacturer]=tmp
		end
	end

	return manufacturers
end

m = Map("modem", translate("Modem Config"))
m.redirect = dispatcher.build_url("admin", "network", "modem","plugin_config")

s = m:section(NamedSection, arg[1], "modem-device", "")
s.addremove = false
s.dynamic = false

-- 手动配置
manual = s:option(Flag, "manual", translate("Manual"))
manual.default = "1"
manual.rmempty = false
-- uci:set('modem','modem-device','manual',1)

-- 隐藏手动配置
m:append(Template("modem/hide_manual_config_modem"))

-- 移动网络
mobile_network = s:option(ListValue, "network", translate("Mobile Network"))
mobile_network.rmempty = true

-- 获取移动网络
function getMobileNetwork()

	--获取所有的网络接口
	local networks = sys.exec("ls -l /sys/class/net/ 2>/dev/null |awk '{print $9}' 2>/dev/null")

	--遍历所有网络接口
	for network in string.gmatch(networks, "%S+") do

		-- 只处理最上级的网络设备
		-- local count=$(echo "${network_path}" | grep -o "/net" | wc -l)
		-- [ "$count" -ge "2" ] && return
	
		-- 获取网络设备路径
		local command="readlink -f /sys/class/net/"..network
		local network_path=shell(command)

		-- 判断路径是否带有usb（排除其他eth网络设备）
		local flag="0"
		if network_path:find("eth") and not network_path:find("usb") then
			flag="1"
		end

		if flag=="0" then
			if network:find("usb") or network:find("wwan") or network:find("eth") then
				--设置USB移动网络
				mobile_network:value(network)
			elseif network:find("mhi_hwip") or network:find("rmnet_mhi") then
				--设置PCIE移动网络
				mobile_network:value(network)
			end
		end

	end
end

getMobileNetwork()

-- 模组名称
name = s:option(ListValue, "name", translate("Modem Name"))
name.placeholder = translate("Not null")
name.rmempty = false

-- 按照制造商给模组分类
local manufacturers=getManufacturers()

for key in pairs(manufacturers) do
	local modems=manufacturers[key]
	-- 排序
	table.sort(modems)

	for i in pairs(modems) do
		-- 首字母大写
		local first_str=string.sub(key, 1, 1)
		local manufacturer = string.upper(first_str)..string.sub(key, 2)
		-- 设置值
		name:value(modems[i],manufacturer.." "..modems[i]:upper())
	end
end

-- AT串口
at_port = s:option(Value, "at_port", translate("AT Port"))
at_port.placeholder = translate("Not null")
at_port.rmempty = false

return m
