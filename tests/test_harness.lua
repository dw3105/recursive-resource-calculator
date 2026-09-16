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
    H.errors(function() return normal.color end, "LuaQualityPrototype doesn't contain key color", "quality mock stays strict")
    H.equal(prototypes.quality.normal.hidden, false, "hidden is a LuaPrototypeBase member, false unless a fixture hides the quality")
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

H.test("H7 recipe filters: category and mode are checked, and matching follows and-before-or with invert", function()
    local world = H.new_world("2.0")
    world.add_item("X")
    world.add_item("Y")
    world.add_recipe({name = "x-rec", category = "recycling", ingredients = {{name = "X", amount = 1}}, products = {{name = "Y", amount = 1}}})
    world.add_recipe({name = "x-craft", category = "crafting", ingredients = {{name = "X", amount = 1}, {name = "Y", amount = 1}}, products = {{name = "Y", amount = 1}}})
    world.add_recipe({name = "y-rec", category = "recycling", ingredients = {{name = "Y", amount = 1}}, products = {{name = "X", amount = 1}}})
    local root = H.gui_root({type = "flow"})
    local function takes(item) return {filter = "has-ingredient-item", elem_filters = {{filter = "name", name = item}}} end
    H.errors(function() root.add{type = "choose-elem-button", elem_type = "recipe", elem_filters = {{filter = "category", category = "smelting"}}} end,
        "unknown recipe category smelting", "unknown category")
    H.errors(function() root.add{type = "choose-elem-button", elem_type = "recipe", elem_filters = {takes("X"), {filter = "category", category = "recycling", mode = "xor"}}} end,
        "Unknown filter mode xor", "unknown mode")
    H.errors(function() root.add{type = "choose-elem-button", elem_type = "recipe", elem_filters = {{filter = "hidden", invert = 1}}} end,
        "invert must be a boolean", "invert type")
    H.deep_equal(H.recipes_matching({takes("X")}), {"x-craft", "x-rec"}, "one filter")
    H.deep_equal(H.recipes_matching({takes("X"), {filter = "category", category = "recycling", mode = "and"}}), {"x-rec"}, "and")
    H.deep_equal(H.recipes_matching({takes("X"), {filter = "category", category = "recycling"}}), {"x-craft", "x-rec", "y-rec"}, "or by default")
    --(X and crafting) or (Y and recycling): and binds tighter
    H.deep_equal(H.recipes_matching({takes("X"), {filter = "category", category = "crafting", mode = "and"}, takes("Y"), {filter = "category", category = "recycling", mode = "and"}}),
        {"x-craft", "y-rec"}, "and before or")
    H.deep_equal(H.recipes_matching({takes("X"), {filter = "category", category = "recycling", mode = "and", invert = true}}), {"x-craft"}, "invert")
    H.equal(prototypes.recipe_category.recycling.name, "recycling", "categories indexed")
end)

--Round 6 (N0): the cursor, custom inputs, player.opened, element lifetime, style names, sprites and placing items

local function cursor_world()
    local world = H.new_world("2.0")
    world.add_item("iron-plate")
    world.add_module("speed-module", "speed", {speed = 0.2, consumption = 0.5})
    world.add_machine({name = "assembler", categories = {"crafting"}})
    world.add_player(1)
    world.add_player(2)
    return world
end

H.test("N0a cursor_ghost takes names or prototypes, reads back prototypes, and refuses unknown items and qualities", function()
    local world = cursor_world()
    local player = game.players[1]
    H.equal(player.cursor_ghost, nil, "empty hand")
    player.cursor_ghost = {name = "speed-module", quality = "rare"}
    local ghost = player.cursor_ghost
    H.equal(ghost.name, prototypes.item["speed-module"], "name reads as the item prototype")
    H.equal(ghost.quality, prototypes.quality.rare, "quality reads as the quality prototype")
    player.cursor_ghost = "iron-plate"
    H.equal(player.cursor_ghost.quality, prototypes.quality.normal, "a ghost without quality reads normal")
    player.cursor_ghost = {name = prototypes.item["speed-module"], quality = prototypes.quality.epic}
    H.equal(player.cursor_ghost.quality.name, "epic", "prototypes accepted on write")
    H.errors(function() player.cursor_ghost = {name = "nothing"} end, "Unknown item nothing", "unknown item")
    H.errors(function() player.cursor_ghost = {name = "iron-plate", quality = "shiny"} end, "Unknown quality shiny", "unknown quality")
    H.errors(function() player.cursor_ghost = 5 end, "ItemWithQualityID", "not an item id")
    player.cursor_ghost = nil
    H.equal(player.cursor_ghost, nil, "cleared")
end)

H.test("N0b cursor_stack is read-only, reads quality as a prototype (normal included), and an empty stack refuses item reads", function()
    local world = cursor_world()
    local player = game.players[1]
    local stack = player.cursor_stack
    H.equal(stack.valid_for_read, false, "empty stack")
    H.errors(function() return stack.name end, "invalid for read", "name of an empty stack")
    world.hold_item(1, "speed-module", "legendary", 3)
    H.equal(stack.valid_for_read, true, "held")
    H.equal(stack.name, "speed-module", "name")
    H.equal(stack.quality, prototypes.quality.legendary, "quality prototype")
    H.equal(stack.count, 3, "count")
    world.hold_item(1, "speed-module")
    H.equal(stack.quality, prototypes.quality.normal, "normal reads as the normal prototype, not nil")
    H.errors(function() player.cursor_stack = stack end, "cursor_stack is read-only", "assigning the stack")
end)

H.test("N0c a stack and a ghost can be held at once; clear_cursor empties both; is_cursor_empty is refused as unmodelled", function()
    local world = cursor_world()
    local player = game.players[1]
    world.hold_ghost(1, "iron-plate", "rare")
    world.hold_item(1, "speed-module", "rare")
    assert(player.cursor_ghost and player.cursor_stack.valid_for_read, "both held")
    H.errors(function() return player.is_cursor_empty() end, "is_cursor_empty is not modelled", "ambiguous member")
    H.equal(player.clear_cursor(), true, "clear_cursor result")
    H.equal(player.cursor_ghost, nil, "ghost cleared")
    H.equal(player.cursor_stack.valid_for_read, false, "stack cleared")
    world.cursor_ghost_needs_empty_cursor = true
    world.hold_item(1, "speed-module")
    H.errors(function() player.cursor_ghost = "iron-plate" end, "cursor is not empty", "strict switch refuses a ghost over a stack")
end)

H.test("N0d every cursor write queues one notification with its tick; flush delivers them in order; suppression and merging are opt-in", function()
    local world = cursor_world()
    local delivered = {}
    world.handlers.events[defines.events.on_player_cursor_stack_changed] = function(event)
        assert(event.name == defines.events.on_player_cursor_stack_changed, "event name")
        delivered[#delivered + 1] = event.player_index .. "@" .. event.tick
        for key, _ in pairs(event) do
            assert(key == "name" or key == "player_index" or key == "tick", "notification carries only name, player_index, tick; got " .. key)
        end
    end
    world.hold_ghost(1, "iron-plate")
    world.advance_tick()
    game.players[1].cursor_ghost = nil
    game.players[2].clear_cursor()
    H.equal(#delivered, 0, "not delivered before a flush")
    world.flush_cursor_events()
    H.deep_equal(delivered, {"1@0", "1@1", "2@1"}, "one per write, in order, each with its tick")
    delivered = {}
    world.suppress_next_cursor_event(1)
    world.hold_ghost(1, "iron-plate")
    world.hold_ghost(1, "speed-module")
    world.flush_cursor_events()
    H.deep_equal(delivered, {"1@1"}, "the suppressed write raised nothing")
    delivered = {}
    world.merge_cursor_events = true
    world.empty_hand(1)
    world.hold_ghost(1, "iron-plate")
    world.advance_tick()
    world.empty_hand(1)
    world.flush_cursor_events()
    H.deep_equal(delivered, {"1@1", "1@2"}, "merge mode: one per player per tick")
end)

H.test("N0e H.press raises a plain custom input event and refuses what the engine cannot produce", function()
    local world = cursor_world()
    local seen
    world.handlers.events["hxrrc_probe"] = function(event) seen = event end
    local button = game.players[1].gui.screen.add{type = "sprite-button", name = "probe_button"}
    world.advance_tick(7)
    H.press(world, "hxrrc_probe", {element = button})
    H.equal(seen.element, button, "element")
    H.equal(seen.in_gui, true, "in_gui follows the element")
    H.equal(seen.tick, 7, "tick")
    H.equal(seen.input_name, "hxrrc_probe", "input_name")
    H.equal(getmetatable(seen), nil, "plain table")
    H.press(world, "hxrrc_probe", {})
    H.equal(seen.element, nil, "no element over the world")
    H.equal(seen.in_gui, false, "not in a GUI")
    H.errors(function() H.press(world, "hxrrc_missing", {}) end, "no handler registered", "unregistered input")
    H.errors(function() H.press(world, "hxrrc_probe", {element = button, in_gui = false}) end, "in_gui true", "element outside a GUI")
    H.errors(function() H.press(world, "hxrrc_probe", {element = button, player_index = 2}) end, "another player", "another player's element")
    H.errors(function() H.press(world, "hxrrc_probe", {selected_prototype = {name = "x"}}) end, "selected_prototype", "malformed selection")
    button.destroy()
    H.errors(function() H.press(world, "hxrrc_probe", {element = button}) end, "not valid", "destroyed element")
end)

H.test("N0f assigning player.opened raises on_gui_closed for the open element; a destroyed opened element reads nil; another GUI can take it", function()
    local world = cursor_world()
    local closed = {}
    world.handlers.events[defines.events.on_gui_closed] = function(event) closed[#closed + 1] = event.element.name end
    local player = game.players[1]
    local first = player.gui.screen.add{type = "frame", name = "first"}
    local second = player.gui.screen.add{type = "frame", name = "second"}
    player.opened = first
    H.deep_equal(closed, {}, "nothing was open")
    player.opened = second
    H.deep_equal(closed, {"first"}, "replacing closes the open element")
    player.opened = second
    H.deep_equal(closed, {"first"}, "re-assigning the same element closes nothing")
    second.destroy()
    H.equal(player.opened, nil, "destroyed element reads nil")
    player.opened = first
    H.deep_equal(closed, {"first"}, "a destroyed element raises no close")
    world.open_other_gui(1)
    H.deep_equal(closed, {"first", "first"}, "another GUI closes ours")
    H.equal(player.opened.name, "other_gui", "the other GUI is opened")
end)

H.test("N0i opening a GUI inside on_gui_closed is refused, as Factorio force closes it; clearing the focus there is allowed", function()
    local world = cursor_world()
    local player = game.players[1]
    local first = player.gui.screen.add{type = "frame", name = "first"}
    local second = player.gui.screen.add{type = "frame", name = "second"}
    world.handlers.events[defines.events.on_gui_closed] = function() player.opened = second end
    player.opened = first
    H.errors(function() player.opened = nil end, "opened during on_gui_closed", "reopening inside the close")
    local cleared = false
    world.handlers.events[defines.events.on_gui_closed] = function()
        if not cleared then cleared = true player.opened = nil end
    end
    player.opened = first
    player.opened = nil
    H.equal(cleared, true, "the close handler ran")
    H.equal(player.opened, nil, "clearing inside the close is fine")
end)

H.test("N0g destroy and clear invalidate the whole removed subtree", function()
    cursor_world()
    local screen = game.players[1].gui.screen
    local outer = screen.add{type = "flow", name = "outer"}
    local inner = outer.add{type = "flow", name = "inner"}
    local leaf = inner.add{type = "sprite-button", name = "leaf"}
    outer.clear()
    H.equal(inner.valid, false, "cleared child")
    H.equal(leaf.valid, false, "cleared grandchild")
    H.equal(outer.valid, true, "cleared element itself stays valid")
    local again = outer.add{type = "flow", name = "inner"}
    local again_leaf = again.add{type = "sprite-button", name = "leaf"}
    outer.destroy()
    H.equal(again_leaf.valid, false, "destroyed grandchild")
end)

H.test("N0h style names, toggled, sprite paths, item flags, placing items and mouse buttons are modelled", function()
    local world = cursor_world()
    local screen = game.players[1].gui.screen
    local button = screen.add{type = "sprite-button", name = "slot", style = "slot_button"}
    H.equal(button.style.name, "slot_button", "style by name")
    button.style.width = 40
    H.equal(button.style.width, 40, "style table still writable")
    button.style = "item_and_count_select_confirm"
    H.equal(button.style.name, "item_and_count_select_confirm", "style assigned by name")
    button.toggled = true
    H.equal(button.toggled, true, "toggled")
    H.equal(helpers.is_valid_sprite_path("hxrrc_recycling"), true, "data-stage sprite")
    H.equal(helpers.is_valid_sprite_path("item/speed-module"), true, "item sprite")
    H.equal(helpers.is_valid_sprite_path("item/nothing"), false, "missing item sprite")
    H.equal(helpers.is_valid_sprite_path("utility/check_mark_green"), true, "utility sprite")
    world.remove_sprite("hxrrc_recycling")
    H.equal(helpers.is_valid_sprite_path("hxrrc_recycling"), false, "removed sprite")
    H.equal(prototypes.item["speed-module"].hidden, false, "hidden defaults false")
    world.set_item_flags("speed-module", {hidden = true, parameter = true})
    H.equal(prototypes.item["speed-module"].parameter, true, "parameter flag")
    H.deep_equal(prototypes.entity.assembler.items_to_place_this, {{name = "assembler", count = 1}}, "default placing item")
    world.set_placing_items("assembler", nil)
    H.equal(prototypes.entity.assembler.items_to_place_this, nil, "absent placing items")
    world.set_placing_items("assembler", {{name = "iron-plate", count = 1}})
    H.equal(prototypes.entity.assembler.items_to_place_this[1].name, "iron-plate", "item name differing from the entity")
    local buttons = defines.mouse_button_type
    assert(buttons.left ~= buttons.right and buttons.left ~= buttons.middle and buttons.right ~= buttons.middle, "distinct mouse buttons")
end)

H.test("P0a quality, entity and utility sprite paths are checked against what exists", function()
    cursor_world()
    local screen = game.players[1].gui.screen
    H.equal(helpers.is_valid_sprite_path("quality/rare"), true, "quality sprite")
    H.equal(helpers.is_valid_sprite_path("quality/nothing"), false, "missing quality sprite")
    H.equal(helpers.is_valid_sprite_path("entity/assembler"), true, "entity sprite")
    H.equal(helpers.is_valid_sprite_path("utility/empty_module_slot"), true, "listed utility sprite")
    H.equal(helpers.is_valid_sprite_path("utility/trash"), true, "listed utility sprite")
    H.equal(helpers.is_valid_sprite_path("utility/nothing_like_this"), false, "unknown utility sprite")
    screen.add{type = "sprite-button", name = "q", sprite = "quality/rare"}
    H.errors(function() screen.add{type = "sprite-button", name = "bad_quality", sprite = "quality/nothing"} end, "Unknown sprite", "missing quality refused")
    H.errors(function() screen.add{type = "sprite-button", name = "bad_utility", sprite = "utility/nothing_like_this"} end, "Unknown sprite", "unknown utility refused")
end)

H.test("P0b entity prototypes expose hidden, false by default, settable by fixtures", function()
    local world = cursor_world()
    H.equal(prototypes.entity.assembler.hidden, false, "machine hidden defaults false")
    world.set_entity_flags("assembler", {hidden = true})
    H.equal(prototypes.entity.assembler.hidden, true, "hidden flag")
end)

H.test("Q0a Q0b engine objects read as userdata, as in Factorio 2.0; plain tables stay tables; a ghost's name is a prototype holding a string name", function()
    local world = cursor_world()
    H.equal(type(prototypes.item["speed-module"]), "userdata", "Q0a: item prototype")
    H.equal(type(prototypes.quality.normal), "userdata", "Q0a: quality prototype")
    H.equal(type(game.players[1]), "userdata", "Q0a: player")
    H.equal(type(game.players[1].gui.screen), "userdata", "Q0a: GUI element")
    H.equal(type({}), "table", "Q0a: plain table")
    H.equal(type("speed-module"), "string", "Q0a: string")
    world.hold_ghost(1, "speed-module")
    local ghost = game.players[1].cursor_ghost
    H.equal(type(ghost), "table", "Q0b: the ghost pair is a concept table")
    H.equal(type(ghost.name), "userdata", "Q0b: its name is a prototype")
    H.equal(type(ghost.name.name), "string", "Q0b: the prototype's name is a string")
    H.equal(type(game.players[1].cursor_stack), "userdata", "Q0b: the cursor stack")
end)

H.done("test_harness")
