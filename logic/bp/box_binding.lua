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

--2.0 get_filter -> {name = ...}; 2.1 get_fluid_filter -> {fluid = <name or prototype>} (headless 2.1.20, 2026-09-30:
--reading only .name bound nothing on 2.1).
local function fluid_name(value)
    if type(value) == "string" then return value end
    local direct = safe(function() return value.name end)
    if type(direct) == "string" then return direct end
    local fluid = safe(function() return value.fluid end)
    return name_of(fluid)
end

local function is_fluid_recipe(recipe)
    for _, list in ipairs({recipe.ingredients or {}, recipe.products or {}}) do
        for _, entry in ipairs(list) do if entry.type == "fluid" then return true end end
    end
    return false
end

--Record fluid -> prototype box; entry.box = lowest index, entry.boxes = every bound index, ascending.
function BoxBinding._add(bindings, fluid, index, role)
    local entry = bindings[fluid]
    if not entry then entry = {box = index, boxes = {}, role = role}; bindings[fluid] = entry end
    for _, known in ipairs(entry.boxes) do if known == index then return entry end end
    entry.boxes[#entry.boxes + 1] = index
    table.sort(entry.boxes)
    entry.box = entry.boxes[1]
    return entry
end

function BoxBinding.probe(surface, machine_proto, recipe_proto)
    if not surface or not machine_proto or not recipe_proto then return {} end
    local machine_name, recipe_name = name_of(machine_proto), name_of(recipe_proto)
    if not machine_name or not recipe_name then return {} end
    --Fixed spots, never find_non_colliding_position: radius 0 means an unlimited search, and it hung headless 2.0.77
    --and 2.1.20 for 300 s (integrator, 2026-09-30); the in-game path would freeze the game the same way.
    local entity
    for _, spot in ipairs({{0, 0}, {16, 0}, {0, 16}, {16, 16}, {-16, 0}, {0, -16}}) do
        entity = safe(function()
            return surface.create_entity{name = machine_name, position = spot, force = "neutral", recipe = recipe_name}
        end)
        if entity then break end
    end
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
            --A runtime box may merge several prototype boxes (foundry casting-iron: one fluid, conns=2, headless
            --2.0.77 + 2.1.20, 2026-09-30); get_prototype then returns an ARRAY. Keep every prototype index.
            local protos = box_proto
            if type(protos) == "table" and protos.index == nil and protos[1] ~= nil then protos = protos
            else protos = {box_proto} end
            for _, proto in ipairs(protos) do
                local index = safe(function() return proto.index end) or safe(function() return boxes[i].index end) or i
                local role = safe(function() return proto.production_type end) or safe(function() return boxes[i].production_type end)
                if role ~= "input" and role ~= "output" and role ~= "input-output" then role = "input" end
                BoxBinding._add(result, fluid, index, role)
            end
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
    if entry and (role == nil or entry.role == role or entry.role == "input-output") then return entry.box end
end

--Every prototype box the engine binds the fluid to (a merged runtime box spans several), or nil when unknown.
function BoxBinding.boxes_for(catalog, machine_name, recipe_name, fluid_name_value, role)
    local recipe = catalog and catalog.recipe and catalog.recipe[recipe_name]
    local machine = recipe and recipe.fluid_boxes and recipe.fluid_boxes[machine_name]
    local entry = machine and machine[fluid_name_value]
    if entry and (role == nil or entry.role == role or entry.role == "input-output") then return entry.boxes or {entry.box} end
end

function BoxBinding.parse_fixture(text)
    if type(text) == "string" and not text:find("\n", 1, true) and not text:match("^%s*BIND") then
        local file = io.open(text, "r")
        if file then text = file:read("*a"); file:close() end
    end
    local result, count = {recipe = {}}, 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local machine, recipe, fluid, role, box = line:match("^BIND%s+(%S+)%s+recipe=(%S+)%s+fluid=(%S+)%s+role=(%S+)%s+box=(%d+)")
        if machine then
            result.recipe[recipe] = result.recipe[recipe] or {fluid_boxes = {}}
            result.recipe[recipe].fluid_boxes[machine] = result.recipe[recipe].fluid_boxes[machine] or {}
            BoxBinding._add(result.recipe[recipe].fluid_boxes[machine], fluid, tonumber(box), role)
            count = count + 1
        end
    end
    return result, count
end

-- Add the measured engine facts to an offline PreparedInput. Existing bindings are
-- authoritative: a catalog with any binding is treated as already engine-bound.
function BoxBinding.apply_offline(prepared, version)
    if os.getenv("RRC_BIND") == "0" or type(prepared) ~= "table" then return prepared end
    if type(prepared.prepared_input) == "table" then prepared = prepared.prepared_input end
    local catalog = prepared.catalog
    if type(catalog) ~= "table" or type(catalog.recipe) ~= "table" or type(catalog.entity) ~= "table" then return prepared end
    for _, recipe in pairs(catalog.recipe) do
        if type(recipe) == "table" and type(recipe.fluid_boxes) == "table" and next(recipe.fluid_boxes) then return prepared end
    end
    version = version == "2.1" and "2.1" or "2.0"
    local file = assert(io.open("tests/fixtures/box_binding_" .. version .. ".txt", "r"))
    local fixture = file:read("*a"); file:close()
    local bindings = BoxBinding.parse_fixture(fixture).recipe
    for recipe_name, machines in pairs(bindings) do
        local recipe = catalog.recipe[recipe_name]
        if recipe then
            for machine, fluids in pairs(machines.fluid_boxes) do
                if catalog.entity[machine] then
                    recipe.fluid_boxes = recipe.fluid_boxes or {}
                    recipe.fluid_boxes[machine] = fluids
                end
            end
        end
    end
    return prepared
end

--Scratch surface for the in-game probe: created once per fill by name, deleted after (generation.lua).
BoxBinding.SURFACE = "rrc-box-binding"
function BoxBinding.scratch_surface(g)
    if type(g) ~= "table" and type(g) ~= "userdata" then return nil end
    local ok, surface = pcall(function()
        return g.surfaces[BoxBinding.SURFACE] or g.create_surface(BoxBinding.SURFACE, {width = 256, height = 256})
    end)
    return ok and surface or nil
end

return BoxBinding
