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

H.test("RM3 a Groups row merges two same-side sources onto its rear feed", function()
    local plan = {steps={{step_id="science", machine="assembler", machine_count=4,
        inputs={{flow_id=Row.COPPER,rate_per_second=1},{flow_id=Row.GEAR,rate_per_second=1}},
        outputs={{flow_id=Row.PACK,rate_per_second=1}}}}, flows={{flow_id=Row.COPPER},{flow_id=Row.GEAR},{flow_id=Row.PACK}}, ports={}}
    local catalog = {entity={assembler={name="assembler",tile_w=3,tile_h=3,etype="assembling-machine"},
        inserter={name="inserter",tile_w=1,tile_h=1,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}},
        inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}},
        belt={belt="transport-belt",items_per_second=10}}
    local gs=Groups.begin({plan=plan,catalog=catalog,_force_multi_flow_hands=true})
    for _=1,16 do if gs.done then break end; Groups.step(gs,{ops=1}) end
    local b
    for _,c in ipairs(gs.result and gs.result.candidates or {}) do for _,candidate in ipairs(c.blocks or {}) do
        if candidate.row then b=candidate; break end
    end; if b then break end end
    H.equal(b~=nil,true,"Groups made a row block"); if not b then return end
    local placement={block_id=b.block_id,x=15,y=16,dir=Grid.NORTH}
    local placed=Groups.materialize(b,placement)
    local ports={
        {port_id="source:copper",role="in",flow_id=Row.COPPER,x=10,y=16,travel_dir=Grid.EAST,rate_per_second=1},
        {port_id="source:gear",role="in",flow_id=Row.GEAR,x=10,y=19,travel_dir=Grid.EAST,rate_per_second=1},
        {port_id="sink:packs",role="out",flow_id=Row.PACK,x=31,y=22,travel_dir=Grid.EAST,rate_per_second=1},
    }
    local flows={{flow_id=Row.COPPER,producers={{step_id="$external",port_id="source:copper",share_per_second=1}},consumers={{step_id="science",share_per_second=1}}},
        {flow_id=Row.GEAR,producers={{step_id="$external",port_id="source:gear",share_per_second=1}},consumers={{step_id="science",share_per_second=1}}},
        {flow_id=Row.PACK,producers={{step_id="science",share_per_second=1}},consumers={{step_id="$external",port_id="sink:packs",share_per_second=1}}}}
    local input={grid={w=40,h=40},blocks={{block_id=b.block_id,step_id="science",w=b.w,h=b.h,entities=b.machines,ports=b.ports}},
        placements={placement},belt_runs=placed.belt_runs,perimeter_ports=ports,flows=flows,multi_flow_hands=true,catalog=catalog}
    local state=Route.begin(input); local ticks=0
    while not state.done and ticks<30000 do ticks=ticks+1; Route.step(state,{ops=50}) end
    H.equal(state.ok,true,"row route succeeds "..tostring(state.errors and state.errors[1] and state.errors[1].code).." "..tostring(state.errors and state.errors[1] and state.errors[1].detail)); if not state.ok then return end
    local rear, feeds, belts=0,0,0
    for _,binding in ipairs(state.result.bindings or {}) do
        if binding.sink_port_id=="row:in:rear" then rear=rear+1 end
        if binding.sink_port_id=="row:in:"..Row.COPPER or binding.sink_port_id=="row:in:"..Row.GEAR then feeds=feeds+1 end
    end
    for _,e in ipairs(state.result.entities or {}) do if e.kind=="belt" or e.name=="transport-belt" then belts=belts+1 end end
    H.equal(rear,2,"both bindings enter through rear port"); H.equal(feeds,0,"side feed ports unused")
    H.equal(belts<40,true,"fewer belts than the two independent feeds; got "..tostring(belts))
    local v=Validate.begin({grid=input.grid,catalog=catalog,entities=state.result.entities,blocks=input.blocks,placements=input.placements,
        bindings=state.result.bindings,port_bindings=state.result.bindings,flows=flows,belt_runs=placed.belt_runs,multi_flow_hands=true})
    while not v.done do Validate.step(v,{ops=100}) end
    local lane_mix=false; for _,e in ipairs(v.errors or {}) do if e.code=="BP_V_LANE_MIX" then lane_mix=true end end
    H.equal(lane_mix,false,"different input flows reach different hand lanes")
end)

H.done("test_route_merge_feed")
