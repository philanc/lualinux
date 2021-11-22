
-- run tests
lualinux = require("lualinux")

print(string.rep("-", 60))
print(_VERSION .. "  -  " .. lualinux.VERSION)

require("test.test_misc")
require("test.test_process")
require("test.test_sock")

-- test_tty is not included since it requires user interaction

-- test_exec must be last since it exec()'s a shell command.
require("test.test_exec") 


