-- OR1-OR4: a Block picks one shared machine Turn and Flip; rebuild tests are red on round-51-base.
local H = require "tests.harness"
local Orient = require "logic.bp.orient"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local connection = {position={x=-1,y=2}, direction=8}
local block = {machines={{id="m1",can_flip=true}}, ports={{port_id="water",kind="fluid",connection=connection}}}
H.test("OR1 foundry port chooses a facing toward west", function()
    local picked = Orient.choose({block=block, turn=0, partner_dir={water=Grid.WEST}})
    local _,_,facing = Grid.fluid_connection(connection, picked.dir, picked.mirror)
    H.equal(facing, Grid.WEST, "selected fluid box points west")
end)
H.test("OR2 a machine without can_flip never receives a Flip", function()
    local picked = Orient.choose({block={machines={{id="m",can_flip=nil}},ports=block.ports}, partner_dir={water=Grid.WEST}})
    H.equal(picked.mirror, false, "non-flippable machine")
end)
H.test("OR3 default orientation returns the same Block and keeps port identity", function()
    local original = {id="b",ports={{port_id="p"}}}
    local result = Groups.reorient({}, original, {dir=0,mirror=false})
    H.equal(result, original, "identity is allocation-free")
    H.equal(result.ports[1].port_id, "p", "port id retained")
end)
H.test("OR4 unavailable rebuild context refuses unsafe orientation", function()
    local original = {id="b",machines={{can_flip=true}},ports={{port_id="p"}}}
    H.equal(Groups.reorient({}, original, {dir=4,mirror=false}), nil, "cannot rebuild without saved build facts")
end)
H.done("test_orient")
