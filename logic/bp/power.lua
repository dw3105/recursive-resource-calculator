--Poles that cover everything electric, and the wires that actually join them.
--
--Owned by lane W3-power.  The input and output are deliberately plain data: the
--power stage does not know what a consumer is, and it never retains a prototype
--or an engine object.
--
--  Power.begin{grid_w, grid_h, occupied = {{rect, owner}}, consumers = {{id, rect}}, pole = <catalog pole>,
--              limits = {max_poles}} -> state
--  state.result = {entities = {PlacedEntity}, wires = {{a_id, a_connector, b_id, b_connector}},
--                  pole_count, components, uncovered = {id}, connection_point = {pole_id, x, y}}
--
--A wire edge is a physical claim, so it carries its connectors: power runs on
--copper (defines.wire_connector_id.pole_copper), and a graph joined through a
--circuit connector is not an electric network.  Reach is the smaller of the
--two poles' own reach at their own quality.  Roboports are not consumers here.
local Power = {}

local EPSILON = 1e-9

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback
end

local function integer(value, fallback)
    value = finite(value, fallback)
    if value == nil then return nil end
    return math.floor(value)
end

--Only plain scalar values cross the stage boundary.  In particular, a
--prototype method or userdata must never become reachable from a resumable
--state.
local function plain_scalar(value, fallback)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    if value == nil then return fallback end
    return tostring(value)
end

local function copy_rect(rect)
    if type(rect) ~= "table" then return nil end
    local result = {
        x = finite(rect.x, nil), y = finite(rect.y, nil),
        w = finite(rect.w, nil), h = finite(rect.h, nil),
    }
    if result.x == nil or result.y == nil or result.w == nil or result.h == nil then return nil end
    return result
end

local function rect_valid(rect)
    return rect ~= nil and rect.w > 0 and rect.h > 0
end

local function rect_intersects(a, b)
    return rect_valid(a) and rect_valid(b)
        and a.x < b.x + b.w and b.x < a.x + a.w
        and a.y < b.y + b.h and b.y < a.y + a.h
end

local function sorted_keys(map)
    local keys = {}
    for key, _ in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function value_for_quality(spec, key, quality)
    local by_quality = spec[key .. "_by_quality"] or spec[key .. "s_by_quality"]
    if type(by_quality) == "table" and by_quality[quality] ~= nil then return by_quality[quality] end

    local qualities = spec.quality_poles or spec.quality_variants
    if type(qualities) == "table" and type(qualities[quality]) == "table" then
        local value = qualities[quality][key]
        if value ~= nil then return value end
    end
    local direct = spec[key]
    if type(direct) == "table" and direct[quality] ~= nil then return direct[quality] end
    return direct
end

local function quality_name(value)
    if type(value) == "table" then return plain_scalar(value.name or value.id, "normal") end
    if type(value) == "string" and value ~= "" then return value end
    return "normal"
end

local function merge_spec(base, variant, quality)
    local result = {}
    for key, value in pairs(base or {}) do result[key] = value end
    for key, value in pairs(variant or {}) do result[key] = value end
    if quality ~= nil then result.quality = quality end
    return result
end

local function looks_like_spec(value)
    if type(value) ~= "table" then return false end
    return value.name ~= nil or value.tile_w ~= nil or value.tile_h ~= nil
        or value.supply_w ~= nil or value.supply_h ~= nil or value.wire_reach ~= nil
        or value.quality ~= nil or value.x ~= nil or value.y ~= nil
end

local function append_spec(specs, raw, quality)
    if type(raw) ~= "table" then return end
    if not looks_like_spec(raw) and type(raw.pole) == "table" then
        raw = merge_spec(raw.pole, raw, quality)
    else
        raw = merge_spec(raw, nil, quality)
    end

    local selected_quality = quality_name(raw.quality)
    local supply_w = value_for_quality(raw, "supply_w", selected_quality)
    local supply_h = value_for_quality(raw, "supply_h", selected_quality)
    if supply_w == nil then supply_w = value_for_quality(raw, "supply_area_distance", selected_quality) end
    if supply_h == nil then supply_h = value_for_quality(raw, "supply_area_distance_h", selected_quality) end
    local result = {
        name = plain_scalar(raw.name or raw.prototype, "electric-pole"),
        quality = selected_quality,
        tile_w = math.max(1, integer(raw.tile_w or raw.width, 1)),
        tile_h = math.max(1, integer(raw.tile_h or raw.height, 1)),
        supply_w = finite(supply_w, nil),
        supply_h = finite(supply_h, nil),
        wire_reach = finite(value_for_quality(raw, "wire_reach", selected_quality), nil),
        max_count = integer(raw.max_count or raw.count_limit, nil),
        fixed_x = finite(raw.x, nil),
        fixed_y = finite(raw.y, nil),
    }

    if result.supply_w == nil then
        local supply = value_for_quality(raw, "supply_area", selected_quality)
        if type(supply) == "table" then
            result.supply_w = finite(supply.w or supply.x or supply[1], 0)
            result.supply_h = finite(supply.h or supply.y or supply[2], result.supply_w)
        else
            result.supply_w = finite(supply, 0)
            result.supply_h = finite(value_for_quality(raw, "supply_h", selected_quality), result.supply_w)
        end
    elseif result.supply_h == nil then
        result.supply_h = result.supply_w
    end
    if result.wire_reach == nil then result.wire_reach = finite(raw.wire_distance, 0) end
    result.supply_w = math.max(0, result.supply_w)
    result.supply_h = math.max(0, result.supply_h)
    result.wire_reach = math.max(0, result.wire_reach)
    result.max_count = result.max_count and math.max(0, result.max_count) or nil
    specs[#specs + 1] = result
end

local function normalize_specs(input)
    local specs = {}
    local pole = input.pole
    local alternatives = input.poles or input.pole_choices

    if type(alternatives) == "table" and #alternatives > 0 then
        for _, raw in ipairs(alternatives) do append_spec(specs, raw) end
    elseif type(pole) == "table" and #pole > 0 then
        for _, raw in ipairs(pole) do append_spec(specs, raw) end
    elseif type(pole) == "table" and not looks_like_spec(pole) then
        local variants = pole.quality_poles or pole.quality_variants or pole.qualities
        if type(variants) == "table" then
            local base = {}
            for key, value in pairs(pole) do
                if key ~= "quality_poles" and key ~= "quality_variants" and key ~= "qualities" then base[key] = value end
            end
            for _, quality in ipairs(sorted_keys(variants)) do
                if type(variants[quality]) == "table" then
                    append_spec(specs, merge_spec(base, variants[quality], quality))
                end
            end
        else
            for _, quality in ipairs(sorted_keys(pole)) do
                if type(pole[quality]) == "table" then append_spec(specs, pole[quality], quality) end
            end
        end
    elseif type(pole) == "table" then
        --A catalog normally gives us one already-selected quality.  Pure-data
        --callers may instead give one pole family with quality variants; make
        --each variant a real spec so every placed pole carries the reach that
        --belongs to its own quality.
        local variants = pole.quality_poles or pole.quality_variants or pole.qualities
        if type(variants) == "table" and pole.quality == nil then
            local base = {}
            for key, value in pairs(pole) do
                if key ~= "quality_poles" and key ~= "quality_variants" and key ~= "qualities" then base[key] = value end
            end
            for _, quality in ipairs(sorted_keys(variants)) do
                if type(variants[quality]) == "table" then
                    append_spec(specs, merge_spec(base, variants[quality], quality))
                end
            end
        else
            append_spec(specs, pole)
        end
    end

    table.sort(specs, function(a, b)
        if a.quality ~= b.quality then return a.quality < b.quality end
        if tostring(a.name) ~= tostring(b.name) then return tostring(a.name) < tostring(b.name) end
        if a.tile_w ~= b.tile_w then return a.tile_w < b.tile_w end
        if a.tile_h ~= b.tile_h then return a.tile_h < b.tile_h end
        if a.supply_w ~= b.supply_w then return a.supply_w > b.supply_w end
        if a.supply_h ~= b.supply_h then return a.supply_h > b.supply_h end
        return a.wire_reach > b.wire_reach
    end)
    return specs
end

local function normalize_consumers(input)
    local result = {}
    for index, entry in ipairs(input.consumers or {}) do
        local id, rect
        if type(entry) == "table" then
            id = entry.id or entry.consumer_id or entry.name
            rect = entry.rect or entry[2]
            if rect == nil and entry[1] and type(entry[1]) == "table" then rect = entry[1] end
            if rect == nil and entry.x ~= nil then rect = entry end
            if id == nil and entry[1] and type(entry[1]) ~= "table" then id = entry[1] end
        end
        result[#result + 1] = {id = plain_scalar(id, tostring(index)), rect = copy_rect(rect)}
    end
    table.sort(result, function(a, b)
        local aa, bb = tostring(a.id), tostring(b.id)
        if aa ~= bb then return aa < bb end
        local ar, br = a.rect or {}, b.rect or {}
        if (ar.y or 0) ~= (br.y or 0) then return (ar.y or 0) < (br.y or 0) end
        return (ar.x or 0) < (br.x or 0)
    end)
    return result
end

local function normalize_occupied(input)
    local result = {}
    for index, entry in ipairs(input.occupied or {}) do
        local rect, owner
        if type(entry) == "table" then
            rect = entry.rect or entry[1]
            owner = entry.owner or entry[2]
            if rect == nil and entry.x ~= nil then rect = entry end
        end
        rect = copy_rect(rect)
        if rect then result[#result + 1] = {rect = rect, owner = plain_scalar(owner, tostring(index))} end
    end
    table.sort(result, function(a, b)
        if a.rect.y ~= b.rect.y then return a.rect.y < b.rect.y end
        if a.rect.x ~= b.rect.x then return a.rect.x < b.rect.x end
        if a.rect.w ~= b.rect.w then return a.rect.w < b.rect.w end
        if a.rect.h ~= b.rect.h then return a.rect.h < b.rect.h end
        return tostring(a.owner) < tostring(b.owner)
    end)
    return result
end

local function connector_id(name)
    if type(defines) == "table" and type(defines.wire_connector_id) == "table"
        and defines.wire_connector_id[name] ~= nil then
        return defines.wire_connector_id[name]
    end
    --The data contract gives pole_copper the first connector id.  Keeping the
    --fallback makes the pure module usable without the Factorio globals too.
    return 0
end

local function supplied_connector_id(input, name)
    local supplied = type(input) == "table" and (input.wire_connector_ids or input.connector_ids) or nil
    if type(supplied) == "table" and supplied[name] ~= nil then return supplied[name] end
    return connector_id(name)
end

local function consume(budget)
    if type(budget) ~= "table" then return false end
    local ops = integer(budget.ops, 0)
    if ops <= 0 then return false end
    budget.ops = ops - 1
    return true
end

local function candidate_rect(spec, x, y)
    return {x = x, y = y, w = spec.tile_w, h = spec.tile_h}
end

local function consumer_covered(candidate, consumer)
    if not rect_valid(consumer.rect) then return false end
    local centre_x = candidate.rect.x + candidate.rect.w / 2
    local centre_y = candidate.rect.y + candidate.rect.h / 2
    local supply = {x = centre_x - candidate.supply_w, y = centre_y - candidate.supply_h,
        w = candidate.supply_w * 2, h = candidate.supply_h * 2}
    return rect_intersects(supply, consumer.rect)
end

local function candidate_less(a, b, candidates)
    local aa, bb = candidates[a], candidates[b]
    if aa.rect.y ~= bb.rect.y then return aa.rect.y < bb.rect.y end
    if aa.rect.x ~= bb.rect.x then return aa.rect.x < bb.rect.x end
    if aa.quality ~= bb.quality then return aa.quality < bb.quality end
    if tostring(aa.name) ~= tostring(bb.name) then return tostring(aa.name) < tostring(bb.name) end
    if aa.rect.w ~= bb.rect.w then return aa.rect.w < bb.rect.w end
    if aa.rect.h ~= bb.rect.h then return aa.rect.h < bb.rect.h end
    return aa.spec_index < bb.spec_index
end

local function distance_squared(a, b)
    local acx, acy = a.rect.x + a.rect.w / 2, a.rect.y + a.rect.h / 2
    local bcx, bcy = b.rect.x + b.rect.w / 2, b.rect.y + b.rect.h / 2
    local dx, dy = acx - bcx, acy - bcy
    return dx * dx + dy * dy
end

local function wire_legal(a, b)
    local reach = math.min(a.wire_reach, b.wire_reach)
    return distance_squared(a, b) <= reach * reach + math.max(EPSILON, reach * EPSILON)
end

local function candidate_key(spec_index, x, y)
    return tostring(spec_index) .. ":" .. tostring(x) .. ":" .. tostring(y)
end

local function append_candidate(work, candidate)
    local key = candidate_key(candidate.spec_index, candidate.rect.x, candidate.rect.y)
    local existing = work.candidate_index_by_key[key]
    if existing ~= nil then return existing, false end
    work.candidates[#work.candidates + 1] = candidate
    work.candidate_keys[key] = true
    work.candidate_index_by_key[key] = #work.candidates
    return #work.candidates, true
end

local function make_candidate(work, spec_index, x, y, with_covers)
    local spec = work.specs[spec_index]
    local candidate = {
        spec_index = spec_index, name = spec.name, quality = spec.quality,
        rect = candidate_rect(spec, x, y), supply_w = spec.supply_w, supply_h = spec.supply_h,
        wire_reach = spec.wire_reach, covers = {},
    }
    if with_covers then candidate.covers = {} end
    return candidate
end

local function range_for_node(spec, node, reach, axis)
    local centre = axis == "x" and node.rect.x + node.rect.w / 2 or node.rect.y + node.rect.h / 2
    local size = axis == "x" and spec.tile_w or spec.tile_h
    return math.ceil(centre - reach - size / 2 - EPSILON),
        math.floor(centre + reach - size / 2 + EPSILON)
end

local function uf_root(connect, index)
    local parent = connect.parent
    while parent[index] ~= index do
        parent[index] = parent[parent[index]]
        index = parent[index]
    end
    return index
end

local function uf_join(connect, left, right)
    local a, b = uf_root(connect, left), uf_root(connect, right)
    if a == b then return false end
    if connect.size[a] < connect.size[b] then a, b = b, a end
    connect.parent[b] = a
    connect.size[a] = connect.size[a] + connect.size[b]
    connect.components = connect.components - 1
    return true
end

local function next_candidate_position(state)
    local work, cursor = state._work, state.cursor
    if cursor.spec_index > #work.specs or #work.candidates >= work.candidate_limit then return nil end
    local spec_index, spec = cursor.spec_index, work.specs[cursor.spec_index]
    local max_x, max_y = work.grid_w - spec.tile_w, work.grid_h - spec.tile_h
    local x, y = cursor.x, cursor.y
    if spec.fixed_x ~= nil or spec.fixed_y ~= nil then
        x = spec.fixed_x ~= nil and integer(spec.fixed_x, 0) or 0
        y = spec.fixed_y ~= nil and integer(spec.fixed_y, 0) or 0
        cursor.spec_index, cursor.x, cursor.y = spec_index + 1, 0, 0
    elseif max_x < 0 or max_y < 0 or y > max_y then
        cursor.spec_index, cursor.x, cursor.y = spec_index + 1, 0, 0
        return false
    else
        cursor.x = cursor.x + 1
        if cursor.x > max_x then cursor.x, cursor.y = 0, cursor.y + 1 end
    end
    if x < 0 or y < 0 or x > max_x or y > max_y then return false end
    if spec.fixed_x ~= nil and x ~= integer(spec.fixed_x, 0) then return false end
    if spec.fixed_y ~= nil and y ~= integer(spec.fixed_y, 0) then return false end
    return {spec_index = spec_index, x = x, y = y}
end

local function advance_pair(repair, count)
    if repair.pair_right < count then
        repair.pair_right = repair.pair_right + 1
    else
        repair.pair_left = repair.pair_left + 1
        repair.pair_right = repair.pair_left + 1
    end
end

local function advance_prune_pair(eval, count)
    --The graph trial uses the old selected positions so that removing a pole
    --does not change the meaning of a pair halfway through the scan.
    while eval.graph_left <= count do
        if eval.graph_left == eval.removed then
            eval.graph_left = eval.graph_left + 1
            eval.graph_right = eval.graph_left + 1
        elseif eval.graph_right > count then
            eval.graph_left = eval.graph_left + 1
            eval.graph_right = eval.graph_left + 1
        elseif eval.graph_right == eval.removed then
            eval.graph_right = eval.graph_right + 1
        else
            return
        end
    end
end

local function begin_prune_eval(work)
    local removed = work.prune_index
    local eval = {
        removed = removed, coverage_index = 1, coverage_selected_index = 1,
        covered = false, graph_left = 1, graph_right = 2,
        parent = {}, size = {}, components = 0, edges = {},
    }
    for position = 1, #work.selected do
        if position ~= removed then
            eval.parent[position], eval.size[position] = position, 1
            eval.components = eval.components + 1
        end
    end
    advance_prune_pair(eval, #work.selected)
    work.prune_eval = eval
    return eval
end

local function accept_prune(work, eval)
    local old_to_new, selected = {}, {}
    local new_position = 0
    for old_position, candidate_index in ipairs(work.selected) do
        if old_position ~= eval.removed then
            new_position = new_position + 1
            old_to_new[old_position] = new_position
            selected[new_position] = candidate_index
        end
    end

    local connect = {add_position = new_position + 1, compare_position = 1,
        parent = {}, size = {}, components = 0, edges = {}}
    for position = 1, new_position do
        connect.parent[position], connect.size[position] = position, 1
        connect.components = connect.components + 1
    end
    for _, edge in ipairs(eval.edges) do
        local left, right = old_to_new[edge.a], old_to_new[edge.b]
        if left and right and uf_join(connect, left, right) then
            connect.edges[#connect.edges + 1] = {a = left, b = right}
        end
    end

    work.selected = selected
    work.selected_set = {}
    for _, candidate_index in ipairs(selected) do work.selected_set[candidate_index] = true end
    work.connect = connect
    work.prune_index = math.min(eval.removed - 1, #selected)
    work.prune_eval = nil
end

local function start_prune(state)
    local work = state._work
    work.prune_index = #work.selected
    work.prune_eval = nil
    state.cursor.phase = "prune"
end

local function start_publish(state)
    local work = state._work
    work.publish = {
        ordered = {}, picked = {}, pick_position = 1, scan_index = 1, best = nil,
        entities = {}, ids_by_position = {}, position_by_candidate = {}, wires = {}, edge_index = 1,
        uncovered = {}, uncovered_index = 1, errors = {}, entity_index = 1,
    }
    state.cursor.phase = "publish_sort"
end

local function finish_repair(state)
    start_prune(state)
end

local function select_repair_candidate(state, candidate)
    local work, repair = state._work, state._work.repair
    local key = candidate_key(candidate.spec_index, candidate.rect.x, candidate.rect.y)
    local index = work.candidate_index_by_key[key]
    if index == nil then
        if work.relay_candidates_used >= work.relay_candidate_limit then
            work.relay_bound_hit = true
            finish_repair(state)
            return
        end
        index = append_candidate(work, candidate)
        work.relay_candidates_used = work.relay_candidates_used + 1
    end
    if work.selected_set[index] then
        repair.mode = repair.resume
        state.cursor.phase = "repair"
        return
    end
    work.selected[#work.selected + 1] = index
    work.selected_set[index] = true
    work.connect.add_position = #work.selected
    work.connect.compare_position = 1
    state.cursor.phase = "connect"
end

local function begin_repair_eval(state, candidate, resume, frontier)
    local work = state._work
    work.repair_eval = {
        candidate = candidate, occupied_index = 1, selected_index = 1,
        resume = resume, frontier = frontier, blocked = false,
    }
    state.cursor.phase = "repair_check"
end

local function repair_position_usable(state, spec_index, x, y, left, right, source)
    local work, spec = state._work, state._work.specs[spec_index]
    local max_x, max_y = work.grid_w - spec.tile_w, work.grid_h - spec.tile_h
    if x < 0 or y < 0 or x > max_x or y > max_y then return nil end
    if spec.fixed_x ~= nil and x ~= integer(spec.fixed_x, 0) then return nil end
    if spec.fixed_y ~= nil and y ~= integer(spec.fixed_y, 0) then return nil end
    local candidate = make_candidate(work, spec_index, x, y, false)
    if left and not wire_legal(candidate, left) then return nil end
    if right and not wire_legal(candidate, right) then return nil end
    if source and not wire_legal(candidate, source) then return nil end
    return candidate
end

local function direct_spec(state)
    local work, repair = state._work, state._work.repair
    local spec = work.specs[repair.spec_index]
    if not spec then
        repair.mode = "pair_direct"
        advance_pair(repair, #work.selected)
        return
    end
    local left = work.candidates[work.selected[repair.pair_left]]
    local right = work.candidates[work.selected[repair.pair_right]]
    local reach_left = math.min(spec.wire_reach, left.wire_reach)
    local reach_right = math.min(spec.wire_reach, right.wire_reach)
    local left_x, left_x2 = range_for_node(spec, left, reach_left, "x")
    local right_x, right_x2 = range_for_node(spec, right, reach_right, "x")
    local left_y, left_y2 = range_for_node(spec, left, reach_left, "y")
    local right_y, right_y2 = range_for_node(spec, right, reach_right, "y")
    repair.min_x, repair.max_x = math.max(left_x, right_x), math.min(left_x2, right_x2)
    repair.min_y, repair.max_y = math.max(left_y, right_y), math.min(left_y2, right_y2)
    if spec.fixed_x ~= nil then repair.min_x, repair.max_x = integer(spec.fixed_x, 0), integer(spec.fixed_x, 0) end
    if spec.fixed_y ~= nil then repair.min_y, repair.max_y = integer(spec.fixed_y, 0), integer(spec.fixed_y, 0) end
    repair.x, repair.y = repair.min_x, repair.min_y
    if repair.min_x > repair.max_x or repair.min_y > repair.max_y then
        repair.spec_index = repair.spec_index + 1
    else
        repair.mode = "direct_position"
    end
end

local function frontier_spec(state)
    local work, repair = state._work, state._work.repair
    local spec = work.specs[repair.spec_index]
    if not spec then
        repair.mode = "frontier_pair"
        advance_pair(repair, #work.selected)
        return
    end
    local source = work.candidates[work.selected[repair.pair_left]]
    local reach = math.min(spec.wire_reach, source.wire_reach)
    repair.min_x, repair.max_x = range_for_node(spec, source, reach, "x")
    repair.min_y, repair.max_y = range_for_node(spec, source, reach, "y")
    if spec.fixed_x ~= nil then repair.min_x, repair.max_x = integer(spec.fixed_x, 0), integer(spec.fixed_x, 0) end
    if spec.fixed_y ~= nil then repair.min_y, repair.max_y = integer(spec.fixed_y, 0), integer(spec.fixed_y, 0) end
    repair.x, repair.y = repair.min_x, repair.min_y
    repair.best, repair.best_distance = nil, math.huge
    if repair.min_x > repair.max_x or repair.min_y > repair.max_y then
        repair.spec_index = repair.spec_index + 1
    else
        repair.mode = "frontier_position"
    end
end

local function start_repair(state)
    local work = state._work
    if #work.selected < 2 or #work.selected >= work.max_poles
        or work.relay_candidate_limit <= 0 or work.relay_check_limit <= 0 then
        if #work.selected >= 2 and work.connect.components > 1 then work.relay_bound_hit = true end
        finish_repair(state)
        return
    end
    work.repair = {mode = "pair_direct", pair_left = 1, pair_right = 2, spec_index = 1,
        checks = work.relay_checks}
    state.cursor.phase = "repair"
end

function Power.begin(input)
    input = type(input) == "table" and input or {}
    local limits = type(input.limits) == "table" and input.limits or {}
    local specs = normalize_specs(input)
    local consumers = normalize_consumers(input)
    local occupied = normalize_occupied(input)
    local grid = type(input.grid) == "table" and input.grid or input
    local grid_w = integer(input.grid_w or grid.w, nil)
    local grid_h = integer(input.grid_h or grid.h, nil)
    if grid_w == nil then
        grid_w = 0
        for _, consumer in ipairs(consumers) do
            if rect_valid(consumer.rect) then grid_w = math.max(grid_w, math.ceil(consumer.rect.x + consumer.rect.w)) end
        end
    end
    if grid_h == nil then
        grid_h = 0
        for _, consumer in ipairs(consumers) do
            if rect_valid(consumer.rect) then grid_h = math.max(grid_h, math.ceil(consumer.rect.y + consumer.rect.h)) end
        end
    end
    grid_w, grid_h = math.max(0, grid_w), math.max(0, grid_h)

    --The old defaults were one pole per tile per spec and 256 search seeds. On the smallest grid the search
    --offers, one roboport block of 54 by 54 tiles, that is 2916 poles chosen out of 2916 candidates, 256 times
    --over, inside a single op that never yields. A player sees a frozen Generate, and a watchdog caught this
    --run still inside the first seed after 25 seconds of it.
    --A pole is worth placing only to cover a consumer or to relay between poles, so the counts come from the
    --problem: one pole per consumer, plus enough relays to cross the grid twice.
    local max_poles = integer(limits.max_poles, nil)
    if max_poles == nil then
        --Relays are counted in wire reaches, never in tiles: crossing the grid twice needs
        --2 * (w + h) / reach poles, not 2 * (w + h) of them.
        local reach = 1
        for _, spec in ipairs(specs) do reach = math.max(reach, finite(spec.wire_reach, 1)) end
        local relays = math.ceil((grid_w + grid_h) / reach) * 2
        max_poles = math.max(1, math.min(grid_w * grid_h * math.max(1, #specs), #consumers + relays))
    end
    local candidate_limit = integer(limits.max_candidates, nil)
    if candidate_limit == nil then
        candidate_limit = math.max(1, math.min(1000000, grid_w * grid_h * math.max(1, #specs)))
    end
    --There is one deterministic greedy pass.  A seed search made each charged
    --unit repeat the whole selection, so it is intentionally no longer part
    --of the power stage's work shape.
    local search_limit = 1
    local relay_candidate_limit = input.max_off_lattice_candidates or input.max_relay_candidates
        or limits.max_off_lattice_candidates or limits.max_relay_candidates or limits.max_local_candidates
    relay_candidate_limit = math.max(0, integer(relay_candidate_limit, 256) or 0)
    local relay_check_limit = input.max_off_lattice_checks or input.max_relay_checks
        or limits.max_off_lattice_checks or limits.max_relay_checks or limits.max_local_checks
    relay_check_limit = math.max(0, integer(relay_check_limit, 4096) or 0)

    local candidate_positions = 0
    for _, spec in ipairs(specs) do
        if spec.fixed_x ~= nil or spec.fixed_y ~= nil then
            candidate_positions = candidate_positions + 1
        else
            candidate_positions = candidate_positions
                + math.max(0, grid_w - spec.tile_w + 1) * math.max(0, grid_h - spec.tile_h + 1)
        end
    end
    local total_units = math.max(1, candidate_positions * (1 + #occupied + #consumers)
        + candidate_limit * math.max(1, #consumers + 2) + relay_check_limit
        + math.max(1, max_poles) * 8 + #consumers + 16)
    local state = {
        done = false, ok = nil,
        cursor = {phase = "candidate_position", spec_index = 1, x = 0, y = 0},
        progress = {phase = "power", done_units = 0, total_units = total_units},
        result = nil, errors = nil, ops_used = 0,
        _work = {
            grid_w = grid_w, grid_h = grid_h, specs = specs, consumers = consumers, occupied = occupied,
            max_poles = math.max(0, max_poles), candidate_limit = candidate_limit,
            search_limit = search_limit, candidates = {}, candidate_keys = {}, candidate_index_by_key = {},
            candidate_eval = nil, selected = {}, selected_set = {}, covered = {}, covered_count = 0,
            greedy = {candidate_index = 1, selected_position = 1, cover_index = 1,
                candidate = nil, rejected = false, variant_count = 0, gain = 0, total = 0,
                best = nil, best_gain = -1, best_total = -1, mode = "candidate"},
            relay_candidate_limit = relay_candidate_limit, relay_check_limit = relay_check_limit,
            relay_candidates_used = 0, relay_checks = 0, relay_bound_hit = false,
            pruning_enabled = limits.prune == true,
            copper_connector = supplied_connector_id(input, "pole_copper"),
        },
    }
    return state
end

function Power.cancel(state)
    if type(state) ~= "table" or state.done then return state end
    state.cancelled, state.done, state.ok, state.result = true, true, false, nil
    state.errors = {{code = "BP_FAIL_CANCELLED"}}
    state.cursor = {phase = "cancelled"}
    state.progress.phase = "cancelled"
    return state
end

function Power.step(state, budget)
    if type(state) ~= "table" or state.done then return state end
    if type(budget) ~= "table" then return state end
    local work = state._work

    while not state.done and consume(budget) do
        state.ops_used = state.ops_used + 1
        local phase, cursor = state.cursor.phase, state.cursor

        if phase == "candidate_position" then
            if #work.candidates >= work.candidate_limit or cursor.spec_index > #work.specs then
                work.greedy.mode = "candidate"
                cursor.phase = "greedy"
            else
                local position = next_candidate_position(state)
                if position == nil then
                    cursor.phase = "greedy"
                    work.greedy.mode = "candidate"
                elseif position ~= false then
                    local candidate = make_candidate(work, position.spec_index, position.x, position.y, true)
                    work.candidate_eval = {candidate = candidate, occupied_index = 1, consumer_index = 1,
                        blocked = false}
                    cursor.phase = "candidate_occupied"
                end
            end

        elseif phase == "candidate_occupied" then
            local eval = work.candidate_eval
            if eval.occupied_index <= #work.occupied then
                if rect_intersects(eval.candidate.rect, work.occupied[eval.occupied_index].rect) then eval.blocked = true end
                eval.occupied_index = eval.occupied_index + 1
            elseif eval.blocked then
                work.candidate_eval = nil
                cursor.phase = "candidate_position"
            else
                cursor.phase = "candidate_coverage"
            end

        elseif phase == "candidate_coverage" then
            local eval = work.candidate_eval
            if eval.consumer_index <= #work.consumers then
                if consumer_covered(eval.candidate, work.consumers[eval.consumer_index]) then
                    eval.candidate.covers[#eval.candidate.covers + 1] = eval.consumer_index
                end
                eval.consumer_index = eval.consumer_index + 1
            else
                cursor.phase = "candidate_commit"
            end

        elseif phase == "candidate_commit" then
            local eval, candidate = work.candidate_eval, work.candidate_eval.candidate
            local spec = work.specs[candidate.spec_index]
            local lattice_step = math.max(1, math.floor(finite(spec.wire_reach, 2) / 2))
            if #candidate.covers > 0 or (candidate.rect.x % lattice_step == 0 and candidate.rect.y % lattice_step == 0) then
                append_candidate(work, candidate)
            end
            work.candidate_eval = nil
            cursor.phase = "candidate_position"

        elseif phase == "greedy" then
            local greedy = work.greedy
            if greedy.mode ~= "add" and greedy.mode ~= "add_coverage"
                and (#work.selected >= work.max_poles or work.covered_count >= #work.consumers) then
                work.connect = {add_position = 1, compare_position = 1, parent = {}, size = {},
                    components = 0, edges = {}}
                cursor.phase = "connect"
            elseif greedy.mode == "candidate" then
                if greedy.candidate_index > #work.candidates then
                    if greedy.best == nil then
                        work.connect = {add_position = 1, compare_position = 1, parent = {}, size = {},
                            components = 0, edges = {}}
                        cursor.phase = "connect"
                    else
                        greedy.mode = "add"
                    end
                else
                    local index = greedy.candidate_index
                    local candidate = work.candidates[index]
                    if work.selected_set[index] or #candidate.covers == 0 then
                        greedy.candidate_index = index + 1
                    else
                        greedy.candidate = index
                        greedy.selected_position, greedy.variant_count = 1, 0
                        greedy.rejected, greedy.mode = false, "selected_check"
                    end
                end
            elseif greedy.mode == "selected_check" then
                if greedy.selected_position <= #work.selected then
                    local selected_index = work.selected[greedy.selected_position]
                    local selected = work.candidates[selected_index]
                    local candidate = work.candidates[greedy.candidate]
                    if rect_intersects(candidate.rect, selected.rect) then greedy.rejected = true end
                    if candidate.spec_index == selected.spec_index then greedy.variant_count = greedy.variant_count + 1 end
                    greedy.selected_position = greedy.selected_position + 1
                else
                    local limit = work.specs[work.candidates[greedy.candidate].spec_index].max_count
                    if limit ~= nil and greedy.variant_count >= limit then greedy.rejected = true end
                    if greedy.rejected then
                        greedy.candidate_index = greedy.candidate_index + 1
                        greedy.mode = "candidate"
                    else
                        greedy.cover_index, greedy.gain, greedy.total = 1, 0, 0
                        greedy.mode = "coverage"
                    end
                end
            elseif greedy.mode == "coverage" then
                local candidate = work.candidates[greedy.candidate]
                if greedy.cover_index <= #candidate.covers then
                    local consumer_index = candidate.covers[greedy.cover_index]
                    greedy.total = greedy.total + 1
                    if not work.covered[consumer_index] then greedy.gain = greedy.gain + 1 end
                    greedy.cover_index = greedy.cover_index + 1
                else
                    if greedy.gain > 0 and (greedy.best == nil or greedy.gain > greedy.best_gain
                        or (greedy.gain == greedy.best_gain and (greedy.total > greedy.best_total
                            or (greedy.total == greedy.best_total and greedy.candidate < greedy.best)))) then
                        greedy.best, greedy.best_gain, greedy.best_total = greedy.candidate, greedy.gain, greedy.total
                    end
                    greedy.candidate_index = greedy.candidate_index + 1
                    greedy.mode = "candidate"
                end
            elseif greedy.mode == "add" then
                local index = greedy.best
                work.selected[#work.selected + 1] = index
                work.selected_set[index] = true
                greedy.cover_index, greedy.mode = 1, "add_coverage"
            elseif greedy.mode == "add_coverage" then
                local candidate = work.candidates[greedy.best]
                if greedy.cover_index <= #candidate.covers then
                    local consumer_index = candidate.covers[greedy.cover_index]
                    if not work.covered[consumer_index] then
                        work.covered[consumer_index] = true
                        work.covered_count = work.covered_count + 1
                    end
                    greedy.cover_index = greedy.cover_index + 1
                else
                    greedy.best, greedy.best_gain, greedy.best_total = nil, -1, -1
                    greedy.candidate_index, greedy.mode = 1, "candidate"
                end
            end

        elseif phase == "connect" then
            local connect = work.connect
            if connect.add_position > #work.selected then
                if connect.components <= 1 then
                    start_prune(state)
                elseif #work.selected >= work.max_poles then
                    --Reaching the pole bound with multiple components is an
                    --incomplete bounded search.  It must not be presented as
                    --a proof that no legal layout exists.
                    work.relay_bound_hit = true
                    start_prune(state)
                else
                    start_repair(state)
                end
            elseif connect.parent[connect.add_position] == nil then
                local position = connect.add_position
                connect.parent[position], connect.size[position] = position, 1
                connect.components = connect.components + 1
                connect.compare_position = 1
            elseif connect.compare_position < connect.add_position then
                local left = work.candidates[work.selected[connect.add_position]]
                local right = work.candidates[work.selected[connect.compare_position]]
                if wire_legal(left, right) and uf_join(connect, connect.add_position, connect.compare_position) then
                    connect.edges[#connect.edges + 1] = {a = connect.compare_position, b = connect.add_position}
                end
                connect.compare_position = connect.compare_position + 1
            else
                connect.add_position = connect.add_position + 1
                connect.compare_position = 1
            end

        elseif phase == "repair" then
            local repair = work.repair
            if repair.mode == "pair_direct" then
                if #work.selected < 2 or #work.selected >= work.max_poles or repair.pair_left >= #work.selected then
                    repair.mode, repair.pair_left, repair.pair_right = "frontier_pair", 1, 2
                elseif repair.pair_right > #work.selected then
                    advance_pair(repair, #work.selected)
                elseif uf_root(work.connect, repair.pair_left) == uf_root(work.connect, repair.pair_right) then
                    advance_pair(repair, #work.selected)
                else
                    repair.spec_index, repair.mode = 1, "direct_spec"
                end
            elseif repair.mode == "direct_spec" then
                direct_spec(state)
            elseif repair.mode == "direct_position" then
                if repair.y > repair.max_y then
                    repair.spec_index, repair.mode = repair.spec_index + 1, "direct_spec"
                else
                    local x, y = repair.x, repair.y
                    repair.x = repair.x + 1
                    if repair.x > repair.max_x then repair.x, repair.y = repair.min_x, repair.y + 1 end
                    if work.relay_checks >= work.relay_check_limit then
                        work.relay_bound_hit = true
                        finish_repair(state)
                    else
                        work.relay_checks = work.relay_checks + 1
                        local left = work.candidates[work.selected[repair.pair_left]]
                        local right = work.candidates[work.selected[repair.pair_right]]
                        local candidate = repair_position_usable(state, repair.spec_index, x, y, left, right, nil)
                        if candidate then begin_repair_eval(state, candidate, "direct_position", false) end
                    end
                end
            elseif repair.mode == "frontier_pair" then
                if #work.selected < 2 or #work.selected >= work.max_poles or repair.pair_left >= #work.selected then
                    finish_repair(state)
                elseif repair.pair_right > #work.selected then
                    advance_pair(repair, #work.selected)
                elseif uf_root(work.connect, repair.pair_left) == uf_root(work.connect, repair.pair_right) then
                    advance_pair(repair, #work.selected)
                else
                    repair.spec_index, repair.mode = 1, "frontier_spec"
                end
            elseif repair.mode == "frontier_spec" then
                frontier_spec(state)
            elseif repair.mode == "frontier_position" then
                if repair.y > repair.max_y then
                    if repair.best then repair.mode = "frontier_commit"
                    else repair.spec_index, repair.mode = repair.spec_index + 1, "frontier_spec" end
                else
                    local x, y = repair.x, repair.y
                    repair.x = repair.x + 1
                    if repair.x > repair.max_x then repair.x, repair.y = repair.min_x, repair.y + 1 end
                    if work.relay_checks >= work.relay_check_limit then
                        work.relay_bound_hit = true
                        finish_repair(state)
                    else
                        work.relay_checks = work.relay_checks + 1
                        local source = work.candidates[work.selected[repair.pair_left]]
                        local candidate = repair_position_usable(state, repair.spec_index, x, y, nil, nil, source)
                        if candidate then begin_repair_eval(state, candidate, "frontier_compare", true) end
                    end
                end
            elseif repair.mode == "frontier_commit" then
                local candidate = repair.best
                repair.best = nil
                select_repair_candidate(state, candidate)
            elseif repair.mode == "direct_commit" then
                local candidate = work.repair_eval.candidate
                work.repair_eval = nil
                select_repair_candidate(state, candidate)
            else
                finish_repair(state)
            end

        elseif phase == "repair_check" then
            local eval = work.repair_eval
            if eval.occupied_index <= #work.occupied then
                if rect_intersects(eval.candidate.rect, work.occupied[eval.occupied_index].rect) then eval.blocked = true end
                eval.occupied_index = eval.occupied_index + 1
            elseif eval.blocked then
                work.repair_eval = nil
                cursor.phase, work.repair.mode = "repair", eval.resume
            elseif eval.selected_index <= #work.selected then
                if rect_intersects(eval.candidate.rect,
                    work.candidates[work.selected[eval.selected_index]].rect) then eval.blocked = true end
                eval.selected_index = eval.selected_index + 1
            else
                cursor.phase = eval.frontier and "frontier_compare" or "repair"
                if not eval.frontier then work.repair.mode = "direct_commit" end
            end

        elseif phase == "frontier_compare" then
            local eval, repair = work.repair_eval, work.repair
            local target = work.candidates[work.selected[repair.pair_right]]
            local distance = distance_squared(eval.candidate, target)
            if repair.best == nil or distance < repair.best_distance
                or (distance == repair.best_distance
                    and (eval.candidate.rect.y < repair.best.rect.y
                        or (eval.candidate.rect.y == repair.best.rect.y and eval.candidate.rect.x < repair.best.rect.x))) then
                repair.best, repair.best_distance = eval.candidate, distance
            end
            work.repair_eval = nil
            cursor.phase = "repair"
            repair.mode = "frontier_position"

        elseif phase == "prune" then
            if not work.pruning_enabled or work.prune_index <= 0 then
                start_publish(state)
            else
                begin_prune_eval(work)
                cursor.phase = "prune_coverage"
            end

        elseif phase == "prune_coverage" then
            local eval = work.prune_eval
            if eval.coverage_index > #work.consumers then
                cursor.phase = "prune_graph"
            elseif eval.covered then
                eval.coverage_index = eval.coverage_index + 1
                eval.coverage_selected_index = 1
                eval.covered = false
            elseif eval.coverage_selected_index > #work.selected then
                --The trial would leave a consumer uncovered; keep this pole.
                work.prune_eval = nil
                work.prune_index = work.prune_index - 1
                cursor.phase = "prune"
            else
                local selected_position = eval.coverage_selected_index
                eval.coverage_selected_index = selected_position + 1
                if selected_position ~= eval.removed
                    and consumer_covered(work.candidates[work.selected[selected_position]],
                        work.consumers[eval.coverage_index]) then
                    eval.covered = true
                end
            end

        elseif phase == "prune_graph" then
            local eval = work.prune_eval
            if eval.graph_left > #work.selected then
                if eval.components <= 1 then
                    accept_prune(work, eval)
                    cursor.phase = "prune"
                else
                    work.prune_eval = nil
                    work.prune_index = work.prune_index - 1
                    cursor.phase = "prune"
                end
            else
                local left = work.candidates[work.selected[eval.graph_left]]
                local right = work.candidates[work.selected[eval.graph_right]]
                if wire_legal(left, right) and uf_join(eval, eval.graph_left, eval.graph_right) then
                    eval.edges[#eval.edges + 1] = {a = eval.graph_left, b = eval.graph_right}
                end
                eval.graph_right = eval.graph_right + 1
                advance_prune_pair(eval, #work.selected)
            end

        elseif phase == "publish_sort" then
            local publish = work.publish
            if publish.pick_position > #work.selected then
                publish.entity_index = 1
                cursor.phase = "publish_entities"
            elseif publish.scan_index <= #work.selected then
                local index = work.selected[publish.scan_index]
                if not publish.picked[index]
                    and (publish.best == nil or candidate_less(index, publish.best, work.candidates)) then
                    publish.best = index
                end
                publish.scan_index = publish.scan_index + 1
            else
                publish.ordered[publish.pick_position] = publish.best
                publish.picked[publish.best] = true
                publish.pick_position = publish.pick_position + 1
                publish.scan_index, publish.best = 1, nil
            end

        elseif phase == "publish_entities" then
            local publish = work.publish
            if publish.entity_index > #publish.ordered then
                publish.edge_index = 1
                cursor.phase = "publish_wires"
            else
                local position, candidate_index = publish.entity_index, publish.ordered[publish.entity_index]
                local candidate, rect = work.candidates[candidate_index], work.candidates[candidate_index].rect
                local id = "p:" .. tostring(position)
                publish.ids_by_position[position] = id
                publish.position_by_candidate[candidate_index] = position
                publish.entities[position] = {
                    id = id, kind = "pole", name = candidate.name, quality = candidate.quality,
                    x = rect.x, y = rect.y, w = rect.w, h = rect.h,
                    rect = {x = rect.x, y = rect.y, w = rect.w, h = rect.h},
                    supply_w = candidate.supply_w, supply_h = candidate.supply_h,
                    wire_reach = candidate.wire_reach,
                }
                publish.entity_index = position + 1
            end

        elseif phase == "publish_wires" then
            local publish, edges = work.publish, work.connect.edges
            if publish.edge_index > #edges then
                publish.uncovered_index = 1
                cursor.phase = "publish_uncovered"
            else
                local edge = edges[publish.edge_index]
                local a_position = publish.position_by_candidate[work.selected[edge.a]]
                local b_position = publish.position_by_candidate[work.selected[edge.b]]
                publish.wires[#publish.wires + 1] = {
                    a_id = publish.ids_by_position[a_position], a_connector = work.copper_connector,
                    b_id = publish.ids_by_position[b_position], b_connector = work.copper_connector,
                }
                publish.edge_index = publish.edge_index + 1
            end

        elseif phase == "publish_uncovered" then
            local publish = work.publish
            if publish.uncovered_index > #work.consumers then
                cursor.phase = "publish_errors"
            else
                local index = publish.uncovered_index
                if not work.covered[index] then publish.uncovered[#publish.uncovered + 1] = work.consumers[index].id end
                publish.uncovered_index = index + 1
            end

        elseif phase == "publish_errors" then
            local publish = work.publish
            if #publish.uncovered > 0 then
                publish.errors[#publish.errors + 1] = {code = "BP_PW_UNCOVERED", ids = publish.uncovered}
            end
            if work.connect.components > 1 then
                publish.errors[#publish.errors + 1] = {code = "BP_PW_DISCONNECTED", components = work.connect.components}
            end
            if work.relay_bound_hit and work.connect.components > 1 then
                publish.errors[#publish.errors + 1] = {code = "BP_PW_SEARCH_BOUND", candidates = work.relay_candidates_used,
                    limit = work.relay_candidate_limit, checks = work.relay_checks, check_limit = work.relay_check_limit}
            end
            cursor.phase = "publish_connection"

        elseif phase == "publish_connection" then
            local publish = work.publish
            if publish.entities[1] then
                local entity = publish.entities[1]
                publish.connection_point = {pole_id = entity.id, x = entity.x + entity.w, y = entity.y + entity.h / 2}
            end
            cursor.phase = "publish_finish"

        elseif phase == "publish_finish" then
            local publish = work.publish
            state.result = {entities = publish.entities, wires = publish.wires, pole_count = #publish.entities,
                components = work.connect.components, uncovered = publish.uncovered,
                connection_point = publish.connection_point, errors = publish.errors}
            state.errors, state.ok, state.done = publish.errors, #publish.errors == 0, true
            cursor.phase = "done"
            state.progress.phase = "power"
            state.progress.done_units = state.progress.total_units
        else
            if phase == "done" then state.done = true end
        end
        state.progress.done_units = math.min(state.progress.total_units, state.progress.done_units + 1)
    end
    return state
end

return Power
