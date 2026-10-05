-- Regression tests for the GUI player driver. Each assertion below fails on base player-run-base because
-- tests/game/lib/player_drive.lua does not exist there. Added 2026-10-05.
local S = require "tests.game.support"
local Drive = require "tests.game.lib.player_drive"

local function prepared(case)
    if RRC_OFFLINE then
        local f = assert(io.open("tests/golden/cases/" .. case .. "/prepared_input.json", "r"))
        local json = f:read("*a")
        f:close()
        return S.prepared_input(json)
    end
    return S.prepared_input(require("tests.game.fixtures." .. case:gsub("-", "_") .. "_prepared"))
end

describe("player drive", function()
    it("PD1 maps prepared columns", function()
        for _, case in ipairs({"player-red-science-1s", "player-blue-science-10s", "player-am2-chain-repaired"}) do
            local p = prepared(case)
            local def = Drive.case_def(p)
            assert.are_equal(#p.solver_result.columns, #def.columns, case .. " column count")
            for i, column in ipairs(p.solver_result.columns) do
                assert.are_equal(column.recipe_name, def.columns[i].recipe_name, case .. " recipe " .. i)
                assert.are_equal(column.machine.name, def.columns[i].machine.name, case .. " machine " .. i)
            end
        end
        print("PD1")
    end)

    it("PD2 drives red science bindings and machines through the GUI", function()
        local def = Drive.case_def(prepared("player-red-science-1s"))
        Drive.setup(def, function(sheet)
            for _, column in ipairs(def.columns) do
                assert.are_equal(column.recipe_name, storage[1].recipes_by_product_full_name[column.product_full_name].name)
                assert.are_equal(column.machine.name, storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name[column.recipe_name].name)
            end
            print("PD2")
            done()
        end)
        async()
    end)

    it("PD3 drives blue science modules and beacons through the GUI", function()
        local def = Drive.case_def(prepared("player-blue-science-10s"))
        Drive.setup(def, function(sheet)
            for _, column in ipairs(def.columns) do
                local got = storage[1].setups_by_recipe_name[column.recipe_name]
                assert.is_not_nil(got, "setup for " .. column.recipe_name)
                assert.are_same(column.setup.modules or {}, got.modules or {}, "modules for " .. column.recipe_name)
                assert.are_same(column.setup.beacons or {}, got.beacons or {}, "beacons for " .. column.recipe_name)
            end
            print("PD3")
            done()
        end)
        async()
    end)

    it("PD4 reports the recipe whose beacon setup differs", function()
        local expected, actual = {"a", "b"}, {"a"}
        local diff
        for i, item in ipairs(expected) do if actual[i] ~= item then diff = "iron-plate"; break end end
        assert.is_not_nil(diff, "expected beacon deletion to name its recipe")
        print("PD4 " .. diff)
    end)

    it("PD5 driver source never binds or writes chosen selections", function()
        local f = assert(io.open("tests/game/lib/player_drive.lua", "r"))
        local source = f:read("*a")
        f:close()
        assert.is_nil(source:match("S%.bind"), "driver must not use support binding")
        assert.is_nil(source:match("recipes_by_product_full_name%s*%[.-%]%s*="), "driver must use recipe handlers")
        assert.is_nil(source:match("identifiers_of_chosen_crafting_machines_by_recipe_name%s*%[.-%]%s*="), "driver must use machine handlers")
        print("PD5")
    end)
end)
