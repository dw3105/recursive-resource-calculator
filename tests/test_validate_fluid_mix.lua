local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local function run(entities)
    local state = Validate.begin({grid={w=12,h=12}, catalog={entity={}}, entities=entities})
    while not state.done do Validate.step(state, {ops=100}) end
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_FLUID_MIX" then return true end end
    return false
end
H.test("adjacent pipes carrying different fluids are rejected", function()
    H.equal(run({{id="a", kind="pipe", name="pipe", flow_id="fluid/a", x=3, y=3, w=1, h=1},
        {id="b", kind="pipe", name="pipe", flow_id="fluid/b", x=4, y=3, w=1, h=1}}), true)
end)
H.test("an underground pipe ignores a foreign pipe beside its surface tile", function()
    H.equal(run({{id="ug", kind="pipe-to-ground", name="pipe-to-ground", flow_id="fluid/a", x=3, y=3, w=1, h=1, connection="pair"},
        {id="b", kind="pipe", name="pipe", flow_id="fluid/b", x=4, y=3, w=1, h=1}}), false)
end)
H.done("test_validate_fluid_mix")
