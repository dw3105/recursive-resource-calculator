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
H.done("test_orient")
