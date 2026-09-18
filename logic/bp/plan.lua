--The sheet's numbers turned into what has to be built: whole machines, their modules and beacons, and the flows
--between them.
--
--Owned by lane W2-plan. This is the only blueprint module allowed to read prototypes, storage or the version
--flag; everything after it takes plain data.
--
--  Step = {step_id, recipe, recipe_quality, machine, machine_quality, machine_count, crafts_per_second_total,
--          crafts_per_second_per_machine, modules = {{name, quality, count}}, beacon_groups = {BeaconGroup},
--          has_quality_module, forbids_speed_beacon, power_w, pollution_per_min, inputs, outputs}
--  Flow = {flow_id, full_name, item_name, quality, is_fluid, rate_per_second,
--          producers = {{step_id, share_per_second}}, consumers = {{step_id, share_per_second}}}
--          step_id "$external" is the world outside the blueprint, on both sides
--  PlanPort = {port_id, role, full_name, is_fluid, rate_per_second, kind, min_lanes}
--
--machine_count is computed once, here, from the full-precision rate: the round-up checkbox is a display setting
--and must never reach a physical count. Nothing downstream may call Utils.machine_amount; the validator counts
--what was placed and compares it against this number instead of recomputing the requirement.
local Plan = {}

Plan.SCHEMA_VERSION = 1

local EPSILON = 1e-9

local function finite_number(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback
end

local function tolerance(value)
    return math.max(EPSILON, math.abs(value or 0) * EPSILON)
end

local function name_of(value)
    if value == nil then return nil end
    if type(value) == "string" then return value end
    if type(value) == "table" then return value.name or value.prototype or value.id end
    return value.name
end

local function quality_of(value)
    local name = name_of(value)
    return name or "normal"
end

local function identifier_of(value)
    if value == nil then return nil end
    local name = name_of(value)
    if not name then return nil end
    local quality = "normal"
    if type(value) == "table" then quality = quality_of(value.quality) end
    return {name = name, quality = quality}
end

local function sorted_keys(map)
    local keys = {}
    for key, _ in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function copy_effects(effects)
    local copy = {}
    for key, value in pairs(effects or {}) do
        if type(key) == "string" and finite_number(value) ~= nil then copy[key] = value end
    end
    return copy
end

local function copy_modules(modules)
    local copy = {}
    for index, module in ipairs(modules or {}) do
        local name = name_of(module)
        if name then
            copy[index] = {name = name, quality = quality_of(type(module) == "table" and module.quality or nil)}
        end
    end
    return copy
end

--The IR groups equal consecutive slots, while retaining the slot order.  A repeated module is not a
--placement count: it is the number of occupied slots in this ordered run.
local function compress_modules(modules)
    local result = {}
    for _, module in ipairs(copy_modules(modules)) do
        local previous = result[#result]
        if previous and previous.name == module.name and previous.quality == module.quality then
            previous.count = previous.count + 1
        else
            result[#result + 1] = {name = module.name, quality = module.quality, count = 1}
        end
    end
    return result
end

local function expand_modules(modules)
    local result = {}
    for _, module in ipairs(modules or {}) do
        local count = math.max(1, math.floor(finite_number(module.count, 1)))
        for _ = 1, count do
            result[#result + 1] = {name = name_of(module), quality = quality_of(module.quality)}
        end
    end
    return result
end

local function module_effect(module_name, quality, catalog)
    local module = catalog and catalog.module and catalog.module[module_name]
    if module and module.effects then return copy_effects(module.effects) end
    local item = catalog and catalog.item and catalog.item[module_name]
    if item and item.module_effects then return copy_effects(item.module_effects) end

    --This fallback is used only while building the plain-data boundary.  No prototype is retained in the
    --state or in the result.
    local item_prototype = type(prototypes) == "table" and prototypes.item and prototypes.item[module_name]
    if item_prototype and type(item_prototype.get_module_effects) == "function" then
        return copy_effects(item_prototype.get_module_effects(quality == "normal" and nil or quality) or {})
    end
    return {}
end

local function machine_projection(machine_name, machine_quality, catalog)
    if not machine_name then
        return {name = nil, quality = machine_quality, energy_usage_w = 0, pollution_per_min = 0}
    end
    local projected = catalog and catalog.entity and catalog.entity[machine_name]
    if projected then
        return {
            name = machine_name,
            quality = machine_quality,
            crafting_speed = finite_number(projected.crafting_speed),
            energy_usage_w = finite_number(projected.energy_usage_w, 0),
            pollution_per_min = finite_number(projected.pollution_per_min, 0),
        }
    end

    local prototype = type(prototypes) == "table" and prototypes.entity and prototypes.entity[machine_name]
    if not prototype then
        return {name = machine_name, quality = machine_quality, energy_usage_w = 0, pollution_per_min = 0}
    end
    local speed
    if type(prototype.get_crafting_speed) == "function" then
        speed = prototype.get_crafting_speed(machine_quality == "normal" and nil or machine_quality)
    end
    local usage = prototype.energy_usage
    if type(prototype.get_max_energy_usage) == "function" then
        usage = prototype.get_max_energy_usage(machine_quality == "normal" and nil or machine_quality) * 60
    end
    return {
        name = machine_name,
        quality = machine_quality,
        crafting_speed = finite_number(speed),
        energy_usage_w = finite_number(usage, 0),
        pollution_per_min = 0,
    }
end

local function beacon_projection(beacon_name, beacon_quality, catalog)
    local projected = catalog and catalog.entity and catalog.entity[beacon_name]
    projected = projected and (projected.beacon and projected or projected)
    local beacon = projected and projected.beacon
    if not beacon and catalog and catalog.beacon then beacon = catalog.beacon[beacon_name] end
    local prototype = type(prototypes) == "table" and prototypes.entity and prototypes.entity[beacon_name]
    local energy = projected and projected.energy_usage_w
    if energy == nil and prototype then
        energy = prototype.energy_usage
        if type(prototype.get_max_energy_usage) == "function" then
            energy = prototype.get_max_energy_usage(beacon_quality == "normal" and nil or beacon_quality) * 60
        end
    end
    return {
        name = beacon_name,
        quality = beacon_quality,
        energy_usage_w = finite_number(energy, 0),
        distribution_effectivity = finite_number(beacon and beacon.distribution_effectivity, 1),
        profile = beacon and beacon.profile,
        counter = beacon and beacon.counter,
    }
end

local function recipe_data(recipe_name, input)
    local recipes = input and (input.recipes or input.recipe)
    local recipe = type(recipes) == "table" and recipes[recipe_name]
    if recipe then return recipe end
    local catalog_recipe = input and input.catalog and input.catalog.recipe
    if type(catalog_recipe) == "table" and catalog_recipe[recipe_name] then return catalog_recipe[recipe_name] end
    if type(prototypes) == "table" and prototypes.recipe then return prototypes.recipe[recipe_name] end
end

local function product_amount(product)
    if product.amount ~= nil then return finite_number(product.amount, 0) end
    local minimum = finite_number(product.amount_min, 0)
    local maximum = finite_number(product.amount_max, minimum)
    if maximum < minimum then maximum = minimum end
    return (minimum + maximum) / 2 + finite_number(product.extra_count_fraction, 0)
end

local function net_amounts_from_recipe(recipe)
    local amounts = {}
    if not recipe then return amounts end
    for _, product in ipairs(recipe.products or {}) do
        if product.type ~= "research-progress" and product.name then
            local full_name = (product.type or "item") .. "/" .. product.name
            amounts[full_name] = (amounts[full_name] or 0) + product_amount(product)
        end
    end
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        if ingredient.name then
            local full_name = (ingredient.type or "item") .. "/" .. ingredient.name
            amounts[full_name] = (amounts[full_name] or 0) - finite_number(ingredient.amount, 0)
        end
    end
    for full_name, amount in pairs(amounts) do
        if amount == 0 then amounts[full_name] = nil end
    end
    return amounts
end

local function copy_amounts(amounts)
    local copy = {}
    for full_name, amount in pairs(amounts or {}) do
        if type(full_name) == "string" and finite_number(amount) ~= nil and amount ~= 0 then
            copy[full_name] = amount
        end
    end
    return copy
end

local function stage_setup(stage, fallback)
    stage = stage or {}
    fallback = fallback or {}
    local modules = stage.modules or (stage.setup and stage.setup.modules) or fallback.modules or {}
    local beacons = stage.beacons or (stage.setup and stage.setup.beacons) or fallback.beacons or {}
    return {modules = copy_modules(modules), beacons = beacons}
end

local function normalize_beacon_groups(groups, catalog)
    local result = {}
    for _, group in ipairs(groups or {}) do
        local name = name_of(group.name or group.type)
        if name then
            local quality = quality_of(group.quality)
            local count = finite_number(group.count_per_machine, finite_number(group.count, 0))
            local sharing = finite_number(group.sharing, 1)
            if count > 0 then
                result[#result + 1] = {
                    name = name,
                    quality = quality,
                    count_per_machine = count,
                    sharing = sharing > 0 and sharing or 1,
                    modules = compress_modules(group.modules or {}),
                    _projection = beacon_projection(name, quality, catalog),
                }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.name == b.name then return a.quality < b.quality end
        return a.name < b.name
    end)
    return result
end

local function selection_maps(snapshot)
    local selections, loops = {}, {}
    for _, entry in ipairs(snapshot and snapshot.selection or {}) do
        if entry.recipe_name then selections[entry.recipe_name] = entry end
    end
    for _, entry in ipairs(snapshot and snapshot.selection and snapshot.selection.quality_loops or {}) do
        if entry.key then loops[entry.key] = entry end
    end
    return selections, loops
end

local function lookup_stage(loop_entry, stage_name, quality)
    if not loop_entry then return nil end
    if stage_name == "recycle" or stage_name == "assist" then return loop_entry[stage_name] end
    for _, entry in ipairs(loop_entry.crafts or {}) do
        if entry.quality == quality then return entry.settings end
    end
    return nil
end

local function stage_descriptor(column, stage, rate, stage_id, input, selections, catalog)
    stage = stage or {}
    local recipe_name = name_of(stage.recipe_name or stage.recipe)
    local selection = recipe_name and selections[recipe_name] or nil
    local setup = stage_setup(stage, selection)
    local machine_identifier = identifier_of(stage.machine or (selection and selection.machine) or column.machine or column.burner)
    local machine_quality = machine_identifier and machine_identifier.quality or "normal"
    local recipe_quality = quality_of(stage.recipe_quality or stage.quality or column.recipe_quality)
    local recipe = stage.recipe_data or (recipe_name and recipe_data(recipe_name, input))
    local net_amounts = stage.net_amounts or column.net_amounts
    if not net_amounts and recipe then net_amounts = net_amounts_from_recipe(recipe) end
    local machine_rate = finite_number(stage.crafts_per_second_per_machine,
        finite_number(column.crafts_per_second_per_machine, finite_number(column.machine_rate)))
    local energy = finite_number(stage.energy, recipe and recipe.energy)
    local machine = machine_projection(machine_identifier and machine_identifier.name, machine_quality, catalog)
    local effects_speed = 0
    local effects_consumption = 0
    local effects_pollution = 0
    local has_quality_module = false
    for _, module in ipairs(expand_modules(setup.modules)) do
        local effects = module_effect(module.name, module.quality, catalog)
        effects_speed = effects_speed + finite_number(effects.speed, 0)
        effects_consumption = effects_consumption + finite_number(effects.consumption, 0)
        effects_pollution = effects_pollution + finite_number(effects.pollution, 0)
        if finite_number(effects.quality, 0) > 0 then has_quality_module = true end
    end

    local count_by_beacon_name, beacon_total = {}, 0
    for _, group in ipairs(normalize_beacon_groups(setup.beacons, catalog)) do
        count_by_beacon_name[group.name] = (count_by_beacon_name[group.name] or 0) + group.count_per_machine
        beacon_total = beacon_total + group.count_per_machine
    end
    local beacon_speed, beacon_consumption, beacon_pollution = 0, 0, 0
    local beacon_power = 0
    local beacon_groups = normalize_beacon_groups(setup.beacons, catalog)
    for _, group in ipairs(beacon_groups) do
        local projection = group._projection
        local reaching = projection.counter == "same_type" and count_by_beacon_name[group.name] or beacon_total
        local profile = projection.profile
        local sample = 1
        if type(profile) == "table" and #profile > 0 then sample = profile[math.min(math.max(1, reaching), #profile)] or 1 end
        local weight = group.count_per_machine * projection.distribution_effectivity * sample
        for _, module in ipairs(expand_modules(group.modules)) do
            local effects = module_effect(module.name, module.quality, catalog)
            beacon_speed = beacon_speed + weight * finite_number(effects.speed, 0)
            beacon_consumption = beacon_consumption + weight * finite_number(effects.consumption, 0)
            beacon_pollution = beacon_pollution + weight * finite_number(effects.pollution, 0)
        end
        local power_multiplier = 1
        local qualities = type(prototypes) == "table" and prototypes.quality
        local quality = qualities and qualities[group.quality]
        if quality then power_multiplier = finite_number(quality.beacon_power_usage_multiplier, 1) end
        beacon_power = beacon_power + group.count_per_machine / group.sharing * projection.energy_usage_w * power_multiplier
    end

    local speed_multiplier = math.max(0.2, 1 + effects_speed + beacon_speed)
    if machine_rate == nil and machine.crafting_speed and energy and energy > 0 then
        machine_rate = machine.crafting_speed * speed_multiplier / energy
    end
    machine_rate = finite_number(machine_rate, 0)
    local consumption_multiplier = math.max(0.2, 1 + effects_consumption + beacon_consumption)
    local pollution_multiplier = math.max(0.2, 1 + effects_pollution + beacon_pollution)
    local power_w = finite_number(stage.power_w,
        column.burner and 0 or machine.energy_usage_w * consumption_multiplier + beacon_power)
    local pollution = finite_number(stage.pollution_per_min,
        machine.pollution_per_min * pollution_multiplier * consumption_multiplier)

    local public_beacons = {}
    for _, group in ipairs(beacon_groups) do
        public_beacons[#public_beacons + 1] = {
            name = group.name,
            quality = group.quality,
            count_per_machine = group.count_per_machine,
            sharing = group.sharing,
            modules = group.modules,
        }
    end
    return {
        step_id = stage_id,
        recipe = recipe_name,
        recipe_quality = recipe_quality,
        machine = machine_identifier and machine_identifier.name or nil,
        machine_quality = machine_quality,
        machine_count = Plan.machine_count(rate, machine_rate),
        crafts_per_second_total = rate,
        crafts_per_second_per_machine = machine_rate,
        modules = compress_modules(setup.modules),
        beacon_groups = public_beacons,
        has_quality_module = has_quality_module,
        forbids_speed_beacon = has_quality_module,
        power_w = power_w,
        pollution_per_min = pollution,
        _net_amounts = copy_amounts(net_amounts),
    }
end

local function direct_stage_specs(column, rate, input, selections, catalog)
    local specs = {}
    if type(column.stages) == "table" then
        for index, stage in ipairs(column.stages) do
            local stage_rate = finite_number(stage.crafts_per_second_total, rate)
            specs[#specs + 1] = stage_descriptor(column, stage, stage_rate,
                stage.step_id or (column.recipe_name .. ":stage:" .. index), input, selections, catalog)
        end
        return specs
    end

    local info = column.quality_loop
    local loops = input.snapshot and input.snapshot.selection and input.snapshot.selection.quality_loops
    local loop_entry
    for _, candidate in ipairs(loops or {}) do
        if candidate.key == (info and info.key) then loop_entry = candidate break end
    end
    if info and loop_entry and type(info.tiers) == "table" then
        for index, tier in ipairs(info.tiers) do
            local quality = quality_of(tier.quality)
            local stage = lookup_stage(loop_entry, "craft", quality)
            if stage then
                local stage_rate = rate * finite_number(tier.crafts, 0)
                specs[#specs + 1] = stage_descriptor(column, stage, stage_rate,
                    column.recipe_name .. ":craft:" .. quality, input, selections, catalog)
            end
        end
        local recycle = lookup_stage(loop_entry, "recycle")
        local recycle_crafts = 0
        for _, tier in ipairs(info.tiers) do recycle_crafts = recycle_crafts + finite_number(tier.recycle_crafts, 0) end
        if recycle then
            specs[#specs + 1] = stage_descriptor(column, recycle, rate * recycle_crafts,
                column.recipe_name .. ":recycle", input, selections, catalog)
        end
        local assist = lookup_stage(loop_entry, "assist")
        local assist_crafts = info.tiers[1] and finite_number(info.tiers[1].assist_crafts, 0) or 0
        if assist then
            specs[#specs + 1] = stage_descriptor(column, assist, rate * assist_crafts,
                column.recipe_name .. ":assist", input, selections, catalog)
        end
        return specs
    end

    local selection = selections[column.recipe_name]
    local stage = {
        recipe_name = column.burner and nil or column.recipe_name,
        recipe_quality = column.recipe_quality,
        machine = column.machine or (selection and selection.machine),
        modules = column.modules or (selection and selection.modules),
        beacons = column.beacons or (selection and selection.beacons),
        setup = column.setup,
        net_amounts = column.net_amounts,
        crafts_per_second_per_machine = column.crafts_per_second_per_machine or column.units_per_second_per_machine
            or column.burn_rate,
        power_w = column.power_w,
        pollution_per_min = column.pollution_per_min,
    }
    specs[1] = stage_descriptor(column, stage, rate, column.step_id or column.recipe_name, input, selections, catalog)
    return specs
end

local function make_descriptors(input)
    local solver = input.solver_result or input.solver or input.result or {}
    local snapshot = input.snapshot or input.sheet or {}
    local catalog = input.catalog or {}
    local selections = selection_maps(snapshot)
    local columns = solver.columns or input.columns or {}
    local by_key = solver.recipe_rates or solver.recipe_rates_by_recipe_name or input.recipe_rates or {}
    local descriptors = {}
    if #columns == 0 then
        for _, key in ipairs(sorted_keys(by_key)) do
            columns[#columns + 1] = {recipe_name = key}
        end
    end
    for _, column in ipairs(columns) do
        local key = column.recipe_name or column.step_id
        local rate = finite_number(column.crafts_per_second_total,
            finite_number(by_key[key], finite_number(column.rate, 0)))
        local produced = direct_stage_specs(column, rate, {snapshot = snapshot, recipes = input.recipes,
            catalog = catalog}, selections, catalog)
        for _, descriptor in ipairs(produced) do descriptors[#descriptors + 1] = descriptor end
    end
    table.sort(descriptors, function(a, b) return a.step_id < b.step_id end)
    return descriptors
end

local function split_flow_identity(full_name)
    local kind, rest = full_name:match("^([^/]+)/(.+)$")
    if kind == "item" or kind == "fluid" then
        return kind, rest, "normal"
    end
    local item_length, position = full_name:match("^item%-quality:(%d+):()")
    if item_length then
        item_length = tonumber(item_length)
        local item_name = full_name:sub(position, position + item_length - 1)
        local quality_length_start = position + item_length
        local quality_length = tonumber(full_name:match("^(%d+):", quality_length_start))
        local quality_start = full_name:find(":", quality_length_start, true)
        if quality_length and quality_start then
            return "item", item_name, full_name:sub(quality_start + 1, quality_start + quality_length)
        end
    end
    return "item", full_name, "normal"
end

local function add_step_io(step, flows)
    step.inputs, step.outputs = {}, {}
    for full_name, amount in pairs(step._net_amounts or {}) do
        local rate = math.abs(amount * step.crafts_per_second_total)
        if rate > tolerance(rate) then
            local target = amount < 0 and step.inputs or step.outputs
            target[#target + 1] = {flow_id = full_name, rate_per_second = rate}
            flows[full_name] = flows[full_name] or {producers = {}, consumers = {}}
            if amount < 0 then
                flows[full_name].consumers[#flows[full_name].consumers + 1] = {step_id = step.step_id, share_per_second = rate}
            else
                flows[full_name].producers[#flows[full_name].producers + 1] = {step_id = step.step_id, share_per_second = rate}
            end
        end
    end
    table.sort(step.inputs, function(a, b) return a.flow_id < b.flow_id end)
    table.sort(step.outputs, function(a, b) return a.flow_id < b.flow_id end)
    step._net_amounts = nil
end

local function lane_count(rate, flow_kind, catalog)
    if flow_kind == "fluid" then return 1 end
    local capacity = catalog and catalog.belt and catalog.belt.lane_items_per_second
    if type(capacity) ~= "number" or capacity <= 0 then return 1 end
    return math.max(1, math.ceil(rate / capacity - tolerance(rate)))
end

local function finalize(state)
    local flow_work = {}
    local machines, steps = 0, 0
    for _, step in ipairs(state.work.steps) do
        add_step_io(step, flow_work)
        machines = machines + step.machine_count
        steps = steps + 1
    end

    local flows, ports = {}, {}
    local catalog = state.work.catalog
    for _, full_name in ipairs(sorted_keys(flow_work)) do
        local work = flow_work[full_name]
        local producers, consumers = work.producers, work.consumers
        local produced, consumed = 0, 0
        for _, entry in ipairs(producers) do produced = produced + entry.share_per_second end
        for _, entry in ipairs(consumers) do consumed = consumed + entry.share_per_second end
        local rate = math.max(produced, consumed)
        if produced < rate - tolerance(rate) then
            producers[#producers + 1] = {step_id = "$external", share_per_second = rate - produced}
        end
        if consumed < rate - tolerance(rate) then
            consumers[#consumers + 1] = {step_id = "$external", share_per_second = rate - consumed}
        end
        table.sort(producers, function(a, b) return a.step_id < b.step_id end)
        table.sort(consumers, function(a, b) return a.step_id < b.step_id end)
        local kind, item_name, quality = split_flow_identity(full_name)
        flows[#flows + 1] = {
            flow_id = full_name,
            full_name = full_name,
            item_name = item_name,
            quality = quality,
            is_fluid = kind == "fluid",
            rate_per_second = rate,
            producers = producers,
            consumers = consumers,
        }
        local external_input = 0
        local external_output = 0
        for _, entry in ipairs(producers) do if entry.step_id == "$external" then external_input = entry.share_per_second end end
        for _, entry in ipairs(consumers) do if entry.step_id == "$external" then external_output = entry.share_per_second end end
        if external_input > tolerance(external_input) then
            ports[#ports + 1] = {
                port_id = "in:" .. full_name, role = "in", full_name = full_name, is_fluid = kind == "fluid",
                rate_per_second = external_input, kind = kind, min_lanes = lane_count(external_input, kind, catalog),
            }
        end
        if external_output > tolerance(external_output) then
            ports[#ports + 1] = {
                port_id = "out:" .. full_name, role = "out", full_name = full_name, is_fluid = kind == "fluid",
                rate_per_second = external_output, kind = kind, min_lanes = lane_count(external_output, kind, catalog),
            }
        end
    end
    table.sort(flows, function(a, b) return a.flow_id < b.flow_id end)
    table.sort(ports, function(a, b) return a.port_id < b.port_id end)
    return {
        schema_version = Plan.SCHEMA_VERSION,
        steps = state.work.steps,
        flows = flows,
        ports = ports,
        totals = {machines = machines, steps = steps},
    }
end

function Plan.begin(input)
    input = input or {}
    local descriptors = make_descriptors(input)
    return {
        done = false,
        ok = nil,
        cursor = {step_index = 1},
        progress = {phase = "planning", done_units = 0, total_units = #descriptors},
        work = {descriptors = descriptors, steps = {}, catalog = input.catalog or {}},
    }
end

function Plan.step(state, budget)
    if state.done then return state end
    budget = budget or {ops = 1}
    local ops = finite_number(budget.ops, 1)
    while ops > 0 and state.cursor.step_index <= #state.work.descriptors do
        local descriptor = state.work.descriptors[state.cursor.step_index]
        state.work.steps[#state.work.steps + 1] = descriptor
        state.cursor.step_index = state.cursor.step_index + 1
        state.progress.done_units = state.progress.done_units + 1
        ops = ops - 1
    end
    budget.ops = ops
    if state.cursor.step_index > #state.work.descriptors then
        state.result = finalize(state)
        state.done = true
        state.ok = true
    end
    return state
end

--Whole machines for one step: ceil of the full-precision requirement, with the calculator's own tolerance, and
--at least one for any step with work to do
function Plan.machine_count(crafts_per_second, crafts_per_second_per_machine)
    crafts_per_second = finite_number(crafts_per_second, 0)
    crafts_per_second_per_machine = finite_number(crafts_per_second_per_machine, 0)
    if crafts_per_second <= 0 then return 0 end
    if crafts_per_second_per_machine <= 0 then return 1 end
    local requirement = crafts_per_second / crafts_per_second_per_machine
    return math.max(1, math.ceil(requirement - tolerance(requirement)))
end

return Plan
