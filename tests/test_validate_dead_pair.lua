-- DP3-DP4 red on round-52-base, 2026-09-30: player ruling 2026-09-30 makes a Dead pair invalid.
local H=require "tests.harness"
local Validate=require "logic.bp.validate"
local Grid=require "logic.bp.grid"
local function run(feeder)
 local entities={{id="m",name="machine",kind="machine",x=4,y=4,w=5,h=3,step_id="m"},
 {id="h",name="inserter",kind="inserter",x=9,y=4,w=1,h=1,dir=Grid.EAST,flow_id="item/o",role="output",machine_id="m",pickup_target="m",drop_target="head",pickup_position={x=8.5,y=4.5},drop_position={x=10.5,y=4.5}},
 {id="head",name="transport-belt",kind="belt",x=10,y=4,w=1,h=1,dir=Grid.EAST,flow_id="item/o"},
 {id="tail",name="transport-belt",kind="belt",x=11,y=4,w=1,h=1,dir=Grid.EAST,flow_id="item/o"},
 {id="ug-in",name="underground-belt",kind="belt",x=3,y=7,w=1,h=1,dir=Grid.EAST,flow_id="item/o",ug_pair_id="ug-out",type="input"},
 {id="ug-out",name="underground-belt",kind="belt",x=6,y=7,w=1,h=1,dir=Grid.EAST,flow_id="item/o",ug_pair_id="ug-in",type="output"}}
 if feeder then entities[#entities+1]={id="feed",name="transport-belt",kind="belt",x=2,y=7,w=1,h=1,dir=Grid.EAST,flow_id="item/o"} end
 local input={grid={w=20,h=12},catalog={entity={machine={name="machine",etype="assembling-machine",tile_w=5,tile_h=3,needs_power=false}},inserter={items_per_second=10,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}},belt={items_per_second=10}},entities=entities,
 plan={steps={{step_id="m",machine="machine",machine_count=1,outputs={{flow_id="item/o",rate_per_second=1}}}}},flows={{flow_id="item/o",producers={{step_id="m",share_per_second=1}},consumers={{step_id="$external",share_per_second=1}}}},
 ports={{port_id="mo",flow_id="item/o",role="out",step_id="m",x=9,y=4,travel_dir=Grid.EAST},{port_id="eo",flow_id="item/o",role="out",perimeter=true,x=11,y=4,travel_dir=Grid.EAST}},segments={{segment_id="r",kind="belt",flow_id="item/o",length=2,allocations={{flow_id="item/o",sink="port:eo",rate_per_second=1}}}},bindings={{source_port_id="mo",sink_port_id="eo",flow_id="item/o",segment_id="r",rate_per_second=1}}}
 local s=Validate.begin(input); while not s.done do Validate.step(s,{ops=100}) end; return s
end
local function dead(s) for _,e in ipairs(s.errors or {}) do if e.code=="BP_V_UNDERGROUND_DEAD" then return e end end end
H.test("DP3 rejects an unfed underground pair",function()
 local e=dead(run(false)); H.equal(e~=nil,true); H.equal(e.detail.x,3); H.equal(e.detail.y,7); H.equal(e.detail.flow_id,"item/o"); io.write("DP3\n")
end)
H.test("DP4 allows a physically fed underground pair",function() H.equal(dead(run(true)),nil); io.write("DP4\n") end)
H.done("test_validate_dead_pair")
