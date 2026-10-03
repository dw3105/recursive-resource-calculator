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
--MC8 (integrator, round 53, 2026-09-30): the recipe scan runs once per prototypes object, not once per catalog build
--(in-game catalog builds repeat every generation). A new prototypes object scans again.
do
    local saved = rawget(_G, "prototypes")
    local scans = 0
    local function protos()
        return {
            entity = {["b"] = {items_to_place_this = {{name = "b"}}}},
            recipe = {b = {ingredients = {{name = "o", amount = 3}}, products = {{name = "b", amount = 2}}, category = "crafting"}},
            tile = {},
            get_entity_filtered = function() scans = scans + 1; return {ore = {mineable_properties = {products = {{name = "o"}}}}} end,
        }
    end
    _G.prototypes = protos()
    local a, b = {belt = {belt = "b"}, entity = {}}, {belt = {belt = "b"}, entity = {}}
    Catalog.fill_material(a); Catalog.fill_material(b)
    assert(scans == 1 and a.material.b == 1.5 and b.material.b == 1.5, "scans " .. scans)
    _G.prototypes = protos()
    local c = {belt = {belt = "b"}, entity = {}}
    Catalog.fill_material(c)
    _G.prototypes = saved
    assert(scans == 2 and c.material.b == 1.5, "new prototypes scans " .. scans); print("MC8")
end

--MC-BP1..BP5 red on round-55-base (2026-10-03): whole-blueprint costs and version fixture selection are absent.
H.test("MC-BP1 through MC-BP5 whole blueprint material", function()
    local entities = {}
    local counts = {['assembling-machine-3']=17, beacon=68, ['bulk-inserter']=101, ['chemical-plant']=5,
        ['electric-furnace']=8, ['electromagnetic-plant']=14, foundry=13, ['long-handed-inserter']=26,
        ['medium-electric-pole']=31, ['oil-refinery']=1, pipe=116, ['pipe-to-ground']=112, roboport=9,
        ['turbo-splitter']=12, ['turbo-transport-belt']=1303, ['turbo-underground-belt']=86}
    local prices=Cost.parse_fixture(read("tests/fixtures/material_cost_2.0.txt"))
    for name,n in pairs(counts) do for i=1,n do entities[#entities+1]={name=name,flow_id="f"..(i%3)} end end
    local catalog={material=prices}
    local total, unknown=Cost.blueprint(catalog,entities)
    H.equal(math.abs(total-521885.2)<0.1,true,"MC-BP1 blueprint score"); H.equal(unknown,0,"MC-BP1 known names")
    local second={}; for name,n in pairs({['assembling-machine-3']=4,beacon=7,['electromagnetic-plant']=1,['fast-inserter']=33,['fast-splitter']=2,['fast-transport-belt']=234,['fast-underground-belt']=10,foundry=6,['long-handed-inserter']=4,['medium-electric-pole']=21,pipe=12,['pipe-to-ground']=12,roboport=4}) do for i=1,n do second[#second+1]={name=name} end end
    H.equal(math.abs(Cost.blueprint(catalog,second)-59323.7)<0.1,true,"MC-BP1 second score")
    local mix={{name="pipe",flow_id="a"},{name="beacon",flow_id="b"},{name="pipe"}}
    local by=Cost.by_flow(catalog,mix); H.equal(by.a+by.b+prices.pipe,prices.pipe+prices.beacon+prices.pipe,"MC-BP3 by flow shape")
    local with_unknown={{name="unknown"},{name="pipe"}}; local v,u=Cost.blueprint(catalog,with_unknown); H.equal(v,prices.pipe,"MC-BP2 total"); H.equal(u,1,"MC-BP2 unknown")
    local empty_total,empty_unknown=Cost.blueprint({material={}},mix); H.equal(empty_total,nil,"MC-BP4 empty material"); H.equal(empty_unknown,#mix,"MC-BP4 unknown count"); H.equal(Cost.by_flow({material={}},mix),nil,"MC-BP4 by flow")
    local x,y=Cost.blueprint({},mix); H.equal(x,nil,"MC-BP4 missing material"); H.equal(y,#mix,"MC-BP4 missing material unknown count"); H.equal(Cost.by_flow({},mix),nil,"MC-BP4 missing material by flow")
    local source=read("tests/golden/generate.lua"); H.equal(source:find("prepared.version",1,true)~=nil,true,"MC-BP5 uses prepared version"); H.equal(source:find('"/tests/fixtures/material_cost_" .. version .. ".txt"',1,true)~=nil,true,"MC-BP5 selects matching fixture")
    for _,m in ipairs({"MC-BP1","MC-BP2","MC-BP3","MC-BP4","MC-BP5"}) do print(m) end
end)
H.done("test_material_cost")
