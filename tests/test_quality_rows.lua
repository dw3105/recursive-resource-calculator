--Quality effects on ordinary recipe rows: outputs spread over qualities, gross output first, the module's own quality, and consumer checks
local H = require "tests.harness"

local M = {}

--Vanilla quality chain. plate -> 2 cable in a foundry (4 slots, speed 1, 100 kW). Modules: pq quality +0.25 only; q quality +0.25 and speed -0.05
--(legendary: quality +0.62, speed -0.05); s speed +0.25 only.
local function cable_world(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    world.add_item("plate")
    world.add_item("cable")
    world.add_module("pq", "quality", {quality = 0.25})
    world.add_module("q", "quality", {quality = 0.25, speed = -0.05}, {legendary = {quality = 0.62, speed = -0.05}})
    world.add_module("s", "speed", {speed = 0.25})
    world.add_machine({name = "foundry", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4, base_quality = options.base_quality})
    world.add_recipe({name = "cable", category = "crafting", energy = 1, ingredients = {{name = "plate", amount = 1}}, products = {{name = "cable", amount = 2}},
        allowed_effects = options.allowed_effects})
    world.add_player(1)
    world.init()
    if options.lock then world.lock_quality(options.lock) end
    M.QualityId = require "logic.quality_id"
    M.Sheet = require "gui.sheet"
    require "gui.calculator"
    return world
end

local function handler_sheet(targets)
    local sheet_pane, sheet_flow = H.fill_sheet(targets)
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
    return sheet_flow
end

local function recompute(sheet_flow)
    storage.computation_stack = {}
    M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
    return H.parse_report(sheet_flow.output_flow)
end

local function fire(element)
    event_handlers.on_gui_elem_changed[element.name]({element = element, player_index = 1})
end

local function find_all(element, name, found)
    found = found or {}
    for _, child in ipairs(element.children) do
        if child.name == name then found[#found + 1] = child end
        find_all(child, name, found)
    end
    return found
end

local CABLE_TIERS = {uncommon = 0.09, rare = 0.009, epic = 0.0009, legendary = 0.0001} --shares of a craft at 10%

H.test("2.0 QL-15 materials: quality modules on an ordinary row spread its output and raise its crafts", function()
    cable_world("2.0")
    local report = H.run_sheet({{item = "cable", rate = 4000, unit = "/s"}})
    H.near(report.rows["item/cable"].machines, 2000, "no modules: machines")
    H.near(report.rows["item/plate"].rate, 2000, "no modules: plates")
    H.equal(report.rows[M.QualityId.encode("cable", "uncommon")], nil, "no quality rows")

    storage[1].module_setups_by_recipe_name.cable.modules = {{name = "pq"}, {name = "pq"}, {name = "pq"}, {name = "pq"}}
    report = H.run_sheet({{item = "cable", rate = 4000, unit = "/s"}})
    H.near(report.rows["item/cable"].machines, 2000 / 0.9, "crafts per second at 90% normal output")
    H.near(report.rows["item/plate"].rate, 2000 / 0.9, "plates")
    for quality, share in pairs(CABLE_TIERS) do
        local row = report.rows[M.QualityId.encode("cable", quality)]
        H.equal(row.kind, "hxrrc.byproduct", quality .. " cable is a byproduct")
        H.near(row.rate, -(4000 / 0.9) * share, quality .. " cable rate")
    end
end)

H.test("2.0 QL-15 the user's scenario: the same modules at legendary quality change the numbers", function()
    cable_world("2.0")
    local sheet_flow = handler_sheet({{item = "cable", rate = 4000, unit = "/s"}})
    local function slots()
        return find_all(H.parse_report(sheet_flow.output_flow).rows["item/cable"].module_cell, "hxrrc_choose_module_button")
    end
    for index = 1, 4 do
        local slot = slots()[index]
        H.pick_module(slot, {name = "q"})
    end
    local report = recompute(sheet_flow)
    H.near_relative(report.rows["item/cable"].machines, 25000 / 9, "normal modules: 2000 / (0.9 x 0.8)")
    for index = 1, 4 do
        local slot = slots()[index]
        H.pick_module(slot, {name = "q", quality = "legendary"})
    end
    report = recompute(sheet_flow)
    H.near_relative(report.rows["item/cable"].machines, 2000 / (0.752 * 0.8), "legendary modules: 24.8% upgrade chance")
    H.near_relative(report.rows["item/plate"].rate, 2000 / 0.752, "plates at legendary modules")
    local caption
    local function labels(element)
        for _, child in ipairs(element.children) do
            if child.type == "label" and type(child.caption) == "table" and child.caption[2] and child.caption[2][1] == "hxrrc.quality" then caption = child.caption[4] end
            labels(child)
        end
    end
    labels(report.rows["item/cable"].module_cell)
    H.equal(caption, "+24.80%", "the label the user saw")
end)

H.test("2.0 QL-15 a recipe forbidding quality refuses quality modules; its machine's own quality is ignored while speed still counts", function()
    cable_world("2.0", {allowed_effects = {"consumption", "speed", "productivity", "pollution"}})
    local sheet_flow = handler_sheet({{item = "cable", rate = 4000, unit = "/s"}})
    local cell = H.parse_report(sheet_flow.output_flow).rows["item/cable"].module_cell
    local slot = find_all(cell, "hxrrc_choose_module_button")[1]
    assert(slot, "a slot for the allowed speed module")
    H.errors(function() H.pick_module(slot, {name = "q"}) end, "the picker does not offer module q", "q not offered")
    require("gui.module_picker").close(1, false)
    H.equal(#storage[1].module_setups_by_recipe_name.cable.modules, 0, "q not kept")
    local report = recompute(sheet_flow)
    H.near(report.rows["item/cable"].machines, 2000, "no spread, no speed penalty")

    cable_world("2.0", {allowed_effects = {"consumption", "speed", "productivity", "pollution"}, base_quality = 1})
    storage[1].module_setups_by_recipe_name.cable.modules = {{name = "s"}, {name = "s"}, {name = "s"}, {name = "s"}}
    report = H.run_sheet({{item = "cable", rate = 4000, unit = "/s"}})
    H.near(report.rows["item/cable"].machines, 1000, "forbidding recipe: no spread, double speed")
    H.equal(report.rows[M.QualityId.encode("cable", "uncommon")], nil, "no quality rows")

    cable_world("2.0", {base_quality = 1})
    storage[1].module_setups_by_recipe_name.cable.modules = {{name = "s"}, {name = "s"}, {name = "s"}, {name = "s"}}
    report = H.run_sheet({{item = "cable", rate = 4000, unit = "/s"}})
    H.near(report.rows["item/cable"].machines, (2000 / 0.9) / 2, "allowing recipe: machine quality 10%, double speed")
end)

H.test("2.0 QL-15 a locked quality stops the spread", function()
    cable_world("2.0", {lock = "rare"})
    storage[1].module_setups_by_recipe_name.cable.modules = {{name = "pq"}, {name = "pq"}, {name = "pq"}, {name = "pq"}}
    local report = H.run_sheet({{item = "cable", rate = 4000, unit = "/s"}})
    H.near(report.rows[M.QualityId.encode("cable", "uncommon")].rate, -(4000 / 0.9) * 0.1, "uncommon keeps the rest")
    H.equal(report.rows[M.QualityId.encode("cable", "rare")], nil, "nothing at rare")
end)

H.test("2.1 QL-16 quality modules on an ordinary row change nothing in Factorio 2.1", function()
    cable_world("2.1")
    storage[1].module_setups_by_recipe_name.cable.modules = {{name = "pq"}, {name = "pq"}, {name = "pq"}, {name = "pq"}}
    local report = H.run_sheet({{item = "cable", rate = 4000, unit = "/s"}})
    H.near(report.rows["item/cable"].machines, 2000, "round 4 numbers")
    H.equal(report.rows[M.QualityId.encode("cable", "uncommon")], nil, "no quality rows")
end)

--One machine with base quality (optionally) in category "loop"; recipe self: 1 X -> amount X
local function catalyst_world(amount, base_quality)
    local world = H.new_world("2.0")
    world.add_item("X")
    world.add_machine({name = "quality-machine", categories = {"loop"}, speed = 1, module_slots = 0, base_quality = base_quality})
    world.add_recipe({name = "self", category = "loop", ingredients = {{name = "X", amount = 1}}, products = {{name = "X", amount = amount}}})
    world.add_player(1)
    world.init()
    return world
end

H.test("2.0 QL-15b catalysts: gross output is spread before the ingredients are taken", function()
    catalyst_world(1, 1)
    local Solver, QualityId = require "logic.solver", require "logic.quality_id"
    local recipe = prototypes.recipe.self
    H.near(Solver.net_amount_of(recipe, "item/X", 1), -0.1, "1 X -> 1 X: normal net")
    local expected = {uncommon = 0.09, rare = 0.009, epic = 0.0009, legendary = 0.0001}
    for quality, amount in pairs(expected) do
        H.near(Solver.net_amount_of(recipe, QualityId.encode("X", quality), 1), amount, "1 X -> 1 X: " .. quality)
    end

    catalyst_world(2, 6)
    Solver, QualityId = require "logic.solver", require "logic.quality_id"
    recipe = prototypes.recipe.self
    H.near(Solver.net_amount_of(recipe, "item/X", 1), 2 * 0.4 - 1, "1 X -> 2 X: normal net -0.2")
    expected = {uncommon = 1.08, rare = 0.108, epic = 0.0108, legendary = 0.0012}
    for quality, amount in pairs(expected) do
        H.near(Solver.net_amount_of(recipe, QualityId.encode("X", quality), 1), amount, "1 X -> 2 X: " .. quality)
    end
    local report = H.run_sheet({{item = "X", rate = 1, unit = "/s"}})
    H.equal(report.energy_caption, "hxrrc.totals_unavailable", "no totals")
    H.equal(report.rows["item/X"].reason, "hxrrc.recipe_runs_backwards", "the producer runs backwards")
    local result = Solver.solve_for({["item/X"] = 1}, 1)
    H.equal(result.status, "infeasible", "infeasible")
    H.near(result.recipe_rates.self, -5, "rate -5")
end)

H.test("2.0 QL-17 a recipe returning what it takes consumes only through its upgrades, and stops when the quality effect goes", function()
    local world = H.new_world("2.0")
    world.add_item("ore")
    world.add_item("X")
    world.add_item("Y")
    world.add_machine({name = "quality-machine", categories = {"loop"}, speed = 1, module_slots = 0, base_quality = 1})
    world.add_machine({name = "plain-machine", categories = {"loop"}, speed = 1, module_slots = 0})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, module_slots = 0})
    world.add_recipe({name = "YX", category = "crafting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "Y", amount = 1}, {name = "X", amount = 1}}})
    world.add_recipe({name = "self", category = "loop", ingredients = {{name = "X", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_player(1)
    world.init()
    world.bind("item/Y", "YX")
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.self = {name = "quality-machine"}
    M.QualityId = require "logic.quality_id"
    M.Sheet = require "gui.sheet"
    require "gui.calculator"

    local sheet_flow = handler_sheet({{item = "Y", rate = 1, unit = "/s"}})
    local report = H.parse_report(sheet_flow.output_flow)
    local picker = report.rows["item/X"].recipe_button
    H.equal(picker.tags.consumer, true, "consumer picker on the excess row")
    picker.elem_value = "self"
    fire(picker)
    H.equal(storage[1].consumer_product_full_names["item/X"], true, "accepted and flagged")
    report = recompute(sheet_flow)
    --X excess 1/s is consumed at -0.1 per craft: 10 crafts, upgrading 0.9 X to uncommon and so on
    H.near(report.rows["item/X"].rate, -1, "normal X consumed")
    H.near(report.rows[M.QualityId.encode("X", "uncommon")].rate, -0.9, "uncommon X made")

    local machine_button = report.rows["item/X"].machine_button
    machine_button.elem_value = {name = "plain-machine"}
    fire(machine_button)
    report = recompute(sheet_flow)
    H.equal(report.rows["item/X"].reason, "hxrrc.consumer_no_longer_consumes", "no quality effect: no longer consumes")
    machine_button = report.rows["item/X"].machine_button
    assert(machine_button, "machine editor on the diagnostic row")
    machine_button.elem_value = {name = "quality-machine"}
    fire(machine_button)
    report = recompute(sheet_flow)
    H.near(report.rows["item/X"].rate, -1, "consumes again")
end)

H.done("test_quality_rows")
