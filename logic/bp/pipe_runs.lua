--A straight run of plain pipes can use one pipe-to-ground pair: the buried span has no side connection.
local Grid = require "logic.bp.grid"
local PipeRuns = {}

local function flow_of(segment)
    return segment and segment.flow_id
end

-- Drop plain pipe tiles whose neighbours remain connected without them.
--Built once: neighbours() runs per BFS cell at publish, and 5 fresh tables per call cost blue's publish tick
--(2026-09-28, legalcopilot-dev, result_for 186 ms).
local NEIGHBOUR_STEPS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

function PipeRuns.prune_redundant(work, h)
    local by_cell = work.segments_by_cell or {}
    local key = h.key
    --Round 56 gate (blue publish tick 201 ms, 2 rounds x 562 checks): a check records every cell key it reads; the
    --next round re-checks a cell only when a later removal hit that set, else the same reads give the same answer.
    local reads = nil
    local entity_by_segment = {}
    -- legalcopilot-dev, lua5.2, 2026-09-28: index once per call; all fixes cut blue publish from 573-773 to 98 ms, with golden sha unchanged.
    local entity_by_tile = {}
    for _, entity in ipairs(work.entities or {}) do
        if entity.segment_id and not entity._route_removed then entity_by_segment[entity.segment_id] = entity end
        if entity.segment_id and entity.position then
            local tiles = entity_by_tile[entity.segment_id]
            if not tiles then tiles = {}; entity_by_tile[entity.segment_id] = tiles end
            local x, y = math.floor(entity.position.x), math.floor(entity.position.y)
            local row = tiles[x]
            if not row then row = {}; tiles[x] = row end
            local list = row[y]
            if not list then list = {}; row[y] = list end
            list[#list + 1] = entity
        end
    end
    local function live(segment)
        return segment and segment.kind == "pipe" and not segment._route_removed
    end
    local function opens_to(segment, x, y, tx, ty)
        if not segment.underground then return true end
        local candidates = entity_by_tile[segment.segment_id]
        candidates = candidates and candidates[x] and candidates[x][y] or {}
        local entity, visits = nil, 0
        for _, candidate in ipairs(candidates) do
            visits = visits + 1
            if not candidate._route_removed then entity = candidate; break end
        end
        if PipeRuns._count_visits then PipeRuns._visits = math.max(PipeRuns._visits or 0, visits) end
        if not entity or entity._route_removed then return false end
        local dx, dy = Grid.dir_vector(entity.direction)
        return dx ~= nil and x + dx == tx and y + dy == ty
    end
    --Neighbour candidates per cell, built once: prune only removes cells, so a later call filters the same list by
    --liveness, flow and skip (same keys read, same order; round 56 gate blue publish tick).
    local adjacency = {}
    local function neighbours(x, y, flow, skip, known_key)
        local here_key = known_key or key(x, y)
        local here = by_cell[here_key]
        local entry = adjacency[here_key]
        if not entry or entry.here ~= here then
            entry = {here = here, keys = {}, cands = {}}
            for index, d in ipairs(NEIGHBOUR_STEPS) do
                local nx, ny = x + d[1], y + d[2]
                local nk = key(nx, ny)
                entry.keys[index] = nk
                local other = by_cell[nk]
                if here and live(other) and opens_to(here, x, y, nx, ny) and opens_to(other, nx, ny, x, y) then
                    entry.cands[#entry.cands + 1] = {key = nk, other = other, x = nx, y = ny, flow = flow_of(other)}
                end
            end
            if here and here.underground then
                local partner_key = here_key == here.underground_entry_key
                    and here.underground_exit_key or here.underground_entry_key
                entry.partner_key = partner_key
                if partner_key then
                    local px, py = h.coordinate_from_key(partner_key)
                    entry.partner = {x = px, y = py, key = partner_key}
                end
            end
            adjacency[here_key] = entry
        end
        --A check reads this cell, its four neighbours and its underground partner. Only the cell is recorded: the
        --staleness test below expands it (a removed cell is plain, never a partner).
        if reads then reads[here_key] = true end
        local result = {}
        --A candidate's kind and flow never change; only removal does (by_cell cleared, _route_removed set). Callers
        --only read x, y and key, so the candidate record itself is returned.
        for _, cand in ipairs(entry.cands) do
            local other = cand.other
            if cand.key ~= skip and cand.flow == flow and by_cell[cand.key] == other and not other._route_removed then
                result[#result + 1] = cand
            end
        end
        local partner_key = entry.partner_key
        if partner_key then
            local partner = by_cell[partner_key]
            if partner_key ~= skip and live(partner) and flow_of(partner) == flow then
                result[#result + 1] = entry.partner
            end
        end
        return result
    end
    local function connected(a, b, flow, skip)
        local seen, queue, head = {[a.key or key(a.x, a.y)] = true}, {a}, 1
        while queue[head] and head <= 64 do
            local cell = queue[head]
            head = head + 1
            if cell.x == b.x and cell.y == b.y then return true end
            for _, n in ipairs(neighbours(cell.x, cell.y, flow, skip, cell.key)) do
                local nk = n.key or key(n.x, n.y)
                if not seen[nk] then seen[nk] = true; queue[#queue + 1] = n end
            end
        end
        return false
    end
    local removed, changed = 0, true
    local removals, checked = {}, {}
    while changed do
        changed = false
        local cells = {}
        for cell_key, segment in pairs(by_cell) do
            if live(segment) and not segment.underground then cells[#cells + 1] = cell_key end
        end
        table.sort(cells)
        for _, cell_key in ipairs(cells) do
            local segment = by_cell[cell_key]
            local x, y = h.coordinate_from_key(cell_key)
            local reserved = work.port_cells and work.port_cells[cell_key]
            local memo = checked[cell_key]
            local stale = memo == nil
            if memo then
                for i = memo.seq + 1, #removals do
                    local r, seen = removals[i], memo.reads
                    if seen[r.key] or seen[key(r.x + 1, r.y)] or seen[key(r.x - 1, r.y)]
                        or seen[key(r.x, r.y + 1)] or seen[key(r.x, r.y - 1)] then stale = true; break end
                end
            end
            if stale and live(segment) and not (reserved and reserved._port_owners) then
                reads = {}
                local around = neighbours(x, y, flow_of(segment), nil)
                local redundant = #around >= 2
                for i = 2, #around do
                    if redundant and not connected(around[1], around[i], flow_of(segment), cell_key) then
                        redundant = false
                    end
                end
                local my_reads = reads
                reads = nil
                if not redundant then checked[cell_key] = {seq = #removals, reads = my_reads} end
                if redundant then
                    segment._route_removed = true
                    local entity = entity_by_segment[segment.segment_id]
                    if entity then entity._route_removed = true end
                    local heir = by_cell[key(around[1].x, around[1].y)]
                    for _, binding in ipairs(work.bindings or {}) do
                        if binding.segment_id == segment.segment_id then binding.segment_id = heir.segment_id end
                    end
                    by_cell[cell_key] = nil
                    removals[#removals + 1] = {key = cell_key, x = x, y = y}
                    removed, changed = removed + 1, true
                end
            end
        end
    end
    if removed > 0 then
        local kept = {}
        for _, segment in ipairs(work.segments or {}) do
            if not segment._route_removed then kept[#kept + 1] = segment end
        end
        work.segments = kept
        local kept_entities = {}
        for _, entity in ipairs(work.entities or {}) do
            if not entity._route_removed then kept_entities[#kept_entities + 1] = entity end
        end
        work.entities = kept_entities
    end
    return removed
end

--`work` is route's mutable work table. `h` supplies route's private geometry and id helpers.
function PipeRuns.bury(work, h)
    PipeRuns.prune_redundant(work, h)
    local by_cell = work.segments_by_cell or {}
    local function key(x, y) return h.key(x, y) end
    local entity_by_segment = {}
    for _, entity in ipairs(work.entities or {}) do
        if entity.segment_id and not entity._route_removed then entity_by_segment[entity.segment_id] = entity end
    end
    local function plain(segment)
        return segment and segment.kind == "pipe" and not segment.underground and not segment._route_removed
    end
    local function port_tile(x, y)
        local reserved = work.port_cells and work.port_cells[key(x, y)]
        return reserved and reserved._port_owners ~= nil
    end
    local reach = math.floor(h.finite(work.pipe and work.pipe.underground_max_distance, 10))
    local pairs_laid = 0
    local function connects_back(x, y, target_x, target_y, flow)
        local segment = by_cell[key(x, y)]
        if not segment or segment._route_removed or segment.kind ~= "pipe" or flow_of(segment) ~= flow then return false end
        if not segment.underground then return true end
        local entity = nil
        for _, candidate in ipairs(work.entities or {}) do
            if candidate.segment_id == segment.segment_id and not candidate._route_removed
                and math.floor(candidate.position.x) == x and math.floor(candidate.position.y) == y then
                entity = candidate
                break
            end
        end
        if not entity then return false end
        local dx, dy = Grid.dir_vector(entity.direction)
        return dx ~= nil and x + dx == target_x and y + dy == target_y
    end

    --A new pair whose end lies inside an existing pipe pair on the same axis would weave into it, which the engine
    --does not do. Gray + magenta (legalcopilot-dev 2026-09-28): plain molten-iron pipes (8..10,88) above pair
    --(6,88)-(16,88) became pair (8,88)-(10,88), flagged by blueprint_audit. Any covering span has an end within
    --reach on the scanned side.
    local function inside_span(x, y, dx, dy)
        for d = 1, reach do
            local segment = by_cell[key(x - dx * d, y - dy * d)]
            if segment and segment.underground and segment.kind == "pipe" and not segment._route_removed
                and segment.underground_entry_x then
                local ex, ey, xx, xy = segment.underground_entry_x, segment.underground_entry_y,
                    segment.underground_exit_x, segment.underground_exit_y
                if dy == 0 and ey == y and xy == y and x > math.min(ex, xx) and x < math.max(ex, xx) then return true end
                if dx == 0 and ex == x and xx == x and y > math.min(ey, xy) and y < math.max(ey, xy) then return true end
            end
        end
        return false
    end
    for _, direction in ipairs({Grid.EAST, Grid.SOUTH}) do
        local dx, dy = Grid.dir_vector(direction)
        local cells = {}
        for cell_key, segment in pairs(by_cell) do
            if plain(segment) then cells[#cells + 1] = cell_key end
        end
        table.sort(cells)
        local done = {}
        for _, cell_key in ipairs(cells) do
            local segment = by_cell[cell_key]
            local x, y = h.coordinate_from_key(cell_key)
            local flow = flow_of(segment)
            local previous = by_cell[key(x - dx, y - dy)]
            if plain(segment) and not done[cell_key] and not (plain(previous) and flow_of(previous) == flow) then
                local run, cx, cy = {}, x, y
                while true do
                    local current = by_cell[key(cx, cy)]
                    if not (plain(current) and flow_of(current) == flow) then break end
                    run[#run + 1] = {x = cx, y = cy, segment = current}
                    cx, cy = cx + dx, cy + dy
                end
                local function side_clean(tile)
                    if port_tile(tile.x, tile.y) then return false end
                    for _, side in ipairs({{dy, dx}, {-dy, -dx}}) do
                        local neighbor = by_cell[key(tile.x + side[1], tile.y + side[2])]
                        if neighbor and neighbor.kind == "pipe" and flow_of(neighbor) == flow then return false end
                        if port_tile(tile.x + side[1], tile.y + side[2]) then return false end
                    end
                    return true
                end
                local i = 1
                while i <= #run do
                    local j = i
                    while j <= #run and side_clean(run[j]) and (j - i) <= reach do j = j + 1 end
                    j = j - 1
                    if j - i + 1 >= 3 then
                        local first, last = run[i], run[j]
                        local before_x, before_y = first.x - dx, first.y - dy
                        local after_x, after_y = last.x + dx, last.y + dy
                        if connects_back(before_x, before_y, first.x, first.y, flow)
                            and connects_back(after_x, after_y, last.x, last.y, flow)
                            and not inside_span(first.x, first.y, dx, dy) and not inside_span(last.x, last.y, dx, dy) then
                            local pair = {segment_id = h.next_segment_id(work), kind = "pipe",
                                capacity_per_second = first.segment.capacity_per_second, allocations = {},
                                flow_id = flow, flow_ids = first.segment.flow_ids, direction = direction,
                                underground = true, length = j - i,
                                underground_entry_x = first.x, underground_entry_y = first.y,
                                underground_exit_x = last.x, underground_exit_y = last.y,
                                underground_entry_key = key(first.x, first.y), underground_exit_key = key(last.x, last.y)}
                            local seen_allocations = {}
                            for tile_index = i, j do
                                local old = run[tile_index].segment
                                for _, allocation in ipairs(old.allocations or {}) do
                                    local allocation_key = tostring(allocation.flow_id) .. "\0" .. tostring(allocation.sink)
                                    if not seen_allocations[allocation_key] then
                                        seen_allocations[allocation_key] = true
                                        pair.allocations[#pair.allocations + 1] = {
                                            flow_id = allocation.flow_id, sink = allocation.sink,
                                            rate_per_second = allocation.rate_per_second}
                                    end
                                end
                                old._route_removed = true
                                local old_entity = entity_by_segment[old.segment_id]
                                if old_entity then old_entity._route_removed = true end
                                for _, binding in ipairs(work.bindings or {}) do
                                    if binding.segment_id == old.segment_id then binding.segment_id = pair.segment_id end
                                end
                                by_cell[key(run[tile_index].x, run[tile_index].y)] = nil
                                done[key(run[tile_index].x, run[tile_index].y)] = true
                            end
                            local name = (work.pipe and (work.pipe.underground or work.pipe.pipe)) or h.infrastructure(work, "pipe")
                            local first_id, second_id = h.next_entity_id(work), h.next_entity_id(work)
                            local first_entity = {id = first_id, name = name,
                                position = h.entity_position(first.x, first.y), direction = Grid.dir_opposite(direction),
                                dir = Grid.dir_opposite(direction), flow_id = flow, ug_role = "input",
                                ug_pair_id = second_id, segment_id = pair.segment_id}
                            local second_entity = {id = second_id, name = name,
                                position = h.entity_position(last.x, last.y), direction = direction, dir = direction,
                                flow_id = flow, ug_role = "output", ug_pair_id = first_id, segment_id = pair.segment_id}
                            if work.journal then h.jinsert(work, work.entities, first_entity) else work.entities[#work.entities + 1] = first_entity end
                            if work.journal then h.jinsert(work, work.entities, second_entity) else work.entities[#work.entities + 1] = second_entity end
                            if work.journal then h.jinsert(work, work.segments, pair) else work.segments[#work.segments + 1] = pair end
                            by_cell[pair.underground_entry_key] = pair
                            by_cell[pair.underground_exit_key] = pair
                            work.underground_cells = work.underground_cells or {}
                            work.underground_cells[pair.underground_entry_key] = true
                            work.underground_cells[pair.underground_exit_key] = true
                            work.entity_by_segment[pair.segment_id] = first_entity
                            entity_by_segment[pair.segment_id] = first_entity
                            pairs_laid = pairs_laid + 1
                        end
                    end
                    i = math.max(j + 1, i + 1)
                end
            end
        end
    end
    local kept = {}
    for _, segment in ipairs(work.segments or {}) do
        if not segment._route_removed then kept[#kept + 1] = segment end
    end
    work.segments = kept
    -- Route publication buries pipes after route pruning; remove dangling plain-pipe leaves here.
    -- Synthetic callers omit demands, so only real route work receives this cleanup.
    if work.demands then
        local endpoint_cells = {}
        local entity_by_cell = {}
        for _, entity in ipairs(work.entities or {}) do
            if entity.segment_id and not entity._route_removed and entity.position then
                entity_by_cell[key(math.floor(entity.position.x), math.floor(entity.position.y))] = entity
            end
        end
        local function protect(point)
            if type(point) == "table" and point.x and point.y then
                endpoint_cells[key(math.floor(point.x), math.floor(point.y))] = true
            end
        end
        for _, demand in ipairs(work.demands) do
            protect(demand.source); protect(demand.sink)
            for _, point in ipairs(demand.source_candidates or {}) do protect(point) end
            for _, point in ipairs(demand.sink_candidates or {}) do protect(point) end
        end
        for _, point in pairs(work.endpoint_by_id or {}) do protect(point) end
        local function endpoint(segment, cell_key)
            return segment.endpoint or segment.route_endpoint or endpoint_cells[cell_key]
        end
        local removed_any = false
        local changed = true
        while changed do
            changed = false
            local leaves = {}
            for cell_key, segment in pairs(by_cell) do
                if plain(segment) then
                    local x, y = h.coordinate_from_key(cell_key)
                    local degree = 0
                    for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                        local nx, ny = x + d[1], y + d[2]
                        local other = by_cell[key(nx, ny)]
                        if other and not other._route_removed and other.kind == "pipe" and flow_of(other) == flow_of(segment) then
                            local here_ok, other_ok = true, true
                            if other.underground then
                                local entity = entity_by_cell[key(nx, ny)]
                                local vx, vy
                                if entity then vx, vy = Grid.dir_vector(entity.direction) end
                                other_ok = vx ~= nil and nx + vx == x and ny + vy == y
                            end
                            if segment.underground then
                                local entity = entity_by_cell[cell_key]
                                local vx, vy
                                if entity then vx, vy = Grid.dir_vector(entity.direction) end
                                here_ok = vx ~= nil and x + vx == nx and y + vy == ny
                            end
                            if here_ok and other_ok then degree = degree + 1 end
                        end
                    end
                    local xcoord, ycoord = h.coordinate_from_key(cell_key)
                    if degree <= 1 and not endpoint(segment, cell_key) and not port_tile(xcoord, ycoord) then
                        leaves[#leaves + 1] = cell_key
                    end
                end
            end
            for _, cell_key in ipairs(leaves) do
                local segment = by_cell[cell_key]
                if segment and plain(segment) then
                    segment._route_removed = true
                    local entity = entity_by_segment[segment.segment_id]
                    if entity then entity._route_removed = true end
                    by_cell[cell_key] = nil
                    removed_any = true
                    changed = true
                end
            end
        end
        if removed_any then
            local live_segments, live_entities = {}, {}
            for _, segment in ipairs(work.segments) do if not segment._route_removed then live_segments[#live_segments + 1] = segment end end
            for _, entity in ipairs(work.entities or {}) do if not entity._route_removed then live_entities[#live_entities + 1] = entity end end
            work.segments, work.entities = live_segments, live_entities
        end
    end
    return pairs_laid
end

return PipeRuns
