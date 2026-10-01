--Round 54 integrator: the engine binds fluoroketone's fluorine to two input connections of the cryogenic plant.
--Cryo x4 Turn 0 ran an ammonia pipe across the spare fluorine connection of one plant, so one pipe network sat on
--an ammonia box and a fluorine box (2.0.77 lab port map). With a known binding that is BP_V_FLUID_MIX.
local H = require "tests.harness"
H.test("BM1 another fluid's pipe on a bound connection of a machine is a fluid mix", function()
    H.new_world("2.0")
    local f = assert(io.open("tests/fixtures/validate_cryo4_bound_mix.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Validate = require "logic.bp.validate"
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local hit
    for _, err in ipairs(state.errors or {}) do
        if err.code == "BP_V_FLUID_MIX" and err.detail and err.detail.cause == "bound_box" then hit = err.detail end
    end
    assert(hit, "bound box mix reported")
    H.equal(hit.flow_a, "fluid/fluorine"); H.equal(hit.flow_b, "fluid/ammonia")
end)
H.done("test_validate_bound_box_mix")
