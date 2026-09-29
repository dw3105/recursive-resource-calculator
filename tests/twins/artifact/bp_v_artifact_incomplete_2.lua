local plan = {steps = {{step_id = "gear", machine = "assembling-machine-2", machine_quality = "normal", machine_count = 1, recipe = "iron-gear-wheel", recipe_quality = "normal", modules = {}}}}
local artifact = {entities = {{entity_number = 1, name = "assembling-machine-2", type = "assembling-machine", quality = "normal", recipe = "iron-gear-wheel", recipe_quality = "normal", items = {}}}, wires = {}}
local catalog = {entity = { ["assembling-machine-2"] = {name = "assembling-machine-2", etype = "assembling-machine", module_slots = 2}, ["electric-furnace"] = {name = "electric-furnace", etype = "furnace", module_slots = 2}, beacon = {name = "beacon", etype = "beacon", module_slots = 2}}}
local input = {artifact = artifact, plan = plan, catalog = catalog}
return {id = "T-280-A12", rule = "BP_V_ARTIFACT_INCOMPLETE", class = "engine", from = "tests/test_blueprint_physical_contract.lua artifact reconciliation",
 stage = "artifact", grid = {w = 1, h = 1}, entities = {}, artifact = input,
 check = "artifact", truth = "ok", codes = {}, audit = {}}
