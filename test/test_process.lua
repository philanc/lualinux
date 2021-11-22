
-- test subprocess functions (run1, run2, run3, shell1, shell2, shell3)

-- NOTE: 
-- For some tests, child process writes to uncaptured stderr. 
-- To prevent the test from displaying stderr text, run it as:
--
--	lua test/test_process.lua 2>/dev/null
--

local process = require "lualinux.process"

local function test_run1() -- stdout only
	local rout, rerr, exitcode = process.run1("/bin/who", {"who"})
--~ 	print("test_run1", rout, rerr, exitcode)
	assert(rerr == "")
	assert(exitcode == 0)
	rout, rerr, exitcode = process.run1("/bin/who", {"who", "-y"})
--~ 	print("test_run1", rout, rerr, exitcode)
	assert(rout == "")
	assert(rerr == "")
	assert(exitcode == 1)
end

local function test_run2() -- stdin + stdout
	local rout, rerr, exitcode = process.run2(
		"/bin/md5sum", {"md5sum"}, "abc"
		)
--~ 	print("test_run2", rout, rerr, exitcode)
	assert(rout == "900150983cd24fb0d6963f7d28e17f72  -\n")
	assert(rerr == "")
	assert(exitcode == 0)
	
	rout, rerr, exitcode = process.run2( -- bad md5sum option
		"/bin/md5sum", {"md5sum", "-y"}, "abc"
		)
--~ 	print("test_run2", rout, rerr, exitcode)
	assert(rout == "")
	assert(rerr == "")
	assert(exitcode == 1)
end --test_run2

local function test_run3() -- stdin + stdout + stderr
	local rout, rerr, exitcode = process.run3(
		"/bin/md5sum", {"md5sum"}, "abc"
		)
--~ 	print("test_run3", rout, rerr, exitcode)
	assert(rout == "900150983cd24fb0d6963f7d28e17f72  -\n")
	assert(rerr == "")
	assert(exitcode == 0)
	
	rout, rerr, exitcode = process.run3( -- bad md5sum option
		"/bin/md5sum", {"md5sum", "-y"}, "abc"
		)
--~ 	print("test_run3", rout, rerr, exitcode)
	assert(rout == "")
	assert(rerr and rerr:match("^md5sum: invalid option"))
	assert(exitcode == 1)
end --test_run3

local function test_shell1_2()
	-- test large input, large output
	local r1 = assert(process.shell1("ls -l /usr/bin | md5sum", ""))
	local r2 = assert(process.shell1("ls -l /usr/bin", ""))
	local r3 = assert(process.shell2("md5sum", r2))
--~ 	print(r3)
	assert(r1 == r3)
end

local function test_shell3()
	-- test get output + err
	local rout, rerr, ex = assert(process.shell3("who --help ; who -y", ""))
--~ 	print("test_shell3", rout, rerr, ex)
	assert(rout and #rout > 50)
	assert(rerr and rerr:match("^who: invalid option"))
	assert(ex == 1)
end

local function test_shell_opt1()
	local rout, rerr, ex = process.shell1("pwd", {cd="/dev"})
--~ 	print("test_shell_opt1", rout, rerr, ex)
	assert(rout == "/dev\n")
	assert(rerr == "")
	assert(ex == 0)
	
	-- read more than maxbytes
	rout, rerr, ex = process.shell1("ls -l /dev", {maxbytes=4096})
--~ 	print("test_shell_opt1", rout, rerr, ex)
	assert(not rout) --nil
	assert(rerr == "readbytes limit exceeded") --nil
	assert(not ex) --nil
	
	-- child process too slow to read/write
	--    - don't spend more than ~500 ms in poll timeout
	local opt = {poll_timeout = 100, poll_maxtimeout = 500}
	rout, rerr, ex = process.shell1("sleep 5 ; pwd", opt)
--~ 	print("test_shell_opt1", rout, rerr, ex)
	assert(not rout) --nil
	assert(rerr == "timeout limit exceeded") --nil
	assert(not ex) --nil
	--
	
end
print("------------------------------------------------------------")
print("test_process...	Please ignore 'who' and 'md5sum' error messages")
test_run1()
test_run2()
test_run3()
test_shell1_2()
test_shell3()
test_shell_opt1()
print("")
print("test_process ok.")

