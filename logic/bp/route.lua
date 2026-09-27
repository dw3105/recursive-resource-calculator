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
local Flags = require "logic.bp.flags"
local FluidTouch = require "logic.bp.fluid_touch"
local SideFeed = require "logic.bp.side_feed"
local PipeRuns = require "logic.bp.pipe_runs"

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
--One A* expansion (heap pop, neighbour checks, crossing targets) costs ~50-80 us on the player's green sheet; one op is
--budgeted at ~8 us (2000 ops ~ one 16 ms game tick). Charged at 1 op, a 2000-op call ran 0.1-0.56 s (measured
--2026-09-24, legalcopilot-dev, tools/tick_parts.lua). Decisions count steps and expansions, never ops.
local EXPANSION_OPS = 10
local HEURISTIC_PER_TILE = 1
--Contract 28.8.  A trunk tile that is already the sink's own port tile, entered in a heading the port
--did not ask for, is the LAST answer the search should take: high enough that any real approach wins,
--finite so a sink with no other approach is still served.
local SEEDED_SINK_LAST = 0
--A splitter is the expensive answer, never the forbidden one (contract 28.8).  Leaving a trunk through a
--splitter body costs two belts' worth of commitment and forces the branch to jog one tile, so it is priced
--above the plain turn it replaces and a continuation keeps winning wherever one exists.
local SPLITTER_BODY_COST = 4
--A side-fed dive blocks one lane; retain it only after straight routes, including a splitter, lose.
local SIDELOAD_UNDERGROUND_COST = 8
--Player: “it is much more reasonable to put gears belt underground instead of copper plates one!” (9,20).
local BURY_COST = 3
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
        --A row port feeds its belt run's head or leaves its end (docs/contracts/row_block.md): like a perimeter
        --door, its belt must face the port's own heading.
        row_port = port.row_port == true or nil,
        --A one-flow rear port may be entered by a curve: its belt faces the port's heading into the row head, and
        --with nothing behind it that belt is a curve, not a side-load (round 28, the player's v8 U-turn).
        rear_curve = (port.rear == true and ((port.flow_ids and #port.flow_ids > 0 and #port.flow_ids <= 2)
            or (port_flow_id(port) ~= nil and port.flow_ids == nil))) or nil,
        --A row's side feed (its belt side-loads the run head) may be entered by a curve for the same reason: the
        --feed belt still faces the port's heading, so it lands on the same lane (player's hand fix of v10 at (7,2),
        --2026-09-24: lane walk mixed=0). Offered only in the keep-if-cheaper improve pass: in first routing it moved
        --the gear feed off its underground and cost the player's sheet 185 -> 190 entities.
        feed_curve = (port.row_port == true and port.rear ~= true and role == "in"
            and ((port.flow_ids and #port.flow_ids > 0 and #port.flow_ids <= 2) or (port_flow_id(port) ~= nil and port.flow_ids == nil))) or nil,
        block_id = block.block_id or block.id,
        step_id = port.step_id or block_step_id(block),
        inserter_id = port.inserter_id,
        role = role,
        position_explicit = port.x ~= nil and port.y ~= nil,
        flow_id = port_flow_id(port),
        flow_ids = port.flow_ids,
        kind = port.kind or (port.is_fluid and "fluid" or "item"),
        rate_per_second = finite(port.rate_per_second, finite(port.rate, 0)),
        x = x, y = y,
        travel_dir = endpoint_direction(port, placement, role),
    }
    endpoint.connection = connection_for(block, port, placement, catalog, x, y)
    --The search names the one-tile moves its hand may make along the machine face (see improve_routes).
    if type(port.slide_options) == "table" and port.hand_x ~= nil and port.hand_y ~= nil then
        endpoint.slide_options, endpoint.hand_x, endpoint.hand_y = port.slide_options, port.hand_x, port.hand_y
    end
    if type(port.hop_options) == "table" and port.hand_x ~= nil and port.hand_y ~= nil then
        endpoint.hop_options, endpoint.hand_x, endpoint.hand_y = port.hop_options, port.hand_x, port.hand_y
    end
    --A rotated materialization carries source-frame attach geometry and a validator-facing travel direction.
    --Traversal still uses the placed direction above, but the validator also protects the approach implied by
    --this published direction. Keep that second direction private to reservation construction.
    if port.x == nil and port.y == nil and port._block_w ~= nil then
        endpoint.validator_travel_dir = port.travel_dir or port.dir or port.normal_dir
    end
    --A pipe has no heading: it joins every neighbour, and the port tile joins the machine's fluid box whichever
    --way the path arrives. A belt heading here only forbids legal arrivals and claims a tile no pipe needs.
    if endpoint.kind == "fluid" then endpoint.fluid_travel_dir = endpoint.travel_dir; endpoint.travel_dir, endpoint.validator_travel_dir = nil, nil end
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

--Validation keys an implicit external output by the first placed machine output port, while an explicitly named
--perimeter port is keyed by that port. Keep the route's physical endpoint separate from the allocation witness:
--the former is still where the belt ends, the latter is what the validator uses to account for the external sink.
local function sink_key(endpoint, work, explicit_port_id)
    if endpoint.perimeter then
        if endpoint.role == "out" and explicit_port_id == nil then
            local by_flow = work and work.endpoint_index and work.endpoint_index[endpoint.flow_id]
            local outputs = by_flow and by_flow.out
            local canonical = outputs and outputs[1]
            if canonical then return "port:" .. tostring(canonical.port_id) end
        end
        return "port:" .. tostring(endpoint.port_id)
    end
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
--A resumable breadth-first flood from one source tile over the static obstacles. Every pair that shares the source
--reads its distance from the same flood: BFS distance to a tile does not depend on where the search stops. The sink
--tile is open for its own pair only, so a blocked sink is reached from its best flooded neighbour.
local function pairing_flood_begin(work, source)
    local start = coordinate_key(source.x, source.y)
    return {source = source, queue = {{x = source.x, y = source.y, distance = 0}}, head = 1,
        dist = {[start] = 0}, done = false}
end

local function pairing_flood_step(work, flood, cells)
    local grid = work.grid or {}
    local source = flood.source
    local used = 0
    while flood.queue[flood.head] and used < cells do
        local current = flood.queue[flood.head]
        flood.head, used = flood.head + 1, used + 1
        for _, direction in ipairs(DIRECTIONS) do
            local dx, dy = Grid.dir_vector(direction)
            local x, y = current.x + dx, current.y + dy
            local key = coordinate_key(x, y)
            if flood.dist[key] == nil and (grid.w == nil or (x >= 0 and y >= 0 and x < grid.w and y < grid.h)) then
                local owner = work.obstacles[coordinate_key(x, y)]
                local open = (x == source.x and y == source.y)
                    or ((owner == nil or owner == Grid.RESERVED.corridor or owner == Grid.RESERVED.port)
                        and indexed_cell(grid, x, y) == nil)
                if open then
                    flood.dist[key] = current.distance + 1
                    flood.queue[#flood.queue + 1] = {x = x, y = y, distance = current.distance + 1}
                end
            end
        end
    end
    if not flood.queue[flood.head] then flood.done, flood.queue = true, nil end
    return used
end

local function pairing_flood(work, source)
    work.pairing_floods = work.pairing_floods or {}
    local key = coordinate_key(source.x, source.y)
    local flood = work.pairing_floods[key]
    if not flood then flood = pairing_flood_begin(work, source); work.pairing_floods[key] = flood end
    return flood
end

local function pairing_route_cost(work, source, sink)
    if not source or not sink then return math.huge end
    if source.x == sink.x and source.y == sink.y then return 0 end
    local flood = pairing_flood(work, source)
    if not flood.done then pairing_flood_step(work, flood, math.huge) end
    local direct = flood.dist[coordinate_key(sink.x, sink.y)]
    if direct ~= nil then return direct end
    local grid = work.grid or {}
    if grid.w ~= nil and not (sink.x >= 0 and sink.y >= 0 and sink.x < grid.w and sink.y < grid.h) then return math.huge end
    local best = math.huge
    for _, direction in ipairs(DIRECTIONS) do
        local dx, dy = Grid.dir_vector(direction)
        local d = flood.dist[coordinate_key(sink.x - dx, sink.y - dy)]
        if d ~= nil and d + 1 < best then best = d + 1 end
    end
    return best
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
--passing at default configuration while the halves are being built.  Integration wired this route half on
--2026-09-22; the shared default remains the authority.
local multi_flow_hands = Flags.multi_flow_hands

local function multi_flow_hands_enabled(input)
    local forced = input and input._force_multi_flow_hands
    if forced ~= nil then return forced == true end
    return multi_flow_hands
end

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
        demands[#demands + 1] = {endpoint = endpoint, candidates = {endpoint}, remaining = amount,
            explicit_port_id = entry and (entry.port_id or entry.port)}
    end
end

-- Output hands from one machine can share a collector when their drop ports form a straight,
-- adjacent run.  Start at the end nearest the usual northbound route; the first belt tiles then
-- cover every hand drop, since a hand can drop onto a belt regardless of its facing.
local function combine_adjacent_output_hands(work, demands)
    local groups = {}
    for _, demand in ipairs(demands) do
        local endpoint = demand.endpoint
        if endpoint and endpoint.step_id ~= "$external" and endpoint.kind ~= "fluid" then
            local key = tostring(endpoint.step_id)
            groups[key] = groups[key] or {}
            groups[key][#groups[key] + 1] = demand
        end
    end
    local removed = {}
    for _, group_key in ipairs(sorted_keys(groups)) do
        local group = groups[group_key]
        local pending = {}
        for _, member in ipairs(group) do pending[member] = true end
        while next(pending) do
            local seed
            for member in pairs(pending) do seed = member; break end
            local component, queue = {}, {seed}
            pending[seed] = nil
            while #queue > 0 do
                local member = table.remove(queue)
                component[#component + 1] = member
                for other in pairs(pending) do
                    local a, b = member.endpoint, other.endpoint
                    if (a.x == b.x and math.abs(a.y - b.y) == 1)
                        or (a.y == b.y and math.abs(a.x - b.x) == 1) then
                        pending[other] = nil
                        queue[#queue + 1] = other
                    end
                end
            end
            local collinear = true
            for _, member in ipairs(component) do
                if member.endpoint.x ~= component[1].endpoint.x and member.endpoint.y ~= component[1].endpoint.y then
                    collinear = false
                end
            end
            if #component > 1 and collinear then
                table.sort(component, function(a, b)
                    if a.endpoint.y ~= b.endpoint.y then return a.endpoint.y > b.endpoint.y end
                    return a.endpoint.x < b.endpoint.x
                end)
                local total, chosen_member, port_ids, members = 0, component[1], {}, {}
                local vertical = true
                for _, member in ipairs(component) do
                    if member.endpoint.x ~= component[1].endpoint.x then vertical = false end
                end
                for _, member in ipairs(component) do
                    total = total + member.remaining
                    removed[member] = true
                    port_ids[member.endpoint.port_id] = true
                    members[#members + 1] = {endpoint = member.endpoint, amount = member.remaining}
                    local point, chosen = member.endpoint, chosen_member.endpoint
                    if (vertical and point.y > chosen.y) or (not vertical and point.x < chosen.x) then chosen_member = member end
                end
                local chosen = chosen_member.endpoint
                demands[#demands + 1] = {endpoint = chosen, candidates = {chosen}, remaining = total,
                    explicit_port_id = chosen_member.explicit_port_id, collector_port_ids = port_ids,
                    collector_members = members}
                local tiles = {}
                table.sort(component, function(a, b)
                    if vertical then return a.endpoint.y > b.endpoint.y end
                    return a.endpoint.x < b.endpoint.x
                end)
                for _, member in ipairs(component) do tiles[#tiles + 1] = {x = member.endpoint.x, y = member.endpoint.y} end
                local direction = vertical and Grid.NORTH or Grid.EAST
                work.belt_runs = work.belt_runs or {}
                local hand_ids = {}
                for _, member in ipairs(component) do
                    if member.endpoint.inserter_id then hand_ids[#hand_ids + 1] = member.endpoint.inserter_id end
                end
                work.collectors_used = true
                work.belt_runs[#work.belt_runs + 1] = {role = "out", dir = direction, flows = {chosen.flow_id},
                    head = tiles[1], tiles = tiles, hand_ids = hand_ids, synthetic_collector = true}
            end
        end
    end
    if next(removed) then
        local kept = {}
        for _, demand in ipairs(demands) do if not removed[demand] then kept[#kept + 1] = demand end end
        for index = #demands, 1, -1 do demands[index] = nil end
        for _, demand in ipairs(kept) do demands[#demands + 1] = demand end
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
                if work.collectors and #consumers == 1 and consumers[1].endpoint.position_explicit then
                    combine_adjacent_output_hands(work, producers)
                end
            else
                for _, entry in ipairs(flow.producers or {}) do
                    local role = step_id_of(entry) == "$external" and "in" or "out"
                    local candidates = demand_endpoint_candidates(work, id, role, entry)
                    producers[#producers + 1] = {endpoint = candidates[1], candidates = candidates,
                        remaining = share_of(entry), explicit_port_id = entry and (entry.port_id or entry.port)}
                end
                for _, entry in ipairs(flow.consumers or {}) do
                    local role = step_id_of(entry) == "$external" and "out" or "in"
                    local candidates = demand_endpoint_candidates(work, id, role, entry)
                    consumers[#consumers + 1] = {endpoint = candidates[1], candidates = candidates,
                        remaining = share_of(entry), explicit_port_id = entry and (entry.port_id or entry.port)}
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
                    pairing_cost = best.route_cost, sink_port_id = best.consumer.explicit_port_id,
                    collector_port_ids = best.producer.collector_port_ids,
                    collector_members = best.producer.collector_members}
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

--Resumable counterpart used by the tick runner. One producer row is scored per route call;
--the stable scan order and comparisons are the same as build_demands above.
local function begin_flow_demand_build(work, flow)
    local id = flow_id_of(flow)
    if not id then return {flow = flow, done = true} end
    local producers, consumers = {}, {}
    if per_port_demands then
        for _, entry in ipairs(flow.producers or {}) do
            append_port_demands(work, producers, id, step_id_of(entry) == "$external" and "in" or "out", entry,
                share_of(entry), "producer")
        end
        for _, entry in ipairs(flow.consumers or {}) do
            append_port_demands(work, consumers, id, step_id_of(entry) == "$external" and "out" or "in", entry,
                share_of(entry), "consumer")
        end
        if work.collectors and #consumers == 1 and consumers[1].endpoint.position_explicit then
            combine_adjacent_output_hands(work, producers)
        end
    else
        for _, entry in ipairs(flow.producers or {}) do
            local candidates = demand_endpoint_candidates(work, id, step_id_of(entry) == "$external" and "in" or "out", entry)
            producers[#producers + 1] = {endpoint = candidates[1], candidates = candidates, remaining = share_of(entry),
                explicit_port_id = entry and (entry.port_id or entry.port)}
        end
        for _, entry in ipairs(flow.consumers or {}) do
            local candidates = demand_endpoint_candidates(work, id, step_id_of(entry) == "$external" and "out" or "in", entry)
            consumers[#consumers + 1] = {endpoint = candidates[1], candidates = candidates, remaining = share_of(entry),
                explicit_port_id = entry and (entry.port_id or entry.port)}
        end
    end
    if #producers == 0 and #consumers == 0 then
        for _, endpoint in ipairs(work.endpoint_index[id] and work.endpoint_index[id].out or {}) do
            producers[#producers + 1] = {endpoint = endpoint, candidates = {endpoint}, remaining = endpoint.rate_per_second}
        end
        for _, endpoint in ipairs(work.endpoint_index[id] and work.endpoint_index[id]["in"] or {}) do
            consumers[#consumers + 1] = {endpoint = endpoint, candidates = {endpoint}, remaining = endpoint.rate_per_second}
        end
    end
    return {flow = flow, id = id, producers = producers, consumers = consumers,
        producer_index = 1, consumer_index = 1, best = nil, done = false,
        demand_start_index = #work.demands + 1}
end

local function advance_flow_demand_build(work, context)
    if context.done then return true end
    local producers, consumers, flow = context.producers, context.consumers, context.flow
    local producer = producers[context.producer_index]
    if producer then
        local consumer = consumers[context.consumer_index]
        if not consumer then
            context.producer_index, context.consumer_index = context.producer_index + 1, 1
            return false
        end
        if producer.endpoint and producer.remaining > tolerance(producer.remaining) then
            if consumer.endpoint and consumer.remaining > tolerance(consumer.remaining) then
                    local route_cost, chosen_source, chosen_sink = math.huge, nil, nil
                    for _, source_candidate in ipairs(producer.candidates or {}) do
                        for _, sink_candidate in ipairs(consumer.candidates or {}) do
                            local candidate_cost = pairing_route_cost(work, source_candidate, sink_candidate)
                            if candidate_cost < route_cost then route_cost, chosen_source, chosen_sink = candidate_cost, source_candidate, sink_candidate end
                        end
                    end
                    chosen_source, chosen_sink = chosen_source or producer.endpoint, chosen_sink or consumer.endpoint
                    local amount = math.min(producer.remaining, consumer.remaining)
                    local flow_capacity = capacity_for(work, flow)
                    local score = route_cost - math.min(amount, flow_capacity) * 1e-6
                    local entry = {producer = producer, consumer = consumer, producer_index = context.producer_index,
                        consumer_index = context.consumer_index, source = chosen_source, sink = chosen_sink,
                        route_cost = route_cost, score = score, amount = amount}
                    local best = context.best
                    if not best or entry.score < best.score
                        or (entry.score == best.score and tostring(entry.source.port_id) < tostring(best.source.port_id))
                        or (entry.score == best.score and tostring(entry.source.port_id) == tostring(best.source.port_id)
                            and tostring(entry.sink.port_id) < tostring(best.sink.port_id)) then context.best = entry end
            end
        end
        context.consumer_index = context.consumer_index + 1
        return false
    end
    local best = context.best
    if best and best.amount > tolerance(best.amount) then
        work.demands[#work.demands + 1] = {flow = flow, flow_id = context.id, source = best.source, sink = best.sink,
            source_candidates = candidate_first(prioritized_candidates(best.producer.candidates, best.sink), best.source),
            sink_candidates = candidate_first(prioritized_candidates(best.consumer.candidates, best.source), best.sink),
            source_index = 1, sink_index = 1, amount = best.amount, remaining = best.amount,
            pairing_cost = best.route_cost, sink_port_id = best.consumer.explicit_port_id,
            collector_port_ids = best.producer.collector_port_ids,
            collector_members = best.producer.collector_members}
        best.producer.remaining = best.producer.remaining - best.amount
        best.consumer.remaining = best.consumer.remaining - best.amount
        context.producer_index, context.consumer_index, context.best = 1, 1, nil
        return false
    end
    for _, entry in ipairs(producers) do
        if entry.remaining > tolerance(entry.remaining) then
            work.initial_error = {code = "BP_R_PORT_BLOCKED", flow_id = context.id, detail = "producer port is not bound"}
            break
        end
    end
    if not work.initial_error then
        for _, entry in ipairs(consumers) do
            if entry.remaining > tolerance(entry.remaining) then
                work.initial_error = {code = "BP_R_PORT_BLOCKED", flow_id = context.id, detail = "consumer port is not bound"}
                break
            end
        end
    end
    local flow_demands = {}
    for index = context.demand_start_index, #work.demands do
        local demand = work.demands[index]
        demand._build_order = index - context.demand_start_index + 1
        flow_demands[#flow_demands + 1] = demand
    end
    table.sort(flow_demands, function(left, right)
        if left.pairing_cost ~= right.pairing_cost then return left.pairing_cost > right.pairing_cost end
        return left._build_order < right._build_order
    end)
    for index, demand in ipairs(flow_demands) do work.demands[context.demand_start_index + index - 1] = demand end
    context.done = true
    return true
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

local add_allocation

--Placed row belts are part of the block. They exist before route search and remain fixed while
--ordinary demands are connected to their heads and ports.
local function lay_belt_runs(work)
    for _, run in ipairs(work.belt_runs or {}) do
        local capacity, kind = capacity_for(work, {is_fluid = false})
        local direction = run.dir
        for _, tile in ipairs(run.tiles or {}) do
            local key = coordinate_key(tile.x, tile.y)
            if not work.segments_by_cell[key] then
                local segment = {segment_id = next_segment_id(work), kind = kind,
                    capacity_per_second = capacity, allocations = {}, direction = direction, length = 1,
                    fixed = true, belt_run_role = run.role}
                for _, flow_id in ipairs(run.flows or {}) do
                    register_segment_flow(segment, flow_id)
                    for _, demand in ipairs(work.demands or {}) do
                        local endpoint = run.role == "in" and demand.sink or demand.source
                        if not run.synthetic_collector and demand.flow_id == flow_id and endpoint and endpoint.step_id ~= "$external" then
                            add_allocation(segment, flow_id, sink_key(demand.sink, work, demand.sink_port_id), demand.amount)
                        elseif run.synthetic_collector and demand.flow_id == flow_id and endpoint
                            and (tile.x ~= endpoint.x or tile.y ~= endpoint.y) then
                            add_allocation(segment, flow_id, sink_key(demand.sink, work, demand.sink_port_id), demand.amount)
                        end
                    end
                end
                local entity = {id = next_entity_id(work), name = infrastructure(work, kind),
                    position = {x = tile.x + 0.5, y = tile.y + 0.5}, direction = direction, dir = direction,
                    flow_id = run.flows and run.flows[1], segment_id = segment.segment_id, fixed = true}
                work.entities[#work.entities + 1] = entity
                work.segments[#work.segments + 1] = segment
                work.segments_by_cell[key] = segment
                work.entity_by_segment[segment.segment_id] = entity
            end
        end
    end
end

local function segment_allows(work, segment, demand, amount)
    if not segment then return true end
    --A placed row's belt run is part of its block: a demand reaches it only through the row's own head-side
    --or output port, never by joining the run from the side (that puts two flows on one lane).
    if segment.fixed then return false, "occupied" end
    if segment.kind ~= demand.kind then return false, "occupied" end
    local same_flow = segment_has_flow(segment, demand.flow_id)
    if not same_flow then
        if segment.kind == "pipe" then return false, "fluid_mix" end
        if not work.multi_flow_hands or segment_flow_count(segment) >= 2 then return false, "occupied" end
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

--A splitter NEVER turns flow.  It carries items in ONE direction: in at the back of both tiles it covers,
--out at the front of both.  There is no side output, so a branch leaving a trunk does not turn ON the trunk
--cell.  It steps sideways into the splitter's other tile, leaves that tile FORWARD, and turns one tile
--later.  The second tile is therefore one step in the BRANCH direction from the anchor, and the splitter
--keeps the TRUNK's heading.  Measured 2026-09-22 on legalcopilot-dev, the player's real sheet: r:279
--covered (12,19)+(12,20) facing WEST while the copper trunk ran north through (12,21), so the walk went
--12:21 -> 12:19 -> 11:20 and 12:18 was never reached.  The north trunk was orphaned by its own splitter.
local function splitter_branch_cell(x, y, branch_direction)
    local dx, dy = Grid.dir_vector(branch_direction)
    if dx == nil or dy == nil then return nil, nil end
    return x + dx, y + dy
end

local function splitter_can_absorb(segment)
    return segment ~= nil and segment.kind == "belt" and not segment.underground and not segment.splitter
end

--A laid tile is a splitter anchor only when its physical feed is straight.  Source
--ports are the sole exception: an inserter can feed an otherwise isolated first tile.
local function splitter_straight_fed(work, x, y, segment, flow_id, source)
    if not segment or segment.kind ~= "belt" or segment.underground or segment.splitter then return false end
    local dx, dy = Grid.dir_vector(segment.direction)
    if dx == nil then return false end
    local feeder = work.segments_by_cell[coordinate_key(x - dx, y - dy)]
    if feeder and segment_has_flow(feeder, flow_id) and feeder.direction == segment.direction
        and (feeder.kind == "belt" or feeder.underground or feeder.splitter) then return true end
    return source ~= nil and source.x == x and source.y == y and feeder == nil
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
        local collector_port = false
        for port_id in pairs(demand.collector_port_ids or {}) do if reserved[port_id] then collector_port = true; break end end
        if not (reserved[source_id] or reserved[sink_id] or collector_port or reserved["flow:" .. tostring(demand.flow_id)]) then
            return blocked("reserved")
        end
    end
    if work.splitter_blocked_cells[coordinate_key(x, y)] then return blocked("underground") end
    local occupant = work.segments_by_cell[coordinate_key(x, y)]
    if occupant ~= nil and occupant ~= segment then
        local same_flow = segment_has_flow(occupant, demand.flow_id)
        local compatible_flow = same_flow or (work.multi_flow_hands and occupant.kind == "belt"
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

local function splitter_branch_allowed(work, demand, x, y, direction, segment, search)
    if segment and segment.splitter then
        --An existing splitter serves a further branch only when it is a real one -- oriented to its own
        --trunk -- and the branch leaves through the tile it already covers.  The old test asked
        --`splitter_direction == direction`, which can only ever match a splitter that TURNS.
        local branch_x, branch_y = splitter_branch_cell(x, y, direction)
        return branch_x ~= nil and segment.splitter_direction == segment.direction
            and segment.splitter_second_key == coordinate_key(branch_x, branch_y)
    end
    if not segment or segment.kind ~= "belt" or not (work.belt and work.belt.splitter) then
        if search then search.saw_blocked = true end
        return false
    end
    local branch_x, branch_y = splitter_branch_cell(x, y, direction)
    if branch_x == nil then
        if search then search.saw_blocked = true end
        return false
    end
    return splitter_cell_allowed(work, demand, branch_x, branch_y, segment, search)
end

local function terminal_splitter_refused(work, x, y, segment, direction)
    if not splitter_can_absorb(segment) then return false end
    --The tile a conversion here would claim is the one the BRANCH steps into, so that is the tile whose
    --reservation decides whether the splitter is refused.  With no branch direction in hand -- the sink's
    --own port tile, where the approach is unknown -- either covered tile being reserved is enough.
    if direction ~= nil then
        local branch_x, branch_y = splitter_branch_cell(x, y, direction)
        return branch_x ~= nil and work.splitter_blocked_cells[coordinate_key(branch_x, branch_y)] == true
    end
    for _, side in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
        if side ~= segment.direction and side ~= Grid.dir_opposite(segment.direction) then
            local branch_x, branch_y = splitter_branch_cell(x, y, side)
            if branch_x ~= nil and work.splitter_blocked_cells[coordinate_key(branch_x, branch_y)] == true then
                return true
            end
        end
    end
    return false
end

--A splitter replaces the two one-tile belts in its footprint.  When the side tile is already part of the
--same-flow trunk, fold that segment into the anchor before publishing the splitter; leaving the old segment
--in the graph would make the physical footprint overlap and would give the old binding a stale segment id.
local function merge_splitter_footprint(work, segment, second_key, demand)
    local occupant = work.segments_by_cell[second_key]
    if occupant == nil or occupant == segment then return segment end
    if occupant.kind ~= "belt" or occupant.underground or occupant.splitter then return nil end
    local same_flow = segment_has_flow(occupant, demand.flow_id)
    local compatible_flow = same_flow or (work.multi_flow_hands and segment_flow_count(occupant) < 2)
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
    --Both endpoint tiles must still be empty at the COMMIT, never only when the search planned them.  A
    --rolled-back append re-runs this creator against a `work` that moved on: measured 2026-09-22 on
    --legalcopilot-dev, the pair entry=9:5 exit=13:5 was laid, rolled back, a splitter was converted onto
    --(9,6)+(9,5) in between, and the pair was then laid a second time straight through the splitter's own
    --body -- published as r:238 over r:264 and caught by tests/test_route_collision.lua RX1.
    for _, cell in ipairs({entry, exit_cell}) do
        local cell_key = coordinate_key(cell.x, cell.y)
        if work.segments_by_cell[cell_key] ~= nil or work.underground_cells[cell_key] then
            --Refusing this pair refuses a CROSSING, never the demand.  The route loop reads these two
            --coordinates, marks the cell so the search stops offering it, and searches again -- exactly the
            --recovery contract 28.5 already gives a refused splitter footprint.
            work.last_route_rejection = work.last_route_rejection or {}
            work.last_route_rejection.x, work.last_route_rejection.y = cell.x, cell.y
            return false, "crossing-occupied"
        end
    end
    --The validator walks the surface graph between paired endpoints. A same-flow belt on a buried
    --middle tile is therefore not a crossing: it is an unpaired underground over its own route.
    local direction = direction_from_step(entry.x, entry.y, exit_cell.x, exit_cell.y)
    local dx, dy = Grid.dir_vector(direction)
    local distance = underground_distance(entry, exit_cell)
    for offset = 1, distance - 1 do
        local middle = work.segments_by_cell[coordinate_key(entry.x + dx * offset, entry.y + dy * offset)]
        if middle and segment_has_flow(middle, demand.flow_id) then return false, "crossing-middle-flow" end
    end
    local family = kind == "pipe" and work.pipe or work.belt
    local name = (family and family.underground) or infrastructure(work, kind)
    local segment = {segment_id = next_segment_id(work), kind = kind,
        capacity_per_second = capacity, allocations = {}, flow_id = demand.flow_id, direction = direction,
        underground = true, length = underground_distance(entry, exit_cell),
        underground_entry_key = coordinate_key(entry.x, entry.y), underground_exit_key = coordinate_key(exit_cell.x, exit_cell.y),
        underground_entry_x = entry.x, underground_entry_y = entry.y,
        underground_exit_x = exit_cell.x, underground_exit_y = exit_cell.y}
    local first_id, second_id = next_entity_id(work), next_entity_id(work)
    --A pipe-to-ground faces its EXPOSED connection (catalog: normal connection at the entity's own direction,
    --underground one opposite). So the entry faces back along the path and the exit faces on along it; both
    --buried sides then face each other. A belt underground faces the travel direction at both ends.
    local paired_exit_direction = direction
    local entry_direction = kind == "pipe" and Grid.dir_opposite(direction) or direction
    local first = {id = first_id, name = name, position = entity_position(entry.x, entry.y),
        direction = entry_direction, dir = entry_direction, flow_id = demand.flow_id,
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
    --An underground endpoint is a real entity on a real tile, so no splitter footprint may later claim it.
    --This creator marked `underground_cells` and never `splitter_blocked_cells`, and it is the creator that
    --lays almost every pair, so almost every pair was invisible to `splitter_cell_allowed`: measured
    --2026-09-22 on legalcopilot-dev, splitter r:238 at (9.5,6) facing EAST published straight on top of
    --underground-belt r:264 at (9.5,5.5), caught by tests/test_route_collision.lua RX1.
    work.splitter_blocked_cells[coordinate_key(entry.x, entry.y)] = true
    work.splitter_blocked_cells[coordinate_key(exit_cell.x, exit_cell.y)] = true
    register_segment_flow(segment, demand.flow_id)
    add_allocation(segment, demand.flow_id, sink_key(demand.sink, work, demand.sink_port_id), amount)
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
            if segment.kind == "pipe" then
                --A pipe network has no direction: fluid reaches every tile it touches. A plain pipe joins all
                --four neighbours; a pipe-to-ground joins only its partner and the one tile its exposed side
                --faces (behind the entry, ahead of the exit, along the span's travel direction).
                local x, y = coordinate_from_key(key)
                local function exposed_key(other)
                    local dx, dy = Grid.dir_vector(other.direction)
                    if dx == nil then return nil end
                    if other.underground_entry_x ~= nil then
                        return coordinate_key(other.underground_entry_x - dx, other.underground_entry_y - dy),
                            coordinate_key(other.underground_exit_x + dx, other.underground_exit_y + dy)
                    end
                    return nil
                end
                if segment.underground then
                    --A pipe network is undirected: enqueue both recorded endpoints from either half. A normal
                    --path can encounter an endpoint through a shared cell whose segment reference was retained
                    --from the earlier route; selecting the partner by entry/exit identity then misses the new
                    --exit. Entity headings are also exposed-side headings, not the pair's fluid direction.
                    enqueue(segment.underground_entry_key)
                    enqueue(segment.underground_exit_key)
                    local behind, ahead = exposed_key(segment)
                    enqueue(key == segment.underground_entry_key and behind or ahead)
                else
                    for _, direction in ipairs(DIRECTIONS) do
                        local dx, dy = Grid.dir_vector(direction)
                        local next_key = coordinate_key(x + dx, y + dy)
                        local other = work.segments_by_cell[next_key]
                        if other and other.kind == "pipe" and other.underground then
                            local behind, ahead = exposed_key(other)
                            if (next_key == other.underground_entry_key and behind == key)
                                or (next_key == other.underground_exit_key and ahead == key) then enqueue(next_key) end
                        elseif other and other.kind == "pipe" then
                            enqueue(next_key)
                        end
                    end
                end
            elseif segment.underground then
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

--Every tile of the path this search is building, from `key` back to its root.  None of them is laid yet
--except the ones the path RIDES on an existing run, so a walk over laid segments alone cannot see a ring
--the path closes through itself.
local function search_path_tiles(search, key)
    local tiles = {}
    while key do
        local point = search.points[key]
        if point then tiles[coordinate_key(point.x, point.y)] = true end
        key = search.parent[key]
    end
    return tiles
end

--A ring is a belt whose items come back to a tile they already passed.  Items leaving onto (x, y) flow on
--down the laid same-flow chain; if that chain, or (x, y) itself, touches ANY tile of this path, the path
--closes a ring.  Checking only the root missed one: measured 2026-09-23 on legalcopilot-dev, the science
--path rooted at (14,0) rode the laid belt (15,0), dived round through (17,2)->(17,7) and (15,7)->(15,2),
--and aimed its last belt at (15,1) back into (15,0) -- a 12-tile ring, r:320..r:330.
local function downstream_reaches_root(work, search, from_key, x, y)
    local own = search_path_tiles(search, from_key)
    if own[coordinate_key(x, y)] then return true end
    local _, tiles = route_chain_walk(work, {x = x, y = y}, nil, search.demand.flow_id)
    for _, key in ipairs(tiles) do if own[key] then return true end end
    return false
end

--The search path is also the router's own directed witness.  A path that merely visited the sink is not a
--route to it, and a newly added branch must not break an earlier binding that shared its trunk.
local function route_chain_reaches_sink(work, demand, path)
    if type(path) ~= "table" or #path == 0 or not demand.sink then return false end
    local last = path[#path]
    if (last.x ~= demand.sink.x or last.y ~= demand.sink.y) and demand.kind ~= "pipe" then return false end
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

local function bury_candidate(work, x, y, cross_direction, allow_port_adjacent)
    local dx, dy = Grid.dir_vector(cross_direction)
    local rdx, rdy = Grid.dir_vector(Grid.rotate_dir(cross_direction, 12))
    if not rdx then return nil end
    local function seg(px, py) return work.segments_by_cell[coordinate_key(px, py)] end
    local bx, by = x - rdx, y - rdy
    local ax, ay = x + rdx, y + rdy
    local BBx, BBy, AAx, AAy = bx - rdx, by - rdy, ax + rdx, ay + rdy
    local b, c, a = seg(bx, by), seg(x, y), seg(ax, ay)
    if not b or not c or not a or b.underground or c.underground or a.underground
        or b.splitter or c.splitter or a.splitter or b.kind ~= "belt" or c.kind ~= "belt" or a.kind ~= "belt"
        or b.direction ~= Grid.dir_from_vector(rdx, rdy) or c.direction ~= b.direction or a.direction ~= b.direction then return nil end
    local function same_flows(s)
        local ids = {}
        for _, allocation in ipairs(s.allocations or {}) do ids[allocation.flow_id] = true end
        return ids
    end
    local flows = same_flows(b)
    for _, s in ipairs({c, a}) do
        local other = same_flows(s)
        for id in pairs(flows) do if not other[id] then return nil end end
        for id in pairs(other) do if not flows[id] then return nil end end
    end
    local function port_or_obstacle(px, py)
        local key = coordinate_key(px, py)
        if work.port_cells and work.port_cells[key] ~= nil then return true end
        if not allow_port_adjacent then
            for _, demand in ipairs(work.demands or {}) do
                for _, endpoint in ipairs({demand.source, demand.sink}) do
                    if endpoint and math.abs(endpoint.x - px) + math.abs(endpoint.y - py) <= 2 then return true end
                end
            end
        end
        return static_owner(work, px, py) ~= nil
    end
    for _, p in ipairs({{bx,by},{x,y},{ax,ay}}) do if port_or_obstacle(p[1],p[2]) then return nil end end
    if SideFeed.into(work.segments_by_cell, coordinate_key, {{bx,by},{x,y},{ax,ay}}, b.direction) then return nil end
    local feed = seg(BBx, BBy)
    if not feed then return nil end
    if feed.underground then
        if feed.underground_exit_key ~= coordinate_key(BBx,BBy) or feed.direction ~= b.direction then return nil end
    elseif feed.splitter then
        if feed.splitter_direction ~= b.direction then return nil end
    elseif feed.direction ~= b.direction then return nil end
    local after = seg(AAx, AAy)
    if not after or after.direction ~= b.direction then return nil end
    local after_flows = same_flows(after)
    for id in pairs(flows) do if not after_flows[id] then return nil end end
    local reach = math.max(0, math.floor(finite(work.belt and work.belt.underground_max_distance, 0)))
    for _, s in ipairs(work.segments) do
        if s.underground and s.direction == b.direction then
            for _, p in ipairs({{bx,by},{ax,ay}}) do
                if not s.underground_entry_x or not s.underground_exit_x
                    or not s.underground_entry_y or not s.underground_exit_y then return nil end
                if (p[1] == s.underground_entry_x and p[2] == s.underground_entry_y)
                    or (p[1] == s.underground_exit_x and p[2] == s.underground_exit_y) then return nil end
                if s.underground_entry_y == p[2] and s.underground_exit_y == p[2]
                    and math.abs(s.underground_entry_x-p[1]) <= reach and math.abs(s.underground_exit_x-p[1]) <= reach then return nil end
                if s.underground_entry_x == p[1] and s.underground_exit_x == p[1]
                    and math.abs(s.underground_entry_y-p[2]) <= reach and math.abs(s.underground_exit_y-p[2]) <= reach then return nil end
            end
        end
    end
    return {x=x,y=y,entry_x=bx,entry_y=by,exit_x=ax,exit_y=ay,direction=b.direction,
        source_ids={b.segment_id,c.segment_id,a.segment_id},cross_direction=cross_direction}
end

local function apply_bury(work, candidate, allow_port_adjacent)
    local fresh = bury_candidate(work, candidate.x, candidate.y, candidate.cross_direction, allow_port_adjacent)
    if not fresh then return false end
    local b = work.segments_by_cell[coordinate_key(fresh.entry_x,fresh.entry_y)]
    local c = work.segments_by_cell[coordinate_key(fresh.x,fresh.y)]
    local a = work.segments_by_cell[coordinate_key(fresh.exit_x,fresh.exit_y)]
    local old = {[b.segment_id]=true,[c.segment_id]=true,[a.segment_id]=true}
    local segment = {segment_id=next_segment_id(work),kind="belt",capacity_per_second=b.capacity_per_second,
        allocations={},flow_id=b.flow_id,flow_ids=b.flow_ids,direction=b.direction,underground=true,length=2,
        underground_entry_x=fresh.entry_x,underground_entry_y=fresh.entry_y,
        underground_exit_x=fresh.exit_x,underground_exit_y=fresh.exit_y,
        underground_entry_key=coordinate_key(fresh.entry_x,fresh.entry_y),underground_exit_key=coordinate_key(fresh.exit_x,fresh.exit_y)}
    local allocation_by_key = {}
    for _, old_segment in ipairs({b,c,a}) do
        for _, al in ipairs(old_segment.allocations or {}) do
            local key = tostring(al.flow_id) .. "\0" .. tostring(al.sink)
            local existing = allocation_by_key[key]
            if existing then existing.rate_per_second = math.max(existing.rate_per_second, al.rate_per_second)
            else
                local copy = {flow_id=al.flow_id,sink=al.sink,rate_per_second=al.rate_per_second}
                segment.allocations[#segment.allocations+1] = copy
                allocation_by_key[key] = copy
            end
        end
    end
    local kept={}
    for _, s in ipairs(work.segments) do if old[s.segment_id] then s._route_removed=true else kept[#kept+1]=s end end
    local underground_name = work.belt and work.belt.underground or infrastructure(work,"belt")
    local first, second = {id=next_entity_id(work),name=underground_name,position=entity_position(fresh.entry_x,fresh.entry_y),
        direction=segment.direction,dir=segment.direction,flow_id=segment.flow_id,ug_role="input",type="input",segment_id=segment.segment_id},
        {id=next_entity_id(work),name=underground_name,position=entity_position(fresh.exit_x,fresh.exit_y),
        direction=segment.direction,dir=segment.direction,flow_id=segment.flow_id,ug_role="output",type="output",segment_id=segment.segment_id}
    first.ug_pair_id, second.ug_pair_id = second.id, first.id
    for _, e in ipairs(work.entities) do if old[e.segment_id] then e._route_removed=true end end
    for id in pairs(old) do work.entity_by_segment[id] = nil end
    work.entities[#work.entities + 1] = first
    work.entities[#work.entities + 1] = second
    kept[#kept+1]=segment; work.segments=kept
    for _, key in ipairs({coordinate_key(fresh.entry_x,fresh.entry_y),coordinate_key(fresh.x,fresh.y),coordinate_key(fresh.exit_x,fresh.exit_y)}) do
        work.segments_by_cell[key]=nil
    end
    work.segments_by_cell[segment.underground_entry_key]=segment; work.segments_by_cell[segment.underground_exit_key]=segment
    work.entity_by_segment[segment.segment_id]=first
    for _, id in ipairs({segment.underground_entry_key,segment.underground_exit_key}) do work.underground_cells[id]=true;work.splitter_blocked_cells[id]=true end
    for _, binding in ipairs(work.bindings) do if old[binding.segment_id] then binding.segment_id=segment.segment_id end end
    return true
end

local function append_collector_member_bindings(work, demand, sink, segment_id)
    for _, member in ipairs(demand.collector_members or {}) do
        if member.endpoint.port_id ~= demand.source.port_id then
            work.bindings[#work.bindings + 1] = {source_port_id = member.endpoint.port_id,
                sink_port_id = demand.binding_sink_port_id or demand.sink.port_id,
                sink = sink, flow_id = demand.flow_id, segment_id = segment_id, rate_per_second = member.amount}
        end
    end
end

local function collector_source_rate(demand, total)
    for _, member in ipairs(demand.collector_members or {}) do
        if member.endpoint.port_id == demand.source.port_id then return member.amount end
    end
    return total
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
    local sink = sink_key(demand.sink, work, demand.sink_port_id)
    local first_segment
    local allocated_segments = {}
    local index = 0
    --A planned bury is applied before the crossing flow is materialised; commit repeats the full eligibility
    --check because earlier route commits may have changed any of its five witness tiles.
    for _, candidate in ipairs(path.buries or {}) do
        local ok = apply_bury(work, candidate)
        if not ok then
            work.last_route_rejection = work.last_route_rejection or {}
            work.last_route_rejection.x, work.last_route_rejection.y = candidate.x, candidate.y
            work.last_route_rejection.bury = true
            return reject("crossing-occupied")
        end
    end
    while index < #path do
        index = index + 1
        local cell = path[index]
        local next_cell = path[index + 1]
        local ridden = is_crossing_step(cell, next_cell) and work.segments_by_cell[coordinate_key(cell.x, cell.y)]
        local here_key = coordinate_key(cell.x, cell.y)
        local next_key = next_cell and coordinate_key(next_cell.x, next_cell.y)
        local same_pair_forward = ridden and ridden.underground
            and ridden.underground_entry_key == here_key and ridden.underground_exit_key == next_key
        local same_pair_reverse = demand.kind == "pipe" and ridden and ridden.underground
            and ridden.underground_exit_key == here_key and ridden.underground_entry_key == next_key
        if same_pair_forward or same_pair_reverse then
            --An existing same-flow underground pair is one edge. Belts ride it in their recorded direction;
            --pipes have no direction, so the reverse endpoint order is the same connected fluid network.
            if not allocated_segments[ridden.segment_id] then
                local allowed, reason = segment_allows(work, ridden, demand, amount)
                if not allowed then return reject(reason or "occupied") end
                register_segment_flow(ridden, demand.flow_id)
                add_allocation(ridden, demand.flow_id, sink, amount)
                allocated_segments[ridden.segment_id] = true
            end
            first_segment = first_segment or ridden
            index = index + 1
        elseif is_crossing_step(cell, path[index + 1]) then
            local crossed, reason, segment = append_crossing(work, demand, cell, path[index + 1], amount)
            if not crossed then return reject(reason) end
            first_segment = first_segment or segment
            index = index + 1
        else
        local next_cell = path[index + 1] or path[index - 1] or cell
        local direction = direction_from_step(cell.x, cell.y, next_cell.x, next_cell.y)
        if index == #path and #path > 1 then direction = direction_from_step(path[index - 1].x, path[index - 1].y, cell.x, cell.y) end
        --A curve onto a one-flow rear port: the last belt faces the port's heading, into the row's head.
        --A row feed port admits a side arrival only through the improve pass's curve freedom, so commit (which may run
        --after that pass cleared its flag) turns such a last belt into the port's heading unconditionally.
        if index == #path and demand.sink and (demand.sink.rear_curve or demand.sink.feed_curve)
            and demand.sink.travel_dir ~= nil
            and cell.x == demand.sink.x and cell.y == demand.sink.y then direction = demand.sink.travel_dir end
        --A cell has TWO directions and they decide different things.  `incoming` is how the items arrived,
        --`outgoing` is how they leave.  Arriving at a run already laid from one of its SIDES is a merge and
        --builds nothing; the run keeps its own heading and carries the items on.  LEAVING a run sideways is
        --the only thing that needs a splitter.  Judging both with one direction converted a merge into a
        --splitter it could never place: measured 2026-09-22 on legalcopilot-dev, item/copper-plate
        --(7,24) -> (12,11) died BP_R_NO_PATH because the sink tile's branch cell (13,11) holds an inserter.
        local incoming = index > 1 and direction_from_step(path[index - 1].x, path[index - 1].y, cell.x, cell.y) or nil
        local outgoing = path[index + 1]
            and direction_from_step(cell.x, cell.y, path[index + 1].x, path[index + 1].y) or nil
        local key = coordinate_key(cell.x, cell.y)
        local segment = work.segments_by_cell[key]
        if segment and direction == nil and segment_has_flow(segment, demand.flow_id) then
            --Contract 28.8: the trunk already runs through this sink's own port tile, so the branch is one
            --cell long and lays nothing.  The sink takes its allocation on the belt that is already there,
            --and its binding is honest.  Never re-derive a direction from a step of length zero.
            direction = segment.direction
        end
        if segment then
            if segment.fixed and outgoing ~= nil and outgoing ~= segment.direction then return reject("occupied") end
            --A path may END on a splitter's second tile: that is where the sink's own port sits, and an
            --inserter picks from the tile, never from a tile further on.  Only LEAVING the body needs the
            --splitter's own heading.  Demanding it on arrival refused the branch outright: measured
            --2026-09-22 on legalcopilot-dev, tests/test_route.lua R6, intermediate-in at (4,3) died
            --BP_R_NO_PATH with the splitter at (4,2)+(4,3) already legal.
            local splitter_continuation = segment.splitter and key == segment.splitter_second_key
                and (outgoing == nil or outgoing == segment.splitter_direction)
            if not allocated_segments[segment.segment_id] then
                local allowed, reason = segment_allows(work, segment, demand, amount)
                if not allowed then return reject(reason or "occupied") end
            end
            if segment.splitter and key == segment.splitter_second_key and not splitter_continuation then return reject("occupied") end
            --A sink is reached by entering its port tile.  Its existing belt need not point out of that tile,
            --but only when the otherwise required splitter footprint is reserved by an underground endpoint.
            --A pipe branches at any tile of its own network: a T of pipe is a legal joint, never a splitter.
            local leaves_sideways = segment.kind ~= "pipe" and outgoing ~= nil and outgoing ~= segment.direction
            local rode_the_trunk = incoming == nil or incoming == segment.direction
            if leaves_sideways and rode_the_trunk and not splitter_continuation
                and not terminal_splitter_refused(work, cell.x, cell.y, segment, outgoing) then
                if work.multi_flow_hands and not segment_has_flow(segment, demand.flow_id) then
                    return reject("splitter-footprint")
                end
                --An underground segment owns two coupled endpoints.  It cannot become a splitter: changing
                --the mapped first entity here would leave its partner carrying a different direction.  The
                --allocation may still share the segment, but its published pair keeps the direction it was built
                --for.  Surface belts retain their existing splitter behaviour.
                    if not splitter_can_absorb(segment)
                        or not splitter_straight_fed(work, cell.x, cell.y, segment, demand.flow_id, demand.source)
                        or not splitter_branch_allowed(work, demand, cell.x, cell.y, outgoing, segment) then
                        work.last_route_rejection = work.last_route_rejection or {}
                        work.last_route_rejection.x, work.last_route_rejection.y = cell.x, cell.y
                        work.last_route_rejection.direction = outgoing
                        work.last_route_rejection.segment = segment.segment_id
                        work.last_route_rejection.splitter = segment.splitter
                        work.last_route_rejection.segment_direction = segment.direction
                        local second_x, second_y = splitter_branch_cell(cell.x, cell.y, outgoing)
                        work.last_route_rejection.second = second_x and (tostring(second_x) .. ":" .. tostring(second_y))
                        work.last_route_rejection.second_segment = second_x and work.segments_by_cell[coordinate_key(second_x, second_y)]
                            and work.segments_by_cell[coordinate_key(second_x, second_y)].segment_id
                        return reject("splitter-footprint")
                    end
                    local entity = work.entity_by_segment[segment.segment_id]
                    --The splitter keeps the TRUNK's heading, never the new demand's.  Orienting it to the
                    --demand severed the trunk feeding it: the input side turned to face the branch, so every
                    --tile of the trunk beyond the splitter was orphaned.  The second tile is then literally
                    --the NEXT path cell, which is what makes contract 28.5 true by construction -- the
                    --search and the materializer cannot disagree about a tile the path already names.
                    local splitter_direction = segment.direction
                    local second_x, second_y = splitter_branch_cell(cell.x, cell.y, outgoing)
                    local second_key = coordinate_key(second_x, second_y)
                    local side_segment = work.segments_by_cell[second_key]
                    if not merge_splitter_footprint(work, segment, second_key, demand) then
                        work.last_route_rejection = work.last_route_rejection or {}
                        work.last_route_rejection.x, work.last_route_rejection.y = cell.x, cell.y
                        return reject("splitter-footprint")
                    end
                    if first_segment == side_segment then first_segment = segment end
                    local side_x, side_y = second_x - cell.x, second_y - cell.y
                    --entity_position adds half a tile to EACH axis already, so the x term took it twice
                    --and every splitter landed half a tile east of its own footprint.  Measured
                    --2026-09-22 on legalcopilot-dev, first candidate of the player's real sheet:
                    --r:825 dir=4 side=(0,1) anchor (12,8) delivered (13,9) against a true (12.5,9.0),
                    --r:846 dir=0 side=(1,0) anchor (10,41) delivered (11.5,41.5) against (11.0,41.5).
                    --Three overlapping pairs, and BP_V_COLLISION went 0 to 60 on the census.
                    entity.position = entity_position(cell.x + side_x / 2, cell.y + side_y / 2)
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
            local already_allocated = false
            for _, allocation in ipairs(segment.allocations or {}) do
                if allocation.flow_id == demand.flow_id and allocation.sink == sink then already_allocated = true; break end
            end
            if not already_allocated then add_allocation(segment, demand.flow_id, sink, amount) end
            allocated_segments[segment.segment_id] = true
        end
        first_segment = first_segment or segment
        end
    end
    local chain_reaches_sink = route_chain_reaches_sink(work, demand, path)
    if not chain_reaches_sink then return reject("route-discontinuous") end
    if first_segment then
        work.bindings[#work.bindings + 1] = {source_port_id = demand.source.port_id, sink_port_id = demand.binding_sink_port_id or demand.sink.port_id,
            sink = sink, flow_id = demand.flow_id, segment_id = first_segment.segment_id,
            rate_per_second = collector_source_rate(demand, amount)}
        append_collector_member_bindings(work, demand, sink, first_segment.segment_id)
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
        underground = true, explicit = true, length = candidate.distance,
        underground_entry_key = coordinate_key(candidate.source.x, candidate.source.y),
        underground_exit_key = coordinate_key(candidate.sink.x, candidate.sink.y),
        underground_entry_x = candidate.source.x, underground_entry_y = candidate.source.y,
        underground_exit_x = candidate.sink.x, underground_exit_y = candidate.sink.y}
    register_segment_flow(segment, demand.flow_id)
    local first_id, second_id = next_entity_id(work), next_entity_id(work)
    local name = infrastructure(work, kind)
    if kind == "pipe" then name = (work.pipe and (work.pipe.underground or work.pipe.pipe)) or name
    else name = (work.belt and (work.belt.underground or work.belt.belt)) or name end
    local exit_direction = candidate.direction
    local entry_direction = kind == "pipe" and Grid.dir_opposite(candidate.direction) or candidate.direction
    local first = {id = first_id, name = name, position = entity_position(candidate.source.x, candidate.source.y),
        direction = entry_direction, dir = entry_direction, flow_id = demand.flow_id,
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
    --Same pair of facts, the other way round: this creator marked only the splitter guard, so a later
    --crossing could dive through a tile a pair already owns.
    work.underground_cells[coordinate_key(candidate.source.x, candidate.source.y)] = true
    work.underground_cells[coordinate_key(candidate.sink.x, candidate.sink.y)] = true
    local sink = sink_key(demand.sink, work, demand.sink_port_id)
    add_allocation(segment, demand.flow_id, sink, amount)
    work.bindings[#work.bindings + 1] = {source_port_id = demand.source.port_id, sink_port_id = demand.sink.port_id,
        sink = sink, flow_id = demand.flow_id, segment_id = segment.segment_id,
        rate_per_second = collector_source_rate(demand, amount)}
    append_collector_member_bindings(work, demand, sink, segment.segment_id)
    return true
end

local function path_cell_free(work, demand, x, y, move_direction, is_target, amount, search)
    local touch_ok = search and search.touch_ok
    if search then search.touch_refused = false end
    if not touch_ok and FluidTouch.path_blocked(work.segments_by_cell, coordinate_key, demand, x, y) then
        search.saw_fluid_mix = true; search.touch_refused = true; return false
    end
    if not touch_ok and demand.kind == "pipe" and work.port_cells then
        for _, d in ipairs(DIRECTIONS) do
            local ddx, ddy = Grid.dir_vector(d)
            local r = work.port_cells[coordinate_key(x + ddx, y + ddy)]
            if r and r._fluid_front then
                for fid in pairs(r._fluid_front) do
                    if fid ~= demand.flow_id then search.saw_fluid_mix = true; search.touch_refused = true; return false end
                end
            end
            if r and r._crowded and r._port_owners and not r["flow:" .. tostring(demand.flow_id)] then
                search.saw_fluid_mix = true; search.touch_refused = true; return false
            end
        end
    end
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
    --On the frozen gray + magenta sheet (legalcopilot-dev, 2026-09-27), paths ended at (36,49) and
    --(66,40) from the buried side of pairs (26,49)->(36,49) and (66,30)->(66,40). A pipe-to-ground's
    --exposed side joins normal pipe; its buried side joins only its partner.
    if segment and demand.kind == "pipe" and segment.kind == "pipe" and segment.underground
        and move_direction ~= nil and segment.underground_entry_x ~= nil then
        local mdx, mdy = Grid.dir_vector(move_direction)
        local sdx, sdy = Grid.dir_vector(segment.direction)
        if mdx ~= nil and sdx ~= nil then
            local fx, fy = x - mdx, y - mdy
            local here = coordinate_key(x, y)
            local ok
            if here == segment.underground_entry_key then
                ok = (fx == segment.underground_entry_x - sdx and fy == segment.underground_entry_y - sdy)
                    or coordinate_key(fx, fy) == segment.underground_exit_key
            else
                ok = (fx == segment.underground_exit_x + sdx and fy == segment.underground_exit_y + sdy)
                    or coordinate_key(fx, fy) == segment.underground_entry_key
            end
            if not ok then search.saw_blocked = true; return false end
        end
    end
    if segment then
        --An underground input consumes its feed into the pair; stepping onto it from the side cannot continue.
        if segment.underground and segment.underground_entry_key == coordinate_key(x, y)
            and not (search and search.allow_ride and demand.kind ~= "pipe" and move_direction == segment.direction
                and segment_has_flow(segment, demand.flow_id)) then
            search.saw_blocked = true
            return false
        end
        local splitter_continuation = segment.splitter and segment.splitter_second_key == coordinate_key(x, y)
            and (is_target or segment.splitter_direction == move_direction)
        if segment.splitter and not splitter_continuation and move_direction ~= segment.direction then
            search.saw_blocked = true
            return false
        end
        local allowed, reason = segment_allows(work, segment, demand, amount)
        if not allowed then
            if reason == "capacity" then search.saw_capacity = true end
            if reason == "occupied" then search.saw_blocked = true end
            --Only a foreign pipe that actually DENIED the step is fluid mixing. Setting the flag on every
            --pipe cell the search merely looked at made an item flow report BP_R_FLUID_MIX, so the belt's
            --real blocker was hidden behind somebody else's pipe.
            --A BELT stopped by a pipe is merely blocked: kind mismatch already said "occupied". Flagging it as
            --fluid mixing both misnamed the failure and skipped the direction-order retries below.
            if not segment_has_flow(segment, demand.flow_id) and segment.kind == "pipe" and demand.kind == "pipe" then search.saw_fluid_mix = true end
            return false
        end
        local terminal_refused = is_target and terminal_splitter_refused(work, x, y, segment, move_direction)
        if move_direction ~= nil and segment.direction ~= move_direction and not terminal_refused then
            if not splitter_continuation then
                --A belt takes items from behind and from its TWO SIDES, never from the tile it faces.  So a
                --side entry into a run already laid is a MERGE, it is legal, and it builds nothing: three
                --furnaces feeding one gear machine is exactly that shape, and refusing it cost 3
                --BP_R_NO_PATH on the player's sheet, measured 2026-09-22 on legalcopilot-dev.  Only the
                --head-on entry is impossible.  TAKING items off a run is the other half, and that is not
                --decided here: it is the body jump in `search_step`, because a splitter never turns flow.
                --Only belts have a facing head; pipes carry fluid through every touching side, including head-on.
                if demand.kind ~= "pipe" and move_direction == Grid.dir_opposite(segment.direction) then
                    search.saw_blocked = true
                    return false
                end
                --On the frozen 154x154 gray + magenta route (85,39), 2026-09-27 on legalcopilot-dev,
                --the first flow lays a belt through the shared hand and the second flow must side-join there.
                local shared_cell = is_target and work.port_cells and work.port_cells[coordinate_key(x, y)]
                local shared_hand = shared_cell and shared_cell[demand.sink and demand.sink.port_id]
                    and segment.flow_id ~= nil and shared_cell["flow:" .. tostring(segment.flow_id)]
                if work.multi_flow_hands and not segment_has_flow(segment, demand.flow_id) and not search.merge_target
                    and not shared_hand then
                    search.saw_blocked = true
                    return false
                end
                if demand.crossing_blocked and demand.crossing_blocked[coordinate_key(x, y)] then
                    search.saw_blocked = true
                    return false
                end
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
    --On the frozen gray + magenta sheet (2026-09-27), iron stick's route returned to (123,18) with another
    --heading. The search may represent that state, but one committed path cannot place two entities on that tile.
    if search.demand.no_self_cross and parent_key ~= nil then
        local walk = parent_key
        while walk do
            local point = search.points[walk]
            if point and point.x == x and point.y == y then return false end
            if walk == search.source_key then break end
            walk = search.parent[walk]
        end
    end
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
        directions = DIRECTION_ORDERS[order_index], order_index = order_index, closed = {},
        --Riding a laid same-flow underground: first routing only as a fallback (the demand's own flag), and in
        --the keep-if-cheaper re-route pass (`allow_bury` marks it).  Refused in that pass, a trial that needed
        --the ride searched the whole grid before failing: player-inserter-10s first-verdict tidy 18 s -> 77 s.
        allow_ride = demand.allow_ride == true or work.allow_bury == true}
    local seed_heading = demand.source.travel_dir or 0
    if demand.strict_branch and demand.kind ~= "pipe" then
        local source_segment = work.segments_by_cell[coordinate_key(demand.source.x, demand.source.y)]
        if source_segment and source_segment.kind == "belt" and not source_segment.underground
            and source_segment.direction ~= nil then
            --BC2: on tile 1 of the frozen gray + magenta sheet (2026-09-27), this coal demand starts on its own
            --source belt; follow its heading so a strict retry cannot turn off the source tile without a splitter.
            seed_heading = source_segment.direction
        end
    end
    search.source_key = state_key(demand.source.x, demand.source.y, seed_heading, demand.kind, 0)
    search.points[search.source_key] = {x = demand.source.x, y = demand.source.y}
    search.best[search.source_key] = 0
    search.parent[search.source_key] = nil
    heap_push(search, {key = search.source_key, x = demand.source.x, y = demand.source.y,
        direction = seed_heading, mode = 0, cost = 0,
        priority = heuristic(search, demand.source.x, demand.source.y)})
    local source_segment = work.segments_by_cell[coordinate_key(demand.source.x, demand.source.y)]
    if source_segment then
        local allowed, reason = segment_allows(work, source_segment, demand, amount)
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
            if x ~= nil and segment and segment_allows(work, segment, demand, amount)
                and not (segment.kind == "pipe" and segment.underground) then
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
    path.buries = {}
    key = target_key
    while key do
        if search.buries and search.buries[key] then path.buries[#path.buries + 1] = search.buries[key] end
        key = search.parent[key]
    end
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

local function crowded_demand(work, demand)
    local cb = work.crowded_blocks or {}
    return demand.kind == "pipe"
        and ((demand.source and cb[demand.source.block_id]) or (demand.sink and cb[demand.sink.block_id])) and true or false
end

local function crossing_targets(work, demand, search, current, direction, amount)
    local reach = underground_reach(work, demand)
    if reach < 2 then return {} end
    --An underground entrance fed from its side takes only the lane on its far side; the validator refuses the
    --shape whenever the feeding lane lands on the blocked half (BP_V_UNDERGROUND_SIDELOAD_BLOCKED), and a map-edge
    --belt carries both lanes. Route and tidy therefore dive straight on only (slow hands, 2.31/s, 2026-09-25).
    if current.direction ~= nil and current.direction ~= direction then return {} end
    local function faces_ok(x, y)
        if demand.kind ~= "pipe" then return true end
        local reserved = work.port_cells and work.port_cells[coordinate_key(x, y)]
        if not (reserved and reserved._port_owners) then return true end
        local fluid = false
        for key in pairs(reserved) do
            if type(key) == "string" and key:sub(1, 11) == "flow:fluid/" then fluid = true; break end
        end
        return not fluid or (reserved._fluid_dir ~= nil and reserved._fluid_dir == direction)
    end
    if not faces_ok(current.x, current.y) then return {} end
    local current_key = coordinate_key(current.x, current.y)
    if work.segments_by_cell[current_key] or work.underground_cells[current_key] then return {} end
    local dx, dy = Grid.dir_vector(direction)
    local targets, blocked_middle = {}, false
    for distance = 2, reach do
        local middle_x, middle_y = current.x + dx * (distance - 1), current.y + dy * (distance - 1)
        if not inside_grid(work, middle_x, middle_y) then break end
        --A pair may not run under another pair of its own family: in the engine the two would connect to each
        --other instead of passing.
        if work.underground_cells[coordinate_key(middle_x, middle_y)] then break end
        --Free middles do not end a possible longer crossing; a crossing must cover at least one blocked tile.
        local middle_segment = work.segments_by_cell[coordinate_key(middle_x, middle_y)]
        if middle_segment and segment_has_flow(middle_segment, demand.flow_id) then break end
        if not path_cell_free(work, demand, middle_x, middle_y, direction, false, amount, PROBE) then
            blocked_middle = true
        end
        local x, y = current.x + dx * distance, current.y + dy * distance
        if not inside_grid(work, x, y) then break end
        local key = coordinate_key(x, y)
        local underground_key = state_key(x, y, direction, demand.kind, 1)
        --No `search.best[underground_key]` refusal here: an exit already reached may be reached again more
        --cheaply, and `enqueue_state` keeps the cheaper.  Refusing it lost the straight feed the player asked
        --for: measured 2026-09-23 on legalcopilot-dev, science 2 reached (13,2) first through a side-fed dive
        --at (13,7) costing 20, so the straight feed (14,8) W, (13,8) N, dive at (13,7), costing 13, was never
        --offered.
        local exit_free = false
        if blocked_middle and not work.segments_by_cell[key] and not work.underground_cells[key] and faces_ok(x, y) then
            if crowded_demand(work, demand) then search.touch_ok = true end
            exit_free = path_cell_free(work, demand, x, y, direction, x == demand.sink.x and y == demand.sink.y, amount, search)
            search.touch_ok = nil
        end
        if exit_free then
            targets[#targets + 1] = {x = x, y = y, distance = distance}
        end
    end
    return targets
end

--A tile that is ANOTHER port of this same flow: a run passing it serves that port for free (contract 28.8).
local function same_flow_port_tile(work, demand, x, y)
    local reserved = work.port_cells and work.port_cells[coordinate_key(x, y)]
    if not (reserved and reserved["flow:" .. tostring(demand.flow_id)]) then return false end
    for owner, _ in pairs(reserved._port_owners or {}) do
        local owner_id = type(owner) == "table" and (owner.port_id or owner.id) or owner
        if owner_id ~= demand.sink.port_id and owner_id ~= demand.source.port_id then return true end
    end
    return false
end

local function transition_cost(work, demand, x, y, direction, previous_direction, mode, distance, amount)
    local collector_alignment = demand.collector_members and demand.source.x == demand.sink.x
        and y < demand.source.y and y > demand.sink.y and x ~= demand.source.x and 80 or 0
    if demand.collector_members and demand.source.x == demand.sink.x then
        if y < demand.sink.y then collector_alignment = collector_alignment + 200
        elseif y == demand.sink.y and x ~= demand.sink.x then collector_alignment = collector_alignment + 5 end
    end
    if mode == 1 then
        --Both endpoints and the underground span are real cost.  Crossings also carry the witness overhead.
        --A pair SURFACING on another same-flow port tile earns the same pass-through credit a plain step
        --does.  Without it, science machine 3's dive (6,8)->(6,3) onto machine 1's output tile tied with a
        --walk east along y=9, lost the tie, and machine 1 then laid its own second long run: measured
        --2026-09-23 on legalcopilot-dev, 6 entities above the player's hand fix.
        return 2 + distance + 2 - (same_flow_port_tile(work, demand, x, y) and 0.5 or 0) + collector_alignment
    end
    local segment = work.segments_by_cell[coordinate_key(x, y)]
    local cost = 1
    if same_flow_port_tile(work, demand, x, y) then cost = 0.5 end
    if segment and segment_has_flow(segment, demand.flow_id)
        and segment.kind == demand.kind
        and segment_total(segment) + amount <= segment.capacity_per_second + tolerance(segment.capacity_per_second) then
        cost = 0.2
    elseif segment and segment.kind == demand.kind and work.multi_flow_hands then
        --A foreign belt is a valid two-lane continuation only when it is the available route.  Price it above
        --a free tile so a same-flow seeded trunk wins when both are possible; otherwise multi-flow admission
        --would turn a straight branch into a cheaper foreign-flow fork.
        cost = 2
    end
    if previous_direction ~= nil and previous_direction ~= 0 and previous_direction ~= direction then cost = cost + 1 end
    if segment and segment.direction ~= direction then cost = cost + 2 end
    if segment and segment.underground and segment.underground_exit_key == coordinate_key(x, y)
        and (segment.direction ~= direction or (previous_direction ~= nil and previous_direction ~= 0
            and previous_direction ~= direction)) then
        --A side entry onto an underground output or a belt aimed into its side blocks one lane; keep it last.
        cost = cost + SIDELOAD_UNDERGROUND_COST
    end
    return cost + collector_alignment
end

--Riding is a last resort only when there is something to ride: a same-flow belt underground already laid.
--Without one the retry repeats the failed search and spends the demand-order restart's budget (test RB3).
local function has_rideable_pair(work, flow_id)
    for _, segment in ipairs(work.segments or {}) do
        if segment.underground and segment.kind ~= "pipe" and not segment.splitter
            and segment_has_flow(segment, flow_id) then return true end
    end
    return false
end

local function search_step(work, search)
    local current = heap_pop(search)
    if not current then return "failed" end
    if search.closed[current.key] then return "continue" end
    if search.best[current.key] ~= current.cost then return "continue" end
    search.closed[current.key] = true
    if search.demand.kind == "pipe" and current.key ~= search.source_key then
        local here = work.segments_by_cell[coordinate_key(current.x, current.y)]
        if here and here.kind == "pipe" and segment_has_flow(here, search.demand.flow_id) then
            search.net_memo = search.net_memo or {}
            local memo = search.net_memo[current.key]
            if memo == nil then
                memo = route_chain_walk(work, {x = current.x, y = current.y}, search.demand.sink, search.demand.flow_id) == true
                search.net_memo[current.key] = memo
            end
            if memo then return reconstruct(search, current.key) end
        end
    end
    if current.x == search.demand.sink.x and current.y == search.demand.sink.y then
        --The second copper branch once pointed back into its own seeded trunk, closing a 14-tile belt ring.
        --A pipe network is undirected, so it always "reaches its root"; a loop of pipe is harmless.
        local dx, dy = Grid.dir_vector(current.direction)
        if dx and search.demand.kind ~= "pipe"
            and downstream_reaches_root(work, search, current.key, current.x + dx, current.y + dy) then
            return "continue"
        end
        return reconstruct(search, current.key)
    end
    --Riding a same-flow trunk straight into its own underground entrance carries the items through the pair:
    --the next tile of the path is the pair's exit, exactly as the laid chain walks it.  `search.allow_ride`
    --(begin_search): in first routing only after the demand found no path without it; offered there first it
    --moved frozen candidates, tests/test_route_chain.lua RC5 (a demand unserved) and RC8, and
    --tests/test_route_collision.lua RX1.
    local riding = search.allow_ride and work.segments_by_cell[coordinate_key(current.x, current.y)]
    if riding and riding.kind ~= "pipe" and riding.underground and not riding.splitter
        and riding.underground_entry_key == coordinate_key(current.x, current.y)
        and current.direction == riding.direction and segment_has_flow(riding, search.demand.flow_id)
        and current.key ~= search.source_key then
        if segment_allows(work, riding, search.demand, search.amount) then
            enqueue_state(search, riding.underground_exit_x, riding.underground_exit_y, riding.direction, 1, current.key,
                current.cost + (riding.length or 1))
        end
        return "continue"
    end
    for _, direction in ipairs(search.directions) do
        local dx, dy = Grid.dir_vector(direction)
        local nx, ny = current.x + dx, current.y + dy
        local target = nx == search.demand.sink.x and ny == search.demand.sink.y
        if search.merge_target then
            target = nx == search.merge_target.x and ny == search.merge_target.y
                and current.x == search.merge_target.from_x and current.y == search.merge_target.from_y
        end
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
        --An inserter picks from the belt TILE, never from the belt's facing, so when a same-flow run already
        --crosses this sink's own port tile the sink is fed however the search arrives there.  Demanding the
        --port's own travel direction made the search jog off the trunk and come back east, and the detour it
        --laid was then real waste: measured 2026-09-22 on legalcopilot-dev, item/copper-plate into
        --automation-science-pack:2 built a splitter at (11,12)+(12,12) and an orphan belt at (11,11) while
        --the trunk already ran through (12,11).  Contract 28.8 wants the continuation, and this is it.
        --Round 19 widens that to a port tile that is still EMPTY, and for the same reason: the inserter
        --reads the tile, so the belt on it may face any way.  Demanding the port's own travel direction on
        --an empty tile forced every machine after the first in a row to leave the trunk, turn onto its own
        --port tile and die there, so the trunk could never continue to the next machine: measured
        --2026-09-22 on legalcopilot-dev, iron-plate:4 at (17,42) starved with ok=false stage=failed while
        --the trunk already ran east through (9,42) and (13,42).  An underground is still refused -- a belt
        --under the ground feeds nothing above it.
        --A perimeter DOOR is no inserter: its belt must face the way the door points, or items never leave
        --the map.  Measured 2026-09-23 on legalcopilot-dev: the science drain at (15,0) travel N was laid
        --facing EAST by a straight arrival, the next science machine could only reach it round a 12-tile
        --ring, and refusing the ring left automation-science-pack:4 BP_R_NO_PATH.  So the widening below is
        --for machine ports only.
        local sink_any_approach = false
        if target and (search.demand.sink.rear_curve or (search.demand.sink.feed_curve
            and (work.free_source_heading or search.demand.curve_allowed)))
            and search.demand.sink.travel_dir ~= nil
            and direction ~= Grid.dir_opposite(search.demand.sink.travel_dir)
            and work.segments_by_cell[coordinate_key(nx, ny)] == nil then
            local sx, sy = Grid.dir_vector(search.demand.sink.travel_dir)
            local approach = sx and work.segments_by_cell[coordinate_key(search.demand.sink.x - sx,
                search.demand.sink.y - sy)]
            sink_any_approach = not (approach and segment_has_flow(approach, search.demand.flow_id)
                and approach.direction == search.demand.sink.travel_dir)
        end
        if target and not search.demand.sink.perimeter and not search.demand.sink.row_port
            and search.demand.sink.travel_dir ~= nil and search.demand.sink.travel_dir ~= direction then
            local sink_segment = work.segments_by_cell[coordinate_key(nx, ny)]
            if sink_segment == nil then
                --Only a STRAIGHT step onto the empty port tile is widened.  A turn onto it still has to be
                --the turn the port asked for, because a turn is where the router builds a splitter and a
                --body it never fed: allowing every approach built r:8 at (6.0,1.5) with no belt behind it,
                --measured 2026-09-22 by tests/test_route_splitter_physics.lua SP3.
                sink_any_approach = current.direction ~= nil and current.direction == direction
            else
                sink_any_approach = not sink_segment.underground
                    and segment_has_flow(sink_segment, search.demand.flow_id)
            end
        end
        --A MACHINE output port's first belt may face any way, for the same reason a sink's may: the inserter
        --drops onto the TILE.  Forcing the port's own heading sent science machine 4's output at (16,1) north
        --into a 9-entity loop round (18,0)..(18,2) and under (17,2)->(15,2), where the player's fix is ONE
        --belt at (16,1) facing west into the trunk at (15,1): measured 2026-09-23 on legalcopilot-dev,
        --~/share/RRC/player-red-science-1s-20260923-fixed.txt, 249 entities against our 257.  A perimeter
        --door keeps its heading, and a source tile already carrying a laid belt keeps that belt's heading.
        --Only for a ONE-step join: the tile the first step lands on already carries a laid run of this flow,
        --so the output merges into it with one belt.  Freeing every first heading let early outputs wander
        --and fenced in two copper-plate demands (BP_R_NO_PATH), measured the same day.
        local source_any_heading = false
        if first and not search.demand.source.perimeter and not search.demand.source.row_port
            and work.segments_by_cell[coordinate_key(current.x, current.y)] == nil then
            local landing = work.segments_by_cell[coordinate_key(nx, ny)]
            source_any_heading = work.free_source_heading == true or search.demand.free_heading == true
                or (landing ~= nil and not landing.underground and not landing.splitter
                    and segment_has_flow(landing, search.demand.flow_id))
        end
        --A splitter body outputs ONLY in front of the tiles it covers.  A search that turns while it is
        --inside the body plans a belt the splitter never feeds, so the body is committed to the trunk's
        --heading for exactly the one tile it spans.  Mode 2 is that commitment, and it is the same shape of
        --rule as `surfaced` above.
        local in_body = current.mode == 2 and current.direction ~= nil and current.direction ~= direction
        --A sink port tile that already carries a surface belt of this flow, laid facing the port's own heading,
        --is reached by merging onto that belt: the merge adopts its heading (below), builds nothing, and the
        --belt keeps facing the way the port asks.  Demanding the step's OWN heading there made every later
        --demand of the flow leave the trunk one tile early, jog sideways through a new splitter and come back
        --into the port tile from behind.  Measured 2026-09-25 on player-inserter-10s: three iron-plate hands
        --rode the trunk down x=27 to the row feed at (27,24), already served by a curve from (27,23), and
        --built splitters r:461 (27,22)+(28,22) and r:462 (27,23)+(28,23) plus belt r:710 at (28,24), which
        --the validator then rightly called BP_V_TRANSPORT_UNUSED: its items only ever rejoin the same tile.
        local sink_laid = false
        if target and search.demand.sink.travel_dir ~= nil
            and direction ~= Grid.dir_opposite(search.demand.sink.travel_dir) then
            local laid = work.segments_by_cell[coordinate_key(nx, ny)]
            sink_laid = laid ~= nil and laid.kind == "belt" and not laid.underground and not laid.splitter
                and laid.direction == search.demand.sink.travel_dir
                and segment_has_flow(laid, search.demand.flow_id)
        end
        if not surfaced and not reversed and not in_body
            and (not first or search.demand.source.travel_dir == nil or search.demand.source.travel_dir == direction
                or source_any_heading)
            and (not target or search.demand.sink.travel_dir == nil or search.demand.sink.travel_dir == direction
                or sink_any_approach or sink_laid) then
            local leaving = work.segments_by_cell[coordinate_key(current.x, current.y)]
            --The body jump.  Leaving a belt already laid is not a turn -- no entity turns flow.  It is a
            --step into the OTHER tile of the splitter this cell is about to become, and the items keep the
            --trunk's heading right through the body.  The tile stepped into is exactly the tile
            --`splitter_branch_allowed` checks and exactly the tile `append_normal_path` claims, so search
            --and materializer cannot disagree about it -- that is contract 28.5 by construction rather than
            --by two predicates agreeing to agree.
            local body_jump = false
            if leaving ~= nil and leaving.kind == "belt" and not leaving.underground and not leaving.splitter
                and current.direction ~= nil and leaving.direction == current.direction
                and direction ~= current.direction and work.belt and work.belt.splitter
                and not (search.demand.crossing_blocked
                    and search.demand.crossing_blocked[coordinate_key(current.x, current.y)])
                and segment_allows(work, leaving, search.demand, search.amount)
                and splitter_can_absorb(leaving)
                and splitter_straight_fed(work, current.x, current.y, leaving, search.demand.flow_id, search.demand.source)
                and splitter_branch_allowed(work, search.demand, current.x, current.y, direction, leaving, nil) then
                body_jump = true
            end
            --A merge adopts the trunk's heading.  Once the items are on a run already laid they travel the
            --way that run faces, so the search must plan from there with the trunk's direction, never with
            --the direction it arrived from.  Mode 2 holds it to that heading for the one tile, exactly as it
            --does inside a splitter body.
            local entering = work.segments_by_cell[coordinate_key(nx, ny)]
            local merge = not body_jump and entering ~= nil and not entering.splitter
                and entering.kind ~= "pipe" and entering.direction ~= nil and entering.direction ~= direction
                and direction ~= Grid.dir_opposite(entering.direction)
            local free = path_cell_free(work, search.demand, nx, ny,
                body_jump and leaving.direction or direction, target, search.amount, search)
            if crowded_demand(work, search.demand) then
                if current.mode == 3 then
                    free, body_jump, merge = false, false, false
                elseif not free and search.touch_refused and not target then
                    search.touch_ok = true
                    local dive_ok = path_cell_free(work, search.demand, nx, ny, direction, target, search.amount, search)
                    search.touch_ok = nil
                    if dive_ok then enqueue_state(search, nx, ny, direction, 3, current.key,
                        current.cost + transition_cost(work, search.demand, nx, ny, direction, current.direction, 0, 0, search.amount)) end
                end
            end
            local refused_body = leaving ~= nil and leaving.kind ~= "pipe"
                and (search.demand.strict_branch or splitter_can_absorb(leaving))
                and current.direction ~= nil and leaving.direction == current.direction
                and direction ~= current.direction and work.belt and work.belt.splitter and not body_jump
            if free and body_jump then
                --A splitter costs two belts' worth of commitment and forces the branch to jog a tile, so it
                --is priced above the plain turn it replaces.  Contract 28.8 wants a continuation to win
                --whenever one exists, and this is the price that keeps it winning.
                search.saw_branch = true
                local cost = current.cost + transition_cost(work, search.demand, nx, ny, leaving.direction,
                    current.direction, 0, 0, search.amount) + SPLITTER_BODY_COST
                enqueue_state(search, nx, ny, leaving.direction, 2, current.key, cost)
            elseif free and merge then
                --A same-flow merge must not reconnect this branch to its own root and close a directed ring.
                if not downstream_reaches_root(work, search, current.key, nx, ny) then
                    local cost = current.cost + transition_cost(work, search.demand, nx, ny, direction,
                        current.direction, 0, 0, search.amount)
                    enqueue_state(search, nx, ny, entering.direction, 2, current.key, cost)
                end
            elseif free and not refused_body then
                local cost = current.cost + transition_cost(work, search.demand, nx, ny, direction,
                    current.direction, 0, 0, search.amount)
                enqueue_state(search, nx, ny, direction, 0, current.key, cost)
            --A pipe-to-ground exit is one entity on one tile: it cannot also be the entrance of the next pair. Diving
            --from the tile the search just surfaced on laid (76,63)->(85,63) and (85,63)->(95,63) for light oil on the
            --player's gray + magenta sheet (2026-09-27), and the router then refused its own path as discontinuous.
            elseif (not first or search.demand.source.perimeter or search.demand.kind == "pipe") and current.mode ~= 2
                --BC1: on the frozen gray + magenta sheet, (2026-09-27), the exit at (85,69) also became
                --an entrance at (85,69); one tile cannot hold both underground-belt entities.
                and not (current.mode == 1 and (search.demand.kind == "pipe" or search.demand.no_chain_dive or search.demand.strict_dive))
                --Steel plate tried to dive from its own occupied (65,25); molten iron did the same at (86,20)
                --on the frozen gray + magenta sheet (2026-09-27). Strict retry entrances must be free tiles.
                and not (search.demand.strict_dive and work.segments_by_cell[coordinate_key(current.x, current.y)] ~= nil)
                and not (current.mode == 3 and direction ~= current.direction) then
                local bury_key = coordinate_key(nx, ny)
                --Bury is offered only inside the re-route pass, where a path is kept only when it gets
                --smaller.  Offered during first routing it reshuffled every later path and took the player's
                --sheet 248 -> 263 entities, measured 2026-09-23 on legalcopilot-dev.
                local bury = work.allow_bury == true
                    and not (search.demand.bury_blocked and search.demand.bury_blocked[bury_key])
                    and bury_candidate(work, nx, ny, direction) or nil
                if bury then
                    local inserted = enqueue_state(search, nx, ny, direction, 0, current.key,
                        current.cost + BURY_COST + (current.direction ~= direction and 1 or 0))
                    if inserted then
                        local key = state_key(nx, ny, direction, search.demand.kind, 0)
                        search.buries = search.buries or {}
                        search.buries[key] = bury
                    end
                end
                --A dive may NEVER start inside a splitter body.  Mode 2 is the tile the body jump claims,
                --and at search time that tile is still free, so the search happily planned an underground
                --entrance on it and the append then published the splitter over it: measured 2026-09-22 on
                --legalcopilot-dev, splitter r:238 at (9.5,6) covering (9,6)+(9,5) with underground-belt
                --r:264 published at (9.5,5.5), caught by tests/test_route_collision.lua RX1.
                --A door on the grid edge may dive on its very FIRST step.  An edge door has exactly one tile
                --and no room to go around, so a belt already laid across its face sealed it completely:
                --measured 2026-09-22 on legalcopilot-dev, item/iron-ore entering at (0,42) with the
                --iron-plate trunk running north up the whole of column x=1, four BP_R_NO_PATH and not one
                --furnace fed.  Diving under that trunk is what the player's own factory does.  A MACHINE
                --port keeps the old rule: its source tile is the tile an inserter drops onto, and that tile
                --stays a plain belt.
                local crossings = crossing_targets(work, search.demand, search, current, direction, search.amount)
                for _, crossing in ipairs(crossings) do
                    local reaches_sink = crossing.x == search.demand.sink.x and crossing.y == search.demand.sink.y
                    if not reaches_sink or search.demand.sink.travel_dir == nil or search.demand.sink.travel_dir == direction then
                        local cost = current.cost + transition_cost(work, search.demand, crossing.x, crossing.y, direction,
                            current.direction, 1, crossing.distance, search.amount)
                        if current.direction ~= direction then cost = cost + SIDELOAD_UNDERGROUND_COST end
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

--`publish` is set only by tidy's final result: the twin-edge fold rewrites segments, so doing it at the end of
--first routing left tidy working on a half-folded state that dropped the splitter (round 37, red-10s route call 3).
local function result_for(work, publish)
    --Fold two neighbouring, straight edge feeds of the same flow into the physical splitter the player
    --would place by hand.  This is deliberately a final publication tidy: path search and its retries
    --remain unchanged, and an incomplete/blocked footprint is left for validation to reject.
    local function fold_edge_twins()
        if not (work.belt and work.belt.splitter) then return end
        local by_cell = work.segments_by_cell or {}
        local segment_by_id, entity_by_id = {}, {}
        for _,s in ipairs(work.segments or {}) do segment_by_id[s.segment_id]=s end
        for _,e in ipairs(work.entities or {}) do entity_by_id[e.segment_id]=e end
        local function key(x,y) return tostring(x) .. ":" .. tostring(y) end
        local function live(seg) return seg and seg.kind == "belt" and not seg.underground and not seg.splitter end
        local function allocations(seg, flow)
            local out = {}; for _,a in ipairs(seg and seg.allocations or {}) do if a.flow_id == flow then out[#out+1]=a end end; return out
        end
        local function only_flow(seg, flow)
            for _,a in ipairs(seg and seg.allocations or {}) do if a.flow_id ~= flow then return false end end
            return true
        end
        local function entity_for(seg)
            return seg and entity_by_id[seg.segment_id]
        end
        local edges = {}
        for _,e in ipairs(work.entities or {}) do
            local x,y=math.floor(e.position.x),math.floor(e.position.y)
            if x==0 or y==0 or x==work.grid.w-1 or y==work.grid.h-1 then
                local seg=segment_by_id[e.segment_id]
                if live(seg) and e.direction then
                    for _,a in ipairs(seg.allocations or {}) do
                        local dx,dy=Grid.dir_vector(e.direction)
                        local ix,iy=x+dx,y+dy
                        if (x==0 and dx==1) or (x==work.grid.w-1 and dx==-1) or (y==0 and dy==1) or (y==work.grid.h-1 and dy==-1) then
                            edges[#edges+1]={x=x,y=y,ix=ix,iy=iy,dir=e.direction,flow=a.flow_id,seg=seg,entity=e}; break
                        end
                    end
                end
            end
        end
        table.sort(edges,function(a,b) if a.flow~=b.flow then return a.flow<b.flow end if a.y~=b.y then return a.y<b.y end return a.x<b.x end)
        for i=1,#edges do
            local a=edges[i]
            if a.used~=true then
                for j=i+1,#edges do
                    local b=edges[j]
                    if not b.used and b.flow==a.flow and b.dir==a.dir and math.abs(a.x-b.x)+math.abs(a.y-b.y)==1 then
                        local one,two=by_cell[key(a.ix,a.iy)],by_cell[key(b.ix,b.iy)]
                        local eone,etwo=entity_for(one),entity_for(two)
                        if live(one) and live(two) and eone and etwo and one~=two
                            and one.direction==a.dir and two.direction==a.dir
                            and only_flow(a.seg,a.flow) and only_flow(b.seg,a.flow)
                            and only_flow(one,a.flow) and only_flow(two,a.flow)
                            and #allocations(a.seg,a.flow)>0 and #allocations(b.seg,b.flow)>0
                            and not (work.obstacles and (work.obstacles[key(a.ix,a.iy)] or work.obstacles[key(b.ix,b.iy)])) then
                            local dx,dy=Grid.dir_vector(a.dir)
                            -- Remove the redundant edge belt and merge its complete rate promises.
                            for _,al in ipairs(b.seg.allocations or {}) do if al.flow_id==a.flow then a.seg.allocations[#a.seg.allocations+1]=al end end
                            b.seg.allocations={}; b.seg._route_removed=true; b.entity._route_removed=true
                            local kept_source_port
                            for _,binding in ipairs(work.bindings or {}) do
                                if binding.segment_id==a.seg.segment_id and binding.flow_id==a.flow then kept_source_port=kept_source_port or binding.source_port_id end
                            end
                            for _,binding in ipairs(work.bindings or {}) do
                                if binding.segment_id==b.seg.segment_id and binding.flow_id==a.flow then
                                    binding.segment_id=a.seg.segment_id
                                    if kept_source_port then binding.source_port_id=kept_source_port end
                                end
                            end
                            -- One splitter occupies the two first inside tiles.  Keep one segment identity.
                            for _,al in ipairs(two.allocations or {}) do one.allocations[#one.allocations+1]=al end
                            two.allocations={}; two._route_removed=true; etwo._route_removed=true
                            one.splitter=true; one.splitter_direction=a.dir; one.direction=a.dir
                            one.capacity_per_second=2*(one.capacity_per_second or 0)
                            one.splitter_anchor_x=a.ix; one.splitter_anchor_y=a.iy
                            one.splitter_second_key=key(b.ix,b.iy)
                            eone.name=work.belt.splitter
                            eone.position={x=a.ix+0.5,y=a.iy+0.5}
                            -- Splitter prototypes are centred between their two tiles.
                            if dx~=0 then eone.position.y=eone.position.y+(b.y-a.y)*0.5
                            else eone.position.x=eone.position.x+(b.x-a.x)*0.5 end
                            eone.direction=a.dir
                            for _,binding in ipairs(work.bindings or {}) do
                                if binding.segment_id==two.segment_id then binding.segment_id=one.segment_id end
                            end
                            by_cell[key(b.ix,b.iy)]=one
                            a.used,b.used=true,true
                            break
                        end
                    end
                end
            end
        end
    end
    if publish then
        PipeRuns.bury(work, {key = coordinate_key, coordinate_from_key = coordinate_from_key, next_segment_id = next_segment_id,
            next_entity_id = next_entity_id, entity_position = entity_position, infrastructure = infrastructure, finite = finite})
    end
    if publish then fold_edge_twins() end
    audit_route_work(work)
    --A belt that serves two flows keeps its legacy scalar flow for consumers that only know the old shape, and
    --also publishes the complete set for the validator and physical witness.  Build this at publication time so
    --the route snapshots stay small while a search is still being retried.
    local flows_by_segment = {}
    for _, segment in ipairs(work.segments or {}) do
        local ids = {}
        if segment.flow_id ~= nil then ids[segment.flow_id] = true end
        for flow_id, present in pairs(segment.flow_ids or {}) do
            if present then ids[flow_id] = true end
        end
        for _, allocation in ipairs(segment.allocations or {}) do
            if allocation.flow_id ~= nil then ids[allocation.flow_id] = true end
        end
        local flow_ids = {}
        for flow_id, _ in pairs(ids) do flow_ids[#flow_ids + 1] = flow_id end
        table.sort(flow_ids)
        flows_by_segment[segment.segment_id] = flow_ids
    end
    for _, entity in ipairs(work.entities or {}) do
        local flow_ids = flows_by_segment[entity.segment_id]
        if flow_ids and #flow_ids > 1 then entity.flow_ids = flow_ids end
    end
    local result = {entities = {}, segments = {}, port_bindings = work.bindings, bindings = work.bindings,
        shortfalls = work.shortfalls or {}, port_slides = {}}
    for _, port_id in ipairs(sorted_keys(work.port_slides or {})) do
        local slide = work.port_slides[port_id]
        result.port_slides[#result.port_slides + 1] = slide.hop and {port_id = port_id, hop = slide.hop}
            or {port_id = port_id, dx = slide.dx, dy = slide.dy}
    end
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

--Player: “underground belts are more expensive than normal one and unused ones must be 'unburied'.”
--The (9,20) crossing motivates burying the straight gear run; pairs that cover nothing are the reverse.
local function unbury_empty_pairs(work)
    local underground_pairs = {}
    for _, segment in ipairs(work.segments or {}) do
        --An endpoint pair requested by underground port connections is part of the blueprint's port shape.
        --UNBURY applies to optional crossing pairs, which are the expensive geometry the player called out.
        if segment.underground and not segment.explicit then underground_pairs[#underground_pairs + 1] = segment end
    end
    table.sort(underground_pairs, function(a, b) return a.underground_entry_key < b.underground_entry_key end)
    for _, pair in ipairs(underground_pairs) do
        local own_ports = {}
        local pair_bindings = {}
        for _, binding in ipairs(work.bindings or {}) do
            if binding.segment_id == pair.segment_id then
                own_ports[binding.source_port_id], own_ports[binding.sink_port_id] = true, true
                pair_bindings[#pair_bindings + 1] = binding
            end
        end
        local dx, dy = Grid.dir_vector(pair.direction)
        local x, y = pair.underground_entry_x + dx, pair.underground_entry_y + dy
        local covered, occupied = {}, false
        while x ~= pair.underground_exit_x or y ~= pair.underground_exit_y do
            local key = coordinate_key(x, y)
            covered[#covered + 1] = {x = x, y = y, key = key}
            local reserved = work.port_cells and work.port_cells[key]
            local other_port = false
            for owner, present in pairs(reserved or {}) do
                if present and owner ~= "_port_owners" and tostring(owner):sub(1, 5) ~= "flow:" and not own_ports[owner] then
                    other_port = true
                end
            end
            if work.segments_by_cell[key] or static_owner(work, x, y) ~= nil or indexed_cell(work.grid, x, y)
                or other_port then occupied = true end
            x, y = x + dx, y + dy
        end
        if not occupied then
            local tiles = {{x = pair.underground_entry_x, y = pair.underground_entry_y}}
            for _, cell in ipairs(covered) do tiles[#tiles + 1] = cell end
            tiles[#tiles + 1] = {x = pair.underground_exit_x, y = pair.underground_exit_y}
            if FluidTouch.unbury_blocked(work.segments_by_cell, coordinate_key, pair, tiles) then occupied = true end
        end
        if not occupied then
            local cells = {{x = pair.underground_entry_x, y = pair.underground_entry_y}}
            for _, cell in ipairs(covered) do cells[#cells + 1] = cell end
            cells[#cells + 1] = {x = pair.underground_exit_x, y = pair.underground_exit_y}
            for _, e in ipairs(work.entities) do
                if e.segment_id == pair.segment_id then e._route_removed = true end
            end
            work.segments_by_cell[pair.underground_entry_key] = nil
            work.segments_by_cell[pair.underground_exit_key] = nil
            work.underground_cells[pair.underground_entry_key], work.underground_cells[pair.underground_exit_key] = nil, nil
            work.splitter_blocked_cells[pair.underground_entry_key], work.splitter_blocked_cells[pair.underground_exit_key] = nil, nil
            pair._route_removed = true
            work.entity_by_segment[pair.segment_id] = nil
            local remaining_segments = {}
            for _, segment in ipairs(work.segments) do if segment ~= pair then remaining_segments[#remaining_segments + 1] = segment end end
            work.segments = remaining_segments
            for _, cell in ipairs(cells) do
                local segment = {segment_id = next_segment_id(work), kind = pair.kind,
                    capacity_per_second = pair.capacity_per_second, allocations = {}, flow_id = pair.flow_id,
                    flow_ids = pair.flow_ids, direction = pair.direction, length = 1}
                for _, a in ipairs(pair.allocations or {}) do
                    segment.allocations[#segment.allocations + 1] = {flow_id = a.flow_id, sink = a.sink,
                        rate_per_second = a.rate_per_second}
                end
                local belt = {id = next_entity_id(work), name = infrastructure(work, pair.kind),
                    position = entity_position(cell.x, cell.y), direction = pair.direction, dir = pair.direction,
                    flow_id = pair.flow_id, segment_id = segment.segment_id}
                work.entities[#work.entities + 1] = belt
                work.segments[#work.segments + 1] = segment
                work.segments_by_cell[coordinate_key(cell.x, cell.y)] = segment
                work.entity_by_segment[segment.segment_id] = belt
            end
            --The original binding is reattached to the first replacement belt in the directed chain.
            for _, binding in ipairs(pair_bindings) do binding.segment_id = work.segments_by_cell[pair.underground_entry_key].segment_id end
        end
    end
end

--A port is useless without the tile its transport reaches it from: an input needs the tile it is entered from,
--an output needs the tile it leaves into.  Routing one demand used to lay a belt straight across the approach
--tile of a port it does not serve, and every later demand for that port then had no path at all.  Those tiles
--are claimed by the ports that own them before any demand is routed, so another belt goes around instead.  A
--belt already carrying the same flow may still pass: one trunk feeding two consumers of one item is the shape
--the allocation rules are written for, and claiming against it would forbid sharing outright.
local function reserve_port_cells(work)
    local reserved = {}
    work.crowded_blocks = {}
    local per = {}
    for _, by_role in pairs(work.endpoint_index or {}) do
        for _, role in ipairs({"in", "out"}) do
            for _, ep in ipairs(by_role[role] or {}) do
                if ep.kind == "fluid" and ep.block_id and ep.port_id then
                    per[ep.block_id] = per[ep.block_id] or {}
                    per[ep.block_id][ep.port_id] = true
                end
            end
        end
    end
    for block_id, set in pairs(per) do
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        if n >= 3 then work.crowded_blocks[block_id] = true end
    end
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
        if endpoint.kind == "fluid" then
            claim(endpoint.x, endpoint.y, endpoint, true)
            local key = coordinate_key(endpoint.x, endpoint.y)
            if reserved[key] and endpoint.fluid_travel_dir ~= nil then reserved[key]._fluid_dir = endpoint.fluid_travel_dir end
            local crowded = work.crowded_blocks[endpoint.block_id]
            if crowded and reserved[key] then reserved[key]._crowded = true end
            if crowded and endpoint.fluid_travel_dir ~= nil then
                local dx, dy = Grid.dir_vector(endpoint.fluid_travel_dir)
                if endpoint.role == "in" then dx, dy = -dx, -dy end
                local ax, ay, steps = endpoint.x + dx, endpoint.y + dy, 0
                while steps < 9 and inside_grid(work, ax, ay) and static_owner(work, ax, ay) ~= nil do
                    ax, ay, steps = ax + dx, ay + dy, steps + 1
                end
                if inside_grid(work, ax, ay) then
                    claim(ax, ay, endpoint, false)
                    local front = coordinate_key(ax, ay)
                    reserved[front]._fluid_front = reserved[front]._fluid_front or {}
                    reserved[front]._fluid_front[endpoint.flow_id] = true
                end
            end
            return
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
    local input_entities = {}
    for _, entity in ipairs(input.entities or {}) do input_entities[#input_entities+1]=entity end
    for _, block in ipairs(blocks) do
        for _, field in ipairs({"entities","placed_entities","inserters"}) do
            for _, entity in ipairs(block[field] or {}) do input_entities[#input_entities+1]=entity end
        end
    end
    local work = {
        input_belt_capacity = finite(input.belt_capacity), input_pipe_capacity = finite(input.pipe_capacity),
        input_belt_name = input.belt_name, input_pipe_name = input.pipe_name,
        multi_flow_hands = multi_flow_hands_enabled(input),
        belt = input.belt or (input.catalog and input.catalog.belt) or {},
        pipe = input.pipe or (input.catalog and input.catalog.pipe) or {},
        --A copy: collectors append synthetic runs, and a keep-if-cheaper retry routes the same input again.
        belt_runs = (function() local runs = {}; for i, run in ipairs(input.belt_runs or {}) do runs[i] = run end; return runs end)(),
        collectors = input.collectors ~= false, collectors_used = false,
        input_entities = input_entities,
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
            elseif endpoint and port.rear and port.port_id == "row:in:rear" then
                -- Keep the multi-flow rear door out of first-pass demand indexing, but make
                -- its physical location available to the improve pass.
                work.endpoint_by_id[endpoint.port_id] = endpoint
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
    work.expansion_limit_input = {grid = input.grid, limits = input.limits, max_expansions = input.max_expansions}
    work.max_expansions = finite(input.limits and input.limits.max_expansions,
        finite(input.max_expansions, default_expansion_limit(input, #work.flows)))
    -- Demand pairing contains obstacle floods for every producer/consumer candidate pair. Keep the
    -- normalized inputs here; Route.step builds one flow's demands at a time under its op budget.
    work.demands, work.demand_build_index = {}, 1
    work.demand_order, work.demands_by_key = {}, {}
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
    lay_belt_runs(work)
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
    lay_belt_runs(work)
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
    --A row side feed is entered straight from behind (often an underground under the machines) in first routing;
    --the curve in from the side waits for the improve pass. When the straight way has no room -- red science
    --10/s (2026-09-25): the output-side beacon row sits where the gear underground had to start -- the demand gets
    --one more restart with the curve allowed, before it is written off as a shortfall.
    if code == "BP_R_NO_PATH" and demand and demand.sink and demand.sink.feed_curve and not demand.curve_allowed then
        demand.curve_allowed = true
        for index = #(work.priority or {}), 1, -1 do
            if work.priority[index] == demand.order_key then table.remove(work.priority, index) end
        end
        if restart_with_priority(state, work, demand) then return false end
    end
    --After the curve retry (which the row feed needs first: red science 10/s gear feed), a machine's output hand drops onto its tile whichever way the belt there faces. First routing still lays
    --that belt in the hand's own heading; when that leaves no way out -- several hands of one flow side by side
    --on one face, as slow hands need (2.31/s, 2026-09-25) -- the demand gets one restart with any heading.
    if code == "BP_R_NO_PATH" and demand and demand.source and not demand.source.perimeter
        and not demand.source.row_port and not demand.free_heading then
        demand.free_heading = true
        for index = #(work.priority or {}), 1, -1 do
            if work.priority[index] == demand.order_key then table.remove(work.priority, index) end
        end
        if restart_with_priority(state, work, demand) then return false end
    end
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

local improve_begin, improve_step

local function finish_demand_build(work)
    -- `build_demands` has already applied its stable route-cost ordering per flow. The old sort
    -- was global; preserve that exact ordering across flows by applying its same comparator once.
    for index, demand in ipairs(work.demands) do demand._build_order = index end
    local crowd, ports = {}, {}
    for _, demand in ipairs(work.demands) do
        for _, ep in ipairs({demand.source, demand.sink}) do
            if ep and ep.kind == "fluid" and ep.block_id and ep.port_id then
                ports[ep.block_id] = ports[ep.block_id] or {}
                ports[ep.block_id][ep.port_id] = true
            end
        end
    end
    for _, demand in ipairs(work.demands) do
        local best = 0
        for _, ep in ipairs({demand.source, demand.sink}) do
            if ep and ep.kind == "fluid" and ep.block_id and ports[ep.block_id] and not ep.perimeter then
                local n = 0
                for _ in pairs(ports[ep.block_id]) do n = n + 1 end
                if demand.source and demand.source.perimeter then n = math.min(n, 1) end
                if n >= 3 then best = math.max(best, n) end
            end
        end
        crowd[demand] = best
    end
    table.sort(work.demands, function(left, right)
        if (crowd[left] or 0) ~= (crowd[right] or 0) then return (crowd[left] or 0) > (crowd[right] or 0) end
        if left.pairing_cost ~= right.pairing_cost then return left.pairing_cost > right.pairing_cost end
        return left._build_order < right._build_order
    end)
    local limits = work.expansion_limit_input or {}
    work.max_expansions = finite(limits.limits and limits.limits.max_expansions,
        finite(limits.max_expansions, default_expansion_limit(limits, #work.demands)))
    work.demand_order, work.demands_by_key = {}, {}
    for index, demand in ipairs(work.demands) do
        demand.order_key = index
        work.demand_order[index], work.demands_by_key[index] = demand, demand
    end
    work.port_cells = reserve_port_cells(work)
    lay_belt_runs(work)
    work.demand_build_done = true
    work.expansion_limit_input = nil
end

function Route.begin(input)
    input = input or {}
    local work = normalize_input(input or {})
    return {done = false, ok = nil, tidy = not (type(input) == "table" and input.tidy == false), cursor = {flow_index = 1, demand_index = 1, phase = "demand_build"},
        progress = {phase = "demand_build", done_units = 0, total_units = #work.flows},
        counters = work.counters, work = work}
end

function Route.tidy_begin(done_state, options)
    options = type(options) == "table" and options or {}
    local work = done_state and done_state.work
    if type(work) ~= "table" or not done_state.done or not done_state.ok then
        return {done = true, ok = false, errors = {{code = "BP_R_NO_PATH"}}}
    end
    for index, obstacle in ipairs(options.obstacles or {}) do
        local rect = copy_rect(obstacle.rect or obstacle)
        if rect then add_rect_cells(work.obstacles, rect, obstacle.owner or obstacle.kind or ("tidy:" .. tostring(index))) end
    end
    local state = {done = false, ok = nil, work = work, counters = work.counters,
        cursor = {demand_index = #work.demands + 1}, progress = {phase = "tidy", done_units = 0, total_units = #work.bindings + 1}}
    state._tidy = true
    return state
end

local prune_dead_route_segments
function Route.tidy_step(state, budget)
    if type(state) ~= "table" or state.done then return state end
    budget = budget or {ops = 1}
    local ops = math.max(0, finite(budget.ops, 1))
    local work = state.work
    if not work.improved then
        work.improve_state = work.improve_state or improve_begin(work)
        local used, finished = improve_step(work, work.improve_state, ops)
        ops = math.max(0, ops - used)
        --Progress for the bar (round 33): bindings tried so far plus the share of the current binding's trials.
        local st = work.improve_state
        if st and st.order then
            local within = st.options and #st.options > 0 and math.min(1, (st.option_index or 1) / #st.options) or 0
            state.progress.total_units = #st.order + 1
            state.progress.done_units = math.min(#st.order, math.max(0, (st.index or 0) - 1 + within))
        end
        if finished then work.improved, work.improve_state = true, nil end
    end
    if work.improved then
        unbury_empty_pairs(work)
        prune_dead_route_segments(work)
        state.result, state.done, state.ok = result_for(work, true), true, true
        state.progress.phase = "done"
    end
    budget.ops = math.max(0, ops)
    return state
end

function Route.free_cell(state, x, y)
    if type(state) ~= "table" or not state.done or not state.ok or type(state.work) ~= "table" then return false end
    local work = state.work
    local segment = work.segments_by_cell[coordinate_key(x, y)]
    if not segment or segment.kind ~= "belt" or segment.underground or segment.splitter then return false end
    for _, cross in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
        local candidate = bury_candidate(work, x, y, cross, true)
        if candidate and apply_bury(work, candidate, true) then
            local refreshed = result_for(work)
            local result = state.result or {}
            for key in pairs(result) do result[key] = nil end
            for key, value in pairs(refreshed) do result[key] = value end
            state.result = result
            return true
        end
    end
    return false
end

function Route.cancel(state)
    if type(state) ~= "table" or state.done then return state end
    clear_route_work(state.work)
    state.cancelled, state.done, state.ok, state.result = true, true, false, nil
    state.errors = {{code = "BP_FAIL_CANCELLED"}}
    state.progress.phase = "cancelled"
    return state
end

--Re-route pass, the player's instrument, 2026-09-23 on legalcopilot-dev.  Paths are laid one at a time, so
--the first path is planned with nothing else on the grid and the later ones must work round it.  Once every
--path exists, each one is lifted -- only the plain belts it owns alone -- and searched again with a free first
--heading at its machine output.  The new path is KEPT ONLY WHEN IT LAYS FEWER ENTITIES than the ones lifted;
--otherwise the snapshot is restored.  So the pass never grows the factory.  Measured on the player's sheet:
--furnace 4's output at (17,48) was forced SOUTH and walked (17,49)..(13,49) back up into the trunk, six
--belts where the straight (17,48)..(14,48) is four ("Why this bend?").
--The tiles items actually travel from `source` to `sink`, following laid same-flow segments, pairs and both
--splitter outputs.  nil when the chain does not reach.
local function binding_path(work, binding)
    local source = work.endpoint_by_id and work.endpoint_by_id[binding.source_port_id]
    local sink = work.endpoint_by_id and work.endpoint_by_id[binding.sink_port_id]
    if not source or not sink then return nil end
    local start, target = coordinate_key(source.x, source.y), coordinate_key(sink.x, sink.y)
    local parent, queue, head = {[start] = false}, {start}, 1
    while queue[head] do
        local key = queue[head]; head = head + 1
        if key == target then break end
        local segment = work.segments_by_cell[key]
        if segment and segment_has_flow(segment, binding.flow_id) then
            local nexts = {}
            if segment.underground then
                if key == segment.underground_entry_key then nexts[#nexts + 1] = segment.underground_exit_key end
                if key == segment.underground_exit_key then
                    local dx, dy = Grid.dir_vector(segment.direction)
                    if dx then nexts[#nexts + 1] = coordinate_key(segment.underground_exit_x + dx, segment.underground_exit_y + dy) end
                end
            elseif segment.splitter then
                local dx, dy = Grid.dir_vector(segment.splitter_direction)
                if dx then
                    nexts[#nexts + 1] = coordinate_key(segment.splitter_anchor_x + dx, segment.splitter_anchor_y + dy)
                    local sx, sy = coordinate_from_key(segment.splitter_second_key or "")
                    if sx then nexts[#nexts + 1] = coordinate_key(sx + dx, sy + dy) end
                end
                nexts[#nexts + 1] = segment.splitter_second_key
            else
                local x, y = coordinate_from_key(key)
                local dx, dy = Grid.dir_vector(segment.direction)
                if dx then nexts[#nexts + 1] = coordinate_key(x + dx, y + dy) end
            end
            for _, n in ipairs(nexts) do
                if n and parent[n] == nil then parent[n] = key; queue[#queue + 1] = n end
            end
        end
    end
    if parent[target] == nil then return nil end
    local path, key = {}, target
    while key do path[#path + 1] = key; key = parent[key] or nil end
    return path
end

--What a path owns ALONE: its own source-to-sink tiles minus every tile on any other path of the same flow.
--Ownership by allocation fails twice over: add_allocation sums rates per (flow, sink), so a merged trunk
--shows one allocation; and a branch laid from a seed on the trunk records nothing upstream of that seed,
--so a trunk four paths ride looked like one path's.  Measured 2026-09-23 on legalcopilot-dev: the first
--version lifted the whole 31-tile iron-plate trunk and orphaned three furnaces.
local function lift_binding(work, binding, allow_fixed)
    local mine = binding_path(work, binding)
    if not mine then return nil end
    local others = {}
    for _, other in ipairs(work.bindings) do
        if other ~= binding and other.flow_id == binding.flow_id then
            for _, key in ipairs(binding_path(work, other) or {}) do others[key] = true end
        end
    end
    local owned_ids, count = {}, 0
    for _, key in ipairs(mine) do
        local segment = work.segments_by_cell[key]
        -- Ordinary improve trials refuse a path that touches a fixed run. A paired rear trial may lift its
        -- connector while retaining every fixed tile and allocation in place.
        if segment and segment.fixed and not allow_fixed then return nil end
        --A tile carrying another sink's allocation is shared even when that binding's own path walk misses it
        --(a one-tile branch into an underground entrance): lifting it deleted that sink's rate and the validator
        --then found the sink unfed (red science 10/s, 2026-09-25).
        local carries_other = false
        for _, allocation in ipairs(segment and segment.allocations or {}) do
            if allocation.sink ~= nil and binding.sink ~= nil and allocation.sink ~= binding.sink then carries_other = true; break end
        end
        if segment and not segment.fixed and not others[key] and not carries_other then
            if segment.splitter then return nil end
            if not owned_ids[segment.segment_id] then owned_ids[segment.segment_id] = true; count = count + 1 end
        end
    end
    if count < 2 then return nil end
    --Shared tiles keep this path's rate: the re-search seeds from the trunk, so items for this sink still ride
    --every tile upstream of its branch.  Subtracting here left the gear trunk at zero after two kept re-routes,
    --and audit_route_work then deleted the gear output tile and two bindings with it (2026-09-23,
    --legalcopilot-dev, first candidate of the player's sheet).
    local segments = {}
    for _, segment in ipairs(work.segments) do
        if not owned_ids[segment.segment_id] then segments[#segments + 1] = segment end
    end
    work.segments = segments
    for key, segment in pairs(work.segments_by_cell) do
        if owned_ids[segment.segment_id] then
            work.segments_by_cell[key] = nil
            --A lifted pair frees its two endpoint tiles for the re-search.
            if segment.underground then work.underground_cells[key], work.splitter_blocked_cells[key] = nil, nil end
        end
    end
    local entities = {}
    for _, entity in ipairs(work.entities) do
        if not owned_ids[entity.segment_id] then entities[#entities + 1] = entity end
    end
    work.entities = entities
    for segment_id in pairs(owned_ids) do work.entity_by_segment[segment_id] = nil end
    local bindings = {}
    for _, other in ipairs(work.bindings) do if other ~= binding then bindings[#bindings + 1] = other end end
    work.bindings = bindings
    return count
end

--A kept reroute can leave the old shared trunk behind when every sink's lift correctly protects the
--other sinks' allocation. Once all trials are over, retain only segments on a complete bound path.
local function untangle_splitter_chains(work)
    local changed = true
    while changed do
    changed = false
    local replacements = {}
    for _, downstream in ipairs(work.segments or {}) do
        if downstream.splitter then
            local dx, dy = Grid.dir_vector(downstream.splitter_direction)
            local x, y = coordinate_from_key(downstream.splitter_second_key or "")
            if dx and x then
                for _, upstream in ipairs(work.segments or {}) do
                    if upstream ~= downstream and upstream.splitter and upstream.flow_id == downstream.flow_id
                        and upstream.splitter_direction == downstream.splitter_direction then
                        local ux, uy = Grid.dir_vector(upstream.splitter_direction)
                        local sx, sy = coordinate_from_key(upstream.splitter_second_key or "")
                        local out1 = coordinate_key(upstream.splitter_anchor_x + ux, upstream.splitter_anchor_y + uy)
                        local out2 = coordinate_key(sx + ux, sy + uy)
                        if coordinate_key(downstream.splitter_anchor_x, downstream.splitter_anchor_y) == out1
                            and downstream.splitter_second_key == out2 then replacements[#replacements + 1] = downstream; break end
                    end
                end
            end
        end
    end
    for _, old in ipairs(replacements) do
        local keys = {old.splitter_anchor_key, old.splitter_second_key}
        local old_entity = work.entity_by_segment[old.segment_id]
        if old_entity then
            old_entity._route_removed = true
            for index = #work.entities, 1, -1 do if work.entities[index] == old_entity then table.remove(work.entities, index) end end
        end
        work.entity_by_segment[old.segment_id] = nil
        work.segments_by_cell[old.splitter_anchor_key] = nil
        work.segments_by_cell[old.splitter_second_key] = nil
        for index = #work.segments, 1, -1 do if work.segments[index] == old then table.remove(work.segments,index) end end
        for i, key in ipairs(keys) do
            local x, y = coordinate_from_key(key)
            local segment = {segment_id = i == 1 and old.segment_id or next_segment_id(work), kind = "belt",
                capacity_per_second = old.capacity_per_second, allocations = {}, flow_id = old.flow_id,
                flow_ids = old.flow_ids, direction = old.splitter_direction, length = 1}
            for _, allocation in ipairs(old.allocations or {}) do
                segment.allocations[#segment.allocations + 1] = {flow_id=allocation.flow_id,sink=allocation.sink,rate_per_second=allocation.rate_per_second}
            end
            local entity = {id=next_entity_id(work),name=work.belt.belt,position=entity_position(x,y),
                direction=segment.direction,dir=segment.direction,flow_id=segment.flow_id,segment_id=segment.segment_id}
            work.segments[#work.segments+1]=segment
            work.segments_by_cell[key]=segment
            work.entities[#work.entities+1]=entity
            work.entity_by_segment[segment.segment_id]=entity
        end
        for _, binding in ipairs(work.bindings or {}) do if binding.segment_id == old.segment_id then binding.segment_id = keys[1] and old.segment_id end end
        changed = true
    end
    end
end

prune_dead_route_segments = function(work)
    untangle_splitter_chains(work)
    --Every route endpoint counts as a feed: a hand drop, a pickup tile or an edge cell. Binding sources alone missed
    --a machine's own output hand when its flow leaves at the map edge, and the sweep deleted a live product line
    --(round 37, tests/test_route_collision.lua RX1).
    --(`endpoint_by_id` is keyed by port id, and a machine port and an edge port can share one, so read the demands.)
    local sources = {}
    local function mark(endpoint) if endpoint and endpoint.x and endpoint.y then sources[coordinate_key(endpoint.x, endpoint.y)] = true end end
    for _, endpoint in pairs(work.endpoint_by_id or {}) do mark(endpoint) end
    for _, demand in ipairs(work.demands or {}) do
        mark(demand.source); mark(demand.sink)
        for _, candidate in ipairs(demand.source_candidates or {}) do mark(candidate) end
    end
    local changed = true
    while changed do
        changed = false
        local fed = {}
        for _, segment in ipairs(work.segments or {}) do
            if segment.underground then
                if segment.underground_entry_key then fed[segment.underground_exit_key] = true end
                if segment.underground_exit_key then
                    local dx,dy=Grid.dir_vector(segment.direction)
                    if dx then fed[coordinate_key(segment.underground_exit_x+dx,segment.underground_exit_y+dy)] = true end
                end
            elseif segment.splitter then
                local dx,dy=Grid.dir_vector(segment.splitter_direction)
                local sx,sy=coordinate_from_key(segment.splitter_second_key or "")
                if dx and sx then
                    fed[coordinate_key(segment.splitter_anchor_x+dx,segment.splitter_anchor_y+dy)] = true
                    fed[coordinate_key(sx+dx,sy+dy)] = true
                end
            elseif segment.kind == "belt" then
                local dx,dy=Grid.dir_vector(segment.direction)
                if dx then
                    for key,owner in pairs(work.segments_by_cell or {}) do
                        if owner == segment then
                            local x,y=coordinate_from_key(key)
                            fed[coordinate_key(x+dx,y+dy)] = true
                        end
                    end
                end
            end
        end
        local remove = {}
        local splitter_remove = {}
        for _, segment in ipairs(work.segments or {}) do
            if segment.splitter then
                local dx, dy = Grid.dir_vector(segment.splitter_direction)
                local sx, sy = coordinate_from_key(segment.splitter_second_key or "")
                if dx and sx then
                    local first = fed[coordinate_key(segment.splitter_anchor_x - dx, segment.splitter_anchor_y - dy)]
                    local second = fed[coordinate_key(sx - dx, sy - dy)]
                    --A branch splitter is fed on one input only; it is dead only when nothing feeds either input
                    --and no hand drops onto it.
                    local own = sources[coordinate_key(segment.splitter_anchor_x, segment.splitter_anchor_y)]
                        or sources[segment.splitter_second_key or ""]
                    if not first and not second and not own then splitter_remove[segment.segment_id] = true end
                end
            end
        end
        for key,segment in pairs(work.segments_by_cell or {}) do
            if segment.kind == "belt" and not segment.underground and not segment.splitter
                and not fed[key] and not sources[key] and not segment.fixed then remove[segment.segment_id] = true end
        end
        if next(remove) or next(splitter_remove) then
            changed = true
            local kept={}
            for _,segment in ipairs(work.segments) do if not remove[segment.segment_id] and not splitter_remove[segment.segment_id] then kept[#kept+1]=segment end end
            work.segments=kept
            for key,segment in pairs(work.segments_by_cell) do if remove[segment.segment_id] or splitter_remove[segment.segment_id] then work.segments_by_cell[key]=nil end end
            local entities={}
            for _,entity in ipairs(work.entities) do
                if remove[entity.segment_id] or splitter_remove[entity.segment_id] then entity._route_removed=true else entities[#entities+1]=entity end
            end
            work.entities=entities
            for id in pairs(remove) do work.entity_by_segment[id]=nil end
            for id in pairs(splitter_remove) do work.entity_by_segment[id]=nil end
        end
    end
    audit_route_work(work)
end

--Underground inputs fed from the side: the player's rule is that a side-load is a last resort, so the
--re-route pass weighs each one like SIDELOAD_UNDERGROUND_COST belts.
local function side_fed_inputs(work)
    local count = 0
    for _, segment in ipairs(work.segments) do
        if segment.underground and segment.underground_entry_x then
            local dx, dy = Grid.dir_vector(segment.direction)
            local behind = dx and work.segments_by_cell[coordinate_key(segment.underground_entry_x - dx,
                segment.underground_entry_y - dy)]
            if not behind or behind.direction ~= segment.direction then count = count + 1 end
        end
    end
    return count
end

local function route_weight(work)
    return #work.entities + SIDELOAD_UNDERGROUND_COST * side_fed_inputs(work)
end

--The source inserter deposits on the far R lane. Curves preserve that lane. At a side entry, validator's
--physical walk puts the entering flow on the lane nearest its approach side; prove that it is L before keeping.
local function merge_lane_witness(work, path, candidate, flow_a, a_lane)
    local target_index
    for i, cell in ipairs(path or {}) do
        if cell.x == candidate.x and cell.y == candidate.y then target_index=i; break end
    end
    if not target_index then return false end
    local target_segment=work.segments_by_cell[coordinate_key(candidate.x,candidate.y)]
    if not target_segment or target_segment.direction==nil then return false end
    if target_index < 2 then return false end
    local adx,ady=Grid.dir_vector(target_segment.direction)
    local behind=path[target_index-1]
    if not adx or behind.x~=candidate.x-adx or behind.y~=candidate.y-ady then return false end
    local behind_segment=work.segments_by_cell[coordinate_key(behind.x,behind.y)]
    if not behind_segment or behind_segment.direction~=target_segment.direction then return false end
    local rx,ry=Grid.dir_vector(Grid.rotate_dir(target_segment.direction,4))
    if not rx then return false end
    local entering_dot=candidate.dx*rx+candidate.dy*ry
    local b_lane=entering_dot>0 and "R" or "L"
    if b_lane==a_lane then return false end
    for i=1,#path do
        local cell=path[i]
        local segment=work.segments_by_cell[coordinate_key(cell.x,cell.y)]
        if not segment or segment.underground or segment.splitter then return false end
        if i < target_index and (not segment_has_flow(segment,flow_a) or segment_flow_count(segment) ~= 1) then return false end
        if i >= target_index and segment_flow_count(segment) > 2 then return false end
    end
    return true
end

local function source_lane(work, endpoint, flow_id)
    local function same_id(a,b)
        a,b=tostring(a or ""),tostring(b or "")
        return a==b or a:gsub("^m:","")==b:gsub("^m:","")
    end
    for _,run in ipairs(work.belt_runs or {}) do
        if run.role=="out" then
            local carries=false
            for _,id in ipairs(run.flows or {}) do if id==flow_id then carries=true end end
            if carries then
                for _,hand_id in ipairs(run.hand_ids or {}) do
                    for _,hand in ipairs(work.input_entities or {}) do
                        if same_id(hand.id,hand_id)
                            and (endpoint.inserter_id == nil or same_id(endpoint.inserter_id, hand_id))
                            and (hand.role=="output" or hand.direction=="output") then
                            local drop=hand.drop_position or hand.drop
                            local hx,hy=finite(hand.x),finite(hand.y)
                            local tx,ty=finite(drop and drop.x),finite(drop and drop.y)
                            if hx and hy and tx and ty then
                                local rx,ry=Grid.dir_vector(Grid.rotate_dir(run.dir,4))
                                local dot=(hx-tx)*rx+(hy-ty)*ry
                                return dot>0 and "L" or "R", true
                            end
                        end
                    end
                end
            end
        end
    end
    -- A source without a represented hand follows the row contract's far-lane drop convention.
    return "R", false
end

--The player placed v4 on 2026-09-23 and boxed two belts: "Why these bends?".  Grouping fixes each hand's
--tile before any belt exists, so the belt bent to reach it: science input (11,5) picked from (12,5) off a run
--along y=6, and science output (16,10) dropped on (16,9) beside its dive at (17,7).  A hand may move one tile
--along its machine face (the search names the legal moves as `slide_options`); its port tile moves with it.
--Returns an undo, or nil when a new tile is taken.
local function slide_endpoint(work, endpoint, dx, dy)
    local port_x, port_y = endpoint.x + dx, endpoint.y + dy
    local hand_x, hand_y = endpoint.hand_x + dx, endpoint.hand_y + dy
    local port_key, hand_key = coordinate_key(port_x, port_y), coordinate_key(hand_x, hand_y)
    if not inside_grid(work, port_x, port_y) or not inside_grid(work, hand_x, hand_y) then return nil end
    if work.segments_by_cell[port_key] or work.segments_by_cell[hand_key] then return nil end
    if work.underground_cells[port_key] or work.underground_cells[hand_key] then return nil end
    local owner = static_owner(work, port_x, port_y)
    if owner ~= nil and not is_allowed_owner(owner) then return nil end
    if work.obstacles[hand_key] ~= nil or not is_allowed_owner(indexed_cell(work.grid, hand_x, hand_y)) then return nil end
    if work.port_cells[hand_key] ~= nil then return nil end
    for port_id in pairs((work.port_cells[port_key] or {})._port_owners or {}) do
        if port_id ~= endpoint.port_id then return nil end
    end
    local old_hand_key = coordinate_key(endpoint.hand_x, endpoint.hand_y)
    local old = {x = endpoint.x, y = endpoint.y, hand_x = endpoint.hand_x, hand_y = endpoint.hand_y,
        port_cells = work.port_cells, owner = work.obstacles[old_hand_key]}
    work.obstacles[old_hand_key] = nil
    work.obstacles[hand_key] = old.owner or ("hand:" .. tostring(endpoint.port_id))
    endpoint.x, endpoint.y, endpoint.hand_x, endpoint.hand_y = port_x, port_y, hand_x, hand_y
    work.port_cells = reserve_port_cells(work)
    old.hand_key, old.old_hand_key = hand_key, old_hand_key
    return old
end

--The undo is plain data, never a closure: the improve pass now spans game ticks, so it lives in storage.
local function unslide_endpoint(work, endpoint, old)
    work.obstacles[old.hand_key] = nil
    work.obstacles[old.old_hand_key] = old.owner
    endpoint.x, endpoint.y, endpoint.hand_x, endpoint.hand_y = old.x, old.y, old.hand_x, old.hand_y
    work.port_cells = old.port_cells
end

--A hop moves the hand to another face and rotates the belt heading with that face. Its undo is plain data so
--the improve pass can be saved and resumed between game ticks.
local function hop_endpoint(work, endpoint, option)
    local port_x, port_y, hand_x, hand_y = option.port_x, option.port_y, option.hand_x, option.hand_y
    local port_key, hand_key = coordinate_key(port_x, port_y), coordinate_key(hand_x, hand_y)
    if not inside_grid(work, port_x, port_y) or not inside_grid(work, hand_x, hand_y) then return nil end
    if work.segments_by_cell[port_key] or work.segments_by_cell[hand_key] then return nil end
    if work.underground_cells[port_key] or work.underground_cells[hand_key] then return nil end
    local owner = static_owner(work, port_x, port_y)
    if owner ~= nil and not is_allowed_owner(owner) then return nil end
    if work.obstacles[hand_key] ~= nil or not is_allowed_owner(indexed_cell(work.grid, hand_x, hand_y)) then return nil end
    if work.port_cells[hand_key] ~= nil then return nil end
    for port_id in pairs((work.port_cells[port_key] or {})._port_owners or {}) do
        if port_id ~= endpoint.port_id then return nil end
    end
    local old_hand_key = coordinate_key(endpoint.hand_x, endpoint.hand_y)
    local old = {x = endpoint.x, y = endpoint.y, hand_x = endpoint.hand_x, hand_y = endpoint.hand_y,
        travel_dir = endpoint.travel_dir, port_cells = work.port_cells, owner = work.obstacles[old_hand_key],
        hand_key = hand_key, old_hand_key = old_hand_key}
    work.obstacles[old_hand_key] = nil
    work.obstacles[hand_key] = old.owner or ("hand:" .. tostring(endpoint.port_id))
    endpoint.x, endpoint.y, endpoint.hand_x, endpoint.hand_y = port_x, port_y, hand_x, hand_y
    endpoint.travel_dir = Grid.rotate_dir(endpoint.travel_dir, (option.turns or 0) * 4)
    work.port_cells = reserve_port_cells(work)
    return old
end

local function unhop_endpoint(work, endpoint, old)
    work.obstacles[old.hand_key] = nil
    work.obstacles[old.old_hand_key] = old.owner
    endpoint.x, endpoint.y, endpoint.hand_x, endpoint.hand_y = old.x, old.y, old.hand_x, old.hand_y
    endpoint.travel_dir = old.travel_dir
    work.port_cells = old.port_cells
end

local function find_binding(work, wanted)
    for _, candidate in ipairs(work.bindings or {}) do
        if candidate.source_port_id == wanted[1] and candidate.sink_port_id == wanted[2]
            and candidate.rate_per_second == wanted[3] then return candidate end
    end
end

local function bindings_on_port(work, port_id)
    local count = 0
    for _, binding in ipairs(work.bindings or {}) do
        if binding.source_port_id == port_id or binding.sink_port_id == port_id then count = count + 1 end
    end
    return count
end

--One re-route trial, resumable: start lifts the path, applies an optional hand slide and begins the search; run
--spends one op per search step and stops when the budget does; finish appends and weighs.  The player's in-game
--generate ran 10+ minutes at 3 UPS on 2026-09-23 because this pass ran inside ONE game tick.
--A trial start/commit copies the whole route state (route_snapshot) and walks every binding's chain; ~2-3 ms on
--the green sheet, so it is charged ~300 ops (one op ~8 us).
local IMPROVE_TRIAL_OPS = 300
local IMPROVE_MAX_STEPS = 200000

local function trial_start(work, wanted, demand, option)
    local trial = {option = option, steps = 0, done = false}
    if option and option.multi_bindings then
        trial.multi, trial.index, trial.demands = true, 1, {}
        for _, spec in ipairs(option.multi_bindings) do
            local binding = find_binding(work, spec)
            local d
            for _, candidate in ipairs(work.demands or {}) do
                if candidate.source.port_id == spec[1] and candidate.sink.port_id == spec[2] then d = candidate; break end
            end
            if not binding or not d or not lift_binding(work, binding) then trial.done = true; return trial end
            trial.demands[#trial.demands + 1] = d
        end
        if option.hop then trial.hop = hop_endpoint(work, option.endpoint, option.hop)
        else trial.slide = slide_endpoint(work, option.endpoint, option.dx, option.dy) end
        if not trial.slide and not trial.hop then trial.done = true; return trial end
        work.free_source_heading, work.allow_bury = true, true
        --A route demand carries `amount`; a binding carries `rate_per_second`.
        trial.amount = trial.demands[1].amount
        trial.search = begin_search(work, trial.demands[1], trial.amount, 1)
        return trial
    end
    local binding = find_binding(work, wanted)
    if not binding or not lift_binding(work, binding) then trial.done = true; return trial end
    if option then
        if option.hop then trial.hop = hop_endpoint(work, option.endpoint, option.hop)
        else trial.slide = slide_endpoint(work, option.endpoint, option.dx, option.dy) end
        if not trial.slide and not trial.hop then trial.refused = true; trial.done = true; return trial end
    end
    trial.amount = binding.rate_per_second
    work.free_source_heading, work.allow_bury = true, true
    trial.search = begin_search(work, demand, trial.amount, 1)
    return trial
end

local function trial_run(work, trial, ops)
    local used = 0
    while not trial.done and used < ops do
        if trial.steps >= IMPROVE_MAX_STEPS then trial.done = true; break end
        trial.steps, used = trial.steps + 1, used + EXPANSION_OPS
        local outcome = search_step(work, trial.search)
        if type(outcome) == "table" then
            if trial.multi then
                local d = trial.demands[trial.index]
                if not append_normal_path(work, d, outcome, d.amount) then trial.done = true
                else
                    trial.index = trial.index + 1
                    if trial.index > #trial.demands then trial.done = true
                    else
                        d = trial.demands[trial.index]
                        trial.search = begin_search(work, d, d.amount, 1)
                    end
                end
            else trial.path, trial.done = outcome, true end
        elseif outcome == "failed" then trial.done = true end
    end
    return used
end

--Returns the new weight, or nil when no path was laid or a binding lost its sink.  A lift may take a pair or a
--shared tile another path's walk missed; a re-route that leaves any binding short of its sink is smaller only
--because it broke something, so it never counts.
local function trial_finish(work, trial, demand)
    work.free_source_heading, work.allow_bury = nil, nil
    if trial.multi then
        if trial.done and trial.index > #trial.demands and all_bindings_reach_sinks(work) then return route_weight(work) end
        return nil
    end
    if trial.path and append_normal_path(work, demand, trial.path, trial.amount) and all_bindings_reach_sinks(work) then
        return route_weight(work)
    end
    return nil
end

local function trial_undo(work, trial)
    if trial.slide then unslide_endpoint(work, trial.option.endpoint, trial.slide) end
    if trial.hop then unhop_endpoint(work, trial.option.endpoint, trial.hop) end
end

--A binding names one live segment of its path.  A kept re-route may delete that segment; point the binding at
--the first live tile of its own path, sink end first.
local function reanchor_bindings(work)
    local live = {}
    for _, segment in ipairs(work.segments) do live[segment.segment_id] = segment end
    for _, binding in ipairs(work.bindings) do
        if not live[binding.segment_id] then
            for _, key in ipairs(binding_path(work, binding) or {}) do
                local segment = work.segments_by_cell[key]
                if segment and segment_has_flow(segment, binding.flow_id) then binding.segment_id = segment.segment_id; break end
            end
        end
    end
end

improve_begin = function(work)
    --Bindings are named by fields, never held by reference: a restored snapshot replaces every table.
    local order = {}
    for _, binding in ipairs(work.bindings or {}) do
        order[#order + 1] = {binding.source_port_id, binding.sink_port_id, binding.rate_per_second}
    end
    work.port_slides = work.port_slides or {}
    return {order = order, index = 0, stage = "next", improved = 0, refused = {}}
end

--Advance the improve pass by at most about `ops` ops; returns ops used and whether the pass finished.  The trials
--and their order are exactly those of the one-shot pass, so the kept layout does not depend on the budget.
improve_step = function(work, st, ops)
    local used = 0
    while used < ops do
        if st.stage == "next" then
            used = used + 1
            st.index = st.index + 1
            local wanted = st.order[st.index]
            if not wanted then
                if not st.retrying and st.improved > 0 and #st.refused > 0 then
                    st.order, st.index, st.retrying = st.refused, 0, true
                    st.refused = {}
                    used = used + 1
                    break
                end
                reanchor_bindings(work)
                work.counters.routes_improved = st.improved
                -- Rear merge trials run after the ordinary reroutes have reached their fixed point.
                if not st.merges then
                    st.merges, st.merge_index = {}, 1
                    st.merge_baseline = route_snapshot(work)
                    local seen = {}
                    for _, rear in pairs(work.endpoint_by_id or {}) do
                        if rear.port_id == "row:in:rear" then
                            local feeds_by_flow = {}
                            for _, binding in ipairs(work.bindings or {}) do
                                if binding.sink_port_id ~= rear.port_id then
                                    local ep = work.endpoint_by_id[binding.sink_port_id]
                                    if ep and ep.row_port and ep.role == "in" and ep.block_id == rear.block_id then
                                        feeds_by_flow[ep.flow_id] = feeds_by_flow[ep.flow_id] or {}
                                        feeds_by_flow[ep.flow_id][#feeds_by_flow[ep.flow_id] + 1] = binding
                                    end
                                end
                            end
                            local flow_a, flow_b = rear.flow_ids and rear.flow_ids[1], rear.flow_ids and rear.flow_ids[2]
                            local feeds_a, feeds_b = feeds_by_flow[flow_a] or {}, feeds_by_flow[flow_b] or {}
                            if feeds_a[1] and feeds_b[1] then
                                local a, b = feeds_a[1], feeds_b[1]
                                local source_a, source_b = work.endpoint_by_id[a.source_port_id], work.endpoint_by_id[b.source_port_id]
                                local dx,dy=Grid.dir_vector(rear.travel_dir)
                                local ahead_a=source_a and (source_a.x-rear.x)*dx+(source_a.y-rear.y)*dy
                                local ahead_b=source_b and (source_b.x-rear.x)*dx+(source_b.y-rear.y)*dy
                                local rx,ry=Grid.dir_vector(Grid.rotate_dir(rear.travel_dir,4))
                                local side_a=source_a and (source_a.x-rear.x)*rx+(source_a.y-rear.y)*ry
                                local side_b=source_b and (source_b.x-rear.x)*rx+(source_b.y-rear.y)*ry
                                --The trial is for two sources approaching the rear door from behind it, on one side
                                --of the row. A source already beyond the door cannot make the player's belt shape.
                                if ahead_a and ahead_b and ahead_a<0 and ahead_b<0 and side_a*side_b>=0 then
                                    local first=#st.merges+1
                                    st.merges[#st.merges + 1] = {rear=rear, a=a, b=b,group_start=first,group_end=first+1}
                                    st.merges[#st.merges + 1] = {rear=rear, a=b, b=a,group_start=first,group_end=first+1}
                                end
                            end
                        end
                    end
                    if #st.merges > 0 then st.stage = "merge_start"; break end
                end
                return used, true
            end
            local demand
            for _, candidate in ipairs(work.demands or {}) do
                if candidate.source and candidate.sink and candidate.source.port_id == wanted[1]
                    and candidate.sink.port_id == wanted[2] then demand = candidate; break end
            end
            if demand and find_binding(work, wanted) then
                --Option 1 keeps both hands; then try the offered slides and hops for each hand.  A hand may move
                --only when this path is the only one on its port, so no other belt loses its end tile.
                local options = {false}
                for _, endpoint in ipairs({demand.sink, demand.source}) do
                    local port_bindings = {}
                    for _, b in ipairs(work.bindings or {}) do
                        if b.source_port_id == endpoint.port_id or b.sink_port_id == endpoint.port_id then
                            port_bindings[#port_bindings + 1] = {b.source_port_id,b.sink_port_id,b.rate_per_second}
                        end
                    end
                    local function add_option(option)
                        if #port_bindings > 1 then option.multi_bindings = port_bindings end
                        options[#options + 1] = option
                    end
                    if endpoint.slide_options and not endpoint.perimeter then
                        for _, slide in ipairs(endpoint.slide_options) do
                            add_option({endpoint = endpoint, dx = slide.dx, dy = slide.dy})
                        end
                    end
                    if endpoint.hop_options and not endpoint.perimeter then
                        for _, hop in ipairs(endpoint.hop_options) do
                            add_option({endpoint = endpoint, hop = hop})
                        end
                    end
                end
                st.wanted, st.demand, st.options = wanted, demand, options
                st.before = route_weight(work)
                st.best, st.best_weight, st.option_index = nil, st.before, 1
                st.stage = "trial_start"
            end
        elseif st.stage == "trial_start" or st.stage == "commit_start" then
            local commit = st.stage == "commit_start"
            st.snapshot = route_snapshot(work)
            st.trial = trial_start(work, st.wanted, st.demand, st.options[commit and st.best or st.option_index] or nil)
            st.stage = commit and "commit_run" or "trial_run"
            used = used + IMPROVE_TRIAL_OPS
        elseif st.stage == "trial_run" or st.stage == "commit_run" then
            used = used + trial_run(work, st.trial, ops - used)
            if st.trial.done then st.stage = st.stage == "trial_run" and "trial_end" or "commit_end" end
        elseif st.stage == "trial_end" then
            if st.trial.refused then
                st.refused[#st.refused + 1] = st.wanted
            end
            local weight = trial_finish(work, st.trial, st.demand)
            if weight and weight < st.best_weight then st.best, st.best_weight = st.option_index, weight end
            restore_route_snapshot(work, st.snapshot)
            trial_undo(work, st.trial)
            st.snapshot, st.trial = nil, nil
            st.option_index = st.option_index + 1
            if st.option_index <= #st.options then st.stage = "trial_start"
            elseif st.best then st.stage = "commit_start"
            else st.stage = "next" end
            used = used + IMPROVE_TRIAL_OPS
        elseif st.stage == "commit_end" then
            local option = st.options[st.best] or nil
            local weight = trial_finish(work, st.trial, st.demand)
            if weight and weight < st.before then
                st.improved = st.improved + 1
                if option then
                    local port_id = option.endpoint.port_id
                    if option.hop then
                        local hop = option.hop
                        work.port_slides[port_id] = {hop = {hand_x = hop.hand_x, hand_y = hop.hand_y,
                            port_x = hop.port_x, port_y = hop.port_y, turns = hop.turns}}
                        --Slides run along the hand's first face; on the new face they would pull it off the machine.
                        option.endpoint.hop_options, option.endpoint.slide_options = nil, nil
                    else
                        local slide = work.port_slides[port_id] or {dx = 0, dy = 0}
                        if slide.hop then
                            local hop = slide.hop
                            work.port_slides[port_id] = {hop = {hand_x = hop.hand_x + option.dx, hand_y = hop.hand_y + option.dy,
                                port_x = hop.port_x + option.dx, port_y = hop.port_y + option.dy, turns = hop.turns}}
                        else
                            work.port_slides[port_id] = {dx = slide.dx + option.dx, dy = slide.dy + option.dy}
                        end
                        option.endpoint.slide_options = nil
                    end
                end
            else
                restore_route_snapshot(work, st.snapshot)
                trial_undo(work, st.trial)
            end
            st.snapshot, st.trial = nil, nil
            st.stage = "next"
            used = used + IMPROVE_TRIAL_OPS
        elseif st.stage == "merge_start" then
            local pair = st.merges[st.merge_index]
            if not pair then
                reanchor_bindings(work)
                work.counters.routes_improved = st.improved
                return used, true
            end
            if st.active_group ~= pair.group_start then
                st.active_group=pair.group_start
                st.pair_base=route_snapshot(work)
                st.pair_best=nil
                st.pair_best_weight=math.huge
            end
            st.snapshot = route_snapshot(work)
            local ba, bb = find_binding(work, {pair.a.source_port_id,pair.a.sink_port_id,pair.a.rate_per_second}),
                find_binding(work, {pair.b.source_port_id,pair.b.sink_port_id,pair.b.rate_per_second})
            st.pair, st.accepted = pair, false
            local lifted_a, lifted_b = ba and lift_binding(work, ba, true), bb and lift_binding(work, bb, true)
            if ba and bb and lifted_a and lifted_b then
                local da, db
                for _, d in ipairs(work.demands or {}) do
                    if d.source.port_id == pair.a.source_port_id then da = da or d end
                    if d.source.port_id == pair.b.source_port_id then db = db or d end
                end
                if da and db then
                    st.da, st.db = {}, {}
                    for k,v in pairs(da) do st.da[k]=v end
                    for k,v in pairs(db) do st.db[k]=v end
                    st.da.sink, st.da.sink_port_id = pair.rear, pair.rear.port_id
                    st.da.binding_sink_port_id = pair.rear.port_id
                    st.merge_search = begin_search(work, st.da, pair.a.rate_per_second, 1)
                    st.merge_phase, st.merge_steps = "a", 0
                    work.free_source_heading, work.allow_bury = true, true
                else st.merge_phase = "failed" end
            else st.merge_phase = "failed" end
            st.stage = "merge_run"
            used = used + IMPROVE_TRIAL_OPS
        elseif st.stage == "merge_run" then
            local phase = st.merge_phase
            if phase == "a" or phase == "b" then
                local outcome = search_step(work, st.merge_search)
                used = used + EXPANSION_OPS; st.merge_steps = st.merge_steps + 1
                if type(outcome) == "table" then
                    if phase == "a" then
                        if append_normal_path(work, st.da, outcome, st.pair.a.rate_per_second) then
                            st.a_path = outcome
                            local candidates = {}
                            for _, cell in ipairs(outcome) do
                                local seg = work.segments_by_cell[coordinate_key(cell.x,cell.y)]
                                local reserved = work.port_cells[coordinate_key(cell.x,cell.y)]
                                local merge_reserved = reserved == nil or reserved["flow:"..tostring(st.da.flow_id)]
                                    or reserved["flow:"..tostring(st.db.flow_id)] or reserved[st.pair.rear.port_id]
                                for _, endpoint in pairs(work.endpoint_by_id or {}) do
                                    if endpoint.x == cell.x and endpoint.y == cell.y then merge_reserved = false; break end
                                end
                                if seg and not seg.underground and not seg.splitter and not seg.fixed and merge_reserved then
                                    for _, side in ipairs({Grid.rotate_dir(seg.direction, 4),Grid.rotate_dir(seg.direction, 12)}) do
                                        local dx,dy=Grid.dir_vector(side)
                                        local near = side == Grid.rotate_dir(seg.direction,4)
                                        -- Source-side feeds occupy the far lane; the opposite side is the open near lane.
                                        local far_side = Grid.rotate_dir(seg.direction,4)
                                        candidates[#candidates+1]={x=cell.x,y=cell.y,dx=dx,dy=dy}
                                    end
                                end
                            end
                            st.candidates, st.candidate_index = candidates, 1
                            st.merge_phase = "bstart"
                        else st.merge_phase = "failed" end
                    else
                        st.merge_b_path = outcome
                        if append_normal_path(work, st.db_trial, outcome, st.pair.b.rate_per_second) then
                            local target_index
                            for i, cell in ipairs(st.a_path or {}) do
                                if cell.x == st.db_trial.sink.x and cell.y == st.db_trial.sink.y then target_index=i; break end
                            end
                            local ok = target_index ~= nil
                            for i=target_index or 1,#(st.a_path or {}) do
                                local cell=st.a_path[i]
                                local segment=work.segments_by_cell[coordinate_key(cell.x,cell.y)]
                                if not segment or segment.underground or segment.splitter
                                    or (i>target_index and segment_total(segment)+st.pair.b.rate_per_second > segment.capacity_per_second+tolerance(segment.capacity_per_second)) then
                                    ok=false; break
                                end
                            end
                            local a_source=work.endpoint_by_id[st.pair.a.source_port_id]
                            local a_lane,a_lane_known=source_lane(work,a_source,st.da.flow_id)
                            if ok and merge_lane_witness(work,st.a_path,st.active_candidate,st.da.flow_id,a_lane) then
                                local sink=sink_key(st.pair.rear,work,st.pair.rear.port_id)
                                for i=target_index+1,#st.a_path do
                                    local cell=st.a_path[i]
                                    local segment=work.segments_by_cell[coordinate_key(cell.x,cell.y)]
                                    register_segment_flow(segment,st.db.flow_id)
                                    add_allocation(segment,st.db.flow_id,sink,st.pair.b.rate_per_second)
                                end
                                -- The side entry rides A's trunk from the merge tile to the rear door.
                                for _,binding in ipairs(work.bindings) do
                                    if binding.source_port_id==st.pair.b.source_port_id and binding.sink_port_id==st.pair.rear.port_id then
                                        binding.segment_id=work.segments_by_cell[coordinate_key(st.db_trial.sink.x,st.db_trial.sink.y)].segment_id
                                    end
                                end
                                st.merge_phase="finish"
                            else
                                restore_route_snapshot(work, st.trial_snapshot)
                                st.candidate_index=st.candidate_index+1
                                st.merge_phase=st.candidate_index<=#st.candidates and "bstart" or "failed"
                            end
                        else
                            restore_route_snapshot(work, st.trial_snapshot)
                            st.candidate_index = st.candidate_index + 1
                            st.merge_phase = "bstart"
                        end
                    end
                elseif outcome == "failed" or st.merge_steps > IMPROVE_MAX_STEPS then
                    if phase == "b" then
                        st.candidate_index = st.candidate_index + 1
                        st.merge_phase = st.candidate_index <= #(st.candidates or {}) and "bstart" or "failed"
                    else st.merge_phase = "failed" end
                end
            elseif phase == "bstart" then
                local c = st.candidates[st.candidate_index]
                if not c then st.merge_phase = "failed"
                else
                    st.trial_snapshot = route_snapshot(work)
                    st.active_candidate=c
                    local virtual = {x=c.x,y=c.y,port_id=st.pair.rear.port_id,role="in",flow_id=st.db.flow_id,travel_dir=nil}
                    local db = {}; for k,v in pairs(st.db) do db[k]=v end
                    db.sink, db.sink_port_id, db.binding_sink_port_id = virtual, st.pair.rear.port_id, st.pair.rear.port_id
                    st.db_trial=db
                    -- Force the final step to enter the chosen A tile from its open side.
                    st.merge_search=begin_search(work, db, st.pair.b.rate_per_second, 1)
                    st.merge_search.merge_target={x=c.x,y=c.y,from_x=c.x+c.dx,from_y=c.y+c.dy}
                    st.merge_search.target_override=true
                    st.merge_phase="b"
                end
            elseif phase == "finish" then
                work.free_source_heading, work.allow_bury = nil, nil
                if all_bindings_reach_sinks(work) and #work.entities < #st.snapshot.entities then
                    local weight=route_weight(work)
                    if weight<st.pair_best_weight then
                        st.pair_best=route_snapshot(work)
                        st.pair_best_weight=weight
                    end
                else st.merge_phase="failed" end
                restore_route_snapshot(work,st.pair_base)
                st.merge_index=st.merge_index+1
                if st.merge_index>st.pair.group_end then
                    if st.pair_best and #st.pair_best.entities<#st.pair_base.entities then
                        restore_route_snapshot(work,st.pair_best)
                    else restore_route_snapshot(work,st.pair_base) end
                    st.active_group=nil; st.pair_base=nil; st.pair_best=nil
                end
                st.snapshot=nil; st.stage="merge_start"
            else
                work.free_source_heading, work.allow_bury = nil, nil
                restore_route_snapshot(work, st.pair_base)
                st.merge_index=st.merge_index+1; st.snapshot=nil; st.stage="merge_start"
                if st.merge_index>st.pair.group_end then
                    if st.pair_best and #st.pair_best.entities<#st.pair_base.entities then
                        restore_route_snapshot(work,st.pair_best)
                    end
                    st.active_group=nil; st.pair_base=nil; st.pair_best=nil
                end
            end
        end
    end
    return used, false
end

function Route.step(state, budget)
    if state.done then return state end
    if state.cancelled then return Route.cancel(state) end
    budget = budget or {ops = 1}
    local ops = finite(budget.ops, 1)
    if ops < 0 then ops = 0 end
    local work = state.work
    local demand_build_ops = 0
    -- Demand construction is ordered exactly as the original one-shot builder, but one flow is
    -- materialized per operation so large plans do not hide pairing work in Route.begin.
    while ops > 0 and not work.demand_build_done do
        local flow = work.flows[work.demand_build_index]
        if not flow then
            finish_demand_build(work)
            state.cursor.phase = "routing"
            state.progress.phase = "routing"
            state.progress.total_units = #work.demands
            budget.ops = math.max(0, ops)
            return state
        end
        work.demand_build_context = work.demand_build_context or begin_flow_demand_build(work, flow)
        --Finish the floods this pairing row reads, a slice per call (4 ops per flooded cell, ~30 us each).
        local pending
        for _, producer in ipairs(work.demand_build_context.producers or {}) do
            for _, candidate in ipairs(producer.candidates or {}) do
                local flood = pairing_flood(work, candidate)
                if not flood.done then pending = flood; break end
            end
            if pending then break end
        end
        local flow_done = false
        if pending then
            ops = ops - 4 * pairing_flood_step(work, pending, math.max(1, math.floor(ops / 4)))
        else
            flow_done = advance_flow_demand_build(work, work.demand_build_context)
            ops = ops - 1
        end
        demand_build_ops = demand_build_ops + 1
        if flow_done then
            work.demand_build_context = nil
            work.demand_build_index = work.demand_build_index + 1
            state.cursor.flow_index = work.demand_build_index
            state.progress.done_units = state.progress.done_units + 1
        end
        --One candidate producer row is a bounded scheduling unit when more rows remain. Small flows can
        --finish their demand setup and continue into routing in this same call.

    end
    if not work.demand_build_done then budget.ops = ops; return state end
    if work.initial_error then
        if ops > 0 then
            state.errors, state.done, state.ok = {work.initial_error}, true, false
            state.progress.phase, ops = "failed", ops - 1
        end
        budget.ops = math.max(0, ops)
        return state
    end
    while ops > 0 and not state.done do
        local demand = work.demands[state.cursor.demand_index]
        if not demand then
            if state.tidy == false then
                state.result, state.done, state.ok = result_for(work), true, true
                state.progress.phase = "done"
                break
            elseif not work.improved then
                work.improve_state = work.improve_state or improve_begin(work)
                local used, finished = improve_step(work, work.improve_state, ops)
                ops = math.max(0, ops - used)
                if finished then work.improved, work.improve_state = true, nil end
            end
            if not work.improved then break end
            if state.tidy ~= false then
                unbury_empty_pairs(work)
                prune_dead_route_segments(work)
            end
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
                ops = ops - EXPANSION_OPS
                if type(outcome) == "table" then
                    local placed, reason = append_normal_path(work, demand, outcome, amount)
                    work.current = nil
                    if not placed and reason == "crossing-occupied" then
                        --A crossing refused at the COMMIT is a refused crossing, never a refused demand.
                        --The tile it wanted is already taken in the live graph, so a fresh search sees that
                        --and plans round it.  Bounded, because a search that keeps landing on taken tiles
                        --must be allowed to fail honestly rather than spin.
                        demand.crossing_retries = (demand.crossing_retries or 0) + 1
                        local rejection = work.last_route_rejection or {}
                        if rejection.bury and rejection.x ~= nil and rejection.y ~= nil then
                            demand.bury_blocked = demand.bury_blocked or {}
                            demand.bury_blocked[coordinate_key(rejection.x, rejection.y)] = true
                        end
                        if demand.crossing_retries <= 4 then
                            work.current = begin_search(work, demand, amount, 1)
                        elseif not demand.strict_dive then
                            --Steel plate repeatedly aimed at the occupied (65,25) and molten iron at (86,20),
                            --frozen gray + magenta sheet (2026-09-27): retry once with free-tile entrances.
                            demand.strict_dive, demand.no_self_cross = true, true
                            demand.crossing_retries = 0
                            work.current = begin_search(work, demand, amount, 1)
                        else
                            fail_demand(state, work, demand, "BP_R_NO_PATH")
                        end
                    elseif not placed and reason == "splitter-footprint" then
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
                        if work.current == nil then
                            if demand.strict_branch then
                                fail_demand(state, work, demand, "BP_R_NO_PATH")
                            elseif not restart_with_priority(state, work, demand) then
                                demand.strict_branch = true
                                work.current = begin_search(work, demand, amount, 1)
                            end
                        end
                    elseif not placed and reason == "route-discontinuous" and (not demand.no_chain_dive or not demand.no_self_cross) then
                        local two_crossings, revisit = false, false
                        local visited = {}
                        for i = 1, #outcome do
                            local key = coordinate_key(outcome[i].x, outcome[i].y)
                            if visited[key] then revisit = true end
                            visited[key] = true
                            if i > 1 and i < #outcome and is_crossing_step(outcome[i - 1], outcome[i])
                                and is_crossing_step(outcome[i], outcome[i + 1]) then
                                two_crossings = true
                            end
                        end
                        two_crossings = two_crossings and not demand.no_chain_dive
                        revisit = revisit and not demand.no_self_cross
                        if two_crossings or revisit then
                            if not restart_with_priority(state, work, demand) then
                                --Iron stick's route revisited (123,18) after surfacing on the frozen gray + magenta
                                --sheet (2026-09-27); only the relevant failed-path shape gets a retry flag.
                                if two_crossings then demand.no_chain_dive = true end
                                if revisit then demand.no_self_cross = true end
                                work.current = begin_search(work, demand, amount, 1)
                            end
                        else
                            fail_demand(state, work, demand, "BP_R_NO_PATH")
                        end
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
                    elseif not demand.allow_ride and not search.saw_fluid_mix and not search.saw_capacity
                        and demand.kind ~= "pipe" and has_rideable_pair(work, demand.flow_id) then
                        --Last resort before the demand fails: search once more, now allowed to ride a same-flow
                        --underground pair already laid (see search_step).
                        demand.allow_ride = true
                        work.current = begin_search(work, demand, amount, 1)
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
    budget.ops = math.max(0, ops)
    return state
end

return Route
