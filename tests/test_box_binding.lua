-- BB1-BB5 red on round-52-base (2026-09-30).
package.path = "./?.lua;" .. package.path
local Binding = require "logic.bp.box_binding"
local function read(path) local f=assert(io.open(path)); local s=f:read("*a"); f:close(); return s end
local a, ar = Binding.parse_fixture(read("tests/fixtures/box_binding_2.0.txt"))
local b, br = Binding.parse_fixture(read("tests/fixtures/box_binding_2.1.txt"))
assert(ar == br); print("BB1")
local expect
for line in read("tests/fixtures/flip_fluidboxes_2.0.txt"):gmatch("[^\n]+") do
    local box, x, y = line:match("CONN oil%-refinery dir=0.-mirror=false.-box=(%d+).-pos=([%d%-%.]+),([%d%-%.]+)")
    if x == "1" and y == "2" then expect = tonumber(box) end
end
assert(Binding.box_for(a, "oil-refinery", "basic-oil-processing", "crude-oil", "input") == expect)
local catalog={recipe={r={fluid_boxes={m={water={box=2,role="input"}}}}}}
assert(Binding.box_for(catalog,"m","r","water","input")==2)
assert(Binding.box_for(catalog,"m","r","x","input")==nil); print("BB2")
local proto={fluidbox_prototypes={{index=3,production_type="input"},{index=1,production_type="output"}}}
local machine={name="m",fluidbox_prototypes=proto.fluidbox_prototypes}
local created=0
local surface={create_entity=function() created=created+1; return {fluidbox={get_filter=function(i) return i==1 and {name="water"} or nil end,get_prototype=function(i) return proto.fluidbox_prototypes[i] end},destroy=function() end} end}
local got=Binding.probe(surface,machine,{name="r",ingredients={{name="water"}}})
assert(got.water.box==3 and got.water.role=="input"); print("BB3")
local surface21={create_entity=function() return {get_fluid_filter=function(i) return i==1 and {name="water"} or nil end,get_fluid_box_prototype=function(i) return proto.fluidbox_prototypes[i] end,destroy=function() end} end}
got=Binding.probe(surface21,machine,{name="r",ingredients={{name="water"}}})
assert(got.water.box==3); print("BB4")
local c={recipe={r={ingredients={{type="fluid",name="water"}},products={}}},entity={m={fluid_boxes={{}}}}}
prototypes={entity={m=machine},recipe={r={name="r",ingredients={{type="fluid",name="water"}},products={}}}}
Binding.fill(c,{{machine="m",recipe="r"}},function() return nil end); assert(c.recipe.r.fluid_boxes==nil)
local n=0; Binding.fill(c,{{machine="m",recipe="r"},{machine="m",recipe="r"}},function() n=n+1; return surface end)
assert(n==1 and created==2 and c.recipe.r.fluid_boxes.m.water.box==3); print("BB5")
