-- OR1-OR4: a Block picks one shared machine Turn and Flip; rebuild tests are red on round-51-base.
local H = require "tests.harness"
local Orient = require "logic.bp.orient"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local connection = {position={x=-1,y=2}, direction=8}
local block = {machines={{id="m1",can_flip=true}}, ports={{port_id="water",kind="fluid",connection=connection}}}
local function built_block(position)
    H.new_world(H.shapes()[1])
    local step = {step_id="cast", machine="foundry", recipe="cast", machine_count=1, modules={}, _groups={},
        inputs={{flow_id="fluid/water",kind="fluid",is_fluid=true,rate_per_second=1}}, outputs={}}
    local catalog = {entity={foundry={name="foundry",etype="assembling-machine",tile_w=5,tile_h=5,
        can_flip=true,fluid_boxes={{index=1,production_type="input",connections={{direction=8,
            positions={{x=position.x,y=position.y},{x=position.y,y=-position.x},
                {x=-position.x,y=-position.y},{x=-position.y,y=position.x}}}}}}}}}
    local flows = {{flow_id="fluid/water",kind="fluid",is_fluid=true}}
    local ports = {{port_id="water",flow_id="fluid/water",step_id="cast",role="in",kind="fluid",is_fluid=true}}
    local state = Groups.begin({plan={steps={step},flows=flows,ports=ports},catalog=catalog,flows=flows,ports=ports})
    for _=1,20 do if state.done then break end; Groups.step(state,{ops=10}) end
    return state, state.result.candidates[1].blocks[1]
end
H.test("OR1 foundry port chooses a facing toward west", function()
    local picked = Orient.choose({block=block, turn=0, partner_dir={water=Grid.WEST}})
    local _,_,facing = Grid.fluid_connection(connection, picked.dir, picked.mirror)
    H.equal(facing, Grid.WEST, "selected fluid box points west")
end)
H.test("OR2 a machine without can_flip never receives a Flip", function()
    local picked = Orient.choose({block={machines={{id="m",can_flip=nil}},ports=block.ports}, partner_dir={water=Grid.WEST}})
    H.equal(picked.mirror, false, "non-flippable machine")
end)
H.test("OR3 rebuilt Block keeps its id and every port id", function()
    local state, original = built_block({x=-1,y=2})
    local result = Groups.reorient(state, original, {dir=4,mirror=false})
    H.equal(result ~= nil, true, "reorientation succeeds")
    H.equal(result.id, original.id, "block id retained")
    H.deep_equal({result.ports[1].port_id}, {original.ports[1].port_id}, "port ids retained")
end)
H.test("OR4 pipe tile inside a machine refuses the reorientation", function()
    local state, original = built_block({x=0,y=0})
    H.equal(Groups.reorient(state, original, {dir=4,mirror=false}), nil, "blocked fluid pipe tile")
end)
--Round 51 integration (magenta light-oil-cracking, 2026-09-30): a rebuild with a port inside the Block can never get a
--pack slot (every grid BP_P_NO_FIT). OR5 fails without Groups.ports_on_edge in Groups.reorient; OR6 without the cache.
H.test("OR5 reorient refuses a rebuilt Block with a port inside its footprint", function()
    local build = Groups._reorient_build
    local inner = {id = "block:x", w = 10, h = 7, ports = {{port_id = "p", attach_dx = 6, attach_dy = 6}}}
    local edge = {id = "block:x", w = 10, h = 7, ports = {{port_id = "p", attach_dx = 10, attach_dy = 6}}}
    Groups._reorient_build = function() return inner end
    local ok, got = pcall(Groups.reorient, {work = {}}, {id = "block:x"}, {dir = 4, mirror = false})
    Groups._reorient_build = function() return edge end
    local ok2, got2 = pcall(Groups.reorient, {work = {}}, {id = "block:x"}, {dir = 4, mirror = false})
    Groups._reorient_build = build
    H.equal(ok and got == nil, true, "inside port refused")
    H.equal(ok2 and got2 == edge, true, "edge port kept")
    print("OR5")
end)

H.test("OR6 reorient builds once per Block and orient", function()
    local build, calls = Groups._reorient_build, 0
    local edge = {id = "block:y", w = 3, h = 3, ports = {{port_id = "p", attach_dx = -1, attach_dy = 1}}}
    Groups._reorient_build = function() calls = calls + 1; return edge end
    local state = {work = {}}
    local a = Groups.reorient(state, {id = "block:y"}, {dir = 8, mirror = false})
    local b = Groups.reorient(state, {id = "block:y"}, {dir = 8, mirror = false})
    Groups.reorient(state, {id = "block:y"}, {dir = 8, mirror = true})
    Groups._reorient_build = build
    H.equal(a == edge and b == edge, true, "same answer")
    H.equal(calls, 2, "one build per (Block, dir, mirror)")
    print("OR6")
end)

print("OR1 OR2 OR3 OR4")
H.done("test_orient")
