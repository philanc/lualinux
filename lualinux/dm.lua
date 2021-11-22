-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
--[[		lualinux device mapper functions

WARNING:  

   These functions allow to setup arbitrary block device mappings.
   
   Some of them must be run as root and may wreak havoc on your system.
   
EXTREME CAUTION IS ADVISED - USE AT YOUR OWN RISK
   
   Test in a VM or at least on ad hoc loop devices!

 ]]
 
local lualinux = require "lualinux"
local util = require "lualinux.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local errm, rpad, pf = util.errm, util.rpad, util.pf

------------------------------------------------------------------------
-- local defs

-- see linux/dm-ioctl.h

local argsize = 512  	-- buffer size for ioctl() 
			-- should be enough for dmcrypt

local DMISIZE = 312  	-- sizeof(struct dm_ioctl)




local function fill_dmioctl(dname)
	local tot
	local flags = (1<<4)
	local dev = 0
	local s = spack("I4I4I4I4I4I4I4I4I4I4I8z",
		4, 0, 0,	-- version (must pass it, or ioctl fails)
		argsize,	-- data_size (total arg size)
		DMISIZE,	-- data_start
		1, 0,		-- target_count, open_count
		flags, 		-- flags (1<<4 for dm_table_status)
		0, 0,		-- event_nr, padding
		dev,		-- dev(u64)
		dname		-- device name
		)
	s = rpad(s, DMISIZE, '\0')
	return s
end

local function fill_dmtarget(secstart, secnb, targettype, options)
	-- struct dm_target_spec
	local DMTSIZE = 40  -- not including option string
	local len = DMTSIZE + #options + 1
	len = ((len >> 3) + 1) << 3  -- ensure multiple of 8 (alignment)
	local s = spack("I8I8I4I4c16z",
		secstart, secnb, -- sector_start, length
		0, len, 	-- status, next
		targettype, 	-- char target_type[16]
		options		-- null-terminated parameter string
		)
	s = rpad(s, len, '\0')
	return s
end

local function dm_opencontrol()
	local fd, eno = lualinux.open("/dev/mapper/control", 0, 0) 
		--O_RDONLY, mode=0
	return assert(fd, errm(eno, "open /dev/mapper/control"))
end

local function dm_getversion(cfd)
	local DM_VERSION= 0xc138fd00
	local arg = fill_dmioctl("")
	local s, eno = lualinux.ioctl(cfd, DM_VERSION, arg, argsize)
	assert(s, errm(eno, "dm_version ioctl"))
--~ 	px(s)
	local major, minor, patch = ("I4I4I4"):unpack(s)
	return major, minor, patch
end

local function dm_getdevlist(cfd)
	local DM_LIST_DEVICES= 0xc138fd02
	local arg = fill_dmioctl("")
	local s, eno = lualinux.ioctl(cfd, DM_LIST_DEVICES, arg, argsize)
	if not s then return nil, errm(eno, "ioctl")  end
	-- devlist is after the dm_ioctl struct
	local data = s:sub(DMISIZE + 1)
	local i, devlist = 1, {}
	local dev, nxt, name
	while true do
		dev, nxt, name = sunpack("I8I4z", data, i)
		table.insert(devlist, {dev=dev, name=name})
		if nxt == 0 then break end
		i = i + nxt
	end
	return devlist
end

local function dm_create(cfd, name)
	local DM_DEV_CREATE = 0xc138fd03
	local arg = fill_dmioctl(name)
	local s, eno = lualinux.ioctl(cfd, DM_DEV_CREATE, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_dev_create") end
	local dev = sunpack("I8", s, 41)
	return dev
end

local function dm_tableload(cfd, name, secstart, secsize, ttype, options)
	local DM_TABLE_LOAD = 0xc138fd09
	local arg = fill_dmioctl(name)
	arg = arg .. fill_dmtarget(secstart, secsize, ttype, options)
	local s, eno = lualinux.ioctl(cfd, DM_TABLE_LOAD, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_table_load") end
	return true
end	

local function dm_suspend(cfd, name)
	DM_DEV_SUSPEND = 0xc138fd06
	local arg = fill_dmioctl(name)
	local s, eno = lualinux.ioctl(cfd, DM_DEV_SUSPEND, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_dev_suspend") end
	local flags = sunpack("I4", s, 29)
	return flags
end

local function dm_remove(cfd, name)
	DM_DEV_REMOVE = 0xc138fd04
	local arg = fill_dmioctl(name)
	local s, eno = lualinux.ioctl(cfd, DM_DEV_REMOVE, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_dev_remove") end
	local flags = sunpack("I4", s, 29)
	return flags
end

local function dm_gettable(cfd, name)
	-- get _one_ table. (ok for basic dmcrypt)
	local DM_TABLE_STATUS = 0xc138fd0c
	local arg = fill_dmioctl(name)
	local s, eno = lualinux.ioctl(cfd, DM_TABLE_STATUS, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_table_status") end
	-- for a single target,
	-- s :: struct dm_ioctl .. struct dm_target_spec .. options
	-- (tbl is here because flags was 1<<4)
	local totsiz, dstart, tcnt, ocnt, flags = sunpack("I4I4I4I4I4", s, 13)
--~ 	print("totsiz, dstart, tcnt, ocnt, flags")
--~ 	print(totsiz, dstart, tcnt, ocnt, flags)
	local data = s:sub(dstart+1, totsiz) -- struct dm_target_spec
	local tbl = {}
	local tnext, ttype
	tbl.secstart, tbl.secnb, tnext, ttype, tbl.options = 
		sunpack("I8I8xxxxI4c16z", data)
	tbl.ttype = sunpack("z", ttype)
	return tbl
end

local function dm_gettable_str(cfd, name)
	local tbl, em = dm_gettable(cfd, name)
	if not tbl then return nil, em end
	return strf("%d %d %s %s", 
		tbl.secstart, tbl.secnb, tbl.ttype, tbl.options)
end

------------------------------------------------------------------------
-- dm functions

local dm = {}

function dm.blkgetsize(devname)
	-- return the byte size of a block device
	fd, eno = lualinux.open(devname, 0, 0) --O_RDONLY, mode=0
	if not fd then return nil, errm(eno, "open") end
	local BLKGETSIZE64 = 0x80081272
	local s, eno = lualinux.ioctl(fd, BLKGETSIZE64, "", 8)
	lualinux.close(fd)
	if not s then return nil, errm(eno, "ioctl") end
	local size = ("T"):unpack(s)
	return size
end


function dm.setup(dname, tblstr)
	local pat = "^(%d+) (%d+) (%S+) (.+)$"
	local start, siz, typ, opt = tblstr:match(pat)
	local cfd = dm_opencontrol()
	local r, em = dm_create(cfd, dname)
	local dmdev = r  -- the dm device (eg. 0xfb01 for /dev/dm-1)
	if not r then goto close end
	r, em = dm_tableload(cfd, dname, start, siz, typ, opt)
	if not r then goto close end
	r, em = dm_suspend(cfd, dname)
	::close::
	lualinux.close(cfd)
	if em then return nil, em else return dmdev end
end

function dm.remove(dname)
	local cfd = dm_opencontrol()
	local r, em = dm_remove(cfd, dname)
	lualinux.close(cfd)
	return r, em
end

function dm.gettable(dname)
	local cfd = dm_opencontrol()
	local r, em = dm_gettable_str(cfd, dname)
	lualinux.close(cfd)
	return r, em
end

function dm.devlist()
	local cfd = dm_opencontrol()
	local dl, em = dm_getdevlist(cfd)
	lualinux.close(cfd)
	return dl, em
end

function dm.devname(dev)
	-- return the device name for a given dev
	-- (returns the actual devname, not the symlink in /dev/mapper
	-- that may be created if udev is running)
	-- eg. devname(0xfb01) => "/dev/dm-1"
	assert(dev >> 8 == 0xfb, "not a mapper device")
	return "/dev/dm-" .. tostring(dev & 0xff)
end


function dm.version()
	local cfd = dm_opencontrol()
	local r, em = dm_getversion(cfd)
	lualinux.close(cfd)
	return r, em
end




------------------------------------------------------------------------
return dm