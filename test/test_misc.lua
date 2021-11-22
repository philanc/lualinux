

lualinux = require "lualinux"

util = require "lualinux.util"
fs = require "lualinux.fs"

local spack, sunpack = string.pack, string.unpack
local insert, concat = table.insert, table.concat

local errm, rpad, repr = util.errm, util.rpad, util.repr
local pf, px = util.pf, util.px


------------------------------------------------------------------------
-- test process info

function test_procinfo()
--~ 	print(lualinux.getpid())
--~ 	print(lualinux.getppid())
--~ 	print(lualinux.geteuid())
--~ 	print(lualinux.getegid())
--~ 	print(lualinux.getcwd())
	assert(math.type(lualinux.getpid()) == "integer")
	assert(math.type(lualinux.getppid()) == "integer")
	assert(math.type(lualinux.geteuid()) == "integer")
	assert(math.type(lualinux.getegid()) == "integer")
	-- assume the current dir is "some/path/lualinux"
	assert(lualinux.getcwd():match(".*/lualinux$")) 
	local k, v = 'xyzzyzzy', 'XYZZYZZY'
	assert(os.getenv(k) == nil)
	lualinux.setenv(k, v); assert(os.getenv(k) == v)
	lualinux.unsetenv(k); assert(os.getenv(k) == nil)
	local el = lualinux.environ()
 	--print("environ lines:", #el)
	local r = false
	for i, line in ipairs(el) do
		r = r or line:match("PATH=.*/usr/bin")
	end
	assert(r)
	print("test_procinfo: ok.")
end

------------------------------------------------------------------------
-- test (l)stat

-- file types:  use mode & S_IFMT
S_IFMT = 0x0000f000
S_IFSOCK = 0x0000c000
S_IFLNK = 0x0000a000
S_IFREG = 0x00008000
S_IFBLK = 0x00006000
S_IFDIR = 0x00004000
S_IFCHR = 0x00002000
S_IFIFO = 0x00001000


function test_stat()
	-- assume the current dir is "some/path/lualinux" and contains lualinux.c
	os.execute("rm -f lualinuxsymlink; ln -s lualinux.c lualinuxsymlink")
	local lmode, lsize, lmtim = lualinux.lstat3("lualinuxsymlink")
	assert(lsize == 10)
	assert(lmode & 0xf000 == 0xa000) -- type is symlink
	assert(lmode & 0xfff == 0x01ff) -- perm is '0777'
	local target = lualinux.readlink("lualinuxsymlink")
	assert(target == "lualinux.c")
	local mode, size, mtim = lualinux.lstat3("lualinux.c")
	assert(mode & 0xf000 == 0x8000)
	t = lualinux.lstat("lualinux.c", {})
	assert(t[3]==mode and t[8]==size and t[12]==mtim)
	-- test mkdir
	local r, eno, em
	local dn = "/tmp/lualinuxtd"
	r, eno = lualinux.mkdir(dn)
	mode, size, mtim = lualinux.lstat3(dn)
	assert(mode & S_IFMT == S_IFDIR)
	r, eno = lualinux.rmdir(dn)
	assert(r)
	mode, size, mtim = lualinux.lstat3(dn)
--~ 	print('dir', mode, size)
	assert((not mode) and size==2) -- here size == errno == ENOENT
	os.remove("lualinuxsymlink")
	print("test_stat: ok.")
end

------------------------------------------------------------------------
-- test fork and other proc funcs

function test_fork()
	parpid = lualinux.getpid()
	pid = lualinux.fork()
	if pid == 0 then
--~ 		print("  child: getpid(), getppid =>", 
--~ 			lualinux.getpid(), lualinux.getppid())
		assert(parpid == lualinux.getppid())
--~ 		print("  child: exiting with os.exit(3)...")
		os.exit(3)
	else
--~ 		print("  parent pid =>", parpid)
--~ 		print("  parent: fork =>", pid)
--~ 		print("  parent: waiting for child...")
--~ 		lualinux.kill(pid, 15)
		pid, status = lualinux.waitpid()
--~ 		print("  parent: wait =>", pid, status)
		-- exitstatus: (status & 0xff00) >> 8
		-- termsig: status & 0x7f
		-- coredump: status & 0x80
		exit = (status & 0xff00) >> 8
		sig = status & 0x7f
		core = status & 0x80
--~ 		print("  status => exit, sig, coredump =>", exit, sig, core)
		assert(exit==3 and sig==0 and core==0)
	end
	print("test_fork: ok.")
end

------------------------------------------------------------------------
-- test filesystem functions


function test_fs()
	local dl, em = fs.ls1("/")
	assert(dl, em)
	local found = false
	for i, e in ipairs(dl) do
--~ 		print(e[2], e[1]) -- ftype, fname
		-- changed '/bin' to '/dev' because /bin is now often a link
		found = found or (e[1] == "dev" and e[2] == "d")
	end
	assert(found, "/dev not found")
	dl, em = fs.ls3("/dev/mapper")
	found = false
	for i, e in ipairs(dl) do
--~ 		print('find devmapper', e[1], e[2], e[3], e[4]) -- fname, ftype, size, mtime
		found = found or 
			(e[1] == "control" and e[2] == "c" and e[3] == 0)
	end
	assert(found, "/dev/mapper/control not found")
	--
	-- test fs.lsdf(path) => dirlist, filelist 
	dl, fl = fs.lsdf("/proc/sys/net/ipv4")
	assert(dl, fl)
	local dls, fls = concat(dl, " "), concat(fl, " ")
--~ 	print("dirs: ", dls, "\nfiles: ", fls)
	assert(fls:find"tcp_mem", "tcp_mem not found in file list")
	assert(dls:find"conf", "conf not found in dir list")
	-- test lstat, attr, mtype, mexec
	local pn, fa
	pn = "lualinux.c"; fa = fs.lstat(pn)
	local m = fs.attr(fa, 'mode')
	assert(fs.typestr(fs.mtype(m)) == 'r')
	assert(not fs.mexec(m))
	print("test_fs: ok.")
end

function test_file()
	-- 
	-- create a tmp file with content "hello"
	fname = "/tmp/lualinuxzz"

	util.fput(fname, "hello")
	local fd, eno, r, s, f
	local O_RDWR = 0x00000002
	fd = assert(lualinux.open(fname, O_RDWR, 0))
	assert(lualinux.ftruncate(fd, 20))
	assert(fs.size(fname) == 20)
	f= assert(lualinux.fdopen(fd, 'a')) -- f is a lua file object
	f:write("world!"); f:flush(); f:close()
	assert(util.fget(fname) == rpad("hello", 20, '\0') .. "world!")
	os.execute("rm " .. fname)
	print("test_file: ok.")
end




------------------------------------------------------------------------
function test_pipe2()
	local fd0, fd1 = lualinux.pipe2()
	assert(fd0, fd1)
--~ 	print("PIPE2", fd0, fd1)
	local pid = lualinux.fork()
	if pid == 0 then -- child
		lualinux.close(fd1)
		local s, err = lualinux.read(fd0)
		assert(s == "Hello!")
		lualinux.close(fd0)
		os.exit()
	else -- parent
		lualinux.close(fd0)
		lualinux.write(fd1, "Hello!")
		lualinux.close(fd1)
	end
	print("test_pipe2: ok.")
end


------------------------------------------------------------------------

print("------------------------------------------------------------")
print("test_misc...")
test_procinfo()
test_stat()
test_fork()
test_pipe2()
test_fs()
test_file()


	

