-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
-- lualinux filesystem functions


local lualinux = require "lualinux"
local util = require "lualinux.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local insert, concat = table.insert, table.concat
local errm, rpad, pf, px = util.errm, util.rpad, util.pf, util.px

------------------------------------------------------------------------



------------------------------------------------------------------------
-- path utilities

fs = {}

function fs.makepath(dirname, name)
	-- returns a path made with a dirname and a filename
	-- if dirname is "", name is returned
	if dirname == "" then return name end
	if dirname:match('/$') then return dirname .. name end
	return dirname .. '/' .. name
end

------------------------------------------------------------------------
-- file types and attributes


local typetbl = {
	[1] = "f",	--fifo
	[2] = "c",	--char device
	[4] = "d",	--directory
	[6] = "b",	--block device
	[8] = "r", 	--regular
	[10]= "l", 	--link
	[12]= "s",	--socket
	--[14]= "w",	--whiteout (only bsd? and/or codafs? => ignore it)
}

function fs.typestr(ft)
	-- convert the numeric file type into a one-letter string
	return typetbl[ft] or "u" --unknown
end

fs.attribute_ids = {
	dev = 1,
	ino = 2,
	mode = 3,
	nlink = 4,
	uid = 5,
	gid = 6,
	rdev = 7,
	size = 8,
	blksize= 9,
	blocks = 10,
	atime = 11,
	mtime = 12,
	ctime = 13,
}

function fs.mtype(mode)
	-- return the file type of a file given its 'mode' attribute
	return (mode >> 12) & 0x1f
end

function fs.mperm(mode) 
	-- get the access permissions of a file given its 'mode' attribute
	return mode & 0x0fff
end

function fs.mpermo(mode) 
	-- get the access permissions of a file given its 'mode' attribute
	-- return the octal representation of permissions as a four-digit
	-- string, eg. "0755", "4755", "0600", etc.
	return strf("%04o", mode & 0x0fff) 
end

function fs.mexec(mode) -- !!! will probably remove this function 
	-- return true if file is a regular file and executable
	-- (0x49 == 0o0111)
	-- note: true if executable "by someone" --maybe not by the caller!!
	return ((mode & 0x49) ~= 0) and ((mode >> 12) == 8) 
end

function fs.lstat(fpath, tbl, statflag)
	-- tbl is filled with lstat() results for file fpath
	-- tbl is optional. it defaults to a new empty table
	-- return tbl
	-- if statflag is true, stat() is used instead of lstat()
	-- (defaults to using lstat)
	statflag = statflag and 1 or nil
	tbl = tbl or {}
	return lualinux.lstat(fpath, tbl, statflag) 
end

function fs.attr(fpath, attr_name, statflag)
	-- return a single lstat() attribute for file fpath
	-- fpath can be replaced by the table returned by lstat()
	-- for the file. attr_name is the name of the attribute.
	-- if statflag is true, stat() is used instead of lstat()
	-- (defaults to using lstat - statflag is of course ignored
	--  when fpath is a table)
	local attr_id = fs.attribute_ids[attr_name] 
		or error("unknown attribute name")
	if type(fpath) == "table" then return fpath[attr_id] end
	statflag = statflag and 1 or nil
	return lualinux.lstat(fpath, attr_id, statflag)
end	

function fs.lstat3(fpath, statflag)
	-- get useful attributes without filling a table:
	-- return file type, size, mtime | nil, errmsg
	-- if statflag is true, stat() is used instead of lstat()
	-- (defaults to using lstat)	
	local mode, size, mtime = lualinux.lstat3(fpath, statflag)
	if not mode then return nil, errm(size, "stat3") end
	local ftype = (mode >> 12) & 0x1f
	return ftype, size, mtime
end

function fs.size(fpath)
	return fs.attr(fpath, 'size')
end

function fs.mtime(fpath)
	return fs.attr(fpath, 'mtime')
end

function fs.touch(fpath, time)
	-- change file mtime and atime attribute (utime() syscall)
	-- time is optional. If time is not provided, current time is used.
	return lualinux.utime(fpath, time)
end


------------------------------------------------------------------------
-- directories

fs.getcwd = lualinux.getcwd	-- return current directory as a string
fs.chdir = lualinux.chdir	-- change current directory

-- directory iteration

function fs.dirmap(dirpath, func, t)
	-- map func over the directory  ("." and ".." are ignored)
	-- func signature: func(fname, ftype, t, dirpath)
	-- t is a table passed to func. It defaults to {}
	-- func should return true if the iteration is to continue.
	-- if func returns nil, err then iteration stops, and dirmap 
	-- returns nil, err.
	-- dirmap() returns t after directory iteration
	-- in case of opendir or readdir error, dirmap returns nil, errno
	-- 
	t = t or {}
	local dp = (dirpath == "") and "." or dirpath
	-- (note: keep dp and dirpath distinct. it allows to have an 
	-- empty prefix instead of "./" for find functions)
	--
	local dh, eno = lualinux.opendir(dp)
	if not dh then return nil, eno end
	local r
	while true do
		local fname, ftype = lualinux.readdir(dh)
		if not fname then
			eno = ftype
			if eno == 0 then break
			else 
				lualinux.closedir(dh)
				return nil, errm(eno, "readdir")
			end
		elseif fname == "." or fname == ".." then
			-- continue
		else
			r, eno = func(fname, ftype, t, dirpath)
			if not r then
				lualinux.closedir(dh)
				return nil, errm(eno, "dirmap func")
			end
		end
	end
	lualinux.closedir(dh)
	return t
end

function fs.ls0(dirpath)
	local tbl = {}
	return fs.dirmap(dirpath, 
		function(fname, ftype, t) insert(t, fname) end,
		tbl)
end

function fs.ls1(dirpath)
	-- ls1(dp) => { {name, type}, ... }
	local tbl = {}
	return fs.dirmap(dirpath, function(fname, ftype, t) 
		insert(t, {fname, fs.typestr(ftype)}) 
		return true
		end, 
		tbl)
end

function fs.ls3(dirpath)
	-- ls3(dp) => { {name, type, size, mtime}, ... }
	local ls3 = function(fname, ftype, t, dirpath)
		local fpath = fs.makepath(dirpath, fname)
		local mode, size, mtime = lualinux.lstat3(fpath)
		insert(t, {fname, fs.typestr(ftype), size, mtime})	
		return true
	end
	return fs.dirmap(dirpath, ls3, {})
end

function fs.lsdf(dirpath)
	-- return directory list, other files list
	local lsdf = function(fname, ftype, t, dirpath)
		insert(t[ftype == 4 and 1 or 2], fname)
		return true
	end
	local t, em = fs.dirmap(dirpath, lsdf, {{}, {}})
	if not t then return nil, em end
	return t[1], t[2]
end

function fs.findall(dirpath, predicate, notflag)
	-- find (recursively) files in dirpath. return a list of file paths
	-- for which predicate is true.
	-- predicate signature: p(fpath, ftype) => true or false value
	-- if predicate is a string, it is considered as a Lua pattern,
	-- the predicate used is a match function.
	-- notflag is optional. if true, the predicate result is negated.
	if type(predicate) == "string" then
		local pattern = predicate
		predicate = function(fp, ft) return (fp:match(pattern)) end
	end
	local t = {} -- used to collect file paths
	t.errors = {} -- use to collect directory errors (usually no perm.)
	local function rec(fname, ftype, t, dirpath)
		local r, eno
		local p = fs.makepath(dirpath, fname)
		r = not predicate or predicate(p, ftype) 
		if notflag then r = not r end
		if r then insert(t, p)	end
--~ 		print("REC", fname, ftype)
		if ftype == 4 then 
--~ 			print("RECURSE into", p)
			local subdir = p -- recurse into subdir
			r, eno = fs.dirmap(subdir, rec, t)
			if not r then 
				insert(t,errors, errm(eno, p)) 
			end
		end
		return true
		end
	return fs.dirmap(dirpath, rec, t)
end

function fs.findfiles(dirpath, predicate, notflag)
	-- same as findall, but does not include directories
	local pred = function(fname, ftype) 
		if ftype == 4 then return false end
		if type(predicate) == "string" then
			return (fp:match(predicate)) 
		end
	end
	return fs.findall(dirpath, pred, notflag)
end


------------------------------------------------------------------------
-- some useful mount options

fs.mount_options = {
	ro = 1,
	nosuid = 2,
	nodev = 4,
	noexec = 8,
	remount = 32,
	noatime = 1024,
	bind = 4096,
}




------------------------------------------------------------------------
return fs
