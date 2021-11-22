-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
--[[

=== lualinux.netif - Network interfaces

How to configure and get information about network interfaces.


---

Notes:

- see  man netdevices (7)



]]

local lualinux = require "lualinux"
local sock = require "lualinux.sock"
local util = require "lualinux.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local srep = string.rep
local insert, concat = table.insert, table.concat
local errm, rpad, pf, px = util.errm, util.rpad, util.pf, util.px

local function repr(x) return strf("%q", x) end



------------------------------------------------------------------------
--[[




]]


-----------------------------------------------------------------------
netif = {} -- the network interface module object


local IFNAMELEN = 16 -- length of an if name in ifreq struct
local IFRLEN = 40 -- length of an ifreq struct
local SALEN = 16  -- length of a sockaddr struct

local ifr0 = srep('\0', IFRLEN) -- an empty ifreq struct


local SIOCGIFNAME = 0x8910
local SIOCGIFCONF = 0x8912
local SIOCGIFADDR = 0x8915

function netif.fd()
	-- return a file descriptor suitable for other netif functions, or nil, errno
	local family = sock.AF_INET
	local sotype = sock.SOCK_DGRAM
	local fd, eno = lualinux.socket(family, sotype, 0)
	return fd, eno
end

function netif.iflist(fd)
	-- return a list of interface names
	-- Note: SIOCGIFCOUNT is deprecated. The current interface for
	-- enumeration is SIOCGIFCONF which cannot be used with 
	-- lualinux.ioctl() (it requires to place a pointer to the result buffer
	-- in the ioctl argument). So we use SIOCGIFCONF only to get
	-- a number of interfaces, and then SIOCGIFNAME to access
	-- names by index
	--
	local iftable = {}
	local r, eno = lualinux.ioctl(fd, SIOCGIFCONF, ifr0, IFRLEN)
	if not r then return nil, eno end
	local n = sunpack("I4", r) // IFRLEN  -- get number of interfaces
	local name0 = srep('\0', IFNAMELEN)
	for i = 1, n do -- interface index starts at 1
		local ifr = spack("c16I4", name0, i)
		r, eno = lualinux.ioctl(fd, SIOCGIFNAME, ifr, IFRLEN)
--~ 		print('iflist loop', i, repr(r), eno)
		assert(r, eno)
		local name = sunpack("z", r)
		insert(iftable, name)
	end
	return iftable
end--iflist()

function netif.getaddr(fd, ifname)
	local SIOCGIFADDR = 0x8915
	local ifr = spack("c16", ifname) --padded with zero
	local r, eno = lualinux.ioctl(fd, SIOCGIFADDR, ifr, IFRLEN)
	if not r then return nil, eno end
--~ 	px(r)
	return r:sub(17, 32) 
end

function netif.getmac(fd, ifname, intflag)
	-- return the MAC address of the interface
	-- as a printable string ("12:34:cd:ef:...") (the default)
	-- or as a Lua integer if intflag is true
	local ifr = spack("c16", ifname) --padded with zero
	local SIOCGIFHWADDR = 0x8927
	local r, eno = lualinux.ioctl(fd, SIOCGIFHWADDR, ifr, IFRLEN)
	if not r then return nil, eno end
	-- return only the 6-byte MAC 
	-- [is the class prefix needed? ('01 00' for LAN) ]
	if intflag then return sunpack("I6", r, 19) end
	-- here, return mac as a printable string ("12:34:cd:ef:...")
	local mac = r:sub(19, 24) 
	t = {}
	for i = 1, #mac do
		insert(t, strf("%02x", string.byte(mac, i)))
	end
	return concat(t, ":")
end

local function test1()
	print"test1"
	local ifl = assert(netif.iflist(nfd))
	print("interface list")
	for i, v in ipairs(ifl) do print('  -', i, v) end
end

	print("test1\n\ninterface list\n" 
		.. map(assert(netif.iflist(nfd)), bind1(strf, "  -  %s\n")))
	

local function saip(sa) 
	local ip, port = sock.sockaddr_ip_port(sa)
	return ip
end

local function test2()
	print"test2"
	local mac, addr, r, eno
	local ifname = "wlan0"
	-- getaddr
	addr, eno = netif.getaddr(nfd, ifname)
	if not addr then print('test2: getaddr error', eno); return end
	print(ifname, "addr", saip(addr))
	-- getmac
	mac, eno = netif.getmac(nfd, ifname, true)
	if not mac then print('test2: getmac error', eno); return end
	print(ifname, "mac(int)", mac, strf("0x%012x", mac))
	mac, eno = netif.getmac(nfd, ifname)
	if not mac then print('test2: getmac error', eno); return end
	print(ifname, "mac(str)", mac)
	
end

--~ nfd = netif.fd()
--~ test1()
--~ test2()
		
		
------------------------------------------------------------------------
return netif


