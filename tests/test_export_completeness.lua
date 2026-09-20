--Contract tests for the replay facts in a debug export.  The Python comparator is deliberately invoked from this
--top-level Lua entry point because tests/run.sh does not discover files below tests/export_golden.
local H = require "tests.harness"
local ExportPayload
local Snapshot
local Catalog

local EXPECTED = "tests/export_golden/expected.json"
local COMPARATOR = "tests/export_golden/compare.py"
local FIXTURE = "tests/export_golden/fixture.json"

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command_status(command)
    local pipe = assert(io.popen(command .. " 2>&1", "r"))
    local output = pipe:read("*a")
    local a, b, c = pipe:close()
    local ok = (type(a) == "number" and a == 0) or (a == true and (c == nil or c == 0))
    return ok, output
end

local function compare_encoded(encoded)
    local path = os.tmpname()
    local file = assert(io.open(path, "wb"))
    file:write(encoded)
    file:close()
    local ok, output = command_status("python3 " .. quote(COMPARATOR) .. " " .. quote(path) .. " " .. quote(EXPECTED))
    os.remove(path)
    return ok, output
end

local function comparator_self_test(argument)
    local command = "python3 " .. quote(COMPARATOR)
    if argument then command = command .. " " .. argument end
    return command_status(command)
end

local function world_with_selection()
    local world = H.new_world("2.0")
    ExportPayload = require "logic.export_payload"
    Snapshot = require "logic.snapshot"
    Catalog = require "logic.catalog"
    world.add_item("ore")
    world.add_item("plate")
    world.add_item("gear")
    world.add_module("speed-module", "speed", {speed = 0.125}, {rare = {speed = 0.25}})
    world.add_module("productivity-module", "productivity", {productivity = 0.10}, {rare = {productivity = 0.20}})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1.5, energy_kw = 210})
    world.add_machine({name = "assembler-alt", categories = {"crafting"}, speed = 2, energy_kw = 300})
    world.add_beacon({name = "beacon", module_slots = 2, energy_kw = 480, distribution_effectivity = 1.5})
    world.add_recipe({name = "plate", category = "crafting", energy = 2.75,
        ingredients = {{name = "ore", amount = 2}}, products = {{name = "plate", amount = 1}}})
    world.add_recipe({name = "gear", category = "crafting", energy = 1.5,
        ingredients = {{name = "plate", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.add_player(2)
    world.init()
    world.bind("item/plate", "plate", 1)
    --The harness auto-binds unique recipes; this fixture intentionally keeps the second recipe unselected until a
    --two-sheet case opts into it, so the golden expectation has one row.
    storage[1].recipes_by_product_full_name["item/gear"] = nil
    storage[1].product_full_names_by_recipe_name.gear = nil
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.plate = {name = "assembler", quality = "rare"}
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler-alt", quality = "normal"}
    storage[1].module_setups_by_recipe_name.plate = {
        modules = {{name = "speed-module", quality = "rare"}, {name = "speed-module", quality = "rare"}},
        beacons = {{name = "beacon", quality = "rare", count = 2, sharing = 3,
            modules = {{name = "speed-module", quality = "rare"}, {name = "speed-module", quality = "rare"}}}},
    }
    storage[1].module_setups_by_recipe_name.gear = {
        modules = {{name = "productivity-module", quality = "normal"}}, beacons = {},
    }
    return world
end

local function make_sheet(targets, player_index)
    local _, sheet = H.fill_sheet(targets, player_index or 1)
    storage[player_index or 1].config_revision = 9
    storage[player_index or 1].sheet_revision = {[sheet.tags.hxrrc_sheet_id] = 4}
    if targets[1] and targets[1].round_up then
        require("gui.sheet").round_up_checkbox_of(sheet).state = true
    end
    return sheet
end

local function result_for(snapshot, status)
    status = status or "ok"
    return {
        status = status or "ok", settings = snapshot, round_up = true,
        columns = {
            {recipe_name = "plate", product_full_name = "item/plate", binding_full_name = "item/plate",
                machine = {name = "assembler", quality = "rare"},
                modules = {{name = "speed-module", quality = "rare", count = 2}},
                beacons = {{name = "beacon", quality = "rare", count = 1, sharing = 2,
                    modules = {{name = "speed-module", quality = "rare", count = 2}}}},
                machine_count = 3.141592653589793, effects = {speed = 0.125},
                energy = 123456.78901234567, pollution = 0.00012345678901234567,
                net_amounts = {["item/plate"] = 1, ["item/ore"] = -2}},
        },
        recipe_rates = status == "ok" and {plate = 1.2345678901234567} or nil,
        solved_rates = status == "ok" and {["item/plate"] = 1.2345678901234567} or nil,
        external_rates = status == "ok" and {["item/ore"] = 2.4691357802469134} or nil,
        reasons_by_column = status == "ok" and {} or {plate = "no_rate"},
        product_parts = {},
    }
end

local function remember(sheet, result, tick)
    local snapshot = Snapshot.of_sheet(sheet)
    storage[1].last_calculation = {sheet_id = snapshot.sheet_id, result = result or result_for(snapshot),
        settings = snapshot, calculation_tick = tick or 17}
    return snapshot
end

local function build(sheet, player_index)
    local payload, state = ExportPayload.build(player_index or 1, sheet)
    H.equal(type(payload), "table", "export payload exists")
    H.equal(type(state), "string", "export state exists")
    return payload, state
end

local function selected(payload, index)
    local entries = payload.sheet.selection
    H.equal(type(entries), "table", "selection table")
    return entries[index]
end

local function base_case()
    local world = world_with_selection()
    local sheet = make_sheet({{item = "plate", rate = 15, unit = "/m", round_up = true}})
    local snapshot = remember(sheet)
    return world, sheet, snapshot
end

H.test("EC1 every selected recipe's prototype facts reach the payload: ingredients, products, crafting time", function()
    local _, sheet = base_case()
    local payload = build(sheet)
    local ok, output = compare_encoded(assert(ExportPayload.encode(payload)))
    H.equal(ok, true, "hand-authored export comparator accepts the complete recipe export: " .. output)
    H.equal(payload.prototypes.recipe.plate.ingredients[1].name, "ore", "recipe ingredient")
    H.equal(payload.prototypes.recipe.plate.products[1].name, "plate", "recipe product")
    H.near(payload.prototypes.recipe.plate.energy, 2.75, "recipe crafting time")
end)

H.test("EC2 deleting the recipe forwarding makes EC1 fail; the recipe map is never silently empty", function()
    local _, sheet = base_case()
    local original = Catalog.for_export
    Catalog.for_export = function(player_index, references)
        references.recipes = nil
        return original(player_index, references)
    end
    local payload = build(sheet)
    Catalog.for_export = original
    local ok = compare_encoded(assert(ExportPayload.encode(payload)))
    H.equal(ok, false, "removing recipe forwarding makes the semantic comparison fail")
    H.equal(next(payload.prototypes.recipe), nil, "the killed recipe forwarding produces an empty map that EC1 rejects")
end)

H.test("EC3 selections survive: machine and recipe identity, quality, and the product-to-recipe binding, per row", function()
    local _, sheet = base_case()
    local payload = build(sheet)
    local entry = selected(payload, 1)
    H.equal(entry.recipe_name, "plate", "recipe identity")
    H.equal(entry.product_full_name, "item/plate", "product binding")
    H.equal(entry.machine.name, "assembler", "machine identity")
    H.equal(entry.machine.quality, "rare", "machine quality")
end)

H.test("EC4 module names, qualities and counts survive, including two rows with different setups", function()
    local world, sheet = base_case()
    local payload = build(sheet)
    local entry = selected(payload, 1)
    H.equal(entry.modules[1].name, "speed-module", "first module name")
    H.equal(entry.modules[1].quality, "rare", "first module quality")
    H.equal(entry.modules[1].count, 2, "first module count")
    local second_sheet = make_sheet({{item = "gear", rate = 1, unit = "/s"}})
    world.bind("item/gear", "gear", 1)
    local second_snapshot = Snapshot.of_sheet(second_sheet)
    storage[1].last_calculation = {sheet_id = second_snapshot.sheet_id, result = result_for(second_snapshot), settings = second_snapshot}
    local second = build(second_sheet)
    H.equal(selected(second, 1).modules[1].name, "productivity-module", "second row setup is local")
    H.equal(selected(second, 1).modules[1].count, 1, "second row module count")
end)

H.test("EC5 beacon prototype, quality, count, sharing and installed modules survive", function()
    local _, sheet = base_case()
    local beacon = selected(build(sheet), 1).beacons[1]
    H.equal(beacon ~= nil, true, "beacon selection exists")
    if not beacon then return end
    H.equal(beacon.name, "beacon", "beacon prototype")
    H.equal(beacon.quality, "rare", "beacon quality")
    H.equal(beacon.count, 2, "beacon count")
    H.equal(beacon.sharing, 3, "beacon sharing")
    H.equal(beacon.modules[1].name, "speed-module", "beacon module")
    H.equal(beacon.modules[1].count, 2, "beacon module count")
end)

H.test("EC6 an explicitly empty module or beacon selection stays explicitly empty, never dropped and never absent", function()
    local _, sheet = base_case()
    storage[1].module_setups_by_recipe_name.plate = {modules = {}, beacons = {}}
    local entry = selected(build(sheet), 1)
    H.equal(entry.modules.rrc_empty_list, true, "empty modules are explicit")
    H.equal(entry.beacons.rrc_empty_list, true, "empty beacons are explicit")
    H.equal(entry.modules == nil or entry.beacons == nil, false, "empty selections are not absent")
end)

H.test("EC7 calculated machine counts, effects, energy and pollution reach the payload at full precision", function()
    local _, sheet = base_case()
    local payload = build(sheet)
    local column = payload.calculation.columns[1]
    H.near_relative(column.machine_count, 3.141592653589793, "machine count precision")
    H.near_relative(column.effects.speed, 0.125, "effects precision")
    H.near_relative(column.energy, 123456.78901234567, "energy precision")
    H.near_relative(column.pollution, 0.00012345678901234567, "pollution precision")
    H.equal(type(payload.calculation.external_rates), "table", "external rates exist")
    if type(payload.calculation.external_rates) ~= "table" then return end
    H.near_relative(payload.calculation.external_rates["item/ore"], 2.4691357802469134, "external rate precision")
end)

H.test("EC8 current against calculated settings carry their sheet and revision identities, and a stale result is named stale rather than blended into current", function()
    local _, sheet = base_case()
    local current = build(sheet)
    H.equal(current.settings.current.sheet_id, current.sheet.sheet_id, "current sheet identity")
    if type(current.settings.current) ~= "table" then return end
    H.equal(current.settings.current.revisions.sheet, 4, "current sheet revision")
    H.equal(current.settings.result.sheet_id, current.sheet.sheet_id, "calculated sheet identity")
    H.equal(current.settings.result.revisions.sheet, 4, "calculated sheet revision")
    sheet.input_container.children[1].rate_textfield.text = "16"
    local stale, state = build(sheet)
    H.equal(state, "stale", "stale state")
    H.equal(stale.state, "stale", "stale payload state")
    H.equal(stale.settings.current.fingerprint == stale.settings.result.fingerprint, false, "stale fingerprints are not blended")
end)

H.test("EC9 a fact the runtime could not supply is an explicit named diagnostic", function()
    local _, sheet = base_case()
    local payload = build(sheet)
    H.equal(type(payload.diagnostics.missing_facts), "table", "missing facts are named")
    if type(payload.diagnostics.missing_facts) ~= "table" then return end
    H.equal(payload.diagnostics.missing_facts[1].fact ~= nil, true, "missing fact has a name")
end)

H.test("EC10 no-result, current, stale and failed states each export honestly", function()
    local _, sheet = base_case()
    storage[1].last_calculation = nil
    local no_result, no_state = build(sheet)
    H.equal(no_state, "not_computed", "no result state")
    H.equal(no_result.calculation.status, "not_computed", "no result calculation")
    remember(sheet)
    local _, current_state = build(sheet)
    H.equal(current_state, "current", "current state")
    sheet.input_container.children[1].rate_textfield.text = "16"
    local _, stale_state = build(sheet)
    H.equal(stale_state, "stale", "stale state")
    local failed_snapshot = Snapshot.of_sheet(sheet)
    storage[1].last_calculation = {sheet_id = failed_snapshot.sheet_id, result = result_for(failed_snapshot, "failed"), settings = failed_snapshot}
    local failed, failed_state = build(sheet)
    H.equal(failed_state, "failed", "failed state")
    H.equal(failed.calculation.status, "failed", "failed calculation")
end)

H.test("EC11 two distinct sheets never borrow each other's selections or results", function()
    local world = world_with_selection()
    local first = make_sheet({{item = "plate", rate = 1, unit = "/s"}})
    local first_snapshot = remember(first)
    local first_payload = build(first)
    local second = make_sheet({{item = "gear", rate = 2, unit = "/s"}}, 2)
    world.bind("item/gear", "gear", 2)
    storage[2].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler-alt", quality = "normal"}
    storage[2].module_setups_by_recipe_name.gear = {modules = {}, beacons = {}}
    local second_snapshot = Snapshot.of_sheet(second)
    storage[2].last_calculation = {sheet_id = second_snapshot.sheet_id, result = result_for(second_snapshot), settings = second_snapshot}
    local second_payload = build(second, 2)
    H.equal(first_payload.sheet.sheet_id ~= second_payload.sheet.sheet_id, true, "distinct sheet identities")
    H.equal(first_payload.settings.result.sheet_id, first_snapshot.sheet_id, "first result stays on first sheet")
    H.equal(second_payload.settings.result.sheet_id, second_snapshot.sheet_id, "second result stays on second sheet")
    if type(second_payload.settings.result) ~= "table" then return end
    H.equal(selected(first_payload, 1).recipe_name, "plate", "first selection")
    H.equal(selected(second_payload, 1).recipe_name, "gear", "second selection")
end)

H.test("EC12 with no attempt available, the payload carries the explicit absent marker, never a fabricated section", function()
    local _, sheet = base_case()
    local payload = build(sheet)
    H.equal(type(payload.generation), "table", "generation attempt section exists")
    if type(payload.generation) ~= "table" then return end
    H.equal(payload.generation.status, "absent", "attempt is explicitly absent")
    H.equal(payload.generation.missing[1], "generation_attempt", "absent attempt is named")
    H.equal(payload.diagnostics.last_blueprint_attempt, nil, "dead attempt field is removed")
end)

H.test("comparator fixture and positive comparison are reached by the entry point", function()
    local fixture = assert(io.open(FIXTURE, "rb")); fixture:close()
    local comparator = assert(io.open(COMPARATOR, "rb")); comparator:close()
    local expected = assert(io.open(EXPECTED, "rb")); expected:close()
    local ok, output = comparator_self_test("--self-test")
    H.equal(ok, true, "comparator self-test: " .. output)
end)

local negative_names = {
    "NEG1 recipe ingredients", "NEG2 recipe products", "NEG3 recipe crafting time", "NEG4 machine identity",
    "NEG5 machine quality", "NEG6 module name", "NEG7 module quality", "NEG8 module count",
    "NEG9 beacon prototype", "NEG10 beacon quality", "NEG11 beacon count", "NEG12 beacon sharing",
    "NEG13 beacon modules", "NEG14 target unit", "NEG15 solved rate", "NEG16 external rate",
    "NEG17 machine count", "NEG18 effects", "NEG19 energy", "NEG20 pollution", "NEG21 round up",
    "NEG22 revision", "NEG23 absent attempt",
}
for index, name in ipairs(negative_names) do
    H.test(name .. " removing or altering only that semantic field fails", function()
        local ok, output = comparator_self_test("--negative " .. tostring(index))
        H.equal(ok, true, "negative control was executed: " .. output)
    end)
end

H.done("test_export_completeness")
