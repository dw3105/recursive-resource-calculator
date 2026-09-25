-- Regression: marking a required transport path must follow every transport type.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"
local Grid = require "logic.bp.grid"

local function run(shape)
    local entities = {
        {id="machine", name="machine", kind="machine", x=4,y=4,w=5,h=3,step_id="maker"},
        {id="hand", name="inserter", kind="inserter", x=9,y=4,w=1,h=1,dir=Grid.EAST,
            flow_id="item/out", role="output", machine_id="machine", pickup_target="machine", drop_target="head",
            pickup_position={x=8.5,y=4.5}, drop_position={x=10.5,y=4.5}},
    }
    local function belt(id,x,y,dir,extra)
        local e={id=id,name="transport-belt",kind="belt",x=x,y=y,w=1,h=1,dir=dir,flow_id="item/out"}
        for k,v in pairs(extra or {}) do e[k]=v end
        entities[#entities+1]=e
    end
    belt("head",10,4,Grid.EAST)
    local endpoint_x
    if shape == "splitter" then
        entities[#entities+1]={id="splitter",name="splitter",kind="splitter",x=11,y=4,w=2,h=1,dir=Grid.EAST,flow_id="item/out"}
        belt("tail",13,4,Grid.EAST); endpoint_x=13
    else
        belt("tail",11,4,Grid.EAST); endpoint_x=11
    end
    if shape == "underground" then
        belt("side-feed",10,5,Grid.NORTH)
        belt("exit",10,6,Grid.NORTH,{name="underground-belt",ug_pair_id="entrance"})
        belt("entrance",10,8,Grid.NORTH,{name="underground-belt",ug_pair_id="exit"})
    else
        belt("stub",10,2,Grid.NORTH)
    end
    local input={grid={w=20,h=12}, catalog={entity={machine={name="machine",etype="assembling-machine",tile_w=5,tile_h=3,needs_power=false}}, inserter={items_per_second=10,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}, belt={items_per_second=10}},
        entities=entities, plan={steps={{step_id="maker",machine="machine",machine_count=1,outputs={{flow_id="item/out",rate_per_second=1}}}}},
        flows={{flow_id="item/out",producers={{step_id="maker",share_per_second=1}},consumers={{step_id="$external",share_per_second=1}}}},
        ports={{port_id="machine-out",flow_id="item/out",role="out",step_id="maker",x=9,y=4,travel_dir=Grid.EAST},
            {port_id="external-out",flow_id="item/out",role="out",perimeter=true,x=endpoint_x,y=4,travel_dir=Grid.EAST}},
        segments={{segment_id="route",kind="belt",flow_id="item/out",length=4,allocations={{flow_id="item/out",sink="port:external-out",rate_per_second=1}}}},
        bindings={{source_port_id="machine-out",sink_port_id="external-out",flow_id="item/out",segment_id="route",rate_per_second=1}}}
    local state=Validate.begin(input)
    while not state.done do Validate.step(state,{ops=100}) end
    return state
end

    -- debug
local function unused(state,id)
    for _,err in ipairs(state.errors or {}) do
        if err.code=="BP_V_TRANSPORT_UNUSED" and err.ids[1]==id then return true end
    end
    return false
end

H.test("belt feeding an underground pair into a used belt is witnessed", function()
    local state=run("underground")
    H.equal(unused(state,"side-feed"),false)
    H.equal(unused(state,"entrance"),false)
    H.equal(unused(state,"exit"),false)
end)
H.test("belt feeding a splitter into a used belt is witnessed", function()
    local state=run("splitter")
    H.equal(unused(state,"splitter"),false)
    H.equal(unused(state,"head"),false)
    H.equal(unused(state,"tail"),false)
end)
H.test("a stub ending in nothing remains unused", function()
    local state=run("stub")
    H.equal(unused(state,"stub"),true)
end)
H.done("test_validate_witness_underground")
