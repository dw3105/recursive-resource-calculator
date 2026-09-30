-- Engine measured recipe to fluid box facts. This module contains no prototype names.
local BoxBinding = {}

local function safe(fn)
    local ok, value = pcall(fn)
    return ok and value or nil
end

local function name_of(value)
    if type(value) == "string" then return value end
    return safe(function() return value.name end)
end

local function prototype_boxes(machine)
    return safe(function() return machine.fluidbox_prototypes end) or {}
end

local function fluid_name(value)
    return name_of(value)
end

local function is_fluid_recipe(recipe)
    for _, list in ipairs({recipe.ingredients or {}, recipe.products or {}}) do
        for _, entry in ipairs(list) do if entry.type == "fluid" then return true end end
    end
    return false
end

function BoxBinding.probe(surface, machine_proto, recipe_proto)
    if not surface or not machine_proto or not recipe_proto then return {} end
    local machine_name, recipe_name = name_of(machine_proto), name_of(recipe_proto)
    if not machine_name or not recipe_name then return {} end
    local pos = {0, 0}
    local found = safe(function()
        if surface.find_non_colliding_position then
            return surface.find_non_colliding_position(machine_name, pos, 0, 1)
        end
    end)
    if found then pos = found end
    local entity = safe(function()
        return surface.create_entity{name = machine_name, position = pos, force = "neutral", recipe = recipe_name}
    end)
    if not entity then return {} end
    local result = {}
    local boxes = prototype_boxes(machine_proto)
    local count = #boxes
    for i = 1, count do
        local filter, box_proto
        local fluidbox = safe(function() return entity.fluidbox end)
        if fluidbox then
            filter = safe(function() return fluidbox.get_filter(i) end)
            box_proto = safe(function() return fluidbox.get_prototype(i) end)
        else
            filter = safe(function() return entity.get_fluid_filter(i) end)
            box_proto = safe(function() return entity.get_fluid_box_prototype(i) end)
        end
        local fluid = fluid_name(filter)
        if fluid then
            local index = safe(function() return box_proto.index end) or safe(function() return boxes[i].index end) or i
            local role = safe(function() return box_proto.production_type end) or safe(function() return boxes[i].production_type end)
            if role ~= "input" and role ~= "output" then role = "input" end
            if not result[fluid] or index < result[fluid].box then result[fluid] = {box = index, role = role} end
        end
    end
    safe(function() entity.destroy() end)
    return result
end

function BoxBinding.fill(catalog, steps, surface_provider)
    if type(catalog) ~= "table" or type(steps) ~= "table" or type(surface_provider) ~= "function" then return end
    local surface = safe(surface_provider)
    if not surface then return 0 end
    local seen = {}
    local probes = 0
    for _, step in ipairs(steps) do
        local machine = step.machine
        if type(machine) == "table" then machine = machine.name end
        local recipe = step.recipe_name or step.recipe
        if type(recipe) == "table" then recipe = recipe.name end
        local key = tostring(machine) .. "\0" .. tostring(recipe)
        local machine_proto = safe(function() return prototypes.entity[machine] end)
        local recipe_proto = safe(function() return prototypes.recipe[recipe] end)
        if machine and recipe and not seen[key] and machine_proto and recipe_proto and #prototype_boxes(machine_proto) > 0
            and is_fluid_recipe(recipe_proto) then
            seen[key] = true
            local binding = BoxBinding.probe(surface, machine_proto, recipe_proto)
            catalog.recipe = catalog.recipe or {}
            catalog.recipe[recipe] = catalog.recipe[recipe] or {}
            catalog.recipe[recipe].fluid_boxes = catalog.recipe[recipe].fluid_boxes or {}
            catalog.recipe[recipe].fluid_boxes[machine] = binding
            probes = probes + 1
        end
    end
    return probes
end

function BoxBinding.box_for(catalog, machine_name, recipe_name, fluid_name_value, role)
    local recipe = catalog and catalog.recipe and catalog.recipe[recipe_name]
    local machine = recipe and recipe.fluid_boxes and recipe.fluid_boxes[machine_name]
    local entry = machine and machine[fluid_name_value]
    if entry and (role == nil or entry.role == role) then return entry.box end
end

function BoxBinding.parse_fixture(text)
    local result, count = {recipe = {}}, 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local machine, recipe, fluid, role, box = line:match("^BIND%s+(%S+)%s+recipe=(%S+)%s+fluid=(%S+)%s+role=(%S+)%s+box=(%d+)")
        if machine then
            result.recipe[recipe] = result.recipe[recipe] or {fluid_boxes = {}}
            result.recipe[recipe].fluid_boxes[machine] = result.recipe[recipe].fluid_boxes[machine] or {}
            local bindings = result.recipe[recipe].fluid_boxes[machine]
            local previous = bindings[fluid]
            if not previous or tonumber(box) < previous.box then
                bindings[fluid] = {box = tonumber(box), role = role}
            end
            count = count + 1
        end
    end
    return result, count
end

return BoxBinding
