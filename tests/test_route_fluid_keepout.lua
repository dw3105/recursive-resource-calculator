--Round 54 integrator: a merged engine-bound fluid box spans several connections. Search hands the route every such
--tile with its fluid (`fluid_keepouts`); only that fluid's pipes may sit there. Cryo x4 ran an ammonia pipe across
--a plant's spare fluorine connection. A belt on the tile joins nothing and stays allowed.
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"

local function fixture(kind, keep_flow)
    local flow = kind == "fluid" and "fluid/a" or "item/a"
    local source = {block_id="source",machines={{step_id="source"}},x=1,y=3,w=1,h=1,
        ports={{port_id="source-out",role="out",kind=kind,flow_id=flow,rate_per_second=1,attach_dx=1,attach_dy=0,travel_dir=Grid.EAST}}}
    local sink = {block_id="sink",machines={{step_id="sink"}},x=6,y=3,w=1,h=1,
        ports={{port_id="port",role="in",kind=kind,flow_id=flow,rate_per_second=1,attach_dx=-1,attach_dy=0,normal_dir=Grid.EAST,travel_dir=Grid.EAST}}}
    return {grid=Grid.new(10,8),catalog={pipe={pipe="pipe",underground="underground-pipe",throughput_per_second=100,underground_max_distance=5},
        belt={belt="belt",underground="underground-belt",items_per_second=100,underground_max_distance=5}},blocks={source,sink},
        fluid_keepouts={{x=3,y=3,flow_id=keep_flow}},
        flows={{flow_id=flow,is_fluid=kind=="fluid",producers={{step_id="source",share_per_second=1}},consumers={{step_id="sink",share_per_second=1}}}}}
end

local function on_tile(input)
    local state=Route.begin(input); local ticks=0
    while not state.done and ticks<20000 do ticks=ticks+1; Route.step(state,{ops=10000}) end
    H.equal(state.done,true,"route finishes"); H.equal(state.ok,true,"route succeeds")
    local count, hit = 0, false
    for _,e in ipairs(state.result.entities or {}) do
        count = count + 1
        if math.floor(e.position.x)==3 and math.floor(e.position.y)==3 then hit=true end
    end
    H.equal(count > 0, true, "something was routed")
    return hit
end

H.test("RK1 a pipe of another fluid stays off a keepout tile",function()
    H.equal(on_tile(fixture("fluid","fluid/b")), false, "fluid/a pipe avoids the fluid/b connection tile (3,3)")
end)
H.test("RK2 the keepout's own fluid and any belt may use the tile",function()
    H.equal(on_tile(fixture("fluid","fluid/a")), true, "own fluid runs straight through")
    H.equal(on_tile(fixture("item","fluid/b")), true, "a belt runs straight through")
end)
H.done("test_route_fluid_keepout")
