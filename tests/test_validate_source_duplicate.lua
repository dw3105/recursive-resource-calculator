--Red on round-37-wave2: the shipped candidate has two map-edge terminals for one flow.
local H = require "tests.harness"
H.test("duplicate edge terminals for one flow are rejected", function()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/validate_red10s_v1.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Validate = require "logic.bp.validate"
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local found = false
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_SOURCE_DUPLICATE" then found = true end end
    H.equal(found, true, "duplicate external source is diagnosed")
end)
H.done("test_validate_source_duplicate")
