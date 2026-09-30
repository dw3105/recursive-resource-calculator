-- DP1-DP2 red on round-52-base, 2026-09-30: an unfed underground pair must be pruned; a fed one stays.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local key, prune = Route._coordinate_key, Route._test.prune_dead_route_segments
local function work(with_pair1)
 local w={segments={},segments_by_cell={},entities={},entity_by_segment={},counters={},bindings={},endpoint_by_id={},demands={}}
 local n=0
 local function add(seg,cells)
  n=n+1; seg.segment_id="s"..n; seg.flow_id="ore"; seg.flow_ids={ore=true}; seg.allocations={{flow_id="ore",sink="x",rate_per_second=1}}
  w.segments[#w.segments+1]=seg; for _,c in ipairs(cells) do w.segments_by_cell[key(c[1],c[2])]=seg end
  local e={segment_id=seg.segment_id}; w.entities[#w.entities+1]=e; w.entity_by_segment[seg.segment_id]=e
 end
 add({kind="belt",direction=Grid.EAST},{{0,0}})
 add({kind="belt",underground=true,direction=Grid.EAST,underground_entry_key=key(1,0),underground_exit_key=key(4,0),underground_exit_x=4,underground_exit_y=0},{{1,0},{4,0}})
 add({kind="belt",direction=Grid.EAST},{{5,0}})
 if with_pair1 then
  add({kind="belt",direction=Grid.EAST},{{0,3}})
  add({kind="belt",underground=true,direction=Grid.EAST,underground_entry_key=key(1,3),underground_exit_key=key(4,3),underground_exit_x=4,underground_exit_y=3},{{1,3},{4,3}})
  add({kind="belt",direction=Grid.EAST},{{5,3}})
  w.demands={{flow_id="ore",source={x=0,y=3},sink={x=5,y=3}}}
 else
  -- The only pair is fed by its upstream surface belt.
  w.segments_by_cell[key(0,0)]=w.segments[1]
  w.demands={{flow_id="ore",source={x=0,y=0},sink={x=5,y=0}}}
 end
 return w
end
H.test("DP1 prunes only the unfed pair and preserves fed route",function()
 local w=work(true); prune(w); H.equal(w.segments_by_cell[key(1,0)]==nil,true); H.equal(w.segments_by_cell[key(4,0)]==nil,true)
 H.equal(w.segments_by_cell[key(1,3)]~=nil,true); io.write("DP1\n")
end)
H.test("DP2 preserves a fed pair",function()
 local w=work(false); prune(w); H.equal(w.segments_by_cell[key(1,0)]~=nil,true); io.write("DP2\n")
end)
H.done("test_route_dead_pair")
