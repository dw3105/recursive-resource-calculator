-- Headless probe. Integrator runs on 2.0 and 2.1; offline registers and checks the data contract only.
local S = require "tests.game.support"
local Generation = require "logic.bp.generation"
local Cases = require "tests.game.lib.turn_flip_cases"
local Settings = require "logic.bp.settings"

local function version() return (script.active_mods.base or "2.0"):match("^(%d+%.%d+)") end
local function main_product(recipe) return (recipe.products or {})[1] end
local function run_case(row, n, found, next_case)
    local recipe, machine = prototypes.recipe[row.recipe], prototypes.entity[row.machine]
    local product = recipe and main_product(recipe)
    if not (recipe and machine and product and machine.crafting_speed) then
        found.absent[#found.absent + 1] = row.machine .. "-" .. row.recipe .. "-" .. n
        next_case()
        return
    end
    local speed = product.amount * machine.crafting_speed / (recipe.energy or 1)
    local sheet = S.first_sheet()
    local player_data = storage[1]
    local product_name = product.name
    local product_type = product.type == "fluid" and "fluid/" or "item/"
    for key in pairs(player_data.recipes_by_product_full_name) do player_data.recipes_by_product_full_name[key] = nil end
    for key in pairs(player_data.product_full_names_by_recipe_name) do player_data.product_full_names_by_recipe_name[key] = nil end
    for key in pairs(player_data.module_setups_by_recipe_name) do player_data.module_setups_by_recipe_name[key] = nil end
    S.bind(product_type .. product_name, row.recipe)
    player_data.identifiers_of_chosen_crafting_machines_by_recipe_name[row.recipe] = {name = row.machine, quality = "normal"}
    Settings.store(1, S.sheet_id(sheet), {input_edge = "left", output_edge = "top"})
    S.fill_row(sheet, 1, product_name, Cases.target_rate(speed, n), "/s")
    S.calculate(sheet)
    S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(sheet), deliver = false})
        S.wait_until(function() return S.generation_state(job_id) ~= "pending" end, 36000, function()
            local state, status = S.generation_state(job_id)
            assert.are_equal("success", state, "generation " .. row.recipe .. ": " .. serpent.line(status, {maxlevel = 3}))
            local capture = assert(Generation.capture(1, job_id))
            found.cases[row.machine .. "-" .. row.recipe .. "-" .. n] = capture
            next_case()
        end, "generation terminal")
    end, "report rows")
end

describe("Turn Flip cases", function()
    it("writes prepared inputs for every available contract row", function()
        if RRC_OFFLINE then assert.are_equal(10, #Cases.CASES); return end
        local found = {version = version(), cases = {}, absent = {}}
        local work = {}
        for _, row in ipairs(Cases.CASES) do
            for _, n in ipairs({1, 4}) do work[#work + 1] = {row = row, n = n} end
        end
        local index = 0
        local function next_case()
            index = index + 1
            local entry = work[index]
            if entry then
                run_case(entry.row, entry.n, found, next_case)
            else
                helpers.write_file("rrc_turn_flip_cases.json", helpers.table_to_json(found))
            end
        end
        next_case()
    end)
end)
