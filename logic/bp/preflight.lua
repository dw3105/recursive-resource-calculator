--What this release refuses to generate, decided before any layout work starts.
--
--Owned by lane W2-preflight. Every reason is reported at once rather than the first one found, so a player fixes
--one sheet instead of discovering one blocker per attempt, and each names the recipe, machine or product at
--fault plus what to change. Codes come from logic/bp/reason_codes.lua; messages are locale keys.
--
--An unsupported choice that is inactive or running at zero rate does not block an otherwise supported sheet.
--Nothing here is a claim about what is impossible: it is what this version can model.
local ReasonCodes = require "logic.bp.reason_codes"
local QualityPolicy = require "logic.bp.quality_policy"

local Preflight = {}

Preflight.MAX_MACHINES = 100
Preflight.MAX_STEPS = 30

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function name_of(value, fallback)
    if value == nil then return fallback end
    if type(value) == "string" or type(value) == "number" then return tostring(value) end
    if type(value) == "table" then
        return value.name or value.full_name or value.recipe_name or value.machine_name or value.id or fallback
    end
    local ok, name = pcall(function() return value.name end)
    return ok and name or fallback
end

local function quality_of(value)
    return type(value) == "table" and (name_of(value.quality, "normal") or "normal") or "normal"
end

local function split_full_name(value)
    if type(value) ~= "string" then return nil, nil end
    return value:match("^([^/]+)/(.+)$")
end

local function make_subject(kind, value, quality)
    local name = name_of(value, kind)
    if type(value) == "table" then quality = quality or value.quality end
    local full_kind, bare_name = split_full_name(name)
    if kind == "product" and full_kind then name = bare_name end
    return {kind = kind, name = name or kind, quality = quality or "normal"}
end

local function values(value)
    if type(value) ~= "table" then return {} end
    local result = {}
    if #value > 0 then
        for _, item in ipairs(value) do result[#result + 1] = item end
    else
        local keys = {}
        for key, _ in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do result[#result + 1] = value[key] end
    end
    return result
end

local function lookup(map, name, quality)
    if type(map) ~= "table" then return nil end
    if map[name] ~= nil then return map[name] end
    if quality and map[name .. "@" .. quality] ~= nil then return map[name .. "@" .. quality] end
    if quality and map[name .. "/" .. quality] ~= nil then return map[name .. "/" .. quality] end
    return nil
end

local function entity_of(catalog, machine, quality)
    local name = name_of(machine)
    return lookup(catalog and (catalog.entity or catalog.entities), name, quality)
        or lookup(catalog and catalog.machine, name, quality)
end

local function item_of(catalog, name)
    return lookup(catalog and (catalog.item or catalog.items), name)
end

local function recipe_of(catalog, column)
    if type(column) ~= "table" then return nil end
    return column.recipe or column.recipe_prototype or column.recipe_data
        or lookup(catalog and (catalog.recipe or catalog.recipes), column.recipe_name or column.name)
        or lookup(catalog and catalog.recipe_by_name, column.recipe_name or column.name)
end

local function recipe_name(column)
    return name_of(column and (column.recipe_name or column.name or column.recipe), "recipe")
end

local function machine_of(column, entry)
    if type(column) == "table" then
        if column.machine ~= nil then return column.machine end
        if column.machine_identifier ~= nil then return column.machine_identifier end
        if column.machine_name ~= nil then return {name = column.machine_name, quality = column.machine_quality} end
    end
    return type(entry) == "table" and entry.machine or nil
end

local function setup_of(column, entry)
    if type(column) == "table" and column.setup then return column.setup end
    if type(entry) == "table" and entry.setup then return entry.setup end
    if type(column) == "table" and (column.modules or column.beacons) then
        return {modules = column.modules, beacons = column.beacons}
    end
    if type(entry) == "table" and (entry.modules or entry.beacons) then
        return {modules = entry.modules, beacons = entry.beacons}
    end
    return {modules = {}, beacons = {}}
end

local function modules_of(setup)
    return values(setup and setup.modules)
end

local function beacons_of(setup)
    return values(setup and setup.beacons)
end

local function module_count(modules)
    local count = 0
    for _, module in ipairs(modules) do
        if module ~= nil then
            local amount = tonumber(type(module) == "table" and module.count or nil) or 1
            if amount > 0 then count = count + amount end
        end
    end
    return count
end

local function rate_of(column, result)
    local key = column and (column.recipe_name or column.name)
    local rates = result and (result.recipe_rates or result.rates)
    if type(rates) == "table" and key ~= nil and rates[key] ~= nil then return rates[key] end
    return column and (column.rate_per_second or column.crafts_per_second_total or column.rate)
end

local function active(column, result)
    if type(column) ~= "table" or column.active == false then return false end
    local rate = rate_of(column, result)
    if rate ~= nil then return rate ~= 0 end
    return column.rate ~= 0 and column.rate_per_second ~= 0 and column.crafts_per_second_total ~= 0
end

local function columns_of(result)
    return values(result and (result.columns or result.steps))
end

local function add(reasons, seen, code, value, kind, detail, quality)
    local item = make_subject(kind, value, quality)
    local key = code .. "\0" .. item.kind .. "\0" .. item.name .. "\0" .. item.quality
    if seen[key] then return end
    seen[key] = true
    reasons[#reasons + 1] = {code = code, subject = item, detail = detail or "", locale_key = ReasonCodes.locale_key(code)}
end

local function diagnostic_reasons(reasons, seen, diagnostics)
    for _, diagnostic in ipairs(values(diagnostics)) do
        if type(diagnostic) == "table" then
            local subject = diagnostic.subject or diagnostic.name or "prototype"
            local kind, name = type(subject) == "string" and subject:match("^([^/]+)/(.+)$")
            if diagnostic.code == "CATALOG_MISSING_QUALITY" then
                add(reasons, seen, "BP_REJ_QUALITY_UNAVAILABLE", name or subject, "quality", diagnostic.detail, name or subject)
            elseif diagnostic.code == "CATALOG_MISSING_PROTOTYPE" or diagnostic.unresolved then
                add(reasons, seen, "BP_REJ_UNRESOLVED_PROTOTYPE", name or subject, kind or "prototype", diagnostic.detail)
            end
        end
    end
end

local function explicit_values(value)
    if value == nil or value == false then return {} end
    return type(value) == "string" and {value} or values(value)
end

local function count_machines(result)
    for _, key in ipairs({"machine_count", "machines", "machine_count_total", "total_machines"}) do
        if type(result[key]) == "number" then return result[key] end
    end
    local total, known = 0, false
    for _, column in ipairs(columns_of(result)) do
        local count = column.machine_count or column.machines
        if type(count) == "number" then total, known = total + count, true end
    end
    return known and total or nil
end

local function count_steps(result)
    for _, key in ipairs({"step_count", "production_step_count", "total_steps"}) do
        if type(result[key]) == "number" then return result[key] end
    end
    local count = 0
    for _, column in ipairs(columns_of(result)) do
        if column.burner == nil and active(column, result) then count = count + 1 end
    end
    return count
end

local function item_spoils(catalog, product, full_name)
    local data = item_of(catalog, product and product.name or full_name) or product
    return data and (data.spoil_result ~= nil or data.spoils == true or data.spoilage ~= nil)
end

local function product_reasons(reasons, seen, catalog, recipe, active_step, recipe_id)
    if not active_step then return end
    recipe_id = recipe_id or name_of(recipe and recipe.name, "recipe")
    local missing = {}
    local missing_seen = {}
    local function require_field(field)
        if not missing_seen[field] then
            missing_seen[field] = true
            missing[#missing + 1] = field
        end
    end
    if type(recipe) ~= "table" then
        require_field("recipe")
    else
        if type(recipe.ingredients) ~= "table" then require_field("ingredients") end
        local products = recipe.products
        if type(products) ~= "table" then
            require_field("products")
        else
            local entries = values(products)
            if #entries == 0 then
                require_field("products (at least one product)")
            else
                for index, product in ipairs(entries) do
                    local prefix = "products[" .. tostring(index) .. "]"
                    if type(product) ~= "table" then
                        require_field(prefix .. ".name")
                        require_field(prefix .. ".type")
                        require_field(prefix .. ".amount")
                    else
                        if product.name == nil then require_field(prefix .. ".name") end
                        if product.type == nil then require_field(prefix .. ".type") end
                        if product.amount == nil and product.amount_min == nil and product.amount_max == nil then
                            require_field(prefix .. ".amount")
                        end
                    end
                end
            end
        end

        --A producer's declaration is additional evidence. Optional fields such as probability are deliberately
        --not in this set, so their engine defaults remain valid when absent.
        local declared = type(recipe.facts) == "table" and recipe.facts.missing
        if type(declared) == "table" then
            for key, value in pairs(declared) do
                local field = type(key) == "number" and value or key
                if value ~= false and type(field) == "string"
                    and (field == "ingredients" or field == "products"
                        or field:match("^products[%.%[]") or field:match("^product[%.%[]")) then
                    require_field(field)
                end
            end
        end
    end
    if #missing > 0 then
        table.sort(missing)
        add(reasons, seen, "BP_REJ_PROTOTYPE_FACTS_MISSING", recipe_id, "recipe",
            recipe_id .. " is missing prototype facts: " .. table.concat(missing, ", "))
        return
    end
    for _, ingredient in ipairs(values(recipe.ingredients or recipe.input)) do
        if type(ingredient) == "table" and ingredient.type ~= "fluid" and item_spoils(catalog, ingredient) then
            local full_name = ingredient.full_name or ((ingredient.type or "item") .. "/" .. tostring(ingredient.name))
            add(reasons, seen, "BP_REJ_SPOILAGE", full_name, "product",
                full_name .. " spoils and cannot be modelled")
        end
    end
    for _, product in ipairs(values(recipe.products)) do
        if type(product) == "table" then
            local full_name = product.full_name or (product.type and product.name and product.type .. "/" .. product.name)
            local product_catalog = catalog.product or catalog.products
            local data = (product_catalog and full_name and product_catalog[full_name]) or product
            local probability = data.probability
            if probability == nil then
                probability = (data.independent_probability or 1)
                    * ((data.shared_probability and (data.shared_probability.max - data.shared_probability.min)) or 1)
            end
            if type(probability) == "number" and probability < 1 then
                add(reasons, seen, "BP_REJ_PROBABILISTIC", full_name or product.name, "product",
                    tostring(full_name or product.name) .. " has a probabilistic product")
            end
            local minimum = data.amount_min or data.amount
            local maximum = data.amount_max or data.amount
            if (data.extra_count_fraction ~= nil and data.extra_count_fraction ~= 0)
                or (minimum ~= nil and maximum ~= nil and minimum ~= maximum) then
                add(reasons, seen, "BP_REJ_RANDOM_AMOUNT", full_name or product.name, "product",
                    tostring(full_name or product.name) .. " produces a random amount")
            end
            if data.type ~= "fluid" and item_spoils(catalog, data, full_name) then
                add(reasons, seen, "BP_REJ_SPOILAGE", full_name or product.name, "product",
                    tostring(full_name or product.name) .. " spoils and cannot be modelled")
            end
        end
    end
end

local function quality_unlocked(options, snapshot, catalog, quality)
    if quality == nil or quality == "normal" then return true end
    for _, map in ipairs({options.unlocked_qualities, snapshot.unlocked_qualities, catalog.unlocked_qualities}) do
        if type(map) == "table" then
            if map[quality] ~= nil then return map[quality] == true end
            for _, value in ipairs(values(map)) do
                if name_of(value) == quality then return true end
            end
            return false
        end
    end
    local quality_data = catalog.quality and catalog.quality[quality]
    if type(quality_data) == "table" then
        if quality_data.unlocked ~= nil then return quality_data.unlocked == true end
        if quality_data.available ~= nil then return quality_data.available == true end
    end
    local players = rawget(_G, "game") and game.players
    local player = players and snapshot.player_index and players[snapshot.player_index]
    local force = player and player.force
    if force and type(force.is_quality_unlocked) == "function" then
        local ok, result = pcall(force.is_quality_unlocked, force, quality)
        if ok then return result == true end
    end
    return true
end

local function quality_reasons(reasons, seen, snapshot, catalog, options, column, entry, is_active)
    if not is_active then return end
    local machine = machine_of(column, entry)
    local machine_quality = quality_of(machine)
    if machine_quality ~= "normal" and not quality_unlocked(options, snapshot, catalog, machine_quality) then
        add(reasons, seen, "BP_REJ_QUALITY_UNAVAILABLE", machine_quality, "quality",
            "quality " .. machine_quality .. " is not unlocked", machine_quality)
    end
    local setup = setup_of(column, entry)
    for _, module in ipairs(modules_of(setup)) do
        local quality = quality_of(module)
        if quality ~= "normal" and not quality_unlocked(options, snapshot, catalog, quality) then
            add(reasons, seen, "BP_REJ_QUALITY_UNAVAILABLE", quality, "quality",
                "quality " .. quality .. " is not unlocked", quality)
        end
    end
    for _, group in ipairs(beacons_of(setup)) do
        local quality = quality_of(group)
        if quality ~= "normal" and not quality_unlocked(options, snapshot, catalog, quality) then
            add(reasons, seen, "BP_REJ_QUALITY_UNAVAILABLE", quality, "quality",
                "quality " .. quality .. " is not unlocked", quality)
        end
        for _, module in ipairs(values(group.modules)) do
            local module_quality = quality_of(module)
            if module_quality ~= "normal" and not quality_unlocked(options, snapshot, catalog, module_quality) then
                add(reasons, seen, "BP_REJ_QUALITY_UNAVAILABLE", module_quality, "quality",
                    "quality " .. module_quality .. " is not unlocked", module_quality)
            end
        end
    end
end

local function entity_reasons(reasons, seen, snapshot, catalog, options, column, entry, is_active)
    if not is_active then return end
    local machine = machine_of(column, entry)
    if not machine then
        add(reasons, seen, "BP_REJ_HANDCRAFT", recipe_name(column), "recipe",
            recipe_name(column) .. " has no machine")
        return
    end
    local machine_name, machine_quality = name_of(machine, "machine"), quality_of(machine)
    local entity = entity_of(catalog, machine, machine_quality)
    if not entity and (catalog.entity or catalog.entities or catalog.machine) then
        add(reasons, seen, "BP_REJ_UNRESOLVED_PROTOTYPE", machine_name, "machine",
            machine_name .. " no longer resolves", machine_quality)
        return
    end
    entity = entity or machine
    local entity_type = entity.etype or entity.type
    if entity_type == "mining-drill" or entity.mining == true or entity.is_mining == true then
        add(reasons, seen, "BP_REJ_MINING", machine_name, "machine", machine_name .. " is a mining machine", machine_quality)
    end
    local burner = entity.burner == true or entity.burner_prototype ~= nil
        or entity.energy_source_type == "burner" or entity.energy_source == "burner"
    if burner then
        add(reasons, seen, "BP_REJ_BURNER_MACHINE", machine_name, "machine", machine_name .. " uses a burner", machine_quality)
    end
    local source = entity.energy_source_type or entity.energy_source
    if entity.non_electric == true or entity.is_electric == false or entity.electric == false
        or (source ~= nil and source ~= "electric" and source ~= "electric-energy-source") then
        add(reasons, seen, "BP_REJ_NON_ELECTRIC", machine_name, "machine", machine_name .. " is not electric", machine_quality)
    end
    if entity.unsupported_geometry == true or entity.geometry_supported == false then
        add(reasons, seen, "BP_REJ_UNSUPPORTED_GEOMETRY", machine_name, "machine",
            machine_name .. " has unsupported geometry", machine_quality)
    end
    if entity.unsupported_interface == true or entity.interface_supported == false then
        add(reasons, seen, "BP_REJ_UNSUPPORTED_INTERFACE", machine_name, "machine",
            machine_name .. " has an unsupported interface", machine_quality)
    end
    if entity.unsupported_fluidbox == true or entity.fluidbox_supported == false then
        add(reasons, seen, "BP_REJ_UNSUPPORTED_FLUIDBOX", machine_name, "machine",
            machine_name .. " has an unsupported fluidbox", machine_quality)
    elseif entity.fluid_boxes then
        for _, box in ipairs(values(entity.fluid_boxes)) do
            for _, connection in ipairs(values(box.connections)) do
                if connection.connection_type ~= nil and connection.connection_type ~= "normal"
                    and connection.connection_type ~= "underground" then
                    add(reasons, seen, "BP_REJ_UNSUPPORTED_FLUIDBOX", machine_name, "machine",
                        machine_name .. " has an unsupported fluid connection", machine_quality)
                elseif connection.positions ~= nil and #values(connection.positions) == 0 then
                    add(reasons, seen, "BP_REJ_UNSUPPORTED_FLUIDBOX", machine_name, "machine",
                        machine_name .. " has an unreadable fluid connection", machine_quality)
                end
            end
        end
    end

    local setup = setup_of(column, entry)
    local modules = modules_of(setup)
    local slots = entity.module_slots
    if type(slots) == "number" and module_count(modules) > slots then
        add(reasons, seen, "BP_REJ_MODULE_SLOTS_EXCEEDED", machine_name, "machine",
            machine_name .. " has " .. module_count(modules) .. " modules but only " .. slots .. " slots", machine_quality)
    end
    for _, group in ipairs(beacons_of(setup)) do
        local beacon_name = name_of(group.name or group.type)
        local beacon = beacon_name and entity_of(catalog, {name = beacon_name, quality = quality_of(group)}, quality_of(group))
        if beacon and type(beacon.module_slots) == "number" and module_count(values(group.modules)) > beacon.module_slots then
            add(reasons, seen, "BP_REJ_MODULE_SLOTS_EXCEEDED", beacon_name, "machine",
                beacon_name .. " has too many modules", quality_of(group))
        end
    end

    --Quality and receiver semantics belong to the shared policy. Build the policy step from the resolved setup
    --because preflight columns store modules and beacons under setup while the policy consumes a production step.
    local quality_step = {}
    for key, value in pairs(column) do quality_step[key] = value end
    quality_step.machine = machine
    quality_step.recipe = column.recipe or recipe_of(catalog, column)
    quality_step.modules = setup.modules or {}
    quality_step.beacons = setup.beacons or {}
    local effective_quality, supported, quality_reason = QualityPolicy.effective_quality(quality_step, catalog)
    local has_quality = QualityPolicy.has_active_quality_module(quality_step, catalog)
    local speed_beacon = QualityPolicy.speed_beacon_contribution(quality_step, catalog)
    local receiver = QualityPolicy.receiver(quality_step, catalog)
    if not supported then
        local code = receiver.status == "missing" and "BP_REJ_PROTOTYPE_FACTS_MISSING"
            or "BP_REJ_UNSUPPORTED_INTERFACE"
        add(reasons, seen, code, machine_name, "machine",
            machine_name .. " " .. tostring(quality_reason or receiver.reason or "receiver facts are unsupported"), machine_quality)
    end
    if effective_quality > 0 then
        add(reasons, seen, "BP_REJ_QUALITY_CHANGING", machine_name, "machine",
            machine_name .. " changes product quality", machine_quality)
    end
    if has_quality and speed_beacon > 0 then
        add(reasons, seen, "BP_REJ_BEACON_SPEED_ON_QUALITY", machine_name, "machine",
            machine_name .. " has quality modules and speed beacons", machine_quality)
    end
    quality_reasons(reasons, seen, snapshot, catalog, options, column, entry, true)
end

local function solver_reasons(reasons, seen, result)
    local function quality_loop_reason(reason)
        return type(reason) == "string" and reason:find("quality_loop", 1, true) ~= nil
    end
    local function cycle_reason(reason)
        return type(reason) == "string" and (reason == "cycle" or reason == "cyclic"
            or reason == "dependency_cycle" or reason:find("dependency_cycle", 1, true) ~= nil)
    end
    local columns_by_name = {}
    for _, column in ipairs(columns_of(result)) do
        columns_by_name[recipe_name(column)] = column
        local quality_loop = column.quality_loop
        local reason = quality_loop and quality_loop.reason
        if active(column, result) and (quality_loop or quality_loop_reason(reason)) then
            local value = quality_loop and (quality_loop.item or quality_loop.key) or recipe_name(column)
            add(reasons, seen, "BP_REJ_QUALITY_LOOP", value, "recipe",
                "quality loop on " .. name_of(value, recipe_name(column)))
        elseif active(column, result) and cycle_reason(reason) then
            add(reasons, seen, "BP_REJ_CYCLE", recipe_name(column), "recipe",
                recipe_name(column) .. " is part of a dependency cycle")
        end
    end
    for column_name, reason in pairs(result.reasons_by_column or {}) do
        local column = columns_by_name[column_name]
        if column and not active(column, result) then
            --An explicitly zero-rate solver column is an inactive choice and cannot block this sheet.
        elseif quality_loop_reason(reason) then
            add(reasons, seen, "BP_REJ_QUALITY_LOOP", column_name, "recipe",
                "quality loop on " .. tostring(column_name))
        elseif cycle_reason(reason) then
            add(reasons, seen, "BP_REJ_CYCLE", column_name, "recipe",
                tostring(column_name) .. " is part of a dependency cycle")
        end
    end
end

local function infrastructure_reasons(reasons, seen, options, catalog)
    local settings = options.settings or options
    local input_edge = settings.input_edge or settings.input
    local output_edge = settings.output_edge or settings.output
    if input_edge ~= nil and output_edge ~= nil and input_edge == output_edge then
        add(reasons, seen, "BP_REJ_EDGES_EQUAL", "input/output", "option",
            "input and output edge are both " .. tostring(input_edge))
    end

    local belt_choice = settings.belt
    if settings.belt_family_missing == true or options.belt_family_missing == true then
        add(reasons, seen, "BP_REJ_BELT_FAMILY_MISSING", belt_choice or "belt", "infrastructure",
            name_of(belt_choice, "belt") .. " has no matching family")
    elseif belt_choice ~= nil and (catalog.belt == nil or catalog.belt.underground == nil or catalog.belt.splitter == nil) then
        add(reasons, seen, "BP_REJ_BELT_FAMILY_MISSING", belt_choice, "infrastructure",
            name_of(belt_choice, "belt") .. " has no matching underground belt and splitter")
    elseif catalog.belt and catalog.belt.family_missing == true then
        add(reasons, seen, "BP_REJ_BELT_FAMILY_MISSING", belt_choice or catalog.belt.belt or "belt", "infrastructure",
            name_of(belt_choice or catalog.belt.belt, "belt") .. " has no matching underground belt and splitter")
    end

    local surface = settings.surface
    if options.surface_restricted == true or (type(catalog.surface) == "table" and catalog.surface.allowed == false) then
        add(reasons, seen, "BP_REJ_SURFACE_RESTRICTED", surface or "surface", "option",
            name_of(surface, "surface") .. " cannot be built on this surface")
    elseif surface and type(options.allowed_surfaces) == "table" and options.allowed_surfaces[surface] == false then
        add(reasons, seen, "BP_REJ_SURFACE_RESTRICTED", surface, "option", tostring(surface) .. " is restricted")
    end
end

local function option_prototype_reasons(reasons, seen, options, catalog)
    for _, choice in ipairs(explicit_values(options.option_prototype_missing or options.missing_options or options.unusable_options)) do
        add(reasons, seen, "BP_REJ_OPTION_PROTOTYPE_MISSING", choice, "option",
            name_of(choice, "option") .. " is not available")
    end
    local selected = options.infrastructure or options
    for _, key in ipairs({"pole", "inserter", "pipe", "underground_pipe", "robo", "roboport"}) do
        local choice = type(selected) == "table" and selected[key]
        if choice ~= nil and choice ~= false then
            local selected_name = name_of(choice)
            local field_name = key == "roboport" and "robo" or key
            local projected = catalog[field_name]
            if selected_name and projected == nil then
                add(reasons, seen, "BP_REJ_OPTION_PROTOTYPE_MISSING", selected_name, "option",
                    selected_name .. " is not available")
            elseif selected_name and projected and projected.name and projected.name ~= selected_name then
                add(reasons, seen, "BP_REJ_OPTION_PROTOTYPE_MISSING", selected_name, "option",
                    selected_name .. " is not available")
            end
        end
    end
end

local function finite_reasons(reasons, seen, snapshot, result)
    for _, target in ipairs(values(snapshot.targets)) do
        if type(target) == "table" and (target.reason == "rate_not_finite"
            or (target.rate_per_second ~= nil and not finite(target.rate_per_second))) then
            add(reasons, seen, "BP_REJ_NON_FINITE_RATE", target.full_name or target.name, "product",
                name_of(target.full_name or target.name, "product") .. " has a non-finite rate", target.quality)
        end
    end
    for key, rate in pairs(result.recipe_rates or result.rates or {}) do
        if not finite(rate) then
            add(reasons, seen, "BP_REJ_NON_FINITE_RATE", key, "recipe",
                name_of(key, "recipe") .. " has a non-finite rate")
        end
    end
    for _, rate_map in ipairs({result.solved_rates, result.unsolved_rates}) do
        for key, rate in pairs(rate_map or {}) do
            if not finite(rate) then
                add(reasons, seen, "BP_REJ_NON_FINITE_RATE", key, "product",
                    name_of(key, "product") .. " has a non-finite rate")
            end
        end
    end
    for _, column in ipairs(columns_of(result)) do
        local rate = column.rate_per_second or column.crafts_per_second_total or column.rate
        if rate ~= nil and not finite(rate) then
            add(reasons, seen, "BP_REJ_NON_FINITE_RATE", recipe_name(column), "recipe",
                recipe_name(column) .. " has a non-finite rate")
        end
    end
end

local function selection_by_recipe(snapshot)
    local result = {}
    for _, entry in ipairs(values(snapshot.selection)) do
        if type(entry) == "table" and entry.recipe_name then result[entry.recipe_name] = entry end
    end
    return result
end

local function sort_reasons(reasons)
    local order = {}
    for index, code in ipairs(ReasonCodes.REJECT) do order[code] = index end
    table.sort(reasons, function(a, b)
        local ao, bo = order[a.code] or math.huge, order[b.code] or math.huge
        if ao ~= bo then return ao < bo end
        if a.subject.kind ~= b.subject.kind then return a.subject.kind < b.subject.kind end
        if a.subject.name ~= b.subject.name then return a.subject.name < b.subject.name end
        if a.subject.quality ~= b.subject.quality then return a.subject.quality < b.subject.quality end
        return a.detail < b.detail
    end)
end

--Returns a list of {code, subject = {kind, name, quality}, detail, locale_key}; empty means the request may proceed.
function Preflight.check(snapshot, solver_result, catalog, options)
    snapshot, solver_result, catalog, options = snapshot or {}, solver_result or {}, catalog or {}, options or {}
    local reasons, seen = {}, {}

    --The limits are deliberately the first work: an oversized request must be refused before prototype and
    --module inspection. We continue afterwards so all applicable blockers still reach the player.
    local machine_count = count_machines(solver_result)
    if machine_count and machine_count > Preflight.MAX_MACHINES then
        add(reasons, seen, "BP_REJ_SIZE_MACHINES", "sheet", "sheet",
            "sheet needs " .. tostring(machine_count) .. " machines; limit is " .. tostring(Preflight.MAX_MACHINES))
    end
    local step_count = count_steps(solver_result)
    if step_count and step_count > Preflight.MAX_STEPS then
        add(reasons, seen, "BP_REJ_SIZE_STEPS", "sheet", "sheet",
            "sheet has " .. tostring(step_count) .. " production steps; limit is " .. tostring(Preflight.MAX_STEPS))
    end

    finite_reasons(reasons, seen, snapshot, solver_result)
    solver_reasons(reasons, seen, solver_result)

    local state = snapshot.state
    if state == "stale" or (snapshot.fingerprint and snapshot.fingerprint.input ~= nil
        and snapshot.fingerprint.result ~= nil and snapshot.fingerprint.input ~= snapshot.fingerprint.result) then
        add(reasons, seen, "BP_REJ_SNAPSHOT_STALE", snapshot.sheet_id or "sheet", "sheet", "the snapshot is stale")
    elseif state ~= nil and state ~= "current" then
        add(reasons, seen, "BP_REJ_SOLVER_NOT_OK", snapshot.sheet_id or "sheet", "sheet",
            "the sheet has no finished calculation")
    elseif solver_result.status ~= nil and solver_result.status ~= "ok" then
        add(reasons, seen, "BP_REJ_SOLVER_NOT_OK", snapshot.sheet_id or "sheet", "sheet",
            "the sheet has no finished calculation")
    end

    local active_columns = {}
    for _, column in ipairs(columns_of(solver_result)) do
        if active(column, solver_result) then active_columns[#active_columns + 1] = column end
    end
    if (state == nil or state == "current") and solver_result.status == "ok" and #active_columns == 0 then
        add(reasons, seen, "BP_REJ_NO_ACTIVE_STEPS", snapshot.sheet_id or "sheet", "sheet",
            "the sheet has no active production steps")
    end

    local selections = selection_by_recipe(snapshot)
    for _, column in ipairs(columns_of(solver_result)) do
        local is_active = active(column, solver_result)
        if is_active then
            local entry = selections[recipe_name(column)]
            product_reasons(reasons, seen, catalog, recipe_of(catalog, column), true, recipe_name(column))
            if not column.burner and not column.quality_loop then
                entity_reasons(reasons, seen, snapshot, catalog, options, column, entry, true)
            end
        end
    end

    for _, column in ipairs(columns_of(solver_result)) do
        if active(column, solver_result) and column.burner then
            local burner = name_of(column.burner, recipe_name(column))
            add(reasons, seen, "BP_REJ_FUEL_CONSUMER", burner, "machine", burner .. " is a fuel-burning consumer")
        end
    end

    diagnostic_reasons(reasons, seen, catalog.diagnostics)
    diagnostic_reasons(reasons, seen, catalog._diagnostics)
    diagnostic_reasons(reasons, seen, options.diagnostics)
    diagnostic_reasons(reasons, seen, options.catalog_diagnostics)
    for _, missing in ipairs(explicit_values(catalog.unresolved_prototypes or catalog.missing_prototypes)) do
        add(reasons, seen, "BP_REJ_UNRESOLVED_PROTOTYPE", missing, "prototype",
            name_of(missing, "prototype") .. " no longer resolves")
    end

    infrastructure_reasons(reasons, seen, options, catalog)
    option_prototype_reasons(reasons, seen, options, catalog)

    for _, target in ipairs(values(snapshot.targets)) do
        if type(target) == "table" and target.rate_per_second ~= 0 and target.valid ~= false then
            local quality = target.quality or "normal"
            if quality ~= "normal" and not quality_unlocked(options, snapshot, catalog, quality) then
                add(reasons, seen, "BP_REJ_QUALITY_UNAVAILABLE", quality, "quality",
                    "quality " .. tostring(quality) .. " is not unlocked", quality)
            end
        end
    end

    sort_reasons(reasons)
    return reasons
end

return Preflight
