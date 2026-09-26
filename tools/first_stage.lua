-- Fast check (round 41): run one golden case only until the FIRST result of one stage, print it, exit.
-- Usage (repository root): lua5.2 tools/first_stage.lua <case> <pack|route|validate> [max_pack_fails]
-- Last line: FIRST-<STAGE> ok=<bool> <code>=<n>... [flow=<id> src=<x>,<y> sink=<x>,<y>]
--         or FIRST-<STAGE> none pack_fails=<n>   (pack refused max_pack_fails grids before the stage ran)
-- Exit 0 when ok=true, 4 when the stage refused, 3 when it never ran.
-- FAST_TIDY=1 skips tidy's keep-if-cheaper improvement pass (the slow part after route), so a first validator
-- verdict costs about a minute on the blue science sheet instead of 10-20 (round 41). DETAIL=1 prints one
-- `DETAIL <code> <ids> | <reason>` line per error and route shortfalls as `SHORT:<flow>@<source>-><sink>`.
package.path = "./?.lua;./?/init.lua;" .. package.path
local case_id = assert(arg[1], "usage: lua5.2 tools/first_stage.lua <case> <pack|route|validate> [max_pack_fails]")
local stage = arg[2] or "validate"
local max_pack_fails = tonumber(arg[3] or "12")
local label = "FIRST-" .. stage:upper()
local pack_fails = 0
local function report(state)
    local counts, parts, detail = {}, {}, ""
    for _, e in ipairs(state.errors or {}) do
        counts[tostring(e.code)] = (counts[tostring(e.code)] or 0) + 1
        local ep = e.endpoints
        if detail == "" and type(ep) == "table" then
            detail = string.format(" flow=%s src=%s,%s sink=%s,%s", tostring(e.flow_id), tostring(ep.source_x),
                tostring(ep.source_y), tostring(ep.sink_x), tostring(ep.sink_y))
        elseif detail == "" and e.block_id then
            detail = " block=" .. tostring(e.block_id)
        end
    end
    if os.getenv("DETAIL") then
        for _, e in ipairs(state.errors or {}) do
            local d = e.detail
            local ds = type(d) == "table" and (tostring(d.reason or "") .. " " .. tostring(d.flow_id or d.port_flow_id or ""))
                or tostring(d)
            io.stderr:write("DETAIL " .. tostring(e.code) .. " " .. table.concat(e.ids or {}, " ") .. " | " .. ds .. "\n")
        end
        for _, sf in ipairs(state.result and state.result.shortfalls or {}) do
            parts[#parts + 1] = "SHORT:" .. tostring(sf.flow_id) .. "@" .. tostring(sf.source_port_id) .. "->" .. tostring(sf.sink_port_id)
        end
    end
    for code, n in pairs(counts) do parts[#parts + 1] = code .. "=" .. n end
    table.sort(parts)
    io.stderr:write(label .. " ok=" .. tostring(state.ok == true) .. " " .. table.concat(parts, " ") .. detail .. "\n")
    os.exit(state.ok == true and 0 or 4)
end
local Route = require "logic.bp.route"
local tidy_begin = Route.tidy_begin
Route.tidy_begin = function(done_state, options)
    local st = tidy_begin(done_state, options)
    if os.getenv("FAST_TIDY") and st and st.work then st.work.improved = true end
    return st
end
local Pack = require "logic.bp.pack"
local pack_step = Pack.step
Pack.step = function(state, budget)
    local r = pack_step(state, budget)
    if state.done and not state._first_stage_seen then
        state._first_stage_seen = true
        if stage == "pack" then report(state) end
        if not state.ok then
            pack_fails = pack_fails + 1
            if pack_fails >= max_pack_fails then
                io.stderr:write(label .. " none pack_fails=" .. pack_fails .. "\n")
                os.exit(3)
            end
        end
    end
    return r
end
if stage ~= "pack" then
    local M = require("logic.bp." .. stage)
    local step = M.step
    M.step = function(state, budget)
        local r = step(state, budget)
        if state.done then report(state) end
        return r
    end
end
arg = {[0] = "tests/golden/generate.lua", "--input", "tests/golden/cases/" .. case_id .. "/prepared_input.json",
    "--output", "/dev/null"}
dofile("tests/golden/generate.lua")
io.stderr:write(label .. " none search-ended\n")
os.exit(3)
