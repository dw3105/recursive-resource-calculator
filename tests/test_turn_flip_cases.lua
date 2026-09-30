-- TFC1-TFC4 red on round-54-base (2026-09-30).
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
H.new_world("2.0")
local Cases = require "tests.game.lib.turn_flip_cases"
local function read(path)
    local f = assert(io.open(path, "r")); local s = f:read("*a"); f:close(); return s
end
local expected = {
    {"assembling-machine-1", "electronic-circuit"},
    {"assembling-machine-2", "concrete"},
    {"chemical-plant", "plastic-bar"},
    {"chemical-plant", "sulfuric-acid"},
    {"oil-refinery", "advanced-oil-processing"},
    {"foundry", "casting-iron"},
    {"foundry", "iron-ore-melting"},
    {"electromagnetic-plant", "electrolyte"},
    {"cryogenic-plant", "fluoroketone"},
}
H.test("TFC1 ordered machine recipe rows and sorted ids", function()
    H.equal(#Cases.CASES, #expected)
    for i, row in ipairs(expected) do
        H.equal(row[1], Cases.CASES[i].machine); H.equal(row[2], Cases.CASES[i].recipe)
    end
    local ids = Cases.ids(); H.equal(#ids, 18)  --biochamber dropped (burner), integrator round 54
    for i = 2, #ids do assert(ids[i - 1] < ids[i], "ids sorted") end
    print("TC1")
end)
H.test("TFC2 target rate stays just below machine capacity", function()
    local r = 17.25
    assert(Cases.target_rate(r, 4) < 4 * r); assert(Cases.target_rate(r, 4) > 3.99 * r)
    assert(Cases.target_rate(r, 1) < r); print("TC2")
end)
H.test("TFC3 fixture shape", function()
    local prepared = helpers.json_to_table(read("tests/golden/cases/player-red-science-1s/prepared_input.json"))
    prepared.settings.input_edge, prepared.settings.output_edge = "left", "top"
    local fixture = {version = "2.0", cases = { ["machine-recipe-1"] = prepared }}
    assert(Cases.check_fixture(fixture))
    assert(not Cases.check_fixture({cases = fixture.cases}))
    local no_catalog = helpers.json_to_table(read("tests/golden/cases/player-red-science-1s/prepared_input.json"))
    no_catalog.settings.input_edge, no_catalog.settings.output_edge, no_catalog.catalog = "left", "top", nil
    assert(not Cases.check_fixture({version = "2.0", cases = {x = no_catalog}}))
    local wrong_edges = helpers.json_to_table(read("tests/golden/cases/player-red-science-1s/prepared_input.json"))
    wrong_edges.settings.input_edge, wrong_edges.settings.output_edge = "top", "left"
    assert(not Cases.check_fixture({version = "2.0", cases = {x = wrong_edges}})); print("TC3")
end)
H.test("TFC4 game probe registers offline", function()
    local pipe = assert(io.popen("lua5.2 tests/game/offline.lua tests/game/test_turn_flip_cases.lua 2>&1", "r"))
    local output = pipe:read("*a"); local ok, why, code = pipe:close()
    assert(ok, output .. tostring(why) .. tostring(code)); print("TC4")
end)
H.done("test_turn_flip_cases")
