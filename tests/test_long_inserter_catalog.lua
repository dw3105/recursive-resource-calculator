local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local Grid = require "logic.bp.grid"
local RowFixture = require "tests.fixtures.row_block"

local function candidate(mode)
    local row = RowFixture.science_row(Grid.NORTH, 10, 10)
    local entities = {}
    for _, item in ipairs(row.machines) do entities[#entities + 1] = item end
    local function belt(id, x, y, dir, flow_ids)
        entities[#entities + 1] = {id=id, kind="belt", name="transport-belt", x=x, y=y, w=1, h=1, dir=dir, flow_ids=flow_ids}
    end
    for x=0,11 do belt("run-"..x, 10+x, 10, Grid.EAST) end
    if mode == "long" or mode == "plain" or mode == "long_nofacts" then
        for _, x in ipairs({12, 15, 18, 21}) do
            -- The hand must reach this far input belt; its near belt tile is deliberately absent.
            belt("far-"..x, x, 9, Grid.EAST, {RowFixture.COPPER, RowFixture.GEAR})
            for i = #entities, 1, -1 do
                local e = entities[i]
                if e.kind == "belt" and e.x == x and e.y == 10 then table.remove(entities, i) end
            end
        end
    end
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
    for _, hand in ipairs(row.inserters) do
        if (mode == "long" or mode == "plain" or mode == "long_nofacts") and hand.role == "input" then
            hand.name = mode == "plain" and "inserter" or "long-handed-inserter"
        end
        entities[#entities + 1] = hand
    end
    local catalog = {entity={}, inserter={pickup_offset={x=0,y=-1},drop_offset={x=0,y=1},items_per_second=10},
        belt={items_per_second=10, lane_items_per_second=5}}
    if mode == "long" then catalog.long_inserter = {name="long-handed-inserter", pickup_offset={x=0,y=-2}, drop_offset={x=0,y=2}, items_per_second=10} end
    local state = Validate.begin({grid={w=60,h=60}, catalog=catalog, entities=entities})
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
local function geometry_errors(state)
    local result = {}
    for _, err in ipairs(state.errors or {}) do if err.code == "BP_V_INSERTER_GEOMETRY" then result[#result+1] = err end end
    return result
end
H.test("LI1 long inserter reads a belt two tiles out and drops two tiles in", function()
    H.equal(#geometry_errors(candidate("long")), 0, "captured long reach resolves both endpoints")
end)
H.test("LI1b with no captured long facts a long-handed hand reaches twice the plain hand", function()
    H.equal(#geometry_errors(candidate("long_nofacts")), 0, "doubled plain reach resolves both endpoints")
end)
H.test("LI2 the same far transfer fails when its entity is treated as a plain inserter", function()
    H.equal(#geometry_errors(candidate("plain")) > 0, true, "plain reach cannot reach far belt")
end)

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " LI3 catalog and default settings carry selected long inserter facts", function()
        local world = H.new_world(shape)
        world.add_default_infrastructure()
        world.add_inserter({name = "long-handed-inserter", pickup = {x=0,y=-2}, drop = {x=0,y=2}})
        world.add_player(1)
        storage[1] = {}
        local Settings = require "logic.bp.settings"
        local settings = Settings.of_sheet(1, "long-test")
        H.equal(settings.long_inserter.name, "long-handed-inserter", "default picker value")
        local catalog = require("logic.catalog").build(1, {
            belt = {belt=settings.belt.name, underground=settings.belt.underground, splitter=settings.belt.splitter, quality=settings.belt.quality},
            pipe = {pipe=settings.pipe.name, underground=settings.underground_pipe.name, quality=settings.pipe.quality},
            inserter=settings.inserter, long_inserter=settings.long_inserter, pole=settings.pole, robo=settings.roboport,
        })
        H.deep_equal(catalog.long_inserter.pickup_offset, {x=0,y=2}, "catalog pickup fact")
        H.deep_equal(catalog.long_inserter.drop_offset, {x=0,y=-2}, "catalog drop fact")
        local ok, code = Settings.validate(settings, catalog)
        H.equal(ok, true, "selected long inserter validates")
        H.equal(code, nil, "no settings rejection")
    end)
end

H.done("test_long_inserter_catalog")
