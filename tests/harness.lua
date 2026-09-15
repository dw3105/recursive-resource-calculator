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

--LuaObject: reading or writing a key outside its member list errors like the engine does.
--gates: member -> set of prototype types it can be used on; reading it unset on another type errors (conservative assumption, not established for every member)
function H.lua_object(class, fields, members, gates)
    local allowed = set_of(members)
    for key, _ in pairs(fields) do
        if not allowed[key] then error("fixture sets non-member " .. class .. "." .. key, 2) end
    end
    return setmetatable(fields, {
        __index = function(object, key)
            if allowed[key] then
                local types = gates and gates[key]
                if types and not types[rawget(object, "type")] then
                    error(class .. "::" .. key .. " can only be used if this is " .. types.names, 2)
                end
                return nil
            end
            error(class .. " doesn't contain key " .. tostring(key), 2)
        end,
        __newindex = function(object, key, value)
            if not allowed[key] then error(class .. " doesn't contain key " .. tostring(key), 2) end
            rawset(object, key, value)
        end,
    })
end

local RECIPE_MEMBERS = {
    ["2.0"] = {"name", "valid", "object_name", "hidden", "products", "ingredients", "energy", "allowed_effects", "allowed_module_categories", "maximum_productivity", "category", "additional_categories"},
    ["2.1"] = {"name", "valid", "object_name", "hidden", "products", "ingredients", "energy", "allowed_effects", "allowed_module_categories", "maximum_productivity", "categories", "get_product_amount"},
    --shape the code at cb6b529 expects: 2.1 recipe members with 2.0 product fields (portal 1.1.9 on Factorio 2.0.77)
    ["hybrid"] = {"name", "valid", "object_name", "products", "ingredients", "energy", "allowed_effects", "allowed_module_categories", "maximum_productivity", "category", "additional_categories", "categories"},
}

local ENTITY_MEMBERS = {"name", "type", "valid", "localised_name", "crafting_categories", "effect_receiver", "energy_usage", "allowed_effects",
    "get_crafting_speed", "get_max_energy_usage", "electric_energy_source_prototype", "burner_prototype", "heat_energy_source_prototype",
    "fluid_energy_source_prototype", "void_energy_source_prototype", "module_inventory_size", "get_inventory_size", "allowed_module_categories",
    "quality_affects_module_slots", "module_slots_quality_bonus", "distribution_effectivity", "distribution_effectivity_bonus_per_quality_level",
    "profile", "beacon_counter"}
local ITEM_MEMBERS = {"name", "type", "valid", "localised_name", "module_effects", "get_module_effects", "category"}
local QUALITY_MEMBERS = {"name", "valid", "level", "crafting_machine_module_slots_bonus", "beacon_module_slots_bonus", "beacon_power_usage_multiplier"}

local function gate(types)
    local set = set_of(types)
    set.names = table.concat(types, " or ")
    return set
end
local CRAFTING_MACHINE_TYPES = {"assembling-machine", "furnace", "rocket-silo"}
local ENTITY_GATES = {
    crafting_categories = gate(CRAFTING_MACHINE_TYPES),
    get_crafting_speed = gate(CRAFTING_MACHINE_TYPES),
    quality_affects_module_slots = gate({"beacon", "assembling-machine", "furnace", "rocket-silo", "mining-drill", "lab"}),
}
local ITEM_GATES = {module_effects = gate({"module"}), get_module_effects = gate({"module"}), category = gate({"module"})}

local EFFECT_NAMES = {"consumption", "speed", "productivity", "pollution", "quality"}

--dictionary[effect -> boolean] over all five effects from a list of allowed ones; nil list gives nil unless every effect is the default
local function effect_dictionary(list, all_by_default)
    if list == nil and not all_by_default then return nil end
    local allowed = set_of(list or EFFECT_NAMES)
    local dictionary = {}
    for _, effect in ipairs(EFFECT_NAMES) do dictionary[effect] = allowed[effect] == true end
    return dictionary
end

--Prototype-doc rule for module slots at a quality: base slots, plus, when quality affects slots, the entity's own bonus for that quality or else the quality's bonus
local function module_slots_at(base, affected, own_bonus_by_quality, quality_bonus_member, quality)
    if not affected or quality == nil then return base end
    local quality_prototype = prototypes.quality[quality]
    if not quality_prototype then error("Unknown quality " .. tostring(quality), 3) end
    local own = own_bonus_by_quality and own_bonus_by_quality[quality]
    if own ~= nil then return base + own end
    return base + quality_prototype[quality_bonus_member]
end
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
    "sprite", "valid", "auto_center", "state"})

local gui_methods = {}

--Values a player can change; kept out of the element table so every script write goes through __newindex
local VALUE_KEYS = {elem_value = true, text = true, state = true}

--Conservative assumption (not established for the engine): choose-elem-buttons refuse names of prototypes that do not exist
local function check_elem_value(element, value)
    if value == nil then return end
    local elem_type = rawget(element, "elem_type")
    if elem_type == "item" and not prototypes.item[value] then
        error("Unknown item " .. tostring(value), 3)
    elseif elem_type == "fluid" and not prototypes.fluid[value] then
        error("Unknown fluid " .. tostring(value), 3)
    elseif elem_type == "item-with-quality" and not prototypes.item[value.name] then
        error("Unknown item " .. tostring(value.name), 3)
    elseif elem_type == "item-with-quality" and value.quality and not prototypes.quality[value.quality] then
        error("Unknown quality " .. tostring(value.quality), 3)
    elseif elem_type == "entity-with-quality" and not prototypes.entity[value.name] then
        error("Unknown entity " .. tostring(value.name), 3)
    elseif elem_type == "entity-with-quality" and value.quality and not prototypes.quality[value.quality] then
        error("Unknown quality " .. tostring(value.quality), 3)
    end
end

--Filter names each choose-elem-button type accepts, from the 2.0.77 RecipePrototypeFilter, EntityPrototypeFilter and ItemPrototypeFilter pages (subset the mod uses)
local FILTER_NAMES_BY_ELEM_TYPE = {
    ["recipe"] = set_of({"has-product-item", "has-product-fluid", "has-ingredient-item", "has-ingredient-fluid", "hidden", "category"}),
    ["entity-with-quality"] = set_of({"crafting-category", "name"}),
    ["item-with-quality"] = set_of({"name"}),
}
--Nested item and fluid filters of has-product/has-ingredient filters match by name here
local NESTED_FILTER_ELEM_TYPE = {["has-product-item"] = "item", ["has-product-fluid"] = "fluid", ["has-ingredient-item"] = "item", ["has-ingredient-fluid"] = "fluid"}

local function check_elem_filters(params)
    if params.type ~= "choose-elem-button" or params.elem_filters == nil then return end
    local allowed = FILTER_NAMES_BY_ELEM_TYPE[params.elem_type]
    if not allowed then error("harness does not know filters for elem_type " .. tostring(params.elem_type), 3) end
    for _, filter in ipairs(params.elem_filters) do
        if not allowed[filter.filter] then
            error("Unknown " .. params.elem_type .. " filter " .. tostring(filter.filter), 3)
        end
        local nested = NESTED_FILTER_ELEM_TYPE[filter.filter]
        if nested then
            if type(filter.elem_filters) ~= "table" or #filter.elem_filters == 0 then
                error(filter.filter .. " filter needs nested elem_filters", 3)
            end
            for _, inner in ipairs(filter.elem_filters) do
                if inner.filter ~= "name" or not prototypes[nested][inner.name] then
                    error(filter.filter .. " filter names unknown " .. nested .. " " .. tostring(inner.name), 3)
                end
            end
        end
    end
end

local function normalize_value(key, value)
    if key == "text" and type(value) == "number" then return tostring(value) end
    return value
end

H.refire_on_script_set = false
local refire_depth = 0

--Re-fire mode: a script write raises the element's handler, as the engine might; a restore that is not idempotent then loops
local function refire(element, key)
    if not H.refire_on_script_set then return end
    local handlers = (key == "elem_value" and event_handlers.on_gui_elem_changed)
        or (key == "state" and event_handlers.on_gui_checked_state_changed)
        or event_handlers.on_gui_confirmed
    local handler = handlers[rawget(element, "name")]
    if not handler then return end
    refire_depth = refire_depth + 1
    if refire_depth > 5 then
        refire_depth = 0
        error("event re-fire loop", 3)
    end
    local ok, err = pcall(handler, {element = element, player_index = rawget(element, "player_index")})
    refire_depth = refire_depth - 1
    if not ok then error(err, 0) end
end

local function new_gui_element(params, parent, player_index)
    local element = {children = {}, style = {}, tabs = {}, valid = true, enabled = true, visible = true, tags = {}, _values = {}}
    for key, value in pairs(params) do
        if key ~= "index" and GUI_MEMBERS[key] and not VALUE_KEYS[key] then element[key] = value end
    end
    if params.enabled == false then element.enabled = false end
    if params.visible == false then element.visible = false end
    if params.elem_type then
        check_elem_value(element, params[params.elem_type])
        element._values.elem_value = params[params.elem_type]
    end
    element._values.text = normalize_value("text", params.text)
    element._values.state = params.state
    element.parent = parent
    element.player_index = parent and parent.player_index or player_index
    return setmetatable(element, {
        __index = function(self, key)
            if VALUE_KEYS[key] then return rawget(self, "_values")[key] end
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
            if VALUE_KEYS[key] then
                if key == "elem_value" then check_elem_value(self, value) end
                rawget(self, "_values")[key] = normalize_value(key, value)
                refire(self, key)
                return
            end
            if not GUI_MEMBERS[key] then error("LuaGuiElement doesn't contain key " .. tostring(key), 2) end
            rawset(self, key, value)
        end,
    })
end

function gui_methods.add(self, params)
    --the engine refuses a second child with the same name under one parent (Factorio 2.0.77: "Gui element with name X already present in the parent element.")
    if params.name and params.name ~= "" then
        for _, sibling in ipairs(self.children) do
            if sibling.name == params.name then
                error("Gui element with name " .. params.name .. " already present in the parent element.", 3)
            end
        end
    end
    --item and fluid sprites need their prototype (see LuaHelpers::is_valid_sprite_path)
    local sprite_type, sprite_name = tostring(params.sprite or ""):match("^(%a+)/(.+)$")
    if (sprite_type == "item" and not prototypes.item[sprite_name]) or (sprite_type == "fluid" and not prototypes.fluid[sprite_name]) then
        error("Unknown sprite " .. params.sprite, 3)
    end
    check_elem_filters(params)
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
    _G.event_handlers = {on_gui_click = {}, on_gui_confirmed = {}, on_gui_elem_changed = {}, on_gui_checked_state_changed = {}}
    _G.async_calls = nil
    _G.defines = {events = {on_player_created = "on_player_created", on_player_removed = "on_player_removed", on_gui_closed = "on_gui_closed",
        on_research_finished = "on_research_finished", on_gui_click = "on_gui_click", on_gui_elem_changed = "on_gui_elem_changed",
        on_gui_confirmed = "on_gui_confirmed", on_gui_checked_state_changed = "on_gui_checked_state_changed", on_tick = "on_tick",
        on_runtime_mod_setting_changed = "on_runtime_mod_setting_changed"},
        inventory = {beacon_modules = 1, crafter_modules = 4}}
    _G.helpers = H.lua_object("LuaHelpers", {compare_versions = compare_versions}, HELPERS_MEMBERS)
    _G.script = H.lua_object("LuaBootstrap", {
        active_mods = {base = base_version, ["RRC-Fork"] = "1.1.10"},
        mod_name = "RRC-Fork",
        on_init = function(handler) world.handlers.on_init = handler end,
        on_configuration_changed = function(handler) world.handlers.on_configuration_changed = handler end,
        on_event = function(event, handler) world.handlers.events[event] = handler end,
    }, SCRIPT_MEMBERS)
    _G.settings = {get_player_settings = function() return {["hxrrc-displayed-floating-point-precision"] = {value = 12}} end}

    local machines = {}
    local beacons = {}
    local modules = {}
    H.refire_on_script_set = false
    refire_depth = 0

    local qualities = {}
    for name, level in pairs({normal = 0, uncommon = 1, rare = 2, epic = 3, legendary = 5}) do
        qualities[name] = H.lua_object("LuaQualityPrototype", {name = name, valid = true, level = level, crafting_machine_module_slots_bonus = level,
            beacon_module_slots_bonus = level, beacon_power_usage_multiplier = 1}, QUALITY_MEMBERS)
    end

    _G.prototypes = {
        recipe = {}, item = {}, fluid = {}, entity = {},
        quality = qualities,
        get_entity_filtered = function(filters)
            local filter = filters[1]
            if filter.filter == "crafting-machine" then return machines end
            if filter.filter == "type" and filter.type == "beacon" then return beacons end
            error("harness does not support entity filter " .. tostring(filter.filter))
        end,
        get_item_filtered = function(filters)
            local filter = filters[1]
            if filter.filter == "type" and filter.type == "module" then return modules end
            error("harness does not support item filter " .. tostring(filter.filter))
        end,
    }
    _G.game = {players = {}, get_player = function(index) return game.players[index] end}

    function world.add_item(name)
        prototypes.item[name] = H.lua_object("LuaItemPrototype", {name = name, type = "item", valid = true, localised_name = {"item-name." .. name}}, ITEM_MEMBERS, ITEM_GATES)
    end

    --effects_by_quality: {[quality name] = effects} for qualities whose effects differ; the engine's scaling is not modelled, fixtures give values
    function world.add_module(name, category, module_effects, effects_by_quality)
        local module = H.lua_object("LuaItemPrototype", {name = name, type = "module", valid = true, localised_name = {"item-name." .. name},
            category = category, module_effects = module_effects,
            get_module_effects = function(quality)
                if quality ~= nil and not prototypes.quality[quality] then error("Unknown quality " .. tostring(quality), 2) end
                return (effects_by_quality and effects_by_quality[quality or "normal"]) or module_effects
            end}, ITEM_MEMBERS, ITEM_GATES)
        prototypes.item[name] = module
        modules[name] = module
    end

    --A mod swap turning a module into a plain item under the same name
    function world.replace_module_with_item(name)
        modules[name] = nil
        world.add_item(name)
    end

    function world.remove_module(name)
        prototypes.item[name] = nil
        modules[name] = nil
    end

    --A mod removing a recipe: the prototype object turns invalid and disappears from prototypes; its product item stays
    function world.remove_recipe(name)
        prototypes.recipe[name].valid = false
        prototypes.recipe[name] = nil
    end

    function world.remove_quality(name)
        prototypes.quality[name] = nil
    end

    --fields: LuaQualityPrototype members to change, e.g. {beacon_power_usage_multiplier = 2}
    function world.set_quality(name, fields)
        for key, value in pairs(fields) do prototypes.quality[name][key] = value end
    end

    function world.add_fluid(name)
        prototypes.fluid[name] = H.lua_object("LuaFluidPrototype", {name = name, valid = true, localised_name = {"fluid-name." .. name}}, FLUID_MEMBERS)
    end

    --spec: {name, type (default assembling-machine), categories, speed, energy_kw, pollution_per_minute, base_productivity, no_effect_receiver, speeds_by_quality,
    --  module_slots (default 4), quality_affects_module_slots, module_slots_quality_bonus, allowed_effects (list), allowed_module_categories (list),
    --  uses_module_effects, uses_beacon_effects}
    function world.add_machine(spec)
        local energy_usage = (spec.energy_kw or 210) * 1000 / 60 --joules per tick
        local pollution_per_second = (spec.pollution_per_minute or 4) / 60
        local categories = {}
        for _, category in ipairs(spec.categories) do categories[category] = true end
        local module_slots = spec.module_slots or 4
        local fields = {
            name = spec.name, type = spec.type or "assembling-machine", valid = true, localised_name = {"entity-name." .. spec.name},
            crafting_categories = categories,
            energy_usage = energy_usage,
            allowed_effects = effect_dictionary(spec.allowed_effects, true),
            allowed_module_categories = spec.allowed_module_categories and set_of(spec.allowed_module_categories),
            module_inventory_size = module_slots,
            quality_affects_module_slots = spec.quality_affects_module_slots,
            module_slots_quality_bonus = spec.module_slots_quality_bonus,
            get_inventory_size = function(index, quality)
                if index ~= defines.inventory.crafter_modules then return nil end
                return module_slots_at(module_slots, spec.quality_affects_module_slots, spec.module_slots_quality_bonus, "crafting_machine_module_slots_bonus", quality)
            end,
            get_crafting_speed = function(quality) return (spec.speeds_by_quality or {})[quality or "normal"] or spec.speed or 1 end,
            get_max_energy_usage = function() return energy_usage end,
            electric_energy_source_prototype = H.lua_object("LuaElectricEnergySourcePrototype",
                {emissions_per_joule = spec.emissions_per_joule or {pollution = pollution_per_second / (energy_usage * 60)}}, ENERGY_SOURCE_MEMBERS),
        }
        if not spec.no_effect_receiver then
            fields.effect_receiver = {base_effect = {productivity = spec.base_productivity}, uses_module_effects = spec.uses_module_effects ~= false,
                uses_beacon_effects = spec.uses_beacon_effects ~= false, uses_surface_effects = true}
        end
        local machine = H.lua_object("LuaEntityPrototype", fields, ENTITY_MEMBERS, ENTITY_GATES)
        prototypes.entity[spec.name] = machine
        machines[spec.name] = machine
    end

    --A mod swap turning a crafting machine into another entity type under the same name
    function world.replace_machine_with_entity(name, entity_type)
        machines[name] = nil
        prototypes.entity[name] = H.lua_object("LuaEntityPrototype",
            {name = name, type = entity_type, valid = true, localised_name = {"entity-name." .. name}}, ENTITY_MEMBERS, ENTITY_GATES)
    end

    function world.remove_machine(name)
        machines[name] = nil
        prototypes.entity[name] = nil
    end

    --spec: {name, module_slots (default 2), quality_affects_module_slots, energy_kw (default 480), distribution_effectivity (default 1.5),
    --  bonus_per_quality_level (default 0.2), profile (default none), beacon_counter (default "same_type"),
    --  allowed_effects (list, default consumption, speed, pollution), allowed_module_categories (list)}
    function world.add_beacon(spec)
        local module_slots = spec.module_slots or 2
        local beacon = H.lua_object("LuaEntityPrototype", {
            name = spec.name, type = "beacon", valid = true, localised_name = {"entity-name." .. spec.name},
            module_inventory_size = module_slots,
            quality_affects_module_slots = spec.quality_affects_module_slots,
            get_inventory_size = function(index, quality)
                if index ~= defines.inventory.beacon_modules then return nil end
                return module_slots_at(module_slots, spec.quality_affects_module_slots, nil, "beacon_module_slots_bonus", quality)
            end,
            energy_usage = (spec.energy_kw or 480) * 1000 / 60,
            distribution_effectivity = spec.distribution_effectivity == nil and 1.5 or spec.distribution_effectivity,
            distribution_effectivity_bonus_per_quality_level = spec.bonus_per_quality_level == nil and 0.2 or spec.bonus_per_quality_level,
            profile = spec.profile,
            beacon_counter = spec.beacon_counter or "same_type",
            allowed_effects = effect_dictionary(spec.allowed_effects or {"consumption", "speed", "pollution"}),
            allowed_module_categories = spec.allowed_module_categories and set_of(spec.allowed_module_categories),
        }, ENTITY_MEMBERS, ENTITY_GATES)
        prototypes.entity[spec.name] = beacon
        beacons[spec.name] = beacon
    end

    function world.remove_beacon(name)
        beacons[name] = nil
        prototypes.entity[name] = nil
    end

    --A mod swap turning a beacon into another entity type under the same name
    function world.replace_beacon_with_entity(name, entity_type)
        beacons[name] = nil
        prototypes.entity[name] = H.lua_object("LuaEntityPrototype",
            {name = name, type = entity_type, valid = true, localised_name = {"entity-name." .. name}}, ENTITY_MEMBERS, ENTITY_GATES)
    end

    --spec: {name, category, additional_categories, energy, ingredients = {{type, name, amount}}, products = {product specs}, maximum_productivity,
    --  allowed_effects (list), allowed_module_categories (list), hidden}
    function world.add_recipe(spec)
        local products = {}
        for index, product_spec in ipairs(spec.products) do products[index] = H.product(shape, product_spec) end
        local ingredients = {}
        for index, ingredient in ipairs(spec.ingredients) do
            ingredients[index] = {type = ingredient.type or "item", name = ingredient.name, amount = ingredient.amount}
        end
        local fields = {name = spec.name, valid = true, object_name = "LuaRecipePrototype", products = products, ingredients = ingredients,
            energy = spec.energy or 1, maximum_productivity = spec.maximum_productivity or 3, hidden = spec.hidden == true,
            allowed_effects = effect_dictionary(spec.allowed_effects), allowed_module_categories = spec.allowed_module_categories and set_of(spec.allowed_module_categories)}
        if shape == "2.1" then
            fields.categories = {spec.category, table.unpack(spec.additional_categories or {})}
        else
            fields.category = spec.category
            fields.additional_categories = spec.additional_categories or {}
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

    --One recipe serves one product, as the recipe button enforces; a fixture breaking that would test a state the mod never stores
    function world.bind(product_full_name, recipe_name, player_index)
        local player_storage = storage[player_index or 1]
        local bound_product = player_storage.product_full_names_by_recipe_name[recipe_name]
        if bound_product and bound_product ~= product_full_name then
            error("fixture binds recipe " .. recipe_name .. " to " .. product_full_name .. " while it serves " .. bound_product, 2)
        end
        player_storage.recipes_by_product_full_name[product_full_name] = prototypes.recipe[recipe_name]
        player_storage.product_full_names_by_recipe_name[recipe_name] = product_full_name
    end

    --Binds a product to a recipe that consumes it, as a pick from a consumer control stores it
    function world.bind_consumer(product_full_name, recipe_name, player_index)
        world.bind(product_full_name, recipe_name, player_index)
        storage[player_index or 1].consumer_product_full_names[product_full_name] = true
    end

    return world
end

--Builds a sheet and types the targets into it without computing. targets: {{item | fluid, rate, unit = "/s" | "/m"}}
function H.fill_sheet(targets, player_index)
    local Sheet = require "gui.sheet"
    local sheet_pane = H.gui_root({type = "tabbed-pane", name = "sheet_pane"}, player_index or 1)
    Sheet.new(sheet_pane)
    sheet_pane.selected_tab_index = 1
    local sheet_flow = sheet_pane.tabs[1].content
    for index, target in ipairs(targets) do
        local row = sheet_flow.input_container.children[index]
        row.rate_textfield.text = string.format("%.17g", target.rate) --17 significant digits round-trip a double; tostring keeps 14
        row.time_unit_dropdown.selected_index = target.unit == "/m" and 1 or 2
        local button_name = target.fluid and "hxrrc_desired_fluid_button" or "hxrrc_desired_item_button"
        row[button_name].elem_value = target.fluid or target.item
        event_handlers.on_gui_elem_changed[button_name]({element = row[button_name], player_index = player_index or 1})
    end
    return sheet_pane, sheet_flow
end

--Builds a sheet, types the targets into it and presses Compute. options: {round_up = true} ticks the sheet's round-up checkbox first
function H.run_sheet(targets, player_index, options)
    local sheet_pane, sheet_flow = H.fill_sheet(targets, player_index)
    if options and options.round_up then
        sheet_flow.hxrrc_round_up_machines_checkbox.state = true
    end
    require("gui.sheet").calculate(sheet_flow.hxrrc_compute_button)
    return H.parse_report(sheet_flow.output_flow), sheet_pane
end

local function number_in(caption)
    return tonumber(caption:match("(-?[%d%.]+)"))
end

--Localised captions read back as their key, plain captions as themselves
local function caption_key(caption)
    return type(caption) == "table" and caption[1] or caption
end

--Reads the report table back into {energy_mw, pollution_per_minute, energy_caption, pollution_caption, rows = {[product_full_name] = row}, row_count}.
--row: {rate, kind, machines, machine_caption, machine_tooltip, machine, machine_button, reason, module_cell, recipe_button}; numbers are nil where the report shows none
function H.parse_report(output_flow)
    local report
    for _, child in ipairs(output_flow.children) do
        if child.name == "report" then report = child end
    end
    if not report then return nil end
    local cells = report.children
    local energy_caption, pollution_caption = cells[2].caption, cells[4].children[1].caption
    local parsed = {energy_caption = caption_key(energy_caption), pollution_caption = caption_key(pollution_caption), rows = {}, row_count = 0}
    parsed.energy_mw = type(energy_caption) == "string" and number_in(energy_caption) or nil
    parsed.pollution_per_minute = type(pollution_caption) == "string" and number_in(pollution_caption) or nil
    local HEADER_CELLS = 8
    assert((#cells - HEADER_CELLS) % 4 == 0, "report cell count " .. #cells .. " is not header + whole rows")
    for first = HEADER_CELLS + 1, #cells, 4 do
        local item_cell, machine_cell, recipe_cell = cells[first], cells[first + 1], cells[first + 3]
        local product_full_name = item_cell.children[1].sprite
        local rate_caption = item_cell.children[2].caption
        local row = {rate = type(rate_caption) == "string" and number_in(rate_caption) or nil}
        if machine_cell.type == "flow" and machine_cell.children[1].name == "hxrrc_choose_crafting_machine_button" then
            row.kind = "solved"
            local label = machine_cell.children[2]
            if type(label.caption) == "table" then
                row.reason = label.caption[1]
            else
                row.machines = number_in(label.caption)
            end
            row.machine_caption = label.caption
            row.machine_tooltip = label.tooltip
            row.machine = machine_cell.children[1].elem_value
            row.machine_button = machine_cell.children[1]
            row.module_cell = cells[first + 2]
        else
            row.kind = machine_cell.caption[1]
            if row.kind ~= "hxrrc.byproduct" and row.kind ~= "hxrrc.unselected_recipe" and row.kind ~= "hxrrc.not_automatically_craftable" then
                row.reason = row.kind
            end
        end
        row.recipe_button = recipe_cell.type == "flow" and recipe_cell.children[1] or nil
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

--NaN compares false with everything, so a plain tolerance check would let it pass
local function check_finite(actual, what)
    if type(actual) ~= "number" or actual ~= actual or actual == math.huge or actual == -math.huge then
        error(string.format("%s: expected a finite number, got %s", what, tostring(actual)), 3)
    end
end

function H.near(actual, expected, what)
    check_finite(actual, what)
    if math.abs(actual - expected) > TOLERANCE then
        error(string.format("%s: expected %.12g, got %s", what, expected, tostring(actual)), 2)
    end
end

--Relative tolerance for large magnitudes, where one unit of rounding already exceeds the absolute tolerance
function H.near_relative(actual, expected, what)
    check_finite(actual, what)
    if math.abs(actual - expected) > TOLERANCE * math.max(1, math.abs(expected)) then
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
