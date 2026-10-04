-- Must fail on base code: offline catalog binding loader is missing. 2026-10-04
local B = require "logic.bp.box_binding"
require("tests.harness").new_world("2.0")
local function read(p) local f=assert(io.open(p)); local s=f:read("*a"); f:close(); return s end
local prep=assert(helpers.json_to_table(read("tests/golden/cases/player-blue-science-10s/prepared_input.json")))
local frozen=assert(helpers.json_to_table(read("tests/fixtures/r56/blue_bound_route.json")))
local a=B.apply_offline(prep,"2.0")
local found=0
for recipe, r in pairs(a.catalog.recipe) do
    for machine, fluids in pairs(r.fluid_boxes or {}) do
        local expected=frozen.catalog.recipe[recipe] and frozen.catalog.recipe[recipe].fluid_boxes and frozen.catalog.recipe[recipe].fluid_boxes[machine]
        if expected then
            for fluid, entry in pairs(fluids) do
                local other=expected[fluid]
                assert(other and entry.box==other.box and entry.role==other.role and #entry.boxes==#other.boxes,"BO1 "..recipe.." "..machine.." "..fluid)
                for i, box in ipairs(entry.boxes) do assert(box==other.boxes[i],"BO1 boxes") end
                found=found+1
            end
        end
    end
end
assert(found>0,"BO1 matching measured bindings")
print("BO1")
local cat={entity={["oil-refinery"]={}},recipe={ ["simple-coal-liquefaction"]={fluid_boxes={ ["oil-refinery"]={water={box=9,boxes={9},role="input"}}}}}}
local bound={catalog=cat}; B.apply_offline(bound); assert(cat.recipe["simple-coal-liquefaction"].fluid_boxes["oil-refinery"].water.box==9 and not cat.recipe["simple-coal-liquefaction"].fluid_boxes["oil-refinery"]["heavy-oil"],"BO2 untouched")
print("BO2")
local catalog21={entity={ ["oil-refinery"]={} },recipe={ ["simple-coal-liquefaction"]={} }}
local b=B.apply_offline({catalog=catalog21},"2.1")
local e=b.catalog.recipe["simple-coal-liquefaction"].fluid_boxes["oil-refinery"]["heavy-oil"]
assert(e and #e.boxes==1 and e.boxes[1]==3,"BO3 2.1 fixture binding")
print("BO3")
print("test_box_binding_offline: 3 cases, 3 passed, 0 failed")
