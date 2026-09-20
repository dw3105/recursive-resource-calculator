--Versioned offline setup descriptions for golden captures.
--
--This module owns only the harness-side world construction.  Calculation,
--preparation and search remain the production paths exercised by capture_case.
local H = require "tests.harness"
local Settings = require "logic.bp.settings"

local Setup = {}
local FORBIDDEN_GENERATION_OPTIONS = {
    "search_budget", "max_ops", "max_search_grids", "max_grid_trials",
}
Setup.SCHEMA_VERSION = 1

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local function require_field(description, name)
    if type(description) ~= "table" or description[name] == nil then
        error("golden setup is missing " .. name, 3)
    end
    return description[name]
end

local function add_infrastructure(world, infrastructure)
    if infrastructure.default_infrastructure ~= false then
        world.add_default_infrastructure()
        return
    end

    local prototypes = infrastructure.prototypes or {}
    if prototypes.belt then world.add_transport_belt(prototypes.belt) end
    if prototypes.underground_belt then world.add_underground_belt(prototypes.underground_belt) end
    if prototypes.splitter then world.add_splitter(prototypes.splitter) end
    if prototypes.inserter then world.add_inserter(prototypes.inserter) end
    if prototypes.pipe then world.add_pipe(prototypes.pipe) end
    if prototypes.underground_pipe then world.add_pipe_to_ground(prototypes.underground_pipe) end
    if prototypes.pole then world.add_electric_pole(prototypes.pole) end
    if prototypes.roboport then world.add_roboport(prototypes.roboport) end
end

local function add_prototypes(world, facts)
    for _, item in ipairs(facts.items or {}) do world.add_item(item.name, item.fuel) end
    for _, fluid in ipairs(facts.fluids or {}) do world.add_fluid(fluid.name, fluid.fuel) end
    for _, module in ipairs(facts.modules or {}) do
        world.add_module(module.name, module.category, module.effects, module.effects_by_quality)
    end
    for _, machine in ipairs(facts.machines or {}) do world.add_machine(machine) end
    for _, machine in ipairs(facts.machines or {}) do
        if machine.fluid_boxes then
            local boxes = {}
            for index, box in ipairs(machine.fluid_boxes) do boxes[index] = world.fluid_box(box) end
            world.set_fluid_boxes(machine.name, boxes)
        end
    end
    for _, beacon in ipairs(facts.beacons or {}) do world.add_beacon(beacon) end
    for _, recipe in ipairs(facts.recipes or {}) do world.add_recipe(recipe) end
end

function Setup.validate(description)
    local facts = require_field(description, "prototype_facts")
    if description.schema_version ~= Setup.SCHEMA_VERSION then
        error("unsupported golden setup schema " .. tostring(description.schema_version), 2)
    end
    if facts.mocked ~= true then error("golden setup prototype_facts must record mocked = true", 2) end
    require_field(description, "targets")
    require_field(description, "selection")
    require_field(description, "infrastructure")
    require_field(description, "engine_scenario")
    if description.production_case == true and description.setup_id ~= "tiny-chain" then
        for _, key in ipairs(FORBIDDEN_GENERATION_OPTIONS) do
            if type(description.generation) == "table" and description.generation[key] ~= nil then
                error(string.format("production golden case %s refused: %s is not default configuration",
                    tostring(description.setup_id), key), 2)
            end
        end
    end
    if description.production_case == true then
        require_field(description, "mod")
        require_field(description, "research")
        require_field(description, "declared_chain")
        if description.source_kind ~= "harness" or type(description.source_sha) ~= "string" then
            error("golden setup provenance must name a harness source and source SHA", 2)
        end
    end
    return true
end

--Build only the prototype/player world.  Calling control.lua is deliberately
--left to the command or test at top level, while it is being parsed.
function Setup.new_world(description, shape)
    Setup.validate(description)
    local world = H.new_world(shape or description.factorio_branch or "2.0")
    add_prototypes(world, description.prototype_facts)
    add_infrastructure(world, description.infrastructure)
    world.add_blueprint_item()
    world.add_player(1, description.research and description.research.recipe_bonuses or {})
    world.init()
    return world
end

local function apply_selection(world, description, player_index)
    local data = storage[player_index]
    for _, choice in ipairs(description.selection) do
        if choice.product_full_name and choice.recipe_name then
            if choice.consumer then
                world.bind_consumer(choice.product_full_name, choice.recipe_name, player_index)
            else
                world.bind(choice.product_full_name, choice.recipe_name, player_index)
            end
        end
        if choice.machine then
            data.identifiers_of_chosen_crafting_machines_by_recipe_name[choice.recipe_name] = copy(choice.machine)
        end
        if choice.setup then
            data.module_setups_by_recipe_name[choice.recipe_name] = copy(choice.setup)
        end
    end
end

--Use the existing sheet controls and input helper; this does not prepare or
--solve anything.  The caller starts the real sliced calculation afterwards.
function Setup.make_sheet(world, description, player_index)
    player_index = player_index or 1
    apply_selection(world, description, player_index)
    local pane, sheet = H.fill_sheet(description.targets, player_index)
    storage[player_index].sheet_section = {sheet_pane = pane}
    Settings.store(player_index, sheet.tags.hxrrc_sheet_id, description.infrastructure)
    return pane, sheet, sheet.tags.hxrrc_sheet_id
end

local function sorted_keys(values)
    local result = {}
    for value, present in pairs(values or {}) do if present then result[#result + 1] = value end end
    table.sort(result)
    return result
end

local function list_text(values)
    return table.concat(values or {}, ", ")
end

--The solver result is the last graph-shaped object before Generation.start can
--enter planning/layout.  Keep this check here so every corpus setup has the
--same guard against a recipe silently becoming an external import.
function Setup.calculated_graph(result)
    local steps, flows = {}, {}
    for _, column in ipairs(result and result.columns or {}) do
        local step_name = column.recipe_name or column.step_id
        if step_name then steps[step_name] = true end
        for full_name, amount in pairs(column.net_amounts or {}) do
            if type(full_name) == "string" and amount ~= 0 then flows[full_name] = true end
        end
    end
    for full_name, amount in pairs(result and result.solved_rates or {}) do
        if type(full_name) == "string" and amount ~= 0 then flows[full_name] = true end
    end
    for full_name, amount in pairs(result and result.unsolved_rates or {}) do
        if type(full_name) == "string" and amount ~= 0 then flows[full_name] = true end
    end
    return {steps = sorted_keys(steps), flows = sorted_keys(flows)}
end

function Setup.assert_calculated_graph(description, result)
    if type(result) ~= "table" or result.status ~= "ok" then
        error("golden setup " .. tostring(description.setup_id) .. " calculation did not finish successfully", 2)
    end
    local found = Setup.calculated_graph(result)
    local expected = description.declared_chain
    local expected_steps, expected_flows = {}, {}
    for _, name in ipairs(expected.steps or {}) do expected_steps[name] = true end
    for _, name in ipairs(expected.flows or {}) do expected_flows[name] = true end
    local declared = {steps = sorted_keys(expected_steps), flows = sorted_keys(expected_flows)}
    if list_text(found.steps) ~= list_text(declared.steps) then
        error(string.format("golden setup %s calculated step names mismatch; found: %s; expected: %s",
            tostring(description.setup_id), list_text(found.steps), list_text(declared.steps)), 2)
    end
    if list_text(found.flows) ~= list_text(declared.flows) then
        error(string.format("golden setup %s calculated flow list mismatch; found: %s; expected: %s",
            tostring(description.setup_id), list_text(found.flows), list_text(declared.flows)), 2)
    end
    return found
end

return Setup
