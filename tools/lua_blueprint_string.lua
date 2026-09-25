#!/usr/bin/env lua5.2
local root=(arg[0]:match("^(.*)/tools/[^/]+$") or ".")
package.path=root.."/?.lua;"..package.path
local H=dofile(root.."/tests/harness.lua")
H.new_world("2.0")
local f=assert(io.open(arg[1],"r")); local text=f:read("*a"); f:close()
local payload=helpers.json_to_table(text)
assert(payload and payload.ok==true,"generator output is not successful JSON")
io.write(require("logic.bp.blueprint_string").build(payload.result,"Recursive Resource Calculator"),"\n")
