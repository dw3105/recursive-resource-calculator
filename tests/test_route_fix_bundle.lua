-- RF1-RF3 are regression cases intended to fail on round-56-base (2026-10-04).
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Search = require "logic.bp.search"
local D = require "tests.fixtures.search_doubles"

H.test("RF1 splitter branch refuses wrong-heading row sink", function()
    H.equal(Route._test.body_jump_row_heading_allowed({row_port=true, travel_dir=4}, 0), false)
end)
H.test("RF2 pipe dive refuses any machine port tile", function()
    H.equal(Route._test.pipe_dive_port_allowed(true, false), false)
end)
H.test("RF3 cleanup trims disconnected plain belt tail", function()
    local seg = {segment_id="tail",kind="belt",flow_id="f",direction=4,length=1,allocations={{flow_id="f",rate_per_second=1}}}
    local ent = {segment_id="tail",name="belt",position={x=1.5,y=1.5},direction=4}
    local work = {segments={seg},entities={ent},segments_by_cell={ ["1:1"]=seg },entity_by_segment={tail=ent},demands={},endpoint_by_id={}}
    Route._test.trim_dead_ends(work)
    H.equal(#work.segments, 0)
end)
--RF5 (integrator 2026-10-04, red on a39ee6a): the proven probe (r56_probes/p_fix3b.lua) trims only a belt segment
--that covers ONE cell; a two-cell east run (9,0)-(10,0) whose sorted-first key "10:0" is its end tile is kept.
H.test("RF5 cleanup keeps a multi-cell belt segment", function()
    local seg = {segment_id="run",kind="belt",flow_id="f",direction=4,length=2,allocations={{flow_id="f",rate_per_second=1}}}
    local ent = {segment_id="run",name="belt",position={x=9.5,y=0.5},direction=4}
    local work = {segments={seg},entities={ent},segments_by_cell={["9:0"]=seg, ["10:0"]=seg},entity_by_segment={run=ent},demands={},endpoint_by_id={}}
    Route._test.trim_dead_ends(work)
    H.equal(#work.segments, 1, "multi-cell segment kept")
    print("RF5")
end)
H.test("RF4 first route is strict", function()
    local original_begin, original_step = Route.begin, Route.step
    local strict
    local ok, err = pcall(function()
        D.run({}, function()
            Route.begin = function(input)
                strict = input.strict_ends
                return {done=true,ok=true,result={entities={},wires={},segments={},bindings={}},cursor={},progress={}}
            end
            Route.step = function(state) return state end
            local state = Search.begin(D.input())
            local ticks = 0
            while not state.done and strict == nil and ticks < 600 do
                ticks = ticks + 1
                Search.step(state, {ops=100})
            end
        end)
    end)
    Route.begin, Route.step = original_begin, original_step
    if not ok then error(err, 0) end
    H.equal(strict, true, "search's first route sets strict ends")
end)
print("RF1 RF2 RF3 RF4")
H.done("test_route_fix_bundle")
