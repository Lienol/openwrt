module("luci.controller.qmodem_mwan", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/qmodem_mwan") then
        return
    end
	--mwan配置
	entry({"admin", "modem", "qmodem", "mwan_config"}, cbi("qmodem/mwan_config"), luci.i18n.translate("Mwan Config"), 21).leaf = true
end
