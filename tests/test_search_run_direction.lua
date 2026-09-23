local H = require "tests.harness"
local Search = require "logic.bp.search"
local Grid = require "logic.bp.grid"

local function block(id, feeds)
    return {id=id,w=5,h=3,row={first_x=0,last_x=4},ports={
        {port_id=id .. ":out:science",row_port=true,role="out",flow_id="science",attach_dx=5,attach_dy=1,normal_dir=Grid.WEST,travel_dir=Grid.EAST},
        {port_id=id .. ":in:ore",row_port=true,role="in",flow_id="ore",attach_dx=-1,attach_dy=1,normal_dir=Grid.EAST,travel_dir=Grid.EAST,rear=true}},
        belt_runs={{role="out",flows={"science"},tiles={{x=0,y=2},{x=1,y=2},{x=2,y=2},{x=3,y=2},{x=4,y=2}},dir=Grid.EAST,port={x=5,y=2,travel_dir=Grid.EAST}},
            {role="in",flows={"ore"},tiles={{x=0,y=0},{x=1,y=0},{x=2,y=0},{x=3,y=0},{x=4,y=0}},dir=Grid.EAST,head={x=0,y=0},feeds=feeds or {}}}}
end
local function source(id, feeds)
    return {id=id,blocks={block("row-a",feeds),{id="machine",w=1,h=1}}}
end
local function queue(candidate, used)
    local state={work={flip_queue={},flip_trials=used or 0}}
    Search._queue_candidate_flips(state,candidate)
    return state.work.flip_queue
end

H.test("queued variant reverses exactly one block and one run",function()
    local original=source("base")
    local variants=queue(original)
    H.equal(#variants,2,"out and one-input in variants are queued")
    local v=variants[1]
    H.equal(v.id,"base:flip:row-a:out","stable variant id")
    H.deep_equal(v.blocks[2],original.blocks[2],"other block is unchanged")
    H.deep_equal(v.blocks[1].belt_runs[2],original.blocks[1].belt_runs[2],"other run on row is unchanged")
    H.equal(v.blocks[1].belt_runs[1].reversed,true,"selected run is reversed")
    H.deep_equal(original.blocks[1].belt_runs[1].reversed,nil,"source remains untouched")
end)
H.test("one-input in-run flips and two-input in-run never flips",function()
    local one=queue(source("one")); local two=queue(source("two",{{flow_id="ore",side_tile={x=-1,y=0}}}))
    local function has(list, suffix) for _,v in ipairs(list) do if v.id:sub(-#suffix)==suffix then return true end end return false end
    H.equal(has(one,":in"),true,"one input eligible")
    H.equal(has(two,":in"),false,"side-fed in-run is not eligible")
end)
H.test("flip queue respects the per-grid cap",function()
    H.equal(#queue(source("at-cap"),8),0,"no more variants after eight trials")
    H.equal(#queue(source("near-cap"),7),1,"only one available slot is filled")
end)
H.test("a flip trial does not trip the ordinary no-improvement stop",function()
    local state={work={active_flip=true,no_improvement_attempts=2,flip_queue={}}}
    H.equal(Search._flip_trial_stops_search(state),false,"flip validation is outside the ordinary miss limit")
    state.work.active_flip=false
    H.equal(Search._flip_trial_stops_search(state),true,"ordinary candidates still obey the limit")
end)
H.test("reversed runs are never flipped back",function()
    local original=source("again")
    original.blocks[1].belt_runs[1].reversed=true
    local variants=queue(original)
    for _,v in ipairs(variants) do H.equal(v.id:find(":row-a:out",1,true),nil,"out run not flipped twice") end
end)
H.done("test_search_run_direction")
