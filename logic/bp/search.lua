--The loop that tries layouts and keeps the best valid one.
--
--Owned by lane W4-search.  The state below is deliberately a data-only state: a blueprint job can be copied by
--logic/jobs.lua and saved by Factorio between ticks.  The stage modules stay in this module's code, never in the
--state handed to the job.
--
--The search has two bounds with different meanings.  The grid bound means that every permitted grid was tried and
--no candidate validated.  The operation bound means that the search stopped before it could finish.  The latter
--is BP_FAIL_SEARCH_BUDGET, even when an earlier candidate was already valid; a partial search must not claim that
--no layout exists.
local Search = {}

local Grid = require "logic.bp.grid"
local Plan = require "logic.bp.plan"
local Preflight = require "logic.bp.preflight"
local Groups = require "logic.bp.groups"
local Pack = require "logic.bp.pack"
local Route = require "logic.bp.route"
local Power = require "logic.bp.power"
local Validate = require "logic.bp.validate"
local Serialize = require "logic.bp.serialize"

local PHASES = {
    plan = "planning", preflight = "preflight", groups = "grouping", pack = "packing", route = "routing",
    power = "power", validate = "validating", serialize = "serializing", done = "done", failed = "failed",
}

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then return value end
    return fallback
end

local function integer(value, fallback)
    value = finite(value, fallback)
    if value == nil then return nil end
    return math.floor(value)
end

--The copy boundary also protects direct users of Search.begin.  Jobs performs the same boundary when a state is
--put in storage, but Search must not retain a LuaObject or a callback in a state returned to an offline caller.
local function copy(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" or value_type == "number" then return value end
    if value_type ~= "table" then return nil end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        local copied_key = copy(key, seen)
        local copied_child = copy(child, seen)
        if copied_key ~= nil and copied_child ~= nil then result[copied_key] = copied_child end
    end
    seen[value] = nil
    return result
end

local function list_copy(values)
    local result = {}
    for index, value in ipairs(values or {}) do result[index] = copy(value) end
    return result
end

local function stage_done(stage)
    return type(stage) == "table" and stage.done == true
end

local function stage_error(stage)
    if type(stage) ~= "table" then return {{code = "BP_FAIL_NO_LAYOUT_GRID_LIMIT"}} end
    if type(stage.errors) == "table" and #stage.errors > 0 then return copy(stage.errors) end
    return {{code = "BP_FAIL_NO_LAYOUT_GRID_LIMIT"}}
end

local function set_phase(state, phase)
    state.phase = phase
    state.cursor.phase = phase
    state.progress.phase = PHASES[phase] or phase
end

local function failure(state, code, details)
    state.done, state.ok = true, false
    state.phase = "failed"
    state.cursor.phase = "failed"
    state.progress.phase = "failed"
    state.errors = {{code = code}}
    if type(details) == "table" then
        for key, value in pairs(details) do state.errors[1][key] = copy(value) end
    end
    state.result = nil
end

local function search_limits(input)
    local limits = type(input.limits) == "table" and input.limits or {}
    local maximum = input.search_budget or input.max_search_ops or input.max_ops
    maximum = maximum or limits.search_budget or limits.max_search_budget or limits.max_search_ops
        or limits.search_ops or limits.max_ops or limits.max_operations
    maximum = integer(maximum, nil)
    if maximum ~= nil then maximum = math.max(0, maximum) end
    return limits, maximum
end

local function grid_trial_limit(input, limits, grid_count)
    local maximum = input.max_search_grids or input.max_grid_trials
        or limits.max_search_grids or limits.max_grid_trials
    --A sheet may describe the familiar 7x7 grid matrix, but a search job must not turn that
    --description into 49 full pack/route/power searches by default.  Callers with a deliberate
    --larger bound can opt in explicitly; the operation budget still remains authoritative.
    maximum = integer(maximum, 12)
    return math.max(1, math.min(grid_count, maximum))
end

local function ordered_grid_specs(input)
    local explicit = input.grids or input.grid_sizes
    if type(explicit) == "table" and #explicit > 0 then return list_copy(explicit) end

    local model = type(input.grid) == "table" and input.grid or {}
    if model.w ~= nil and model.h ~= nil and model.cols == nil and model.rows == nil then
        return {{w = model.w, h = model.h}}
    end

    local limits = type(input.limits) == "table" and input.limits or {}
    local maximum = input.max_grid or input.grid_limit or limits.max_grid
    local max_cols = input.max_grid_cols or limits.max_grid_cols
    local max_rows = input.max_grid_rows or limits.max_grid_rows
    if type(maximum) == "table" then
        max_cols = max_cols or maximum.cols
        max_rows = max_rows or maximum.rows
    elseif type(maximum) == "number" then
        max_cols, max_rows = max_cols or maximum, max_rows or maximum
    end
    max_cols = integer(max_cols or model.max_cols or model.cols, 8)
    max_rows = integer(max_rows or model.max_rows or model.rows, 8)
    max_cols, max_rows = math.max(2, max_cols), math.max(2, max_rows)

    local result = {}
    for cols = 2, max_cols do
        for rows = 2, max_rows do result[#result + 1] = {cols = cols, rows = rows} end
    end
    table.sort(result, function(a, b)
        local aa, bb = a.cols * a.rows, b.cols * b.rows
        if aa ~= bb then return aa < bb end
        if a.cols ~= b.cols then return a.cols < b.cols end
        return a.rows < b.rows
    end)
    return result
end

local function grid_model(input, raw)
    local source = type(input.grid) == "table" and input.grid or {}
    local catalog = input.catalog or {}
    local robo = catalog.robo or catalog.roboport or {}
    local result = copy(raw) or {}
    if result.w ~= nil and result.h ~= nil and result.cols == nil then
        result.w, result.h = finite(result.w, 0), finite(result.h, 0)
        result.roboports = list_copy(result.roboports)
        return result
    end
    result.cols, result.rows = integer(raw.cols, 2), integer(raw.rows, 2)
    result.tile_w = finite(raw.tile_w, finite(source.tile_w, finite(robo.tile_w, 1)))
    result.tile_h = finite(raw.tile_h, finite(source.tile_h, finite(robo.tile_h, 1)))
    result.max_connection_distance = finite(raw.max_connection_distance,
        finite(source.max_connection_distance, finite(robo.connection_distance, 1)))
    local built = Grid.robo_grid(result)
    built.cols, built.rows = result.cols, result.rows
    built.tile_w, built.tile_h = result.tile_w, result.tile_h
    built.max_connection_distance = result.max_connection_distance
    return built
end

local function grid_area(grid, input)
    local area = input.area or input.pack_area
    if type(area) == "table" and area.w ~= nil and area.h ~= nil then return copy(area) end
    return {x = 0, y = 0, w = finite(grid.w, 0), h = finite(grid.h, 0)}
end

local function roboport_obstacles(grid, input)
    if input.include_roboports == false then return {}, {} end
    local obstacles, entities = {}, {}
    local settings = input.settings or {}
    local selected = settings.roboport or input.roboport
    if type(selected) == "table" then selected = selected.name end
    selected = selected or (input.catalog and input.catalog.robo and input.catalog.robo.name) or "roboport"
    local spec = input.catalog and input.catalog.robo or {}
    for index, raw in ipairs(grid.roboports or {}) do
        local port = copy(raw) or {}
        local id = "k:" .. tostring(index)
        obstacles[#obstacles + 1] = {rect = {x = port.x, y = port.y, w = port.w, h = port.h}, owner = id}
        local entity = copy(spec) or {}
        entity.id, entity.kind, entity.type, entity.name = id, "roboport", "roboport", selected
        entity.x, entity.y, entity.w, entity.h = port.x, port.y, port.w, port.h
        entity.position = {x = port.x + port.w / 2, y = port.y + port.h / 2}
        entity.connection_distance = finite(entity.connection_distance, grid.max_connection_distance)
        entity.logistic_radius = finite(entity.logistic_radius, 0)
        entity.construction_radius = finite(entity.construction_radius, 0)
        entities[#entities + 1] = entity
    end
    return obstacles, entities
end

local function append_all(target, source)
    for _, value in ipairs(source or {}) do target[#target + 1] = copy(value) end
end

local function bare_rects(entries)
    local result = {}
    for _, entry in ipairs(entries or {}) do
        local rect = type(entry) == "table" and (entry.rect or entry)
        if rect then result[#result + 1] = copy(rect) end
    end
    return result
end

local function stage_input(state, extra)
    local result = copy(state.work.input) or {}
    for key, value in pairs(extra or {}) do result[key] = copy(value) end
    return result
end

local function candidate_orders(state, candidate)
    local input = state.work.input
    local supplied = candidate.block_orderings or candidate.orders or input.block_orderings or input.block_orders
    if type(supplied) == "table" and #supplied > 0 and type(supplied[1]) ~= "table" then supplied = {supplied} end
    if type(supplied) ~= "table" or #supplied == 0 then
        local natural = list_copy(candidate.blocks)
        local result = {{blocks = natural}}
        if #natural > 1 then
            local reverse = {}
            for index = #natural, 1, -1 do reverse[#reverse + 1] = copy(natural[index]) end
            result[#result + 1] = {blocks = reverse}
        end
        return result
    end

    local result = {}
    for _, order in ipairs(supplied) do
        local ordered = {}
        if type(order) == "table" then
            local by_id = {}
            for _, block in ipairs(candidate.blocks or {}) do by_id[block.id or block.block_id] = block end
            for _, value in ipairs(order) do
                local block = type(value) == "table" and value or by_id[value]
                if block then ordered[#ordered + 1] = copy(block) end
            end
        end
        if #ordered == #candidate.blocks then result[#result + 1] = {blocks = ordered} end
    end
    if #result == 0 then result[1] = {blocks = list_copy(candidate.blocks)} end
    return result
end

local function block_map(blocks)
    local result = {}
    for _, block in ipairs(blocks or {}) do result[block.id or block.block_id] = block end
    return result
end

local function materialize_candidate(state, candidate, placements)
    local by_id = block_map(candidate.blocks)
    local blocks, entities, ports = {}, {}, {}
    for _, placement in ipairs(placements or {}) do
        local block = by_id[placement.block_id or placement.id]
        if block then
            local placed = Groups.materialize(block, placement)
            blocks[#blocks + 1] = {
                block_id = block.id or block.block_id, id = block.id or block.block_id,
                x = placed.envelope.x, y = placed.envelope.y, w = placed.envelope.w, h = placed.envelope.h,
                dir = placed.envelope.dir, ports = placed.ports,
            }
            append_all(entities, placed.entities)
            append_all(ports, placed.ports)
        end
    end
    return blocks, entities, ports
end

local function lower_name(value)
    return type(value) == "string" and value:lower() or ""
end

local function catalog_entity(catalog, name)
    if type(catalog) ~= "table" or type(name) ~= "string" then return {} end
    local entity = type(catalog.entity) == "table" and catalog.entity[name]
    if entity then return entity end
    for _, family in ipairs({"machine", "beacon", "inserter", "belt", "pipe"}) do
        if type(catalog[family]) == "table" and catalog[family][name] then return catalog[family][name] end
    end
    return {}
end

local function electrical_kind(entity, catalog)
    local declared = lower_name(entity.kind or entity.etype)
    local typed = lower_name(entity.type)
    local name = lower_name(entity.name or entity.entity or entity.prototype)
    local spec = catalog_entity(catalog, entity.name or entity.entity or entity.prototype)
    local catalog_kind = lower_name(spec.kind or spec.etype or spec.type)

    local function classify(value)
        if value == "roboport" or value == "robo" then return "roboport" end
        if value == "machine" or value == "assembler" or value == "assembling-machine" or value == "furnace"
            or value == "rocket-silo" or value == "lab" or value == "mining-drill" then return "machine" end
        if value == "beacon" then return "beacon" end
        if value == "inserter" then return "inserter" end
        if value == "transport" or value == "powered-transport" or value == "belt" or value == "lane" or value == "pipe"
            or value == "transport-belt" or value == "underground-belt" or value == "splitter"
            or value == "pipe-to-ground" then return "transport" end
        return nil
    end

    --Route entities use type = input/output, so an entity kind or a prototype/catalog type wins over that field.
    if declared == "roboport" or typed == "roboport" or catalog_kind == "roboport"
        or name == "roboport" or name:find("roboport", 1, true) then return nil end
    if entity.powered_transport == true or entity.is_powered_transport == true then return "transport" end
    local result = classify(declared) or classify(catalog_kind)
    if result == "roboport" then return nil end
    if result then return result end
    if typed ~= "input" and typed ~= "output" then
        result = classify(typed)
        if result == "roboport" then return nil end
        if result then return result end
    end

    if name == "roboport" or name:find("roboport", 1, true) then return nil end
    if name == "inserter" or name:find("inserter", 1, true) then return "inserter" end
    if name == "beacon" or name:find("beacon", 1, true) then return "beacon" end
    if name == "belt" or name:find("transport%-belt", 1) or name:find("underground%-belt", 1)
        or name:find("splitter", 1, true) or name == "pipe" or name:find("pipe", 1, true) then
        return "transport"
    end
    if name:find("assembling%-machine", 1) or name:find("assembler", 1, true) or name:find("furnace", 1, true)
        or name:find("rocket%-silo", 1) or name:find("mining%-drill", 1)
        or name:find("lab", 1, true) then return "machine" end
    return nil
end

local function entity_rect(entity, catalog)
    local name = entity.name or entity.entity or entity.prototype
    local spec = catalog_entity(catalog, name)
    local size = type(spec.size) == "table" and spec.size or {}
    local w = finite(entity.w, finite(spec.tile_w, finite(size.w, 1)))
    local h = finite(entity.h, finite(spec.tile_h, finite(size.h, 1)))
    local position = type(entity.position) == "table" and entity.position or {}
    local x = finite(entity.x, nil)
    local y = finite(entity.y, nil)
    if x == nil then x = finite(position.x, 0) - w / 2 end
    if y == nil then y = finite(position.y, 0) - h / 2 end
    return {x = x, y = y, w = w, h = h}
end

local function power_consumers(entities, plan, catalog)
    local step_by_id = {}
    for _, step in ipairs(plan and plan.steps or {}) do step_by_id[step.step_id] = step end
    local result = {}
    for _, entity in ipairs(entities or {}) do
        local kind = electrical_kind(entity, catalog)
        if kind == "machine" or kind == "beacon" or kind == "inserter" or kind == "transport" then
            local step = step_by_id[entity.step_id]
            result[#result + 1] = {id = entity.id, rect = entity_rect(entity, catalog),
                power_w = finite(entity.power_w, finite(step and step.power_w, 0))}
        end
    end
    return result
end

local function occupied_rects(entities, roboports, obstacles)
    local result = {}
    for _, entry in ipairs(obstacles or {}) do result[#result + 1] = copy(entry) end
    for _, entity in ipairs(entities or {}) do
        local position = entity.position or {}
        result[#result + 1] = {rect = {
            x = finite(entity.x, finite(position.x, 0) - 0.5), y = finite(entity.y, finite(position.y, 0) - 0.5),
            w = finite(entity.w, 1), h = finite(entity.h, 1),
        }, owner = entity.id}
    end
    for _, entity in ipairs(roboports or {}) do
        result[#result + 1] = {rect = {x = entity.x, y = entity.y, w = entity.w, h = entity.h}, owner = entity.id}
    end
    return result
end

local function make_power_input(state, grid, entities, roboports, obstacles)
    local input = stage_input(state, {
        grid_w = grid.w, grid_h = grid.h,
        consumers = power_consumers(entities, state.work.plan_result, state.work.input.catalog),
        occupied = occupied_rects(entities, roboports, obstacles),
    })
    input.grid = {w = grid.w, h = grid.h}
    if input.pole == nil then
        input.pole = (state.work.input.catalog and state.work.input.catalog.pole)
            or (state.work.input.settings and state.work.input.settings.pole)
    end
    return input
end

--The factory perimeter is not a block envelope: its port occupies the edge cell of the grid.  Keep the
--ordering, pitch and outward-facing direction of Grid.edge_slots without asking it for the tile outside the grid.
local function perimeter_slots(grid, edge, pitch)
    if pitch == nil or pitch <= 0 then error("perimeter slot pitch must be positive", 2) end
    local slots = {}
    local length, origin, direction
    if edge == "top" then
        length, origin, direction = grid.w, {x = 0, y = 0}, Grid.NORTH
    elseif edge == "bottom" then
        length, origin, direction = grid.w, {x = 0, y = grid.h - 1}, Grid.SOUTH
    elseif edge == "left" then
        length, origin, direction = grid.h, {x = 0, y = 0}, Grid.WEST
    elseif edge == "right" then
        length, origin, direction = grid.h, {x = grid.w - 1, y = 0}, Grid.EAST
    else
        error("unknown edge " .. tostring(edge), 2)
    end
    for offset = 0, length - 1, pitch do
        local x, y = origin.x, origin.y
        if edge == "top" or edge == "bottom" then x = x + offset else y = y + offset end
        slots[#slots + 1] = {x = x, y = y, dir = direction}
    end
    return slots
end

local function perimeter_cell_key(x, y)
    return tostring(x) .. ":" .. tostring(y)
end

local function perimeter_port_needs_route(port)
    local rate = port.rate_per_second
    if rate == nil then rate = port.rate end
    return rate == nil or rate > 0
end

local function has_active_perimeter_ports(state)
    for _, port in ipairs(state.work.plan_result.ports or {}) do
        if perimeter_port_needs_route(port) then return true end
    end
    return false
end

local function can_stop_implicit_perimeter_search(state, score)
    local input = state.work.input
    return has_active_perimeter_ports(state) and finite(score and score.beacon_count, 0) == 0
        and input.grids == nil and input.grid_sizes == nil and input.grid == nil
end

local function perimeter_blocked_cells(blocks, obstacles)
    local result = {}
    local function add_rect(raw)
        local rect = type(raw) == "table" and (raw.rect or raw)
        if type(rect) ~= "table" then return end
        for y = rect.y, rect.y + rect.h - 1 do
            for x = rect.x, rect.x + rect.w - 1 do result[perimeter_cell_key(x, y)] = true end
        end
    end
    for _, block in ipairs(blocks or {}) do add_rect(block) end
    for _, obstacle in ipairs(obstacles or {}) do add_rect(obstacle) end
    return result
end

local function generated_perimeter_ports(state, grid, input_edge, output_edge, pitch, blocked)
    local slots = {
        ["in"] = perimeter_slots(grid, input_edge, pitch),
        ["out"] = perimeter_slots(grid, output_edge, pitch),
    }
    local next_slot = {["in"] = 1, ["out"] = 1}
    local occupied = {}
    local external = {}
    for _, port in ipairs(state.work.plan_result.ports or {}) do
        local role = port.role == "in" and "in" or "out"
        local index = next_slot[role]
        while index <= #slots[role] do
            local slot = slots[role][index]
            local key = perimeter_cell_key(slot.x, slot.y)
            if not occupied[key] and (not perimeter_port_needs_route(port) or not blocked[key]) then break end
            index = index + 1
        end
        next_slot[role] = index + 1
        if index > #slots[role] then
            return external, false
        end

        local slot = slots[role][index]
        occupied[perimeter_cell_key(slot.x, slot.y)] = true
        local point = copy(port) or {}
        point.x, point.y = slot.x, slot.y
        point.travel_dir = role == "in" and Grid.dir_opposite(slot.dir) or slot.dir
        external[#external + 1] = point
    end
    return external, true
end

local function perimeter_roboport_clearance(state, grid)
    for _, port in ipairs(state.work.plan_result.ports or {}) do
        if perimeter_port_needs_route(port) then
            local result = {}
            for _, obstacle in ipairs(state.work.robo_obstacles or {}) do
                local rect = obstacle.rect or obstacle
                local x, y = math.max(0, rect.x - 1), math.max(0, rect.y - 1)
                local right = math.min(grid.w, rect.x + rect.w + 1)
                local bottom = math.min(grid.h, rect.y + rect.h + 1)
                if right > x and bottom > y then
                    result[#result + 1] = {x = x, y = y, w = right - x, h = bottom - y}
                end
            end
            return result
        end
    end
    return {}
end

local function make_route_input(state, grid, blocks, ports, obstacles)
    local external = state.work.input.perimeter_ports or state.work.input.perimeter
    if type(external) ~= "table" then
        local settings = state.work.input.settings or {}
        local input_edge = settings.input_edge or state.work.input.input_edge or "left"
        local output_edge = settings.output_edge or state.work.input.output_edge or "top"
        local pitch = finite(state.work.input.port_pitch, 1)
        local complete
        external, complete = generated_perimeter_ports(state, grid, input_edge, output_edge, pitch,
            perimeter_blocked_cells(blocks, obstacles))
        state.work.perimeter_ports = external
        if not complete then return nil end
    else
        external = list_copy(external)
    end
    state.work.perimeter_ports = external
    local input = stage_input(state, {
        grid = {w = grid.w, h = grid.h}, blocks = blocks, perimeter_ports = external,
        flows = state.work.plan_result.flows, obstacles = obstacles,
    })
    input.ports = ports
    return input
end

local function make_candidate(state, grid, blocks, entities, ports, route_result, power_result, roboports)
    local segments = {}
    for _, segment in ipairs(route_result and route_result.segments or {}) do
        local copy_segment = copy(segment) or {}
        copy_segment.id = copy_segment.id or copy_segment.segment_id
        segments[#segments + 1] = copy_segment
    end
    local external_ports = list_copy(state.work.perimeter_ports)
    for _, port in ipairs(external_ports) do port.id = port.id or port.port_id end
    local candidate = {
        grid = {w = grid.w, h = grid.h, cols = grid.cols, rows = grid.rows}, grid_w = grid.w, grid_h = grid.h,
        blocks = blocks, placements = state.work.pack.result.placements, entities = {}, ports = {},
        external_ports = external_ports,
        flows = state.work.plan_result.flows, plan = state.work.plan_result, route = route_result, power = power_result,
        settings = state.work.input.settings, infrastructure = state.work.input.settings,
    }
    append_all(candidate.entities, roboports)
    append_all(candidate.entities, entities)
    append_all(candidate.entities, route_result and route_result.entities)
    append_all(candidate.entities, power_result and power_result.entities)
    candidate.wires = {}
    append_all(candidate.wires, power_result and power_result.wires)
    append_all(candidate.wires, route_result and route_result.wires)
    candidate.segments = segments
    candidate.bindings = route_result and (route_result.port_bindings or route_result.bindings) or {}
    return candidate
end

local function expected_revisions(container, state)
    local revisions = (type(container) == "table" and container.revisions) or state.revisions or {}
    return finite(revisions and revisions.sheet, 0), finite(revisions and revisions.config, 0)
end

local function current_revisions(container, state)
    local input = state.work.input
    local source = state.current_revisions or (type(container) == "table" and container.current_revisions)
        or input.current_revisions or input.revisions_current
    if type(source) == "table" then return finite(source.sheet, 0), finite(source.config, 0), true end
    if container == state and state.initial_revisions then
        local initial = state.initial_revisions
        if state.revisions.sheet ~= initial.sheet or state.revisions.config ~= initial.config then
            return finite(state.revisions.sheet, 0), finite(state.revisions.config, 0), true
        end
    end
    if input.sheet_revision ~= nil or input.config_revision ~= nil then
        return finite(input.sheet_revision, 0), finite(input.config_revision, 0), true
    end
    if type(rawget(_G, "storage")) == "table" and type(container) == "table" and container.player_index ~= nil then
        local player = storage[container.player_index]
        if type(player) == "table" then
            local sheets = type(player.sheet_revision) == "table" and player.sheet_revision or {}
            return finite(sheets[container.sheet_id], 0), finite(player.config_revision, 0), true
        end
    end
    return nil, nil, false
end

local function revisions_match(container, state)
    local expected_sheet, expected_config = expected_revisions(container, state)
    local current_sheet, current_config, known = current_revisions(container, state)
    return not known or (expected_sheet == current_sheet and expected_config == current_config)
end

local function sync_job(container, state)
    if container == state then return end
    container.phase, container.cursor, container.progress = state.phase, state.cursor, state.progress
    container.done, container.ok, container.result, container.errors = state.done, state.ok, state.result, state.errors
    container.incumbent = state.incumbent
end

local function state_of(container)
    if type(container) == "table" and type(container.state) == "table" and (container.kind == "blueprint" or container.revisions) then
        return container.state
    end
    return container
end

local function run_stage(state, field, module, budget)
    local stage = state.work[field]
    local before = finite(budget.ops, 0)
    module.step(stage, budget)
    local after = finite(budget.ops, before)
    local spent = math.max(0, before - after)
    state.ops_used = state.ops_used + spent
    state.progress.done_units = state.progress.done_units + spent
    --A third-party stage must still yield.  The merged stages all spend inside their own work, but this guard
    --keeps a malformed empty stage from making Search.step spin forever.
    if not stage_done(stage) and spent == 0 and budget.ops > 0 then
        budget.ops = budget.ops - 1
        state.ops_used = state.ops_used + 1
    end
    return stage
end

local function budget_limit_reached(state)
    return state.max_ops ~= nil and state.ops_used >= state.max_ops
end

local function start_grid(state)
    local raw = state.work.grid_specs[state.cursor.grid_index]
    if not raw then return false end
    state.work.grid_trials = state.work.grid_trials + 1
    local grid = grid_model(state.work.input, raw)
    local robo_obstacles, roboports = roboport_obstacles(grid, state.work.input)
    state.work.grid = grid
    state.work.robo_obstacles = robo_obstacles
    state.work.roboports = roboports
    state.work.groups = Groups.begin(stage_input(state, {plan = state.work.plan_result, grid = grid}))
    state.work.candidate = nil
    state.work.orderings = nil
    state.work.pack, state.work.route, state.work.power, state.work.validate = nil, nil, nil, nil
    state.cursor.candidate_index, state.cursor.order_index = 1, 1
    set_phase(state, "groups")
    return true
end

local function next_grid(state)
    if state.cursor.grid_index >= #state.work.grid_specs then return false end
    if state.work.grid_trials >= state.work.grid_trial_limit then
        state.work.grid_limit_hit = true
        return false
    end
    state.cursor.grid_index = state.cursor.grid_index + 1
    return start_grid(state)
end

local function fail_revision(state)
    failure(state, "BP_FAIL_REVISION_CHANGED")
end

local function fail_budget(state)
    failure(state, "BP_FAIL_SEARCH_BUDGET")
end

local function candidate_beacon_count(candidate)
    if type(candidate) ~= "table" then return nil end
    local value = candidate.physical_beacon_count
        or candidate.beacon_count
        or (type(candidate.score) == "table" and candidate.score.beacon_count)
    return finite(value, nil)
end

local function record_candidate_bound(state)
    local candidates = state.work.groups and state.work.groups.result
        and state.work.groups.result.candidates
    if type(candidates) ~= "table" then return end
    local lower_bound
    for _, candidate in ipairs(candidates) do
        local count = candidate_beacon_count(candidate)
        if count ~= nil and (lower_bound == nil or count < lower_bound) then lower_bound = count end
    end
    if lower_bound ~= nil then
        local previous = state.work.candidate_beacon_lower_bound
        state.work.candidate_beacon_lower_bound = previous == nil and lower_bound
            or math.min(previous, lower_bound)
    end
end

--Groups enumerates the complete candidate set for a sheet.  A candidate's physical beacon count is
--a lower bound on the validated score: packing, routing and power can add infrastructure, but none
--of those stages can remove a beacon from the candidate.  Once the incumbent reaches that bound,
--no unvisited grid can improve the first (beacon) objective, so compactness and pole tie-breaks do
--not justify another expensive grid.  A larger grid is still visited whenever a lower-beacon
--candidate has not yet been made feasible and validated.
local function can_improve_beacons(state)
    if state.incumbent == nil then return true end
    local bound = state.work.candidate_beacon_lower_bound
    if bound == nil then return false end
    return finite(state.incumbent.score and state.incumbent.score.beacon_count, math.huge) > bound
end

local function begin_serialization(state)
    if state.phase == "serialize" then return true end
    if not revisions_match(nil, state) then fail_revision(state); return false end
    state.work.serializing_candidate = state.incumbent and state.incumbent.candidate
    if state.work.serializing_candidate == nil then return false end
    --Publication is a reserved phase.  Search work is allowed to consume the exploration budget
    --right up to its limit; once a validated incumbent exists, subsequent ticks are reserved for
    --Serialize so a partial search never discards its best complete layout.
    state.work.publication_reserved = true
    state.work.serialize = Serialize.begin(state.work.serializing_candidate)
    set_phase(state, "serialize")
    return true
end

local function finish_search_budget(state)
    if state.incumbent then begin_serialization(state) else fail_budget(state) end
end

function Search.begin(input)
    input = copy(type(input) == "table" and input or {}) or {}
    local limits, max_ops = search_limits(input)
    local state = {
        done = false, ok = nil, phase = "plan", cursor = {phase = "plan", grid_index = 1, candidate_index = 1, order_index = 1},
        incumbent = nil, result = nil, errors = nil, ops_used = 0, max_ops = max_ops,
        revisions = copy(input.revisions) or {sheet = 0, config = 0}, current_revisions = copy(input.current_revisions),
        progress = {phase = "planning", done_units = 0, total_units = nil},
        work = {input = input, limits = limits, grid_specs = ordered_grid_specs(input), plan_state = nil,
            plan_result = nil, preflight = nil, grid = nil, groups = nil, candidate = nil, orderings = nil,
            pack = nil, route = nil, power = nil, validate = nil, serializing_candidate = nil, serialize = nil,
            grid_trials = 0, grid_trial_limit = 0, grid_limit_hit = false,
            candidate_beacon_lower_bound = nil, publication_reserved = false, power_bound_hit = false},
    }
    state.work.grid_trial_limit = grid_trial_limit(input, limits, #state.work.grid_specs)
    state.initial_revisions = copy(state.revisions)
    local supplied_plan = input.plan_result or (type(input.plan) == "table" and input.plan.steps and input.plan)
    if supplied_plan then
        state.work.plan_state = {done = true, ok = true, result = copy(supplied_plan),
            progress = {phase = "planning", done_units = 1, total_units = 1}, cursor = {phase = "done"}}
    else
        state.work.plan_state = Plan.begin(input)
    end
    state.progress.total_units = math.max(1, #state.work.grid_specs)
    return state
end

local function finish_grid_or_search(state)
    if not can_improve_beacons(state) then begin_serialization(state); return end
    if next_grid(state) then return end
    if state.work.grid_limit_hit then finish_search_budget(state); return end
    if state.work.power_bound_hit then finish_search_budget(state); return end
    if state.incumbent then begin_serialization(state) else failure(state, "BP_FAIL_NO_LAYOUT_GRID_LIMIT") end
end

--A grid too small to hold the blocks and the rows their ports need can never produce a layout, and packing it
--anyway costs a full pack plus a full route before it says so. The area check is exact about what it counts and
--cheap: the five-step fixture spends its whole budget on such grids without it.
local function candidate_fits_grid(state, candidate)
    local grid = state.work.grid
    if type(grid) ~= "table" or type(grid.w) ~= "number" or type(grid.h) ~= "number" then return true end
    local needed, widest, tallest = 0, 0, 0
    for _, block in ipairs(candidate.blocks or {}) do
        local sides = type(block.port_sides) == "table" and block.port_sides or {}
        local w = (block.w or 0) + (sides.left and 1 or 0) + (sides.right and 1 or 0)
        local h = (block.h or 0) + (sides.top and 1 or 0) + (sides.bottom and 1 or 0)
        needed = needed + w * h
        widest = math.max(widest, math.min(w, h))
        tallest = math.max(tallest, math.max(w, h))
    end
    if needed > grid.w * grid.h then return false end
    --A block fits in one orientation or the other, so its shorter side must fit the shorter side of the grid.
    if widest > math.min(grid.w, grid.h) then return false end
    if tallest > math.max(grid.w, grid.h) then return false end
    return true
end

local function prepare_candidate(state)
    local candidate = state.work.groups.result.candidates[state.cursor.candidate_index]
    if not candidate then
        finish_grid_or_search(state)
        return false
    end
    if not candidate_fits_grid(state, candidate) then
        state.cursor.candidate_index = state.cursor.candidate_index + 1
        state.cursor.order_index = 1
        return prepare_candidate(state)
    end
    state.work.candidate = candidate
    state.work.orderings = candidate_orders(state, candidate)
    if not state.work.orderings[state.cursor.order_index] then
        state.cursor.candidate_index = state.cursor.candidate_index + 1
        state.cursor.order_index = 1
        return prepare_candidate(state)
    end
    local ordering = state.work.orderings[state.cursor.order_index]
    local obstacles = bare_rects(state.work.robo_obstacles)
    append_all(obstacles, bare_rects(state.work.input.obstacles))
    append_all(obstacles, bare_rects(state.work.input.occupied))
    append_all(obstacles, perimeter_roboport_clearance(state, state.work.grid))
    state.work.pack = Pack.begin({area = grid_area(state.work.grid, state.work.input), obstacles = obstacles,
        blocks = ordering.blocks, limits = state.work.input.limits or {}})
    set_phase(state, "pack")
    return true
end

local function discard_candidate(state)
    state.work.pack, state.work.route, state.work.power, state.work.validate = nil, nil, nil, nil
    state.cursor.order_index = state.cursor.order_index + 1
    if state.work.orderings and state.cursor.order_index <= #state.work.orderings then
        prepare_candidate(state)
    else
        state.cursor.candidate_index = state.cursor.candidate_index + 1
        state.cursor.order_index = 1
        prepare_candidate(state)
    end
end

function Search.step(container, budget)
    local state = state_of(container)
    if type(state) ~= "table" then return container end
    if state.done then sync_job(container, state); return container end
    budget = type(budget) == "table" and budget or {ops = 1}
    budget.ops = math.max(0, integer(budget.ops, 1) or 0)
    if state.max_ops ~= nil and state.phase ~= "serialize" then
        budget.ops = math.min(budget.ops, math.max(0, state.max_ops - state.ops_used))
    end
    if budget.ops <= 0 then
        if state.max_ops ~= nil and budget_limit_reached(state) and state.phase ~= "serialize" then
            finish_search_budget(state)
        end
        sync_job(container, state)
        return container
    end

    while not state.done and budget.ops > 0 do
        if state.phase ~= "serialize" and budget_limit_reached(state) then finish_search_budget(state); break end
        if state.phase == "plan" then
            run_stage(state, "plan_state", Plan, budget)
            if stage_done(state.work.plan_state) then
                if not state.work.plan_state.ok then
                    state.errors = stage_error(state.work.plan_state); state.done, state.ok = true, false; set_phase(state, "failed")
                else
                    state.work.plan_result = state.work.plan_state.result or {}
                    state.work.preflight = Preflight.check(state.work.input.snapshot, state.work.input.solver_result or state.work.input.solver,
                        state.work.input.catalog, state.work.input.options or state.work.input.settings)
                    set_phase(state, "preflight")
                end
            end
        elseif state.phase == "preflight" then
            if type(state.work.preflight) == "table" and #state.work.preflight > 0 then
                state.errors = copy(state.work.preflight); state.done, state.ok = true, false; set_phase(state, "failed")
            else
                start_grid(state)
            end
        elseif state.phase == "groups" then
            run_stage(state, "groups", Groups, budget)
            if stage_done(state.work.groups) then
                record_candidate_bound(state)
                if state.work.groups.ok == false and not (state.work.groups.result and state.work.groups.result.candidates) then
                    if not next_grid(state) then finish_grid_or_search(state) end
                else
                    state.cursor.candidate_index, state.cursor.order_index = 1, 1
                    prepare_candidate(state)
                end
            end
        elseif state.phase == "pack" then
            run_stage(state, "pack", Pack, budget)
            if stage_done(state.work.pack) then
                if not state.work.pack.ok then discard_candidate(state)
                else
                    local blocks, entities, ports = materialize_candidate(state, state.work.candidate,
                        state.work.pack.result and state.work.pack.result.placements)
                    state.work.materialized = {blocks = blocks, entities = entities, ports = ports}
                    local route_input = make_route_input(state, state.work.grid, blocks, ports, state.work.robo_obstacles)
                    if route_input then
                        state.work.route = Route.begin(route_input)
                        set_phase(state, "route")
                    else
                        discard_candidate(state)
                    end
                end
            end
        elseif state.phase == "route" then
            run_stage(state, "route", Route, budget)
            if stage_done(state.work.route) then
                if not state.work.route.ok then discard_candidate(state)
                else
                    local power_entities = list_copy(state.work.materialized.entities)
                    append_all(power_entities, state.work.route.result and state.work.route.result.entities)
                    state.work.power = Power.begin(make_power_input(state, state.work.grid, power_entities,
                        state.work.roboports, state.work.robo_obstacles))
                    set_phase(state, "power")
                end
            end
        elseif state.phase == "power" then
            run_stage(state, "power", Power, budget)
            if stage_done(state.work.power) then
                if not state.work.power.ok then
                    for _, power_error in ipairs(state.work.power.errors or {}) do
                        if power_error.code == "BP_PW_SEARCH_BOUND" then state.work.power_bound_hit = true; break end
                    end
                    discard_candidate(state)
                else
                    local route_result = state.work.route.result or {}
                    local power_result = state.work.power.result or {}
                    state.work.validate_candidate = make_candidate(state, state.work.grid, state.work.materialized.blocks,
                        state.work.materialized.entities, state.work.materialized.ports, route_result, power_result,
                        state.work.roboports)
                    state.work.validate = Validate.begin({candidate = state.work.validate_candidate,
                        plan = state.work.plan_result, catalog = state.work.input.catalog})
                    set_phase(state, "validate")
                end
            end
        elseif state.phase == "validate" then
            run_stage(state, "validate", Validate, budget)
            if stage_done(state.work.validate) then
                if not state.work.validate.ok then discard_candidate(state)
                else
                    local score = state.work.validate.result and state.work.validate.result.score or {}
                    if state.incumbent == nil or Validate.compare(score, state.incumbent.score) < 0 then
                        state.incumbent = {score = copy(score), candidate = copy(state.work.validate_candidate),
                            validation = copy(state.work.validate.result)}
                    end
                    if can_stop_implicit_perimeter_search(state, score) then
                        local candidates = state.work.groups.result.candidates or {}
                        state.cursor.grid_index = #state.work.grid_specs
                        state.cursor.candidate_index = #candidates
                        state.cursor.order_index = #state.work.orderings
                    end
                    discard_candidate(state)
                end
            end
        elseif state.phase == "serialize" then
            if not revisions_match(container, state) then fail_revision(state); break end
            run_stage(state, "serialize", Serialize, budget)
            if stage_done(state.work.serialize) then
                if not revisions_match(container, state) then fail_revision(state)
                elseif state.work.serialize.ok then
                    state.result = copy(state.work.serialize.result)
                    state.done, state.ok = true, true
                    set_phase(state, "done")
                else
                    failure(state, "BP_FAIL_ENTITY_BUDGET")
                end
            end
        elseif state.phase == "failed" or state.phase == "done" then
            state.done = true
        else
            failure(state, "BP_FAIL_NO_LAYOUT_GRID_LIMIT")
        end
    end

    if not state.done and state.phase ~= "serialize" and budget_limit_reached(state) then finish_search_budget(state) end
    sync_job(container, state)
    return container
end

function Search.cancel(container)
    local state = state_of(container)
    if type(state) ~= "table" or state.done then return container end
    state.incumbent, state.result = nil, nil
    failure(state, "BP_FAIL_CANCELLED")
    sync_job(container, state)
    return container
end

--0..1 and a phase key. Held below 1 until a complete result is committed: a bar that reads 100% while work
--continues is a lie the player then has to sit through.
function Search.progress(container)
    local state = state_of(container)
    if type(state) ~= "table" then return 0, "planning" end
    if state.done and state.ok and state.result ~= nil then return 1, "done" end
    local progress = state.progress or {}
    local done_units, total_units = finite(progress.done_units, 0), finite(progress.total_units, nil)
    local fraction
    if total_units and total_units > 0 then
        fraction = math.min(done_units / total_units, 0.999999999)
    else
        fraction = done_units > 0 and done_units / (done_units + 1) or 0
    end
    if fraction >= 1 then fraction = 0.999999999 end
    return fraction, progress.phase or PHASES[state.phase] or "planning"
end

return Search
