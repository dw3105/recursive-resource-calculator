local snapshot = {sheet_id = "sheet", state = "current", targets = {{full_name = "item/iron-gear-wheel", quality = "normal", rate_per_second = 1}}, selection = {{recipe_name = "iron-gear-wheel", machine = {name = "assembling-machine-2", quality = "normal"}, modules = {}, beacons = {}}}}
local column = {recipe_name = "iron-gear-wheel", machine = {name = "assembling-machine-2"}, rate = 1, recipe = {name = "iron-gear-wheel", ingredients = {{type = "item", name = "iron-plate", amount = 2}}, products = {{type = "item", name = "iron-gear-wheel", amount = 1}}}}
local catalog = {entity = { ["assembling-machine-2"] = {name = "assembling-machine-2", type = "assembling-machine", module_slots = 2, energy_source_type = "electric", effect_receiver = {status = "verified_default", source = "prototype", branch = "2.0", base_effect = {}, uses_module_effects = true, uses_beacon_effects = true, uses_surface_effects = true}}}, item = { ["iron-plate"] = {name = "iron-plate", type = "item"}}, module = {}, quality = {normal = {unlocked = true}}}
local result = {status = "ok", columns = {column}, recipe_rates = { ["iron-gear-wheel"] = 1}}
local options = {input_edge = "left", output_edge = "right"}
return {id = "T-280-82", rule = "BP_REJ_BURNER_MACHINE", class = "engine", from = "tests/test_bp_preflight.lua twin fixture",
    stage = "preflight", grid = {w = 1, h = 1}, entities = {},
    preflight = {snapshot = snapshot, solver_result = result, catalog = catalog, options = options},
    subject = {kind = "entity", name = "stone-furnace"}, check = "prototype", truth = "ok", codes = {}, audit = {}}
