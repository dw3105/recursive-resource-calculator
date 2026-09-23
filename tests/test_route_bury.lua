--Straight laid runs can be buried for a crossing flow; empty spans are published as surface belts.
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"

local function crossing_input(curved)
    local function block(id, x, y, port_id, role, flow, attach_dx, attach_dy, dir)
        return {block_id=id,machines={{step_id=id}},x=x,y=y,w=1,h=1,ports={{port_id=port_id,role=role,kind="item",
            flow_id=flow,rate_per_second=10,attach_dx=attach_dx,attach_dy=attach_dy,normal_dir=Grid.dir_opposite(dir),travel_dir=dir}}}
    end
    local a_source_y = curved and 2 or 4
    return {grid=Grid.new(18,12),catalog={belt={belt="basic-belt",underground="basic-underground",
        splitter="basic-splitter",items_per_second=10,lane_items_per_second=5,underground_max_distance=5}},
        blocks={block("as",1,a_source_y,"as-out","out","item/a",1,0,Grid.EAST),
            block("at",15,4,"at-in","in","item/a",-1,0,Grid.EAST),
            block("bs",7,0,"bs-out","out","item/b",0,1,Grid.SOUTH),
            block("bt",7,9,"bt-in","in","item/b",0,-1,Grid.SOUTH)},
        flows={{flow_id="item/a",is_fluid=false,producers={{step_id="as",share_per_second=10}},consumers={{step_id="at",share_per_second=10}}},
            {flow_id="item/b",is_fluid=false,producers={{step_id="bs",share_per_second=10}},consumers={{step_id="bt",share_per_second=10}}}}}
end
local function run(input)
    local state=Route.begin(input); local ticks=0
    while not state.done and ticks<20000 do ticks=ticks+1; Route.step(state,{ops=10000}) end
    H.equal(state.done,true,"route completes"); H.equal(state.ok,true,"route succeeds"); return state
end
local function run_with_empty_optional_pair(input)
    local state=Route.begin(input); local ticks=0; local released=false
    while not state.done and ticks<20000 do
        ticks=ticks+1; Route.step(state,{ops=1})
        if not released then
            for _,segment in ipairs(state.work.segments or {}) do
                if segment.underground then segment.explicit=nil; released=true; break end
            end
        end
    end
    H.equal(released,true,"route creates a candidate pair before final publication")
    H.equal(state.done,true,"optional-pair route completes")
    return state
end
local function explicit_pair_input()
    local east={connection_type="underground",direction=Grid.EAST,max_underground_distance=5}
    local west={connection_type="underground",direction=Grid.WEST,max_underground_distance=5}
    return {grid=Grid.new(10,4),catalog={belt={belt="basic-belt",underground="basic-underground",items_per_second=10,
        underground_max_distance=5}},blocks={
        {block_id="source",machines={{step_id="source"}},x=1,y=1,w=1,h=1,ports={{port_id="s",role="out",kind="item",
            flow_id="item/free",rate_per_second=4,attach_dx=1,attach_dy=0,normal_dir=Grid.WEST,travel_dir=Grid.EAST,connection=east}}},
        {block_id="sink",machines={{step_id="sink"}},x=6,y=1,w=1,h=1,ports={{port_id="t",role="in",kind="item",
            flow_id="item/free",rate_per_second=4,attach_dx=-1,attach_dy=0,normal_dir=Grid.EAST,travel_dir=Grid.EAST,connection=west}}}},
        flows={{flow_id="item/free",producers={{step_id="source",share_per_second=4}},consumers={{step_id="sink",share_per_second=4}}}}}
end
local function ug_for(state, flow)
    local entries, count = {}, 0
    for _,e in ipairs(state.result.entities or {}) do
        if e.ug_role then count=count+1; if e.ug_role=="input" then entries[#entries+1]=e end end
    end
    return entries,count
end

for _,shape in ipairs(H.shapes()) do
    H.test(shape.." BU1 straight laid flow yields to a surface crossing",function()
        local state=run(crossing_input(false)); local a,b={},{}
        for _,e in ipairs(state.result.entities) do if e.ug_role=="input" then
            if e.flow_id=="item/a" then a[#a+1]=e elseif e.flow_id=="item/b" then b[#b+1]=e end end end
        H.equal(#a>0,true,"laid flow A has the buried pair"); H.equal(#b,0,"crossing flow B stays on surface")
        H.equal(math.floor(a[1].position.x),6,"buried input is one tile before crossing");
        H.equal(math.floor(a[1].position.y),4,"buried input stays on straight run")
    end)
    H.test(shape.." BU2 a turn before the crossing cannot be buried",function()
        local state=run(crossing_input(true)); local a,b={},{}
        for _,e in ipairs(state.result.entities) do if e.ug_role=="input" then
            if e.flow_id=="item/a" then a[#a+1]=e elseif e.flow_id=="item/b" then b[#b+1]=e end end end
        H.equal(#a,0,"curved flow A stays on surface"); H.equal(#b>0,true,"flow B dives")
    end)
    H.test(shape.." BU3 empty optional spans unbury; occupied crossings stay underground",function()
        local empty=run_with_empty_optional_pair(explicit_pair_input()); local _,empty_count=ug_for(empty)
        H.equal(empty_count,0,"pair covering only free tiles becomes surface belts")
        local occupied=run(crossing_input(true)); local _,occupied_count=ug_for(occupied)
        H.equal(occupied_count>0,true,"pair covering the laid crossing remains underground")
    end)
end
H.done("test_route_bury")
