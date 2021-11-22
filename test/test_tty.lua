
lualinux = require "lualinux"

util = require "lualinux.util"
tty = require "lualinux.tty"

local spack, sunpack = string.pack, string.unpack
local insert, concat = table.insert, table.concat

local errm, rpad, repr = util.errm, util.rpad, util.repr
local pf, px = util.pf, util.px


------------------------------------------------------------------------
-- test ioctl() - set tty in raw mode and back to original mode


function test_tty_mode()
	-- get current mode
	local cookedmode, eno = tty.getmode()
	assert(cookedmode, errm(eno, "tty.getmode"))
	assert(cookedmode:sub(1,36) == tty.initialmode:sub(1,36))
		--why the difference, starting at c_cc[19] (tos+36) ???

	print("test raw mode (blocking):  hit key, 'q' to quit.")
	-- set raw mode
	nonblocking = nil
	local rawmode = tty.makerawmode(cookedmode, nonblocking)
	tty.setmode(rawmode)
--~ 	tty.setmode(cookedmode)
--~ 	tty.setrawmode()
	while true do 
		c = io.read(1)
		if c == 'q' then break end
		io.write(' ')
		io.write(string.byte(c))
	end
	-- reset cooked mode
--~ 	tty.setmode(cookedmode)
	tty.restoremode()
	print("\rback to normal cooked mode.")
	
	print("test raw mode (nonblocking):  hit key, 'q' to quit.")
	-- set raw mode
	nonblocking = true
	local rawmode = tty.makerawmode(cookedmode, nonblocking)
	tty.setmode(rawmode)
	while true do 
		c = io.read(1)
		if not c then
			io.write(".")
			lualinux.msleep(500)
		elseif c == 'q' then break
		else	io.write(' ') ; io.write(string.byte(c))
		end
	end
	-- reset cooked mode
--~ 	tty.setmode(cookedmode)
	tty.restoremode()
	print("\rback to normal cooked mode.")

	print("test_mode: ok.")
end

------------------------------------------------------------------------

test_tty_mode()
	

