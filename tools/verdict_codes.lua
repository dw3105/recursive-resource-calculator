-- First validate verdict of one prepared input, one line per error: `<code> <flow_id> <ids joined by commas>` (round 36).
-- Usage (repository root): lua5.2 tools/verdict_codes.lua <prepared_input.json>
package.path = "./?.lua;./?/init.lua;" .. package.path
local input = assert(arg[1], "usage: lua5.2 tools/verdict_codes.lua <prepared_input.json>")
local V = require "logic.bp.validate"
local step = V.step
V.step = function(state, budget)
    local r = step(state, budget)
    if state.done then
        for _, e in ipairs(state.errors or {}) do
            print(tostring(e.code) .. " " .. tostring(e.detail and e.detail.flow_id) .. " " .. table.concat(e.ids or {}, ","))
        end
        print("VERDICT ok=" .. tostring(state.ok == true))
        os.exit(0)
    end
    return r
end
arg = {[0] = "tests/golden/generate.lua", "--input", input, "--output", "/dev/null"}
dofile("tests/golden/generate.lua")
