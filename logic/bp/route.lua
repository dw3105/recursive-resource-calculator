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
--The search was Dijkstra: cost only, no estimate of what is left.  One tile of straight belt costs 1, so
--1 per remaining tile is the ordinary per-tile price and the estimate leads the frontier at the sink.
--Measured 2026-09-22 on legalcopilot-dev against tests/fixtures/routing/player_chain_first_candidate.lua,
--with the whole route family green on both interpreters at each step:
--
--  no estimate   68672 ops   85 belts,  6 underground, 0 splitter
--  0.2 per tile  61817 ops   85 belts,  6 underground, 0 splitter
--  1   per tile  51638 ops   85 belts,  6 underground, 0 splitter   <- taken
--  2   per tile  43784 ops   79 belts, 12 underground, 1 splitter   <- refused, it buys ops with geometry
--
--The remaining cost is NOT here.  35 searches run on this candidate and the expensive ones are the searches
--that FAIL: a sink fenced in by an earlier demand exhausts its whole reachable set whatever order the
--frontier is opened in, and no estimate shortens that.  item/cable 10:8 -> 10:5 alone spends about 52800
--over six of them.
local HEURISTIC_PER_TILE = 1
--Contract 28.8.  A trunk tile that is already the sink's own port tile, entered in a heading the port
--did not ask for, is the LAST answer the search should take: high enough that any real approach wins,
--finite so a sink with no other approach is still served.
local SEEDED_SINK_LAST = 0
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
        discarded_geometry = 0,
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

local function next_entity_id(work)
    work.entity_serial = (work.entity_serial or #work.entities) + 1
    return "r:" .. tostring(work.entity_serial)
end

local function next_segment_id(work)
    work.segment_serial = (work.segment_serial or #work.segments) + 1
    return "r:s:" .. tostring(work.segment_serial)
end

local function coordinate_from_key(key)
    local x, y = string.match(key, "^([^:]+):([^:]+)$")
    if x == nil then return nil end
    return tonumber(x), tonumber(y)
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
    --Placed x/y are the coordinates validation reads. A position object may be a stale source-frame helper,
    --so it must not override the materialized tile when both representations are present.
    local x, y = finite(value.x), finite(value.y)
    if x == nil or y == nil then
        local position = value.position
        x, y = finite(position and position.x), finite(position and position.y)
    end
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
    local point = ((port.x ~= nil or port.y ~= nil) and port) or port.position or nil
    local x, y = point_from(point)
    if x ~= nil and y ~= nil and (work == nil or inside_grid(work, x, y)) then return x, y end
    local frame = block
    if port._block_w ~= nil and port._block_h ~= nil then frame = {w = port._block_w, h = port._block_h} end
    local placed = Grid.place_port(frame, placement, port)
    --A mirrored coordinate is not an attachment.  Moving it to the opposite block edge without a materialized
    --connector would make the router claim a transfer the real inserter/fluid connection never made.  Preserve the
    --physical coordinate and let endpoint_is_blocked report the named boundary failure instead.
    return placed.x, placed.y
end

local function endpoint_direction(port, placement, role)
    local direction = port.travel_dir
    if direction == nil and port.dir ~= nil then direction = port.dir end
    if direction == nil then
        local normal = port.normal_dir or Grid.NORTH
        direction = role == "in" and normal or Grid.dir_opposite(normal)
    end
    if port.x ~= nil or port.y ~= nil then return direction end
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
    --A rotated materialization carries source-frame attach geometry and a validator-facing travel direction.
    --Traversal still uses the placed direction above, but the validator also protects the approach implied by
    --this published direction. Keep that second direction private to reservation construction.
    if port.x == nil and port.y == nil and port._block_w ~= nil then
        endpoint.validator_travel_dir = port.travel_dir or port.dir or port.normal_dir
    end
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

local function prioritized_candidates(candidates, anchor)
    if type(anchor) ~= "table" or #candidates < 2 then return candidates end
    local ranked = {}
    for index, endpoint in ipairs(candidates) do
        ranked[#ranked + 1] = {endpoint = endpoint, index = index,
            distance = math.abs(endpoint.x - anchor.x) + math.abs(endpoint.y - anchor.y)}
    end
    table.sort(ranked, function(left, right)
        if left.distance ~= right.distance then return left.distance < right.distance end
        if tostring(left.endpoint.port_id) ~= tostring(right.endpoint.port_id) then
            return tostring(left.endpoint.port_id) < tostring(right.endpoint.port_id)
        end
        return left.index < right.index
    end)
    local result = {}
    for index, entry in ipairs(ranked) do result[index] = entry.endpoint end
    return result
end

local function perimeter_for(perimeter, flow_id, role, port_id)
    for _, endpoint in ipairs(perimeter) do
        if (port_id == nil or endpoint.port_id == port_id)
            and endpoint.flow_id == flow_id and endpoint.role == role then return endpoint end
    end
    return nil
end

local function perimeter_candidates(perimeter, flow_id, role, port_id)
    local result = {}
    for _, endpoint in ipairs(perimeter) do
        if (port_id == nil or endpoint.port_id == port_id)
            and endpoint.flow_id == flow_id and endpoint.role == role then
            result[#result + 1] = endpoint
        end
    end
    return result
end

local function demand_endpoint_candidates(work, flow_id, role, entry)
    local step_id = step_id_of(entry)
    local port_id = entry and entry.port_id
    if step_id == "$external" then
        return perimeter_candidates(work.perimeter, flow_id, role, port_id)
    end
    local result = {}
    for _, endpoint in ipairs(endpoint_candidates(work.endpoint_index, flow_id, role, step_id)) do
        result[#result + 1] = endpoint
    end
    return result
end

--Pairing is a routing decision too.  This small static flood fill is deliberately run before materialized
--segments exist: it prices the obstacle-aware route that each producer/consumer pair is asking for, rather than
--letting input list order choose the first trunk.  The real Dijkstra below still makes the final decision with
--capacity, bends, crossings and sharing in view.
local function pairing_route_cost(work, source, sink)
    if not source or not sink then return math.huge end
    local grid = work.grid or {}
    local function inside(x, y)
        return (grid.w == nil or (x >= 0 and y >= 0 and x < grid.w and y < grid.h))
    end
    local function open(x, y)
        if (x == source.x and y == source.y) or (x == sink.x and y == sink.y) then return true end
        local owner = work.obstacles[coordinate_key(x, y)]
        if owner ~= nil and owner ~= Grid.RESERVED.corridor and owner ~= Grid.RESERVED.port then return false end
        return indexed_cell(grid, x, y) == nil
    end
    local start = coordinate_key(source.x, source.y)
    local queue, head = {{x = source.x, y = source.y, distance = 0}}, 1
    local seen = {[start] = true}
    while queue[head] do
        local current = queue[head]
        head = head + 1
        if current.x == sink.x and current.y == sink.y then return current.distance end
        for _, direction in ipairs(DIRECTIONS) do
            local dx, dy = Grid.dir_vector(direction)
            local x, y = current.x + dx, current.y + dy
            local key = coordinate_key(x, y)
            if inside(x, y) and not seen[key] and open(x, y) then
                seen[key] = true
                queue[#queue + 1] = {x = x, y = y, distance = current.distance + 1}
            end
        end
    end
    return math.huge
end

local function candidate_first(candidates, chosen)
    local result = {}
    if chosen then result[#result + 1] = chosen end
    for _, endpoint in ipairs(candidates or {}) do
        if endpoint ~= chosen then result[#result + 1] = endpoint end
    end
    return result
end

local function source_endpoint(work, flow_id, entry)
    local role = step_id_of(entry) == "$external" and "in" or "out"
    return demand_endpoint_candidates(work, flow_id, role, entry)[1]
end

local function target_endpoint(work, flow_id, entry)
    local role = step_id_of(entry) == "$external" and "out" or "in"
    return demand_endpoint_candidates(work, flow_id, role, entry)[1]
end

--Contract 28.1 and 28.3: one hand may serve two item flows that ride one belt, using both belt lanes, which
--is how the player's own factory gets 22 inserters where ours plans 26.  The switch is OFF here and stays off
--for every lane: three lanes build three halves of one feature behind it -- groups pairs the hands, route shares the belt, validate witnesses per flow -- and integration
--flips all three together, because that is the only point where the halves meet.  Golden tests therefore keep
--passing at default configuration while the halves are being built.
local multi_flow_hands = false

--A route may reuse an existing belt only when the existing run can become a real splitter at the
--mismatch.  Keep this switch separate from the multi-flow hand work: same-flow trunk sharing is
--the default route behaviour and is the geometry rule this lane closes.
local share_trunk = true

local per_port_demands = true

local function append_port_demands(work, demands, flow_id, role, entry, share, label)
    local candidates = demand_endpoint_candidates(work, flow_id, role, entry)
    if #candidates == 0 then
        if share > tolerance(share) then
            local step_id = step_id_of(entry)
            work.initial_error = {code = "BP_R_PORT_BLOCKED", flow_id = flow_id, role = role,
                step_id = step_id, detail = label .. " plan entry has no matching port for step " .. tostring(step_id)}
        end
        return
    end

    --A positive rate on every endpoint is an explicit weighting.  A zero rate is the marker used by the
    --materializer for an anchored hand that still needs routing, so the presence of any such endpoint makes
    --the whole plan entry an equal fan-out.  That keeps a synthetic zero from turning a real hand into a
    --zero-demand alias.
    local weighted, total_rate = true, 0
    for _, endpoint in ipairs(candidates) do
        local rate = finite(endpoint.rate_per_second, 0)
        if rate <= tolerance(rate) then weighted = false end
        total_rate = total_rate + math.max(0, rate)
    end
    if total_rate <= tolerance(total_rate) then weighted = false end

    local port_count = #candidates
    for _, endpoint in ipairs(candidates) do
        local amount = weighted and share * endpoint.rate_per_second / total_rate or share / port_count
        if amount <= tolerance(amount) then
            work.initial_error = {code = "BP_R_PORT_BLOCKED", flow_id = flow_id, role = role,
                step_id = endpoint.step_id, port_id = endpoint.port_id,
                detail = label .. " port has no demand: " .. tostring(endpoint.port_id)}
            return
        end
        demands[#demands + 1] = {endpoint = endpoint, candidates = {endpoint}, remaining = amount}
    end
end

local function build_demands(work, flows)
    local demands = {}
    for _, flow in ipairs(flows) do
        local id = flow_id_of(flow)
        if id then
            local producers, consumers = {}, {}
            if per_port_demands then
                for _, entry in ipairs(flow.producers or {}) do
                    local role = step_id_of(entry) == "$external" and "in" or "out"
                    append_port_demands(work, producers, id, role, entry, share_of(entry), "producer")
                end
                for _, entry in ipairs(flow.consumers or {}) do
                    local role = step_id_of(entry) == "$external" and "out" or "in"
                    append_port_demands(work, consumers, id, role, entry, share_of(entry), "consumer")
                end
            else
                for _, entry in ipairs(flow.producers or {}) do
                    local role = step_id_of(entry) == "$external" and "in" or "out"
                    local candidates = demand_endpoint_candidates(work, id, role, entry)
                    producers[#producers + 1] = {endpoint = candidates[1], candidates = candidates,
                        remaining = share_of(entry)}
                end
                for _, entry in ipairs(flow.consumers or {}) do
                    local role = step_id_of(entry) == "$external" and "out" or "in"
                    local candidates = demand_endpoint_candidates(work, id, role, entry)
                    consumers[#consumers + 1] = {endpoint = candidates[1], candidates = candidates,
                        remaining = share_of(entry)}
                end
            end
            if #producers == 0 and #consumers == 0 then
                for _, endpoint in ipairs(work.endpoint_index[id] and work.endpoint_index[id]["out"] or {}) do
                    producers[#producers + 1] = {endpoint = endpoint, candidates = {endpoint},
                        remaining = endpoint.rate_per_second}
                end
                for _, endpoint in ipairs(work.endpoint_index[id] and work.endpoint_index[id]["in"] or {}) do
                    consumers[#consumers + 1] = {endpoint = endpoint, candidates = {endpoint},
                        remaining = endpoint.rate_per_second}
                end
            end
            --Select the next pair by an obstacle-aware route estimate.  Ties use stable endpoint ids and larger
            --available flow first, which makes a high-capacity/farther trunk exist before its nearby branches.
            while true do
                local best
                for producer_index, producer in ipairs(producers) do
                    if producer.endpoint and producer.remaining > tolerance(producer.remaining) then
                        for consumer_index, consumer in ipairs(consumers) do
                            if consumer.endpoint and consumer.remaining > tolerance(consumer.remaining) then
                                local route_cost = math.huge
                                local chosen_source, chosen_sink
                                for _, source_candidate in ipairs(producer.candidates or {}) do
                                    for _, sink_candidate in ipairs(consumer.candidates or {}) do
                                        local candidate_cost = pairing_route_cost(work, source_candidate, sink_candidate)
                                        if candidate_cost < route_cost then
                                            route_cost, chosen_source, chosen_sink = candidate_cost, source_candidate, sink_candidate
                                        end
                                    end
                                end
                                chosen_source, chosen_sink = chosen_source or producer.endpoint, chosen_sink or consumer.endpoint
                                local amount = math.min(producer.remaining, consumer.remaining)
                                local flow_capacity = capacity_for(work, flow)
                                local score = route_cost - math.min(amount, flow_capacity) * 1e-6
                                local entry = {producer = producer, consumer = consumer, producer_index = producer_index,
                                    consumer_index = consumer_index, source = chosen_source, sink = chosen_sink,
                                    route_cost = route_cost, score = score, amount = amount}
                                if not best or entry.score < best.score
                                    or (entry.score == best.score and tostring(entry.source.port_id) < tostring(best.source.port_id))
                                    or (entry.score == best.score and tostring(entry.source.port_id) == tostring(best.source.port_id)
                                        and tostring(entry.sink.port_id) < tostring(best.sink.port_id)) then
                                    best = entry
                                end
                            end
                        end
                    end
                end
                if not best or best.amount <= tolerance(best.amount) then break end
                local source_candidates = candidate_first(prioritized_candidates(best.producer.candidates, best.sink), best.source)
                local sink_candidates = candidate_first(prioritized_candidates(best.consumer.candidates, best.source), best.sink)
                demands[#demands + 1] = {flow = flow, flow_id = id, source = best.source, sink = best.sink,
                    source_candidates = source_candidates, sink_candidates = sink_candidates,
                    source_index = 1, sink_index = 1, amount = best.amount, remaining = best.amount,
                    pairing_cost = best.route_cost}
                best.producer.remaining = best.producer.remaining - best.amount
                best.consumer.remaining = best.consumer.remaining - best.amount
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
    --The pairing loop above deliberately keeps its existing cost and stable endpoint tie-breaks.  Once those
    --pairs are materialized, route the expensive spans first: a short branch laid across a long cross-block
    --trunk can fence that trunk in, while the reverse order lets the unchanged splitter/underground search
    --share the trunk and attach its local branches.  The original append order is the deterministic tie-break.
    --
    --This sort is measured, in both directions, on legalcopilot-dev 2026-09-22, on the player's real captured
    --sheet at 5,000,000 ops with 3 candidates reaching `validate` either way:
    --
    --  with the sort     853 BP_V_TRANSPORT_UNUSED   63 BP_V_ROUTE_DISCONTINUOUS
    --  without it        949                         67
    --
    --So removing it makes the product WORSE, and it is kept for that reason and no other.  It also costs real
    --geometry: with it, tests/test_route_footprints.lua is 0 of 6 and tests/test_route_budget.lua is 6 of 8,
    --and with it removed both are whole while tests/test_bindings_per_hand.lua stays 8 of 8 either way.
    --Do not delete these lines to turn those two files green: that trade was measured and refused.  Order is
    --load-bearing here only because a refused splitter footprint is still committed (route.lua:1042 has no
    --`else`) and because two demands of one flow lay two runs instead of sharing a trunk.  Contract 28.5,
    --28.7 and 28.8 remove the dependence on order; until they land, the sort stays.
    for index, demand in ipairs(demands) do demand._build_order = index end
    table.sort(demands, function(left, right)
        if left.pairing_cost ~= right.pairing_cost then return left.pairing_cost > right.pairing_cost end
        return left._build_order < right._build_order
    end)
    return demands
end

local function segment_total(segment)
    local total = 0
    for _, allocation in ipairs(segment.allocations or {}) do total = total + allocation.rate_per_second end
    return total
end

local function segment_flow_count(segment)
    local count = 0
    for _, present in pairs(segment.flow_ids or {}) do
        if present then count = count + 1 end
    end
    if count == 0 and segment.flow_id ~= nil then return 1 end
    return count
end

local function segment_has_flow(segment, flow_id)
    return segment.flow_id == flow_id or (segment.flow_ids and segment.flow_ids[flow_id] == true)
end

local function register_segment_flow(segment, flow_id)
    segment.flow_ids = segment.flow_ids or {}
    segment.flow_ids[flow_id] = true
end

local function segment_allows(segment, demand, amount)
    if not segment then return true end
    if segment.kind ~= demand.kind then return false, "occupied" end
    local same_flow = segment_has_flow(segment, demand.flow_id)
    if not same_flow then
        if segment.kind == "pipe" then return false, "fluid_mix" end
        if not multi_flow_hands or segment_flow_count(segment) >= 2 then return false, "occupied" end
    elseif not share_trunk then
        return false, "occupied"
    end
    if segment_total(segment) + amount > segment.capacity_per_second + tolerance(segment.capacity_per_second) then return false, "capacity" end
    return true
end

local function static_owner(work, x, y)
    local owner = work.obstacles[coordinate_key(x, y)]
    if owner ~= nil then return owner end
    return indexed_cell(work.grid, x, y)
end

local function endpoint_reservation_conflict(work, endpoint)
    if endpoint.validator_travel_dir == nil then return false end
    local reserved = work.port_cells and work.port_cells[coordinate_key(endpoint.x, endpoint.y)]
    if reserved == nil then return false end
    for port_id, _ in pairs(reserved._port_owners or {}) do
        if port_id ~= endpoint.port_id then return true end
    end
    return false
end

local function is_allowed_owner(owner)
    return owner == nil or owner == Grid.RESERVED.corridor or owner == Grid.RESERVED.port
end

local function endpoint_is_blocked(work, endpoint)
    if not endpoint then return true end
    local owner = static_owner(work, endpoint.x, endpoint.y)
    return (owner ~= nil and not is_allowed_owner(owner)) or endpoint_reservation_conflict(work, endpoint)
end

--A splitter's anchor is the tile where the existing belt was found.  Its other tile is one step in the direction
--the splitter carries transport, not one step in a fixed north/east/west order.  Keep the footprint in the same
--cell index used by path search so a later branch sees the second tile as occupied before it mutates any entity.
local function splitter_second_cell(x, y, direction)
    local side = Grid.rotate_dir(Grid.EAST, direction)
    local dx, dy = Grid.dir_vector(side)
    if dx == nil or dy == nil then return nil, nil end
    return x + dx, y + dy
end

local function splitter_can_absorb(segment)
    return segment ~= nil and segment.kind == "belt" and not segment.underground and not segment.splitter
end

local function merged_segment_total(left, right)
    local rates = {}
    for _, allocation in ipairs(left and left.allocations or {}) do
        local key = tostring(allocation.flow_id) .. "\0" .. tostring(allocation.sink)
        rates[key] = math.max(rates[key] or 0, allocation.rate_per_second)
    end
    for _, allocation in ipairs(right and right.allocations or {}) do
        local key = tostring(allocation.flow_id) .. "\0" .. tostring(allocation.sink)
        rates[key] = math.max(rates[key] or 0, allocation.rate_per_second)
    end
    local total = 0
    for _, rate in pairs(rates) do total = total + rate end
    return total
end

local function splitter_cell_allowed(work, demand, x, y, segment, search)
    local function blocked(reason)
        if search then search.saw_blocked = true end
        work.last_route_rejection = work.last_route_rejection or {}
        return false
    end
    if not inside_grid(work, x, y) then return blocked("outside") end
    local owner = static_owner(work, x, y)
    if owner ~= nil and not is_allowed_owner(owner) then return blocked("owner") end
    local reserved = work.port_cells and work.port_cells[coordinate_key(x, y)]
    if reserved ~= nil then
        local source_id = demand.source and demand.source.port_id
        local sink_id = demand.sink and demand.sink.port_id
        if not (reserved[source_id] or reserved[sink_id] or reserved["flow:" .. tostring(demand.flow_id)]) then
            return blocked("reserved")
        end
    end
    if work.splitter_blocked_cells[coordinate_key(x, y)] then return blocked("underground") end
    --The published splitter box is wider than its anchor/side index.  Check the adjacent cells that the
    --materialized footprint covers as well, so a reserved underground endpoint cannot be hidden just outside
    --the logical second tile.
    for _, offset in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {-1, 1}, {1, -1}, {1, 1}}) do
        if work.splitter_blocked_cells[coordinate_key(x + offset[1], y + offset[2])] then
            return blocked("underground")
        end
    end
    local occupant = work.segments_by_cell[coordinate_key(x, y)]
    if occupant ~= nil and occupant ~= segment then
        local same_flow = segment_has_flow(occupant, demand.flow_id)
        local compatible_flow = same_flow or (multi_flow_hands and occupant.kind == "belt"
            and segment_flow_count(occupant) < 2)
        local combined_capacity = merged_segment_total(segment, occupant)
        if occupant.kind ~= "belt" or occupant.underground or occupant.splitter
            or not compatible_flow
            or combined_capacity > segment.capacity_per_second + tolerance(segment.capacity_per_second) then
            return blocked("occupant")
        end
    end
    return true
end

local add_allocation

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

local function terminal_splitter_refused(work, x, y, segment)
    if not splitter_can_absorb(segment) then return false end
    local second_x, second_y = splitter_second_cell(x, y, segment.direction)
    return second_x ~= nil and work.splitter_blocked_cells[coordinate_key(second_x, second_y)] == true
end

--A splitter replaces the two one-tile belts in its footprint.  When the side tile is already part of the
--same-flow trunk, fold that segment into the anchor before publishing the splitter; leaving the old segment
--in the graph would make the physical footprint overlap and would give the old binding a stale segment id.
local function merge_splitter_footprint(work, segment, second_key, demand)
    local occupant = work.segments_by_cell[second_key]
    if occupant == nil or occupant == segment then return segment end
    if occupant.kind ~= "belt" or occupant.underground or occupant.splitter then return nil end
    local same_flow = segment_has_flow(occupant, demand.flow_id)
    local compatible_flow = same_flow or (multi_flow_hands and segment_flow_count(occupant) < 2)
    if not compatible_flow or merged_segment_total(segment, occupant)
        > segment.capacity_per_second + tolerance(segment.capacity_per_second) then return nil end

    for flow_id, present in pairs(occupant.flow_ids or {}) do
        if present then register_segment_flow(segment, flow_id) end
    end
    if occupant.flow_id ~= nil then register_segment_flow(segment, occupant.flow_id) end
    for _, allocation in ipairs(occupant.allocations or {}) do
        local existing
        for _, current in ipairs(segment.allocations or {}) do
            if current.flow_id == allocation.flow_id and current.sink == allocation.sink then existing = current; break end
        end
        if existing then existing.rate_per_second = math.max(existing.rate_per_second, allocation.rate_per_second)
        else add_allocation(segment, allocation.flow_id, allocation.sink, allocation.rate_per_second) end
    end
    for key, mapped in pairs(work.segments_by_cell) do
        if mapped == occupant then work.segments_by_cell[key] = segment end
    end
    for _, binding in ipairs(work.bindings or {}) do
        if binding.segment_id == occupant.segment_id then binding.segment_id = segment.segment_id end
    end
    local old_entity = work.entity_by_segment[occupant.segment_id]
    work.entity_by_segment[occupant.segment_id] = nil
    if old_entity then
        for index = #work.entities, 1, -1 do
            if work.entities[index] == old_entity then table.remove(work.entities, index); break end
        end
    end
    for index = #work.segments, 1, -1 do
        if work.segments[index] == occupant then table.remove(work.segments, index); break end
    end
    return segment
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

add_allocation = function(segment, flow_id, sink, amount)
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
    local segment = {segment_id = next_segment_id(work), kind = kind,
        capacity_per_second = capacity, allocations = {}, flow_id = demand.flow_id, direction = direction,
        underground = true, length = underground_distance(entry, exit_cell),
        underground_entry_key = coordinate_key(entry.x, entry.y), underground_exit_key = coordinate_key(exit_cell.x, exit_cell.y),
        underground_entry_x = entry.x, underground_entry_y = entry.y,
        underground_exit_x = exit_cell.x, underground_exit_y = exit_cell.y}
    local first_id, second_id = next_entity_id(work), next_entity_id(work)
    local paired_exit_direction = kind == "pipe" and Grid.dir_opposite(direction) or direction
    local first = {id = first_id, name = name, position = entity_position(entry.x, entry.y),
        direction = direction, dir = direction, flow_id = demand.flow_id,
        ug_role = "input", ug_pair_id = second_id, segment_id = segment.segment_id}
    local second = {id = second_id, name = name, position = entity_position(exit_cell.x, exit_cell.y),
        direction = paired_exit_direction, dir = paired_exit_direction, flow_id = demand.flow_id,
        ug_role = "output", ug_pair_id = first_id, segment_id = segment.segment_id}
    if kind ~= "pipe" then first.type, second.type = "input", "output" end
    work.entities[#work.entities + 1] = first
    work.entities[#work.entities + 1] = second
    work.segments[#work.segments + 1] = segment
    work.counters.crossings_placed = work.counters.crossings_placed + 1
    work.entity_by_segment[segment.segment_id] = first
    work.segments_by_cell[coordinate_key(entry.x, entry.y)] = segment
    work.segments_by_cell[coordinate_key(exit_cell.x, exit_cell.y)] = segment
    work.underground_cells[coordinate_key(entry.x, entry.y)] = true
    work.underground_cells[coordinate_key(exit_cell.x, exit_cell.y)] = true
    register_segment_flow(segment, demand.flow_id)
    add_allocation(segment, demand.flow_id, sink_key(demand.sink), amount)
    return true, nil, segment
end

--Appending is the commit point for a complete route.  Keep a cheap structural checkpoint around it so a
--defensive validation failure (capacity, a splitter footprint, or a late crossing conflict) cannot leave a
--successful prefix in the working graph.
local function route_snapshot(work)
    local entity_serial, segment_serial = work.entity_serial, work.segment_serial
    local entities, entity_by_id = {}, {}
    for index, entity in ipairs(work.entities) do
        local copy = {}
        for key, value in pairs(entity) do
            if key == "position" and type(value) == "table" then copy[key] = {x = value.x, y = value.y}
            else copy[key] = value end
        end
        entities[index], entity_by_id[tostring(entity.id)] = copy, copy
    end
    local segments, segment_by_id = {}, {}
    for index, segment in ipairs(work.segments) do
        local copy = {}
        for key, value in pairs(segment) do
            if key ~= "allocations" then copy[key] = value end
        end
        copy.allocations = {}
        for allocation_index, allocation in ipairs(segment.allocations or {}) do
            local allocation_copy = {}
            for key, value in pairs(allocation) do allocation_copy[key] = value end
            copy.allocations[allocation_index] = allocation_copy
        end
        segments[index], segment_by_id[segment.segment_id] = copy, copy
    end
    local bindings = {}
    for index, binding in ipairs(work.bindings) do
        bindings[index] = {}
        for key, value in pairs(binding) do bindings[index][key] = value end
    end
    local function copy_map(map)
        local result = {}
        for key, value in pairs(map or {}) do result[key] = value end
        return result
    end
    return {entities = entities, segments = segments, bindings = bindings,
        segments_by_cell = copy_map(work.segments_by_cell), entity_by_segment = copy_map(work.entity_by_segment),
        underground_cells = copy_map(work.underground_cells), splitter_blocked_cells = copy_map(work.splitter_blocked_cells),
        segment_by_id = segment_by_id, entity_by_id = entity_by_id,
        entity_serial = entity_serial, segment_serial = segment_serial}
end

local function restore_route_snapshot(work, snapshot)
    work.entities, work.segments, work.bindings = snapshot.entities, snapshot.segments, snapshot.bindings
    work.entity_serial, work.segment_serial = snapshot.entity_serial, snapshot.segment_serial
    local segments_by_cell = {}
    for key, segment in pairs(snapshot.segments_by_cell) do segments_by_cell[key] = snapshot.segment_by_id[segment.segment_id] end
    work.segments_by_cell = segments_by_cell
    local entity_by_segment = {}
    for key, entity in pairs(snapshot.entity_by_segment) do entity_by_segment[key] = snapshot.entity_by_id[tostring(entity.id)] end
    work.entity_by_segment = entity_by_segment
    work.underground_cells = snapshot.underground_cells
    work.splitter_blocked_cells = snapshot.splitter_blocked_cells
end

--One walk, two questions.  28.7 asks whether the directed same-flow chain from `source` reaches a named
--tile; 28.8 asks WHICH tiles that chain covers, because a second demand of one flow must start its own
--branch from the trunk its flow already laid.  A copied walk is a walk that drifts, so both callers share
--this body.  With `sink` nil the walk visits the whole run and reports every tile it reached.
local function route_chain_walk(work, source, sink, flow_id)
    local tiles = {}
    if not source then return false, tiles end
    local start_key = coordinate_key(source.x, source.y)
    local target_key = sink and coordinate_key(sink.x, sink.y) or nil
    if target_key ~= nil and work.segments_by_cell[target_key] == nil then return false, tiles end
    local queue, head, seen = {start_key}, 1, {[start_key] = true}
    local function enqueue(key)
        if key ~= nil and not seen[key] then seen[key] = true; queue[#queue + 1] = key end
    end
    while queue[head] do
        local key = queue[head]
        head = head + 1
        local segment = work.segments_by_cell[key]
        if segment and segment_has_flow(segment, flow_id) then
            tiles[#tiles + 1] = key
            if key == target_key then return true, tiles end
            if segment.underground then
                if key == segment.underground_entry_key then enqueue(segment.underground_exit_key) end
                if key == segment.underground_exit_key then
                    local x, y = segment.underground_exit_x, segment.underground_exit_y
                    local dx, dy = Grid.dir_vector(segment.direction)
                    if dx ~= nil then enqueue(coordinate_key(x + dx, y + dy)) end
                end
            elseif segment.splitter then
                local x, y = segment.splitter_anchor_x, segment.splitter_anchor_y
                local dx, dy = Grid.dir_vector(segment.splitter_direction)
                if dx ~= nil then enqueue(coordinate_key(x + dx, y + dy)) end
                enqueue(segment.splitter_second_key)
                --A splitter has TWO output tiles, one in front of each of the tiles it covers.  The walk only
                --ever left by the anchor's, so a run that legally continued out of the second tile read as a
                --broken chain: measured 2026-09-22 on the frozen candidate, item/plate 0:16 -> 12:2 leaving
                --the splitter anchored at 10:7 through its second tile 10:6 into 9:6.
                if dx ~= nil and segment.splitter_second_key ~= nil then
                    local sx, sy = coordinate_from_key(segment.splitter_second_key)
                    if sx ~= nil then enqueue(coordinate_key(sx + dx, sy + dy)) end
                end
            else
                local x, y = string.match(key, "^([^:]+):([^:]+)$")
                local dx, dy = Grid.dir_vector(segment.direction)
                if dx ~= nil then enqueue(coordinate_key(tonumber(x) + dx, tonumber(y) + dy)) end
            end
        end
    end
    return false, tiles
end

local function route_chain_reaches_tiles(work, source, sink, flow_id)
    if not source or not sink then return false end
    local reached = route_chain_walk(work, source, sink, flow_id)
    return reached
end

--Contract 28.8: the tiles this demand's own source already reaches over this flow.  Every tile is by
--construction downstream of THIS demand's source port, so a trunk fed by a different producer is never
--offered as a branch point.
local function route_chain_tiles(work, source, flow_id)
    local _, tiles = route_chain_walk(work, source, nil, flow_id)
    return tiles
end

--The search path is also the router's own directed witness.  A path that merely visited the sink is not a
--route to it, and a newly added branch must not break an earlier binding that shared its trunk.
local function route_chain_reaches_sink(work, demand, path)
    if type(path) ~= "table" or #path == 0 or not demand.sink then return false end
    local last = path[#path]
    if last.x ~= demand.sink.x or last.y ~= demand.sink.y then return false end
    return route_chain_reaches_tiles(work, demand.source, demand.sink, demand.flow_id)
end

local function all_bindings_reach_sinks(work)
    for _, binding in ipairs(work.bindings or {}) do
        local source = work.endpoint_by_id and work.endpoint_by_id[binding.source_port_id]
        local sink = work.endpoint_by_id and work.endpoint_by_id[binding.sink_port_id]
        if not route_chain_reaches_tiles(work, source, sink, binding.flow_id) then return false end
    end
    return true
end

local function append_normal_path(work, demand, path, amount)
    local snapshot = route_snapshot(work)
    local function reject(reason)
        work.last_route_rejection = work.last_route_rejection or {}
        work.last_route_rejection.reason = reason
        work.last_route_rejection.source = demand.source and demand.source.port_id
        work.last_route_rejection.sink = demand.sink and demand.sink.port_id
        work.last_route_rejection.flow_id = demand.flow_id
        restore_route_snapshot(work, snapshot)
        return false, reason
    end
    local sink = sink_key(demand.sink)
    local first_segment
    local allocated_segments = {}
    local index = 0
    while index < #path do
        index = index + 1
        local cell = path[index]
        if is_crossing_step(cell, path[index + 1]) then
            local crossed, reason, segment = append_crossing(work, demand, cell, path[index + 1], amount)
            if not crossed then return reject(reason) end
            first_segment = first_segment or segment
            index = index + 1
        else
        local next_cell = path[index + 1] or path[index - 1] or cell
        local direction = direction_from_step(cell.x, cell.y, next_cell.x, next_cell.y)
        if index == #path and #path > 1 then direction = direction_from_step(path[index - 1].x, path[index - 1].y, cell.x, cell.y) end
        local key = coordinate_key(cell.x, cell.y)
        local segment = work.segments_by_cell[key]
        if segment and direction == nil and segment_has_flow(segment, demand.flow_id) then
            --Contract 28.8: the trunk already runs through this sink's own port tile, so the branch is one
            --cell long and lays nothing.  The sink takes its allocation on the belt that is already there,
            --and its binding is honest.  Never re-derive a direction from a step of length zero.
            direction = segment.direction
        end
        if segment then
            local splitter_continuation = segment.splitter and key == segment.splitter_second_key
                and direction == segment.splitter_direction
            if not allocated_segments[segment.segment_id] then
                local allowed, reason = segment_allows(segment, demand, amount)
                if not allowed then return reject(reason or "occupied") end
            end
            if segment.splitter and key == segment.splitter_second_key and not splitter_continuation then return reject("occupied") end
            --A sink is reached by entering its port tile.  Its existing belt need not point out of that tile,
            --but only when the otherwise required splitter footprint is reserved by an underground endpoint.
            if segment.direction ~= direction and not splitter_continuation
                and not (index == #path and terminal_splitter_refused(work, cell.x, cell.y, segment)) then
                --An underground segment owns two coupled endpoints.  It cannot become a splitter: changing
                --the mapped first entity here would leave its partner carrying a different direction.  The
                --allocation may still share the segment, but its published pair keeps the direction it was built
                --for.  Surface belts retain their existing splitter behaviour.
                    if not splitter_can_absorb(segment)
                        or not splitter_branch_allowed(work, demand, cell.x, cell.y, direction, segment) then
                        work.last_route_rejection = work.last_route_rejection or {}
                        work.last_route_rejection.x, work.last_route_rejection.y = cell.x, cell.y
                        work.last_route_rejection.direction = direction
                        work.last_route_rejection.segment = segment.segment_id
                        work.last_route_rejection.splitter = segment.splitter
                        work.last_route_rejection.segment_direction = segment.direction
                        local second_x, second_y = splitter_second_cell(cell.x, cell.y, direction)
                        work.last_route_rejection.second = second_x and (tostring(second_x) .. ":" .. tostring(second_y))
                        work.last_route_rejection.second_segment = second_x and work.segments_by_cell[coordinate_key(second_x, second_y)]
                            and work.segments_by_cell[coordinate_key(second_x, second_y)].segment_id
                        return reject("splitter-footprint")
                    end
                    local entity = work.entity_by_segment[segment.segment_id]
                    local splitter_direction = direction
                    local second_x, second_y = splitter_second_cell(cell.x, cell.y, splitter_direction)
                    local second_key = coordinate_key(second_x, second_y)
                    local side_segment = work.segments_by_cell[second_key]
                    if not merge_splitter_footprint(work, segment, second_key, demand) then
                        return reject("splitter-footprint")
                    end
                    if first_segment == side_segment then first_segment = segment end
                    local side_x, side_y = second_x - cell.x, second_y - cell.y
                    entity.position = entity_position(cell.x + 0.5 + side_x / 2, cell.y + side_y / 2)
                    entity.name = work.belt.splitter
                    entity.splitter = true
                    entity.direction = splitter_direction
                    entity.dir = splitter_direction
                    segment.splitter = true
                    segment.splitter_direction = splitter_direction
                    segment.splitter_anchor_key = key
                    segment.splitter_second_key = second_key
                    segment.splitter_anchor_x, segment.splitter_anchor_y = cell.x, cell.y
                    work.segments_by_cell[segment.splitter_second_key] = segment
                    end
        else
            local capacity, kind = capacity_for(work, demand.flow)
            segment = {segment_id = next_segment_id(work), kind = kind,
                capacity_per_second = capacity, allocations = {}, flow_id = demand.flow_id, direction = direction,
                length = 1}
            local entity = {id = next_entity_id(work), name = infrastructure(work, kind),
                position = entity_position(cell.x, cell.y), direction = direction, dir = direction,
                flow_id = demand.flow_id, segment_id = segment.segment_id}
            work.entities[#work.entities + 1] = entity
            work.segments[#work.segments + 1] = segment
            work.segments_by_cell[key] = segment
            work.entity_by_segment[segment.segment_id] = entity
        end
        if not allocated_segments[segment.segment_id] then
            register_segment_flow(segment, demand.flow_id)
            add_allocation(segment, demand.flow_id, sink, amount)
            allocated_segments[segment.segment_id] = true
        end
        first_segment = first_segment or segment
        end
    end
    local chain_reaches_sink = route_chain_reaches_sink(work, demand, path)
    if not chain_reaches_sink then return reject("route-discontinuous") end
    if first_segment then
        work.bindings[#work.bindings + 1] = {source_port_id = demand.source.port_id, sink_port_id = demand.sink.port_id,
            sink = sink, flow_id = demand.flow_id, segment_id = first_segment.segment_id, rate_per_second = amount}
    end
    --debug-disabled
    return true
end

--The tile items go down on is the entrance, and a blueprint spells that `type = "input"`; the tile they come up
--on is `"output"`.  Transport runs from the demand's source to its sink, so the source end is the entrance.
local function append_underground(work, demand, candidate, amount)
    local capacity, kind = capacity_for(work, demand.flow)
    if amount > capacity + tolerance(capacity) then return false, "capacity" end
    --An explicit underground endpoint owns its tile for the whole candidate.  If an earlier surface
    --demand already turned that tile into a splitter footprint, reject this route so the normal priority
    --restart can place the underground pair first instead of committing an overlapping pair.
    for _, endpoint in ipairs({candidate.source, candidate.sink}) do
        local occupied = work.segments_by_cell[coordinate_key(endpoint.x, endpoint.y)]
        if occupied and occupied.splitter then return false, "splitter-footprint" end
    end
    local segment = {segment_id = next_segment_id(work), kind = kind,
        capacity_per_second = capacity, allocations = {}, flow_id = demand.flow_id, direction = candidate.direction,
        underground = true, length = candidate.distance,
        underground_entry_key = coordinate_key(candidate.source.x, candidate.source.y),
        underground_exit_key = coordinate_key(candidate.sink.x, candidate.sink.y),
        underground_entry_x = candidate.source.x, underground_entry_y = candidate.source.y,
        underground_exit_x = candidate.sink.x, underground_exit_y = candidate.sink.y}
    local first_id, second_id = next_entity_id(work), next_entity_id(work)
    local name = infrastructure(work, kind)
    if kind == "pipe" then name = (work.pipe and (work.pipe.underground or work.pipe.pipe)) or name
    else name = (work.belt and (work.belt.underground or work.belt.belt)) or name end
    local exit_direction = kind == "pipe" and Grid.dir_opposite(candidate.direction) or candidate.direction
    local first = {id = first_id, name = name, position = entity_position(candidate.source.x, candidate.source.y),
        direction = candidate.direction, dir = candidate.direction, flow_id = demand.flow_id,
        ug_role = "input", ug_pair_id = second_id, segment_id = segment.segment_id}
    local second = {id = second_id, name = name, position = entity_position(candidate.sink.x, candidate.sink.y),
        direction = exit_direction, dir = exit_direction, flow_id = demand.flow_id,
        ug_role = "output", ug_pair_id = first_id, segment_id = segment.segment_id}
    if kind ~= "pipe" then first.type, second.type = "input", "output" end
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
        local allowed, reason = segment_allows(segment, demand, amount)
        if not allowed then
            if reason == "capacity" then search.saw_capacity = true end
            if reason == "occupied" then search.saw_blocked = true end
            --Only a foreign pipe that actually DENIED the step is fluid mixing. Setting the flag on every
            --pipe cell the search merely looked at made an item flow report BP_R_FLUID_MIX, so the belt's
            --real blocker was hidden behind somebody else's pipe.
        if segment.flow_id ~= demand.flow_id and segment.kind == "pipe" then search.saw_fluid_mix = true end
            return false
        end
        local terminal_refused = is_target and terminal_splitter_refused(work, x, y, segment)
        if move_direction ~= nil and segment.direction ~= move_direction and not terminal_refused then
            if not splitter_continuation then
                --A crossing the MATERIALIZER already refused is refused here too, for this demand, for the
                --rest of its routing.  Contract 28.5 says search and materializer ask the same question, and
                --calling the same predicate is not enough to make that true: the search plans a whole path
                --against the world as it stands, while `append_normal_path` mutates the world cell by cell,
                --so an earlier cell of the SAME path can take the splitter's second tile before the crossing
                --is reached.  Measured 2026-09-22 on legalcopilot-dev against
                --tests/fixtures/routing/player_chain_first_candidate.lua: the search passed (10,6), the
                --materializer refused it with second=10:7 held by r:s:19, and the demand died BP_R_NO_PATH
                --with a route still available around it.
                if demand.crossing_blocked and demand.crossing_blocked[coordinate_key(x, y)] then
                    search.saw_blocked = true
                    return false
                end
                if not splitter_can_absorb(segment)
                    or not splitter_branch_allowed(work, demand, x, y, move_direction, segment, search) then
                    search.saw_blocked = true
                    return false
                end
                search.saw_branch = true
            end
        end
    end
    return true
end

local function default_expansion_limit(input, demand_count)
    local grid = type(input) == "table" and input.grid or nil
    local w = type(grid) == "table" and finite(grid.w, nil) or nil
    local h = type(grid) == "table" and finite(grid.h, nil) or nil
    demand_count = math.max(1, math.floor(finite(demand_count, 1)))
    local cells = 1
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
        cells = math.max(1, math.floor(w * h))
    end
    --A frontier state is (cell, arrival heading, transport kind, underground mode).  The four direction-order
    --replays remain part of the bounded recovery protocol, so the cumulative default is cells * 4 * 2 * 2 * 4.
    local sweep = cells * #DIRECTIONS * 2 * 2 * #DIRECTION_ORDERS
    return math.max(4096, sweep) * demand_count
end

local function state_key(x, y, arrival_direction, kind, underground_mode)
    return coordinate_key(x, y) .. ":d=" .. tostring(arrival_direction or 0)
        .. ":k=" .. tostring(kind or "") .. ":u=" .. tostring(underground_mode or 0)
end

local function heuristic(search, x, y)
    local sink = search.demand and search.demand.sink
    if not sink or sink.x == nil or sink.y == nil then return 0 end
    return HEURISTIC_PER_TILE * (math.abs(x - sink.x) + math.abs(y - sink.y))
end

local function heap_before(left, right)
    local left_priority = left.priority or left.cost
    local right_priority = right.priority or right.cost
    if left_priority ~= right_priority then return left_priority < right_priority end
    if left.cost ~= right.cost then return left.cost < right.cost end
    return left.serial < right.serial
end

local function heap_push(search, node)
    search.serial = search.serial + 1
    node.serial = search.serial
    local heap = search.heap
    heap[#heap + 1] = node
    local index = #heap
    while index > 1 do
        local parent = math.floor(index / 2)
        if heap_before(heap[parent], heap[index]) then break end
        heap[parent], heap[index] = heap[index], heap[parent]
        index = parent
    end
end

local function heap_pop(search)
    local heap = search.heap
    if #heap == 0 then return nil end
    local result = heap[1]
    local last = heap[#heap]
    heap[#heap] = nil
    if #heap > 0 then
        heap[1] = last
        local index = 1
        while true do
            local left, right = index * 2, index * 2 + 1
            local smallest = index
            if left <= #heap and heap_before(heap[left], heap[smallest]) then smallest = left end
            if right <= #heap and heap_before(heap[right], heap[smallest]) then smallest = right end
            if smallest == index then break end
            heap[index], heap[smallest] = heap[smallest], heap[index]
            index = smallest
        end
    end
    return result
end

local function enqueue_state(search, x, y, arrival_direction, mode, parent_key, cost)
    local key = state_key(x, y, arrival_direction, search.demand.kind, mode)
    local previous = search.best[key]
    if previous ~= nil and cost >= previous - EPSILON then return false end
    search.best[key] = cost
    search.parent[key] = parent_key
    search.points[key] = {x = x, y = y}
    heap_push(search, {key = key, x = x, y = y, direction = arrival_direction, mode = mode, cost = cost,
        priority = cost + heuristic(search, x, y)})
    return true
end

local function begin_search(work, demand, amount, order_index)
    order_index = order_index or 1
    local search = {demand = demand, amount = amount, heap = {}, serial = 0, best = {}, parent = {}, points = {},
        saw_capacity = false, saw_fluid_mix = false, saw_blocked = false,
        directions = DIRECTION_ORDERS[order_index], order_index = order_index, closed = {}}
    search.source_key = state_key(demand.source.x, demand.source.y, demand.source.travel_dir or 0, demand.kind, 0)
    search.points[search.source_key] = {x = demand.source.x, y = demand.source.y}
    search.best[search.source_key] = 0
    search.parent[search.source_key] = nil
    heap_push(search, {key = search.source_key, x = demand.source.x, y = demand.source.y,
        direction = demand.source.travel_dir or 0, mode = 0, cost = 0,
        priority = heuristic(search, demand.source.x, demand.source.y)})
    local source_segment = work.segments_by_cell[coordinate_key(demand.source.x, demand.source.y)]
    if source_segment then
        local allowed, reason = segment_allows(source_segment, demand, amount)
        if not allowed then
            search.saw_capacity, search.saw_fluid_mix, search.heap = reason == "capacity", reason == "fluid_mix", {}
        end
    end
    --Contract 28.8.  Two demands of one flow share one trunk, and sharing the trunk does not discharge the
    --branch: this sink still needs its own belt from that trunk to its own port tile.  Until this seeding
    --existed, every demand re-walked the whole distance from its own source port, collided with the trunk
    --its predecessor laid, and died -- measured on the player's frozen candidate 2026-09-22 as
    --BP_R_NO_PATH for item/plate (0,16) -> (10,7) while (10,6) was already served.
    --
    --Seeding is additive: the real source seed above is unconditional, so a flow with no laid run searches
    --exactly as before.  A seed's parent stays nil, which is what `reconstruct` stops on.
    local source_key = coordinate_key(demand.source.x, demand.source.y)
    for _, key in ipairs(route_chain_tiles(work, demand.source, demand.flow_id)) do
        if key ~= source_key then
            local segment = work.segments_by_cell[key]
            local x, y = coordinate_from_key(key)
            --A refused seed is skipped, never fatal: the run may be full at one tile and free at the next.
            if x ~= nil and segment and segment_allows(segment, demand, amount) then
                local heading = segment.splitter and segment.splitter_direction or segment.direction
                local seed_cost = 0
                if x == demand.sink.x and y == demand.sink.y
                    and demand.sink.travel_dir ~= nil and heading ~= demand.sink.travel_dir then
                    --The trunk already crosses this sink's own port tile, but in the wrong heading.  That
                    --still feeds the sink, and it is still worse geometry than approaching the port tile the
                    --way the port asks.  So it is priced LAST, never forbidden and never free.  Measured
                    --2026-09-22 on legalcopilot-dev: forbidding it loses the player's frozen candidate
                    --entirely (ok=false), and offering it at cost 0 loses the splitter that
                    --tests/test_route_footprints.lua RF1 requires at the turn.
                    seed_cost = SEEDED_SINK_LAST
                end
                enqueue_state(search, x, y, heading, 0, nil, seed_cost)
            end
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
        local underground_key = state_key(x, y, direction, demand.kind, 1)
        if not search.best[underground_key] and not work.segments_by_cell[key] and not work.underground_cells[key]
            and path_cell_free(work, demand, x, y, direction, x == demand.sink.x and y == demand.sink.y, amount, search) then
            return {x = x, y = y}
        end
    end
    return nil
end

local function transition_cost(work, demand, x, y, direction, previous_direction, mode, distance, amount)
    if mode == 1 then
        --Both endpoints and the underground span are real cost.  Crossings also carry the witness overhead.
        return 2 + distance + 2
    end
    local segment = work.segments_by_cell[coordinate_key(x, y)]
    local cost = 1
    if segment and segment_has_flow(segment, demand.flow_id)
        and segment.kind == demand.kind
        and segment_total(segment) + amount <= segment.capacity_per_second + tolerance(segment.capacity_per_second) then
        cost = 0.2
    end
    if previous_direction ~= nil and previous_direction ~= 0 and previous_direction ~= direction then cost = cost + 1 end
    if segment and segment.direction ~= direction then cost = cost + 2 end
    return cost
end

local function search_step(work, search)
    local current = heap_pop(search)
    if not current then return "failed" end
    if search.closed[current.key] then return "continue" end
    if search.best[current.key] ~= current.cost then return "continue" end
    search.closed[current.key] = true
    if current.x == search.demand.sink.x and current.y == search.demand.sink.y then
        return reconstruct(search, current.key)
    end
    for _, direction in ipairs(search.directions) do
        local dx, dy = Grid.dir_vector(direction)
        local nx, ny = current.x + dx, current.y + dy
        local target = nx == search.demand.sink.x and ny == search.demand.sink.y
        local first = current.x == search.demand.source.x and current.y == search.demand.source.y
        --An underground exit IS the underground entity, and it delivers onto the one tile it faces.  A search
        --that turns the moment it surfaces plans a belt no chain can walk: measured 2026-09-22 on the frozen
        --candidate as item/cable 10:8 -> 10:5 surfacing north at 11:5 and stepping west to 10:5, which
        --contract 28.7 then correctly refuses as route-discontinuous.  A crossing is committed to its own
        --heading for exactly one more tile.
        local surfaced = current.mode == 1 and current.direction ~= nil and current.direction ~= direction
        --A belt cannot carry items back the way they came.  Materialising a reversal writes two belts facing
        --each other, and contract 28.7's walk then loops instead of reaching the sink: measured 2026-09-22 on
        --the frozen candidate as item/plate 0:16 -> 12:2 stepping 10:6 west to 9:6 and diving east again.
        local reversed = current.direction ~= nil and direction == Grid.dir_opposite(current.direction)
        if not surfaced and not reversed
            and (not first or search.demand.source.travel_dir == nil or search.demand.source.travel_dir == direction)
            and (not target or search.demand.sink.travel_dir == nil or search.demand.sink.travel_dir == direction) then
            local free = path_cell_free(work, search.demand, nx, ny, direction, target, search.amount, search)
            if free then
                local cost = current.cost + transition_cost(work, search.demand, nx, ny, direction,
                    current.direction, 0, 0, search.amount)
                enqueue_state(search, nx, ny, direction, 0, current.key, cost)
            elseif not first then
                local crossing = crossing_target(work, search.demand, search, current, direction, search.amount)
                if crossing then
                    local reaches_sink = crossing.x == search.demand.sink.x and crossing.y == search.demand.sink.y
                    if not reaches_sink or search.demand.sink.travel_dir == nil or search.demand.sink.travel_dir == direction then
                        local cost = current.cost + transition_cost(work, search.demand, crossing.x, crossing.y, direction,
                            current.direction, 1, underground_distance(current, crossing), search.amount)
                        enqueue_state(search, crossing.x, crossing.y, direction, 1, current.key, cost)
                    end
                end
            end
        end
    end
    return "continue"
end

local function audit_route_work(work)
    local live_segments = {}
    for _, segment in ipairs(work.segments or {}) do
        local live = false
        for _, allocation in ipairs(segment.allocations or {}) do
            if allocation.rate_per_second > tolerance(allocation.rate_per_second) then live = true; break end
        end
        if live then live_segments[segment.segment_id] = segment end
    end
    local segments = {}
    for _, segment in ipairs(work.segments or {}) do
        if live_segments[segment.segment_id] then segments[#segments + 1] = segment end
    end
    local entities = {}
    for _, entity in ipairs(work.entities or {}) do
        if entity.segment_id and live_segments[entity.segment_id] then
            entity._route_removed = nil
            entities[#entities + 1] = entity
        else
            work.counters.discarded_geometry = (work.counters.discarded_geometry or 0) + 1
        end
    end
    work.segments, work.entities = segments, entities
    local segments_by_cell = {}
    for key, segment in pairs(work.segments_by_cell or {}) do
        if live_segments[segment.segment_id] then segments_by_cell[key] = segment end
    end
    work.segments_by_cell = segments_by_cell
    local entity_by_segment = {}
    for _, entity in ipairs(entities) do
        if entity_by_segment[entity.segment_id] == nil then entity_by_segment[entity.segment_id] = entity end
    end
    work.entity_by_segment = entity_by_segment
    local underground_cells = {}
    for key, _ in pairs(work.underground_cells or {}) do
        local segment = work.segments_by_cell[key]
        if segment and segment.underground then underground_cells[key] = true end
    end
    work.underground_cells = underground_cells
    local splitter_cells = {}
    for key, _ in pairs(work.splitter_blocked_cells or {}) do
        if work.segments_by_cell[key] then splitter_cells[key] = true end
    end
    work.splitter_blocked_cells = splitter_cells
    local bindings = {}
    for _, binding in ipairs(work.bindings or {}) do
        if live_segments[binding.segment_id] then bindings[#bindings + 1] = binding end
    end
    work.bindings = bindings
    return work
end

local function result_for(work)
    audit_route_work(work)
    local result = {entities = {}, segments = {}, port_bindings = work.bindings, bindings = work.bindings,
        shortfalls = work.shortfalls or {}}
    for _, entity in ipairs(work.entities) do
        if not entity._route_removed then result.entities[#result.entities + 1] = entity end
    end
    for _, segment in ipairs(work.segments) do
        local copy = {segment_id = segment.segment_id, kind = segment.kind,
            capacity_per_second = segment.capacity_per_second, allocations = {}, length = segment.length}
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
    local function claim(x, y, endpoint, owns_tile)
        if endpoint.port_id == nil or not inside_grid(work, x, y) then return end
        local key = coordinate_key(x, y)
        reserved[key] = reserved[key] or {}
        reserved[key][endpoint.port_id] = true
        if endpoint.flow_id ~= nil then reserved[key]["flow:" .. tostring(endpoint.flow_id)] = true end
        if owns_tile then
            reserved[key]._port_owners = reserved[key]._port_owners or {}
            reserved[key]._port_owners[endpoint.port_id] = true
        end
    end
    local function claim_endpoint(endpoint)
        if type(endpoint) ~= "table" or endpoint.x == nil or endpoint.y == nil then return end
        local function claim_approach(direction)
            claim(endpoint.x, endpoint.y, endpoint, true)
            local dx, dy = Grid.dir_vector(direction or Grid.NORTH)
            if endpoint.role == "in" then claim(endpoint.x - dx, endpoint.y - dy, endpoint, false)
            else claim(endpoint.x + dx, endpoint.y + dy, endpoint, false) end
        end
        claim_approach(endpoint.travel_dir)
        if endpoint.validator_travel_dir ~= nil and endpoint.validator_travel_dir ~= endpoint.travel_dir then
            claim_approach(endpoint.validator_travel_dir)
        end
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
        grid = copy_grid(input), obstacles = {}, endpoint_index = {}, endpoint_by_id = {}, perimeter = {},
        entities = {}, segments = {}, bindings = {}, segments_by_cell = {}, entity_by_segment = {},
        --Ids were derived from the arrays' LENGTH.  merge_splitter_footprint folds a side segment out
        --of both arrays, so the next id repeated one already in the result: measured 2026-09-22 as
        --tests/test_underground_pairs.lua 'route entity ids are unique' the moment a splitter merged.
        --A serial only ever moves forward, and a snapshot restores the serial it was taken with.
        entity_serial = 0, segment_serial = 0,
        underground_cells = {}, splitter_blocked_cells = {}, counters = new_counters(), attempt_generation = 0,
        --The allowance is filled after demands are built. One routing run has one cumulative budget, so every
        --demand gets the same cell/direction-order sweep that a single-demand run would have had. This keeps
        --adding consumers from stealing the budget from the demand whose path became easier to find.
        max_expansions = nil, expansions = 0,
        expansion_state_space = {directions = #DIRECTIONS, kinds = 2, underground_modes = 2,
            direction_orders = #DIRECTION_ORDERS},
    }
    for _, block in ipairs(blocks) do
        local placement = placement_for(block, placements)
        block._placement, block._w, block._h = placement, dimension_for(block, placement, "w", 1), dimension_for(block, placement, "h", 1)
        for _, port in ipairs(block.ports or block.block_ports or {}) do
            local endpoint = normalize_endpoint(block, placement, port, input.catalog or {}, work)
            if endpoint and endpoint.flow_id then
                work.endpoint_by_id[endpoint.port_id] = endpoint
                work.endpoint_index[endpoint.flow_id] = work.endpoint_index[endpoint.flow_id] or {["in"] = {}, ["out"] = {}}
                work.endpoint_index[endpoint.flow_id][endpoint.role][#work.endpoint_index[endpoint.flow_id][endpoint.role] + 1] = endpoint
            end
        end
    end
    add_input_obstacles(work, input, blocks)
    for _, port in ipairs(perimeter_entries(input)) do
        local endpoint = normalize_perimeter(port)
        if endpoint and endpoint.flow_id then
            work.endpoint_by_id[endpoint.port_id] = endpoint
            work.perimeter[#work.perimeter + 1] = endpoint
        end
    end
    --Explicit underground ports reserve their endpoint tiles before the first demand is searched.  A surface
    --demand must therefore refuse a splitter footprint that would consume a future underground end; otherwise
    --the later pair would have to undo an already published surface route.
    for _, endpoint in pairs(work.endpoint_by_id) do
        if endpoint.connection and endpoint.connection.connection_type == "underground" then
            work.splitter_blocked_cells[coordinate_key(endpoint.x, endpoint.y)] = true
        end
    end
    work.flows = flow_list(input)
    work.demands = build_demands(work, work.flows)
    work.max_expansions = finite(input.limits and input.limits.max_expansions,
        finite(input.max_expansions, default_expansion_limit(input, #work.demands)))
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
    audit_route_work(work)
    work.counters.restarts = work.counters.restarts + 1
    work.demands = ordered
    for _, entry in ipairs(ordered) do
        entry.remaining = entry.amount
        entry.source_index, entry.sink_index = 1, 1
        entry.source = entry.source_candidates and entry.source_candidates[1] or entry.source
        entry.sink = entry.sink_candidates and entry.sink_candidates[1] or entry.sink
    end
    work.entities, work.segments, work.bindings = {}, {}, {}
    work.segments_by_cell, work.entity_by_segment, work.underground_cells = {}, {}, {}
    work.splitter_blocked_cells = {}
    work.attempt_generation, work.current = work.attempt_generation + 1, nil
    audit_route_work(work)
    state.cursor.demand_index, state.progress.done_units = 1, 0
    state.progress.phase = "routing"
    return true
end

local function clear_route_work(work)
    audit_route_work(work)
    work.entities, work.segments, work.bindings = {}, {}, {}
    work.segments_by_cell, work.entity_by_segment, work.underground_cells = {}, {}, {}
    work.splitter_blocked_cells = {}
    work.current = nil
    audit_route_work(work)
end

local function next_endpoint_candidate(demand)
    local sources = demand and demand.source_candidates or {}
    local sinks = demand and demand.sink_candidates or {}
    local source_index = demand and demand.source_index or 1
    local sink_index = demand and demand.sink_index or 1
    if source_index < #sources then
        demand.source_index = source_index + 1
        demand.source = sources[demand.source_index]
        return demand.source ~= nil
    end
    if sink_index < #sinks then
        demand.sink_index = sink_index + 1
        demand.source_index = 1
        demand.source = sources[1]
        demand.sink = sinks[demand.sink_index]
        return demand.source ~= nil and demand.sink ~= nil
    end
    return false
end

--Contract 28.7 says "the demand is refused by name".  It says nothing about refusing the candidate, and the
--difference is the whole product.  Measured 2026-09-22 on legalcopilot-dev against the player's real sheet:
--refusing the candidate left 0 of 11 candidates reaching the validator and the search died BP_FAIL_GRID_LIMIT
--with 12 BP_R_NO_PATH records and nothing judged; refusing only the demand restores the flow and drops the
--dominant code, 853 BP_V_TRANSPORT_UNUSED to 706 and 63 BP_V_ROUTE_DISCONTINUOUS to 58, 919 records to 818.
--
--An unserved demand is a SHORTFALL, and the validator already names it: BP_V_TARGET_SHORTFALL, plus the
--honest consequences of an unfed machine -- BP_V_PORT_UNREACHABLE, BP_V_TRANSFER_BROKEN.  Those codes were
--zero before only because no candidate had ever admitted leaving a machine unfed.
--
--Only BP_R_NO_PATH becomes a shortfall, and that is the point: it is the one refusal that says "this
--geometry has no room", which is exactly what 28.7 and 28.8 refuse by name.  Every other refusal stays
--FATAL, because each says the plan itself is wrong and a shortfall would bury that:
--  BP_R_FLUID_MIX   two fluids on one pipe -- tests/test_route.lua R5
--  BP_R_CAPACITY    two 6/s demands on one 10/s belt -- tests/test_route.lua R6
--  BP_R_PORT_BLOCKED  a port nothing can attach to
--  BP_R_EXPANSIONS  a budget stop, never a geometry fact -- tests/test_route_budget.lua RB3
--And a route that serves NO demand at all is not a shortfall, it is a failure, so its code is reported.
local function shortfall_allowed(work, demand, code)
    if code ~= "BP_R_NO_PATH" or demand == nil then return false end
    for _, entry in ipairs(work.demands or {}) do
        if entry ~= demand and entry.unroutable == nil then return true end
    end
    return #(work.bindings or {}) > 0
end

local function fail_demand(state, work, demand, code, detail)
    if code ~= "BP_R_EXPANSIONS" and restart_with_priority(state, work, demand) then return false end
    if shortfall_allowed(work, demand, code) then
        demand.unroutable = code
        demand.remaining = 0
        work.shortfalls = work.shortfalls or {}
        work.shortfalls[#work.shortfalls + 1] = {code = code, flow_id = demand.flow_id,
            source_port_id = demand.source and demand.source.port_id,
            sink_port_id = demand.sink and demand.sink.port_id,
            rate_per_second = demand.amount, detail = detail}
        return false
    end
    local record = {code = code, flow_id = demand and demand.flow_id}
    if detail ~= nil then record.detail = detail end
    --A bare BP_R_NO_PATH names the flow and nothing else, so every diagnosis of it starts by rebuilding the
    --endpoints by hand. Carry them on the record: which cell the router started from, which it had to reach,
    --and how many alternatives it had left.
    if demand ~= nil then
        local source, sink = demand.source, demand.sink
        record.endpoints = {
            source_x = source and source.x, source_y = source and source.y,
            source_port_id = source and source.port_id,
            sink_x = sink and sink.x, sink_y = sink and sink.y,
            sink_port_id = sink and sink.port_id,
            source_candidates = #(demand.source_candidates or {}),
            sink_candidates = #(demand.sink_candidates or {}),
        }
    end
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
                    if not next_endpoint_candidate(demand) and fail_demand(state, work, demand, "BP_R_PORT_BLOCKED",
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
                    if not next_endpoint_candidate(demand) then
                        fail_demand(state, work, demand, code,
                            code == "BP_R_PORT_BLOCKED" and blocked_port_detail(work, demand.source, demand.sink) or nil)
                    end
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
                    if not placed and reason == "splitter-footprint" then
                        --A refused splitter footprint is a refused CROSSING, never a refused demand.  Record
                        --the anchor cell so the search stops offering it, then search again.  Without this,
                        --contract 28.5's named refusal turns every crossing it correctly rejects into
                        --BP_R_NO_PATH for the whole flow, which is strictly worse than the silent
                        --mismatched belt it replaced.
                        local rejection = work.last_route_rejection or {}
                        local blocked_x, blocked_y = rejection.x, rejection.y
                        if blocked_x ~= nil and blocked_y ~= nil then
                            demand.crossing_blocked = demand.crossing_blocked or {}
                            local blocked_key = coordinate_key(blocked_x, blocked_y)
                            if not demand.crossing_blocked[blocked_key] then
                                demand.crossing_blocked[blocked_key] = true
                                work.current = begin_search(work, demand, amount, 1)
                            end
                        end
                        if work.current == nil then fail_demand(state, work, demand, "BP_R_NO_PATH") end
                    elseif not placed then
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
                    elseif next_endpoint_candidate(demand) then
                        work.current = nil
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
