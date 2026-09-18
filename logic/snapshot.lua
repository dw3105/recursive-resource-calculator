--One sheet, read out of its GUI into plain data that nothing else can change under a reader's feet.
--
--Owned by lane W1-snapshot. Everything the export, the calculation and the blueprint path work from starts here,
--so a target that was edited after a solve can never be presented as the input that produced it.
--
--Snapshot shape (every field plain data: number, string, boolean, table; never a LuaObject, never a function):
--  {
--    schema_version = 1,
--    sheet_id = string,
--    player_index = int,
--    revisions = {sheet = int, config = int},
--    state = "not_computed" | "current" | "pending" | "stale" | "failed",
--    targets = { -- UI order, never sorted
--      {index = int, full_name = string, type = "item"|"fluid", name = string, quality = string,
--       parts = {type, name, quality} | nil, raw_text = string, time_unit = "/s"|"/m",
--       rate_per_second = number|nil, valid = boolean, reason = string|nil},
--    },
--    options = {round_up = boolean, start_leftovers = "byproduct"|"craft"|"recycle"|nil},
--    selection = { -- bound recipe entries in product-name order, with burners and quality loops attached
--      {product_full_name, recipe_name, consumer, status, machine, modules, beacons},
--    },
--    fingerprint = {input = string, result = string|nil},
--  }
--
--Two fingerprints, never one: the inputs a player can edit, and the result that was computed from some earlier
--inputs. "current" means those two agree. Anything else has to say which is which.
local Sheet = require "gui.sheet"
local ModuleSetup = require "logic.module_setup"
local QualityId = require "logic.quality_id"

local Snapshot = {}

Snapshot.SCHEMA_VERSION = 1
Snapshot.STATES = {not_computed = true, current = true, pending = true, stale = true, failed = true}

local function name_of(value)
    if value == nil or type(value) == "string" then
        return value
    end
    return value.name
end

local function quality_name_of(value)
    local name = name_of(value)
    return name or "normal"
end

local function copy_identifier(identifier)
    if not identifier then
        return nil
    end
    return {name = name_of(identifier.name) or name_of(identifier), quality = quality_name_of(identifier.quality)}
end

local function copy_module(module)
    if not module then
        return nil
    end
    local name = name_of(module.name) or name_of(module)
    return {name = name, quality = quality_name_of(module.quality)}
end

local function copy_modules(modules)
    local copy = {}
    for index, module in ipairs(modules or {}) do
        copy[index] = copy_module(module)
    end
    return copy
end

local function copy_setup(setup)
    local copy = {modules = copy_modules(setup and setup.modules), beacons = {}}
    for index, group in ipairs(setup and setup.beacons or {}) do
        local name = name_of(group.name) or name_of(group.type)
        copy.beacons[index] = {
            --The snapshot calls the entity kind type; name is retained as a useful plain-data alias for consumers of old setup shapes.
            type = name,
            name = name,
            quality = quality_name_of(group.quality),
            count = group.count,
            sharing = group.sharing,
            modules = copy_modules(group.modules),
        }
    end
    return copy
end

local function copy_stage(settings)
    if settings == nil then
        return nil
    end
    local setup = copy_setup(settings.setup)
    local signature_setup = settings.setup or {modules = {}, beacons = {}}
    return {
        recipe_name = name_of(settings.recipe_name),
        machine = copy_identifier(settings.machine),
        modules = setup.modules,
        beacons = setup.beacons,
        setup = setup,
        signature = ModuleSetup.signature(signature_setup, settings.machine),
    }
end

local function sorted_keys(map)
    local keys = {}
    for key, _ in pairs(map or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function selection_of(player_index)
    local player_storage = storage[player_index] or {}
    local recipes = player_storage.recipes_by_product_full_name or {}
    local machines = player_storage.identifiers_of_chosen_crafting_machines_by_recipe_name or {}
    local setups = player_storage.module_setups_by_recipe_name or {}
    local consumers = player_storage.consumer_product_full_names or {}
    local selection = {}

    local product_names = sorted_keys(recipes)
    for _, product_full_name in ipairs(product_names) do
        local recipe = recipes[product_full_name]
        if recipe then
            local recipe_name = name_of(recipe.name) or name_of(recipe)
            local identifier = machines[recipe_name]
            local setup = copy_setup(setups[recipe_name])
            local signature_setup = setups[recipe_name] or {modules = {}, beacons = {}}
            selection[#selection + 1] = {
                product_full_name = product_full_name,
                recipe_name = recipe_name,
                consumer = consumers[product_full_name] == true,
                --A bound recipe with no machine is still recorded: it is a hand/unselected binding, not an absent entry.
                status = identifier and "selected" or "unselected",
                selected = identifier ~= nil,
                unselected = identifier == nil,
                machine = copy_identifier(identifier),
                modules = setup.modules,
                beacons = setup.beacons,
                signature = ModuleSetup.signature(signature_setup, identifier),
            }
        end
    end

    local burners = {}
    for _, product_full_name in ipairs(sorted_keys(player_storage.burners_by_product_full_name)) do
        burners[#burners + 1] = {
            product_full_name = product_full_name,
            burner = copy_identifier(player_storage.burners_by_product_full_name[product_full_name]),
            status = "selected",
        }
    end
    selection.burners = burners

    local quality_loops = {}
    local loops = player_storage.quality_loops_by_key or {}
    for _, key in ipairs(sorted_keys(loops)) do
        local loop = loops[key]
        local entry = {
            key = key,
            item = loop.item,
            quality = quality_name_of(loop.quality),
            start_quality = loop.start_quality and quality_name_of(loop.start_quality) or nil,
            recycle_only = loop.recycle_only == true,
            recycle_recipe_name = loop.recycle_recipe_name,
            crafts = {},
            recycle = copy_stage(loop.recycle),
            assist = copy_stage(loop.assist),
        }
        for _, tier in ipairs(sorted_keys(loop.crafts)) do
            entry.crafts[#entry.crafts + 1] = {quality = tier, settings = copy_stage(loop.crafts[tier])}
        end
        quality_loops[#quality_loops + 1] = entry
    end
    selection.quality_loops = quality_loops
    return selection
end

local function controls_have_start_leftovers(sheet_flow)
    for _, child in ipairs(sheet_flow.children or {}) do
        if child.name == "hxrrc_sheet_controls" then
            for _, cell in ipairs(child.children or {}) do
                if cell.name == "start_leftovers_dropdown_cell" and cell.children[1] then
                    return true
                end
            end
        end
    end
    return false
end

local function target_from_row(row, index)
    local item = row.hxrrc_desired_item_button.elem_value
    local fluid = row.hxrrc_desired_fluid_button.elem_value
    local target_type, name, quality, full_name, parts

    if item then
        target_type = "item"
        name = name_of(item.name) or name_of(item)
        quality = quality_name_of(item.quality)
        if quality == "normal" then
            full_name = "item/" .. name
        else
            full_name = QualityId.encode(name, quality)
            parts = {type = "item", name = name, quality = quality}
        end
    elseif fluid then
        target_type = "fluid"
        name = name_of(fluid)
        quality = "normal"
        full_name = "fluid/" .. name
    else
        return nil
    end

    local raw_text = row.rate_textfield.text or ""
    local time_unit = row.time_unit_dropdown.selected_index == 1 and "/m" or "/s"
    local numeric_rate = tonumber(raw_text)
    local finite = numeric_rate and numeric_rate == numeric_rate and numeric_rate ~= math.huge and numeric_rate ~= -math.huge
    local target_exists = name ~= nil and prototypes[target_type] and prototypes[target_type][name] ~= nil
    if quality ~= "normal" and (not prototypes.quality or not prototypes.quality[quality]) then
        target_exists = false
    end

    local rate_per_second, valid, reason
    if not finite then
        valid, reason = false, "rate_not_finite"
    elseif numeric_rate <= 0 then
        valid, reason = false, "no_rate"
    elseif not target_exists then
        valid, reason = false, "target_missing"
    else
        rate_per_second, valid = numeric_rate / (time_unit == "/m" and 60 or 1), true
    end

    return {
        index = index,
        full_name = full_name,
        type = target_type,
        name = name,
        quality = quality,
        parts = parts,
        raw_text = raw_text,
        time_unit = time_unit,
        rate_per_second = rate_per_second,
        valid = valid,
        reason = reason,
    }
end

--Reads the sheet's own controls and the player's recipe setup into the shape above. Never writes to the sheet,
--never recalculates, never repairs: a broken target is reported with valid = false and a reason.
function Snapshot.of_sheet(sheet_flow)
    local inputs = Sheet.read_inputs(sheet_flow)
    local player_storage = storage[inputs.player_index] or {}
    local sheet_revisions = player_storage.sheet_revision or {}
    local snapshot = {
        schema_version = Snapshot.SCHEMA_VERSION,
        sheet_id = inputs.sheet_id,
        player_index = inputs.player_index,
        revisions = {sheet = sheet_revisions[inputs.sheet_id] or 0, config = player_storage.config_revision or 0},
        state = "not_computed",
        targets = {},
        options = {
            round_up = inputs.options.round_up == true,
            start_leftovers = controls_have_start_leftovers(sheet_flow) and inputs.options.start_leftovers or nil,
        },
        selection = selection_of(inputs.player_index),
        fingerprint = {input = nil, result = nil},
    }

    for index, row in ipairs(sheet_flow.input_container.children or {}) do
        local target = target_from_row(row, index)
        if target then
            snapshot.targets[#snapshot.targets + 1] = target
        end
    end

    snapshot.fingerprint.input = Snapshot.fingerprint(snapshot)
    return snapshot
end

--Each scalar and every table edge is length-prefixed. Type tags keep e.g. a numeric key 1 separate from string key "1";
--sorted encoded keys keep map order out of the result while array order remains significant.
local function length_prefixed(value)
    return tostring(#value) .. ":" .. value
end

local function encode_value(value, active)
    local value_type = type(value)
    if value == nil then
        return "n"
    elseif value_type == "boolean" then
        return "b" .. length_prefixed(value and "1" or "0")
    elseif value_type == "number" then
        return "d" .. length_prefixed(string.format("%.17g", value))
    elseif value_type == "string" then
        return "s" .. length_prefixed(value)
    elseif value_type == "table" then
        active = active or {}
        if active[value] then
            error("snapshot fingerprint cannot encode a cyclic table", 3)
        end
        active[value] = true
        local entries = {}
        for key, child in pairs(value) do
            entries[#entries + 1] = {key = encode_value(key, active), value = encode_value(child, active)}
        end
        active[value] = nil
        table.sort(entries, function(a, b)
            if a.key == b.key then return a.value < b.value end
            return a.key < b.key
        end)
        local out = {"t", length_prefixed(tostring(#entries))}
        for _, entry in ipairs(entries) do
            out[#out + 1] = length_prefixed(entry.key)
            out[#out + 1] = length_prefixed(entry.value)
        end
        return table.concat(out)
    end
    error("snapshot fingerprint cannot encode " .. value_type, 3)
end

--A stable string over the parts of a snapshot a reader must not confuse: same inputs give the same fingerprint,
--and any edit that changes what would be solved changes it.
function Snapshot.fingerprint(snapshot)
    return "rrc-snapshot-1:" .. encode_value({targets = snapshot.targets or {}, options = snapshot.options or {}, selection = snapshot.selection or {}})
end

--Which of the five states a sheet is in, given its snapshot and the result the report is currently showing
function Snapshot.state_of(snapshot, result_fingerprint, job_running)
    if snapshot and snapshot.state == "failed" and not job_running then
        return "failed"
    end
    if job_running then
        return "pending"
    end
    if not result_fingerprint then
        return "not_computed"
    end
    if snapshot and snapshot.fingerprint and result_fingerprint == snapshot.fingerprint.input then
        return "current"
    end
    return "stale"
end

return Snapshot
