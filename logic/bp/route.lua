--Belts, undergrounds, splitters and pipes between blocks, with enough capacity for every consumer at once.
--
--Owned by lane W3-route. It creates no inserters: a block already carries the ones that serve its machines.
--
--Capacity is an allocation, not a rate comparison: a segment carries a list of who gets how much through it, so
--one belt cannot promise its whole throughput to an intermediate consumer and again to an external output.
--  Segment = {segment_id, kind = "belt"|"lane"|"pipe"|"inserter", capacity_per_second,
--             allocations = {{flow_id, sink = "step:<id>"|"port:<id>", rate_per_second}}}
--
--Underground pairing is resolved from the rotated runtime connections, never from a vanilla rule: an endpoint
--pairs when its own connection of type "underground" faces its partner's, within that connection's own
--max_underground_distance. The exposed connection of a vanilla pipe-to-ground faces away from its partner.
local Route = {}

local Grid = require "logic.bp.grid"

local EPSILON = 1e-9
local DIRECTIONS = {Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}
local DIRECTION_ORDERS = {
    DIRECTIONS,
    {Grid.SOUTH, Grid.EAST, Grid.NORTH, Grid.WEST},
    {Grid.EAST, Grid.SOUTH, Grid.WEST, Grid.NORTH},
    {Grid.EAST, Grid.NORTH, Grid.WEST, Grid.SOUTH},
}

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback
end

local function tolerance(value)
    return math.max(EPSILON, math.abs(value or 0) * EPSILON)
end

local function new_counters()
    return {
        expansions = 0,
        demands_attempted = 0,
        restarts = 0,
        crossings_placed = 0,
        searches_abandoned = {
            blocked = 0,
            capacity = 0,
            expansions = 0,
            fluid_mix = 0,
            no_path = 0,
        },
    }
end

local function abandon_search(work, reason)
    local abandoned = work.counters.searches_abandoned
    abandoned[reason] = (abandoned[reason] or 0) + 1
end

local function copy_position(value)
    if type(value) ~= "table" or type(value.x) ~= "number" or type(value.y) ~= "number" then return nil end
    return {x = value.x, y = value.y}
end

local function copy_rect(value)
    if type(value) ~= "table" then return nil end
    local x, y = finite(value.x), finite(value.y)
    local w, h = finite(value.w or value.width), finite(value.h or value.height)
    if x == nil or y == nil or w == nil or h == nil then return nil end
    return {x = x, y = y, w = w, h = h}
end

local function sorted_keys(map)
    local keys = {}
    for key, _ in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function flow_id_of(flow)
    return flow and (flow.flow_id or flow.full_name or flow.id)
end

local function port_flow_id(port)
    return port and (port.flow_id or port.full_name or port.flow)
end

local function role_of(port)
    return port and (port.role or (port.direction == "in" and "in") or (port.direction == "out" and "out"))
end

local function step_id_of(value)
    if type(value) == "table" then return value.step_id or value.id or value.block_id end
    return value
end

local function block_step_id(block)
    if type(block) ~= "table" then return nil end
    if block.step_id ~= nil then return block.step_id end
    for _, machine in ipairs(block.machines or {}) do
        if machine.step_id ~= nil then return machine.step_id end
    end
    for _, member in ipairs(block.members or {}) do
        if member.step_id ~= nil then return member.step_id end
    end
    return nil
end

local function share_of(value)
    if type(value) ~= "table" then return finite(value, 0) end
    return finite(value.share_per_second or value.rate_per_second or value.rate, 0)
end

local function coordinate_key(x, y)
    return tostring(x) .. ":" .. tostring(y)
end

local function direction_from_step(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    --An underground crossing steps over the tiles it dives under, so the step is longer than one tile while the
    --direction is still one of the four.
    if dx ~= 0 then dx = dx > 0 and 1 or -1 end
    if dy ~= 0 then dy = dy > 0 and 1 or -1 end
    return Grid.dir_from_vector(dx, dy)
end

local function is_crossing_step(from, to)
    if type(from) ~= "table" or type(to) ~= "table" then return false end
    return math.abs(to.x - from.x) + math.abs(to.y - from.y) > 1
end

local function add_rect_cells(cells, rect, owner)
    if not rect then return end
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do cells[coordinate_key(x, y)] = owner end
    end
end

local function placement_for(block, placements)
    local placement = block.placement or {}
    local id = block.block_id or block.id
    if placements then
        if placements[id] then placement = placements[id]
        else
            for _, candidate in ipairs(placements) do
                if (candidate.block_id or candidate.id) == id then placement = candidate; break end
            end
        end
    end
    return {
        x = finite(block.x, finite(placement.x, 0)),
        y = finite(block.y, finite(placement.y, 0)),
        dir = finite(block.dir, finite(placement.dir, Grid.NORTH)),
    }
end

local function dimension_for(block, placement, key, fallback)
    return finite(block[key], finite(placement[key], fallback))
end

local function turns_for(dir)
    return math.floor((dir or Grid.NORTH) % 16 / 4)
end

local function rotate_connection(raw, placement_dir, endpoint_x, endpoint_y)
    if type(raw) ~= "table" then return nil end
    local result = {}
    local direction = raw.direction or raw.dir or raw.connection_dir
    local position = copy_position(raw.position)
    if not position and type(raw.positions) == "table" then
        position = copy_position(raw.positions[turns_for(placement_dir) + 1]) or copy_position(raw.positions[1])
    end
    if direction ~= nil and not raw.global_direction then direction = Grid.rotate_dir(direction, placement_dir) end
    if position and raw.position ~= nil and raw.global_position then
        result.x, result.y = math.floor(position.x), math.floor(position.y)
    else
        result.x, result.y = endpoint_x, endpoint_y
    end
    result.direction = direction
    result.connection_type = raw.connection_type or raw.type
    result.max_underground_distance = finite(raw.max_underground_distance, finite(raw.max_distance))
    return result
end

local function connection_for(block, port, placement, catalog, endpoint_x, endpoint_y)
    local raw = port.connection or port.pipe_connection or port.underground_connection
    if not raw and (port.connection_type or port.connection_dir or port.connection_direction) then raw = port end
    if raw then return rotate_connection(raw, placement.dir, endpoint_x, endpoint_y) end
    local member = port.member_id and (block.members and block.members[port.member_id])
    local machine_name = port.machine or (type(member) == "table" and member.name) or block.machine
    local entity = catalog and catalog.entity and machine_name and catalog.entity[machine_name]
    local boxes = entity and (entity.fluid_boxes or entity.fluidbox_prototypes)
    if not boxes then return nil end
    local wanted_box = port.fluidbox_index or port.box_index
    local wanted_connection = port.connection_index or port.pipe_connection_index
    for box_index, box in ipairs(boxes) do
        if wanted_box == nil or wanted_box == box.index or wanted_box == box_index then
            for connection_index, candidate in ipairs(box.connections or box.pipe_connections or {}) do
                if wanted_connection == nil or wanted_connection == connection_index then
                    return rotate_connection(candidate, placement.dir, endpoint_x, endpoint_y)
                end
            end
        end
    end
    return nil
end

local function point_from(value)
    if type(value) ~= "table" then return nil, nil end
    local point = value.position or value
    local x, y = finite(point.x), finite(point.y)
    if x == nil or y == nil then return nil, nil end
    return math.floor(x), math.floor(y)
end

local function perimeter_entries(input)
    local source = input.perimeter_ports or input.perimeter or input.external_ports
    if not source and type(input.ports) == "table" then source = input.ports end
    local result = {}
    if type(source) ~= "table" then return result end
    if #source > 0 then
        for _, port in ipairs(source) do result[#result + 1] = port end
    else
        for _, key in ipairs(sorted_keys(source)) do
            local port = source[key]
            if type(port) == "table" then
                local copy = {}
                for child_key, child in pairs(port) do copy[child_key] = child end
                copy.port_id = copy.port_id or key
                result[#result + 1] = copy
            end
        end
    end
    table.sort(result, function(a, b)
        return tostring(a.port_id or a.id or "") < tostring(b.port_id or b.id or "")
    end)
    return result
end

local function map_blocks(input)
    local source = input.blocks or {}
    local result = {}
    if #source > 0 then
        for _, block in ipairs(source) do
            local copy = {}
            for key, value in pairs(block) do copy[key] = value end
            result[#result + 1] = copy
        end
    else
        for _, id in ipairs(sorted_keys(source)) do
            local block = source[id]
            if type(block) == "table" then
                local copy = {}
                for key, value in pairs(block) do copy[key] = value end
                copy.block_id = copy.block_id or id
                result[#result + 1] = copy
            end
        end
    end
    table.sort(result, function(a, b)
        return tostring(a.block_id or a.id or "") < tostring(b.block_id or b.id or "")
    end)
    return result
end

local function map_placements(input)
    local source = input.placements or {}
    local result = {}
    if #source > 0 then
        for _, placement in ipairs(source) do result[placement.block_id or placement.id] = placement end
    else
        for id, placement in pairs(source) do result[id] = placement end
    end
    return result
end

local function flow_list(input)
    local source = input.flows or (input.plan and input.plan.flows) or {}
    local result = {}
    if #source > 0 then
        for _, flow in ipairs(source) do result[#result + 1] = flow end
    else
        for _, id in ipairs(sorted_keys(source)) do
            local flow = source[id]
            if type(flow) == "table" then
                local copy = {}
                for key, value in pairs(flow) do copy[key] = value end
                copy.flow_id = copy.flow_id or id
                result[#result + 1] = copy
            end
        end
    end
    table.sort(result, function(a, b) return tostring(flow_id_of(a)) < tostring(flow_id_of(b)) end)
    return result
end

local function copy_grid(input)
    local grid = input.grid
    local w = finite(input.grid_w, finite(input.width))
    local h = finite(input.grid_h, finite(input.height))
    if type(grid) == "table" then w, h = finite(grid.w, w), finite(grid.h, h) end
    local cells = {}
    if type(grid) == "table" and type(grid.cells) == "table" then
        for index, owner in pairs(grid.cells) do if owner ~= nil then cells[index] = owner end end
    end
    return {w = w, h = h, indexed_cells = cells}
end

local function indexed_cell(grid, x, y)
    if grid.w == nil or grid.h == nil then return nil end
    if x < 0 or y < 0 or x >= grid.w or y >= grid.h then return "__outside__" end
    return grid.indexed_cells[y * grid.w + x + 1]
end

local function add_input_obstacles(work, input, blocks)
    local cells = work.obstacles
    local obstacles = input.obstacles or input.occupied or {}
    if #obstacles > 0 then
        for index, obstacle in ipairs(obstacles) do
            local rect = copy_rect(obstacle.rect or obstacle)
            if rect then add_rect_cells(cells, rect, obstacle.owner or obstacle.kind or index) end
        end
    else
        for key, obstacle in pairs(obstacles) do
            local rect = copy_rect(obstacle.rect or obstacle)
            if rect then add_rect_cells(cells, rect, obstacle.owner or obstacle.kind or key) end
        end
    end
    local roboports = input.roboports or input.roboport_rects or {}
    for index, roboport in ipairs(roboports) do
        local rect = copy_rect(roboport.rect or roboport)
        if rect then add_rect_cells(cells, rect, "roboport:" .. tostring(index)) end
    end
    for _, block in ipairs(blocks) do
        local placement = block._placement
        local owner = "machine:" .. tostring(block.block_id or block.id)
        local indexed_members = false
        for _, entity in ipairs(block.entities or block.placed_entities or {}) do
            local rect = copy_rect(entity.rect or entity)
            if rect then
                add_rect_cells(cells, rect, owner)
                indexed_members = true
            end
        end
        if not indexed_members then
            for _, port in ipairs(block.ports or block.block_ports or {}) do
                for _, rect in ipairs(port._occupied or {}) do
                    local copied = copy_rect(rect)
                    if copied then add_rect_cells(cells, copied, rect.owner or owner); indexed_members = true end
                end
                if indexed_members then break end
            end
        end
        if not indexed_members then
            -- Search passes a materialized envelope and absolute port cells. Direct route callers pass a local
            -- block rectangle plus a placement. Do not rotate the former a second time.
            local width, height = Grid.rotate_size(block._w, block._h, placement.dir)
            for _, port in ipairs(block.ports or block.block_ports or {}) do
                if port.x ~= nil or port.y ~= nil then
                    width, height = block._w, block._h
                    break
                end
            end
            add_rect_cells(cells, {x = placement.x, y = placement.y, w = width, h = height}, owner)
        end
    end
end

--A block packed flush with the grid edge puts the tile above it, or beside it, outside the world, and routing
--refuses every cell outside the grid. The port then moves to the block's opposite side, which is the same
--distance from its machine and is still a tile outside the block, as §5.8 requires.
local function mirrored_port(block, port)
    --The attach coordinates are written in the block's own frame, so the mirror is computed there too. Reading
    --the rotated size here made a rotated block never mirror, and its port stayed one tile outside the world.
    local envelope = type(block.envelope) == "table" and block.envelope or block
    local w = finite(port._block_w, finite(block.w, finite(envelope.w, 1)))
    local h = finite(port._block_h, finite(block.h, finite(envelope.h, 1)))
    local mirrored = {}
    for key, value in pairs(port) do mirrored[key] = value end
    if port.attach_dy == -1 then
        mirrored.attach_dy = h
    elseif port.attach_dy == h then
        mirrored.attach_dy = -1
    elseif port.attach_dx == -1 then
        mirrored.attach_dx = w
    elseif port.attach_dx == w then
        mirrored.attach_dx = -1
    else
        return nil
    end
    mirrored.normal_dir = port.normal_dir ~= nil and Grid.dir_opposite(port.normal_dir) or nil
    mirrored.travel_dir = port.travel_dir ~= nil and Grid.dir_opposite(port.travel_dir) or nil
    return mirrored
end

local function inside_grid(work, x, y)
    local grid = work and work.grid
    if type(grid) ~= "table" then return true end
    return x >= 0 and y >= 0 and x < finite(grid.w, 0) and y < finite(grid.h, 0)
end

local function endpoint_position(block, placement, port, work)
    local point = port.position or ((port.x ~= nil or port.y ~= nil) and port) or nil
    local x, y = point_from(point)
    if x ~= nil and y ~= nil and (work == nil or inside_grid(work, x, y)) then return x, y end
    local frame = block
    if port._block_w ~= nil and port._block_h ~= nil then frame = {w = port._block_w, h = port._block_h} end
    local placed = Grid.place_port(frame, placement, port)
    if work ~= nil and not inside_grid(work, placed.x, placed.y) then
        local mirrored = mirrored_port(block, port)
        if mirrored then
            local other = Grid.place_port(frame, placement, mirrored)
            if inside_grid(work, other.x, other.y) then return other.x, other.y, mirrored end
        end
    end
    return placed.x, placed.y
end

local function endpoint_direction(port, placement, role)
    if port.x ~= nil or port.y ~= nil then
        return port.travel_dir or port.dir or port.normal_dir
    end
    local direction = port.travel_dir
    if direction == nil and port.dir ~= nil then direction = port.dir end
    if direction == nil then
        local normal = port.normal_dir or Grid.NORTH
        direction = role == "in" and normal or Grid.dir_opposite(normal)
    end
    return Grid.rotate_dir(direction, placement.dir)
end

local function normalize_endpoint(block, placement, port, catalog, work)
    local role = role_of(port)
    if role ~= "in" and role ~= "out" then return nil end
    local x, y, mirrored = endpoint_position(block, placement, port, work)
    if mirrored then port = mirrored end
    local endpoint = {
        port_id = port.port_id or port.id or ((block.block_id or block.id or "block") .. ":" .. tostring(port.flow_id or port.full_name)),
        block_id = block.block_id or block.id,
        step_id = port.step_id or block_step_id(block),
        role = role,
        flow_id = port_flow_id(port),
        kind = port.kind or (port.is_fluid and "fluid" or "item"),
        rate_per_second = finite(port.rate_per_second, finite(port.rate, 0)),
        x = x, y = y,
        travel_dir = endpoint_direction(port, placement, role),
    }
    endpoint.connection = connection_for(block, port, placement, catalog, x, y)
    return endpoint
end

local function normalize_perimeter(port)
    local role = role_of(port)
    if role ~= "in" and role ~= "out" then return nil end
    local x, y = point_from(port)
    if x == nil or y == nil then return nil end
    return {
        port_id = port.port_id or port.id,
        step_id = "$external",
        role = role,
        flow_id = port_flow_id(port),
        kind = port.kind or (port.is_fluid and "fluid" or "item"),
        rate_per_second = finite(port.rate_per_second, finite(port.rate, 0)),
        x = x, y = y,
        travel_dir = port.travel_dir or port.dir or port.normal_dir,
        perimeter = true,
    }
end

local function capacity_for(work, flow)
    if flow.is_fluid or flow.kind == "fluid" then
        return finite(work.input_pipe_capacity, finite(work.pipe and work.pipe.throughput_per_second, math.huge)), "pipe"
    end
    return finite(work.input_belt_capacity, finite(work.belt and work.belt.items_per_second,
        finite(work.belt and work.belt.capacity_per_second, math.huge))), "belt"
end

local function infrastructure(work, kind)
    if kind == "pipe" then return (work.pipe and (work.pipe.pipe or work.pipe.name)) or work.input_pipe_name or "pipe" end
    return (work.belt and (work.belt.belt or work.belt.name)) or work.input_belt_name or "transport-belt"
end

local function sink_key(endpoint)
    if endpoint.perimeter then return "port:" .. tostring(endpoint.port_id) end
    return "step:" .. tostring(endpoint.step_id)
end

local function endpoint_candidates(index, flow_id, role, step_id)
    local by_flow = index[flow_id] or {}
    local candidates = by_flow[role] or {}
    local result = {}
    for _, endpoint in ipairs(candidates) do
        if step_id == nil or endpoint.step_id == step_id then result[#result + 1] = endpoint end
    end
    return result
end

local function first_endpoint(index, flow_id, role, step_id)
    return endpoint_candidates(index, flow_id, role, step_id)[1]
end

local function perimeter_for(perimeter, flow_id, role, port_id)
    for _, endpoint in ipairs(perimeter) do
        if (port_id == nil or endpoint.port_id == port_id)
            and endpoint.flow_id == flow_id and endpoint.role == role then return endpoint end
    end
    return nil
end

local function source_endpoint(work, flow_id, entry)
    local step_id = step_id_of(entry)
    if step_id == "$external" then return perimeter_for(work.perimeter, flow_id, "in", entry.port_id) end
    return first_endpoint(work.endpoint_index, flow_id, "out", step_id)
end

local function target_endpoint(work, flow_id, entry)
    local step_id = step_id_of(entry)
    if step_id == "$external" then return perimeter_for(work.perimeter, flow_id, "out", entry.port_id) end
    return first_endpoint(work.endpoint_index, flow_id, "in", step_id)
end

local function build_demands(work, flows)
    local demands = {}
    for _, flow in ipairs(flows) do
        local id = flow_id_of(flow)
        if id then
            local producers, consumers = {}, {}
            for _, entry in ipairs(flow.producers or {}) do
                producers[#producers + 1] = {endpoint = source_endpoint(work, id, entry), remaining = share_of(entry)}
            end
            for _, entry in ipairs(flow.consumers or {}) do
                consumers[#consumers + 1] = {endpoint = target_endpoint(work, id, entry), remaining = share_of(entry)}
            end
            if #producers == 0 and #consumers == 0 then
                for _, endpoint in ipairs(work.endpoint_index[id] and work.endpoint_index[id]["out"] or {}) do
                    producers[#producers + 1] = {endpoint = endpoint, remaining = endpoint.rate_per_second}
                end
                for _, endpoint in ipairs(work.endpoint_index[id] and work.endpoint_index[id]["in"] or {}) do
                    consumers[#consumers + 1] = {endpoint = endpoint, remaining = endpoint.rate_per_second}
                end
            end
            for _, producer in ipairs(producers) do
                for _, consumer in ipairs(consumers) do
                    if producer.endpoint and consumer.endpoint then
                        local amount = math.min(producer.remaining, consumer.remaining)
                        if amount > tolerance(amount) then
                            demands[#demands + 1] = {flow = flow, flow_id = id, source = producer.endpoint, sink = consumer.endpoint,
                                amount = amount, remaining = amount}
                            producer.remaining, consumer.remaining = producer.remaining - amount, consumer.remaining - amount
                        end
                    end
                    if producer.remaining <= tolerance(producer.remaining) then break end
                end
            end
            for _, producer in ipairs(producers) do
                if producer.remaining > tolerance(producer.remaining) then
                    work.initial_error = {code = "BP_R_PORT_BLOCKED", flow_id = id, detail = "producer port is not bound"}
                    return demands
                end
            end
            for _, consumer in ipairs(consumers) do
                if consumer.remaining > tolerance(consumer.remaining) then
                    work.initial_error = {code = "BP_R_PORT_BLOCKED", flow_id = id, detail = "consumer port is not bound"}
                    return demands
                end
            end
        end
    end
    return demands
end

local function segment_total(segment)
    local total = 0
    for _, allocation in ipairs(segment.allocations or {}) do total = total + allocation.rate_per_second end
    return total
end

local function segment_allows(segment, demand, amount)
    if not segment then return true end
    if segment.flow_id ~= demand.flow_id then return false, segment.kind == "pipe" and "fluid_mix" or "occupied" end
    if segment.kind ~= demand.kind then return false, "occupied" end
    if segment_total(segment) + amount > segment.capacity_per_second + tolerance(segment.capacity_per_second) then return false, "capacity" end
    return true
end

local function static_owner(work, x, y)
    local owner = work.obstacles[coordinate_key(x, y)]
    if owner ~= nil then return owner end
    return indexed_cell(work.grid, x, y)
end

local function is_allowed_owner(owner)
    return owner == nil or owner == Grid.RESERVED.corridor or owner == Grid.RESERVED.port
end

local function endpoint_is_blocked(work, endpoint)
    if not endpoint then return true end
    local owner = static_owner(work, endpoint.x, endpoint.y)
    return owner ~= nil and not is_allowed_owner(owner)
end

--A splitter's anchor is the tile where the existing belt was found.  Its other tile is one step in the direction
--the splitter carries transport, not one step in a fixed north/east/west order.  Keep the footprint in the same
--cell index used by path search so a later branch sees the second tile as occupied before it mutates any entity.
local function splitter_second_cell(x, y, direction)
    --The splitter is two tiles across its belt travel, not two tiles along it.  Rotate the east-side offset with
    --the travel direction: north -> east, east -> south, south -> west, west -> north.
    local side = Grid.rotate_dir(Grid.EAST, direction)
    local dx, dy = Grid.dir_vector(side)
    if dx == nil or dy == nil then return nil, nil end
    return x + dx, y + dy
end

local function splitter_can_absorb(segment)
    return segment ~= nil and segment.kind == "belt" and not segment.underground and not segment.splitter
end

local function splitter_cell_allowed(work, demand, x, y, segment, search)
    local function blocked()
        if search then search.saw_blocked = true end
        return false
    end
    if not inside_grid(work, x, y) then return blocked() end
    local owner = static_owner(work, x, y)
    if owner ~= nil and not is_allowed_owner(owner) then return blocked() end
    local reserved = work.port_cells and work.port_cells[coordinate_key(x, y)]
    if reserved ~= nil then
        local source_id = demand.source and demand.source.port_id
        local sink_id = demand.sink and demand.sink.port_id
        if not (reserved[source_id] or reserved[sink_id] or reserved["flow:" .. tostring(demand.flow_id)]) then
            return blocked()
        end
    end
    if work.splitter_blocked_cells[coordinate_key(x, y)] then return blocked() end
    local occupant = work.segments_by_cell[coordinate_key(x, y)]
    if occupant ~= nil and occupant ~= segment then return blocked() end
    return true
end

local function splitter_branch_allowed(work, demand, x, y, direction, segment, search)
    if segment and segment.splitter then
        local second_x, second_y = splitter_second_cell(x, y, direction)
        return second_x ~= nil and segment.splitter_direction == direction
            and segment.splitter_second_key == coordinate_key(second_x, second_y)
    end
    if not segment or segment.kind ~= "belt" or not (work.belt and work.belt.splitter) then
        if search then search.saw_blocked = true end
        return false
    end
    local second_x, second_y = splitter_second_cell(x, y, direction)
    if second_x == nil then
        if search then search.saw_blocked = true end
        return false
    end
    return splitter_cell_allowed(work, demand, second_x, second_y, segment, search)
end

local function blocked_port_detail(work, source, sink)
    local function describe(endpoint)
        if not endpoint then return "nil" end
        return "(" .. tostring(endpoint.x) .. "," .. tostring(endpoint.y) .. " owner="
            .. tostring(static_owner(work, endpoint.x, endpoint.y)) .. ")"
    end
    return "src=" .. describe(source) .. " sink=" .. describe(sink)
end

local function connection_direction(endpoint)
    return endpoint and endpoint.connection and endpoint.connection.direction
end

local function underground_distance(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

local function underground_candidate(demand, kind, work)
    local source, sink = demand.source, demand.sink
    if not source or not sink then return nil, "missing" end
    local source_connection, sink_connection = source.connection, sink.connection
    local requested = (source_connection and source_connection.connection_type == "underground")
        or (sink_connection and sink_connection.connection_type == "underground")
    if not requested then return nil, "not_requested" end
    if not source_connection or not sink_connection
        or source_connection.connection_type ~= "underground"
        or sink_connection.connection_type ~= "underground" then return nil, "reversed" end
    local dx, dy = sink.x - source.x, sink.y - source.y
    if not ((dx == 0 and dy ~= 0) or (dy == 0 and dx ~= 0)) then return nil, "not_facing" end
    local travel
    if dx == 0 then travel = Grid.dir_from_vector(0, dy > 0 and 1 or -1)
    else travel = Grid.dir_from_vector(dx > 0 and 1 or -1, 0) end
    local reverse = Grid.dir_opposite(travel)
    if connection_direction(source) ~= travel or connection_direction(sink) ~= reverse then return nil, "reversed" end
    local distance = underground_distance(source, sink)
    local family_max = kind == "pipe" and work.pipe and work.pipe.underground_max_distance
        or work.belt and work.belt.underground_max_distance
    local source_max = finite(source_connection.max_underground_distance, family_max)
    local sink_max = finite(sink_connection.max_underground_distance, family_max)
    if source_max ~= nil and distance > source_max + tolerance(source_max) then return nil, "range" end
    if sink_max ~= nil and distance > sink_max + tolerance(sink_max) then return nil, "range" end
    if endpoint_is_blocked(work, source) or endpoint_is_blocked(work, sink) then return nil, "blocked" end
    return {source = source, sink = sink, direction = travel, distance = distance, kind = kind}, nil
end

local function add_allocation(segment, flow_id, sink, amount)
    for _, allocation in ipairs(segment.allocations) do
        if allocation.flow_id == flow_id and allocation.sink == sink then
            allocation.rate_per_second = allocation.rate_per_second + amount
            return
        end
    end
    segment.allocations[#segment.allocations + 1] = {flow_id = flow_id, sink = sink, rate_per_second = amount}
end

local function entity_position(x, y)
    return {x = x + 0.5, y = y + 0.5}
end

--The tile a path dives on and the tile it surfaces on become one underground pair.  Both carry the segment; the
--tiles between them carry nothing, so the belt they cross keeps them.
local function append_crossing(work, demand, entry, exit_cell, amount)
    local capacity, kind = capacity_for(work, demand.flow)
    if amount > capacity + tolerance(capacity) then return false, "capacity" end
    local direction = direction_from_step(entry.x, entry.y, exit_cell.x, exit_cell.y)
    local family = kind == "pipe" and work.pipe or work.belt
    local name = (family and family.underground) or infrastructure(work, kind)
    local segment = {segment_id = "r:s:" .. tostring(#work.segments + 1), kind = kind,
        capacity_per_second = capacity, allocations = {}, flow_id = demand.flow_id, direction = direction,
        underground = true}
    local first_id, second_id = "r:" .. tostring(#work.entities + 1), "r:" .. tostring(#work.entities + 2)
    local first = {id = first_id, name = name, position = entity_position(entry.x, entry.y),
        direction = direction, dir = direction, flow_id = demand.flow_id,
        ug_role = "input", type = "input", ug_pair_id = second_id}
    local second = {id = second_id, name = name, position = entity_position(exit_cell.x, exit_cell.y),
        direction = direction, dir = direction, flow_id = demand.flow_id,
        ug_role = "output", type = "output", ug_pair_id = first_id}
    work.entities[#work.entities + 1] = first
    work.entities[#work.entities + 1] = second
    work.segments[#work.segments + 1] = segment
    work.counters.crossings_placed = work.counters.crossings_placed + 1
    work.entity_by_segment[segment.segment_id] = first
    work.segments_by_cell[coordinate_key(entry.x, entry.y)] = segment
    work.segments_by_cell[coordinate_key(exit_cell.x, exit_cell.y)] = segment
    work.underground_cells[coordinate_key(entry.x, entry.y)] = true
    work.underground_cells[coordinate_key(exit_cell.x, exit_cell.y)] = true
    add_allocation(segment, demand.flow_id, sink_key(demand.sink), amount)
    return true, nil, segment
end

local function append_normal_path(work, demand, path, amount)
    local sink = sink_key(demand.sink)
    local first_segment
    local allocated_segments = {}
    local index = 0
    while index < #path do
        index = index + 1
        local cell = path[index]
        if is_crossing_step(cell, path[index + 1]) then
            local crossed, reason, segment = append_crossing(work, demand, cell, path[index + 1], amount)
            if not crossed then return false, reason end
            first_segment = first_segment or segment
            index = index + 1
        else
        local next_cell = path[index + 1] or path[index - 1] or cell
        local direction = direction_from_step(cell.x, cell.y, next_cell.x, next_cell.y)
        if index == #path and #path > 1 then direction = direction_from_step(path[index - 1].x, path[index - 1].y, cell.x, cell.y) end
        local key = coordinate_key(cell.x, cell.y)
        local segment = work.segments_by_cell[key]
        if segment then
            local splitter_continuation = segment.splitter and key == segment.splitter_second_key
                and direction == segment.splitter_direction
            if not allocated_segments[segment.segment_id] then
                local allowed = segment_allows(segment, demand, amount)
                if not allowed then return false, "capacity" end
            end
            if segment.splitter and key == segment.splitter_second_key and not splitter_continuation then return false, "occupied" end
            if segment.direction ~= direction and not splitter_continuation then
                --An underground segment owns two coupled endpoints.  It cannot become a splitter: changing
                --the mapped first entity here would leave its partner carrying a different direction.  The
                --allocation may still share the segment, but its published pair keeps the direction it was built
                --for.  Surface belts retain their existing splitter behaviour.
                    if not segment.underground then
                        if segment.kind ~= "belt" or not (work.belt and work.belt.splitter) then return false, "occupied" end
                        if splitter_branch_allowed(work, demand, cell.x, cell.y, direction, segment) then
                            local entity = work.entity_by_segment[segment.segment_id]
                            local second_x, second_y = splitter_second_cell(cell.x, cell.y, direction)
                            local second_key = coordinate_key(second_x, second_y)
                            local side_x, side_y = second_x - cell.x, second_y - cell.y
                            entity.position = entity_position(cell.x + side_x / 2, cell.y + side_y / 2)
                            entity.name = work.belt.splitter
                            entity.splitter = true
                            entity.direction = direction
                            entity.dir = direction
                            segment.splitter = true
                            segment.splitter_direction = direction
                            segment.splitter_anchor_key = key
                            segment.splitter_second_key = second_key
                            work.segments_by_cell[segment.splitter_second_key] = segment
                        end
                    end
            end
        else
            local capacity, kind = capacity_for(work, demand.flow)
            segment = {segment_id = "r:s:" .. tostring(#work.segments + 1), kind = kind,
                capacity_per_second = capacity, allocations = {}, flow_id = demand.flow_id, direction = direction}
            local entity = {id = "r:" .. tostring(#work.entities + 1), name = infrastructure(work, kind),
                position = entity_position(cell.x, cell.y), direction = direction, dir = direction, flow_id = demand.flow_id}
            work.entities[#work.entities + 1] = entity
            work.segments[#work.segments + 1] = segment
            work.segments_by_cell[key] = segment
            work.entity_by_segment[segment.segment_id] = entity
        end
        if not allocated_segments[segment.segment_id] then
            add_allocation(segment, demand.flow_id, sink, amount)
            allocated_segments[segment.segment_id] = true
        end
        first_segment = first_segment or segment
        end
    end
    if first_segment then
        work.bindings[#work.bindings + 1] = {source_port_id = demand.source.port_id, sink_port_id = demand.sink.port_id,
            sink = sink, flow_id = demand.flow_id, segment_id = first_segment.segment_id, rate_per_second = amount}
    end
    return true
end

--The tile items go down on is the entrance, and a blueprint spells that `type = "input"`; the tile they come up
--on is `"output"`.  Transport runs from the demand's source to its sink, so the source end is the entrance.
local function append_underground(work, demand, candidate, amount)
    local capacity, kind = capacity_for(work, demand.flow)
    if amount > capacity + tolerance(capacity) then return false, "capacity" end
    local segment = {segment_id = "r:s:" .. tostring(#work.segments + 1), kind = kind,
        capacity_per_second = capacity, allocations = {}, flow_id = demand.flow_id, direction = candidate.direction}
    local first_id, second_id = "r:" .. tostring(#work.entities + 1), "r:" .. tostring(#work.entities + 2)
    local name = infrastructure(work, kind)
    if kind == "pipe" then name = (work.pipe and (work.pipe.underground or work.pipe.pipe)) or name
    else name = (work.belt and (work.belt.underground or work.belt.belt)) or name end
    local first = {id = first_id, name = name, position = entity_position(candidate.source.x, candidate.source.y),
        direction = candidate.direction, dir = candidate.direction, flow_id = demand.flow_id,
        ug_role = "input", type = "input", ug_pair_id = second_id}
    local second = {id = second_id, name = name, position = entity_position(candidate.sink.x, candidate.sink.y),
        direction = candidate.direction, dir = candidate.direction, flow_id = demand.flow_id,
        ug_role = "output", type = "output", ug_pair_id = first_id}
    work.entities[#work.entities + 1] = first
    work.entities[#work.entities + 1] = second
    work.segments[#work.segments + 1] = segment
    work.entity_by_segment[segment.segment_id] = first
    work.splitter_blocked_cells[coordinate_key(candidate.source.x, candidate.source.y)] = true
    work.splitter_blocked_cells[coordinate_key(candidate.sink.x, candidate.sink.y)] = true
    add_allocation(segment, demand.flow_id, sink_key(demand.sink), amount)
    work.bindings[#work.bindings + 1] = {source_port_id = demand.source.port_id, sink_port_id = demand.sink.port_id,
        sink = sink_key(demand.sink), flow_id = demand.flow_id, segment_id = segment.segment_id, rate_per_second = amount}
    return true
end

local function path_cell_free(work, demand, x, y, move_direction, is_target, amount, search)
    local owner = static_owner(work, x, y)
    if owner ~= nil and not is_allowed_owner(owner) then search.saw_blocked = true; return false end
    local reserved = work.port_cells and work.port_cells[coordinate_key(x, y)]
    if reserved ~= nil then
        local source_id = demand.source and demand.source.port_id
        local sink_id = demand.sink and demand.sink.port_id
        if not (reserved[source_id] or reserved[sink_id] or reserved["flow:" .. tostring(demand.flow_id)]) then
            search.saw_blocked = true
            return false
        end
    end
    local segment = work.segments_by_cell[coordinate_key(x, y)]
    if segment then
        local splitter_continuation = segment.splitter and segment.splitter_second_key == coordinate_key(x, y)
            and segment.splitter_direction == move_direction
        if segment.splitter and segment.splitter_second_key == coordinate_key(x, y) and not splitter_continuation then
            search.saw_blocked = true
            return false
        end
        if segment.flow_id ~= demand.flow_id and segment.kind == "pipe" then search.saw_fluid_mix = true end
        local allowed, reason = segment_allows(segment, demand, amount)
        if not allowed then
            if reason == "capacity" then search.saw_capacity = true end
            if reason == "occupied" then search.saw_blocked = true end
            return false
        end
        if move_direction ~= nil and segment.direction ~= move_direction then
            if not splitter_continuation and (segment.kind ~= "belt" or not (work.belt and work.belt.splitter)) then
                search.saw_blocked = true; return false
            end
            search.saw_branch = true
        end
    end
    return true
end

local function default_expansion_limit(input)
    local grid = type(input) == "table" and input.grid or nil
    local w = type(grid) == "table" and finite(grid.w, nil) or nil
    local h = type(grid) == "table" and finite(grid.h, nil) or nil
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return 100000 end
    return math.max(4096, math.floor(w * h * 16))
end

local function begin_search(work, demand, amount, order_index)
    order_index = order_index or 1
    local search = {demand = demand, amount = amount, queue = {{x = demand.source.x, y = demand.source.y}}, head = 1, tail = 1,
        visited = {[coordinate_key(demand.source.x, demand.source.y)] = true}, parent = {}, neighbor_index = 1,
        saw_capacity = false, saw_fluid_mix = false, saw_blocked = false,
        directions = DIRECTION_ORDERS[order_index], order_index = order_index}
    local source_segment = work.segments_by_cell[coordinate_key(demand.source.x, demand.source.y)]
    if source_segment then
        local allowed, reason = segment_allows(source_segment, demand, amount)
        if not allowed then
            search.saw_capacity, search.saw_fluid_mix, search.queue, search.tail = reason == "capacity", reason == "fluid_mix", {}, 0
        end
    end
    return search
end

local function reconstruct(search, target_key)
    local reversed, key = {}, target_key
    while key do
        reversed[#reversed + 1] = search.points[key]
        if key == search.source_key then break end
        key = search.parent[key]
    end
    local path = {}
    for index = #reversed, 1, -1 do path[#path + 1] = reversed[index] end
    return path
end

--Two belts that must cross cannot both stay on the surface.  A player builds an underground pair there, and so
--does the search: when the next tile in a direction is taken, it dives under and surfaces on the first free tile
--within the family's underground distance.  The tiles in between keep no segment, which is exactly what lets the
--belt that took them keep them.
local function underground_reach(work, demand)
    local family = demand.kind == "pipe" and work.pipe or work.belt
    if type(family) ~= "table" or family.underground == nil then return 0 end
    return math.max(0, math.floor(finite(family.underground_max_distance, 0)))
end

--One scratch table, reused: the probe below runs on the hot path and a fresh table per tile is pure garbage.
local PROBE = {}

local function crossing_target(work, demand, search, current, direction, amount)
    local reach = underground_reach(work, demand)
    if reach < 2 then return nil end
    local current_key = coordinate_key(current.x, current.y)
    if work.segments_by_cell[current_key] or work.underground_cells[current_key] then return nil end
    local dx, dy = Grid.dir_vector(direction)
    for distance = 2, reach do
        local middle_x, middle_y = current.x + dx * (distance - 1), current.y + dy * (distance - 1)
        if not inside_grid(work, middle_x, middle_y) then return nil end
        --A pair may not run under another pair of its own family: in the engine the two would connect to each
        --other instead of passing.
        if work.underground_cells[coordinate_key(middle_x, middle_y)] then return nil end
        --Only tiles the search cannot walk are worth diving under. The moment one of them is walkable, walking
        --it is shorter and costs no entities, so the dive stops there.
        if path_cell_free(work, demand, middle_x, middle_y, direction, false, amount, PROBE) then return nil end
        local x, y = current.x + dx * distance, current.y + dy * distance
        if not inside_grid(work, x, y) then return nil end
        local key = coordinate_key(x, y)
        if not search.visited[key] and not work.segments_by_cell[key] and not work.underground_cells[key]
            and path_cell_free(work, demand, x, y, direction, x == demand.sink.x and y == demand.sink.y, amount, search) then
            return {x = x, y = y}
        end
    end
    return nil
end

local function search_step(work, search)
    if not search.points then
        search.points = {[coordinate_key(search.demand.source.x, search.demand.source.y)] = search.queue[1]}
        search.source_key = coordinate_key(search.demand.source.x, search.demand.source.y)
    end
    if search.head > search.tail then return "failed" end
    local current = search.queue[search.head]
    local current_key = coordinate_key(current.x, current.y)
    if current.x == search.demand.sink.x and current.y == search.demand.sink.y then return reconstruct(search, current_key) end
    if search.neighbor_index > #search.directions then search.head, search.neighbor_index = search.head + 1, 1; return "continue" end
    local direction = search.directions[search.neighbor_index]
    search.neighbor_index = search.neighbor_index + 1
    local dx, dy = Grid.dir_vector(direction)
    local nx, ny = current.x + dx, current.y + dy
    local target = nx == search.demand.sink.x and ny == search.demand.sink.y
    local first = current.x == search.demand.source.x and current.y == search.demand.source.y
    if first and search.demand.source.travel_dir ~= nil and search.demand.source.travel_dir ~= direction then return "continue" end
    if target and search.demand.sink.travel_dir ~= nil and search.demand.sink.travel_dir ~= direction then return "continue" end
    local key = coordinate_key(nx, ny)
    if not search.visited[key]
        and path_cell_free(work, search.demand, nx, ny, direction, target, search.amount, search) then
        search.visited[key], search.parent[key], search.points[key] = true, current_key, {x = nx, y = ny}
        search.queue[search.tail + 1], search.tail = {x = nx, y = ny}, search.tail + 1
        return "continue"
    end
    --A port tile is an entity, never an underground entrance, so a crossing never starts on the source.
    if first then return "continue" end
    local crossing = crossing_target(work, search.demand, search, current, direction, search.amount)
    if crossing then
        local reaches_sink = crossing.x == search.demand.sink.x and crossing.y == search.demand.sink.y
        if not reaches_sink or search.demand.sink.travel_dir == nil or search.demand.sink.travel_dir == direction then
            local crossing_key = coordinate_key(crossing.x, crossing.y)
            search.visited[crossing_key], search.parent[crossing_key], search.points[crossing_key] =
                true, current_key, {x = crossing.x, y = crossing.y}
            search.queue[search.tail + 1], search.tail = {x = crossing.x, y = crossing.y}, search.tail + 1
        end
    end
    return "continue"
end

local function result_for(work)
    local result = {entities = {}, segments = {}, port_bindings = work.bindings, bindings = work.bindings}
    for _, entity in ipairs(work.entities) do
        if not entity._route_removed then result.entities[#result.entities + 1] = entity end
    end
    for _, segment in ipairs(work.segments) do
        local copy = {segment_id = segment.segment_id, kind = segment.kind,
            capacity_per_second = segment.capacity_per_second, allocations = {}}
        for _, allocation in ipairs(segment.allocations) do
            copy.allocations[#copy.allocations + 1] = {flow_id = allocation.flow_id, sink = allocation.sink,
                rate_per_second = allocation.rate_per_second}
        end
        result.segments[#result.segments + 1] = copy
    end
    return result
end

--A port is useless without the tile its transport reaches it from: an input needs the tile it is entered from,
--an output needs the tile it leaves into.  Routing one demand used to lay a belt straight across the approach
--tile of a port it does not serve, and every later demand for that port then had no path at all.  Those tiles
--are claimed by the ports that own them before any demand is routed, so another belt goes around instead.  A
--belt already carrying the same flow may still pass: one trunk feeding two consumers of one item is the shape
--the allocation rules are written for, and claiming against it would forbid sharing outright.
local function reserve_port_cells(work)
    local reserved = {}
    local function claim(x, y, endpoint)
        if endpoint.port_id == nil or not inside_grid(work, x, y) then return end
        local key = coordinate_key(x, y)
        reserved[key] = reserved[key] or {}
        reserved[key][endpoint.port_id] = true
        if endpoint.flow_id ~= nil then reserved[key]["flow:" .. tostring(endpoint.flow_id)] = true end
    end
    local function claim_endpoint(endpoint)
        if type(endpoint) ~= "table" or endpoint.x == nil or endpoint.y == nil then return end
        claim(endpoint.x, endpoint.y, endpoint)
        local dx, dy = Grid.dir_vector(endpoint.travel_dir or Grid.NORTH)
        if endpoint.role == "in" then claim(endpoint.x - dx, endpoint.y - dy, endpoint)
        else claim(endpoint.x + dx, endpoint.y + dy, endpoint) end
    end
    for _, by_role in pairs(work.endpoint_index or {}) do
        for _, role in ipairs({"in", "out"}) do
            for _, endpoint in ipairs(by_role[role] or {}) do claim_endpoint(endpoint) end
        end
    end
    for _, endpoint in ipairs(work.perimeter or {}) do claim_endpoint(endpoint) end
    return reserved
end

local function normalize_input(input)
    input = input or {}
    local placements, blocks = map_placements(input), map_blocks(input)
    local work = {
        input_belt_capacity = finite(input.belt_capacity), input_pipe_capacity = finite(input.pipe_capacity),
        input_belt_name = input.belt_name, input_pipe_name = input.pipe_name,
        belt = input.belt or (input.catalog and input.catalog.belt) or {},
        pipe = input.pipe or (input.catalog and input.catalog.pipe) or {},
        grid = copy_grid(input), obstacles = {}, endpoint_index = {}, perimeter = {},
        entities = {}, segments = {}, bindings = {}, segments_by_cell = {}, entity_by_segment = {},
        underground_cells = {}, splitter_blocked_cells = {}, counters = new_counters(), attempt_generation = 0,
        --A path search visits cells, so the whole routing run is bounded by the grid it runs on. The old default
        --of one million let a single demand burn 1.2 million expansions on a 54 by 54 grid (2916 cells) without
        --finishing, which is a hang the player sees as a frozen Generate. Sixteen visits per cell is generous for
        --four directions and both transport kinds, and a hopeless search now fails fast enough for the search to
        --try the next ordering instead of the next hour.
        max_expansions = finite(input.limits and input.limits.max_expansions,
            finite(input.max_expansions, default_expansion_limit(input))), expansions = 0,
    }
    for _, block in ipairs(blocks) do
        local placement = placement_for(block, placements)
        block._placement, block._w, block._h = placement, dimension_for(block, placement, "w", 1), dimension_for(block, placement, "h", 1)
        for _, port in ipairs(block.ports or block.block_ports or {}) do
            local endpoint = normalize_endpoint(block, placement, port, input.catalog or {}, work)
            if endpoint and endpoint.flow_id then
                work.endpoint_index[endpoint.flow_id] = work.endpoint_index[endpoint.flow_id] or {["in"] = {}, ["out"] = {}}
                work.endpoint_index[endpoint.flow_id][endpoint.role][#work.endpoint_index[endpoint.flow_id][endpoint.role] + 1] = endpoint
            end
        end
    end
    add_input_obstacles(work, input, blocks)
    for _, port in ipairs(perimeter_entries(input)) do
        local endpoint = normalize_perimeter(port)
        if endpoint and endpoint.flow_id then work.perimeter[#work.perimeter + 1] = endpoint end
    end
    work.flows = flow_list(input)
    work.demands = build_demands(work, work.flows)
    work.demand_order, work.demands_by_key = {}, {}
    for index, demand in ipairs(work.demands) do
        demand.order_key = index
        work.demand_order[index] = demand
        work.demands_by_key[index] = demand
    end
    work.port_cells = reserve_port_cells(work)
    return work
end

--A demand that finds no path is often only the victim of the order it was routed in: the belts already on the
--grid boxed its port in.  Instead of losing the whole candidate, the run rips every segment out and starts over
--with that demand first.  Each demand may claim the front once, so the retries are bounded by the number of
--demands and the order the run ends on is still a function of its input.
local function restart_with_priority(state, work, demand)
    if type(demand) ~= "table" or demand.order_key == nil then return false end
    work.priority = work.priority or {}
    for _, key in ipairs(work.priority) do
        if key == demand.order_key then return false end
    end
    table.insert(work.priority, 1, demand.order_key)
    local claimed, ordered = {}, {}
    for _, key in ipairs(work.priority) do claimed[key] = true end
    for _, key in ipairs(work.priority) do ordered[#ordered + 1] = work.demands_by_key[key] end
    for _, entry in ipairs(work.demand_order) do
        if not claimed[entry.order_key] then ordered[#ordered + 1] = entry end
    end
    work.counters.restarts = work.counters.restarts + 1
    work.demands = ordered
    for _, entry in ipairs(ordered) do entry.remaining = entry.amount end
    work.entities, work.segments, work.bindings = {}, {}, {}
    work.segments_by_cell, work.entity_by_segment, work.underground_cells = {}, {}, {}
    work.splitter_blocked_cells = {}
    work.attempt_generation, work.current = work.attempt_generation + 1, nil
    state.cursor.demand_index, state.progress.done_units = 1, 0
    state.progress.phase = "routing"
    return true
end

local function clear_route_work(work)
    work.entities, work.segments, work.bindings = {}, {}, {}
    work.segments_by_cell, work.entity_by_segment, work.underground_cells = {}, {}, {}
    work.splitter_blocked_cells = {}
    work.current = nil
end

local function fail_demand(state, work, demand, code, detail)
    if code ~= "BP_R_EXPANSIONS" and restart_with_priority(state, work, demand) then return false end
    local record = {code = code, flow_id = demand and demand.flow_id}
    if detail ~= nil then record.detail = detail end
    state.errors, state.done, state.ok = {record}, true, false
    state.progress.phase = "failed"
    return true
end

function Route.begin(input)
    local work = normalize_input(input or {})
    return {done = false, ok = nil, cursor = {flow_index = 1, demand_index = 1, phase = "routing"},
        progress = {phase = "routing", done_units = 0, total_units = #work.demands},
        counters = work.counters, work = work}
end

function Route.cancel(state)
    if type(state) ~= "table" or state.done then return state end
    clear_route_work(state.work)
    state.cancelled, state.done, state.ok, state.result = true, true, false, nil
    state.errors = {{code = "BP_FAIL_CANCELLED"}}
    state.progress.phase = "cancelled"
    return state
end

function Route.step(state, budget)
    if state.done then return state end
    if state.cancelled then return Route.cancel(state) end
    budget = budget or {ops = 1}
    local ops = finite(budget.ops, 1)
    if ops < 0 then ops = 0 end
    local work = state.work
    if work.initial_error then
        if ops > 0 then
            state.errors, state.done, state.ok = {work.initial_error}, true, false
            state.progress.phase, ops = "failed", ops - 1
        end
        budget.ops = ops
        return state
    end
    while ops > 0 and not state.done do
        local demand = work.demands[state.cursor.demand_index]
        if not demand then
            state.result, state.done, state.ok = result_for(work), true, true
            state.progress.phase = "done"
            break
        end
        if demand.remaining <= tolerance(demand.remaining) then
            state.cursor.demand_index, state.progress.done_units = state.cursor.demand_index + 1, state.progress.done_units + 1
        else
            if demand._attempt_generation ~= work.attempt_generation then
                demand._attempt_generation = work.attempt_generation
                work.counters.demands_attempted = work.counters.demands_attempted + 1
            end
            local capacity, kind = capacity_for(work, demand.flow)
            local amount = math.min(demand.remaining, capacity)
            if amount <= 0 then
                ops = ops - 1
                if fail_demand(state, work, demand, "BP_R_CAPACITY") then break end
            else
            demand.kind = kind
            if not work.current then
                if not demand.source or not demand.sink or endpoint_is_blocked(work, demand.source) or endpoint_is_blocked(work, demand.sink) then
                    ops = ops - 1
                    if fail_demand(state, work, demand, "BP_R_PORT_BLOCKED",
                        blocked_port_detail(work, demand.source, demand.sink)) then break end
                else
                local candidate, underground_reason = underground_candidate(demand, kind, work)
                if candidate then
                    local placed, reason = append_underground(work, demand, candidate, amount)
                    ops = ops - 1
                    if not placed then
                        fail_demand(state, work, demand, reason == "capacity" and "BP_R_CAPACITY" or "BP_R_NO_PATH")
                    else demand.remaining = demand.remaining - amount end
                elseif underground_reason ~= "not_requested" then
                    local code = underground_reason == "blocked" and "BP_R_PORT_BLOCKED" or "BP_R_NO_PATH"
                    ops = ops - 1
                    fail_demand(state, work, demand, code,
                        code == "BP_R_PORT_BLOCKED" and blocked_port_detail(work, demand.source, demand.sink) or nil)
                else
                    work.current = begin_search(work, demand, amount)
                end
                end
            else
                if work.expansions >= work.max_expansions then
                    work.current, ops = nil, ops - 1
                    abandon_search(work, "expansions")
                    if fail_demand(state, work, demand, "BP_R_EXPANSIONS") then break end
                else
                work.expansions = work.expansions + 1
                work.counters.expansions = work.counters.expansions + 1
                local outcome = search_step(work, work.current)
                ops = ops - 1
                if type(outcome) == "table" then
                    local placed, reason = append_normal_path(work, demand, outcome, amount)
                    work.current = nil
                    if not placed then
                        fail_demand(state, work, demand, reason == "capacity" and "BP_R_CAPACITY" or "BP_R_NO_PATH")
                    else demand.remaining = demand.remaining - amount end
                elseif outcome == "failed" then
                    local search = work.current
                    local reason = search.saw_fluid_mix and "fluid_mix"
                        or (search.saw_capacity and "capacity" or (search.saw_blocked and "blocked" or "no_path"))
                    abandon_search(work, reason)
                    if search.saw_blocked and not search.saw_capacity and not search.saw_fluid_mix
                        and search.order_index < #DIRECTION_ORDERS then
                        work.current = begin_search(work, demand, amount, search.order_index + 1)
                    else
                        local code = search.saw_fluid_mix and "BP_R_FLUID_MIX" or (search.saw_capacity and "BP_R_CAPACITY" or "BP_R_NO_PATH")
                        work.current = nil
                        fail_demand(state, work, demand, code)
                    end
                end
                end
            end
            end
        end
    end
    budget.ops = ops
    return state
end

return Route
