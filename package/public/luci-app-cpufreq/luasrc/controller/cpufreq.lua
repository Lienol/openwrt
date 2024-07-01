module("luci.controller.cpufreq", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/cpufreq") then
		return
	end

	local page = entry({"admin", "system", "cpufreq"}, cbi("cpufreq"), _("CPU Freq"), 90)
	page.dependent = false
	page.acl_depends = { "luci-app-cpufreq" }
end
