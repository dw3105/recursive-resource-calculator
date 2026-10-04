-- RF1-RF3 are regression cases intended to fail on round-56-base (2026-10-04).
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Search = require "logic.bp.search"

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
H.test("RF4 first route is strict", function()
    local input = {grid={w=2,h=2},catalog={belt={belt="belt"}},flows={},blocks={},strict_ends=true}
    local route = Route.begin(input)
    H.equal(route.work.strict_ends, true)
end)
print("RF1 RF2 RF3 RF4")
H.done("test_route_fix_bundle")
