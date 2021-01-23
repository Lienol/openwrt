--[[
LuCI - Lua Configuration Interface
Copyright 2019 lisaac <https://github.com/lisaac/luci-app-dockerman>
]]--

require "luci.util"
local docker = require "luci.model.docker"
local dk = docker.new()

m = SimpleForm("docker", translate("Docker"))
m.redirect = luci.dispatcher.build_url("admin", "docker", "networks")

docker_status = m:section(SimpleSection)
docker_status.template = "dockerman/apply_widget"
docker_status.err=docker:read_status()
docker_status.err=docker_status.err and docker_status.err:gsub("\n","<br>"):gsub(" ","&nbsp;")
if docker_status.err then docker:clear_status() end

s = m:section(SimpleSection, translate("New Network"))
s.addremove = true
s.anonymous = true

d = s:option(Value, "name", translate("Network Name"))
d.rmempty = true

d = s:option(ListValue, "dirver", translate("Driver"))
d.rmempty = true
d:value("bridge", "bridge")
d:value("macvlan", "macvlan")
d:value("ipvlan", "ipvlan")
d:value("overlay", "overlay")

d = s:option(Value, "parent", translate("Parent Interface"))
d.rmempty = true
d:depends("dirver", "macvlan")
local interfaces = luci.sys and luci.sys.net and luci.sys.net.devices() or {}
for _, v in ipairs(interfaces) do
  d:value(v, v)
end
d.default="br-lan"
d.placeholder="br-lan"

d = s:option(Value, "macvlan_mode", translate("Macvlan Mode"))
d.rmempty = true
d:depends("dirver", "macvlan")
d.default="bridge"
d:value("bridge", "bridge")
d:value("private", "private")
d:value("vepa", "vepa")
d:value("passthru", "passthru")

d = s:option(Value, "ipvlan_mode", translate("Ipvlan Mode"))
d.rmempty = true
d:depends("dirver", "ipvlan")
d.default="l3"
d:value("l2", "l2")
d:value("l3", "l3")

d = s:option(Flag, "ingress", translate("Ingress"), translate("Ingress network is the network which provides the routing-mesh in swarm mode"))
d.rmempty = true
d.disabled = 0
d.enabled = 1
d.default = 0
d:depends("dirver", "overlay")

d = s:option(DynamicList, "options", translate("Options"))
d.rmempty = true
d.placeholder="com.docker.network.driver.mtu=1500"

d = s:option(Flag, "internal", translate("Internal"), translate("Restrict external access to the network"))
d.rmempty = true
d:depends("dirver", "overlay")
d.disabled = 0
d.enabled = 1
d.default = 0

if  nixio.fs.access("/etc/config/network") and nixio.fs.access("/etc/config/firewall")then
  d = s:option(Flag, "op_macvlan", translate("Create macvlan interface"), translate("Auto create macvlan interface in Openwrt"))
  d:depends("dirver", "macvlan")
  d.disabled = 0
  d.enabled = 1
  d.default = 1
end

d = s:option(Value, "subnet", translate("Subnet"))
d.rmempty = true
d.placeholder="10.1.0.0/16"
d.datatype="ip4addr"

d = s:option(Value, "gateway", translate("Gateway"))
d.rmempty = true
d.placeholder="10.1.1.1"
d.datatype="ip4addr"

d = s:option(Value, "ip_range", translate("IP range"))
d.rmempty = true
d.placeholder="10.1.1.0/24"
d.datatype="ip4addr"

d = s:option(DynamicList, "aux_address", translate("Exclude IPs"))
d.rmempty = true
d.placeholder="my-route=10.1.1.1"

d = s:option(Flag, "ipv6", translate("Enable IPv6"))
d.rmempty = true
d.disabled = 0
d.enabled = 1
d.default = 0

d = s:option(Value, "subnet6", translate("IPv6 Subnet"))
d.rmempty = true
d.placeholder="fe80::/10"
d.datatype="ip6addr"
d:depends("ipv6", 1)

d = s:option(Value, "gateway6", translate("IPv6 Gateway"))
d.rmempty = true
d.placeholder="fe80::1"
d.datatype="ip6addr"
d:depends("ipv6", 1)

m.handle = function(self, state, data)
  if state == FORM_VALID then
    local name = data.name
    local driver = data.dirver

    local internal = data.internal == 1 and true or false

    local subnet = data.subnet
    local gateway = data.gateway
    local ip_range = data.ip_range

    local aux_address = {}
    local tmp = data.aux_address or {}
    for i,v in ipairs(tmp) do
      _,_,k1,v1 = v:find("(.-)=(.+)")
      aux_address[k1] = v1
    end

    local options = {}
    tmp = data.options or {}
    for i,v in ipairs(tmp) do
      _,_,k1,v1 = v:find("(.-)=(.+)")
      options[k1] = v1
    end

    local ipv6 = data.ipv6 == 1 and true or false

    local create_body={
      Name = name,
      Driver = driver,
      EnableIPv6 = ipv6,
      IPAM = {
        Driver= "default"
      },
      Internal = internal
    }
  
    if subnet or gateway or ip_range then
      create_body["IPAM"]["Config"] = {
        {
          Subnet = subnet,
          Gateway = gateway,
          IPRange = ip_range,
          AuxAddress = aux_address,
          AuxiliaryAddresses = aux_address
        }
      }
    end
    if driver == "macvlan" then
      create_body["Options"] = {
        macvlan_mode = data.macvlan_mode,
        parent = data.parent
      }
    elseif driver == "ipvlan" then
      create_body["Options"] = {
        ipvlan_mode = data.ipvlan_mode
      }
    elseif driver == "overlay" then
      create_body["Ingress"] = data.ingerss == 1 and true or false
    end

    if ipv6 and data.subnet6 and data.subnet6 then
      if type(create_body["IPAM"]["Config"]) ~= "table" then 
        create_body["IPAM"]["Config"] = {}
      end
      local index = #create_body["IPAM"]["Config"]
      create_body["IPAM"]["Config"][index+1] = {
        Subnet = data.subnet6,
        Gateway = data.gateway6
      }
    end

    if next(options) ~= nil then
      create_body["Options"] = create_body["Options"] or {}
      for k, v in pairs(options) do
        create_body["Options"][k] = v
      end
    end

    create_body = docker.clear_empty_tables(create_body)
    docker:write_status("Network: " .. "create" .. " " .. create_body.Name .. "...")
    local res = dk.networks:create({body = create_body})
    if res and res.code == 201 then
      docker:write_status("Network: " .. "create macvlan interface...")
      res = dk.networks:inspect({ name = create_body.Name })
      if driver == "macvlan" and data.op_macvlan ~= 0 and res.code == 200 
        and res.body and res.body.IPAM and res.body.IPAM.Config and res.body.IPAM.Config[1] 
        and res.body.IPAM.Config[1].Gateway and res.body.IPAM.Config[1].Subnet then
        docker.create_macvlan_interface(data.name, data.parent, res.body.IPAM.Config[1].Gateway, res.body.IPAM.Config[1].Subnet)
      end
      docker:clear_status()
      luci.http.redirect(luci.dispatcher.build_url("admin/docker/networks"))
    else
      docker:append_status("code:" .. res.code.." ".. (res.body.message and res.body.message or res.message).. "\n")
      luci.http.redirect(luci.dispatcher.build_url("admin/docker/newnetwork"))
    end
  end
end

return m
