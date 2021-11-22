-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
-- simple utility functions

local spack, sunpack, strf = string.pack, string.unpack, string.format

util = {}

function util.pf(...) print(strf(...)) end

function util.px(s) -- hex dump the string s
	for i = 1, #s-1 do
		io.write(strf("%02x", s:byte(i)))
		if i%4==0 then io.write(' ') end
		if i%8==0 then io.write(' ') end
		if i%16==0 then io.write('') end
		if i%32==0 then io.write('\n') end
	end
	io.write(strf("%02x\n", s:byte(#s)))
end

function util.repr(x) return string.format('%q', x) end

function util.rpad(s, w, ch) 
	-- pad s to the right to width w with char ch
	return (#s < w) and s .. ch:rep(w - #s) or s
end

function util.lstrip(s)
	-- remove whitespace at beginning of string s
	s = string.gsub(s, '^%s+', '')
	return s  -- return only 1st value returned by gsub
end

function util.rstrip(s) 
	-- remove whitespace at end of string s
	s = string.gsub(s, '%s+$', '')
	return s  -- return only 1st value returned by gsub
end

function util.strip(s) 
	-- remove whitespace at both ends of string s
	return util.lstrip(util.rstrip(s)) 
end



function util.errm(eno, txt)
	-- errm(17, "open") => "open error: 17"
	-- errm(17)         => "error: 17"
	-- errm(0, "xyz")   => nil
	if eno == 0 then return end
	local s = "error: " .. tostring(eno)
	return txt and (txt .. " " .. s) or s
end
	
function util.fget(fname)
	-- return content of file 'fname' or nil, msg in case of error
	local f, msg, s
	f, msg = io.open(fname, 'rb')
	if not f then return nil, msg end
	s, msg = f:read("*a")
	f:close()
	if not s then return nil, msg end
	return s
end

function util.fput(fname, content)
	-- write 'content' to file 'fname'
	-- return true in case of success, or nil, msg in case of error
	local f, msg, r
	f, msg = io.open(fname, 'wb')
	if not f then return nil, msg end
	r, msg = f:write(content)
	f:flush(); f:close()
	if not r then return nil, msg else return true end
end





------------------------------------------------------------------------
return util
