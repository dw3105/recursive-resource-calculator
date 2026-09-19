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
    return spec[key]
end

local function quality_name(value)
    if type(value) == "table" then return value.name or value.id or "normal" end
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
    local result = {
        name = raw.name or raw.prototype or "electric-pole",
        quality = selected_quality,
        tile_w = math.max(1, integer(raw.tile_w or raw.width, 1)),
        tile_h = math.max(1, integer(raw.tile_h or raw.height, 1)),
        supply_w = finite(value_for_quality(raw, "supply_w", selected_quality), nil),
        supply_h = finite(value_for_quality(raw, "supply_h", selected_quality), nil),
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
        append_spec(specs, pole)
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
        result[#result + 1] = {id = id == nil and tostring(index) or id, rect = copy_rect(rect)}
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
        if rect then result[#result + 1] = {rect = rect, owner = owner == nil and tostring(index) or owner} end
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
    local left = centre_x - candidate.supply_w
    local right = centre_x + candidate.supply_w
    local top = centre_y - candidate.supply_h
    local bottom = centre_y + candidate.supply_h
    return left <= consumer.rect.x + EPSILON and top <= consumer.rect.y + EPSILON
        and right + EPSILON >= consumer.rect.x + consumer.rect.w
        and bottom + EPSILON >= consumer.rect.y + consumer.rect.h
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

local function overlap_selected(candidate_index, selected, candidates)
    local candidate = candidates[candidate_index]
    for _, selected_index in ipairs(selected) do
        if rect_intersects(candidate.rect, candidates[selected_index].rect) then return true end
    end
    return false
end

local function variant_allowed(candidate_index, selected, candidates, specs)
    local limit = specs[candidates[candidate_index].spec_index].max_count
    if limit == nil then return true end
    local count = 0
    for _, selected_index in ipairs(selected) do
        if candidates[selected_index].spec_index == candidates[candidate_index].spec_index then count = count + 1 end
    end
    return count < limit
end

local function selection_coverage(selected, candidates, consumers)
    local covered = {}
    for _, candidate_index in ipairs(selected) do
        for _, consumer_index in ipairs(candidates[candidate_index].covers) do covered[consumer_index] = true end
    end
    local uncovered = {}
    for index, consumer in ipairs(consumers) do
        if not covered[index] then uncovered[#uncovered + 1] = consumer.id end
    end
    return covered, uncovered
end

local function distance_squared(a, b)
    local acx = a.rect.x + a.rect.w / 2
    local acy = a.rect.y + a.rect.h / 2
    local bcx = b.rect.x + b.rect.w / 2
    local bcy = b.rect.y + b.rect.h / 2
    local dx, dy = acx - bcx, acy - bcy
    return dx * dx + dy * dy
end

local function wire_legal(a, b)
    local reach = math.min(a.wire_reach, b.wire_reach)
    return distance_squared(a, b) <= reach * reach + math.max(EPSILON, reach * EPSILON)
end

local function graph_info(selected, candidates)
    local parent = {}
    for index = 1, #selected do parent[index] = index end

    local function root(index)
        while parent[index] ~= index do
            parent[index] = parent[parent[index]]
            index = parent[index]
        end
        return index
    end
    local function join(a, b)
        a, b = root(a), root(b)
        if a == b then return false end
        if a < b then parent[b] = a else parent[a] = b end
        return true
    end

    local possible = {}
    for a = 1, #selected do
        for b = a + 1, #selected do
            local left, right = candidates[selected[a]], candidates[selected[b]]
            if wire_legal(left, right) then
                possible[#possible + 1] = {a = a, b = b, distance = distance_squared(left, right)}
            end
        end
    end
    table.sort(possible, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        if a.a ~= b.a then return a.a < b.a end
        return a.b < b.b
    end)

    local edges = {}
    for _, edge in ipairs(possible) do
        if join(edge.a, edge.b) then edges[#edges + 1] = edge end
    end
    local roots = {}
    for index = 1, #selected do roots[root(index)] = true end
    local components = 0
    for _, _ in pairs(roots) do components = components + 1 end
    return {components = components, edges = edges, parent = parent, root = root}
end

local function addable(candidate_index, selected, candidates, specs, max_poles)
    if #selected >= max_poles then return false end
    if overlap_selected(candidate_index, selected, candidates) then return false end
    return variant_allowed(candidate_index, selected, candidates, specs)
end

local function greedy_selection(work, seed_index)
    local selected, selected_set = {}, {}
    local max_poles = work.max_poles
    if seed_index ~= nil and seed_index > 0 and work.candidates[seed_index]
        and #work.candidates[seed_index].covers > 0
        and addable(seed_index, selected, work.candidates, work.specs, max_poles) then
        selected[#selected + 1] = seed_index
        selected_set[seed_index] = true
    end

    local covered = selection_coverage(selected, work.candidates, work.consumers)
    while #selected < max_poles do
        local all_covered = true
        for index, _ in ipairs(work.consumers) do
            if not covered[index] then all_covered = false break end
        end
        if all_covered then break end

        local best, best_gain, best_total
        for candidate_index, candidate in ipairs(work.candidates) do
            if not selected_set[candidate_index] and #candidate.covers > 0
                and addable(candidate_index, selected, work.candidates, work.specs, max_poles) then
                local gain, total = 0, 0
                for _, consumer_index in ipairs(candidate.covers) do
                    total = total + 1
                    if not covered[consumer_index] then gain = gain + 1 end
                end
                if gain > 0 and (best == nil or gain > best_gain
                    or (gain == best_gain and (total > best_total
                        or (total == best_total and candidate_index < best)))) then
                    best, best_gain, best_total = candidate_index, gain, total
                end
            end
        end
        if best == nil then break end
        selected[#selected + 1] = best
        selected_set[best] = true
        for _, consumer_index in ipairs(work.candidates[best].covers) do covered[consumer_index] = true end
    end
    return selected
end

local function connect_selection(selected, work)
    local selected_set = {}
    for _, index in ipairs(selected) do selected_set[index] = true end

    while #selected < work.max_poles do
        local current = graph_info(selected, work.candidates)
        if current.components <= 1 then break end

        local best, best_gain, best_distance
        for candidate_index, candidate in ipairs(work.candidates) do
            if not selected_set[candidate_index]
                and addable(candidate_index, selected, work.candidates, work.specs, work.max_poles) then
                local component_seen, component_count = {}, 0
                local closest_source = math.huge
                local target_distance = math.huge
                for selected_position, selected_index in ipairs(selected) do
                    local other = work.candidates[selected_index]
                    local component = current.root(selected_position)
                    local distance = distance_squared(candidate, other)
                    if wire_legal(candidate, other) then
                        if not component_seen[component] then
                            component_seen[component] = true
                            component_count = component_count + 1
                        end
                        if distance < closest_source then closest_source = distance end
                    elseif component ~= current.root(1) then
                        if distance < target_distance then target_distance = distance end
                    end
                end
                --A candidate joining two existing components is always better
                --than one which merely extends a frontier.  When extending, walk
                --towards another component so a legal chain is deterministic.
                local gain = component_count > 0 and component_count - 1 or -1
                local distance_key = gain > 0 and closest_source or target_distance
                if distance_key == math.huge then distance_key = closest_source end
                if gain >= 0 and (best == nil or gain > best_gain
                    or (gain == best_gain and (distance_key < best_distance
                        or (distance_key == best_distance and candidate_index < best)))) then
                    best, best_gain, best_distance = candidate_index, gain, distance_key
                end
            end
        end
        if best == nil then break end
        selected[#selected + 1] = best
        selected_set[best] = true
    end
    return selected
end

local function remove_redundant(selected, work)
    local require_connected = graph_info(selected, work.candidates).components <= 1
    local index = #selected
    while index >= 1 do
        local trial = {}
        for position, candidate_index in ipairs(selected) do
            if position ~= index then trial[#trial + 1] = candidate_index end
        end
        local _, uncovered = selection_coverage(trial, work.candidates, work.consumers)
        local components = graph_info(trial, work.candidates).components
        if #uncovered == 0 and (not require_connected or components <= 1) then selected = trial end
        index = index - 1
    end
    return selected
end

local function selection_key(selected, candidates)
    local ordered = {}
    for index, candidate_index in ipairs(selected) do ordered[index] = candidate_index end
    table.sort(ordered, function(a, b) return candidate_less(a, b, candidates) end)
    local parts = {}
    for _, index in ipairs(ordered) do
        local candidate = candidates[index]
        parts[#parts + 1] = tostring(candidate.rect.y) .. ":" .. tostring(candidate.rect.x)
            .. ":" .. tostring(candidate.quality) .. ":" .. tostring(candidate.name)
    end
    return table.concat(parts, "|")
end

local function better_selection(candidate_selection, best, work)
    local _, candidate_uncovered = selection_coverage(candidate_selection, work.candidates, work.consumers)
    local candidate_graph = graph_info(candidate_selection, work.candidates)
    local candidate_connected = candidate_graph.components <= 1 and #candidate_uncovered == 0
    if best == nil then return true end

    local _, best_uncovered = selection_coverage(best, work.candidates, work.consumers)
    local best_graph = graph_info(best, work.candidates)
    local best_connected = best_graph.components <= 1 and #best_uncovered == 0
    if #candidate_uncovered ~= #best_uncovered then return #candidate_uncovered < #best_uncovered end
    if candidate_connected ~= best_connected then return candidate_connected end
    if candidate_graph.components ~= best_graph.components then return candidate_graph.components < best_graph.components end
    if #candidate_selection ~= #best then return #candidate_selection < #best end
    return selection_key(candidate_selection, work.candidates) < selection_key(best, work.candidates)
end

local function publish(state)
    local work = state._work
    local selected = state.best or {}
    local ordered = {}
    for index, candidate_index in ipairs(selected) do ordered[index] = candidate_index end
    table.sort(ordered, function(a, b) return candidate_less(a, b, work.candidates) end)

    local entities, ids = {}, {}
    for position, candidate_index in ipairs(ordered) do
        local candidate = work.candidates[candidate_index]
        local rect = candidate.rect
        local id = "p:" .. tostring(position)
        ids[candidate_index] = id
        entities[#entities + 1] = {
            id = id, kind = "pole", name = candidate.name, quality = candidate.quality,
            x = rect.x, y = rect.y, w = rect.w, h = rect.h,
            rect = {x = rect.x, y = rect.y, w = rect.w, h = rect.h},
            supply_w = candidate.supply_w, supply_h = candidate.supply_h,
            wire_reach = candidate.wire_reach,
        }
    end

    local ordered_graph = {}
    for index = 1, #ordered do ordered_graph[index] = index end
    local graph = graph_info(ordered_graph, entities)
    local wires = {}
    local copper = connector_id("pole_copper")
    for _, edge in ipairs(graph.edges) do
        local left, right = entities[edge.a], entities[edge.b]
        wires[#wires + 1] = {
            a_id = left.id, a_connector = copper,
            b_id = right.id, b_connector = copper,
        }
    end
    table.sort(wires, function(a, b)
        if a.a_id ~= b.a_id then return a.a_id < b.a_id end
        return a.b_id < b.b_id
    end)

    local _, uncovered = selection_coverage(selected, work.candidates, work.consumers)
    local errors = {}
    if #uncovered > 0 then errors[#errors + 1] = {code = "BP_PW_UNCOVERED", ids = uncovered} end
    if graph.components > 1 then errors[#errors + 1] = {code = "BP_PW_DISCONNECTED", components = graph.components} end

    local connection_point
    if entities[1] then
        local entity = entities[1]
        connection_point = {
            pole_id = entity.id,
            --The point is on the right-hand edge of the first pole, not in its
            --collision rectangle, so an external source can reach it.
            x = entity.x + entity.w,
            y = entity.y + entity.h / 2,
        }
    end

    state.result = {
        entities = entities, wires = wires, pole_count = #entities,
        components = graph.components, uncovered = uncovered,
        connection_point = connection_point, errors = errors,
    }
    state.errors = errors
    state.ok = #errors == 0
    state.done = true
    state.cursor = {phase = "done"}
    state.progress.phase = "power"
    state.progress.done_units = state.progress.total_units or state.progress.done_units
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
    local search_limit = integer(limits.max_search_seeds, 8)
    search_limit = math.max(1, search_limit)

    local total_units = candidate_limit + search_limit + 1
    local state = {
        done = false, ok = nil, cursor = {phase = "candidates", spec_index = 1, x = 0, y = 0},
        progress = {phase = "power", done_units = 0, total_units = total_units},
        result = nil, errors = nil, ops_used = 0,
        _work = {
            grid_w = grid_w, grid_h = grid_h, specs = specs, consumers = consumers, occupied = occupied,
            max_poles = math.max(0, max_poles), candidate_limit = candidate_limit,
            search_limit = search_limit, candidates = {}, best = nil,
        },
    }
    return state
end

function Power.step(state, budget)
    if type(state) ~= "table" or state.done then return state end
    if type(budget) ~= "table" then return state end
    local work = state._work

    while not state.done and consume(budget) do
        state.ops_used = state.ops_used + 1
        if state.cursor.phase == "candidates" then
            local spec_index = state.cursor.spec_index
            if spec_index > #work.specs or #work.candidates >= work.candidate_limit then
                state.cursor.phase, state.cursor.search_index = "search", 0
            else
                local spec = work.specs[spec_index]
                local max_x = work.grid_w - spec.tile_w
                local max_y = work.grid_h - spec.tile_h
                local x, y = state.cursor.x, state.cursor.y
                if spec.fixed_x ~= nil or spec.fixed_y ~= nil then
                    x, y = integer(spec.fixed_x, 0), integer(spec.fixed_y, 0)
                    state.cursor.y = max_y + 1
                elseif max_x < 0 or max_y < 0 or y > max_y then
                    state.cursor.spec_index = spec_index + 1
                    state.cursor.x, state.cursor.y = 0, 0
                else
                    state.cursor.x = state.cursor.x + 1
                    if state.cursor.x > max_x then state.cursor.x, state.cursor.y = 0, state.cursor.y + 1 end
                end

                if not (max_x < 0 or max_y < 0 or (spec.fixed_x == nil and spec.fixed_y == nil and y > max_y)) then
                    local rect = candidate_rect(spec, x, y)
                    local blocked = false
                    for _, occupied in ipairs(work.occupied) do
                        if rect_intersects(rect, occupied.rect) then blocked = true break end
                    end
                    if not blocked and x >= 0 and y >= 0 and x <= max_x and y <= max_y then
                        local candidate = {
                            spec_index = spec_index, name = spec.name, quality = spec.quality,
                            rect = rect, supply_w = spec.supply_w, supply_h = spec.supply_h,
                            wire_reach = spec.wire_reach, covers = {},
                        }
                        for consumer_index, consumer in ipairs(work.consumers) do
                            if consumer_covered(candidate, consumer) then candidate.covers[#candidate.covers + 1] = consumer_index end
                        end
                        --A pole that covers nothing is only ever a relay, and a relay chain needs one position
                        --every half wire reach, never one per tile. Keeping every empty tile made the selection
                        --scan thousands of candidates that can never improve it.
                        local step = math.max(1, math.floor(finite(spec.wire_reach, 2) / 2))
                        if #candidate.covers > 0 or (x % step == 0 and y % step == 0) then
                            work.candidates[#work.candidates + 1] = candidate
                        end
                    end
                end
            end
        elseif state.cursor.phase == "search" then
            local search_index = state.cursor.search_index
            local seed_count = math.min(#work.candidates + 1, work.search_limit)
            if search_index >= seed_count then
                state.cursor.phase = "finalize"
            else
                local seed = search_index == 0 and nil or search_index
                local selected = greedy_selection(work, seed)
                selected = connect_selection(selected, work)
                selected = remove_redundant(selected, work)
                if better_selection(selected, work.best, work) then work.best = selected end
                state.cursor.search_index = search_index + 1
            end
        elseif state.cursor.phase == "finalize" then
            state.best = work.best or {}
            publish(state)
        else
            state.cursor.phase = "finalize"
        end
        state.progress.done_units = state.progress.done_units + 1
    end
    return state
end

return Power
