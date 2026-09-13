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

H.done("test_harness")
