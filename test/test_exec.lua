
lualinux = require "lualinux"

print("------------------------------------------------------------")
print("test_exec...")

-- test execve
--	env is exec'd with an environment containing only
--	"test_execve= ok" - so this is what it should print!
lualinux.execve("/usr/bin/env", {"/usr/bin/env"}, {"test_execve= ok."})


	

