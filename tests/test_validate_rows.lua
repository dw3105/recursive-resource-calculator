local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local Grid = require "logic.bp.grid"
local RowFixture = require "tests.fixtures.row_block"

local function candidate(mode)
    local row = RowFixture.science_row(Grid.NORTH, 10, 10)
    local entities = {}
    for _, item in ipairs(row.machines) do entities[#entities + 1] = item end
    for _, item in ipairs(row.inserters) do entities[#entities + 1] = item end
    local function belt(id, x, y, dir, flow_ids)
        entities[#entities + 1] = {id=id, kind="belt", name="transport-belt", x=x, y=y, w=1, h=1, dir=dir, flow_ids=flow_ids}
    end
    for x=0,11 do belt("run-"..x, 10+x, 10, Grid.EAST) end
    -- Short feeds meet the input head at (10,10). Their declared item identity is the witness source.
    if mode == "same" then
        belt("feed-both", 10, 9, Grid.SOUTH, {RowFixture.COPPER, RowFixture.GEAR})
    elseif mode ~= "missing" then
        belt("feed-copper", 10, 9, Grid.SOUTH, {RowFixture.COPPER})
        belt("feed-gear", 10, 11, Grid.NORTH, {RowFixture.GEAR})
    else
        belt("feed-copper", 10, 9, Grid.SOUTH, {RowFixture.COPPER})
        belt("feed-gear", 10, 11, Grid.NORTH, {"item/other"})
    end
    for x=2,11 do belt("out-"..x, 10+x, 16, Grid.EAST, {RowFixture.PACK}) end
    if mode == "single" then
        for _, hand in ipairs(row.inserters) do
            if hand.role == "input" then hand.flow_ids = {RowFixture.COPPER} end
        end
    end
    for _, hand in ipairs(row.inserters) do if hand.role == "input" then entities[#entities + 1] = hand end end
    local state = Validate.begin({grid={w=60,h=60}, catalog={entity={}, inserter={pickup_offset={x=0,y=1},drop_offset={x=0,y=-1},items_per_second=10}, belt={items_per_second=10, lane_items_per_second=5}}, entities=entities})
    while not state.done do Validate.step(state, {ops=100}) end
    return state
end
local function lane_errors(state)
    local result = {}
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_LANE_MIX" then result[#result+1] = err end end
    return result
end
H.test("VL1 paired flows side-loaded from opposite sides use separate lanes", function()
    H.equal(#lane_errors(candidate("split")), 0)
end)
H.test("VL2 paired flows entering from one side report every affected hand", function()
    local errors = lane_errors(candidate("same"))
    H.equal(#errors > 0, true)
    H.equal(errors[1].ids[1]:find(":input:") ~= nil, true)
    H.equal(errors[1].detail.hand_id, errors[1].ids[1])
end)
H.test("VL3 an absent paired flow is reported", function()
    H.equal(#lane_errors(candidate("missing")) > 0, true)
end)
H.test("VL4 a single-flow input hand is not judged as paired", function()
    H.equal(#lane_errors(candidate("single")), 0)
end)
H.done("test_validate_rows")
