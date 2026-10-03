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
local FlowDraw = require "logic.bp.flow_draw"
local Orient = require "logic.bp.orient"
local Belt = require "logic.bp.belt"

local Grid = require "logic.bp.grid"
local Plan = require "logic.bp.plan"
local Preflight = require "logic.bp.preflight"
local Groups = require "logic.bp.groups"
local Pack = require "logic.bp.pack"
local Route = require "logic.bp.route"
local Power = require "logic.bp.power"
local Validate = require "logic.bp.validate"
local Serialize = require "logic.bp.serialize"
local Hands = require "logic.bp.hands"
local Ends = require "logic.bp.ends"
local BeaconPrune = require "logic.bp.beacon_prune"
local RunDir = require "logic.bp.run_dir"
local Seat = require "logic.bp.seat"
local MaterialCost = require "logic.bp.material_cost"

local STRICT_REROUTE_CODES = {
    BP_V_BELT_BLEED = true, BP_V_UNDERGROUND_SIDELOAD_BLOCKED = true, BP_V_ROUTE_DISCONTINUOUS = true,
    BP_V_ROUTE_LOOP = true, BP_V_BELT_NO_SOURCE = true, BP_V_UNDERGROUND_DEAD = true, BP_V_TRANSPORT_UNUSED = true,
}
local candidate_links


--Round 51: ops charged for one Block rebuild (Groups.reorient cache miss), so one rebuild ends a 2000-op step.
local REORIENT_OPS = 2000

local PHASES = {
    plan = "planning", preflight = "preflight", groups = "grouping", draw = "drawing", pack = "packing", route = "routing",
    hands = "hands", power = "power", tidy = "tidying", validate = "validating", serialize = "serializing", done = "done", failed = "failed",
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
    state.progress.stage = phase == "plan" and "prepare" or state.progress.phase
    state.progress.stage_done, state.progress.stage_total = 0, 1
    state.progress.attempt = (state.work.attempt or 0) + 1  --work.attempt counts retries from 0
    state.progress.attempts = 3
end

local function failure(state, code, details)
    state.done, state.ok = true, false
    state.phase = "failed"
    state.cursor.phase = "failed"
    state.progress.phase = "failed"
    --The terminal cause is the first record.  Rejections are evidence about that stop, not a replacement for it;
    --keep both in the same plain-data record so Generation can expose the cause and its reasons separately.
    local previous = type(state.errors) == "table" and copy(state.errors) or {}
    state.errors = {{code = code}}
    if type(details) == "table" then
        for key, value in pairs(details) do state.errors[1][key] = copy(value) end
    end
    local reason_details = state.errors[1].reason_details
    if type(reason_details) ~= "table" then reason_details = {} end
    for _, record in ipairs(previous) do
        local duplicate = false
        for _, existing in ipairs(reason_details) do
            if existing.code == record.code and existing.detail == record.detail then duplicate = true; break end
        end
        if not duplicate and type(record) == "table" and record.code ~= nil then
            reason_details[#reason_details + 1] = copy(record)
        end
    end
    if #reason_details > 0 then state.errors[1].reason_details = reason_details end
    state.result = nil
end

--Every call is ONE candidate attempt that ONE stage refused, and the records are then flattened into a single
--list. Flat, the list cannot answer "how many candidates were judged", so a count of any code is unreadable:
--a change that tries fewer candidates reports fewer errors and looks like an improvement. Stamping the attempt
--ordinal and the refusing stage makes the list countable, which is what lets a census divide a code's count by
--the attempts that reached `validate` instead of comparing raw totals.
local function record_rejection(state, errors, stage)
    local records = state.work.rejections or {}
    state.work.rejections = records
    state.work.rejection_attempts = (state.work.rejection_attempts or 0) + 1
    local attempt = state.work.rejection_attempts
    stage = stage or state.phase
    local seen = false
    for _, entry in ipairs(errors or {}) do
        local record
        if type(entry) == "table" then
            record = copy(entry)
            record.code = record.code or record.reason
        elseif entry ~= nil then
            record = {code = tostring(entry)}
        end
        if type(record) == "table" and record.code ~= nil then
            record.attempt = attempt
            record.stage = stage
            records[#records + 1] = record
            seen = true
        end
    end
    if not seen then records[#records + 1] = {code = "BP_V_UNSPECIFIED", attempt = attempt, stage = stage} end
end

local function rejection_details(state)
    local records = state.work and state.work.rejections
    if type(records) ~= "table" or #records == 0 then return nil end
    return list_copy(records)
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
    maximum = integer(maximum, grid_count)
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

local function spacing_override(input, raw, source)
    local catalog = type(input and input.catalog) == "table" and input.catalog or {}
    local robo = catalog.robo or catalog.roboport or {}
    local candidates = {}
    local function add(value) candidates[#candidates + 1] = value end
    add(raw and raw.max_connection_distance); add(raw and raw.connection_distance)
    add(input and input.max_connection_distance); add(input and input.connection_distance)
    add(source and source.max_connection_distance); add(source and source.connection_distance)
    add(robo and robo.max_connection_distance); add(robo and robo.connection_distance)
    local supplied = input and input.grid_spacing
    if type(supplied) == "table" then
        candidates[#candidates + 1] = supplied.resolved or supplied.value
    end
    for _, value in ipairs(candidates) do
        value = finite(value, nil)
        if value ~= nil then return value end
    end
end

local function resolved_grid_spacing(input, raw)
    local source = type(input.grid) == "table" and input.grid or {}
    local catalog = type(input.catalog) == "table" and input.catalog or {}
    local robo = catalog.robo or catalog.roboport or {}
    local override = spacing_override(input, raw, source)
    if override ~= nil then
        local supplied = input.grid_spacing
        local source_value = type(supplied) == "table" and finite(supplied.source_value, override) or override
        return {resolved = override, kind = "override", source = "caller", source_value = source_value,
            generation_job_id = input.generation_job_id}
    end
    local radius = finite(robo.logistic_radius, 0)
    return {resolved = radius * 2, kind = "derived", source = "logistic_radius", source_value = radius,
        generation_job_id = input.generation_job_id}
end

local function grid_model(input, raw)
    local source = type(input.grid) == "table" and input.grid or {}
    local catalog = input.catalog or {}
    local robo = catalog.robo or catalog.roboport or {}
    local result = copy(raw) or {}
    local spacing = resolved_grid_spacing(input, raw)
    if result.w ~= nil and result.h ~= nil and result.cols == nil then
        result.w, result.h = finite(result.w, 0), finite(result.h, 0)
        result.roboports = list_copy(result.roboports)
        result.grid_spacing = spacing
        return result
    end
    result.cols, result.rows = integer(raw.cols, 2), integer(raw.rows, 2)
    result.tile_w = finite(raw.tile_w, finite(source.tile_w, finite(robo.tile_w, 1)))
    result.tile_h = finite(raw.tile_h, finite(source.tile_h, finite(robo.tile_h, 1)))
    --Roboport gap. An explicit caller value still wins. Otherwise it is derived from the roboport's own
    --logistic radius: two roboports share a network when their logistic areas meet, so the widest spacing is
    --logistic_radius * 2. Measured against a player blueprint of four unmodded roboports at maximum
    --connection distance, 2.0.77: adjacent centres exactly 50 tiles apart, logistic_radius 25.
    --The old literal 1 fell back to a one-tile gap on the real engine, because it asked catalog.robo for
    --connection_distance, a member only rolling stock has. An 8x8 grid then measured 11x11 tiles and no
    --candidate could ever fit.
    result.max_connection_distance = spacing.resolved
    local built = Grid.robo_grid(result)
    built.cols, built.rows = result.cols, result.rows
    built.tile_w, built.tile_h = result.tile_w, result.tile_h
    built.max_connection_distance = result.max_connection_distance
    built.grid_spacing = spacing
    return built
end

local function grid_area(grid, input)
    local area = input.area or input.pack_area
    if type(area) == "table" and area.w ~= nil and area.h ~= nil then return copy(area) end
    return {x = 0, y = 0, w = finite(grid.w, 0), h = finite(grid.h, 0)}
end

--Edge inset (round 54): a Block packed one tile from the input edge leaves no corridor for the edge feeds (EM plant
--Flip: five feeds and two fluid fronts in columns 0-1, every way refused). When every attempt failed, pack keeps
--`edge_inset` tiles free along the input edge (`discard_candidate`). Only failing sheets get it.
local function pack_area(state, input_edge)
    local input = state.work.input
    local area = grid_area(state.work.grid, input)
    local inset = state.work.edge_inset or 0
    if inset <= 0 or input.area or input.pack_area then return area end
    if input_edge == "left" then area.x, area.w = area.x + inset, area.w - inset
    elseif input_edge == "right" then area.w = area.w - inset
    elseif input_edge == "top" then area.y, area.h = area.y + inset, area.h - inset
    elseif input_edge == "bottom" then area.h = area.h - inset end
    return area
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

--`port_flow_id` is defined below, next to the other port helpers, but greedy_block_order reads it. A Lua local
--is invisible above its own declaration, so the call at interface_weight resolved to a nil GLOBAL and the real
--player case died with "attempt to call global 'port_flow_id' (a nil value)" inside search.lua:320. The lane's
--focused tests never drove prepare_candidate down that path, so nothing caught it before the merge.
local port_flow_id

local function greedy_block_order(state, candidate)
    local natural = list_copy(candidate.blocks)
    local result = {}
        local function interface_weight(left, right)
            local weight = 0
            for _, source in ipairs(left.ports or left.block_ports or {}) do
                for _, target in ipairs(right.ports or right.block_ports or {}) do
                    local source_flow, target_flow = port_flow_id(source), port_flow_id(target)
                    if source_flow ~= nil and source_flow == target_flow
                        and source.role ~= target.role then
                        weight = weight + math.max(1, finite(source.rate_per_second, finite(target.rate_per_second, 0)))
                    end
                end
            end
            return weight
        end
        if #natural > 1 then
            local connected, remaining = {copy(natural[1])}, {}
            for index = 2, #natural do remaining[#remaining + 1] = natural[index] end
            while #remaining > 0 do
                local best_index, best_weight, best_id
                for index, block in ipairs(remaining) do
                    local weight = 0
                    for _, placed in ipairs(connected) do weight = weight + interface_weight(placed, block) end
                    local id = tostring(block.id or block.block_id or "")
                    if best_index == nil or weight > best_weight or (weight == best_weight and id < best_id) then
                        best_index, best_weight, best_id = index, weight, id
                    end
                end
                connected[#connected + 1] = copy(remaining[best_index])
                table.remove(remaining, best_index)
            end
            local differs = false
            for index, block in ipairs(connected) do
                if (block.id or block.block_id) ~= (natural[index].id or natural[index].block_id) then differs = true; break end
            end
            if differs then result[#result + 1] = {blocks = connected} end
        end
    if #result == 0 then return natural end
    return result[1].blocks
end

local function block_map(blocks)
    local result = {}
    for _, block in ipairs(blocks or {}) do result[block.id or block.block_id] = block end
    return result
end

local function manhattan(a, b) return math.abs(a.x - b.x) + math.abs(a.y - b.y) end
local function partner_id(entry)
    if type(entry) == "table" then return entry.step_id or entry.block_id or entry.id or entry.owner_id end
    return entry
end

-- Pick each row run independently. The partner locations come from the flow graph; external
-- partners sit on the same perimeter edge used later to make router terminals.
local function materialize_candidate(state, candidate, placements)
    local by_id = block_map(candidate.blocks)
    local blocks, entities, ports = {}, {}, {}
    local placement_by_id, placed_in_order = {}, {}
    for _, p in ipairs(placements or {}) do placement_by_id[p.block_id or p.id] = p end
    for _, b in ipairs(candidate.blocks or {}) do placed_in_order[#placed_in_order + 1] = placement_by_id[b.id or b.block_id] end
    local settings = state.work.input.settings or {}
    local input_edge = settings.input_edge or state.work.input.input_edge or "left"
    local output_edge = settings.output_edge or state.work.input.output_edge or "top"
    for _, placement in ipairs(placements or {}) do
        local block = by_id[placement.block_id or placement.id]
        if block then
            block = RunDir.choose(block, placement, candidate.blocks, placed_in_order, state.work.grid,
                state.work.plan_result.flows, input_edge, output_edge, state.work.robo_obstacles)
            local placed = Groups.materialize(block, placement)
            blocks[#blocks + 1] = {
                block_id = block.id or block.block_id, id = block.id or block.block_id,
                x = placed.envelope.x, y = placed.envelope.y, w = placed.envelope.w, h = placed.envelope.h,
                dir = placed.envelope.dir, ports = placed.ports, belt_runs = placed.belt_runs,
            }
            append_all(entities, placed.entities)
            append_all(ports, placed.ports)
        end
    end
    return blocks, entities, ports
end

--`materialized.ports` and each `blocks[i].ports` hold separate copies of one port (append_all copies), and
--Route reads the block copies.  A slide must reach every copy.
local Hands = require "logic.bp.hands"

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

--Electrical demand comes from normalized prototype data, never from an entity's transport role. A plain belt
--or pipe has no energy source, so it adds no consumer; a modded belt whose catalog entry declares needs_power
--does. The validator reads the same two fields in the same order (validate.lua needs_power), so planner and
--checker cannot drift apart silently.
local function declared_power_need(entity, catalog)
    if type(entity) ~= "table" then return nil end
    if entity.needs_power ~= nil then return entity.needs_power == true end
    local spec = catalog_entity(catalog, entity.name or entity.entity or entity.prototype)
    if spec.needs_power ~= nil then return spec.needs_power == true end
    return nil
end

local function requires_power(entity, catalog, kind)
    if kind == nil or kind == "roboport" then return false end
    local declared = declared_power_need(entity, catalog)
    if declared ~= nil then return declared end
    if kind == "transport" then
        return entity.powered_transport == true or entity.is_powered_transport == true
    end
    return kind == "machine" or kind == "beacon" or kind == "inserter"
end

local function power_consumers(entities, plan, catalog)
    local step_by_id = {}
    for _, step in ipairs(plan and plan.steps or {}) do step_by_id[step.step_id] = step end
    local result = {}
    for _, entity in ipairs(entities or {}) do
        local kind = electrical_kind(entity, catalog)
        if requires_power(entity, catalog, kind) then
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
        local name = lower_name(entity.name or entity.entity or entity.prototype)
        local kind = lower_name(entity.kind or entity.etype)
        if kind == "transport" or kind == "powered-transport" then
            if name:find("underground", 1, true) then kind = "underground"
            elseif name:find("splitter", 1, true) then kind = "splitter"
            elseif name:find("pipe", 1, true) then kind = "pipe"
            else kind = "belt" end
        elseif kind == "" then
            if name:find("inserter", 1, true) then kind = "inserter"
            elseif name:find("roboport", 1, true) then kind = "roboport"
            elseif name:find("underground", 1, true) then kind = "underground"
            elseif name:find("splitter", 1, true) then kind = "splitter"
            elseif name:find("pipe", 1, true) then kind = "pipe"
            elseif name:find("belt", 1, true) then kind = "belt"
            elseif electrical_kind(entity, {}) == "machine" then kind = "machine" end
        end
        result[#result + 1] = {rect = {
            x = finite(entity.x, finite(position.x, 0) - 0.5), y = finite(entity.y, finite(position.y, 0) - 0.5),
            w = finite(entity.w, 1), h = finite(entity.h, 1),
        }, owner = entity.id, kind = kind ~= "" and kind or nil}
    end
    for _, entity in ipairs(roboports or {}) do
        result[#result + 1] = {rect = {x = entity.x, y = entity.y, w = entity.w, h = entity.h}, owner = entity.id, kind = "roboport"}
    end
    return result
end

--Power may bury a belt or slide a hand to make room for a pole; it asks through this callback.  A function is never
--saved in storage (the blueprint job lives there between ticks), so the callback is attached only while power
--steps and removed after (round 33: the job record was deep-copied every tick until then, which hid it).
local function power_make_room(state)
    return function(x, y)
        if Route.free_cell(state.work.route_state or state.work.route, x, y) then return true end
        return Hands.free_cell(state.work.materialized, x, y)
    end
end

local function power_room(state, attach)
    local work = state.work.power and state.work.power._work
    if type(work) == "table" then work.make_room = attach and power_make_room(state) or nil end
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

local function mark_perimeter_port_cells(blocked, block)
    local placement = {x = finite(block.x, 0), y = finite(block.y, 0), dir = finite(block.dir, Grid.NORTH)}
    for _, port in ipairs(block.ports or block.block_ports or {}) do
        local x, y = finite(port.x), finite(port.y)
        local direction = port.travel_dir or port.dir or port.normal_dir
        if x == nil or y == nil then
            local frame = {w = finite(port._block_w, finite(block.w, 1)), h = finite(port._block_h, finite(block.h, 1))}
            local placed = Grid.place_port(frame, placement, port)
            x, y = placed.x, placed.y
            direction = direction and Grid.rotate_dir(direction, placement.dir) or placed.dir
        end
        if x ~= nil and y ~= nil then
            blocked[perimeter_cell_key(x, y)] = true
            local dx, dy = Grid.dir_vector(direction or Grid.NORTH)
            if dx ~= nil and dy ~= nil then
                --The approach tile is kept for the port's own flow: an edge terminal of that flow standing there
                --feeds the port straight on (red science 10/s, 2026-09-25: the only straight way into a foundry
                --hand's port tile was that edge tile, and reserving it from every flow left the hand unfed).
                local keep = port_flow_id(port) or true
                local key
                if port.role == "in" then key = perimeter_cell_key(x - dx, y - dy)
                elseif port.role == "out" then key = perimeter_cell_key(x + dx, y + dy) end
                if key then blocked[key] = blocked[key] == nil and keep or (blocked[key] == keep and keep or true) end
            end
        end
    end
end

--A reserved perimeter cell stays usable by a terminal of the one flow it was reserved for -- only once an attempt
--has starved an edge flow (`edge_split_flows`); a sheet that routes as it is keeps its terminals.
local function perimeter_cell_free(state, blocked, key, port)
    local mark = blocked[key]
    if mark == nil then return true end
    return mark ~= true and Seat.approach_open(state) and mark == port_flow_id(port)
end

local function perimeter_port_needs_route(port)
    local rate = port.rate_per_second
    if rate == nil then rate = port.rate end
    return rate == nil or rate > 0
end

function port_flow_id(port)
    return port and (port.flow_id or port.full_name or port.flow)
end

local function positive(value)
    value = finite(value, nil)
    return value and value > 0 and value or nil
end

local function first_positive(sources, fields)
    for _, source in ipairs(sources or {}) do
        if type(source) == "table" then
            for _, field in ipairs(fields or {}) do
                local value = positive(source[field])
                if value ~= nil then return value end
            end
        end
    end
end

local function entry_id(entry)
    return entry and (entry.step_id or entry.id or entry.block_id)
end

local function flow_for_port(state, port)
    local flow_id = port_flow_id(port)
    if flow_id == nil then return nil end
    for _, flow in ipairs(state.work.plan_result.flows or {}) do
        local candidate_id = flow.flow_id or flow.full_name or flow.id
        if candidate_id == flow_id then return flow end
    end
    return nil
end

local function terminal_capacity(state, network)
    local input = state and state.work and state.work.input or {}
    local port, flow = network.port or {}, network.flow or {}
    local family = "item"
    if port.kind == "fluid" or port.is_fluid == true or flow.is_fluid == true then family = "fluid" end
    local explicit = first_positive({network, port, flow, input}, {
        "terminal_capacity_per_second", "terminal_capacity", "external_capacity_per_second",
        "external_terminal_capacity", "capacity_per_second", "capacity",
    })
    if explicit ~= nil then return explicit, "declared" end

    local family_input = family == "fluid" and input.pipe_capacity or input.belt_capacity
    if positive(family_input) ~= nil then return positive(family_input), "input" end
    local catalog = type(input.catalog) == "table" and input.catalog or {}
    local details = family == "fluid" and (catalog.pipe or {}) or (catalog.belt or {})
    local capacity = first_positive({details}, family == "fluid"
        and {"throughput_per_second", "capacity_per_second"}
        or {"items_per_second", "capacity_per_second"})
    if family == "item" and Belt.is_external_item(flow) and capacity then capacity = capacity * Belt.stack_max(catalog) end
    if capacity ~= nil then return capacity, "catalog" end
    return nil, "unbounded"
end

local function terminal_branch_limit(state, network)
    local input = state and state.work and state.work.input or {}
    local port, flow = network.port or {}, network.flow or {}
    --A flow from the map edge that route could not bring to every sink through one terminal gets one terminal per
    --sink on the next try (marked in `note_edge_shortfalls`). Any flow, never a named one.
    local split = state and state.work and state.work.edge_split_flows
    local flow_key = port.flow_id or port.full_name or flow.flow_id or flow.full_name
    if split and flow_key and split[flow_key] then return 1 end
    return first_positive({network, port, flow, input}, {
        "max_branches_per_terminal", "terminal_branch_capacity", "max_terminal_branches",
        "max_branching_factor", "branching_factor", "max_fanout", "fanout",
        "max_branches", "branch_capacity", "legal_branching",
    })
end

--Size edge endpoints from the work carried by one compatible supply network. The first endpoint is the
--network itself; additional endpoints are justified only by a declared transport capacity or an explicit
--branching limit. Demand entries are used for legal branching, never as a proxy for capacity.
--This is an anonymous assignment rather than `local function` so the lane's red mutation can replace the call
--without turning the required mutation into a syntax error.
local terminals_for_demand = function(state, network)
    local port, flow = network.port or {}, network.flow or {}
    local role = network.role or (port.role == "in" and "in" or "out")
    local external_side = role == "in" and flow.producers or flow.consumers
    local demand_side = role == "in" and flow.consumers or flow.producers
    local has_external, demand, branches = false, 0, 0
    for _, entry in ipairs(external_side or {}) do
        if entry_id(entry) == "$external" then has_external = true end
    end
    if has_external then
        for _, entry in ipairs(demand_side or {}) do
            if entry_id(entry) ~= "$external" then
                demand = demand + math.max(0, finite(entry.share_per_second, finite(entry.rate_per_second,
                    finite(entry.rate, 0))))
                branches = branches + 1
            end
        end
    end
    if demand <= 0 then
        --A hand-built plan may omit flow shares. Its port rate is still a demand; an absent flow is not a
        --reason to resurrect headcount sizing.
        for _, value in ipairs(network.ports or {}) do
            demand = demand + math.max(0, finite(value.rate_per_second, finite(value.rate, 0)))
        end
        demand = math.max(demand, math.max(0, finite(port.rate_per_second, finite(port.rate, 0))))
    end

    local capacity, capacity_source = terminal_capacity(state, network)
    local branch_limit = terminal_branch_limit(state, network)
    local capacity_terminals = 1
    if capacity ~= nil and demand > capacity then
        capacity_terminals = math.max(1, math.ceil(demand / capacity - math.max(1e-9, demand * 1e-9)))
    end
    local branch_terminals = 1
    if branch_limit ~= nil and branches > branch_limit then
        branch_terminals = math.max(1, math.ceil(branches / branch_limit))
    end
    local count = math.max(1, capacity_terminals, branch_terminals)
    local reasons = {}
    if capacity_terminals > 1 then
        reasons[#reasons + 1] = {kind = "capacity", detail = "aggregate demand exceeds terminal capacity",
            demand_per_second = demand, capacity_per_second = capacity, capacity_source = capacity_source,
            terminals = capacity_terminals}
    end
    if branch_terminals > 1 then
        reasons[#reasons + 1] = {kind = "feasibility", detail = "legal branching limit requires another terminal",
            branches = branches, branch_limit = branch_limit, terminals = branch_terminals}
    end
    return {
        count = count, demand_per_second = demand, capacity_per_second = capacity,
        capacity_source = capacity_source, capacity_terminals = capacity_terminals,
        branch_count = branches, branch_limit = branch_limit, branch_terminals = branch_terminals,
        reasons = reasons,
    }
end

Search.terminals_for_demand = terminals_for_demand

local function terminal_network_key(port)
    local flow_id = port_flow_id(port) or (port.port_id or port.id or "unknown")
    local role = port.role == "in" and "in" or "out"
    local kind = port.kind or (port.is_fluid and "fluid" or "item")
    return table.concat({tostring(role), tostring(flow_id), tostring(kind)}, "\0")
end

local function terminal_networks(state)
    local result, by_key = {}, {}
    for _, port in ipairs(state.work.plan_result.ports or {}) do
        local key = terminal_network_key(port)
        local network = by_key[key]
        if not network then
            network = {key = key, port = port, ports = {}, role = port.role == "in" and "in" or "out",
                flow = flow_for_port(state, port)}
            by_key[key] = network
            result[#result + 1] = network
        end
        network.ports[#network.ports + 1] = port
    end
    return result
end

local function port_first_belt(port)
    local x, y = finite(port.x), finite(port.y)
    local direction = finite(port.travel_dir)
    if x == nil or y == nil or direction == nil then return nil end
    local dx, dy = Grid.dir_vector(direction)
    if dx == nil then return nil end
    local sign = port.role == "in" and -1 or 1
    return {x = x + sign * dx, y = y + sign * dy}
end

local function terminal_consumers(state, network)
    local flow = network.flow or {}
    local sinks = network.role == "in" and flow.consumers or flow.producers
    local wanted = {}
    for _, entry in ipairs(sinks or {}) do
        local id = entry_id(entry)
        if id and id ~= "$external" then wanted[id] = true end
    end
    local result = {}
    for _, block in ipairs(state.work.materialized and state.work.materialized.blocks or {}) do
        for _, port in ipairs(block.ports or {}) do
            local id = port.block_id or port.step_id or port.owner_id or port.owner
            if port_flow_id(port) == port_flow_id(network.port) and wanted[id] then
                local x, y = finite(port.x), finite(port.y)
                if x == nil or y == nil then
                    --A rotated placement keeps source-frame attach geometry (Groups.materialize); place it as
                    --mark_perimeter_port_cells does.
                    local frame = {w = finite(port._block_w, finite(block.w, 1)), h = finite(port._block_h, finite(block.h, 1))}
                    local placed = Grid.place_port(frame, {x = finite(block.x, 0), y = finite(block.y, 0),
                        dir = finite(block.dir, Grid.NORTH)}, port)
                    x, y = placed.x, placed.y
                end
                if x ~= nil and y ~= nil then
                    local point = port_first_belt(port) or {x = x, y = y}
                    result[#result + 1] = point
                end
            end
        end
    end
    return result
end

local function slot_cost(slot, consumers)
    local cost = 0
    local x, y = slot.x, slot.y
    local visited = {}
    --On the measured copper-ore row, summing distances tied (0,24) through (0,28) and picked (0,25),
    --between the two consumers. Price the single one-way run instead.
    for _ = 1, #consumers do
        local nearest_index, nearest_distance
        for index, point in ipairs(consumers) do
            if not visited[index] then
                local distance = math.abs(x - point.x) + math.abs(y - point.y)
                if nearest_index == nil or distance < nearest_distance
                    or (distance == nearest_distance and (point.y < consumers[nearest_index].y
                        or (point.y == consumers[nearest_index].y and point.x < consumers[nearest_index].x))) then
                    nearest_index, nearest_distance = index, distance
                end
            end
        end
        local point = consumers[nearest_index]
        cost = cost + nearest_distance
        x, y = point.x, point.y
        visited[nearest_index] = true
    end
    return cost
end

local function perimeter_blocked_cells(blocks, obstacles)
    --`__walls` keeps the Block cells apart from port reservations: only a Block wall kills an edge slot.
    local result = {__walls = {}}
    local function add_rect(raw, wall)
        local rect = type(raw) == "table" and (raw.rect or raw)
        if type(rect) ~= "table" then return end
        for y = rect.y, rect.y + rect.h - 1 do
            for x = rect.x, rect.x + rect.w - 1 do
                result[perimeter_cell_key(x, y)] = true
                if wall then result.__walls[perimeter_cell_key(x, y)] = true end
            end
        end
    end
    for _, block in ipairs(blocks or {}) do
        --Blocks only: roboport clearance obstacles bind pack, a route crosses them (am2 chain copper ore (0,21)).
        add_rect(block, true)
        mark_perimeter_port_cells(result, block)
    end
    for _, obstacle in ipairs(obstacles or {}) do add_rect(obstacle) end
    return result
end

--Fluid edge spread (round 54): two fluids whose port tiles sit side by side under one machine (refinery water
--and crude, Turn 0) both want the edge tile level with them; the farther one took it and walled the nearer one in
--(BP_R_NO_PATH). After an edge fluid came up short (`note_edge_shortfalls`), fluid slots go nearest first and a
--slot is kept only when a straight L path from it to its port tiles stays clear of every other fluid's path and
--of the tiles beside that path.
local function fluid_l_path(slot, consumers, blocked, flow_id, taken)
    local cells, x, y = {}, slot.x, slot.y
    local function walk(tx, ty, horizontal_first)
        local out, cx, cy = {}, x, y
        local function step_to(nx, ny)
            while cx ~= nx do cx = cx + (nx > cx and 1 or -1); out[#out + 1] = {cx, cy} end
            while cy ~= ny do cy = cy + (ny > cy and 1 or -1); out[#out + 1] = {cx, cy} end
        end
        if horizontal_first then step_to(tx, cy); step_to(tx, ty) else step_to(cx, ty); step_to(tx, ty) end
        for index, cell in ipairs(out) do
            local key = perimeter_cell_key(cell[1], cell[2])
            local mark = blocked[key]
            if index < #out and mark ~= nil and mark ~= flow_id then return nil end
            local other = taken[key]
            if other and other ~= flow_id then return nil end
        end
        return out
    end
    if taken[perimeter_cell_key(x, y)] and taken[perimeter_cell_key(x, y)] ~= flow_id then return nil end
    cells[1] = {x, y}
    local visited = {}
    for _ = 1, #consumers do
        local nearest
        for index, point in ipairs(consumers) do
            if not visited[index] and (nearest == nil or math.abs(point.x - x) + math.abs(point.y - y)
                < math.abs(consumers[nearest].x - x) + math.abs(consumers[nearest].y - y)) then nearest = index end
        end
        visited[nearest] = true
        local point = consumers[nearest]
        local leg = walk(point.x, point.y, true) or walk(point.x, point.y, false)
        if not leg then return nil end
        for _, cell in ipairs(leg) do cells[#cells + 1] = cell end
        x, y = point.x, point.y
    end
    return cells
end

local function claim_fluid_path(taken, cells, flow_id)
    for _, cell in ipairs(cells) do
        for _, d in ipairs({{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local key = perimeter_cell_key(cell[1] + d[1], cell[2] + d[2])
            if taken[key] == nil then taken[key] = flow_id elseif taken[key] ~= flow_id then taken[key] = true end
        end
    end
end

local function generated_perimeter_ports(state, grid, input_edge, output_edge, pitch, blocked)
    local slots = {
        ["in"] = perimeter_slots(grid, input_edge, pitch),
        ["out"] = perimeter_slots(grid, output_edge, pitch),
    }
    local next_slot = {["in"] = 1, ["out"] = 1}
    local occupied = {}
    local fluid_doors = {}
    local external = {}
    local sizing = {}
    local networks = terminal_networks(state)
    for _, network in ipairs(networks) do
        network.consumers = terminal_consumers(state, network)
        local best
        for _, slot in ipairs(slots[network.role]) do
            local key = perimeter_cell_key(slot.x, slot.y)
            if not occupied[key] and (not perimeter_port_needs_route(network.port) or perimeter_cell_free(state, blocked, key, network.port)) then
                local cost = slot_cost(slot, network.consumers)
                if best == nil or cost < best then best = cost end
            end
        end
        network.need = best or math.huge
    end
    local spread = state.work.fluid_edge_spread
    local fluid_taken = {}
    table.sort(networks, function(a, b)
        if a.need ~= b.need then
            if spread then return a.need < b.need end
            return a.need > b.need
        end
        return a.key < b.key
    end)
    for _, network in ipairs(networks) do
        local port = network.port
        local role = network.role
        local sizing_result = terminals_for_demand(state, network)
        --Keep a malformed sizing provider a bounded one-terminal decision. This also keeps a mutation of the
        --mandated sizing call observable as a wrong layout, rather than turning the proof into an incidental Lua
        --field-access error.
        if type(sizing_result) ~= "table" then
            sizing_result = {count = 1, demand_per_second = 0, capacity_per_second = nil,
                capacity_source = "invalid", branch_count = 0, branch_limit = nil, reasons = {}}
        end
        sizing[#sizing + 1] = {
            network = network.key, flow_id = port_flow_id(port), role = role,
            demand_per_second = sizing_result.demand_per_second,
            capacity_per_second = sizing_result.capacity_per_second,
            capacity_source = sizing_result.capacity_source,
            branch_count = sizing_result.branch_count, branch_limit = sizing_result.branch_limit,
            terminal_count = sizing_result.count, reasons = copy(sizing_result.reasons),
        }
        local requested = sizing_result.count
        local base_id = port.port_id or port.id or port_flow_id(port) or role
        for copy_index = 1, requested do
            local index, best_cost
            for _, strict in ipairs(spread and {true, false} or {false}) do if index == nil then
            for candidate_index, candidate_slot in ipairs(slots[role]) do
                local key = perimeter_cell_key(candidate_slot.x, candidate_slot.y)
                local fluid_near = false
                if tostring(port_flow_id(port)):sub(1, 6) == "fluid/" then
                    for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                        local neighbor = fluid_doors[perimeter_cell_key(candidate_slot.x + d[1], candidate_slot.y + d[2])]
                        if neighbor and neighbor ~= port_flow_id(port) then fluid_near = true end
                    end
                end
                if strict and not fluid_near and tostring(port_flow_id(port)):sub(1, 6) == "fluid/"
                    and not fluid_l_path(candidate_slot, network.consumers, blocked, port_flow_id(port), fluid_taken) then
                    fluid_near = true
                end
                --An edge terminal leaves straight inward; a slot whose inward tile is a Block wall is dead (chemical
                --plant plastic Turn 4: water slot (0,18) faced the turned machine at (1,18), BP_R_NO_PATH).
                --Inputs only: an output's last belt may reach its slot sideways and turn out (am2 chain layered
                --bytes moved when outputs were held to this too).
                --Only on the retry after an edge fluid came up short (`fluid_edge_spread`): am2 chain's copper ore and
                --molten iron slots face a Block yet route today (an edge tile may turn).
                --In the last-resort inset phase the inward tile must be free of any other reservation too (cryo plant
                --x4 Turn 8 needs it; on first routing it moved player-red-science-1s-foundry bytes).
                local last_resort = (state.work.edge_inset or 0) > 0
                if (spread or last_resort) and not fluid_near and role == "in" and perimeter_port_needs_route(port) then
                    local ddx, ddy = Grid.dir_vector(candidate_slot.dir)
                    local ix, iy = candidate_slot.x - (ddx or 0), candidate_slot.y - (ddy or 0)
                    if ddx and blocked.__walls and blocked.__walls[perimeter_cell_key(ix, iy)] then fluid_near = true end
                    local inward = ddx and blocked[perimeter_cell_key(ix, iy)]
                    if last_resort and inward ~= nil and inward ~= port_flow_id(port) then fluid_near = true end
                    --A fluid's first pipe also must not touch another fluid's reserved front tile (EM plant Flip:
                    --heavy oil slot (0,18) stepped to (1,18), beside a pipe front at (1,17), BP_R_FLUID_MIX).
                    local own = port_flow_id(port)
                    if ddx and tostring(own):sub(1, 6) == "fluid/" then
                        for _, d in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                            local mark = blocked[perimeter_cell_key(ix + d[1], iy + d[2])]
                            if type(mark) == "string" and mark:sub(1, 6) == "fluid/" and mark ~= own then fluid_near = true end
                        end
                    end
                end
                if not fluid_near and not occupied[key] and (not perimeter_port_needs_route(port) or perimeter_cell_free(state, blocked, key, port)) then
                    local cost = slot_cost(candidate_slot, network.consumers)
                    if index == nil or cost < best_cost or (cost == best_cost and candidate_index < index) then
                        index, best_cost = candidate_index, cost
                    end
                end
            end
            end end
            index = index or (#slots[role] + 1)
            while index <= #slots[role] do
                local slot = slots[role][index]
                local key = perimeter_cell_key(slot.x, slot.y)
                if not occupied[key] and (not perimeter_port_needs_route(port) or perimeter_cell_free(state, blocked, key, port)) then break end
                index = index + 1
            end
            next_slot[role] = math.max(next_slot[role], index + 1)
            if index > #slots[role] then
                return external, false
            end

            local slot = slots[role][index]
            occupied[perimeter_cell_key(slot.x, slot.y)] = true
            if tostring(port_flow_id(port)):sub(1, 6) == "fluid/" then
                fluid_doors[perimeter_cell_key(slot.x, slot.y)] = port_flow_id(port)
                local cells = spread and fluid_l_path(slot, network.consumers, blocked, port_flow_id(port), fluid_taken)
                if cells then claim_fluid_path(fluid_taken, cells, port_flow_id(port)) end
            end
            local point = copy(port) or {}
            point.port_id = copy_index == 1 and base_id or (tostring(base_id) .. ":" .. tostring(copy_index))
            point.x, point.y = slot.x, slot.y
            point.travel_dir = role == "in" and Grid.dir_opposite(slot.dir) or slot.dir
            point.terminal_index = copy_index
            point.terminal_count = requested
            point.terminal_network = network.key
            if copy_index == 1 then
                point.terminal_reason = "base supply network"
            else
                local reason = sizing_result.reasons[math.min(copy_index - 1, #sizing_result.reasons)]
                point.terminal_reason = reason and reason.kind or "feasibility"
                point.terminal_reason_detail = reason and reason.detail or "additional feasible supply terminal"
                point.terminal_reason_code = point.terminal_reason
                point.terminal_reason_record = copy(reason)
                point.reason = point.terminal_reason
            end
            external[#external + 1] = point
        end
    end
    state.work.terminal_sizing = sizing
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

--Every pipe tile of an engine-bound fluid box (catalog.recipe[r].fluid_boxes, round 52 binding) with its fluid: a
--merged runtime box spans several connections, and the route may lay only that fluid's pipes on them. Without a
--binding in the catalog the list is empty (offline goldens: no change).
local function fluid_keepouts(state)
    local catalog = state.work.input.catalog or {}
    local step_recipe = {}
    for _, step in ipairs(state.work.plan_result and state.work.plan_result.steps or {}) do
        local recipe = step.recipe_name or step.recipe
        if type(recipe) == "table" then recipe = recipe.name end
        step_recipe[step.step_id or step.id] = recipe
    end
    local list = {}
    for _, entity in ipairs(state.work.materialized and state.work.materialized.entities or {}) do
        if entity.kind == "machine" and entity.name then
            local recipe_name = entity.recipe or step_recipe[entity.step_id]
            if type(recipe_name) == "table" then recipe_name = recipe_name.name end
            local recipe = catalog.recipe and catalog.recipe[recipe_name or ""]
            local bound = recipe and recipe.fluid_boxes and recipe.fluid_boxes[entity.name]
            local spec = catalog_entity(catalog, entity.name)
            local boxes = spec and (spec.fluid_boxes or spec.fluidbox_prototypes)
            if type(bound) == "table" and type(boxes) == "table" then
                local fluids = {}
                for fluid in pairs(bound) do fluids[#fluids + 1] = fluid end
                table.sort(fluids)
                local cx, cy = entity.x + entity.w / 2, entity.y + entity.h / 2
                for _, fluid in ipairs(fluids) do
                    local wanted = {}
                    for _, index in ipairs(bound[fluid].boxes or {bound[fluid].box}) do wanted[index] = true end
                    for box_index, box in ipairs(boxes) do
                        if wanted[box.index or box_index] then
                            for _, connection in ipairs(box.connections or box.pipe_connections or {}) do
                                local px, py, outward = Grid.fluid_connection(connection, entity.dir or 0, entity.mirror)
                                if px then
                                    local x, y = math.floor(cx + px + 1e-6), math.floor(cy + py + 1e-6)
                                    if x >= entity.x and x < entity.x + entity.w and y >= entity.y and y < entity.y + entity.h then
                                        local dx, dy = Grid.dir_vector(outward)
                                        x, y = x + (dx or 0), y + (dy or 0)
                                    end
                                    list[#list + 1] = {x = x, y = y, flow_id = "fluid/" .. fluid}
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return list
end

local function make_route_input(state, grid, blocks, ports, obstacles)
    local external = state.work.input.perimeter_ports or state.work.input.perimeter
    local generated = false
    if type(external) ~= "table" then
        generated = true
        local settings = state.work.input.settings or {}
        local input_edge = settings.input_edge or state.work.input.input_edge or "left"
        local output_edge = settings.output_edge or state.work.input.output_edge or "top"
        local pitch = finite(state.work.input.port_pitch, 1)
        local complete
        external, complete = generated_perimeter_ports(state, grid, input_edge, output_edge, pitch,
            perimeter_blocked_cells(blocks, obstacles))
        state.work.perimeter_ports = external
        if not complete then
            local requested = 0
            for _, entry in ipairs(state.work.terminal_sizing or {}) do requested = requested + (entry.terminal_count or 1) end
            state.work.route_input_error = {
                code = "BP_R_PORT_BLOCKED", detail = "no free perimeter port slot",
                grid_size = {w = grid.w, h = grid.h}, available_ports = #external,
                requested_ports = requested,
            }
            return nil
        end
    else
        external = list_copy(external)
    end
    state.work.perimeter_ports = external
    state.work.generated_perimeter_ports = generated
    state.work.route_input_error = nil
    local input = stage_input(state, {
        grid = {w = grid.w, h = grid.h}, blocks = blocks, perimeter_ports = external,
        flows = state.work.plan_result.flows, obstacles = obstacles,
        belt_runs = (function()
            local runs = {}
            local ordered = {}
            for _, block in ipairs(blocks or {}) do ordered[#ordered + 1] = block end
            table.sort(ordered, function(a, b)
                return tostring(a.block_id or a.id or "") < tostring(b.block_id or b.id or "")
            end)
            for _, block in ipairs(ordered) do
                for _, run in ipairs(block.belt_runs or {}) do runs[#runs + 1] = run end
            end
            return runs
        end)(),
    })
    input.ports = ports
    local keepouts = fluid_keepouts(state)
    if #keepouts > 0 then input.fluid_keepouts = keepouts end
    input.tidy = false
    return input
end

--Generated fan-out invents several edge endpoints for one flow before routing knows how that flow's demand
--splits, so every endpoint carried the whole flow rate and some endpoints carried no demand at all. After
--routing the split is known: an endpoint's rate is the demand actually bound to it, and an endpoint nothing was
--bound to is not part of the layout. Endpoints the caller supplied are never rewritten or dropped: an unserved
--one of those is a real shortfall and must still be reported.
local function reconcile_generated_ports(state, external_ports, bindings)
    if not state.work.generated_perimeter_ports then return external_ports end
    local served = {}
    for _, binding in ipairs(bindings or {}) do
        local rate = finite(binding.rate_per_second, 0)
        local source = binding.source_port_id or binding.source
        local sink = binding.sink_port_id or binding.sink
        if type(source) == "string" then
            served[source] = served[source] or {}
            served[source].out = (served[source].out or 0) + rate
        end
        if type(sink) == "string" then
            served[sink] = served[sink] or {}
            served[sink]["in"] = (served[sink]["in"] or 0) + rate
        end
    end

    --Endpoints of one flow and role are one fan-out group. A group nothing was bound to is left exactly as it
    --was: the layout may not have routed yet, and an unserved endpoint of a demanded flow is a real shortfall
    --the validator must still see. Inside a group that was used, only the used endpoints remain.
    local function group_key(port)
        local id = tostring(port.port_id or port.id or "")
        local flow = port.flow_id or port.full_name or (id:gsub(":%d+$", ""))
        return tostring(flow) .. "/" .. tostring(port.role)
    end
    local function port_rate(port)
        local record = served[port.port_id or port.id]
        if record == nil then return nil end
        return port.role == "out" and record["in"] or record.out
    end

    local used = {}
    for _, port in ipairs(external_ports) do
        if port_rate(port) ~= nil then used[group_key(port)] = true end
    end
    local kept = {}
    for _, port in ipairs(external_ports) do
        local rate = port_rate(port)
        if rate ~= nil then
            port.rate_per_second = rate
            port.rate = rate
            kept[#kept + 1] = port
        elseif not used[group_key(port)] then
            kept[#kept + 1] = port
        end
    end
    return kept
end

--`ports` is the list of ports actually PLACED by materialize_candidate (search.lua:345-356).  It arrived here
--from the start and was dropped on the floor: the candidate published `ports = {}`, and because
--`route_result` is always a table (search.lua:1236 supplies `or {}`), every production candidate satisfied
--`legacy_route_only` at validate.lua:654 and took the early return at validate.lua:1217 -- skipping every
--physical transfer check, and the recipe identity checks at validate.lua:1483 and :1493 with them.  The
--comment at validate.lua:1213 asserted the opposite and was false for every candidate this function built.
--Measured consequence on the delivered artifact: 11 of 18 inserters moved nothing, 12 of 12 pipe-to-ground
--endpoints could not pair, 224 of 224 belt entities served no obligation, and the generator reported ok=true.
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
        blocks = blocks, placements = state.work.pack.result.placements, entities = {}, ports = ports,
        external_ports = external_ports,
        flows = state.work.plan_result.flows, plan = state.work.plan_result, route = route_result, power = power_result,
        settings = state.work.input.settings, infrastructure = state.work.input.settings,
        grid_spacing = copy(grid.grid_spacing or state.work.grid_spacing),
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
    candidate.external_ports = reconcile_generated_ports(state, candidate.external_ports, candidate.bindings)
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
    container.grid_spacing = state.grid_spacing
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
    if type(stage) == "table" and type(stage.progress) == "table" then
        state.progress.stage_done = finite(stage.progress.done_units, 0)
        state.progress.stage_total = math.max(1, finite(stage.progress.total_units, 1))
    end
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
    state.work.grid_spacing = copy(grid.grid_spacing)
    state.grid_spacing = copy(grid.grid_spacing)
    state.work.robo_obstacles = robo_obstacles
    state.work.roboports = roboports
    state.work.groups = Groups.begin(stage_input(state, {plan = state.work.plan_result, grid = grid, ring_bump = state.work.attempt or 0}))
    state.work.candidate = nil
    state.work.pack, state.work.route, state.work.route_state, state.work.power, state.work.validate = nil, nil, nil, nil, nil
    state.work.materialized, state.work.hand_entities, state.work.validate_candidate = nil, nil, nil
    state.work.post_tidy_power = false
    state.cursor.candidate_index = 1
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
    failure(state, "BP_FAIL_SEARCH_BUDGET", {reason_details = rejection_details(state)})
end

local function candidate_label(candidate)
    if type(candidate) ~= "table" then return nil end
    return candidate.id or candidate.candidate_id or candidate.block_id
end

local function grid_record(state)
    local grid = state.work.grid or {}
    return {index = state.cursor.grid_index, w = grid.w, h = grid.h}
end

local function record_discarded_attempt(state, score, reason)
    local work = state.work
    if work.attempt_recorded then return end
    local record = {
        kind = "candidate", candidate_id = candidate_label(work.candidate), grid = grid_record(state),
        reason = reason or "rejected",
    }
    if type(score) == "table" then record.score = copy(score) end
    local start = work.candidate_rejection_start or (#(work.rejections or {}) + 1)
    record.reason_codes = {}
    for index = start, #(work.rejections or {}) do
        local rejection = work.rejections[index]
        if rejection and rejection.code then record.reason_codes[#record.reason_codes + 1] = rejection.code end
    end
    if #record.reason_codes == 0 then record.reason_codes = nil end
    work.discarded_alternatives[#work.discarded_alternatives + 1] = record
    work.attempt_recorded = true
end

local function record_valid_attempt(state, score)
    local work = state.work
    local record = {
        kind = "candidate", candidate_id = candidate_label(work.candidate), grid = grid_record(state),
        score = copy(score), chosen = false,
    }
    work.valid_alternatives[#work.valid_alternatives + 1] = record
    return record
end

local function record_search_bound(state, reason, detail)
    local work = state.work
    if work.search_bound_recorded then return end
    work.search_bound_recorded = true
    work.bound_reason = reason
    work.discarded_alternatives[#work.discarded_alternatives + 1] = {
        kind = "search-space", reason = reason, detail = detail,
        next_grid_index = state.cursor.grid_index, permitted_grids = #work.grid_specs,
    }
end

local function search_diagnostics(state)
    local discarded = list_copy(state.work.discarded_alternatives)
    for _, record in ipairs(state.work.valid_alternatives or {}) do
        if not record.chosen then discarded[#discarded + 1] = copy(record) end
    end
    return {
        chosen_score = copy(state.incumbent and state.incumbent.score or {}),
        discarded_alternatives = discarded,
        bound = state.work.bound_reason and {kind = state.work.bound_reason}
            or {kind = "exhaustive", grids = #state.work.grid_specs},
        stop = state.work.stop_reason,
        incumbent_location = copy(state.work.incumbent_location),
        validated_no_improvement = state.work.no_improvement_attempts or 0,
    }
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

--A derived job has two budgets.  Feasibility is a deterministic bound for the complete candidate set on every
--permitted grid.  Once a validated incumbent exists, a separate improvement allowance pays for more grids and
--candidates.  Neither is measured from a candidate: in particular, a cheap pack or route rejection cannot set the
--ceiling for the rest of the job.
local function grid_area_bound(input, specs)
    local source = type(input.grid) == "table" and input.grid or {}
    local catalog = type(input.catalog) == "table" and input.catalog or {}
    local robo = catalog.robo or catalog.roboport or {}
    local tile_w = finite(source.tile_w, finite(robo.tile_w, 1))
    local tile_h = finite(source.tile_h, finite(robo.tile_h, 1))
    local result = 1
    for _, raw in ipairs(specs or {}) do
        local width, height
        if raw.w ~= nil and raw.h ~= nil then
            width, height = finite(raw.w, 1), finite(raw.h, 1)
        else
            local spacing = resolved_grid_spacing(input, raw)
            width = tile_w + math.max(0, integer(raw.cols, 2) - 1) * spacing.resolved
            height = tile_h + math.max(0, integer(raw.rows, 2) - 1) * spacing.resolved
        end
        result = math.max(result, math.ceil(math.max(1, width) * math.max(1, height)))
    end
    return result
end

local function declare_allowance(state)
    if not state.work.allowance_derived or state.max_ops ~= nil or state.work.allowance_declared then return end
    local candidates = state.work.groups and state.work.groups.result and state.work.groups.result.candidates or {}
    local input, plan = state.work.input or {}, state.work.plan_result or {}
    local area = grid_area_bound(input, state.work.grid_specs)
    local steps, flows = math.max(1, #(plan.steps or {})), math.max(1, #(plan.flows or {}))
    local demand_bound = math.max(1, steps * flows)
    local candidate_count = math.max(1, #candidates)
    --The square term covers power's candidate-position sweep and the linear term covers pack/route/validate/
    --serialize work.  It is intentionally a declared problem bound, not a sample of whichever candidate happens
    --to fail first.  Keep the arithmetic finite for malformed but finite caller inputs.
    --Stages charge honest ~8 us ops since 2026-09-24 (route 10 per expansion, 300 per improve trial, pairing 4 per
    --flooded cell; power and pack by work done), so one unit of real work costs up to ~32 of the old ops. The
    --allowance stays a runaway guard, scaled by the same factor.
    local per_candidate = 32 * math.max(256, area * area * math.max(16, demand_bound * 8 + steps * 4)
        + area * math.max(1, steps + flows) * 64)
    local grids = math.max(1, state.work.grid_trial_limit)
    local feasibility = math.max(1, per_candidate * candidate_count * grids)
    local improvement = math.max(1, per_candidate * candidate_count * math.max(1, grids - 1))
    state.work.feasibility_limit = state.ops_used + feasibility
    state.work.improvement_budget = improvement
    state.work.allowance_declared = true
    state.max_ops = state.work.feasibility_limit
end

local function stop_no_improvement(state, reason)
    if not state.incumbent then return false end
    state.work.stop_reason = "no_improvement"
    record_search_bound(state, "no_improvement", reason)
    begin_serialization(state)
    return true
end


local function finish_search_budget(state)
    if state.incumbent then
        record_search_bound(state, "search_budget", "unvisited grid and candidate alternatives were discarded at the operation bound")
        begin_serialization(state)
    else fail_budget(state) end
end

local function finish_search_bound(state, code)
    if state.incumbent then
        record_search_bound(state, code, "the search bound discarded unvisited alternatives")
        begin_serialization(state)
    else failure(state, code, {reason_details = rejection_details(state)}) end
end

--Only a running Turn trial shows the "trial" stage; a normal run keeps its own stage names.
local function trial_set_phase(state, phase)
    set_phase(state, phase)
    if state.work.trial and state.work.trial.running then state.progress.stage = "trial" end
end

--Turn trials ship OFF (round 55, player 2026-10-03): at game rate they found no win on red-1s and foundry and one
---2.8% area win on green-1s past 5x the search time, while every drawn sheet paid the time. RRC_TURN_TRIALS=1
--(offline study) or settings.turn_trials = true switches them on; in game os.getenv is absent, so they stay off.
Search.turn_trials = (os and os.getenv and os.getenv("RRC_TURN_TRIALS")) == "1"

--One Turn try: every other Block pinned at its incumbent place, the tried Block at the pose's pack dir.
local function start_try(state, pose)
    local t = state.work.trial
    t.active_pose = pose
    local candidate = copy(state.incumbent.source_candidate)
    if pose.block then
        for i, b in ipairs(candidate.blocks or {}) do
            if (b.id or b.block_id) == pose.block_id then candidate.blocks[i] = copy(pose.block); break end
        end
    end
    state.work.candidate = candidate
    local pins = {}
    for _, p in ipairs(state.incumbent.candidate.placements or {}) do
        if p.block_id ~= pose.block_id then pins[p.block_id] = {x = p.x, y = p.y, dir = p.dir} end
    end
    local input_edge = (state.work.input.settings or {}).input_edge or state.work.input.input_edge or "left"
    local obstacles = bare_rects(state.work.robo_obstacles)
    append_all(obstacles, bare_rects(state.work.input.obstacles)); append_all(obstacles, bare_rects(state.work.input.occupied))
    append_all(obstacles, perimeter_roboport_clearance(state, state.work.grid))
    state.work.pack = Pack.begin({area = pack_area(state, input_edge), obstacles = obstacles,
        zone_blockers = bare_rects(state.work.robo_obstacles), links = candidate_links(state, candidate),
        blocks = greedy_block_order(state, candidate), limits = state.work.input.limits or {}, layered = true,
        mode = "sugiyama", drawing = state.work.draw.result, pins = pins, trial = {block_id = pose.block_id, dir = pose.dir}})
    t.running = true
    trial_set_phase(state, "pack")
    return true
end

local function pose_text(pose) return tostring(pose.dir) .. "/" .. (pose.mirror and "1" or "0") end

--ADR 0002 cap, counted in search ops (the game spends Jobs.OPS_PER_TICK per tick; a step count means a different
--budget in every harness: generate.lua steps 100000 ops, the game 2000).
local function trial_cap_reached(state)
    local t = state.work.trial
    return (state.ops_used or 0) - t.ops_before >= t.ops_before
end

--Screen each pose up to the pre-tidy point; the first screen whose Material is not above the incumbent's pre-tidy
--Material runs in full at once (green-1s 2026-10-03: the first screened pose was the only win). A lost or failed
--final goes back to screening; a won final becomes the incumbent the later screens are measured against.
local function trial_next(state)
    local t = state.work.trial
    if t.current_result then
        local pose = t.active_pose
        local r = t.current_result
        t.rows[#t.rows + 1] = {block = pose.block_id, rule = pose.rule, pose = pose_text(pose), result = r.result,
            code = r.code, material = r.material, area = r.area}
        if r.result == "won" then t.won = t.won + 1 end
        if r.result == "fail" or r.result == "pin" then t.fails = t.fails + 1 end
        t.current_result = nil
        if t.mode == "final" then
            t.mode = "screen"
        else
            t.tried = t.tried + 1
            if r.result == "screened" then
                t.screened = t.screened + 1
                local bar = state.incumbent.pre_tidy_material
                if type(r.material) == "number" and (type(bar) ~= "number" or r.material <= bar)
                    and not trial_cap_reached(state) then
                    t.mode = "final"; t.finals = t.finals + 1
                    t.finalist = tostring(pose.block_id) .. " " .. pose_text(pose)
                    return start_try(state, pose)
                end
            end
        end
    end
    while t.index <= #t.poses and (t.poses[t.index].forbidden or t.poses[t.index].rebuild_fail) do
        local pose = t.poses[t.index]
        t.rows[#t.rows + 1] = {block = pose.block_id, rule = pose.rule, pose = pose_text(pose),
            result = pose.forbidden and "forbidden" or "fail", code = pose.rebuild_fail and "BP_FAIL_FLIP_REBUILD" or nil}
        t.tried = t.tried + 1
        if pose.rebuild_fail then t.fails = t.fails + 1 end
        t.index = t.index + 1
    end
    t.running = false
    if t.index > #t.poses or trial_cap_reached(state) then
        t.ticks = state.step_count - t.ticks_before
        t.ops = (state.ops_used or 0) - t.ops_before
        state.result = state.result or {}
        state.work.serialize_next = true
        state.phase = "validate"
        return false
    end
    local pose = t.poses[t.index]
    t.index = t.index + 1
    return start_try(state, pose)
end

local function begin_turn_trials(state)
    local settings=state.work.input.settings or {}
    if not (Search.turn_trials or settings.turn_trials == true) then return false end
    if Pack.mode~="sugiyama" or state.work.drawn_off or settings.force_turn_flip or state.work.trial_done
        or type(MaterialCost.blueprint)~="function" then return false end
    local old=MaterialCost.blueprint(state.work.input.catalog,state.incumbent.candidate.entities or {})
    if type(old)~="number" then return false end
    local flows=MaterialCost.by_flow(state.work.input.catalog,state.incumbent.candidate.entities or {}) or {}
    local placements={}
    for _,p in ipairs(state.incumbent.candidate.placements or {}) do placements[p.block_id]=p end
    local ordered={}
    for _,b in ipairs(state.incumbent.source_candidate.blocks or {}) do
        local id=b.id or b.block_id; local score=0
        for _,p in ipairs(b.ports or {}) do score=score+(flows[p.flow_id] or 0) end
        ordered[#ordered+1]={b=b,id=id,score=score}
    end
    table.sort(ordered,function(a,b) if a.score~=b.score then return a.score>b.score end return tostring(a.id)<tostring(b.id) end)
    local poses={}
    for _,item in ipairs(ordered) do
        local p=placements[item.id]; local d=p and p.dir or 0
        local machine=(item.b.machines or {})[1] or {}
        local orient_dir=machine.dir or item.b.orient_dir or item.b.turn or item.b.dir or d
        local mirror=machine.mirror==true or item.b.mirror==true
        --Rule and pose both name pack dir / mirror, so a row shows whether the try moved off the rule's pick.
        local rule=tostring(d).."/"..(mirror and "1" or "0")
        for _,dir in ipairs({0,4,8,12}) do if dir~=d then poses[#poses+1]={block_id=item.id,dir=dir,mirror=mirror,rule=rule} end end
        local fluid=false; for _,port in ipairs(item.b.ports or {}) do if port.kind=="fluid" or port.is_fluid then fluid=true end end
        local can=fluid
        for _,m in ipairs(item.b.machines or item.b.members or {}) do
            local spec=state.work.input.catalog and state.work.input.catalog.entity and state.work.input.catalog.entity[m.name or m.entity]
            if not (m.can_flip or spec and spec.can_flip) then can=false end
        end
        if can then
            local rebuilt=Groups.reorient(state.work.groups,item.b,{dir=orient_dir,mirror=not mirror})
            if rebuilt then for _,dir in ipairs({0,4,8,12}) do poses[#poses+1]={block_id=item.id,dir=dir,mirror=not mirror,rule=rule,block=rebuilt} end
            else for _,dir in ipairs({0,4,8,12}) do poses[#poses+1]={block_id=item.id,dir=dir,mirror=not mirror,rule=rule,
                forbidden=Groups.fluid_port_walled(item.b),rebuild_fail=not Groups.fluid_port_walled(item.b)} end end
        end
    end
    state.work.trial_done=true
    state.work.trial={ticks_before=state.step_count,ops_before=state.ops_used or 0,ticks=0,tried=0,won=0,fails=0,screened=0,finals=0,rows={},poses=poses,index=1,
        material=old,running=false,mode="screen"}
    state.work.trial_route_options={collectors=state.work.current_collectors,
        lane_cap=state.work.lane_cap==true,strict_ends=state.work.strict_ends==true}
    return trial_next(state)
end

--The electrical demand projection is public so a test can measure it without rebuilding a whole search.
Search.power_consumers = power_consumers

function Search.begin(input)
    input = copy(type(input) == "table" and input or {}) or {}
    local limits, max_ops = search_limits(input)
    local state = {
        done = false, ok = nil, phase = "plan", cursor = {phase = "plan", grid_index = 1, candidate_index = 1},
        incumbent = nil, result = nil, errors = nil, ops_used = 0, max_ops = max_ops, grid_spacing = nil,
        revisions = copy(input.revisions) or {sheet = 0, config = 0}, current_revisions = copy(input.current_revisions),
        progress = {phase = "planning", stage = "prepare", stage_done = 0, stage_total = 1, attempt = 1, attempts = 1, shown = 0, done_units = 0, total_units = nil},
        work = {input = input, limits = limits, grid_specs = ordered_grid_specs(input), plan_state = nil,
            plan_result = nil, preflight = nil, grid = nil, groups = nil, candidate = nil,
            pack = nil, route = nil, power = nil, validate = nil, serializing_candidate = nil, serialize = nil,
            grid_trials = 0, grid_trial_limit = 0, grid_limit_hit = false, generated_perimeter_ports = false,
            publication_reserved = false, power_bound_hit = false, grid_spacing = nil, route_input_error = nil,
            rejections = {}, discarded_alternatives = {}, valid_alternatives = {}, attempt_recorded = false,
            candidate_rejection_start = 1, incumbent_record = nil, search_bound_recorded = false, bound_reason = nil,
            allowance_derived = max_ops == nil, allowance_declared = false, feasibility_limit = nil,
            improvement_budget = nil, improvement_started = false, improvement_start_ops = nil,
            attempt = 0},
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
    state.progress.attempts = 3
    return state
end

--Layered pack (Pack.layered) goes first. On its first rejected candidate, or when no grid fits, the search
--starts over with MaxRects from grid 1 and attempt 0, so the sheet ends no worse than MaxRects alone.
local function pack_layered(state)
    return Pack.layered and not state.work.layered_off
end

local function layered_fallback(state)
    if (state.work.input.settings or {}).force_turn_flip ~= nil then return false end
    if not pack_layered(state) or state.incumbent then return false end
    --Drawn pack (RRC_PACK=sugiyama) falls back to today's layered pack first, never straight to MaxRects: magenta
    --drawn ended BP_FAIL_NO_LAYOUT through the MaxRects fallback while layered delivers it (round 51, 2026-09-30).
    if Pack.mode == "sugiyama" and not state.work.drawn_off then
        state.work.drawn_off = true
        state.work.fell_back = true
    else
        state.work.layered_off = true
    end
    state.work.attempt, state.work.grid_trials = 0, 0
    state.work.grid_limit_hit, state.work.power_bound_hit = false, nil
    --Round 53 integration: edge terminal splits learnt from another pack mode's route are not this mode's; red-1s-bulk
    --layered Fallback inherited the drawn attempts' splits and failed BP_V_SOURCE_DUPLICATE x4 (layered alone passes).
    state.work.edge_split_flows = nil
    state.work.fluid_edge_spread = nil
    state.work.edge_inset = nil
    state.cursor.grid_index = 1
    return start_grid(state)
end

local function finish_grid_or_search(state)
    if state.work.power_bound_hit then finish_search_bound(state, "BP_FAIL_POWER_BOUND"); return end
    if next_grid(state) then return end
    if state.work.grid_limit_hit then finish_search_bound(state, "BP_FAIL_GRID_LIMIT"); return end
    if state.incumbent then begin_serialization(state)
    elseif not layered_fallback(state) then failure(state, "BP_FAIL_NO_LAYOUT", {reason_details = rejection_details(state)}) end
end

--A grid too small to hold the blocks and the rows their ports need can never produce a layout, and packing it
--anyway costs a full pack plus a full route before it says so. The area check is exact about what it counts and
--cheap: the five-step fixture spends its whole budget on such grids without it.

candidate_links = function(state, candidate)
    local links, port_by_step_flow = {}, {}
    local blocks_for_step = {}
    for _, block in ipairs(candidate.blocks or {}) do
        for _, port in ipairs(block.ports or {}) do
            local key = tostring(port.step_id) .. "|" .. tostring(port.flow_id or port.full_name) .. "|" .. tostring(port.role)
            --One step can fill several blocks (casting-iron#1, #2); retain every block for link construction.
            local list = port_by_step_flow[key] or {}
            port_by_step_flow[key] = list
            list[#list + 1] = {block_id = block.id or block.block_id, port_id = port.port_id}
            blocks_for_step[tostring(port.step_id)] = block.id or block.block_id
        end
    end
    local settings = state.work.input.settings or {}
    local input_edge = settings.input_edge or state.work.input.input_edge or "left"
    local output_edge = settings.output_edge or state.work.input.output_edge or "top"
    for _, flow in ipairs(state.work.plan_result.flows or {}) do
        local fid = flow.flow_id or flow.full_name or flow.id
        local producers, consumers = {}, {}
        for _, p in ipairs(flow.producers or {}) do
            for _, v in ipairs(port_by_step_flow[tostring(p.step_id) .. "|" .. tostring(fid) .. "|out"] or {}) do
                producers[#producers + 1] = v
            end
        end
        for _, p in ipairs(flow.consumers or {}) do
            for _, v in ipairs(port_by_step_flow[tostring(p.step_id) .. "|" .. tostring(fid) .. "|in"] or {}) do
                consumers[#consumers + 1] = v
            end
        end
        for _, a in ipairs(producers) do for _, b in ipairs(consumers) do
            if a.block_id ~= b.block_id then links[#links + 1] = {a=a,b=b} end
        end end
        local ext_in, ext_out = false, false
        for _, p in ipairs(flow.producers or {}) do if p.step_id == "$external" then ext_in = true end end
        for _, p in ipairs(flow.consumers or {}) do if p.step_id == "$external" then ext_out = true end end
        if ext_in then for _, b in ipairs(consumers) do links[#links + 1] = {a=b, b={edge=input_edge}, flow_id=fid, ext="in"} end end
        if ext_out then for _, a in ipairs(producers) do links[#links + 1] = {a=a, b={edge=output_edge}, flow_id=fid, ext="out"} end end
    end
    return links
end

local function prepare_candidate(state, budget)
    local candidate = state.work.groups and state.work.groups.result and state.work.groups.result.candidates
        and state.work.groups.result.candidates[1]
    if not candidate then finish_grid_or_search(state); return false end
    state.work.candidate = candidate
    local forced = (state.work.input.settings or {}).force_turn_flip
    if forced then
        local prep = state.work.forced_prep
        if not prep or prep.candidate ~= candidate then
            prep = {candidate=candidate,index=1}
            state.work.forced_prep = prep
        end
        while prep.index <= #(candidate.blocks or {}) and finite(budget and budget.ops, 0) > 0 do
            local block = candidate.blocks[prep.index]
            prep.index = prep.index + 1
            block.allowed_dirs = {forced.turn}
            local cost = 1
            if forced.flip == true then
                local can_flip = false
                for _, machine in ipairs(block.machines or block.members or {}) do
                    local entity = catalog_entity(state.work.input.catalog, machine.name or machine.entity)
                    if entity.use_mirroring == false then
                        failure(state, "BP_FAIL_FLIP_FORBIDDEN", {subject = machine.name or machine.entity})
                        return false
                    end
                    if entity.can_flip then can_flip = true end
                end
                if can_flip then
                    local cache = state.work.groups and state.work.groups.work and state.work.groups.work.reorient_cache
                    local key = tostring(block.id or block.block_id) .. "|0|true|ring"
                    local hit = cache and cache[key] ~= nil
                    local rebuilt, why = Groups.reorient(state.work.groups, block, {dir=0, mirror=true, fluid_ring=true})
                    cost = hit and 1 or REORIENT_OPS
                    if not rebuilt then
                        --Player rule 2026-10-01: a machine wall makes the Flip invalid; any other refusal is a bug.
                        failure(state, why == "machine" and "BP_FAIL_FLUID_PORT_BLOCKED" or "BP_FAIL_FLIP_REBUILD",
                            {subject = block.id or block.block_id})
                        return false
                    end
                    --The flipped rebuild carries its own directions; the forced Turn holds for it too (foundry Flip
                    --rows shipped one north-facing blueprint for all four turns).
                    rebuilt.allowed_dirs = {forced.turn}
                    for i, old in ipairs(candidate.blocks) do
                        if old == block then candidate.blocks[i] = rebuilt; break end
                    end
                end
            end
            budget.ops = finite(budget.ops, 0) - cost
            state.ops_used = state.ops_used + cost
        end
        if prep.index <= #(candidate.blocks or {}) then return false end
        state.work.forced_prep = nil
        candidate = state.work.candidate
    end
    state.work.pack_links = candidate_links(state, candidate)
    state.work.candidate_rejection_start = #(state.work.rejections or {}) + 1
    state.work.attempt_recorded = false
    local block_order = greedy_block_order(state, candidate)
    local obstacles = bare_rects(state.work.robo_obstacles)
    append_all(obstacles, bare_rects(state.work.input.obstacles))
    append_all(obstacles, bare_rects(state.work.input.occupied))
    append_all(obstacles, perimeter_roboport_clearance(state, state.work.grid))
    local settings = state.work.input.settings or {}
    local input_edge = settings.input_edge or state.work.input.input_edge or "left"
    if Pack.mode == "sugiyama" and pack_layered(state) and not state.work.drawn_off then
        local nodes = {}
        for _, block in ipairs(candidate.blocks or {}) do
            local ports = {}
            for _, p in ipairs(block.ports or {}) do ports[#ports+1] = {port_id=p.port_id, role=p.role,
                attach_dx=p.attach_dx, attach_dy=p.attach_dy, kind=p.kind} end
            nodes[#nodes+1] = {id=block.id or block.block_id, w=block.w, h=block.h, ports=ports}
        end
        state.work.draw = FlowDraw.begin{nodes=nodes, links=state.work.pack_links, input_edge=input_edge,
            output_edge=settings.output_edge or state.work.input.output_edge or "top", restarts=30, sweeps=8, seed=1}
        set_phase(state, "draw")
        return true
    end
    state.work.pack = Pack.begin({area = pack_area(state, input_edge), obstacles = obstacles,
        zone_blockers = bare_rects(state.work.robo_obstacles), links = state.work.pack_links,
        blocks = block_order, limits = state.work.input.limits or {}, layered = pack_layered(state), input_edge=input_edge,
        forced_dir = forced and forced.turn or nil})
    set_phase(state, "pack")
    return true
end

--Route writes off a demand it has no room for as a shortfall. When that demand starts at a map-edge terminal,
--one terminal was shared by several sinks and the geometry left no way to branch to one of them (red science
--10/s, 2026-09-25: a foundry hand's port tile walled in by a row belt and its own hand). Mark the flow so the
--next attempt sizes one terminal per sink.
local function note_edge_shortfalls(state)
    local route = state.work.route
    local shortfalls = route and route.result and route.result.shortfalls
    if type(shortfalls) ~= "table" or #shortfalls == 0 then return end
    local edge = {}
    for _, port in ipairs(state.work.perimeter_ports or {}) do
        if port.port_id then edge[port.port_id] = true end
    end
    local edge_short = false
    for _, shortfall in ipairs(shortfalls) do
        if shortfall.flow_id and shortfall.source_port_id and edge[shortfall.source_port_id] then
            edge_short = true
            if tostring(shortfall.flow_id):sub(1, 6) == "fluid/" then state.work.fluid_edge_spread = true end
        end
    end
    if not edge_short then return end
    --The starved flow is often not the one to split: a flow with several sinks that shares one terminal runs its
    --trunk across the edge rows and walls a neighbour in (red science 10/s: a two-sink flow crossed the row of a
    --one-sink flow). Every edge flow that feeds more than one sink gets one terminal per sink on the next try.
    state.work.edge_split_flows = state.work.edge_split_flows or {}
    local sinks = {}
    for _, shortfall in ipairs(shortfalls) do
        if shortfall.flow_id then sinks[shortfall.flow_id] = math.max(sinks[shortfall.flow_id] or 0, 2) end
    end
    for _, binding in ipairs(route.result.bindings or {}) do
        if binding.flow_id and binding.source_port_id and edge[binding.source_port_id] then
            sinks[binding.flow_id] = (sinks[binding.flow_id] or 0) + 1
        end
    end
    for flow_id, count in pairs(sinks) do
        if count > 1 then state.work.edge_split_flows[flow_id] = true end
    end
end

--Collector keep-if-cheaper (round 37): the player's shape puts every same-flow output hand of one machine on one
--belt, but on some sheets that heading costs more once hands, power and tidy are done (inserter 10/s: 401 against
--373 entities). A validated candidate that used collectors is routed once more without them from the same packing;
--Validate.compare picks the finished winner. A retry that fails anywhere hands back the first.
local function restore_collector_first(state)
    local saved = state.work.collector_first
    state.work.collector_first, state.work.collector_trial = nil, "done"
    state.incumbent, state.work.incumbent_record = saved.incumbent, saved.record
    saved.record.chosen = true
    state.work.attempt_recorded = true
    begin_serialization(state)
end

--Split retry (round 48, player's gray + magenta re-export): every grid and attempt found no fit because one
--step sat in a single row too wide for any grid (24 electric furnaces, a 75x14 block). Before BP_FAIL_NO_LAYOUT,
--cut the widest no-fit multi-machine step into twice as many chunks and search again from the first grid. It only
--runs where the search would fail anyway, so every sheet that lays out today keeps its bytes.
local MAX_SPLITS = 4
local function split_retry(state)
    local steps = {}
    for _, step in ipairs((state.work.plan_result or {}).steps or {}) do steps[step.step_id] = step end
    local best, best_n
    for _, r in ipairs(state.work.rejections or {}) do
        if r.code == "BP_P_NO_FIT" and type(r.block_id) == "string" then
            local step_id = r.block_id:gsub("^block:", ""):gsub("[#@]%d+$", "")
            local step = steps[step_id]
            local n = step and step.machine_count or 0
            local now = (state.work.split_steps or {})[step_id] or 1
            if n >= 4 and now * 2 <= n and (best_n == nil or n > best_n) then best, best_n = step_id, n end
        end
    end
    if not best or (state.work.split_count or 0) >= MAX_SPLITS then return false end
    state.work.split_steps = state.work.split_steps or {}
    state.work.split_steps[best] = ((state.work.split_steps[best]) or 1) * 2
    state.work.split_count = (state.work.split_count or 0) + 1
    state.work.input.split_steps = state.work.split_steps
    state.work.attempt = 0
    state.cursor.grid_index = 1
    start_grid(state)
    return true
end

local function discard_candidate(state)
    state.work.strict_ends = nil
    state.work.lane_cap = nil
    if state.work.collector_trial == "running" then restore_collector_first(state); return end
    note_edge_shortfalls(state)
    if not state.work.attempt_recorded then
        local score = state.work.validate and state.work.validate.result and state.work.validate.result.score
        record_discarded_attempt(state, score, score and "lower_score" or "rejected")
    end
    state.work.pack, state.work.route, state.work.power, state.work.validate, state.work.tidy = nil, nil, nil, nil, nil
    if layered_fallback(state) then return end
    if (state.work.attempt or 0) < 2 then
        state.work.attempt = (state.work.attempt or 0) + 1
        state.cursor.grid_index = 1
        start_grid(state)
        return
    end
    --Edge inset retry: every attempt failed, so before BP_FAIL_NO_LAYOUT keep 3 more tiles free along the input
    --edge (cap 9) and search again at the same attempt. The edge split is dropped: the inset replaces it, and a
    --split item has two edge sources (BP_V_SOURCE_DUPLICATE). Only sheets that fail today reach this.
    if (state.work.edge_inset or 0) < 9 then
        state.work.edge_inset = (state.work.edge_inset or 0) + 3
        state.work.edge_split_flows = nil
        state.cursor.grid_index = 1
        start_grid(state)
        return
    end
    if split_retry(state) then return end
    failure(state, "BP_FAIL_NO_LAYOUT", {reason_details = rejection_details(state)})
    return

end

function Search.step(container, budget)
    local state = state_of(container)
    if type(state) ~= "table" then return container end
    state.step_count = (state.step_count or 0) + 1
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
        --ADR 0002: Turn trials may spend at most the ticks the search took before them. A try still running at the
        --cap is cut (red-1s drawn: one try ran 466 ticks against a cap of 186); the incumbent is delivered.
        local cap_trial = state.work.trial
        if cap_trial and cap_trial.running and not state.work.trial_finish
            and trial_cap_reached(state) then
            state.work.trial_finish = {result = "cut"}
        end
        if state.work.trial_finish then
            state.work.trial.current_result=state.work.trial_finish; state.work.trial_finish=nil
            if trial_next(state) then else state.work.serialize_next=true end
        end
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
            if not stage_done(state.work.groups) then
                --Grouping is a potentially dense search tree. Advance one resumable transition per game tick;
                --leaving the unused nominal ops for the next tick keeps the engine frame bounded.
                break
            else
                declare_allowance(state)
                if state.work.groups.ok == false and not (state.work.groups.result and state.work.groups.result.candidates) then
                    record_rejection(state, state.work.groups.errors or state.work.groups.result.failures, "groups")
                    discard_candidate(state)
                else
                    state.cursor.candidate_index = 1
                    prepare_candidate(state, budget)
                end
            end
        elseif state.phase == "draw" then
            if not stage_done(state.work.draw) then run_stage(state, "draw", FlowDraw, budget) end
            if stage_done(state.work.draw) then
                local drawing = state.work.draw.result or {}
                --Round 51 integration: one Block rebuild costs up to 580 ms (magenta); rebuilding every Block in one tick
                --made a 1390 ms tick. Reorient one Block per step, charged REORIENT_OPS on a cache miss, and resume.
                local orient_state = state.work.orient_state
                if not orient_state then
                    orient_state = {candidate = copy(state.work.candidate), index = 1}
                    state.work.orient_state = orient_state
                    --Start rebuilds on a fresh step: the step that ended grouping/drawing already spent up to 583 ms.
                    state.ops_used = state.ops_used + math.max(0, finite(budget.ops, 0))
                    budget.ops = 0
                end
                local candidate = orient_state.candidate
                local forced = (state.work.input.settings or {}).force_turn_flip
                if forced then orient_state.index = #(candidate.blocks or {}) + 1 end
                local input_edge = (state.work.input.settings or {}).input_edge or state.work.input.input_edge or "left"
                local flow_dir = ({left=4,right=12,top=8,bottom=0})[input_edge] or 4
                local towards = (flow_dir + 8) % 16
                local across = (input_edge == "left" or input_edge == "right") and 8 or 4
                while orient_state.index <= #(candidate.blocks or {}) and finite(budget.ops, 0) > 0 do
                    local block = candidate.blocks[orient_state.index]
                    orient_state.index = orient_state.index + 1
                    local id = block.id or block.block_id
                    local partners = {}
                    for _, p in ipairs(block.ports or {}) do if p.kind == "fluid" then
                        for _, link in ipairs(state.work.pack_links) do
                            local own = link.a.block_id == id and link.a or (link.b.block_id == id and link.b)
                            if own and own.port_id == p.port_id then
                                local other = own == link.a and link.b or link.a
                                local dir = towards
                                if other.edge then dir = ({left=12,right=4,top=0,bottom=8})[other.edge] or towards
                                elseif other.block_id then
                                    local ml, ol = drawing.layer_of[id] or 1, drawing.layer_of[other.block_id] or 1
                                    if ml == ol then dir = drawing.rank_of[id] < drawing.rank_of[other.block_id] and across or ((across + 8) % 16)
                                    else dir = (ml > ol) and towards or flow_dir end
                                end
                                partners[p.port_id] = dir
                            end
                        end
                    end end
                    local o = Orient.choose{block=block, catalog=state.work.input.catalog,
                        turn=drawing.turn_of and drawing.turn_of[id], partner_dir=partners}
                    local cache = state.work.groups and state.work.groups.work and state.work.groups.work.reorient_cache
                    local key = tostring(block.id) .. "|" .. tostring(o.dir or 0) .. "|" .. tostring(o.mirror == true)
                    local hit = ((o.dir or 0) == 0 and not o.mirror) or (cache ~= nil and cache[key] ~= nil)
                    local nb = Groups.reorient(state.work.groups, block, o)
                    if nb then candidate.blocks[orient_state.index - 1] = nb end
                    local cost = hit and 1 or REORIENT_OPS
                    budget.ops = finite(budget.ops, 0) - cost
                    state.ops_used = state.ops_used + cost
                end
                if orient_state.index > #(candidate.blocks or {}) then
                    state.work.orient_state = nil
                    state.work.candidate = candidate
                    state.work.pack_links = candidate_links(state, candidate)
                    local obstacles = bare_rects(state.work.robo_obstacles)
                    append_all(obstacles, bare_rects(state.work.input.obstacles)); append_all(obstacles, bare_rects(state.work.input.occupied))
                    append_all(obstacles, perimeter_roboport_clearance(state, state.work.grid))
                    state.work.pack = Pack.begin({area=pack_area(state,input_edge), obstacles=obstacles,
                        zone_blockers=bare_rects(state.work.robo_obstacles), links=state.work.pack_links,
                        blocks=greedy_block_order(state,candidate), limits=state.work.input.limits or {}, layered=true,
                        mode="sugiyama", drawing=drawing, input_edge=input_edge,
                        forced_dir=forced and forced.turn or nil})
                    set_phase(state,"pack")
                end
            end
        elseif state.phase == "pack" then
            run_stage(state, "pack", Pack, budget)
            if stage_done(state.work.pack) then
                    if not state.work.pack.ok then
                        if state.work.trial and state.work.trial.running then
                            local err=state.work.pack.errors and state.work.pack.errors[1]
                            state.work.trial_finish={result=err and err.code=="BP_P_TRIAL_PIN" and "pin" or "fail",code=err and err.code}
                        else
                        record_rejection(state, state.work.pack.errors, "pack")
                    local no_fit = false
                    for _, e in ipairs(state.work.pack.errors or {}) do if e.code == "BP_P_NO_FIT" then no_fit = true end end
                    if no_fit and next_grid(state) then -- a no-fit pack rejection grows this attempt's grid
                    else discard_candidate(state) end
                    end
                else
                    local blocks, entities, ports = materialize_candidate(state, state.work.candidate,
                        state.work.pack.result and state.work.pack.result.placements)
                    state.work.materialized = {blocks = blocks, entities = entities, ports = ports}
                    Hands.offer_slides(state.work.materialized, state.work.grid)
                    local settings = state.work.input.settings or {}
                    --Integrator round 54: Seat moves every edge-fed hand to the face nearest the input edge. On a Block
                    --turned sideways that face already carries both fluids, and the extra item boxed the other one in
                    --(cryo x4 Turn 4). The last-resort inset phase keeps the Block's own hand sides.
                    if (state.work.edge_inset or 0) == 0 and Seat.run(state.work.materialized, state.work.grid, state.work.plan_result.flows,
                        settings.input_edge or state.work.input.input_edge or "left") > 0 then
                        Hands.offer_slides(state.work.materialized, state.work.grid)
                    end
                    local route_input = make_route_input(state, state.work.grid, blocks, ports, state.work.robo_obstacles)
                    if route_input and state.work.trial and state.work.trial.running then
                        local options=state.work.trial_route_options or {}
                        if options.collectors ~= nil then route_input.collectors=options.collectors end
                        if options.lane_cap then route_input.lane_cap=true end
                        if options.strict_ends then route_input.strict_ends=true end
                    end
                    if route_input and state.work.strict_ends then route_input.strict_ends = true end
                    if route_input and state.work.lane_cap then route_input.lane_cap = true end
                    if route_input and (state.work.edge_inset or 0) > 0 then route_input.strict_ptg = true end
                    if route_input then
                        state.work.route_args = {blocks = blocks, ports = ports}
                        if not (state.work.trial and state.work.trial.running) then
                            state.work.current_collectors=route_input.collectors
                        end
                        state.work.collector_trial, state.work.collector_first = nil, nil
                        state.work.route = Route.begin(route_input)
                        trial_set_phase(state, "route")
                    else
                        if state.work.trial and state.work.trial.running then
                            state.work.trial_finish={result="fail",code=state.work.route_input_error and state.work.route_input_error.code or "BP_R_INPUT"}
                        else
                        record_rejection(state, {state.work.route_input_error}, "route_input")
                        discard_candidate(state)
                        end
                    end
                end
            end
        elseif state.phase == "route" then
            run_stage(state, "route", Route, budget)
            if stage_done(state.work.route) then
                    if not state.work.route.ok then
                        if state.work.trial and state.work.trial.running then
                            local err=state.work.route.errors and state.work.route.errors[1]
                            state.work.trial_finish={result="fail",code=err and err.code or "BP_V_UNSPECIFIED"}
                        else
                        record_rejection(state, state.work.route.errors, "route")
                        discard_candidate(state)
                        end
                else
                    local power_entities = list_copy(state.work.materialized.entities)
                    append_all(power_entities, state.work.route.result and state.work.route.result.entities)
                    state.work.hand_entities = power_entities
                    trial_set_phase(state, "hands")
                end
            end
        elseif state.phase == "power" then
            power_room(state, true)
            run_stage(state, "power", Power, budget)
            power_room(state, false)
            if stage_done(state.work.power) then
                if not state.work.power.ok then
                    if state.work.trial and state.work.trial.running then
                        local err=state.work.power.errors and state.work.power.errors[1]
                        state.work.trial_finish={result="fail",code=err and err.code or "BP_V_UNSPECIFIED"}
                    else
                        record_rejection(state, state.work.power.errors, "power")
                        for _, power_error in ipairs(state.work.power.errors or {}) do
                            if power_error.code == "BP_PW_SEARCH_BOUND" then state.work.power_bound_hit = true; break end
                        end
                        if state.work.power_bound_hit then finish_search_bound(state, "BP_FAIL_POWER_BOUND")
                        else discard_candidate(state) end
                    end
                else
                    if state.work.post_tidy_power then
                        state.work.post_tidy_power = false
                        state.work.validate_candidate = make_candidate(state, state.work.grid, state.work.materialized.blocks,
                            state.work.materialized.entities, state.work.materialized.ports,
                            state.work.route_state.result or state.work.route.result,
                            state.work.power.result, state.work.roboports)
                        state.work.validate = Validate.begin({candidate = state.work.validate_candidate,
                            plan = state.work.plan_result, catalog = state.work.input.catalog, ring_bump = state.work.attempt or 0})
                        trial_set_phase(state, "validate")
                    else
                    local pre_tidy_entities=list_copy(state.work.hand_entities)
                    append_all(pre_tidy_entities,state.work.power.result and state.work.power.result.entities)
                    state.work.pre_tidy_material=MaterialCost.blueprint(state.work.input.catalog,pre_tidy_entities)
                    if state.work.trial and state.work.trial.running and state.work.trial.mode=="screen" then
                        state.work.trial.current_result={result="screened",material=state.work.pre_tidy_material}
                        if not trial_next(state) then state.work.serialize_next=true end
                    else
                    local poles = {}
                    for _, e in ipairs(state.work.power.result and state.work.power.result.entities or {}) do
                        if e.kind == "pole" or e.type == "pole" then poles[#poles + 1] = {x=e.x,y=e.y,w=e.w or 1,h=e.h or 1} end
                    end
                    --On 2026-09-28, blue science tidy routed a pipe under the refinery beacon at tile (7,16) after it slid.
                    for index, e in ipairs(state.work.materialized.entities or {}) do
                        if not e._gone and (e.kind == "beacon" or e.type == "beacon") then
                            poles[#poles + 1] = {x=e.x,y=e.y,w=e.w or 1,h=e.h or 1,
                                owner="beacon:" .. tostring(e.id or index)}
                        end
                    end
                    local pole_cells = {}
                    for _, r in ipairs(poles) do
                        for x = r.x, r.x + r.w - 1 do for y = r.y, r.y + r.h - 1 do pole_cells[x .. ":" .. y] = true end end
                    end
                    local function filter_port(port)
                        local kept = {}
                        for _, option in ipairs(port.slide_options or {}) do
                            if not pole_cells[(port.hand_x + option.dx) .. ":" .. (port.hand_y + option.dy)] then kept[#kept + 1] = option end
                        end
                        port.slide_options = #kept > 0 and kept or nil
                    end
                    for _, port in ipairs(state.work.materialized.ports or {}) do filter_port(port) end
                    for _, block in ipairs(state.work.materialized.blocks or {}) do for _, port in ipairs(block.ports or {}) do filter_port(port) end end
                    state.work.route_state = Route.tidy_begin(state.work.route, {obstacles = poles})
                    trial_set_phase(state, "tidy")
                    end
                    end
                end
            end
        elseif state.phase == "hands" then
            BeaconPrune.run(state.work.materialized.entities, state.work.input.catalog,
                state.work.route.result and state.work.route.result.entities)
            local all = list_copy(state.work.materialized.entities)
            append_all(all, state.work.route.result and state.work.route.result.entities)
            state.work.hand_entities = all
            state.work.power = Power.begin(make_power_input(state, state.work.grid, all,
                state.work.roboports, state.work.robo_obstacles))
            trial_set_phase(state, "power")
        elseif state.phase == "tidy" then
            local before = budget.ops
            Route.tidy_step(state.work.route_state, budget)
            local spent = math.max(0, before - budget.ops)
            state.ops_used = state.ops_used + spent
            --Route asks for a fresh tick before a heavy publish step; the rest of this tick is left unused, not spent.
            if state.work.route_state and state.work.route_state.yield_tick then
                state.work.route_state.yield_tick = nil
                budget.ops = 0
            end
            state.progress.done_units = state.progress.done_units + spent
            local tidy_progress = state.work.route_state and state.work.route_state.progress or {}
            state.progress.stage_done = finite(tidy_progress.done_units, 0)
            state.progress.stage_total = math.max(1, finite(tidy_progress.total_units, 1))
            if stage_done(state.work.route_state) then
                local before = #(state.work.route_state.result and state.work.route_state.result.port_slides or {})
                Ends.turn_heads(state.work.route_state.result or {})
                Hands.place(state.work.materialized, state.work.route_state.result or {})
                if before > 0 then
                    state.work.post_tidy_power = true
                    local all = list_copy(state.work.materialized.entities)
                    append_all(all, state.work.route_state.result.entities)
                    state.work.power = Power.begin(make_power_input(state, state.work.grid, all,
                        state.work.roboports, state.work.robo_obstacles))
                    trial_set_phase(state, "power")
                else
                    state.work.validate_candidate = make_candidate(state, state.work.grid, state.work.materialized.blocks,
                        state.work.materialized.entities, state.work.materialized.ports,
                        state.work.route_state.result or state.work.route.result,
                        state.work.power.result, state.work.roboports)
                    state.work.validate = Validate.begin({candidate = state.work.validate_candidate,
                        plan = state.work.plan_result, catalog = state.work.input.catalog, ring_bump = state.work.attempt or 0})
                    trial_set_phase(state, "validate")
                end
            end
        elseif state.phase == "validate" and state.work.serialize_next then
            --Success work is spread over ticks: gray + magenta's success tick was 0.74 s (last validate step +
            --three deep copies 0.21 s + begin_serialization 0.24 s; legalcopilot-dev 2026-09-29, DoD 300 ms).
            state.work.serialize_next = nil
            begin_serialization(state)
            budget.ops = 0
        elseif state.phase == "validate" then
            local was_done = stage_done(state.work.validate)
            if not was_done then run_stage(state, "validate", Validate, budget) end
            if stage_done(state.work.validate) and state.work.validate.ok and not was_done then
                --The copies below get a tick of their own, apart from the last validate step.
                budget.ops = 0
            elseif stage_done(state.work.validate) then
                if not state.work.validate.ok then
                    --A candidate discarded without a record makes every validator rejection look like a routing
                    --failure from outside.  Counting the codes costs nothing and is what the failure message and
                    --the debug export need.
                    local belt_shape = false
                    for _, err in ipairs(state.work.validate.errors or {}) do
                        if STRICT_REROUTE_CODES[err.code] then belt_shape = true; break end
                    end
                    local lane_over = false
                    for _, err in ipairs(state.work.validate.errors or {}) do
                        if err.code == "BP_V_LANE_OVERLOAD" then lane_over = true; break end
                    end
                    if state.work.trial and state.work.trial.running then
                        local code = state.work.validate.errors and state.work.validate.errors[1]
                        state.work.trial_finish = {result="fail", code=code and code.code or "BP_V_UNSPECIFIED"}
                    else
                    record_rejection(state, state.work.validate.errors, "validate")
                    if lane_over and not state.work.lane_cap and state.work.collector_trial == nil then
                        --Round 54 (plastic x4 Turn 8 in Factorio 2.0.77: 7.5/s of 7.992/s): route the same grid again
                        --with lane capacity counted, so a branch joins the trunk on the lane that still has room.
                        state.work.lane_cap = true
                        start_grid(state)
                    elseif belt_shape and not state.work.strict_ends and state.work.collector_trial == nil then
                        -- Magenta science: strict redo at grid 6 on 2026-09-29 (tick 18351); accepted at tick 34785.
                        state.work.strict_ends = true
                        start_grid(state)
                    else
                        discard_candidate(state)
                    end
                    end
                else
                    local score = state.work.validate.result and state.work.validate.result.score or {}
                    if state.work.trial and state.work.trial.running then
                        local t = state.work.trial
                        local material = MaterialCost.blueprint(state.work.input.catalog,
                            state.work.validate_candidate.entities or {})
                        local old_material = t.material
                        local old_area = state.incumbent.score and state.incumbent.score.production_area or math.huge
                        local area = score.production_area or math.huge
                        local tie = math.abs(material - old_material) <= .10 * math.max(material, old_material)
                        local win = (material < old_material and old_material - material > .10 * old_material)
                            or (tie and area < old_area)
                        t.current_result = {result=win and "won" or "lost", material=material, area=area}
                        if win then
                            state.incumbent = {score=copy(score), candidate=copy(state.work.validate_candidate),
                                source_candidate=copy(state.work.candidate), validation=copy(state.work.validate.result),
                                pre_tidy_material=state.work.pre_tidy_material}
                            t.material = material
                        end
                        state.work.trial_finish = t.current_result
                    else
                    local record = record_valid_attempt(state, score)
                    local incumbent = {score = copy(score), candidate = copy(state.work.validate_candidate),
                        source_candidate = copy(state.work.candidate), validation = copy(state.work.validate.result),
                        pre_tidy_material=state.work.pre_tidy_material}
                    local routed = state.work.route and state.work.route.work
                    local first = state.work.collector_first
                    if state.work.collector_trial == "running" and first then
                        state.work.collector_trial, state.work.collector_first = "done", nil
                        if Validate.compare(score, first.incumbent.score) >= 0 then
                            state.incumbent, state.work.incumbent_record = first.incumbent, first.record
                            first.record.chosen = true
                            state.work.attempt_recorded = true
                            if not begin_turn_trials(state) then state.work.serialize_next = true end
                            budget.ops = 0
                            incumbent = nil
                        end
                    elseif not (state.work.trial and state.work.trial.running) and state.work.collector_trial == nil and routed and routed.collectors_used and state.work.route_args then
                        local retry_input = make_route_input(state, state.work.grid, state.work.route_args.blocks,
                            state.work.route_args.ports, state.work.robo_obstacles)
                        if retry_input then
                            retry_input.collectors = false
                            state.work.current_collectors=false
                            state.work.collector_first = {incumbent = incumbent, record = record}
                            state.work.collector_trial = "running"
                            state.work.power, state.work.validate, state.work.tidy, state.work.route_state = nil, nil, nil, nil
                            state.work.route = Route.begin(retry_input)
                            trial_set_phase(state, "route")
                            incumbent = nil
                        end
                    end
                    if incumbent then
                        record.chosen = true
                        state.work.incumbent_record = record
                        state.incumbent = incumbent
                        state.work.attempt_recorded = true
                        if not begin_turn_trials(state) then state.work.serialize_next = true end
                        budget.ops = 0
                    end
                    end
                end
            end
        elseif state.phase == "serialize" then
            if not revisions_match(container, state) then fail_revision(state); break end
            run_stage(state, "serialize", Serialize, budget)
            if stage_done(state.work.serialize) then
                if not revisions_match(container, state) then fail_revision(state)
                elseif state.work.serialize.ok then
                    state.result = copy(state.work.serialize.result)
                    local diagnostics = search_diagnostics(state)
                    --Keep the optimization claim beside the delivered result. The blueprint encoder ignores this
                    --plain diagnostic field, while offline callers and the job record can see exactly what was
                    --chosen and which alternatives were rejected, outscored or left beyond a declared bound.
                    state.result.search = diagnostics
                    if state.work.trial then
                        state.work.trial.ticks=state.work.trial.ticks or (state.step_count-state.work.trial.ticks_before)
                        state.result.search.trial={ticks_before=state.work.trial.ticks_before,ticks=state.work.trial.ticks,
                            ops_before=state.work.trial.ops_before,ops=state.work.trial.ops,
                            tried=state.work.trial.tried,won=state.work.trial.won,fails=state.work.trial.fails,
                            screened=state.work.trial.screened,finals=state.work.trial.finals,finalist=state.work.trial.finalist,rows=copy(state.work.trial.rows)}
                    end
                    state.result.search.fell_back = state.work.fell_back == true
                    state.result.chosen_score = copy(diagnostics.chosen_score)
                    state.result.discarded_alternatives = copy(diagnostics.discarded_alternatives)
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

Search._slot_cost = slot_cost
Search._port_first_belt = port_first_belt

return Search
