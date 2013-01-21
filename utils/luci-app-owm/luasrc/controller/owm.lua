--[[
LuCI - Lua Configuration Interface

Copyright 2008 Steven Barth <steven@midlink.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

module("luci.controller.owm", package.seeall)

function index()
	entry({"owm.json"}, call("jsonowm"))

	local page  = node()
	page.lock   = true
	page.target = alias("owm")
	page.subindex = true
	page.index = false

	local page = node("owm")
	page.target = template("owm")
	page.title = "OpenWifiMap"
	page.order = 100
end

local function fetch_olsrd_config()
	local sys = require "luci.sys"
	local util = require "luci.util"
	local table = require "table"
	local json = require "luci.json"
	local jsonreq4 = luci.util.exec("echo /config | nc 127.0.0.1 9090")
	local jsonreq6 = luci.util.exec("echo /config | nc ::1 9090")
	local jsondata4 = {}
	local jsondata6 = {}
	local data = {}
	if #jsonreq4 ~= 0 then
		jsondata4 = json.decode(jsonreq4)
		data['ipv4Config'] = jsondata4['data'][1]['config']
	end
	if #jsonreq6 ~= 0 then
		jsondata6 = json.decode(jsonreq6)
		data['ipv6Config'] = jsondata6['data'][1]['config']
	end
	return data
end

local function fetch_olsrd_links()
	local sys = require "luci.sys"
	local util = require "luci.util"
	local table = require "table"
	local json = require "luci.json"
	local jsonreq4 = luci.util.exec("echo /links | nc 127.0.0.1 9090")
	local jsonreq6 = luci.util.exec("echo /links | nc ::1 9090")
	local jsondata4 = {}
	local jsondata6 = {}
	local data = {}
	if #jsonreq4 ~= 0 then
		jsondata4 = json.decode(jsonreq4)
		local links = jsondata4['data'][1]['links']
		for i,v in ipairs(links) do
			links[i]['sourceAddr'] = v['localIP'] --owm sourceAddr
			links[i]['destAddr'] = v['remoteIP'] --owm destAddr
			hostname = nixio.getnameinfo(v['remoteIP'], "inet")
			if hostname then
				links[i]['destNodeId'] = string.gsub(hostname, "mid..", "") --owm destNodeId
			end 
		end
		data = links
	end
	if #jsonreq6 ~= 0 then
		jsondata6 = json.decode(jsonreq6)
		local links = jsondata6['data'][1]['links']
		for i,v in ipairs(links) do
			links[i]['sourceAddr'] = v['localIP']
			links[i]['destAddr'] = v['remoteIP']
			hostname = nixio.getnameinfo(v['remoteIP'], "inet6")
			if hostname then
				links[i]['destNodeId'] = string.gsub(hostname, "mid..", "") --owm destNodeId
			end
			data[#data+1] = links[i]
		end
	end
	return data
end

local function fetch_olsrd_neighbors(interfaces)
	local sys = require "luci.sys"
	local util = require "luci.util"
	local table = require "table"
	local json = require "luci.json"
	local jsonreq4 = luci.util.exec("echo /links | nc 127.0.0.1 9090")
	local jsonreq6 = luci.util.exec("echo /links | nc ::1 9090")
	local jsondata4 = {}
	local jsondata6 = {}
	local data = {}
	if #jsonreq4 ~= 0 then
		jsondata4 = json.decode(jsonreq4)
		local links = jsondata4['data'][1]['links']
		for i,v in ipairs(links) do
			links[i]['quality'] = v['linkQuality'] --owm
			links[i]['sourceAddr'] = v['localIP'] --owm
			links[i]['destAddr'] = v['remoteIP'] --owm
			hostname = nixio.getnameinfo(v['remoteIP'], "inet")
			if hostname then
				links[i]['id'] = string.gsub(hostname, "mid..", "") --owm
			end
			if #interfaces ~= 0 then
			for _,iface in ipairs(interfaces) do
				if iface['ipaddr'] == v['localIP'] then
					links[i]['interface'] = iface['name'] --owm
				end
			end
			end
		end
		data = links
	end
	if #jsonreq6 ~= 0 then
		jsondata6 = json.decode(jsonreq6)
		local links = jsondata6['data'][1]['links']
		for i,v in ipairs(links) do
			links[i]['quality'] = v['linkQuality'] --owm
			links[i]['sourceAddr'] = v['localIP'] --owm
			links[i]['destAddr'] = v['remoteIP'] --owm
			hostname = nixio.getnameinfo(v['remoteIP'], "inet6")
			if hostname then
				links[i]['id'] = string.gsub(hostname, "mid..", "") --owm
			end
			if #interfaces ~= 0 then
			for _,iface in ipairs(interfaces) do
				if iface['ip6addr'] then
				if string.gsub(iface['ip6addr'], "/64", "") == v['localIP'] then
					links[i]['interface'] = iface['name'] --owm
				end
				end
			end
			end
			data[#data+1] = links[i]
		end
	end
	return data
end

	
local function fetch_olsrd()
	local sys = require "luci.sys"
	local util = require "luci.util"
	local table = require "table"
	local data = {}
	data['links'] = fetch_olsrd_links()
	local olsrconfig = fetch_olsrd_config()
	data['ipv4Config'] = olsrconfig['ipv4Config']
	data['ipv6Config'] = olsrconfig['ipv6Config']
	
	return data
end

function jsonowm()
	local root = {}
	local sys = require "luci.sys"
	local uci = require "luci.model.uci"
	local util = require "luci.util"
	local http = require "luci.http"
	local json = require "luci.json"
	local ltn12 = require "luci.ltn12"
	local version = require "luci.version"
	local webadmin = require "luci.tools.webadmin"
	local status = require "luci.tools.status"

	local cursor = uci.cursor_state()

	--root.protocol = 1
	root.type = 'node' --owm

	root.system = {
		uptime = {sys.uptime()},
		loadavg = {sys.loadavg()},
		sysinfo = {sys.sysinfo()},
	}
	root.hostname = sys.hostname() --owm
	root.lastupdate = os.date("!%Y-%m-%dT%H:%M:%SZ") --owm
	root.updateInterval = 60 --owm


	-- s system,a arch,r ram owm
	local s,a,r = sys.sysinfo() --owm
	root.hardware = s --owm
	

	root.firmware = {
	--	luciname=version.luciname,
	--	luciversion=version.luciversion,
	--	distname=version.distname,
		name=version.distname, --owm
	--	distversion=version.distversion,
		revision=version.distversion --owm
	}

	root.freifunk = {}
	cursor:foreach("freifunk", "public", function(s)
		local pname = s[".name"]
		s['.name'] = nil
		s['.anonymous'] = nil
		s['.type'] = nil
		s['.index'] = nil
		if s['mail'] then
			s['mail'] = string.gsub(s['mail'], "@", "./-\\.T.")
		end
		root.freifunk[pname] = s
	end)

	cursor:foreach("system", "system", function(s) --owm
		root.latitude = tonumber(s.latitude) --owm
		root.longitude = tonumber(s.longitude) --owm
	end)

	root.interfaces = {} --owm
	root.wireless = {devices = {}, interfaces = {}, status = {}}
	
	cursor:foreach("network", "interface",function(vif)
		if 'lo' == vif.ifname then
			return
		end
		root.interfaces[#root.interfaces+1] =  vif
		root.interfaces[#root.interfaces].name = vif['.name'] --owm
		root.interfaces[#root.interfaces].ifname = vif.ifname --owm
		root.interfaces[#root.interfaces].ipv4Addresses = {vif.ipaddr} --owm
		root.interfaces[#root.interfaces].ipv6Addresses = {vif.ip6addr} --owm
		root.interfaces[#root.interfaces]['.name'] = nil
		root.interfaces[#root.interfaces]['.anonymous'] = nil
		root.interfaces[#root.interfaces]['.type'] = nil
		root.interfaces[#root.interfaces]['.index'] = nil
	end)
	
	cursor:foreach("wireless", "wifi-device",function(s)
		root.wireless.devices[#root.wireless.devices+1] = s
		root.wireless.devices[#root.wireless.devices]['.name'] = nil
		root.wireless.devices[#root.wireless.devices]['.anonymous'] = nil
		root.wireless.devices[#root.wireless.devices]['.type'] = nil
		root.wireless.devices[#root.wireless.devices]['.index'] = nil
	end)

	cursor:foreach("wireless", "wifi-iface",function(s)
		root.wireless.interfaces[#root.wireless.interfaces+1] = s
		root.wireless.interfaces[#root.wireless.interfaces]['.name'] = nil
		root.wireless.interfaces[#root.wireless.interfaces]['.anonymous'] = nil
		root.wireless.interfaces[#root.wireless.interfaces]['.type'] = nil
		root.wireless.interfaces[#root.wireless.interfaces]['.index'] = nil
		local iwinfo = luci.sys.wifi.getiwinfo(s.ifname)
		if iwinfo then
			local _, f
			for _, f in ipairs({
			"channel", "txpower", "bitrate", "signal", "noise",
			"quality", "quality_max", "mode", "ssid", "bssid", "encryption", "ifname"
			}) do
				root.wireless.interfaces[#root.wireless.interfaces][f] = iwinfo[f]
			end
		end
	end)

	cursor:foreach("wireless", "wifi-iface",function(s)
		local iwinfo = luci.sys.wifi.getiwinfo(s.ifname)
		if iwinfo then
			root.wireless.status[#root.wireless.status+1] = {}
			root.wireless.status[#root.wireless.status]['network'] = s.network
			root.wireless.status[#root.wireless.status]['device'] = s.device
			local _, f
			for _, f in ipairs({
			"channel", "txpower", "bitrate", "signal", "noise",
			"quality", "quality_max", "mode", "ssid", "bssid", "encryption", "ifname"
			}) do
				root.wireless.status[#root.wireless.status][f] = iwinfo[f]
			end
		end
	end)

	root.wifistatus = status.wifi_networks()

	local dr4 = sys.net.defaultroute()
	local dr6 = sys.net.defaultroute6()
	
	if dr6 then
		def6 = { 
		gateway = dr6.nexthop:string(),
		dest = dr6.dest:string(),
		dev = dr6.device,
		metr = dr6.metric }
	end   

	if dr4 then
		def4 = { 
		gateway = dr4.gateway:string(),
		dest = dr4.dest:string(),
		dev = dr4.device,
		metr = dr4.metric }
	else
		local dr = sys.exec("ip r s t olsr-default")
		if dr then
			local dest, gateway, dev, metr = dr:match("^(%w+) via (%d+.%d+.%d+.%d+) dev (%w+) +metric (%d+)")
			def4 = {
				dest = dest,
				gateway = gateway,
				dev = dev,
				metr = metr
			}
		end
        end
        
	root.ipv4defaultGateway = def4
	root.ipv6defaultGateway = def6
       
	root.neighbors = fetch_olsrd_neighbors(root.interfaces)

	root.routingNeighbors = {}
	root.routingNeighbors.olsr = fetch_olsrd()

	http.prepare_content("application/json")
	ltn12.pump.all(json.Encoder(root):source(), http.write)
end

