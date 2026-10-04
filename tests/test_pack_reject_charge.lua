-- Regression tests for lane 311. These assertions fail on round-56-base (2026-10-04).
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Pack = require "logic.bp.pack"
H.new_world("2.0")

H.test("PR1 rejected layered origins charge each buffer zone scanned", function()
    local state = Pack.begin({area = Grid.rect(0, 0, 20, 20), zone_blockers={{x=0,y=0,w=1,h=1}},
        mode="sugiyama", drawing={layer_of={x=1},rank_of={x=1}},
        blocks = {{block_id = "x", w = 1, h = 1,
        allowed_dirs = {Grid.NORTH}, buffer_zones = {{x=0,y=0,w=1,h=1,ring=1}}}}})
    -- The far-away placed zones all miss; the candidate is then rejected by the blocker after scanning them.
    for i = 1, 40 do state.buffer_zones[i] = {rect = {x=100+i,y=100,w=1,h=1}, ring=1} end
    local budget = {ops = 200}
    Pack.step(state, budget)
    H.equal((state.counters.buffer_zone_checks or 0) >= 40, true, "a reject bills the 40 placed zones")
    H.equal(200 - budget.ops >= 40, true, "the reject spends at least one op per scanned zone")
    H.equal(state.done, false, "zone scan yields with work remaining")
    print("PR1")
end)

H.test("PR2 blue bound pack remains deterministic", function()
    local file = assert(io.open("tests/fixtures/r56/blue_bound_pack.json", "r"))
    local input = helpers.json_to_table(file:read("*a")); file:close()
    local state = Pack.begin(input)
    while not state.done do Pack.step(state, {ops = 2000}) end
    local expected_file = assert(io.open("tests/fixtures/r56/311/pack_base.json", "r"))
    local expected = expected_file:read("*a"); expected_file:close()
    H.equal(helpers.table_to_json(state.result.placements), expected, "placements match round-56-base")
    print("PR2")
end)
--PR3 (integrator 2026-10-04, red on a8af1aa): pack cell keys built with tostring made 30-37 k tostring calls per
--game tick on red-1s at 4000 ops (Tick cost 60-73 ms, ADR 0003). Cell index lookups need no strings.
H.test("PR3 pack steps build no string cell keys", function()
    local file = assert(io.open("tests/fixtures/r56/blue_bound_pack.json", "r"))
    local input = helpers.json_to_table(file:read("*a")); file:close()
    local state = Pack.begin(input)
    local native, calls, worst = tostring, 0, 0
    _G.tostring = function(v) calls = calls + 1; return native(v) end
    local ok, err = pcall(function()
        while not state.done do calls = 0; Pack.step(state, {ops = 4000}); if calls > worst then worst = calls end end
    end)
    _G.tostring = native
    assert(ok, err)
    H.equal(worst <= 2000, true, "tostring calls in one 4000-op pack step: " .. worst)
    local expected_file = assert(io.open("tests/fixtures/r56/311/pack_base.json", "r"))
    local expected = expected_file:read("*a"); expected_file:close()
    H.equal(helpers.table_to_json(state.result.placements), expected, "placements match round-56-base")
    print("PR3")
end)
H.done("test_pack_reject_charge")
