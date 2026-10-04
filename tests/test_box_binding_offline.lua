-- Must fail on base code: offline catalog binding loader is missing. 2026-10-04
local B = require "logic.bp.box_binding"
local JSON = require "tests.json"
local function read(p) local f=assert(io.open(p)); local s=f:read("*a"); f:close(); return s end
local prep=JSON.decode(read("tests/golden/cases/player-blue-science-10s/prepared_input.json"))
local frozen=JSON.decode(read("tests/fixtures/r56/blue_bound_route.json"))
local a=B.apply_offline(prep,"2.0")
assert(a.catalog.recipe["advanced-oil-processing"].fluid_boxes, "BO1 binding")
local cat={recipe={r={fluid_boxes={m={f={box=9,boxes={9},role="input"}}}}}}
local bound={catalog=cat}; B.apply_offline(bound); assert(cat.recipe.r.fluid_boxes.m.f.box==9,"BO2 untouched")
local b=B.apply_offline({catalog={entity={},recipe={}}},"2.1"); assert(b.catalog,"BO3 2.1")
print("BO1 BO2 BO3")
