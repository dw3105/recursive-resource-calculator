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
H.done("test_validate_slices")
