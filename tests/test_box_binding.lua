-- BB1-BB5 red on round-52-base (2026-09-30).
package.path = "./?.lua;" .. package.path
local Binding = require "logic.bp.box_binding"
local function read(path) local f=assert(io.open(path)); local s=f:read("*a"); f:close(); return s end
local a, ar = Binding.parse_fixture(read("tests/fixtures/box_binding_2.0.txt"))
local b, br = Binding.parse_fixture(read("tests/fixtures/box_binding_2.1.txt"))
--Integrator 2026-09-30: fixtures are the full headless tables (2.0.77, 2.1.20). Same bindings for every recipe both
--versions know, except one real engine difference: 2.0 merges simple-coal-liquefaction heavy-oil over output boxes
--3-5, 2.1 binds box 3 only. 2.1 renamed molten-iron/molten-copper to iron-ore-melting/copper-ore-melting.
assert(ar > 200 and br > 200)
local function same(x, y)
    if #x.boxes ~= #y.boxes or x.role ~= y.role then return false end
    for i = 1, #x.boxes do if x.boxes[i] ~= y.boxes[i] then return false end end
    return true
end
local common = 0
for recipe, r in pairs(a.recipe) do
    local other = b.recipe[recipe]
    if other and recipe ~= "simple-coal-liquefaction" then
        for machine, fluids in pairs(r.fluid_boxes) do
            for fluid, entry in pairs(fluids) do
                common = common + 1
                assert(same(entry, other.fluid_boxes[machine][fluid]), recipe .. " " .. machine .. " " .. fluid)
            end
        end
    end
end
assert(common > 150, "common bindings " .. common)
local merged = a.recipe["casting-iron"].fluid_boxes.foundry["molten-iron"].boxes
assert(#merged == 2 and merged[1] == 1 and merged[2] == 2, "foundry casting-iron merged runtime box -> boxes 1, 2")
print("BB1")
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
--BB6 (integrator): get_prototype returns an ARRAY for a merged runtime box -> every prototype index bound.
local merged_surface={create_entity=function() return {fluidbox={get_filter=function(i) return i==1 and {name="water"} or nil end,
    get_prototype=function(i) return i==1 and {proto.fluidbox_prototypes[1], proto.fluidbox_prototypes[2]} or nil end},destroy=function() end} end}
got=Binding.probe(merged_surface,machine,{name="r",ingredients={{name="water"}}})
assert(#got.water.boxes==2 and got.water.boxes[1]==1 and got.water.boxes[2]==3 and got.water.box==1); print("BB6")
--BB7 (integrator): 2.1 get_fluid_filter gives {fluid = name}; reading only .name bound nothing headless 2.1.20.
local s21={create_entity=function() return {get_fluid_filter=function(i) return i==1 and {fluid="water"} or nil end,
    get_fluid_box_prototype=function(i) return proto.fluidbox_prototypes[i] end,destroy=function() end} end}
got=Binding.probe(s21,machine,{name="r",ingredients={{name="water"}}})
assert(got.water and got.water.box==3); print("BB7")
local c={recipe={r={ingredients={{type="fluid",name="water"}},products={}}},entity={m={fluid_boxes={{}}}}}
prototypes={entity={m=machine},recipe={r={name="r",ingredients={{type="fluid",name="water"}},products={}}}}
Binding.fill(c,{{machine="m",recipe="r"}},function() return nil end); assert(c.recipe.r.fluid_boxes==nil)
local n=0; Binding.fill(c,{{machine="m",recipe="r"},{machine="m",recipe="r"}},function() n=n+1; return surface end)
assert(n==1 and created==2 and c.recipe.r.fluid_boxes.m.water.box==3); print("BB5")
print("test_box_binding [Lua 5.2]: 5 cases, 5 passed, 0 failed")
