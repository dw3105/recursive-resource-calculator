local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local Grid = require "logic.bp.grid"

--Player, green v2, 2026-09-24: a flow's last belt pointed into another flow's belt ("belt bleeding").
--Flow A runs down x=5 and ends at (5,2); flow B runs east along y=3.
local function run(last_dir, b_flows)
    local entities = {}
    local function belt(id, x, y, dir, flow_ids)
        entities[#entities + 1] = {id=id, kind="belt", name="transport-belt", x=x, y=y, w=1, h=1, dir=dir, flow_ids=flow_ids}
    end
    belt("a0", 5, 0, Grid.SOUTH, {"item/a"})
    belt("a1", 5, 1, Grid.SOUTH, {"item/a"})
    belt("a2", 5, 2, last_dir, {"item/a"})
    for x = 3, 8 do belt("b" .. x, x, 3, Grid.EAST, b_flows or {"item/b"}) end
    local state = Validate.begin({grid={w=20,h=20}, catalog={entity={}, belt={items_per_second=10, lane_items_per_second=5}}, entities=entities})
    while not state.done do Validate.step(state, {ops=100}) end
    local found = {}
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_BELT_BLEED" then found[#found + 1] = err end end
    return found
end
H.test("VB1 a last belt pointing into another flow's belt bleeds", function()
    local found = run(Grid.SOUTH)
    H.equal(#found > 0, true)
    H.equal(found[1].detail.flow, "item/a")
    H.equal(found[1].detail.tile.x, 5); H.equal(found[1].detail.tile.y, 3)
end)
H.test("VB2 the same last belt turned away does not bleed", function()
    H.equal(#run(Grid.EAST), 0)
end)
H.test("VB3 a join the receiving belt declares is no bleed", function()
    H.equal(#run(Grid.SOUTH, {"item/a", "item/b"}), 0)
end)
H.done("test_validate_bleed")
