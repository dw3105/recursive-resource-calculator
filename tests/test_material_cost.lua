-- MC1-MC6 red on round-53-base (2026-09-30).
package.path = "./?.lua;" .. package.path
local Cost = require "logic.bp.material_cost"
local graph = {place={belt="belt", underground="underground"}, recipe_of={gear="gear", belt="belt", underground="underground"}, recipes={
 gear={ingredients={{name="plate",amount=2}},products={{name="gear",amount=1}}},
 belt={ingredients={{name="plate",amount=1},{name="gear",amount=1}},products={{name="belt",amount=2}}},
 underground={ingredients={{name="plate",amount=10},{name="belt",amount=5}},products={{name="underground",amount=2}}}
}}
local result=Cost.compute(graph,{"belt","underground"})
assert(result.belt==1.5 and result.underground==8.75); print("MC1")
local fluid=Cost.compute({place={x="x"},recipe_of={x="r"},recipes={r={ingredients={{name="water",amount=1}},products={{name="x",amount=1}}}}},{"x"})
assert(fluid.x==1); print("MC2")
local cycle=Cost.compute({place={x="a"},recipe_of={a="ra",b="rb"},recipes={ra={ingredients={{name="b",amount=1}},products={{name="a",amount=1}}},rb={ingredients={{name="a",amount=1}},products={{name="b",amount=1}}}}},{"x"})
assert(cycle.x>0 and cycle.x<math.huge); print("MC3")
local multi=Cost.compute({place={x="x"},recipe_of={x="r"},recipes={r={ingredients={{name="ore",amount=6}},products={{name="x",amount=2},{name="y",amount=4}}}}},{"x"})
assert(multi.x==3); print("MC4")
local function read(p) local f=assert(io.open(p)); local s=f:read("*a"); f:close(); return s end
local a=Cost.parse_fixture(read("tests/fixtures/material_cost_2.0.txt")); local b=Cost.parse_fixture(read("tests/fixtures/material_cost_2.1.txt"))
for _,t in ipairs({a,b}) do for _,v in pairs(t) do assert(v>0) end end
assert(a["transport-belt"]==b["transport-belt"]); print("MC5")
local H=require "tests.harness"
local world=H.new_world("2.0"); world.add_default_infrastructure()
local Catalog=require "logic.catalog"
local c={belt={belt="transport-belt",underground="underground-belt",splitter="splitter"},entity={}}
Catalog.fill_material(c); H.equal(c.material["transport-belt"]>0,true,"belt material from mock prototypes"); print("MC6")

--MC7 (integrator, round 53, 2026-09-30): Space Age makes ore by recipe (1 chunk -> 20 ore). A mined resource product
--is still a leaf: belt = 1.5, never 0.15. Red before the leaf rule (belt read 0.15).
do
    local saved = rawget(_G, "prototypes")
    local function r(ings, prods) return {ingredients = ings, products = prods, category = "crafting"} end
    _G.prototypes = {
        entity = {["b"] = {items_to_place_this = {{name = "b"}}}},
        recipe = {
            b = r({{name = "p", amount = 1}, {name = "g", amount = 1}}, {{name = "b", amount = 2}}),
            g = r({{name = "p", amount = 2}}, {{name = "g", amount = 1}}),
            p = r({{name = "o", amount = 1}}, {{name = "p", amount = 1}}),
            crush = r({{name = "chunk", amount = 1}}, {{name = "o", amount = 20}}),
        },
        tile = {},
        get_entity_filtered = function() return {ore = {mineable_properties = {products = {{name = "o"}}}}} end,
    }
    local c7 = {belt = {belt = "b"}, entity = {}}
    Catalog.fill_material(c7)
    _G.prototypes = saved
    assert(c7.material.b == 1.5, "belt costs " .. tostring(c7.material.b)); print("MC7")
end
H.done("test_material_cost")
