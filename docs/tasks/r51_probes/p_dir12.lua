package.path = "./?.lua;./?/init.lua;" .. package.path
local Pack = require "logic.bp.pack"
local begin = Pack.begin
Pack.begin = function(input)
  for _, b in ipairs(input.blocks or {}) do b.allowed_dirs = {12} end
  io.stderr:write("PATCH-LIVE dir=12\n")
  return begin(input)
end
