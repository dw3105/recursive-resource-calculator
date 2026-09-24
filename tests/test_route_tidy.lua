local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"
local function input()
    return {grid=Grid.new(10,6),catalog={belt={belt="basic-belt",underground="basic-underground",splitter="basic-splitter",items_per_second=10,lane_items_per_second=5,underground_max_distance=5}},blocks={
        {block_id="p",machines={{step_id="p"}},x=7,y=1,w=1,h=1,ports={{port_id="p-out",role="out",kind="item",flow_id="item/plate",rate_per_second=1,attach_dx=0,attach_dy=1,normal_dir=Grid.NORTH,travel_dir=Grid.SOUTH}}},
        {block_id="c",machines={{step_id="c"}},x=1,y=2,w=1,h=1,ports={{port_id="c-in",role="in",kind="item",flow_id="item/plate",rate_per_second=1,attach_dx=1,attach_dy=0,normal_dir=Grid.EAST,travel_dir=Grid.WEST}}}},
        flows={{flow_id="item/plate",is_fluid=false,producers={{step_id="p",share_per_second=1}},consumers={{step_id="c",share_per_second=1}}}}}
end
local function finish(s, tidy)
    local n=0; while not s.done and n<20000 do n=n+1; if tidy then Route.tidy_step(s,{ops=100000}) else Route.step(s,{ops=100000}) end end
    return s
end
for _,shape in ipairs(H.shapes()) do
 H.test(shape.." route tidy can be a separate step",function()
    local first=finish(Route.begin(input())); local separated
    local arg=input(); arg.tidy=false; separated=finish(Route.begin(arg))
    H.equal(separated.ok,true,"first routing succeeds")
    H.equal(separated.counters.routes_improved,nil,"first routing has no improve counters")
    local live=0; for _,e in ipairs(separated.work.entities) do if not e._route_removed then live=live+1 end end
    H.equal(#separated.result.entities,live,"first result is exactly the first routing layout")
    local tidy=finish(Route.tidy_begin(separated),true)
    H.equal(tidy.ok,true,"tidy completes")
    H.equal(#tidy.result.entities,#first.result.entities,"tidy reaches one-shot entity count")
 end)
 H.test(shape.." tidy obstacle blocks its cell",function()
    local initial=input(); initial.tidy=false
    local original=finish(Route.begin(initial))
    local state=finish(Route.tidy_begin(original,{obstacles={{x=4,y=2,w=1,h=1}}}),true)
    H.equal(state.ok,true,"tidy completes")
    local hit=false; for _,e in ipairs(state.result.entities) do if math.floor(e.position.x)==4 and math.floor(e.position.y)==2 then hit=true end end
    H.equal(hit,false,"tidy route avoids obstacle")
 end)
end
H.done("test_route_tidy")
