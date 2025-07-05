-- Copyright 2024 Siriling <siriling@qq.com>
module("luci.controller.qmodem_ttl", package.seeall)
function index()
    if not nixio.fs.access("/etc/config/qmodem_ttl") then
        return
    end
	entry({"admin", "modem", "qmodem", "modem_ttl"}, cbi("qmodem/modem_ttl"), luci.i18n.translate("TTL Config"), 22).leaf = true
end
