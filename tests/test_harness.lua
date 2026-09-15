--Proves the mocks behave like the engine in both directions before any mod test trusts them
local H = require "tests.harness"

H.test("LuaObject mock errors on a non-member read", function()
    local recipe = H.lua_object("LuaRecipePrototype", {name = "r"}, {"name", "category"})
    H.errors(function() return recipe.categories end, "LuaRecipePrototype doesn't contain key categories", "unknown member read")
end)

H.test("LuaObject mock returns nil for an unset member", function()
    local recipe = H.lua_object("LuaRecipePrototype", {name = "r"}, {"name", "category"})
    H.equal(recipe.category, nil, "unset member")
    H.equal(recipe.name, "r", "set member")
end)

H.test("LuaObject mock errors on a non-member write", function()
    local recipe = H.lua_object("LuaRecipePrototype", {name = "r"}, {"name"})
    H.errors(function() recipe.categories = {} end, "doesn't contain key categories", "unknown member write")
end)

H.test("product concept tables return nil for absent optional keys", function()
    local product = H.product("2.0", {name = "x", amount = 1})
    H.equal(product.extra_count_fraction, nil, "absent optional key")
    H.equal(product.probability, 1, "2.0 probability")
    local product_2_1 = H.product("2.1", {name = "x", amount = 1, p = 0.5, no_shared = true})
    H.equal(product_2_1.probability, nil, "2.1 has no probability")
    H.equal(product_2_1.shared_probability, nil, "2.1.7 shape without shared_probability")
    H.equal(product_2_1.independent_probability, 0.5, "2.1 independent_probability")
end)

H.test("recipe shapes expose only their version's category members", function()
    for _, case in ipairs({{"2.0", "category", "categories"}, {"2.1", "categories", "category"}}) do
        local world = H.new_world(case[1])
        world.add_recipe({name = "r", category = "crafting", ingredients = {}, products = {{name = "x", amount = 1}}})
        local recipe = prototypes.recipe.r
        assert(recipe[case[2]] ~= nil, case[1] .. " recipe lacks " .. case[2])
        H.errors(function() return recipe[case[3]] end, "doesn't contain key " .. case[3], case[1] .. " recipe exposes " .. case[3])
    end
end)

H.test("GUI mock resolves children by name and rejects unknown keys", function()
    local root = H.gui_root({type = "flow"})
    local child = root.add{type = "label", name = "hello", caption = "hi"}
    H.equal(root.hello, child, "child by name")
    H.equal(child.player_index, 1, "inherited player_index")
    H.errors(function() return root.nonexistent end, "LuaGuiElement doesn't contain key nonexistent", "unknown key")
end)

H.test("F3 numeric helpers reject non-finite values", function()
    for _, helper in ipairs({{"near", H.near}, {"near_relative", H.near_relative}}) do
        assert(type(helper[2]) == "function", "H." .. helper[1] .. " is missing")
        for _, value in ipairs({{"NaN", 0 / 0}, {"+inf", math.huge}, {"-inf", -math.huge}}) do
            H.errors(function() helper[2](value[2], 8, "value") end, "expected a finite number", helper[1] .. " accepts " .. value[1])
        end
    end
end)

H.test("F3 numeric helpers keep their finite tolerance", function()
    H.near(8 + 1e-10, 8, "inside absolute tolerance")
    H.errors(function() H.near(8 + 1e-6, 8, "value") end, "expected 8", "near outside tolerance")
    H.near_relative(6553500000 * (1 + 1e-10), 6553500000, "inside relative tolerance")
    H.errors(function() H.near_relative(6553500000 * (1 + 1e-6), 6553500000, "value") end, "expected 6553500000", "near_relative outside tolerance")
end)

H.test("H1 fluid buttons refuse unknown fluids and checkboxes keep their state", function()
    local world = H.new_world("2.0")
    world.add_fluid("lube")
    local root = H.gui_root({type = "flow"})
    local fluid_button = root.add{type = "choose-elem-button", name = "fluid", elem_type = "fluid"}
    fluid_button.elem_value = "lube"
    H.equal(fluid_button.elem_value, "lube", "known fluid")
    H.errors(function() fluid_button.elem_value = "gone" end, "Unknown fluid gone", "unknown fluid")
    local checkbox = root.add{type = "checkbox", name = "check", state = false}
    H.equal(checkbox.state, false, "initial state")
    checkbox.state = true
    H.equal(checkbox.state, true, "written state")
end)

H.test("H2a item-with-quality buttons refuse unknown items and qualities", function()
    local world = H.new_world("2.0")
    world.add_module("speed-module", "speed", {speed = 0.2})
    local root = H.gui_root({type = "flow"})
    local button = root.add{type = "choose-elem-button", name = "module", elem_type = "item-with-quality"}
    button.elem_value = {name = "speed-module", quality = "rare"}
    H.equal(button.elem_value.name, "speed-module", "known module")
    H.errors(function() button.elem_value = {name = "gone"} end, "Unknown item gone", "unknown item")
    H.errors(function() button.elem_value = {name = "speed-module", quality = "mythic"} end, "Unknown quality mythic", "unknown quality")
end)

H.test("H2b members of another prototype type error, and filtered prototype lists follow their filter", function()
    local world = H.new_world("2.0")
    world.add_item("plate")
    world.add_module("speed-module", "speed", {speed = 0.2})
    world.add_machine({name = "assembler", categories = {"crafting"}})
    world.add_machine({name = "old", categories = {"crafting"}})
    world.replace_machine_with_entity("old", "container")
    world.add_beacon({name = "beacon"})

    H.errors(function() return prototypes.entity.old.crafting_categories end, "can only be used if", "container crafting_categories")
    H.errors(function() return prototypes.entity.old.quality_affects_module_slots end, "can only be used if", "container quality_affects_module_slots")
    H.errors(function() return prototypes.entity.beacon.get_crafting_speed end, "can only be used if", "beacon get_crafting_speed")
    H.errors(function() return prototypes.item.plate.get_module_effects end, "can only be used if", "plain item get_module_effects")
    H.equal(prototypes.entity.assembler.quality_affects_module_slots, nil, "unset member on a crafting machine")

    local function names(list)
        local sorted = {}
        for name, _ in pairs(list) do sorted[#sorted + 1] = name end
        table.sort(sorted)
        return table.concat(sorted, ",")
    end
    H.equal(names(prototypes.get_entity_filtered{{filter = "crafting-machine"}}), "assembler", "crafting machines")
    H.equal(names(prototypes.get_entity_filtered{{filter = "type", type = "beacon"}}), "beacon", "beacons")
    H.equal(names(prototypes.get_item_filtered{{filter = "type", type = "module"}}), "speed-module", "modules")
end)

H.test("H2c module inventory size follows quality, the machine's own bonus overriding the quality's", function()
    local world = H.new_world("2.0")
    world.add_machine({name = "flag", categories = {"crafting"}, module_slots = 2, quality_affects_module_slots = true})
    world.add_machine({name = "own-2", categories = {"crafting"}, module_slots = 2, quality_affects_module_slots = true, module_slots_quality_bonus = {legendary = 2}})
    world.add_machine({name = "own-0", categories = {"crafting"}, module_slots = 2, quality_affects_module_slots = true, module_slots_quality_bonus = {legendary = 0}})
    world.add_machine({name = "no-flag", categories = {"crafting"}, module_slots = 2})
    world.add_beacon({name = "beacon", module_slots = 2, quality_affects_module_slots = true})
    local crafter, beacon_modules = defines.inventory.crafter_modules, defines.inventory.beacon_modules
    H.equal(prototypes.entity.flag.get_inventory_size(crafter, "legendary"), 7, "quality bonus = level")
    H.equal(prototypes.entity.flag.get_inventory_size(crafter), 2, "normal quality")
    H.equal(prototypes.entity["own-2"].get_inventory_size(crafter, "legendary"), 4, "machine bonus 2")
    H.equal(prototypes.entity["own-0"].get_inventory_size(crafter, "legendary"), 2, "machine bonus 0")
    H.equal(prototypes.entity["no-flag"].get_inventory_size(crafter, "legendary"), 2, "quality does not affect slots")
    H.equal(prototypes.entity.flag.get_inventory_size(beacon_modules), nil, "beacon inventory on a crafting machine")
    H.equal(prototypes.entity.beacon.get_inventory_size(beacon_modules, "rare"), 4, "beacon quality bonus")
end)

H.test("H3 GUI mock refuses a second child with the same name under one parent, as the engine does", function()
    local root = H.gui_root({type = "flow"})
    root.add{type = "button", name = "same"}
    H.errors(function() root.add{type = "button", name = "same"} end, "Gui element with name same already present in the parent element.", "same name twice under one parent")
    local first, second = root.add{type = "flow"}, root.add{type = "flow"}
    first.add{type = "button", name = "repeated"}
    second.add{type = "button", name = "repeated"}
    H.equal(#root.children, 3, "unnamed siblings and equal names under different parents are allowed")
end)

H.test("H4 recipe buttons accept documented ingredient and product filters and refuse unknown ones", function()
    local world = H.new_world("2.0")
    world.add_item("plate")
    world.add_fluid("oil")
    world.add_recipe({name = "burn", category = "crafting", hidden = true, ingredients = {{name = "plate", amount = 1}}, products = {}})
    H.equal(prototypes.recipe.burn.hidden, true, "recipes expose hidden")
    local root = H.gui_root({type = "flow"})
    for _, filter in ipairs({{"has-ingredient-item", "plate"}, {"has-ingredient-fluid", "oil"}, {"has-product-item", "plate"}, {"has-product-fluid", "oil"}}) do
        root.add{type = "flow"}.add{type = "choose-elem-button", elem_type = "recipe",
            elem_filters = {{filter = filter[1], elem_filters = {{filter = "name", name = filter[2]}}}}}
    end
    H.errors(function()
        root.add{type = "choose-elem-button", elem_type = "recipe", elem_filters = {{filter = "consumes-item", elem_filters = {{filter = "name", name = "plate"}}}}}
    end, "Unknown recipe filter consumes-item", "made-up filter name")
    H.errors(function()
        root.add{type = "choose-elem-button", elem_type = "recipe", elem_filters = {{filter = "has-ingredient-fluid", elem_filters = {{filter = "name", name = "plate"}}}}}
    end, "has-ingredient-fluid filter names unknown fluid plate", "item name in a fluid filter")
    H.errors(function()
        root.add{type = "choose-elem-button", elem_type = "recipe", elem_filters = {{filter = "has-ingredient-item"}}}
    end, "has-ingredient-item filter needs nested elem_filters", "missing nested filters")
end)

H.test("H5 burner and fluid energy source mocks follow their version's members, and type filters take lists", function()
    for _, shape in ipairs({"2.0", "2.1"}) do
        local world = H.new_world(shape)
        world.add_item("fuel", {value = 12e6, category = "chemical"})
        world.add_item("rock")
        world.add_fluid("gas", {value = 1e6})
        world.add_burner({name = "tower", type = "reactor", energy_kw = 40000, burner = {fuel_categories = {"chemical"}, effectivity = 2.5}})
        world.add_burner({name = "flare", type = "boiler", energy_kw = 1000, fluid = {scale_fluid_usage = true}})
        world.add_burner({name = "engine", type = "burner-generator", max_power_kw = 900, burner = {fuel_categories = {"chemical"}}})
        world.add_burner({name = "train", type = "locomotive", energy_kw = 600, burner = {fuel_categories = {"chemical"}}})
        H.equal(prototypes.item.rock.fuel_value, 0, shape .. ": plain item has no fuel value")
        H.equal(prototypes.item.rock.fuel_category, nil, shape .. ": plain item has no fuel category")
        H.equal(prototypes.item.fuel.fuel_emissions_multiplier, 1, shape .. ": default emissions multiplier")
        local tower = prototypes.entity.tower
        H.equal(tower.burner_prototype.fuel_categories.chemical, true, shape .. ": fuel categories as a set")
        H.near(tower.get_max_energy_usage() * 60, 40e6, shape .. ": usage in joules per tick")
        H.errors(function() return tower.burner_prototype.fuel_category end, "LuaBurnerPrototype doesn't contain key fuel_category", shape .. ": burner strict")
        H.errors(function() return tower.get_max_power_output end, "can only be used if this is burner-generator or generator", shape .. ": power output gated")
        H.near(prototypes.entity.engine.get_max_power_output() * 60, 900e3, shape .. ": burner generator output")
        local source = prototypes.entity.flare.fluid_energy_source_prototype
        H.equal(source.fluid_usage_per_tick, 0, shape .. ": usage per tick is always a number")
        if shape == "2.0" then
            H.errors(function() return source.output_fluid_box end, "doesn't contain key output_fluid_box", "2.0 has no output fluid box")
            H.errors(function() return prototypes.fluid.gas.spent_fluid end, "doesn't contain key spent_fluid", "2.0 fluids have no spent fluid")
        else
            H.equal(source.output_fluid_box, nil, "2.1 output fluid box reads nil when absent")
        end
        local found = prototypes.get_entity_filtered({{filter = "type", type = {"reactor", "boiler", "burner-generator"}}})
        H.equal(found.tower ~= nil and found.flare ~= nil and found.engine ~= nil, true, shape .. ": listed types found")
        H.equal(found.train, nil, shape .. ": other types left out")
    end
end)

H.test("H6 quality prototypes chain through next, and forces answer is_quality_unlocked", function()
    local world = H.new_world("2.0")
    world.add_player(1)
    local normal = prototypes.quality.normal
    H.equal(normal.next.name, "uncommon", "normal's next")
    H.equal(normal.next_probability, 0.1, "vanilla next_probability")
    H.equal(prototypes.quality.legendary.next, nil, "last quality has no next")
    H.equal(prototypes.quality.legendary.next_probability, 0, "last quality's next_probability")
    H.equal(prototypes.quality.epic.next.name, "legendary", "epic's next skips no quality")
    local force = game.players[1].force
    H.equal(force.is_quality_unlocked("rare"), true, "unlocked by default")
    world.lock_quality("rare")
    H.equal(force.is_quality_unlocked(prototypes.quality.rare), false, "locked, asked by prototype")
    H.errors(function() force.is_quality_unlocked("shiny") end, "Unknown quality shiny", "unknown quality")
    world.remove_quality("legendary")
    H.equal(prototypes.quality.epic.next, nil, "a removed quality is no one's next")
    world.set_quality_chain({{name = "normal", level = 0, next_probability = 0.3}, {name = "c", level = 1, next_probability = 0.05}, {name = "b:c", level = 2}})
    H.equal(prototypes.quality.normal.next.name, "c", "modded chain")
    H.equal(prototypes.quality.c.next_probability, 0.05, "modded next_probability")
    H.equal(prototypes.quality.uncommon, nil, "vanilla qualities replaced")
    H.errors(function() return normal.hidden end, "LuaQualityPrototype doesn't contain key hidden", "quality mock stays strict")
end)

H.test("H6 GUI mock: elem_type is read-only, only sprite-buttons show a quality, and a destroyed child's name can be reused", function()
    H.new_world("2.0")
    local root = H.gui_root({type = "flow"})
    local button = root.add{type = "choose-elem-button", name = "hxrrc_desired_item_button", elem_type = "item"}
    H.errors(function() button.elem_type = "item-with-quality" end, "elem_type is read-only", "elem_type write")
    button.destroy()
    local replaced = root.add{type = "choose-elem-button", name = "hxrrc_desired_item_button", elem_type = "item-with-quality", index = 1}
    H.equal(root.hxrrc_desired_item_button, replaced, "same name after destroy")
    H.errors(function() root.add{type = "choose-elem-button", name = "hxrrc_desired_item_button", elem_type = "item"} end, "already present", "duplicate still refused")
    local badge = root.add{type = "sprite-button", quality = "rare"}
    H.equal(badge.quality.name, "rare", "quality reads back as the prototype")
    H.equal(badge.quality.level, 2, "prototype members readable")
    badge.quality = nil
    H.equal(badge.quality, nil, "quality cleared")
    H.errors(function() root.add{type = "sprite-button", quality = "shiny"} end, "Unknown quality shiny", "unknown badge quality")
    H.errors(function() badge.quality = "shiny" end, "Unknown quality shiny", "unknown badge quality write")
    H.errors(function() root.add{type = "sprite", quality = "rare"} end, "only used on a sprite-button", "quality on a sprite")
    local locked = root.add{type = "choose-elem-button", elem_type = "item", locked = true}
    H.equal(locked.locked, true, "locked member")
end)

H.done("test_harness")
