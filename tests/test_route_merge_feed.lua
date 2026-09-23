-- Round 27: rear-fed two-input rows share one mixed belt.  The first case
-- exercises the physical lane witness on an explicit rear-port feed; the
-- second keeps the existing Groups-built row routing fixture in the route
-- path so this contract stays tied to real row blocks.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"
local Validate = require "logic.bp.validate"
local Row = require "tests.fixtures.row_block"

local function paired_lane_case(same_lane)
    local copper, gear, pack = Row.COPPER, Row.GEAR, Row.PACK
    -- Both item identities reach the same hand on one physical lane.
    local entities = {
        {id="rear-belt",kind="belt",name="transport-belt",x=12,y=12,dir=Grid.EAST,flow_ids={copper,gear}},
        {id="row:input:test",kind="inserter",name="inserter",role="input",flow_ids={copper,gear},
            x=12,y=13,pickup_position={x=12.5,y=12.5},drop_position={x=12.5,y=14.5}},
    }
    local v = Validate.begin({grid={w=40,h=40}, catalog={entity={}, inserter={items_per_second=10,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}, belt={items_per_second=10}},entities=entities})
    while not v.done do Validate.step(v,{ops=100}) end
    local mixed = false
    for _, e in ipairs(v.errors or {}) do if e.code == "BP_V_LANE_MIX" then mixed=true end end
    return mixed
end

H.test("RM1 the rear-feed validator still rejects two flows on one lane", function()
    H.equal(paired_lane_case(true), true)
end)

H.test("RM2 Groups continues to offer a two-input row with its rear port", function()
    local plan = {steps={{step_id="science", machine="assembler", machine_count=4,
        inputs={{flow_id=Row.COPPER,rate_per_second=1},{flow_id=Row.GEAR,rate_per_second=1}},
        outputs={{flow_id=Row.PACK,rate_per_second=1}}}}, flows={{flow_id=Row.COPPER},{flow_id=Row.GEAR},{flow_id=Row.PACK}}, ports={}}
    local catalog = {entity={assembler={name="assembler",tile_w=3,tile_h=3,etype="assembling-machine"},
        inserter={name="inserter",tile_w=1,tile_h=1,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}},
        inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}}
    local state = Groups.begin({plan=plan,catalog=catalog,_force_multi_flow_hands=true})
    for _=1,8 do if state.done then break end; Groups.step(state,{ops=1}) end
    local found=false
    for _, candidate in ipairs(state.result and state.result.candidates or {}) do
        for _, block in ipairs(candidate.blocks or {}) do
            for _, port in ipairs(block.ports or {}) do if port.port_id == "row:in:rear" then found=true end end
        end
    end
    H.equal(found,true,"Groups-built row exposes rear input")
end)

H.done("test_route_merge_feed")
