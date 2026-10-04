-- CS1-CS3 exercise sharing and sliced copies; intended to fail on round-56-base (2026-10-04).
local H = require "tests.harness"
local Search = require "logic.bp.search"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local function route_input()
    local function block(id,x,role,dx,dir)
        return {block_id=id,machines={{step_id=id}},x=x,y=2,w=1,h=1,ports={{port_id=id.."-port",role=role,
            kind="item",flow_id="item/f",rate_per_second=1,attach_dx=dx,attach_dy=0,
            normal_dir=Grid.dir_opposite(dir),travel_dir=dir}}}
    end
    return {grid=Grid.new(8,5),catalog={belt={belt="basic-belt",underground="basic-underground",
        items_per_second=10,lane_items_per_second=5,underground_max_distance=3}},
        blocks={block("source",0,"out",1,Grid.EAST),block("sink",7,"in",-1,Grid.EAST)},
        flows={{flow_id="item/f",producers={{step_id="source",share_per_second=1}},
            consumers={{step_id="sink",share_per_second=1}}}}}
end
local function run(ops)
    local state, ticks = Route.begin(route_input()), 0
    while not state.done and ticks < 10000 do ticks=ticks+1; Route.step(state,{ops=ops}) end
    H.equal(state.done,true,"route completes")
    H.equal(state.ok,true,"route succeeds")
    return state.result,ticks
end
H.test("CS1 stage input shares read-only catalog", function()
    local catalog = {entity={x={marker=1}}}
    local staged = Search._test.stage_input({work={input={catalog=catalog,snapshot={a=1},settings={nested={a=1}}}}}, {})
    H.equal(staged.catalog, catalog)
    staged.settings.nested.a = 2
    H.equal(catalog.entity.x.marker, 1)
end)
H.test("CS2 incumbent snapshot survives later work mutation", function()
    local source = {score={cost=7},candidate={entities={{id="e"}}}}
    local saved = Search._test.keep_incumbent(source)
    source.score.cost = 99
    source.candidate = {entities={{id="replacement"}}}
    H.equal(saved.score.cost, 7)
    H.equal(saved.candidate.entities[1].id, "e")
end)
H.test("CS3 copy slicers resume byte-identically", function()
    local one = run(2000)
    local resumed, ticks = run(1)
    H.deep_equal(resumed, one, "resumed publication equals the one-shot publication")
    H.equal(ticks > 1,true,"small operation budgets resume across calls")
    local cursor, sliced = nil, nil
    repeat
        local _, next_cursor, copied = Route._test.copy_result_sliced(one.segments, 1, cursor)
        cursor = next_cursor
        H.equal(copied <= 1, true, "one call copies at most one unit")
        sliced = cursor.result
    until cursor.index > #cursor.segments
    H.deep_equal(sliced.segments, one.segments, "sliced segment copy preserves result order and values")
end)
print("CS1 CS2 CS3")
--CS4 (round 56 copy on trial, 2026-10-04): a plain accept shares; a trial start freezes a deep copy that later
--in-place edits of the work candidate cannot reach (CT1 failed when the collector trial started without it).
H.test("CS4 trial start freezes the incumbent", function()
    local work_candidate = {entities = {{name = "belt", x = 1}}}
    local kept = Search._test.keep_incumbent({score = {}, candidate = work_candidate, source_candidate = {}, validation = {}})
    H.equal(kept.candidate == work_candidate, true, "plain accept shares the candidate")
    local frozen = Search._test.freeze_incumbent(kept)
    work_candidate.entities[1].x = 99
    H.equal(frozen.candidate.entities[1].x, 1, "frozen incumbent unchanged by later edits")
    H.equal(Search._test.freeze_incumbent(frozen) == frozen, true, "freezing twice copies once")
    print("CS4")
end)
H.done("test_copy_share")
