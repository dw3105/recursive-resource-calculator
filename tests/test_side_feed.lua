--This regression fails on the base code: SideFeed.into is a stub that always returns false.
local H = require "tests.harness"
local SideFeed = require "logic.bp.side_feed"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function key(x, y) return tostring(x) .. ":" .. tostring(y) end
local run = {{2, 5}, {3, 5}, {4, 5}}
local function side_at(tile, from_north, extra)
    local x, y = tile[1], tile[2]
    local d = from_north and Grid.SOUTH or Grid.NORTH
    local dx, dy = Grid.dir_vector(d)
    local cx, cy = x - dx, y - dy
    local cells = extra or {}
    cells[key(cx, cy)] = {kind="belt", direction=d}
    return cells
end

for i = 1, 3 do
    for _, north in ipairs({true, false}) do
        H.test("SF"..i.." side feed into east run tile", function()
            H.equal(SideFeed.into(side_at(run[i], north), key, run, Grid.EAST), true, "side belt feeds run")
        end)
    end
end

H.test("SF4 behind/ahead and belt pointing away do not count", function()
    local cells = {
        [key(1,5)]={kind="belt",direction=Grid.EAST},
        [key(5,5)]={kind="belt",direction=Grid.EAST},
        [key(3,4)]={kind="belt",direction=Grid.NORTH},
    }
    H.equal(SideFeed.into(cells,key,run,Grid.EAST),false,"longitudinal and away belts ignored")
end)

H.test("SF5 underground entrance outputs nothing but exit can feed", function()
    local tile=run[2]; local entrance=side_at(tile,true)
    entrance[key(3,4)].underground=true; entrance[key(3,4)].underground_entry_key=key(3,4)
    H.equal(SideFeed.into(entrance,key,run,Grid.EAST),false,"entrance has no side output")
    local exit=side_at(tile,true)
    exit[key(3,4)].underground=true; exit[key(3,4)].underground_entry_key=key(1,4)
    H.equal(SideFeed.into(exit,key,run,Grid.EAST),true,"underground exit can side feed")
end)

local function crossing_with_side_source()
    local function block(id,x,y,port,role,flow,adx,ady,dir,rate)
        return {block_id=id,machines={{step_id=id}},x=x,y=y,w=1,h=1,ports={{port_id=port,role=role,kind="item",
            flow_id=flow,rate_per_second=rate or 10,attach_dx=adx,attach_dy=ady,normal_dir=Grid.dir_opposite(dir),travel_dir=dir}}}
    end
    local input={grid=Grid.new(18,12),catalog={belt={belt="basic-belt",underground="basic-underground",
        splitter="basic-splitter",items_per_second=10,lane_items_per_second=5,underground_max_distance=5}},
        blocks={block("as",1,4,"as-out","out","item/a",1,0,Grid.EAST,5),
            block("at",15,4,"at-in","in","item/a",-1,0,Grid.EAST),
            block("bs",7,2,"bs-out","out","item/b",0,1,Grid.SOUTH),
            block("bt",7,9,"bt-in","in","item/b",0,-1,Grid.SOUTH),
            block("as2",9,1,"as2-out","out","item/a",0,1,Grid.SOUTH,5)},
        flows={{flow_id="item/a",is_fluid=false,producers={{step_id="as",share_per_second=5},{step_id="as2",share_per_second=5}},
            consumers={{step_id="at",share_per_second=10}}},
            {flow_id="item/b",is_fluid=false,producers={{step_id="bs",share_per_second=10}},consumers={{step_id="bt",share_per_second=10}}}}}
    return input
end

H.test("SF6 route preserves side feed when crossing buries the run", function()
    local state=Route.begin(crossing_with_side_source()); local ticks=0
    while not state.done and ticks<20000 do ticks=ticks+1; Route.step(state,{ops=10000}) end
    H.equal(state.done,true,"route completes")
    H.equal(state.ok,true,"route succeeds "..tostring(state.errors and state.errors[1] and state.errors[1].code))
    local cells=state.work.segments_by_cell
    local directions={Grid.NORTH,Grid.EAST,Grid.SOUTH,Grid.WEST}
    local saw_entrance=false
    for cell_key, segment in pairs(cells or {}) do
        if segment.underground and segment.underground_entry_key==cell_key then
            saw_entrance=true
            local x,y=cell_key:match("^(-?%d+):(-?%d+)$")
            x,y=tonumber(x),tonumber(y)
            for _,d in ipairs(directions) do
                if d~=segment.direction and d~=Grid.dir_opposite(segment.direction) then
                    local dx,dy=Grid.dir_vector(d); local side=cells[key(x-dx,y-dy)]
                    H.equal(not (side and side.kind=="belt" and not side.splitter and side.direction==d),true,
                        "no belt side feeds underground entrance")
                end
            end
        end
    end
    H.equal(saw_entrance,true,"crossing route still uses an underground entrance")
end)

H.done("test_side_feed")
