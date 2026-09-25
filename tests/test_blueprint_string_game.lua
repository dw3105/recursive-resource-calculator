-- Fails before the fix: generation emitted an unwrapped JSON result without Factorio's leading 0.
local H=require "tests.harness"
H.new_world("2.0")
local B=require "logic.bp.blueprint_string"
local s=B.build({entities={{name="assembling-machine-1",position={x=0,y=0},type="machine",recipe="x"},{name="underground-belt",type="input",position={x=1,y=0}},{name="small-electric-pole",position={x=2,y=0}},{name="medium-electric-pole",position={x=3,y=0}}},wires={{3,0,4,0}}},"test")
H.equal(s:sub(1,1),"0","version prefix")
local bp=helpers.json_to_table(helpers.decode_string(s:sub(2))).blueprint
H.equal(bp.item,"blueprint","item"); H.equal(bp.label,"test","label"); H.equal(type(bp.version),"number","version")
H.equal(bp.entities[2].type,"input","typed underground end"); H.equal(bp.wires,nil,"placeholder pole wire omitted")
H.equal(bp.icons[1].signal.name,"assembling-machine-1","icon")
H.equal(bp.entities[1].search,nil,"internal key removed")
H.done("test_blueprint_string_game")
