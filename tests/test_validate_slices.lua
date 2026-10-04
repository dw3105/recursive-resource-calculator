--Round 56 integrator (2026-10-04). VS6 red on round-56-base: worst Validate.step at 4000 ops was 3.7-4.6 M weighted
--instructions (Tick cost 75-95 ms) on these fixtures; budget 2.44 M = 50 ms (ADR 0003). VS1: codes, ids and verdict
--equal to round-56-base at 50 / 4000 ops. Both run in a clean lua5.2: tests.harness swaps _G.type for a Lua function.
local H = require "tests.harness"
local FIXTURES = {"validate_red_green_r40_c1", "validate_red10s_attempt1", "validate_ins10s_v3_chain"}
local base = {}
for line in io.lines("tests/fixtures/r56/312/codes_base.txt") do
    local name, sha = line:match("^(%S+) (%x+)$"); if name then base[name] = sha end
end
local function run(cmd)
    local pipe = assert(io.popen(cmd .. " 2>&1")); local out = pipe:read("*a"); pipe:close(); return out
end
H.test("VS1 codes, ids and verdict equal base at 50 and 4000 ops", function()
    for _, fx in ipairs(FIXTURES) do
        for _, ops in ipairs({50, 4000}) do
            local out = run("lua5.2 tests/fixtures/r56/312/validate_codes.lua tests/fixtures/" .. fx .. ".json " .. ops .. " | sha256sum")
            H.equal(out:match("^(%x+)"), base[fx], fx .. " ops=" .. ops)
        end
    end
    print("VS1")
end)
H.test("VS6 every Validate.step at 4000 ops fits the 50 ms Tick cost", function()
    for _, fx in ipairs(FIXTURES) do
        local out = run("lua5.2 tests/fixtures/r56/312/validate_tick_cost.lua tests/fixtures/" .. fx .. ".json 4000")
        local worst = tonumber(out:match("WORST (%d+)"))
        H.equal(worst ~= nil and worst <= 2440000, true, fx .. ": " .. out)
    end
    print("VS6")
end)
H.test("VS8 red-green validate state: every step fits the 50 ms model (sort keys and tile keys built once)", function()
    --Round 56 gate 2026-10-04: base 3312046 weighted, 22.6k tostring calls in one tick (65 ms).
    local out = run("lua5.2 tests/fixtures/r56/312/validate_state_tick_cost.lua tests/fixtures/r56/rg_validate_t812.lua.gz 4000")
    local worst = tonumber(out:match("WORST (%d+)"))
    H.equal(worst ~= nil and worst <= 2440000, true, "every validate step fits the 50 ms model: " .. tostring(worst) .. " " .. out)
    H.equal(out:match("codes=(%d+)"), "0", "same verdict: no codes")
    print("VS8")
end)

H.test("VS9 blue beacon pass: same answer within the 50 ms model (per-beacon and per-pair answers built once)", function()
    --Round 56 gate 2026-10-04: base 5473472 weighted in one call (module lists re-expanded for every match).
    local out = run("lua5.2 tests/fixtures/r56/312/validate_phase_cost.lua tests/fixtures/r56/312/blue_val_beacon.lua.gz beacon")
    local weighted = tonumber(out:match("WEIGHTED (%d+)"))
    H.equal(out:match("SIG (%x+)"), "7dcef8a8", "same codes and beacon effects: " .. out)
    H.equal(weighted ~= nil and weighted <= 1000000, true, "beacon pass fits a tick: " .. tostring(weighted))
    print("VS9")
end)

H.test("VS10 a one-shot pass asks for a fresh tick", function()
    local G = require "tools.lib.graph_dump"
    local Validate = require "logic.bp.validate"
    local state = G.load("tests/fixtures/r56/312/blue_val_beacon.lua.gz")
    local budget = {ops = 4000}
    Validate.step(state, budget)
    H.equal(state.yield_tick, true, "beacon pass yields")
    H.equal(budget.ops > 0, true, "the unused rest is handed back, not spent")
    print("VS10")
end)

H.done("test_validate_slices")
