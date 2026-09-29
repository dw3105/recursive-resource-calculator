--RS1 is red on round-49-base.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local key = Route._coordinate_key
local N, E = Grid.NORTH, Grid.EAST

local function setup(strict, sink)
    local segment = {kind="belt", flow_id="stone", flow_ids={stone=true}, direction=E, underground=true,
        underground_exit_key=key(40,4), allocations={}}
    local work = {strict_ends=strict, segments_by_cell={[key(40,4)]=segment}}
    return work, sink or {row_port=true, travel_dir=8, x=40, y=4}, segment
end

H.test("RS1 wrong-way underground row head cannot seed", function()
    local w,sink,seg=setup(true)
    H.equal(Route._test.row_seed_passes(w,{flow_id="stone",sink=sink},40,4,E,seg),true)
    io.write("RS1\n")
end)
H.test("RS2 strict ends off preserves wrong-way seed", function()
    local w,sink,seg=setup(nil)
    H.equal(Route._test.row_seed_passes(w,{flow_id="stone",sink=sink},40,4,E,seg),false)
    io.write("RS2\n")
end)
H.test("RS3 inserter port is not suppressed", function()
    local w,sink,seg=setup(true,{travel_dir=8,x=40,y=4})
    H.equal(Route._test.row_seed_passes(w,{flow_id="stone",sink=sink},40,4,E,seg),false)
    io.write("RS3\n")
end)
H.test("RS4 a continuing same-flow trunk cannot seed the wrong-way row head", function()
    local w,sink,seg=setup(true)
    seg.underground=nil
    seg.direction=E
    w.segments_by_cell[key(41,4)]={kind="belt",flow_id="stone",flow_ids={stone=true},direction=E}
    H.equal(Route._test.row_seed_passes(w,{flow_id="stone",sink=sink},40,4,E,seg),true)
    w.segments_by_cell[key(41,4)]=nil
    H.equal(Route._test.row_seed_passes(w,{flow_id="stone",sink=sink},40,4,E,seg),false)
    io.write("RS4\n")
end)
H.done("test_route_row_seed")
