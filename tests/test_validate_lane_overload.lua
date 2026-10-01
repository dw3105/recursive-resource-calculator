--Round 54 integrator: plastic x4 Turn 8 in Factorio 2.0.77 delivered 7.5/s of 7.992/s. Both plastic branches landed on
--the west lane of the trunk at (14,4): the trunk's hands drop from the east (far lane = west) and the other branch
--side-loads from the west (near lane = west). One lane of a belt carries half the belt, so the sheet can never reach
--its rate; the validator counted flows per lane but never rates.
local H = require "tests.harness"
local function run(path)
    H.new_world("2.0")
    local f = assert(io.open(path))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Validate = require "logic.bp.validate"
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local found = {}
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_LANE_OVERLOAD" then found[#found + 1] = err end end
    return found, state
end
H.test("LO1 two branches on one lane above half a belt are a lane overload", function()
    local found = run("tests/fixtures/validate_plastic4_lane_overload.json")
    H.equal(#found >= 1, true, "plastic x4 Turn 8 names the overloaded lane")
    local d = found[1] and found[1].detail or {}
    H.equal(d.tile and d.tile.x, 14, "overload on the trunk column")
    H.equal(d.lane, "L", "the west lane of the north trunk")
    H.equal(d.rate > 7.9 and d.rate < 8.1, true, "all 7.992/s on that lane")
    H.equal(d.capacity, 7.5, "one lane of the belt")
end)
H.test("LO2 branches on opposite lanes are no overload", function()
    --First candidate of plastic x4 Turn 0 (rejected for other reasons); its two branches meet from opposite sides.
    local found = run("tests/fixtures/validate_plastic4_lane_ok.json")
    H.equal(#found, 0, "plastic x4 Turn 0 keeps each lane under half a belt")
end)
H.done("test_validate_lane_overload")
