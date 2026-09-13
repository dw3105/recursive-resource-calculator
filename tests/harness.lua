--Offline test harness: mocks just enough of the Factorio runtime API to drive the mod's logic and GUI code from plain Lua
--Mock strictness follows the engine: LuaObjects throw on unknown members, concept tables are plain Lua tables, custom tables return nil for unknown names
package.path = "./?.lua;" .. package.path

local H = {}

local TOLERANCE = 1e-9

local function set_of(list)
    local set = {}
    for _, value in ipairs(list) do set[value] = true end
    return set
end

--LuaObject: reading or writing a key outside its member list errors like the engine does
function H.lua_object(class, fields, members)
    local allowed = set_of(members)
    for key, _ in pairs(fields) do
        if not allowed[key] then error("fixture sets non-member " .. class .. "." .. key, 2) end
    end
    return setmetatable(fields, {
        __index = function(_, key)
            if allowed[key] then return nil end
            error(class .. " doesn't contain key " .. tostring(key), 2)
        end,
        __newindex = function(object, key, value)
            if not allowed[key] then error(class .. " doesn't contain key " .. tostring(key), 2) end
            rawset(object, key, value)
        end,
    })
end

local RECIPE_MEMBERS = {
    ["2.0"] = {"name", "valid", "object_name", "products", "ingredients", "energy", "allowed_module_categories", "maximum_productivity", "category", "additional_categories"},
    ["2.1"] = {"name", "valid", "object_name", "products", "ingredients", "energy", "allowed_module_categories", "maximum_productivity", "categories", "get_product_amount"},
    --shape the code at cb6b529 expects: 2.1 recipe members with 2.0 product fields (portal 1.1.9 on Factorio 2.0.77)
    ["hybrid"] = {"name", "valid", "object_name", "products", "ingredients", "energy", "allowed_module_categories", "maximum_productivity", "category", "additional_categories", "categories"},
}

local ENTITY_MEMBERS = {"name", "type", "valid", "localised_name", "crafting_categories", "effect_receiver", "energy_usage", "allowed_effects",
    "get_crafting_speed", "get_max_energy_usage", "electric_energy_source_prototype", "burner_prototype", "heat_energy_source_prototype",
    "fluid_energy_source_prototype", "void_energy_source_prototype"}
local ITEM_MEMBERS = {"name", "type", "valid", "localised_name", "module_effects", "category"}
local FLUID_MEMBERS = {"name", "valid", "localised_name"}
local ENERGY_SOURCE_MEMBERS = {"emissions_per_joule"}
local FORCE_RECIPE_MEMBERS = {"name", "valid", "productivity_bonus"}
local FORCE_MEMBERS = {"name", "valid", "recipes", "players"}
local PLAYER_MEMBERS = {"index", "name", "valid", "force", "gui", "opened", "create_local_flying_text"}
local HELPERS_MEMBERS = {"compare_versions"}
local SCRIPT_MEMBERS = {"active_mods", "mod_name", "on_init", "on_load", "on_configuration_changed", "on_event", "on_nth_tick"}

local GUI_MEMBERS = set_of({"type", "name", "caption", "tooltip", "children", "parent", "style", "tags", "player_index", "enabled", "visible",
    "text", "elem_value", "elem_type", "elem_filters", "elem_tooltip", "selected_index", "items", "tabs", "selected_tab_index", "numeric",
    "allow_decimal", "allow_negative", "lose_focus_on_confirm", "direction", "column_count", "draw_horizontal_lines", "draw_vertical_lines",
    "sprite", "valid", "auto_center"})

local gui_methods = {}

local function new_gui_element(params, parent, player_index)
    local element = {children = {}, style = {}, tabs = {}, valid = true, enabled = true, visible = true, tags = {}}
    for key, value in pairs(params) do
        if key ~= "index" and GUI_MEMBERS[key] then element[key] = value end
    end
    if params.enabled == false then element.enabled = false end
    if params.visible == false then element.visible = false end
    if params.elem_type then element.elem_value = params[params.elem_type] end
    element.parent = parent
    element.player_index = parent and parent.player_index or player_index
    return setmetatable(element, {
        __index = function(self, key)
            --the engine binds methods, so mod code calls element.add{...} without self; accept both call styles
            local method = gui_methods[key]
            if method then
                return function(first, ...)
                    if first == self then return method(self, ...) end
                    return method(self, first, ...)
                end
            end
            for _, child in ipairs(rawget(self, "children")) do
                if child.name == key then return child end
            end
            if GUI_MEMBERS[key] then return nil end
            error("LuaGuiElement doesn't contain key " .. tostring(key), 2)
        end,
        __newindex = function(self, key, value)
            if not GUI_MEMBERS[key] then error("LuaGuiElement doesn't contain key " .. tostring(key), 2) end
            rawset(self, key, value)
        end,
    })
end

function gui_methods.add(self, params)
    local child = new_gui_element(params, self)
    if params.index then
        table.insert(self.children, params.index, child)
    else
        table.insert(self.children, child)
    end
    return child
end

function gui_methods.get_index_in_parent(self)
    for index, child in ipairs(self.parent.children) do
        if child == self then return index end
    end
end

function gui_methods.destroy(self)
    if self.parent then table.remove(self.parent.children, self:get_index_in_parent()) end
    self.valid = false
end

function gui_methods.clear(self)
    self.children = {}
end

function gui_methods.add_tab(self, tab, content)
    table.insert(self.tabs, {tab = tab, content = content})
end

function gui_methods.remove_tab(self, tab)
    for index, tab_and_content in ipairs(self.tabs) do
        if tab_and_content.tab == tab then table.remove(self.tabs, index) return end
    end
end

function gui_methods.swap_children(self, a, b)
    self.children[a], self.children[b] = self.children[b], self.children[a]
end

function gui_methods.force_auto_center() end

function H.gui_root(params, player_index)
    return new_gui_element(params, nil, player_index or 1)
end

local function compare_versions(a, b)
    local function parts(version)
        local numbers = {}
        for number in version:gmatch("%d+") do numbers[#numbers + 1] = tonumber(number) end
        return numbers
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

--Product concept table in the shape of the given API version; spec: {type, name, amount | min+max, p, e, ignored, ignored_by_stats, shared, no_shared, percent_spoiled}
function H.product(shape, spec)
    local product = {type = spec.type or "item", name = spec.name, amount = spec.amount, amount_min = spec.min, amount_max = spec.max,
        extra_count_fraction = spec.e, ignored_by_productivity = spec.ignored, ignored_by_stats = spec.ignored_by_stats, percent_spoiled = spec.percent_spoiled}
    if shape == "2.1" then
        product.independent_probability = spec.p or 1
        if not spec.no_shared then product.shared_probability = spec.shared or {min = 0, max = 1} end
    else
        product.probability = spec.p or 1
    end
    return product
end

local MOD_MODULE_PREFIXES = {"gui.", "logic.", "control", "updates"}

--Fresh runtime globals and module cache. shape: "2.0", "2.1" or "hybrid"
function H.new_world(shape)
    for module_name, _ in pairs(package.loaded) do
        for _, prefix in ipairs(MOD_MODULE_PREFIXES) do
            if module_name:sub(1, #prefix) == prefix then package.loaded[module_name] = nil end
        end
    end

    local world = {shape = shape, flying_texts = {}, handlers = {events = {}}}
    local base_version = shape == "2.1" and "2.1.17" or "2.0.77"

    _G.storage = {}
    _G.event_handlers = {on_gui_click = {}, on_gui_confirmed = {}, on_gui_elem_changed = {}}
    _G.async_calls = nil
    _G.defines = {events = {on_player_created = "on_player_created", on_player_removed = "on_player_removed", on_gui_closed = "on_gui_closed",
        on_research_finished = "on_research_finished", on_gui_click = "on_gui_click", on_gui_elem_changed = "on_gui_elem_changed",
        on_gui_confirmed = "on_gui_confirmed", on_tick = "on_tick", on_runtime_mod_setting_changed = "on_runtime_mod_setting_changed"}}
    _G.helpers = H.lua_object("LuaHelpers", {compare_versions = compare_versions}, HELPERS_MEMBERS)
    _G.script = H.lua_object("LuaBootstrap", {
        active_mods = {base = base_version, RecursiveResourceCalculator = "1.1.10"},
        on_init = function(handler) world.handlers.on_init = handler end,
        on_configuration_changed = function(handler) world.handlers.on_configuration_changed = handler end,
        on_event = function(event, handler) world.handlers.events[event] = handler end,
    }, SCRIPT_MEMBERS)
    _G.settings = {get_player_settings = function() return {["hxrrc-displayed-floating-point-precision"] = {value = 12}} end}

    local machines = {}
    local modules = {}
    _G.prototypes = {
        recipe = {}, item = {}, fluid = {}, entity = {},
        get_entity_filtered = function() return machines end,
        get_item_filtered = function() return modules end,
    }
    _G.game = {players = {}, get_player = function(index) return game.players[index] end}

    function world.add_item(name)
        prototypes.item[name] = H.lua_object("LuaItemPrototype", {name = name, type = "item", valid = true, localised_name = {"item-name." .. name}}, ITEM_MEMBERS)
    end

    function world.add_module(name, category, module_effects)
        local module = H.lua_object("LuaItemPrototype", {name = name, type = "module", valid = true, localised_name = {"item-name." .. name},
            category = category, module_effects = module_effects}, ITEM_MEMBERS)
        prototypes.item[name] = module
        modules[name] = module
    end

    function world.remove_module(name)
        prototypes.item[name] = nil
        modules[name] = nil
    end

    function world.add_fluid(name)
        prototypes.fluid[name] = H.lua_object("LuaFluidPrototype", {name = name, valid = true, localised_name = {"fluid-name." .. name}}, FLUID_MEMBERS)
    end

    --spec: {name, categories, speed, energy_kw, pollution_per_minute, base_productivity, no_effect_receiver, speeds_by_quality}
    function world.add_machine(spec)
        local energy_usage = (spec.energy_kw or 210) * 1000 / 60 --joules per tick
        local pollution_per_second = (spec.pollution_per_minute or 4) / 60
        local categories = {}
        for _, category in ipairs(spec.categories) do categories[category] = true end
        local fields = {
            name = spec.name, type = "assembling-machine", valid = true, localised_name = {"entity-name." .. spec.name},
            crafting_categories = categories,
            energy_usage = energy_usage,
            allowed_effects = {consumption = true, speed = true, productivity = true, pollution = true, quality = true},
            get_crafting_speed = function(quality) return (spec.speeds_by_quality or {})[quality or "normal"] or spec.speed or 1 end,
            get_max_energy_usage = function() return energy_usage end,
            electric_energy_source_prototype = H.lua_object("LuaElectricEnergySourcePrototype",
                {emissions_per_joule = spec.emissions_per_joule or {pollution = pollution_per_second / (energy_usage * 60)}}, ENERGY_SOURCE_MEMBERS),
        }
        if not spec.no_effect_receiver then
            fields.effect_receiver = {base_effect = {productivity = spec.base_productivity}, uses_module_effects = true, uses_beacon_effects = true, uses_surface_effects = true}
        end
        local machine = H.lua_object("LuaEntityPrototype", fields, ENTITY_MEMBERS)
        prototypes.entity[spec.name] = machine
        machines[spec.name] = machine
    end

    --spec: {name, category, energy, ingredients = {{type, name, amount}}, products = {product specs}, maximum_productivity}
    function world.add_recipe(spec)
        local products = {}
        for index, product_spec in ipairs(spec.products) do products[index] = H.product(shape, product_spec) end
        local ingredients = {}
        for index, ingredient in ipairs(spec.ingredients) do
            ingredients[index] = {type = ingredient.type or "item", name = ingredient.name, amount = ingredient.amount}
        end
        local fields = {name = spec.name, valid = true, object_name = "LuaRecipePrototype", products = products, ingredients = ingredients,
            energy = spec.energy or 1, maximum_productivity = spec.maximum_productivity or 3}
        if shape == "2.1" then
            fields.categories = {spec.category}
        else
            fields.category = spec.category
            fields.additional_categories = {}
            if shape == "hybrid" then fields.categories = {spec.category} end
        end
        prototypes.recipe[spec.name] = H.lua_object("LuaRecipePrototype", fields, RECIPE_MEMBERS[shape])
    end

    function world.add_player(index, research_bonus_by_recipe_name)
        world.research_bonus_by_recipe_name = research_bonus_by_recipe_name or {}
        local force = H.lua_object("LuaForce", {name = "player", valid = true, recipes = {}, players = {}}, FORCE_MEMBERS)
        local player = H.lua_object("LuaPlayer", {
            index = index, name = "player" .. index, valid = true, force = force,
            gui = {screen = H.gui_root({type = "empty-widget", name = "screen"}, index)},
            create_local_flying_text = function(params) table.insert(world.flying_texts, params.text) end,
        }, PLAYER_MEMBERS)
        table.insert(force.players, player)
        game.players[index] = player
        return player
    end

    --Runs the mod's own indexing and per-player initialization over the fixture prototypes
    function world.init()
        for _, player in pairs(game.players) do
            for recipe_name, _ in pairs(prototypes.recipe) do
                player.force.recipes[recipe_name] = H.lua_object("LuaRecipe",
                    {name = recipe_name, valid = true, productivity_bonus = world.research_bonus_by_recipe_name[recipe_name] or 0}, FORCE_RECIPE_MEMBERS)
            end
        end
        require("logic.indexer").run()
        storage.computation_stack = {}
        for index, _ in pairs(game.players) do
            require("logic.player_data").initialize_player_data(index)
        end
    end

    function world.bind(product_full_name, recipe_name, player_index)
        local player_storage = storage[player_index or 1]
        player_storage.recipes_by_product_full_name[product_full_name] = prototypes.recipe[recipe_name]
        player_storage.product_full_names_by_recipe_name[recipe_name] = product_full_name
    end

    return world
end

--Builds a sheet, types the targets into it and presses Compute. targets: {{item, rate, unit = "/s" | "/m"}}
function H.run_sheet(targets, player_index)
    local Sheet = require "gui.sheet"
    local sheet_pane = H.gui_root({type = "tabbed-pane", name = "sheet_pane"}, player_index or 1)
    Sheet.new(sheet_pane)
    sheet_pane.selected_tab_index = 1
    local sheet_flow = sheet_pane.tabs[1].content
    for index, target in ipairs(targets) do
        local row = sheet_flow.input_container.children[index]
        row.rate_textfield.text = tostring(target.rate)
        row.time_unit_dropdown.selected_index = target.unit == "/m" and 1 or 2
        row.hxrrc_desired_item_button.elem_value = target.item
        event_handlers.on_gui_elem_changed["hxrrc_desired_item_button"]({element = row.hxrrc_desired_item_button, player_index = player_index or 1})
    end
    Sheet.calculate(sheet_flow.hxrrc_compute_button)
    return H.parse_report(sheet_flow.output_flow)
end

local function number_in(caption)
    return tonumber(caption:match("(-?[%d%.]+)"))
end

--Reads the report table back into {energy_mw, pollution_per_minute, rows = {[product_full_name] = {rate, machines, kind}}, row_count}
function H.parse_report(output_flow)
    local report
    for _, child in ipairs(output_flow.children) do
        if child.name == "report" then report = child end
    end
    if not report then return nil end
    local cells = report.children
    local parsed = {energy_mw = number_in(cells[2].caption), pollution_per_minute = number_in(cells[4].children[1].caption), rows = {}, row_count = 0}
    local HEADER_CELLS = 8
    assert((#cells - HEADER_CELLS) % 4 == 0, "report cell count " .. #cells .. " is not header + whole rows")
    for first = HEADER_CELLS + 1, #cells, 4 do
        local item_cell, machine_cell = cells[first], cells[first + 1]
        local product_full_name = item_cell.children[1].sprite
        local row = {rate = number_in(item_cell.children[2].caption)}
        if machine_cell.type == "flow" and machine_cell.children[1].name == "hxrrc_choose_crafting_machine_button" then
            row.kind = "solved"
            row.machines = number_in(machine_cell.children[2].caption)
            row.machine = machine_cell.children[1].elem_value
        else
            row.kind = machine_cell.caption[1]
        end
        assert(not parsed.rows[product_full_name], "report has two rows for " .. product_full_name)
        parsed.rows[product_full_name] = row
        parsed.row_count = parsed.row_count + 1
    end
    return parsed
end

local results = {passed = 0, failed = 0, names = {}}

function H.test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        results.passed = results.passed + 1
    else
        results.failed = results.failed + 1
        print("FAIL " .. name .. "\n  " .. tostring(err):gsub("\n", "\n  "))
    end
end

function H.near(actual, expected, what)
    if type(actual) ~= "number" or math.abs(actual - expected) > TOLERANCE then
        error(string.format("%s: expected %.12g, got %s", what, expected, tostring(actual)), 2)
    end
end

function H.equal(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
    end
end

function H.errors(fn, pattern, what)
    local ok, err = pcall(fn)
    if ok then error(what .. ": expected an error matching '" .. pattern .. "', got none", 2) end
    if not tostring(err):find(pattern, 1, true) then error(what .. ": error '" .. tostring(err) .. "' does not contain '" .. pattern .. "'", 2) end
end

--Shapes to run version-parametrized cases against; RRC_SHAPES overrides (e.g. "hybrid" for a red run on cb6b529)
function H.shapes()
    local shapes = {}
    for shape in (os.getenv("RRC_SHAPES") or "2.0,2.1"):gmatch("[^,]+") do shapes[#shapes + 1] = shape end
    return shapes
end

function H.done(file)
    print(string.format("%s [%s]: %d cases, %d passed, %d failed", file, _VERSION, results.passed + results.failed, results.passed, results.failed))
    os.exit(results.failed == 0 and 0 or 1)
end

return H
