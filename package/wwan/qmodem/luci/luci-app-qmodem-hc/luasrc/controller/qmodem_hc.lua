module("luci.controller.qmodem_hc", package.seeall)
local http = require "luci.http"
local fs = require "nixio.fs"
local json = require("luci.jsonc")
function index()
    --sim卡配置
	entry({"admin", "modem", "qmodem", "modem_sim"}, cbi("qmodem_hc/modem_sim"), luci.i18n.translate("SIM Config"), 23).leaf = true
	entry({"admin", "modem", "qmodem", "set_sim"}, call("setSIM"), nil).leaf = true
	entry({"admin", "modem", "qmodem", "get_sim"}, call("getSIM"), nil).leaf = true
end

function getSimSlot(sim_path)
    local sim_slot = fs.readfile(sim_path)
    local current_slot = string.match(sim_slot, "%d")
    if current_slot == "0" then
        return "SIM2"
    else
        return "SIM1"
    end
end

function shell(command)
	local odpall = io.popen(command)
	local odp = odpall:read("*a")
	odpall:close()
	return odp
end


function getNextBootSlot()
    local fw_print_cmd = "fw_printenv -n sim2"
    local nextboot_slot = shell(fw_print_cmd)
    if nextboot_slot == "" then
        return "SIM1"
    else
        return "SIM2"
    end
end

function writeJsonResponse(current_slot, nextboot_slot)
    local result_json = {}
    result_json["current_slot"] = current_slot
    result_json["nextboot_slot"] = nextboot_slot
    luci.http.prepare_content("application/json")
    luci.http.write_json(result_json)
end

function getSIM()
    local sim_path = "/sys/class/gpio/sim/value"
    local current_slot = getSimSlot(sim_path)
    local nextboot_slot = getNextBootSlot()
    writeJsonResponse(current_slot, nextboot_slot)
end

function setSIM()
    local sim_gpio = "/sys/class/gpio/sim/value"
    local modem_gpio = "/sys/class/gpio/4g/value"
    local sim_slot = http.formvalue("slot")
    local pre_detect = getSimSlot(sim_gpio)
    
    local reset_module = 1
    if pre_detect == sim_slot then
        reset_module = 0
    end
    if sim_slot == "SIM1" then
        sysfs_cmd = "echo 1 >"..sim_gpio
        fw_setenv_cmd = "fw_setenv sim2"
    elseif sim_slot == "SIM2" then
        sysfs_cmd = "echo 0 >"..sim_gpio
        fw_setenv_cmd = "fw_setenv sim2 1"
    end
    shell(sysfs_cmd)
    shell(fw_setenv_cmd)
    if reset_module == 1 then
        shell("echo 0 >"..modem_gpio)
        os.execute("sleep 1")
        shell("echo 1 >"..modem_gpio)
    end
    local current_slot = getSimSlot(sim_gpio)
    local nextboot_slot = getNextBootSlot()
    writeJsonResponse(current_slot, nextboot_slot)
end
