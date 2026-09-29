--The vanilla-named mock world the offline game shim runs on (tests/game/offline.lua) and the mock-parity manifest is
--read from (tools/fixture_facts.lua --mock, round 48 D6): every mocked prototype here has a real counterpart by name.
return function(H, shape)
    shape = shape or os.getenv("RRC_SHAPE") or "2.0"
    local world = H.new_world(shape)
    world.add_item("iron-plate")
    world.add_item("copper-plate")
    world.add_item("iron-gear-wheel")
    world.add_item("automation-science-pack", nil, nil, shape == "2.1" and "item" or "tool")  --2.1 types science packs item
    world.add_item("coal", {value = 4e6, category = "chemical"})
    world.add_machine({name = "assembling-machine-1", categories = {"crafting", "basic-crafting", "advanced-crafting", "electronics", "pressing"}, speed = 0.5, module_slots = 0, energy_kw = 75})  -- vanilla: no slots (headless, round 42)
    world.add_machine({name = "assembling-machine-2", categories = {"crafting", "basic-crafting", "advanced-crafting", "crafting-with-fluid", "electronics", "pressing"}, speed = 0.75, module_slots = 2, energy_kw = 150})
    world.add_recipe({name = "iron-gear-wheel", category = "crafting", energy = 0.5,
        ingredients = {{name = "iron-plate", amount = 2}}, products = {{name = "iron-gear-wheel", amount = 1}}})
    world.add_recipe({name = "automation-science-pack", category = "crafting", energy = 5,
        ingredients = {{name = "copper-plate", amount = 1}, {name = "iron-gear-wheel", amount = 1}},
        products = {{name = "automation-science-pack", amount = 1}}})
    --Green science chain, modules and a beacon: what the lane test files type or pick in the real game.
    world.add_item("copper-cable")
    world.add_item("electronic-circuit")
    world.add_item("logistic-science-pack", nil, nil, shape == "2.1" and "item" or "tool")
    world.add_recipe({name = "copper-cable", category = "electronics", energy = 0.5,
        ingredients = {{name = "copper-plate", amount = 1}}, products = {{name = "copper-cable", amount = 2}}})
    world.add_recipe({name = "electronic-circuit", category = "electronics", energy = 0.5,
        ingredients = {{name = "iron-plate", amount = 1}, {name = "copper-cable", amount = 3}},
        products = {{name = "electronic-circuit", amount = 1}}})
    world.add_module("speed-module", "speed", {speed = 0.2})
    world.add_module("productivity-module", "productivity", {productivity = 0.04})
    world.add_beacon({name = "beacon"})
    world.add_default_infrastructure()
    --Placing items of the default infrastructure, as vanilla has them (inserter and belt recipes need them).
    for _, name in ipairs({"transport-belt", "inserter"}) do
        if not prototypes.item[name] then world.add_item(name) end
    end
    world.add_recipe({name = "inserter", category = "crafting", energy = 0.5,
        ingredients = {{name = "electronic-circuit", amount = 1}, {name = "iron-gear-wheel", amount = 1}, {name = "iron-plate", amount = 1}},
        products = {{name = "inserter", amount = 1}}})
    world.add_recipe({name = "transport-belt", category = "pressing", energy = 0.5,
        ingredients = {{name = "iron-plate", amount = 1}, {name = "iron-gear-wheel", amount = 1}},
        products = {{name = "transport-belt", amount = 2}}})
    world.add_recipe({name = "logistic-science-pack", category = "crafting", energy = 6,
        ingredients = {{name = "inserter", amount = 1}, {name = "transport-belt", amount = 1}},
        products = {{name = "logistic-science-pack", amount = 1}}})
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    return world
end
