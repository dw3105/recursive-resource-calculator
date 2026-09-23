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

local CANDIDATE_ALLOWANCE = 4
-- The player replay's winning layout is found early; allow two later validated misses to
-- guard against ordering noise while bounding work by complete validated layouts.
local NO_IMPROVEMENT_LIMIT = 2
local MAX_LAYOUTS = 3

local function grid_trial_limit(input, limits, grid_count)
    local maximum = input.max_search_grids or input.max_grid_trials
        or limits.max_search_grids or limits.max_grid_trials
    --The default breadth is the same declared allowance used for improvement work.  A caller may deliberately
    --raise it, but an implicit 12-grid cap over a 49-grid ladder must not contradict the job's other bound.
    maximum = integer(maximum, CANDIDATE_ALLOWANCE)
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

--`port_flow_id` is defined below, next to the other port helpers, but candidate_orders reads it. A Lua local
--is invisible above its own declaration, so the call at interface_weight resolved to a nil GLOBAL and the real
--player case died with "attempt to call global 'port_flow_id' (a nil value)" inside search.lua:320. The lane's
--focused tests never drove prepare_candidate down that path, so nothing caught it before the merge.
local port_flow_id

local function candidate_orders(state, candidate)
    local input = state.work.input
    local supplied = candidate.block_orderings or candidate.orders or input.block_orderings or input.block_orders
    if type(supplied) == "table" and #supplied > 0 and type(supplied[1]) ~= "table" then supplied = {supplied} end
    if type(supplied) ~= "table" or #supplied == 0 then
        local natural = list_copy(candidate.blocks)
        local result = {{blocks = natural}}
        --Packing is intentionally blind to recipe semantics. Give it a deterministic connectivity ordering so
        --blocks joined by real flow interfaces are consumed by neighbouring free regions before unrelated blocks.
        --Pack still chooses the legal collision-free port slots and rotations, so this is a preference, not a
        --geometry shortcut or a bypass around beacon constraints.
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
        if #natural > 1 then
            local reverse = {}
            for index = #natural, 1, -1 do reverse[#reverse + 1] = copy(natural[index]) end
            local duplicate = true
            for index, block in ipairs(reverse) do
                if (block.id or block.block_id) ~= (result[#result].blocks[index].id or result[#result].blocks[index].block_id) then
                    duplicate = false; break
                end
            end
            if not duplicate then result[#result + 1] = {blocks = reverse} end
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

--`materialized.ports` and each `blocks[i].ports` hold separate copies of one port (append_all copies), and
--Route reads the block copies.  A slide must reach every copy.
local function every_port_copy(materialized)
    local result = {}
    for _, port in ipairs(materialized.ports or {}) do result[#result + 1] = port end
    for _, block in ipairs(materialized.blocks or {}) do
        for _, port in ipairs(block.ports or {}) do result[#result + 1] = port end
    end
    return result
end

--The player placed v4 on 2026-09-23 and boxed two belts that bent only to reach a hand grouping had fixed
--before any belt existed.  Each hand that serves one port may move one tile along its machine face; route.lua
--improve_routes tries the move and keeps it only when the layout gets smaller.  Only unrotated placements
--carry world port tiles (Groups.materialize), so only those are offered.
local function offer_hand_slides(materialized, grid)
    local by_id, taken, served = {}, {}, {}
    for _, entity in ipairs(materialized.entities or {}) do
        by_id[tostring(entity.id)] = entity
        if entity.x ~= nil and entity.y ~= nil then
            for x = entity.x, entity.x + finite(entity.w, 1) - 1 do
                for y = entity.y, entity.y + finite(entity.h, 1) - 1 do taken[x .. ":" .. y] = true end
            end
        end
    end
    local function hand_of(port)
        if port.inserter_id == nil then return nil end
        return by_id["m:" .. tostring(port.inserter_id)] or by_id[tostring(port.inserter_id)]
    end
    for _, port in ipairs(materialized.ports or {}) do
        local hand = hand_of(port)
        if hand then served[hand] = (served[hand] or 0) + 1 end
    end
    for _, port in ipairs(materialized.ports or {}) do
        local hand = hand_of(port)
        local machine = hand and by_id[tostring(hand.machine_id)]
        if hand and machine and served[hand] == 1 and port.x ~= nil and port.y ~= nil and port.attach_dx ~= nil
            and hand.x ~= nil and machine.x ~= nil and finite(hand.w, 1) == 1 and finite(hand.h, 1) == 1 then
            local nx, ny = port.x - hand.x, port.y - hand.y
            if math.abs(nx) + math.abs(ny) == 1 then
                local options = {}
                for _, step in ipairs(nx ~= 0 and {{0, -1}, {0, 1}} or {{-1, 0}, {1, 0}}) do
                    local hx, hy = hand.x + step[1], hand.y + step[2]
                    local reach_x, reach_y = hx - nx, hy - ny
                    local on_face = reach_x >= machine.x and reach_x < machine.x + finite(machine.w, 1)
                        and reach_y >= machine.y and reach_y < machine.y + finite(machine.h, 1)
                    if on_face and not taken[hx .. ":" .. hy] and hx >= 0 and hy >= 0 and hx < grid.w and hy < grid.h then
                        options[#options + 1] = {dx = step[1], dy = step[2]}
                    end
                end
                if #options > 0 then
                    for _, twin in ipairs(every_port_copy(materialized)) do
                        if twin.port_id == port.port_id then twin.slide_options, twin.hand_x, twin.hand_y = options, hand.x, hand.y end
                    end
                end
            end
        end
    end
end

--Move each hand the route kept a slide for, with its port tile and pickup/drop points.
local function apply_hand_slides(materialized, route_result)
    local by_port = {}
    for _, slide in ipairs(route_result and route_result.port_slides or {}) do by_port[tostring(slide.port_id)] = slide end
    if next(by_port) == nil then return end
    local by_id = {}
    for _, entity in ipairs(materialized.entities or {}) do by_id[tostring(entity.id)] = entity end
    local ports = every_port_copy(materialized)
    for _, port in ipairs(ports) do
        local slide = by_port[tostring(port.port_id or port.id)]
        if slide then
            port.x, port.y = port.x + slide.dx, port.y + slide.dy
            port.attach_dx, port.attach_dy = port.attach_dx + slide.dx, port.attach_dy + slide.dy
            port.slide_options = nil
        end
    end
    for _, port in ipairs(materialized.ports or {}) do
        local slide = by_port[tostring(port.port_id or port.id)]
        local hand = slide and port.inserter_id ~= nil
            and (by_id["m:" .. tostring(port.inserter_id)] or by_id[tostring(port.inserter_id)])
        if hand then
            local dx, dy = slide.dx, slide.dy
            local old_x, old_y = hand.x, hand.y
            hand.x, hand.y = hand.x + dx, hand.y + dy
            for _, field in ipairs({"position", "pickup_position", "drop_position"}) do
                local point = hand[field]
                if type(point) == "table" and point.x ~= nil then hand[field] = {x = point.x + dx, y = point.y + dy} end
            end
            for _, other in ipairs(ports) do
                for _, rect in ipairs(other._occupied or {}) do
                    if rect.x == old_x and rect.y == old_y and finite(rect.w, 1) == 1 and finite(rect.h, 1) == 1 then
                        rect.x, rect.y = rect.x + dx, rect.y + dy
                    end
                end
            end
        end
    end
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
                if port.role == "in" then
                    blocked[perimeter_cell_key(x - dx, y - dy)] = true
                elseif port.role == "out" then
                    blocked[perimeter_cell_key(x + dx, y + dy)] = true
                end
            end
        end
    end
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
    if capacity ~= nil then return capacity, "catalog" end
    return nil, "unbounded"
end

local function terminal_branch_limit(state, network)
    local input = state and state.work and state.work.input or {}
    local port, flow = network.port or {}, network.flow or {}
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
                result[#result + 1] = {x = port.x, y = port.y}
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
    local result = {}
    local function add_rect(raw)
        local rect = type(raw) == "table" and (raw.rect or raw)
        if type(rect) ~= "table" then return end
        for y = rect.y, rect.y + rect.h - 1 do
            for x = rect.x, rect.x + rect.w - 1 do result[perimeter_cell_key(x, y)] = true end
        end
    end
    for _, block in ipairs(blocks or {}) do
        add_rect(block)
        mark_perimeter_port_cells(result, block)
    end
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
    local sizing = {}
    local networks = terminal_networks(state)
    for _, network in ipairs(networks) do
        network.consumers = terminal_consumers(state, network)
        local best
        for _, slot in ipairs(slots[network.role]) do
            local key = perimeter_cell_key(slot.x, slot.y)
            if not occupied[key] and (not perimeter_port_needs_route(network.port) or not blocked[key]) then
                local cost = slot_cost(slot, network.consumers)
                if best == nil or cost < best then best = cost end
            end
        end
        network.need = best or math.huge
    end
    table.sort(networks, function(a, b)
        if a.need ~= b.need then return a.need > b.need end
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
            for candidate_index, candidate_slot in ipairs(slots[role]) do
                local key = perimeter_cell_key(candidate_slot.x, candidate_slot.y)
                if not occupied[key] and (not perimeter_port_needs_route(port) or not blocked[key]) then
                    local cost = slot_cost(candidate_slot, network.consumers)
                    if index == nil or cost < best_cost or (cost == best_cost and candidate_index < index) then
                        index, best_cost = candidate_index, cost
                    end
                end
            end
            index = index or (#slots[role] + 1)
            while index <= #slots[role] do
                local slot = slots[role][index]
                local key = perimeter_cell_key(slot.x, slot.y)
                if not occupied[key] and (not perimeter_port_needs_route(port) or not blocked[key]) then break end
                index = index + 1
            end
            next_slot[role] = math.max(next_slot[role], index + 1)
            if index > #slots[role] then
                return external, false
            end

            local slot = slots[role][index]
            occupied[perimeter_cell_key(slot.x, slot.y)] = true
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
    })
    input.ports = ports
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
        order_index = state.cursor.order_index, reason = reason or "rejected",
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
        order_index = state.cursor.order_index, score = copy(score), chosen = false,
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
    local per_candidate = math.max(256, area * area * math.max(16, demand_bound * 8 + steps * 4)
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

local function publish_interim(state)
    local serial = Serialize.begin(state.incumbent.candidate)
    while not serial.done do Serialize.step(serial, {ops = 1000000000}) end
    state.interim = {sequence = (state.interim and state.interim.sequence or 0) + 1,
        result = copy(serial.result), entities = #(serial.result.entities or {})}
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

--The electrical demand projection is public so a test can measure it without rebuilding a whole search.
Search.power_consumers = power_consumers

function Search.begin(input)
    input = copy(type(input) == "table" and input or {}) or {}
    local limits, max_ops = search_limits(input)
    local state = {
        done = false, ok = nil, phase = "plan", cursor = {phase = "plan", grid_index = 1, candidate_index = 1, order_index = 1},
        incumbent = nil, result = nil, errors = nil, ops_used = 0, max_ops = max_ops, grid_spacing = nil,
        revisions = copy(input.revisions) or {sheet = 0, config = 0}, current_revisions = copy(input.current_revisions),
        progress = {phase = "planning", done_units = 0, total_units = nil},
        work = {input = input, limits = limits, grid_specs = ordered_grid_specs(input), plan_state = nil,
            plan_result = nil, preflight = nil, grid = nil, groups = nil, candidate = nil, orderings = nil,
            pack = nil, route = nil, power = nil, validate = nil, serializing_candidate = nil, serialize = nil,
            grid_trials = 0, grid_trial_limit = 0, grid_limit_hit = false, generated_perimeter_ports = false,
            publication_reserved = false, power_bound_hit = false, grid_spacing = nil, route_input_error = nil,
            rejections = {}, discarded_alternatives = {}, valid_alternatives = {}, attempt_recorded = false,
            candidate_rejection_start = 1, incumbent_record = nil, search_bound_recorded = false, bound_reason = nil,
            allowance_derived = max_ops == nil, allowance_declared = false, feasibility_limit = nil,
            improvement_budget = nil, improvement_started = false, improvement_start_ops = nil},
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
    if state.work.power_bound_hit then finish_search_bound(state, "BP_FAIL_POWER_BOUND"); return end
    if next_grid(state) then return end
    if state.work.grid_limit_hit then finish_search_bound(state, "BP_FAIL_GRID_LIMIT"); return end
    if state.incumbent then begin_serialization(state)
    else failure(state, "BP_FAIL_NO_LAYOUT_GRID_LIMIT", {reason_details = rejection_details(state)}) end
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
    local fits = needed <= grid.w * grid.h
    --A block fits in one orientation or the other, so its shorter side must fit the shorter side of the grid.
    fits = fits and widest <= math.min(grid.w, grid.h) and tallest <= math.max(grid.w, grid.h)
    if not fits then
        record_rejection(state, {{code = "BP_P_NO_FIT", detail = "candidate does not fit this grid",
            candidate_size = {area = needed, width = widest, height = tallest},
            grid_size = {w = grid.w, h = grid.h}}}, "fit")
    end
    return fits
end

local function prepare_candidate(state)
    local candidate = state.work.groups.result.candidates[state.cursor.candidate_index]
    if not candidate then
        finish_grid_or_search(state)
        return false
    end
    state.work.candidate = candidate
    state.work.candidate_rejection_start = #(state.work.rejections or {}) + 1
    state.work.attempt_recorded = false
    if not candidate_fits_grid(state, candidate) then
        record_discarded_attempt(state, nil, "grid_fit")
        state.cursor.candidate_index = state.cursor.candidate_index + 1
        state.cursor.order_index = 1
        return prepare_candidate(state)
    end
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
    if not state.work.attempt_recorded then
        local score = state.work.validate and state.work.validate.result and state.work.validate.result.score
        record_discarded_attempt(state, score, score and "lower_score" or "rejected")
    end
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
            if not stage_done(state.work.groups) then
                --Grouping is a potentially dense search tree. Advance one resumable transition per game tick;
                --leaving the unused nominal ops for the next tick keeps the engine frame bounded.
                break
            else
                declare_allowance(state)
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
                if not state.work.pack.ok then
                    record_rejection(state, state.work.pack.errors, "pack")
                    discard_candidate(state)
                else
                    local blocks, entities, ports = materialize_candidate(state, state.work.candidate,
                        state.work.pack.result and state.work.pack.result.placements)
                    state.work.materialized = {blocks = blocks, entities = entities, ports = ports}
                    offer_hand_slides(state.work.materialized, state.work.grid)
                    local route_input = make_route_input(state, state.work.grid, blocks, ports, state.work.robo_obstacles)
                    if route_input then
                        state.work.route = Route.begin(route_input)
                        set_phase(state, "route")
                    else
                        record_rejection(state, {state.work.route_input_error}, "route_input")
                        discard_candidate(state)
                    end
                end
            end
        elseif state.phase == "route" then
            run_stage(state, "route", Route, budget)
            if stage_done(state.work.route) then
                if not state.work.route.ok then
                    record_rejection(state, state.work.route.errors, "route")
                    discard_candidate(state)
                else
                    apply_hand_slides(state.work.materialized, state.work.route.result)
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
                    record_rejection(state, state.work.power.errors, "power")
                    for _, power_error in ipairs(state.work.power.errors or {}) do
                        if power_error.code == "BP_PW_SEARCH_BOUND" then state.work.power_bound_hit = true; break end
                    end
                    if state.work.power_bound_hit then
                        finish_search_bound(state, "BP_FAIL_POWER_BOUND")
                    else
                        discard_candidate(state)
                    end
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
                if not state.work.validate.ok then
                    --A candidate discarded without a record makes every validator rejection look like a routing
                    --failure from outside.  Counting the codes costs nothing and is what the failure message and
                    --the debug export need.
                    record_rejection(state, state.work.validate.errors, "validate")
                    discard_candidate(state)
                else
                    local score = state.work.validate.result and state.work.validate.result.score or {}
                    local record = record_valid_attempt(state, score)
                    local improves = state.incumbent == nil or Validate.compare(score, state.incumbent.score) < 0
                    if improves then
                        local first_incumbent = state.incumbent == nil
                        if state.work.incumbent_record then
                            state.work.incumbent_record.chosen = false
                            state.work.incumbent_record.reason = "outscored"
                        end
                        record.chosen = true
                        state.work.incumbent_record = record
                        state.incumbent = {score = copy(score), candidate = copy(state.work.validate_candidate),
                            validation = copy(state.work.validate.result)}
                        --The layout-count stop decides when to stop; the declared improvement allowance stays as a finite
                        --safety net (tests/test_search_allowance.lua), sized from the grid area, never a fixed op count.
                        if first_incumbent and state.work.allowance_derived then
                            state.max_ops = state.ops_used + math.max(1, state.work.improvement_budget or 1)
                        elseif first_incumbent then
                            state.max_ops = nil
                        end
                        state.work.incumbent_location = {grid_index = state.cursor.grid_index,
                            candidate_index = state.cursor.candidate_index, ordering_index = state.cursor.order_index}
                        state.work.no_improvement_attempts = 0
                        publish_interim(state)
                    else
                        state.work.no_improvement_attempts = (state.work.no_improvement_attempts or 0) + 1
                    end
                    state.work.validated_layouts = (state.work.validated_layouts or 0) + 1
                    state.work.attempt_recorded = true
                    if not improves and state.work.no_improvement_attempts >= NO_IMPROVEMENT_LIMIT then
                        stop_no_improvement(state, "validated alternatives did not improve the incumbent")
                    elseif state.work.validated_layouts >= MAX_LAYOUTS then
                        state.work.stop_reason = "max_layouts"
                        record_search_bound(state, "max_layouts", "maximum validated layouts reached")
                        begin_serialization(state)
                    else
                        discard_candidate(state)
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

return Search
