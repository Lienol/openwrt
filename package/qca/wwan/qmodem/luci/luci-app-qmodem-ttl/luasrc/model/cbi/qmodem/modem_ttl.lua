local uci = luci.model.uci.cursor()
m = Map("qmodem_ttl", translate("TTL Config"))
s = m:section(NamedSection, "main", "main", translate("Global Config"))

enable = s:option(Flag, "enable", translate("Enable"))
enable.default = "0"

ttl = s:option(Value, "ttl", translate("TTL"))
ttl.default = 64
ttl.datatype = "uinteger"


return m
