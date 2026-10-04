package.path = "./?.lua;" .. package.path
local f = assert(io.open("tests/golden/generate.lua")); local gen = f:read("*a"):gsub("^#![^\n]*\n", ""); f:close()
local a = gen:find("local JSON = {}", 1, true); local b = gen:find("local input_path,", a, true)
local JSON = assert(load(gen:sub(a, b - 1) .. "\nreturn JSON"))()
local input = JSON.decode(assert(io.open(arg[1])):read("*a"))
local Validate = require "logic.bp.validate"
local st = Validate.begin(input)
while not st.done do Validate.step(st, {ops = tonumber(arg[2])}) end
local out = {tostring(st.ok)}
for _, e in ipairs(st.errors or {}) do out[#out+1] = tostring(e.code) .. "(" .. table.concat(e.ids or {}, "|") .. ")" end
print(table.concat(out, ";"))
