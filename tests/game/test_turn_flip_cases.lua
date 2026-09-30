-- Headless probe. Integrator runs on 2.0 and 2.1; offline registers and checks the data contract only.
local S = require "tests.game.support"
local Generation = require "logic.bp.generation"
local Cases = require "tests.game.lib.turn_flip_cases"
local Settings = require "logic.bp.settings"

local function main_product(recipe)
    local name = recipe.main_product
    for _, product in ipairs(recipe.products or {}) do
        if name and product.name == name then return product end
    end
    return (recipe.products or {})[1]
end
local function fill_target(sheet, product, rate)
    if product.type == "fluid" then
        local row = sheet.input_container.children[1]
        row.rate_textfield.text = string.format("%.17g", rate)
        row.time_unit_dropdown.selected_index = 2
        row.hxrrc_desired_fluid_button.elem_value = product.name
        event_handlers.on_gui_elem_changed[row.hxrrc_desired_fluid_button.name](
            {element = row.hxrrc_desired_fluid_button, player_index = 1})
    else
        S.fill_row(sheet, 1, product.name, rate, "/s")
    end
end
local function run_case(row, n, found, next_case)
    local recipe, machine = prototypes.recipe[row.recipe] or (row.alt and prototypes.recipe[row.alt]), prototypes.entity[row.machine]
    local product = recipe and main_product(recipe)
    --Integrator round 54 (2026-09-30): 2.0+ entity prototypes have get_crafting_speed(quality), no crafting_speed
    --field (headless 2.0.77 + 2.1.20: __index error); same read as logic/catalog.lua:481.
    local crafting_speed = machine and machine.get_crafting_speed and machine.get_crafting_speed("normal")
    if not (recipe and machine and product and crafting_speed) then
        found.absent[#found.absent + 1] = row.machine .. "-" .. row.recipe .. "-" .. n
        next_case()
        return
    end
    local amount = product.amount or ((product.amount_min or 0) + (product.amount_max or 0)) / 2
    local speed = amount * (product.probability or 1) * crafting_speed / (recipe.energy or 1)
    local sheet = S.first_sheet()
    local player_data = storage[1]
    local product_name = product.name
    local product_type = product.type == "fluid" and "fluid/" or "item/"
    --Integrator round 54: undo only the previous case's binding (clearing every module setup left the report unable
    --to build a row: headless 2.0.77 "timed out after 600 ticks: report rows" on the first case).
    if found.bound then
        player_data.recipes_by_product_full_name[found.bound.product] = nil
        player_data.product_full_names_by_recipe_name[found.bound.recipe] = nil
    end
    found.bound = {product = product_type .. product_name, recipe = recipe.name}
    S.bind(product_type .. product_name, recipe.name)
    player_data.identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name] = {name = row.machine, quality = "normal"}
    Settings.store(1, S.sheet_id(sheet), {input_edge = "left", output_edge = "top"})
    fill_target(sheet, product, Cases.target_rate(speed, n))
    S.calculate(sheet)
    local id = row.machine .. "-" .. row.recipe .. "-" .. n
    print("TURN_FLIP start " .. id .. " tick " .. game.tick); log("TURN_FLIP start " .. id .. " tick " .. game.tick)
    --Integrator round 54: report rows left from the previous case satisfy the wait before the new calculation is
    --current (headless 2.0.77: BP_REJ_SOLVER_NOT_OK "no finished calculation" on case 2). Retry that refusal every
    --60 ticks, 20 times; any other failure is recorded under `failed` and the probe moves on.
    local function attempt(left)
        local job_id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(sheet), deliver = false})
        --Integrator round 54: the probe needs only the prepared input, which exists once preparation ends. Take it and
        --cancel the job: headless 2.0.77 EM plant x4 generation ran past the runner's 300 s silence limit, and the
        --offline census judges generation anyway.
        S.wait_until(function()
            return S.generation_state(job_id) ~= "pending" or Generation.capture(1, job_id) ~= nil
        end, 36000, function()
            local state, status = S.generation_state(job_id)
            if state == "pending" then
                found.cases[id] = assert(Generation.capture(1, job_id))
                Generation.cancel(1, job_id)
                print("TURN_FLIP ok " .. id .. " (prepared, cancelled) tick " .. game.tick); log("TURN_FLIP ok " .. id .. " prepared")
                next_case()
                return
            end
            if state == "success" then
                found.cases[id] = assert(Generation.capture(1, job_id))
                print("TURN_FLIP ok " .. id .. " tick " .. game.tick); log("TURN_FLIP ok " .. id)
                next_case()
                return
            end
            local codes = status and status.reason_codes or {}
            if codes[1] == "BP_REJ_SOLVER_NOT_OK" and left > 0 then
                local waited = 0
                S.wait_until(function() waited = waited + 1; return waited >= 60 end, 120, function() attempt(left - 1) end, "retry wait")
                return
            end
            --Integrator round 54: a case today's code cannot lay out (headless 2.0.77: refinery x4 BP_FAIL_NO_LAYOUT)
            --still carries its prepared input; the census turns it into FAIL rows for the fix wave.
            local capture = Generation.capture(1, job_id)
            if capture then found.cases[id] = capture end
            found.failed[#found.failed + 1] = {id = id, state = state, codes = codes, captured = capture ~= nil}
            print("TURN_FLIP failed " .. id .. " " .. tostring(codes[1])); log("TURN_FLIP failed " .. id .. " " .. tostring(codes[1]))
            next_case()
        end, "generation terminal")
    end
    S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function() attempt(20) end, "report rows")
end

describe("Turn Flip cases", function()
    it("writes prepared inputs for every available contract row", function()
        if RRC_OFFLINE then assert.are_equal(9, #Cases.CASES); return end
        log("TURN_FLIP probe begin")
        local found = {version = script.active_mods.base, cases = {}, absent = {}, failed = {}}
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
                found.bound = nil
                helpers.write_file("rrc_turn_flip_cases.json", helpers.table_to_json(found))
            end
        end
        next_case()
    end)
end)
