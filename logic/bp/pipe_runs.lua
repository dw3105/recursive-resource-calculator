--A straight run of plain pipes can use one pipe-to-ground pair: the buried span has no side connection.
local Grid = require "logic.bp.grid"
local PipeRuns = {}

local function flow_of(segment)
    return segment and segment.flow_id
end

--`work` is route's mutable work table. `h` supplies route's private geometry and id helpers.
function PipeRuns.bury(work, h)
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
                            and connects_back(after_x, after_y, last.x, last.y, flow) then
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
                            work.entities[#work.entities + 1] = first_entity
                            work.entities[#work.entities + 1] = second_entity
                            work.segments[#work.segments + 1] = pair
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
    return pairs_laid
end

return PipeRuns
