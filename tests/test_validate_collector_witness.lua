--This frozen red-10s validator input reports the collector's second output hand and belt unused before the witness
--fix, even though both hands drop onto the same flow's witnessed collector belt.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"

H.test("red 10/s collector hands and belts are witnessed", function()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/validate_red10s_collector.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local unused = 0
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_TRANSPORT_UNUSED" then print(err.ids[1]) end end
    for _, err in ipairs(state.errors or {}) do
        if err.code == "BP_V_TRANSPORT_UNUSED" then unused = unused + 1 end
    end
    H.equal(unused, 0, "no transport hand or belt is unused")
end)

H.done("test_validate_collector_witness")
