-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
--[[		 lualinux poll functions and constants

XXXXXXXXXXXXXX   Work In Progress !!!   XXXXXXXXXXXXXXXXX

At the moment, a better example of lualinux.poll() usage can be found 
in file 'process.lua' (eg. see function run() and related local functions)


]]
local lualinux = require "lualinux"
local util = require "lualinux.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local errm, rpad, pf, px = util.errm, util.rpad, util.pf, util.px

------------------------------------------------------------------------


poll = {}

-- event and revent constants (see 'man 2 poll')
poll.POLLIN = 0x01
poll.POLLOUT = 0x04
poll.POLLERR = 0x08
poll.POLLHUP = 0x10
-- next is only available if poll is compiled with _GNU_SOURCE defined (!!)
poll.POLLHRDUP = 0x2000 
poll.POLLINVAL = 0x20

-- a pollfd struct is represented in Lua by a Lua Integer (int64)
-- a list of encoded pollfd structs is passed to poll()
-- events are arguments passed to poll in pollfd << structs
-- revents are results returned by poll() in the same list
-- events and revents are constants that can be OR'ed.
-- a pollfd struct is encoded as:   (fd << 32 | events << 16 | revents)
-- (see 'man 2 poll')

function poll.makepfd(fd, events)
	-- return a pollfd struct as a Lua integer
	return (fd << 32) | (events << 16)
end

function poll.parsepfd(pfd)
	-- parse an encoded pollfd struct and return fd, events, revents
	local fd, events, revents
	fd = pfd >> 32
	events = (pfd >> 16) & 0xffff
	revents = pfd & 0xffff
	return fd, events, revents
end


	
------------------------------------------------------------------------
return poll
