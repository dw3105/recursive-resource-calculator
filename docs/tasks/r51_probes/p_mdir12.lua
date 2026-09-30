package.path = "./?.lua;./?/init.lua;" .. package.path
local f = assert(io.open("logic/bp/groups.lua")); local src = f:read("*a"); f:close()
local n; src, n = src:gsub("block%.machines%[#block%.machines %+ 1%] = machine\n", function() return "machine.dir = 12\n        block.machines[#block.machines + 1] = machine\n" end)
io.stderr:write("PATCH-LIVE mdir=12 n=" .. n .. "\n")
package.preload["logic.bp.groups"] = function() return assert(load(src, "@logic/bp/groups.lua"))() end
