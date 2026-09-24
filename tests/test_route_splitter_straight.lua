--R1: a branch may only leave a straight-fed belt; splitter tiles also reject side merges.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"
local function fixture(heading)
    local data={grid=Grid.new(8,8),catalog={belt={belt="transport-belt",splitter="splitter",items_per_second=10,
        lane_items_per_second=5,underground_max_distance=0}},obstacles={{x=0,y=2,w=5,h=1,owner="wall"}},
        blocks={
            {block_id="source",machines={{step_id="source"}},x=0,y=3,w=1,h=1,ports={{port_id="source-out",role="out",kind="item",flow_id="item/r1",rate_per_second=3,
                attach_dx=1,attach_dy=0,normal_dir=Grid.WEST,travel_dir=Grid.EAST}}},
        {block_id="straight",machines={{step_id="straight"}},x=7,y=5,w=1,h=1,ports={{port_id="straight-in",role="in",kind="item",flow_id="item/r1",rate_per_second=1,
                x=5,y=5,travel_dir=Grid.EAST}}},
            {block_id="north",machines={{step_id="north"}},x=5,y=0,w=1,h=1,ports={{port_id="north-in",role="in",kind="item",flow_id="item/r1",rate_per_second=1,
                attach_dx=0,attach_dy=1,normal_dir=Grid.SOUTH,travel_dir=Grid.NORTH}}},
            {block_id="far-north",machines={{step_id="far-north"}},x=6,y=0,w=1,h=1,ports={{port_id="far-in",role="in",kind="item",flow_id="item/r1",rate_per_second=1,
                attach_dx=0,attach_dy=1,normal_dir=Grid.SOUTH,travel_dir=Grid.NORTH}}},
        },flows={{flow_id="item/r1",producers={{step_id="source",share_per_second=3}},consumers={{step_id="straight",share_per_second=1},
            {step_id="north",share_per_second=1},{step_id="far-north",share_per_second=1}}}}}
    local turns=heading/4
    local function point(x,y) for _=1,turns do x,y=7-y,x end; return x,y end
    local function vector(x,y) for _=1,turns do x,y=-y,x end; return x,y end
    for _,block in ipairs(data.blocks) do
        block.x,block.y=point(block.x,block.y)
        for _,port in ipairs(block.ports) do
            if port.x~=nil then port.x,port.y=point(port.x,port.y) end
            if port.attach_dx~=nil then port.attach_dx,port.attach_dy=vector(port.attach_dx,port.attach_dy) end
            for _,field in ipairs({"normal_dir","travel_dir"}) do
                if port[field]~=nil then port[field]=(port[field]+heading)%16 end
            end
        end
    end
    data.obstacles[#data.obstacles+1]={x=1,y=4,w=4,h=1,owner="wall"}
    for _,obstacle in ipairs(data.obstacles) do
        local corners={{obstacle.x,obstacle.y},{obstacle.x+obstacle.w-1,obstacle.y},
            {obstacle.x,obstacle.y+obstacle.h-1},{obstacle.x+obstacle.w-1,obstacle.y+obstacle.h-1}}
        local minx,miny,maxx,maxy
        for _,c in ipairs(corners) do local x,y=point(c[1],c[2]); minx=not minx and x or math.min(minx,x); maxx=not maxx and x or math.max(maxx,x); miny=not miny and y or math.min(miny,y); maxy=not maxy and y or math.max(maxy,y) end
        obstacle.x,obstacle.y,obstacle.w,obstacle.h=minx,miny,maxx-minx+1,maxy-miny+1
    end
    return data
end
local function run(heading)
    local state,ticks=Route.begin(fixture(heading)),0
    while not state.done and ticks<200000 do ticks=ticks+1;Route.step(state,{ops=100000}) end
    return state
end
local function key(x,y) return tostring(x)..":"..tostring(y) end
for _,heading in ipairs({Grid.NORTH,Grid.EAST,Grid.SOUTH,Grid.WEST}) do
    H.test("R1 heading "..tostring(heading).." splitter trunk is straight-fed",function()
        local state=run(heading)
        H.equal(state.ok,true,"both sinks are served")
        local count,has_corner=0,false
        for k,segment in pairs(state.work.segments_by_cell or {}) do
            if segment and segment.kind=="belt" and not segment.splitter and not segment.underground then
                local x,y=string.match(k,"^(%-?%d+):(%-?%d+)$");x,y=tonumber(x),tonumber(y)
                local dx,dy=Grid.dir_vector(segment.direction)
                local feeder=state.work.segments_by_cell[key(x-dx,y-dy)]
                if feeder and feeder.direction~=segment.direction then has_corner=true end
            end
        end
        H.equal(has_corner,true,"trunk includes a turn")
        for _,segment in ipairs(state.work.segments or {}) do
            if segment.splitter then
                count=count+1
                local dx,dy=Grid.dir_vector(segment.direction)
                local anchor=segment.splitter_anchor_key
                local ax,ay=string.match(anchor or "","^(%-?%d+):(%-?%d+)$");ax,ay=tonumber(ax),tonumber(ay)
                local feeder=state.work.segments_by_cell[key(ax-dx,ay-dy)]
                H.equal(feeder~=nil and feeder.direction==segment.direction,true,"anchor has a matching feeder behind it")
            end
        end
        H.equal(count>0,true,"fixture uses a splitter")
    end)
end
H.test("R1 a splitter anchor refuses a side merge",function()
    local state=run(Grid.EAST); H.equal(state.ok,true,"splitter route succeeds")
    for _,segment in ipairs(state.work.segments or {}) do
        if segment.splitter then
            local anchor=segment.splitter_anchor_key
            local ax,ay=string.match(anchor,"^(%-?%d+):(%-?%d+)$");ax,ay=tonumber(ax),tonumber(ay)
            local sideways=Grid.rotate_dir(segment.direction,Grid.EAST)
            local dx,dy=Grid.dir_vector(sideways)
            local target=state.work.segments_by_cell[key(ax+dx,ay+dy)]
            if target then H.equal(target.splitter,true,"side tile remains owned by splitter") end
        end
    end
end)
H.done("test_route_splitter_straight")
