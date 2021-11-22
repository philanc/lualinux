-- Copyright (c) 2020  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------

--[[    lualinux process functions

run1(exe, argl, opt) => stdout, nil, exitcode  or  nil, errmsg
run2(exe, argl, input, opt) => stdout, nil, exitcode  or  nil, errmsg
run3(exe, argl, input, opt) => stdout, stderr, exitcode  or  nil, errmsg

	exe: path of executable program
	argl:     argument list
	input:    string provided to the program as stdin
	stdout:   stdout of the program captured as a string
	stderr:   stderr of the program captured as a string
	exitcode: program exitcode
	opt:      option table
	  opt.envl: program environment as a list of strings
		"key=value" (as returned by lualinux.environ())
	  opt.cd: the program is run in this directory
	  opt.maxsize:  if captured stdout or stderr is larger than this, 
		the program is terminated
	  opt.poll_timeout: poll timout in ms
	  opt.poll_maxtimeout: total poll timeout in ms
	  
shell1(cmd, opt) => stdout, nil, exitcode  or  nil, errmsg
shell2(cmd, input, opt) => stdout, nil, exitcode  or  nil, errmsg
shell3(cmd, input, opt) => stdout, stderr, exitcode  or  nil, errmsg

shell<i> are similar to run<i> functions except that the executable path and 
argument list are replaced with a shell command.

]]



--  he = require "he" -- at https://github.com/philanc/he

lualinux = require "lualinux"

util = require "lualinux.util"
fs = require "lualinux.fs"

local spack, sunpack = string.pack, string.unpack
local strf = string.format
local insert, concat = table.insert, table.concat

local errm, rpad, repr = util.errm, util.rpad, util.repr
local pf, px = util.pf, util.px

-- Linux constants

local POLLIN, POLLOUT = 1, 4
local POLLNVAL, POLLUP, POLLERR = 32, 16, 8

local O_CLOEXEC = 0x00080000
local O_NONBLOCK = 0x800  -- for non-blocking pipes

local F_GETFD, F_SETFD = 1, 2  -- (used to set O_CLOEXEC)
local F_GETFL, F_SETFL = 3, 4  -- (used to set O_NONBLOCK)

local ENOENT = 2
local EPIPE = 32
local EINVAL = 22

local MAXINT = math.maxinteger

------------------------------------------------------------------------

local clo = function(fd) 
	if fd and (fd ~= -1) then return lualinux.close(fd) end 
end


local function spawn_child(exepath, argl, envl, pn, cd)
	-- pn is the number of pipes
	--	1 for child stdout
	--	2 for child stdin, stdout
	-- 	3 for child stdin, stdout, stderr
	-- if cd is provided, the child process changes its working 
	--   directory to cd
	-- return child pid, cin, cout, cerr  or nil, errmsg
	-- cin, cout, cerr are always returned. They may be nil if not 
	-- required according to pn.
	-- child exit codes:
	--	99 exec failed
	--	98 chdir failed
	--	97 pipe dup2 failed

	-- create pipes:  
	-- cin is child stdin, cout is child stdout, cerr is child stderr
	-- pipes are non-blocking
	
	local cin0, cin1, cout0, cout1, cerr0, cerr1
	local flags, r, eno, pid
	
	cout0, cout1 = lualinux.pipe2()
	assert(cout0, cout1)

	if pn >= 2 then
		cin0, cin1 = lualinux.pipe2(); assert(cin0, cin1)
	end

	if pn == 3 then 
		cerr0, cerr1 = lualinux.pipe2(); assert(cerr0, cerr1)
	end

	-- set cin1 non-blocking
	if cin then
		flags = assert(lualinux.fcntl(cin1, F_GETFL))
		assert(lualinux.fcntl(cin1, F_SETFL, O_NONBLOCK))
	end
	
	pid, eno = lualinux.fork()
	if not pid then 
		clo(cin0); clo(cin1)
		clo(cout0); clo(cout1)
		clo(cerr0); clo(cerr1)
		return nil, errm(eno, "fork") 
	end	
	if pid == 0 then -- child
		if cd then
			-- if chdir fails, not much to do. just exit(98)
			r = lualinux.chdir(cd) or os.exit(98)
		end
		clo(cin1)  -- close unused ends
		clo(cout0)
		clo(cerr0)
		
		-- set pipe ends to child stdin, stdout, stderr
		-- if dup2 fails then exit(97)
		r = lualinux.dup2(cout1, 1) and lualinux.close(cout1) or os.exit(97)
		if pn >= 2 then
			r = lualinux.dup2(cin0, 0) and lualinux.close(cin0) 
				or os.exit(97)
		end
		if pn == 3 then
			r = lualinux.dup2(cerr1, 2) and lualinux.close(cerr1) 
				or os.exit(97)
		end
		r, err = lualinux.execve(exepath, argl, envl)
		-- get here only if execve failed.
		os.exit(99) -- child exits with an error code
	end
	-- parent
	clo(cin0)  -- close unused ends
	clo(cout1)
	clo(cerr1)
	-- parent writes to child stdin (cin1), 
	-- and reads from child stdout (cout0) [and stderr (cerr0)]
	return pid, cin1, cout0, cerr0
end --spawn_child

local function piperead_new(fd, maxbytes)
	-- create a new read task
	fd = fd or -1
	maxbytes = maxbytes or MAXINT
	local prt = { -- a "piperead" task
		done = (fd == -1), -- nothing to do if fd=-1
		fd = fd,
		rt = {}, -- table to collect read fragments
		maxbytes = maxbytes, -- max number of byte to read
		readbytes = 0,  -- total number of bytes already read
		poll = (fd << 32) | (POLLIN << 16), -- poll_list entry
	}
	return prt
end

local function piperead(prt, rev)
	-- a read step in a poll loop
	-- prt: the piperead state
	-- rev: a poll revents for the prt file descriptor
	-- return the updated prt or nil, errmsg in case of unrecoverable
	-- error
	local em
	if prt.done or rev == 0 then 
		-- nothing to do
	elseif rev & POLLIN ~= 0 then -- can read
		r, eno = lualinux.read(prt.fd)
		if not r then
			em = errm(eno, "piperead")
			return nil, em --abort
		elseif #r == 0 then --eof?
			goto done
			prt.done=true
		else
			table.insert(prt.rt, r)
			prt.readbytes = prt.readbytes + #r
			if prt.readbytes > prt.maxbytes then
				return nil, "readbytes limit exceeded" --abort
			end
		end
	elseif rev & (POLLNVAL | POLLUP) ~= 0 then 
		-- pipe closed by other party
		goto done
	elseif rev & POLLERR ~= 0 then
		-- cannot read. should abort.
		em = "cannot read from pipe (POLLERR)"
		return nil, em
	else
		-- unknown condition - abort
		em = strf("unknown poll revents: 0x%x", rev)
		return nil, em
	end--if
	do return prt end --return MUST be at the end of a block!!!
	
	::done::
	prt.done = true
	prt.poll = -1 << 32
	return prt
end --piperead

local function pipewrite_new(fd, str)
	-- create a new write task
	fd = fd or -1
	local pwt = {
		done = (fd == -1), -- nothing to do if fd=-1
		fd = fd, 
		s = str,
		si = 1, 	--index in s
		bs = 4096,  	--blocksize
		poll = (fd << 32) | (POLLOUT << 16), -- poll_list entry
	}
	return pwt
end

local function pipewrite(pwt, rev)
	-- a write step in a poll loop
	-- pwt: the pipewrite task
	-- rev: a poll revents for the pwt file descriptor
	-- return the updated task or nil, errmsg in case of 
	-- unrecoverable error
	local em, eno, status, exitcode, cnt, wpid
	if pwt.done or rev == 0 then 
		-- nothing to do
	elseif rev & (POLLNVAL | POLLUP | POLLERR) ~= 0 then
		-- cannot write. assume child is no longer there 
		-- or has closed the pipe. => write is done.
		goto done
	elseif rev & POLLOUT ~= 0 then -- can write
		cnt =  #pwt.s - pwt.si + 1
		if cnt > pwt.bs then cnt = pwt.bs end
		r, eno = lualinux.write(pwt.fd, pwt.s, pwt.si, cnt)
		if not r then	
			em = errm(eno, "write to cin")
			return nil, em
		else
			assert(r >= 0)
			pwt.si = pwt.si + r
			if pwt.si >= #pwt.s then goto done end
		end
	else
		-- unknown poll condition - abort
		em = strf("unknown poll revents: 0%x", rev)
		return nil, em	
	end

	do return pwt end --return MUST be at the end of a block!!!
	
	::done::
	pwt.done = true
	pwt.poll = -1 << 32
	-- close pipe end, so that reading child can detect eof
	lualinux.close(pwt.fd) 
	pwt.closed = true --dont close it again later
	return pwt
end --pipewrite


------------------------------------------------------------------------
-- run


local function run(exepath, argl, input_str, opt, pn)
	-- run a program in a subprocess
	-- according to pn, send string to subprocess stdin, 
	-- and capture subprocess stdout and stderr
	--	pn=1	stdout
	--	pn=2	stdin, stdout
	--	pn=3	stdin, stdout and stderr
	-- return pid, cin, cout, cerr
	
	opt = opt or {}
	envl = opt.envl or lualinux.environ()
	local r, eno, em, err, pid
	-- create pipes:  cin is child stdin, cout is child stdout,
	-- cerr is child stderr. pipes are non-blocking.
	local pid, cin, cout, cerr = spawn_child(
		exepath, argl, envl, pn, opt.cd
		)
	if not pid then return nil, cin end --here cin is the errmsg
	
--~ print("CHILD PID", pid)

	-- here parent writes to child stdin on cin and reads from
	-- child stdout, stderr on cout, cerr
	
	
	local inpwt = pipewrite_new(cin, input_str)
	local outprt = piperead_new(cout, opt.maxbytes)
	local errprt = piperead_new(cerr, opt.maxbytes)
	
	local poll_list = {inpwt.poll, outprt.poll, errprt.poll}
	local rev, cnt, wpid, status, exitcode
	local rout, rerr
	local timeout = opt.poll_timeout or 200 -- default timeout=200ms
	local maxtimeout = opt.poll_maxtimeout or MAXINT 
		-- default is to wait forever
	local totaltimeout = 0
	
	while true do
		-- poll cin, cout, cerr
		r, eno = lualinux.poll(poll_list, 200) -- timeout=200ms
		if not r then
			em = errm(eno, "poll")
			goto abort
		elseif r == 0 then -- timeout
			totaltimeout = totaltimeout + timeout
			if totaltimeout > maxtimeout then
				em = "timeout limit exceeded"
				goto abort
			end
			-- nothing else to do
			goto continue
		end
		
		--write to cin
		rev = poll_list[1] & 0xffff
		r, em = pipewrite(inpwt, rev)
		if not r then goto abort end
		
		--read from cout
		rev = poll_list[2] & 0xffff
		r, em = piperead(outprt, rev)
		if not r then goto abort end
		
		--read from cerr
		rev = poll_list[3] & 0xffff
		r, em = piperead(errprt, rev)
		if not r then goto abort end
		
		-- are we done?
		if inpwt.done and outprt.done and errprt.done then break end
		
		-- update the poll_list
		poll_list[1] = inpwt.poll
		poll_list[2] = outprt.poll
		poll_list[3] = errprt.poll
		
		::continue::
	end--while
	
	wpid, status = lualinux.waitpid(pid)
	exitcode = (status & 0xff00) >> 8
--~ pf("WAITPID\t\t%s   status: 0x%x  exit: %d", wpid, status, exitcode)
	
	rout = table.concat(outprt.rt)
	rerr = table.concat(errprt.rt)
	em = nil
	goto closeall
	
	::abort::
		rout, rerr = nil, em -- return nil, error msg

	::closeall::
		if not inpwt.closed then clo(cin) end
		clo(cout)
		clo(cerr)
	
	return rout, rerr, exitcode
	
end--run

local function run1(exepath, argl, opt)
	return run(exepath, argl, nil, opt, 1)
end

local function run2(exepath, argl, instr, opt)
	return run(exepath, argl, instr, opt, 2)
end

local function run3(exepath, argl, instr, opt)
	return run(exepath, argl, instr, opt, 3)
end

local function shell1(cmd, opt)
	return run1("/bin/sh", {"sh", "-c", cmd}, opt)
end

local function shell2(cmd, instr, opt)
	return run2("/bin/sh", {"sh", "-c", cmd}, instr, opt)
end

local function shell3(cmd, instr, opt)
	return run3("/bin/sh", {"sh", "-c", cmd}, instr, opt)
end


------------------------------------------------------------------------
local process = {
	run1 = run1,
	run2 = run2,
	run3 = run3,
	shell1 = shell1,
	shell2 = shell2,
	shell3 = shell3,
}

return process


	
	