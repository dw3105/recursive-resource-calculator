--Round 54 integrator: EM x1 Turn 12 Flip ended its holmium-ore belt (5,13) facing east into the side of the stone
--underground exit (6,13). The engine side-loads onto the exit's open half, so holmium rode the stone line; the bleed
--walk dropped every surface belt pointing into an exit, not only one from behind.
local H = require "tests.harness"
H.test("XS1 a belt side-loading another flow's underground exit is a bleed", function()
    H.new_world("2.0")
    local f = assert(io.open("tests/fixtures/validate_em1_exit_sideload.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Validate = require "logic.bp.validate"
    local state = Validate.begin(root)
    while not state.done do Validate.step(state, {ops = 100000}) end
    local hit = false
    for _, err in ipairs(state.errors or {}) do
        local d = err.detail or {}
        if err.code == "BP_V_BELT_BLEED" and d.flow == "item/holmium-ore" and d.tile and d.tile.x == 6 and d.tile.y == 13 then hit = true end
    end
    H.equal(hit, true, "holmium-ore bleed on the stone exit (6,13)")
end)
H.done("test_validate_exit_sideload")
