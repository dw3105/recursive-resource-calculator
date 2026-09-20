--The player's own blocks, built in isolation, as a failing regression.
--
--Round 11 fixed the coverage RULE and still could not build the player's sheet. Every explanation offered for
--that came from reading code, and each one was wrong. This file exists so the next attempt is measured instead.
--
--Measured on the merged round 11 tree, legalcopilot-dev 2026-09-20, from
--tests/golden/cases/player-am2-chain/prepared_input.json, one block per step, no search, no packing, no routing:
--
--  step               machines  needs  covered  beacons emitted  width      time
--  casting-iron              1      3        2              518  2059 tiles  2.73s
--  copper-plate              1      3        2              518  2059 tiles  2.67s
--  casting-steel             1      1        1                2     5 tiles  0.0004s
--  copper-cable              1      1        1                2     4 tiles  0.0005s
--  electronic-circuit        1      1        1                2     4 tiles  0.0005s
--
--Three separate defects are visible in that table, and this file pins all three:
--
--  1. A single machine asking for three beacons never gets past two. The growth loop adds a beacon to whichever
--     side currently has FEWER hits, so when that side cannot reach the machine at all, all 512 additions are
--     futile. Six initial beacons plus 512 additions is exactly the 518 emitted.
--  2. The block inflates to 2059 tiles while doing it, so nothing can ever fit a grid.
--  3. A machine asking for ONE beacon is given two, one row above and one below, unconditionally. That is
--     double cost in the player's game for no coverage gain.
--
--The configured beacon counts here are the player's own and are never reduced to make this pass.
local H = require "tests.harness"
local Plan = require "logic.bp.plan"
local Groups = require "logic.bp.groups"

local CASE = "tests/golden/cases/player-am2-chain/prepared_input.json"

--The block builder and its helpers are file-locals. Reaching them through upvalues keeps this test on the real
--production code rather than a reimplementation of it, which is the whole point.
local function upvalue(fn, want)
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == want then return value end
    end
    error("missing upvalue " .. want, 2)
end

local function read_input()
    local file = io.open(CASE, "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    local source = io.open("tests/golden/generate.lua", "r")
    local generator = source:read("*a"):gsub("^#![^\n]*\n", "")
    source:close()
    local cut = generator:find("local input_path,", 1, true)
    local JSON = assert(load(generator:sub(1, cut - 1) .. "\nreturn JSON", "@json-reader"))()
    return JSON.decode(text)
end

local function blocks_for_each_step(instruction_bound)
    local input = read_input()
    if not input then return nil end
    local plan = Plan.begin(input)
    local guard = 0
    while not plan.done and guard < 100000 do
        guard = guard + 1
        Plan.step(plan, {ops = 100000})
    end
    H.equal(plan.ok, true, "the player's plan is healthy before any beacon work")
    input.plan = plan.result

    local make_candidates = upvalue(Groups.begin, "make_candidates")
    local normalize_plan = upvalue(make_candidates, "normalize_plan")
    local build_block = upvalue(make_candidates, "build_block")
    local step_ports = upvalue(make_candidates, "step_ports")
    local relevant_ports = upvalue(make_candidates, "relevant_ports")

    local _, catalog, steps, flows = normalize_plan(input)
    local ports = step_ports(steps)
    local built = {}
    for _, step in ipairs(steps) do
        --An instruction bound, so a runaway loop fails this test in seconds instead of hanging a suite.
        local instructions = 0
        if instruction_bound then
            debug.sethook(function()
                instructions = instructions + 1
                if instructions > instruction_bound then
                    error("instruction bound: this block does not terminate cheaply", 0)
                end
            end, "", 10000)
        end
        local ok, block = pcall(build_block, {step}, catalog,
            relevant_ports({step}, ports, flows), flows, input, "incident:" .. step.step_id)
        debug.sethook()
        built[#built + 1] = {step_id = step.step_id, ok = ok, block = ok and block or nil, err = not ok and block or nil}
    end
    return built
end

local function required_for(block)
    local most = 0
    for _, group in ipairs(block.beacon_groups or {}) do
        most = math.max(most, group.count_per_machine or 0)
    end
    return most
end

local function coverage_of(block)
    local counts = {}
    for _, beacon in ipairs(block.beacons or {}) do
        for _, id in ipairs(beacon.covered_members or {}) do counts[id] = (counts[id] or 0) + 1 end
    end
    return counts
end

H.test("BI1 every block of the player's sheet is built without a runaway", function()
    local built = blocks_for_each_step(4000)
    if not built then return H.equal(true, true, "the incident case is absent; nothing to check") end
    for _, entry in ipairs(built) do
        H.equal(entry.ok, true, entry.step_id .. " builds within its instruction bound: " .. tostring(entry.err))
    end
end)

H.test("BI2 a machine asking for three beacons is covered by three, never stuck at two", function()
    local built = blocks_for_each_step(nil)
    if not built then return H.equal(true, true, "the incident case is absent; nothing to check") end
    for _, entry in ipairs(built) do
        if entry.ok and entry.block then
            local needed = required_for(entry.block)
            if needed > 0 then
                for _, machine in ipairs(entry.block.machines or {}) do
                    local got = coverage_of(entry.block)[machine.id] or 0
                    H.equal(got >= needed, true, entry.step_id .. " covers " .. machine.id
                        .. ": needed " .. needed .. ", got " .. got)
                end
            end
        end
    end
end)

H.test("BI3 no block of the player's sheet is wider than the grid could ever hold", function()
    local built = blocks_for_each_step(nil)
    if not built then return H.equal(true, true, "the incident case is absent; nothing to check") end
    --An 8x8 roboport lattice at the measured 50-tile gap spans 4 + 7 * 50 = 354 tiles. A block wider than that
    --can never be placed, whatever the search does afterwards.
    for _, entry in ipairs(built) do
        if entry.ok and entry.block then
            H.equal((entry.block.w or 0) <= 354, true,
                entry.step_id .. " is " .. tostring(entry.block.w) .. " tiles wide; the largest grid is 354")
        end
    end
end)

H.test("BI4 a machine asking for one beacon is given one, not one above and one below", function()
    local built = blocks_for_each_step(nil)
    if not built then return H.equal(true, true, "the incident case is absent; nothing to check") end
    for _, entry in ipairs(built) do
        if entry.ok and entry.block and required_for(entry.block) == 1 then
            H.equal(entry.block.physical_beacon_count, 1,
                entry.step_id .. " emits " .. tostring(entry.block.physical_beacon_count)
                .. " beacons for a single-beacon requirement")
        end
    end
end)

H.done("test_beacon_placement_incident")
