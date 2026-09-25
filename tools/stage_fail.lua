-- Every stage's verdict per attempt for one prepared input (round 36).
-- Usage (repository root): lua5.2 tools/stage_fail.lua <prepared_input.json>
-- Prints `STAGE <name> ok=<bool> <code>=<n>...` each time a stage finishes, then `STAGE-END ok=<bool>`.
package.path = "./?.lua;./?/init.lua;" .. package.path
local input = assert(arg[1], "usage: lua5.2 tools/stage_fail.lua <prepared_input.json>")
local seen = setmetatable({}, {__mode = "k"})
for _, name in ipairs({"groups", "pack", "route", "hands", "power", "validate"}) do
    local M = require("logic.bp." .. name)
    local step = M.step
    M.step = function(state, budget)
        local r = step(state, budget)
        if state.done and not seen[state] then
            seen[state] = true
            local counts = {}
            for _, e in ipairs(state.errors or {}) do counts[e.code] = (counts[e.code] or 0) + 1 end
            for _, f in ipairs(state.result and state.result.failures or {}) do
                local key = tostring(f.code) .. ":" .. tostring(f.detail)
                counts[key] = (counts[key] or 0) + 1
            end
            local parts = {}
            for k, v in pairs(counts) do parts[#parts + 1] = k .. "=" .. v end
            table.sort(parts)
            io.stdout:write("STAGE " .. name .. " ok=" .. tostring(state.ok == true) .. " " .. table.concat(parts, " ") .. "\n")
        end
        return r
    end
end
local out = os.tmpname()
arg = {[0] = "tests/golden/generate.lua", "--input", input, "--output", out}
dofile("tests/golden/generate.lua")
local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
os.remove(out)
io.stdout:write("STAGE-END ok=" .. tostring(text:find('"ok":%s*true') ~= nil) .. "\n")
