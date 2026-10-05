-- Regression tests for the GUI player driver. These fail on player-run-base because Drive.compare is absent.
-- Added 2026-10-05.
local S = require "tests.game.support"
local Drive = require "tests.game.lib.player_drive"
local prepared_fixtures = {}
for _, case in ipairs({"player-red-science-1s", "player-blue-science-10s", "player-am2-chain-repaired"}) do
    local module = "tests.game.fixtures." .. case:gsub("-", "_") .. "_prepared"
    local ok, fixture = pcall(require, module)
    if ok then prepared_fixtures[case] = fixture end
end

local function prepared(case)
    if RRC_OFFLINE then
        local f = assert(io.open("tests/golden/cases/" .. case .. "/prepared_input.json", "r"))
        local json = f:read("*a"); f:close()
        return S.prepared_input(json)
    end
    assert(prepared_fixtures[case], "missing staged prepared fixture for " .. case)
    return S.prepared_input(prepared_fixtures[case])
end

local function synthetic(beacon)
    local setup = {modules = {{name = "speed-module", quality = "normal"}, {name = "speed-module", quality = "normal"}}}
    if beacon then setup.beacons = {{name = "beacon", count = 2, modules = {
        {name = "speed-module", quality = "normal"}, {name = "speed-module", quality = "normal"}}}} end
    local columns = {
        {product_full_name = "item/automation-science-pack", recipe_name = "automation-science-pack", machine = {name = "assembling-machine-2", quality = "normal"}, setup = setup},
        {product_full_name = "item/iron-gear-wheel", recipe_name = "iron-gear-wheel", machine = {name = "assembling-machine-2", quality = "normal"}, setup = {modules = {{}, {}}}},
    }
    return {targets = {{full_name = "item/automation-science-pack", rate_per_second = 1, quality = "normal", type = "item"}},
        columns = columns, settings = {}, options = {}, edges = {input = "left", output = "top"}, force = {}, qualities = {}}
end

describe("player drive", function()
    it("PD1 maps prepared columns", function()
        for _, case in ipairs({"player-red-science-1s", "player-blue-science-10s", "player-am2-chain-repaired"}) do
            local p, def = prepared(case), nil
            def = Drive.case_def(p)
            assert.are_equal(#p.solver_result.columns, #def.columns, case .. " column count")
            for i, column in ipairs(p.solver_result.columns) do
                assert.are_equal(column.recipe_name, def.columns[i].recipe_name, case .. " recipe " .. i)
                assert.are_equal(column.machine.name, def.columns[i].machine.name, case .. " machine " .. i)
                assert.are_same(column.setup or {}, def.columns[i].setup, case .. " setup " .. i)
                assert.are_same((column.setup or {}).beacons or {}, def.columns[i].setup.beacons or {}, case .. " beacons " .. i)
            end
        end
        print("PD1")
    end)
    it("PD2 drives recipes, machines, and modules through GUI handlers", function()
        local def = synthetic(false)
        for _, c in ipairs(def.columns) do c.setup.modules = {} end
        Drive.setup(def, function() assert.are_same({}, Drive.compare(def)); print("PD2"); done() end)
        async()
    end)
    it("PD3 drives modules and beacon setup through GUI handlers", function()
        local def = synthetic(true)
        Drive.setup(def, function() assert.are_same({}, Drive.compare(def)); print("PD3"); done() end)
        async()
    end)
    it("PD4 identifies an omitted beacon by recipe", function()
        local def = synthetic(true)
        local wanted = def.columns[1].recipe_name
        def.columns[1].setup.beacons = {}
        Drive.setup(def, function()
            -- Run a second intended definition against the same storage state.
            local expected = synthetic(true)
            local diffs = Drive.compare(expected)
            local found = false
            for _, diff in ipairs(diffs) do if diff:find(wanted, 1, true) and diff:find("beacon", 1, true) then found = true end end
            assert.is_true(found, table.concat(diffs, "\n")); print("PD4"); done()
        end)
        async()
    end)
    it("PD5 driver source never binds or writes chosen selections", function()
        --A source scan: the offline run (tests/game/offline.lua) reads the file; the engine sandbox has no io (suite
        --2026-10-05: "attempt to index global 'io'"), so in game this static check has nothing to read.
        if type(io) ~= "table" then print("PD5 offline only"); return end
        local f = assert(io.open("tests/game/lib/player_drive.lua", "r")); local source = f:read("*a"); f:close()
        assert.is_nil(source:match("S%.bind"))
        assert.is_nil(source:match("recipes_by_product_full_name%s*%[.-%]%s*="))
        assert.is_nil(source:match("identifiers_of_chosen_crafting_machines_by_recipe_name%s*%[.-%]%s*="))
        print("PD5")
    end)
end)
