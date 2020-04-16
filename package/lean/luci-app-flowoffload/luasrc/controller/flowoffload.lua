module("luci.controller.flowoffload", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/flowoffload") then
		return
	end
	local page
	page = entry({"admin", "network", "flowoffload"}, cbi("flowoffload"), _("Turbo ACC Center"), 101)
	page.i18n = "flowoffload"
	page.dependent = true
	
	entry({"admin", "network", "flowoffload", "status"}, call("action_status"))
end

local function is_running()
	return luci.sys.call("[ `cat /sys/module/xt_FLOWOFFLOAD/refcnt 2>/dev/null` -gt 0 ] 2>/dev/null") == 0
end

local function is_bbr()
	return luci.sys.call("[ `cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null` = bbr ] 2>/dev/null") == 0
end

local function is_fullcone()
	return luci.sys.call("[ `cat /sys/module/xt_FULLCONENAT/refcnt 2>/dev/null` -gt 0 ] 2>/dev/null") == 0
end

function action_status()
	luci.http.prepare_content("application/json")
	luci.http.write_json({
		run_state = is_running(),
		down_state = is_bbr(),
		up_state = is_fullcone()
	})
end


