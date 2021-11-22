-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
-- lualinux tty mode functions


local lualinux = require "lualinux"
local util = require "lualinux.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local errm, rpad, pf, px = util.errm, util.rpad, util.pf, util.px

------------------------------------------------------------------------

-- see bits/termios.h

tty = {}

function tty.makerawmode(mode, nonblocking, opostflag)
	-- mode is the content of struct termios for the current tty
	-- return a termios content for tty raw mode (ie. no echo, 
	-- read one key at a time, etc.)
	-- if nonblocking is true, then read() is non blocking and
	-- return 0 if no key has been pressed
	-- taken from linenoise
	-- see also musl src/termios/cfmakeraw.c  and man termios(3)
	
	local fmt = "I4I4I4I4c6I1I1c36" -- struct termios is 60 bytes
	local iflag, oflag, cflag, lflag, dum1, ccVTIME, ccVMIN, dum2 =
		string.unpack(fmt, mode)
	-- no break, no CRtoNL, no parity check, no strip, no flow control
	-- .c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
	iflag = iflag & 0xfffffacd
	-- disable output post-processing
	if not opostflag then oflag = oflag & 0xfffffffe end
	-- set 8 bit chars -- .c_cflag |= CS8
	cflag = cflag | 0x00000030
	-- echo off, canonical off, no extended funcs, no signal (^Z ^C)
	-- .c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG)
	lflag = lflag & 0xffff7ff4
	-- return every single byte, without timeout
	ccVTIME = 0
	ccVMIN = (nonblocking and 0 or 1)
	return fmt:pack(iflag, oflag, cflag, lflag, 
			dum1, ccVTIME, ccVMIN, dum2)
end

function tty.getmode()
	-- return mode, or nil, errno
	return lualinux.ioctl(0, 0x5401, "", 60)
end

function tty.setmode(mode)
	-- return true or nil, errno
	return lualinux.ioctl(0, 0x5404, mode)
end

tty.initialmode = tty.getmode()

function tty.setrawmode(nonblocking)
	-- set raw mode based on the initial (cooked) mode
	-- default tty.setrawmode() gives a blocking raw mode.
	-- tty.setrawmode(true) gives a nonblocking raw mode 
	-- ie. lualinux.read() returns immediately 0 if no input is available.
	-- in Lua, io.read(1) doesn't block and return nil if no input 
	-- is available.
	local rawmode = tty.makerawmode(tty.initialmode, nonblocking)
	return tty.setmode(rawmode)
end

function tty.restoremode()
	return tty.setmode(tty.initialmode)
end


------------------------------------------------------------------------
return tty	
