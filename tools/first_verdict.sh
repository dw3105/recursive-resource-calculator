#!/bin/sh
# Fast probe: run the player's sheet until the FIRST candidate's validator verdict, print it, exit. ~5 s.
# Usage (repository root): sh tools/first_verdict.sh   -- prints FIRST-VERDICT ok=... <code>=<count>...
lua5.2 -e '
package.path = "./?.lua;./?/init.lua;" .. package.path
local V = require "logic.bp.validate"
local step = V.step
V.step = function(state, budget)
  local r = step(state, budget)
  if state.done then
    local codes = {}
    for _, e in ipairs(state.errors or {}) do codes[e.code] = (codes[e.code] or 0) + 1 end
    local parts = {}
    for c, n in pairs(codes) do parts[#parts + 1] = c .. "=" .. n end
    table.sort(parts)
    io.stderr:write("FIRST-VERDICT ok=" .. tostring(state.ok) .. " " .. table.concat(parts, " ") .. "\n")
    os.exit(state.ok and 0 or 4)
  end
  return r
end
arg = {[0] = "tests/golden/generate.lua", "--input", "tests/golden/cases/player-red-science-1s/prepared_input.json", "--output", "/dev/null"}
dofile("tests/golden/generate.lua")
' 2>&1 >/dev/null | grep FIRST-VERDICT
