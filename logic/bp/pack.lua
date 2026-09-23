--MaxRects with Best Short Side Fit: put opaque rectangles into a rectangle that already has holes in it.
--
--Owned by lane W3-pack. It never learns what a block contains, which flow it carries or why it is that size;
--that ignorance is what keeps it small and testable. Insertion order is decided by the search, not here.
--
--  Pack.begin{area = TileRect, obstacles = {TileRect}, blocks = {{block_id, w, h, allowed_dirs}},
--             limits = {max_free_regions = int}} -> state
--  Pack.step(state, budget) -> state          budget = {ops = int}, decremented inside the region scan
--  state.result = {placements = {{block_id, x, y, dir, w, h}}, free_regions = {TileRect},
--                  stats = {peak_free_regions, scans}}
--  state.errors = {{code = "BP_P_NO_FIT", block_id}} | {{code = "BP_P_REGION_LIMIT"}}
--
--Yielding happens inside the scan over free regions, not between blocks: one block against many regions is
--already enough work to hold a tick.
local Pack = {}
local Grid = require "logic.bp.grid"
local Buffer = require "logic.bp.buffer"

local DIRECTIONS = {Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}
--An origin with ports evaluates multiple attachment cells and route approaches. Account for that bounded
--inner work so one module call stays short even when the search budget is large.  256 made one op ~0.5 us, so a
--2000-op game tick did ~1 ms and the player's sheet needed 6101 pack ticks; 16 gives ~8 us per op, ~16 ms per
--tick (measured 2026-09-23 on legalcopilot-dev with tools/speed_probe.sh).
local PORT_ORIGIN_OPS = 16

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback
end

local function copy_rect(rect)
    return Grid.rect(rect.x, rect.y, rect.w, rect.h)
end

local function copy_directions(allowed_dirs)
    if allowed_dirs == nil then
        local result = {}
        for index, direction in ipairs(DIRECTIONS) do result[index] = direction end
        return result
    end

    local result, seen = {}, {}
    for _, direction in ipairs(allowed_dirs) do
        if not seen[direction] then
            result[#result + 1] = direction
            seen[direction] = true
        end
    end
    table.sort(result)
    return result
end

local function copy_port(port, index)
    return {
        port_id = port.port_id or port.id or tostring(index),
        role = port.role,
        inserter_id = port.inserter_id,
        --A row port is fixed at its belt run's head or end (docs/contracts/row_block.md), like a hand's port.
        row_port = port.row_port == true or nil,
        pinned = port.inserter_id ~= nil or port.row_port == true,
        attach_dx = finite(port.attach_dx), attach_dy = finite(port.attach_dy),
        normal_dir = finite(port.normal_dir), travel_dir = finite(port.travel_dir),
    }
end

local function copy_block(block)
    local ports = {}
    for index, port in ipairs(block.ports or block.block_ports or {}) do
        ports[index] = copy_port(port, index)
    end
    local buffer_zones = {}
    for index, zone in ipairs(block.buffer_zones or {}) do
        buffer_zones[index] = {x = zone.x, y = zone.y, w = zone.w, h = zone.h,
            ring = zone.ring, key = zone.key}
    end
    return {
        block_id = block.block_id ~= nil and block.block_id or block.id,
        w = block.w,
        h = block.h,
        allowed_dirs = copy_directions(block.allowed_dirs),
        ports = ports,
        buffer_zones = buffer_zones,
    }
end

local function rotate_buffer_zones(block, x, y, direction)
    local zones = {}
    for _, zone in ipairs(block.buffer_zones or {}) do
        local dx, dy, w, h = Grid.rotate_rect(zone.x, zone.y, zone.w, zone.h,
            block.w, block.h, direction)
        zones[#zones + 1] = {rect = {x = x + dx, y = y + dy, w = w, h = h},
            ring = zone.ring, key = zone.key}
    end
    return zones
end

local function buffer_zones_fit(state, zones)
    for _, candidate in ipairs(zones) do
        for _, placed in ipairs(state.buffer_zones) do
            if Buffer.conflict(candidate, placed) then return false end
        end
    end
    return true
end

local function copy_rects(rects)
    local result = {}
    for index, rect in ipairs(rects or {}) do result[index] = copy_rect(rect) end
    return result
end

--Equivalent to Grid.prune's stable containment rule, with larger rectangles considered first. Keeping
--only maximal rectangles while scanning avoids the quadratic all-pairs pass when a placement fragments space.
local function prune_regions(rects)
    local order = {}
    for i, rect in ipairs(rects) do order[i] = {index = i, rect = rect, area = rect.w * rect.h} end
    table.sort(order, function(a, b)
        if a.area ~= b.area then return a.area > b.area end
        return a.index < b.index
    end)
    local maximal, keep = {}, {}
    for _, item in ipairs(order) do
        local r, contained = item.rect, false
        for _, larger in ipairs(maximal) do
            if larger.x <= r.x and larger.y <= r.y
                and larger.x + larger.w >= r.x + r.w and larger.y + larger.h >= r.y + r.h then
                contained = true
                break
            end
        end
        if not contained then
            keep[item.index] = true
            maximal[#maximal + 1] = r
        end
    end
    local out = {}
    for i, rect in ipairs(rects) do if keep[i] then out[#out + 1] = rect end end
    return out
end

local function set_result(state)
    state.result = {
        placements = state.placements,
        free_regions = state.regions,
        stats = {
            peak_free_regions = state.stats.peak_free_regions,
            scans = state.stats.scans,
        },
    }
end

local function fail(state, code, block_id)
    local error_record = {code = code}
    if block_id ~= nil then error_record.block_id = block_id end
    state.errors[#state.errors + 1] = error_record
    state.done = true
    state.ok = false
    state.progress.phase = "packing"
    set_result(state)
end

local function finish(state)
    state.done = true
    state.ok = true
    state.progress.phase = "packing"
    set_result(state)
end

local function better(candidate, best)
    if best == nil then return true end
    if candidate.short_side ~= best.short_side then return candidate.short_side < best.short_side end
    if candidate.long_side ~= best.long_side then return candidate.long_side < best.long_side end
    if candidate.x ~= best.x then return candidate.x < best.x end
    if candidate.y ~= best.y then return candidate.y < best.y end
    return candidate.dir < best.dir
end

local function slot_key(dx, dy)
    return tostring(dx) .. ":" .. tostring(dy)
end

local function cell_key(x, y) return tostring(x) .. ":" .. tostring(y) end

local function rebuild_indexes(state)
    local free = {}
    for _, region in ipairs(state.regions) do
        for y = region.y, region.y + region.h - 1 do
            for x = region.x, region.x + region.w - 1 do free[cell_key(x, y)] = true end
        end
    end
    state.free_cell_index = free
    local ports, n = {}, 0
    for _, cell in ipairs(state.port_cells or {}) do
        ports[cell_key(cell.x, cell.y)] = true
        n = n + 1
    end
    state.port_cell_index, state.port_cell_count = ports, n
end

local function ensure_port_index(state)
    if state.port_cell_index == nil or state.port_cell_count ~= #(state.port_cells or {}) then
        local ports, n = {}, 0
        for _, cell in ipairs(state.port_cells or {}) do ports[cell_key(cell.x, cell.y)] = true; n = n + 1 end
        state.port_cell_index, state.port_cell_count = ports, n
    end
end

local function edge_slots(w, h)
    local result = {}
    for x = 0, w - 1 do result[#result + 1] = {attach_dx = x, attach_dy = -1, normal_dir = Grid.SOUTH} end
    for x = 0, w - 1 do result[#result + 1] = {attach_dx = x, attach_dy = h, normal_dir = Grid.NORTH} end
    for y = 0, h - 1 do result[#result + 1] = {attach_dx = -1, attach_dy = y, normal_dir = Grid.EAST} end
    for y = 0, h - 1 do result[#result + 1] = {attach_dx = w, attach_dy = y, normal_dir = Grid.WEST} end
    return result
end

local function bounded_slot(slot, w, h)
    return (slot.attach_dx == -1 or slot.attach_dx == w) and slot.attach_dy >= 0 and slot.attach_dy < h
        or (slot.attach_dy == -1 or slot.attach_dy == h) and slot.attach_dx >= 0 and slot.attach_dx < w
end

local function normal_for_slot(slot, w, h)
    if slot.attach_dx == -1 then return Grid.EAST end
    if slot.attach_dx == w then return Grid.WEST end
    if slot.attach_dy == -1 then return Grid.SOUTH end
    if slot.attach_dy == h then return Grid.NORTH end
    return nil
end

local function port_slots(block, port)
    if port._slot_options then return port._slot_options end
    local result, seen = {}, {}
    local function add(slot)
        --A row's second head feed sits inside the envelope beside the head; it keeps its own heading.
        local interior_row_feed = port.row_port and not bounded_slot(slot, block.w, block.h)
        if not bounded_slot(slot, block.w, block.h) and not interior_row_feed then return end
        local key = slot_key(slot.attach_dx, slot.attach_dy)
        if seen[key] then return end
        seen[key] = true
        local normal = interior_row_feed and slot.normal_dir or normal_for_slot(slot, block.w, block.h)
        local travel = port.role == "in" and normal or Grid.dir_opposite(normal)
        if port.row_port and port.travel_dir ~= nil then travel = port.travel_dir end
        result[#result + 1] = {
            attach_dx = slot.attach_dx, attach_dy = slot.attach_dy,
            normal_dir = normal, travel_dir = travel,
        }
    end
    if port.attach_dx ~= nil and port.attach_dy ~= nil then
        add({attach_dx = port.attach_dx, attach_dy = port.attach_dy, normal_dir = port.normal_dir})
    end
    if port.pinned then port._slot_options = result; return result end
    for _, slot in ipairs(edge_slots(block.w, block.h)) do add(slot) end
    port._slot_options = result
    return result
end

local function cell_is_free(state, x, y)
    if x < state.area.x or y < state.area.y
        or x >= state.area.x + state.area.w or y >= state.area.y + state.area.h then
        return false
    end
    ensure_port_index(state)
    return not state.port_cell_index[cell_key(x, y)] and state.free_cell_index[cell_key(x, y)] == true
end

local function inner_cell(state, x, y)
    return x > state.area.x and y > state.area.y
        and x < state.area.x + state.area.w - 1 and y < state.area.y + state.area.h - 1
end

local function placement_avoids_port_cells(state, x, y, w, h)
    ensure_port_index(state)
    for cy = y, y + h - 1 do for cx = x, x + w - 1 do
        if state.port_cell_index[cell_key(cx, cy)] then return false end
    end end
    return true
end

local function world_slot(block, x, y, direction, slot)
    local dx, dy = Grid.rotate_rect(slot.attach_dx, slot.attach_dy, 1, 1, block.w, block.h, direction)
    return x + dx, y + dy
end

local function choose_port_slots(state, block, x, y, direction)
    local entries = {}
    for index, port in ipairs(block.ports or {}) do
        local options = {}
        for _, slot in ipairs(port_slots(block, port)) do
            local world_x, world_y = world_slot(block, x, y, direction, slot)
            local travel = Grid.rotate_dir(slot.travel_dir, direction)
            local dx, dy = Grid.dir_vector(travel)
            local approach_x, approach_y = world_x, world_y
            if port.role == "in" then approach_x, approach_y = approach_x - dx, approach_y - dy
            else approach_x, approach_y = approach_x + dx, approach_y + dy end
            -- The endpoint itself must be free, and the first cell on the route side must also exist. This
            -- is what makes an edge port routable: an input needs a predecessor inside the grid, an output
            -- needs its first successor inside it.
            --A row port and the tile before it also keep off the grid's outer ring: a row feed boxed against
            --the edge has one way in, and the paths laid before it took that way (measured 2026-09-23 on
            --legalcopilot-dev, the player's sheet: copper-ore BP_R_NO_PATH into a furnace row at x=0).
            local inner = not port.row_port or (inner_cell(state, world_x, world_y) and inner_cell(state, approach_x, approach_y))
            if inner and cell_is_free(state, world_x, world_y) and cell_is_free(state, approach_x, approach_y) then
                options[#options + 1] = {slot = slot, x = world_x, y = world_y}
            end
        end
        if #options == 0 then
            if port.pinned and port.attach_dx ~= nil and port.attach_dy ~= nil
                and (port.row_port or bounded_slot(port, block.w, block.h)) then
                return nil, "pinned-free"
            end
            return nil, "no-slot"
        end
        entries[#entries + 1] = {index = index, port = port, options = options}
    end
    table.sort(entries, function(a, b)
        if #a.options ~= #b.options then return #a.options < #b.options end
        local aid = tostring(a.port.port_id or a.index)
        local bid = tostring(b.port.port_id or b.index)
        if aid ~= bid then return aid < bid end
        return a.index < b.index
    end)

    local chosen, used = {}, {}
    local function visit(index)
        if index > #entries then return true end
        local entry = entries[index]
        for _, option in ipairs(entry.options) do
            local key = slot_key(option.x, option.y)
            if not used[key] then
                used[key], chosen[entry.index] = true, option.slot
                if visit(index + 1) then return true end
                used[key], chosen[entry.index] = nil, nil
            end
        end
        return false
    end
    if not visit(1) then return nil end

    local selected = {}
    for index, port in ipairs(block.ports or {}) do
        local slot = chosen[index]
        selected[index] = {
            port_id = port.port_id, index = index,
            attach_dx = slot.attach_dx, attach_dy = slot.attach_dy,
            normal_dir = slot.normal_dir, travel_dir = slot.travel_dir,
        }
    end
    return selected
end

local function scan_origin(state, block, region, direction, x, y)
            local w, h = Grid.rotate_size(block.w, block.h, direction)
            state.counters.origins = state.counters.origins + 1
                local buffer_zones = rotate_buffer_zones(block, x, y, direction)
                if not buffer_zones_fit(state, buffer_zones) then return true end
                if placement_avoids_port_cells(state, x, y, w, h) then
                    local short_side, long_side = Pack.bssf_score(region, w, h)
                    local candidate = {
                        x = x, y = y, dir = direction, w = w, h = h,
                        short_side = short_side, long_side = long_side,
                    }
                    if #block.ports == 0 then
                        if better(candidate, state.cursor.best) then state.cursor.best = candidate end
                    else
                        local slots, reason = choose_port_slots(state, block, x, y, direction)
                        if slots then
                            candidate.port_slots = slots
                            if better(candidate, state.cursor.best) then state.cursor.best = candidate end
                        elseif reason == "pinned-free" then
                            return true
                        end
                    end
                end
                return false
end

local function scan_one(state, block, region)
    local c = state.cursor
    while c.direction_index <= #block.allowed_dirs do
        local direction = block.allowed_dirs[c.direction_index]
        local w, h = Grid.rotate_size(block.w, block.h, direction)
        if region.w < w or region.h < h then
            c.direction_index, c.needs_offset = c.direction_index + 1, false
        elseif c.origin_x == nil then
            c.origin_x, c.origin_y, c.needs_offset = region.x, region.y, false
        else
            local x, y = c.origin_x, c.origin_y
            local pinned_failed = scan_origin(state, block, region, direction, x, y)
            if x == region.x and y == region.y then
                c.needs_offset = pinned_failed
                c.origin_x, c.origin_y = region.x + 1, region.y
                if c.origin_x > region.x + region.w - w then
                    c.origin_x, c.origin_y = region.x, region.y + 1
                end
            else
                c.origin_x = x + 1
                if c.origin_x > region.x + region.w - w then
                    c.origin_x, c.origin_y = region.x, y + 1
                end
            end
            if not c.needs_offset then
                c.direction_index, c.origin_x, c.origin_y = c.direction_index + 1, nil, nil
            elseif c.origin_y > region.y + region.h - h then
                c.direction_index, c.origin_x, c.origin_y, c.needs_offset = c.direction_index + 1, nil, nil, false
            end
            return true
        end
    end
    return false
end

local function reset_region_cursor(cursor)
    cursor.direction_index, cursor.origin_x, cursor.origin_y, cursor.needs_offset = 1, nil, nil, false
end

--Every origin in one free region has the same BSSF score for a given direction. Once a
--better candidate exists, a region whose best possible score is strictly worse cannot
--win; strict comparison keeps equal-score regions in the scan for coordinate tie-breaks.
local function region_can_beat(state, block, region)
    local best = state.cursor.best
    if best == nil then return true end
    for _, direction in ipairs(block.allowed_dirs) do
        local w, h = Grid.rotate_size(block.w, block.h, direction)
        if region.w >= w and region.h >= h then
            local short_side, long_side = Pack.bssf_score(region, w, h)
            if short_side < best.short_side
                or (short_side == best.short_side and long_side <= best.long_side) then
                return true
            end
        end
    end
    return false
end

local function place(state, block)
    local candidate = state.cursor.best
    if candidate == nil then
        fail(state, "BP_P_NO_FIT", block.block_id)
        return
    end

    local placement = {
        block_id = block.block_id,
        x = candidate.x, y = candidate.y, dir = candidate.dir,
        w = candidate.w, h = candidate.h,
        port_slots = candidate.port_slots,
    }
    state.placements[#state.placements + 1] = placement
    local placed_zones = rotate_buffer_zones(block, candidate.x, candidate.y, candidate.dir)
    for _, zone in ipairs(placed_zones) do state.buffer_zones[#state.buffer_zones + 1] = zone end

    --Reserve a routing corridor around the block, never only the block itself.
    --
    --Subtracting the bare placement let the next block sit flush against this one. Every flow leaving either
    --block then had to share whatever gap happened to be left over -- on the player's sheet that was two
    --tiles for ten flows, so the first few belts filled it and every later flow reported BP_R_NO_PATH with
    --its source and sink walled in. Free area was never the problem: 423 of 2916 tiles were in use.
    --
    --The margin is the number of distinct flow lanes this block attaches. Per-inserter ports share a flow's
    --corridor; using the raw port count would reserve a ring wider than the grid can hold.
    local attached_flows = {}
    for _, port in ipairs(block.ports or {}) do
        attached_flows[tostring(port.flow_id or port.full_name or port.port_id or "")] = true
    end
    local margin = 0
    for _ in pairs(attached_flows) do margin = margin + 1 end
    local reserved = placement
    if margin > 0 then
        reserved = {x = placement.x - margin, y = placement.y - margin,
            w = placement.w + margin * 2, h = placement.h + margin * 2}
    end
    local next_regions = {}
    for _, region in ipairs(state.regions) do
        local pieces = Grid.subtract(region, reserved)
        for _, piece in ipairs(pieces) do next_regions[#next_regions + 1] = piece end
    end
    for index, slot in ipairs(candidate.port_slots or {}) do
        local x, y = world_slot(block, candidate.x, candidate.y, candidate.dir, slot)
        state.port_cells[#state.port_cells + 1] = {x = x, y = y}
        --A row port's approach tile is reserved too, so no later block covers the row's one way in or out.
        local port = block.ports and block.ports[index]
        if port and port.row_port and slot.travel_dir ~= nil then
            local dx, dy = Grid.dir_vector(Grid.rotate_dir(slot.travel_dir, candidate.dir))
            if port.role == "in" then dx, dy = -dx, -dy end
            state.port_cells[#state.port_cells + 1] = {x = x + dx, y = y + dy}
        end
    end
    state.regions = prune_regions(next_regions)
    rebuild_indexes(state)
    if #state.regions > state.stats.peak_free_regions then
        state.stats.peak_free_regions = #state.regions
    end

    state.cursor.block_index = state.cursor.block_index + 1
    state.cursor.region_index = 1
    reset_region_cursor(state.cursor)
    state.cursor.best = nil
    state.progress.done_units = state.progress.done_units + 1

    local limit = state.limits.max_free_regions
    if limit ~= nil and #state.regions > limit then
        fail(state, "BP_P_REGION_LIMIT")
    end
end

function Pack.begin(input)
    input = input or {}
    local area = copy_rect(input.area)
    local obstacles = copy_rects(input.obstacles)
    local blocks = {}
    for index, block in ipairs(input.blocks or {}) do blocks[index] = copy_block(block) end

    local regions = Grid.free_regions(area, obstacles)
    local limits = {max_free_regions = input.limits and input.limits.max_free_regions or nil}
    local state = {
        area = area,
        obstacles = obstacles,
        blocks = blocks,
        limits = limits,
        regions = regions,
        placements = {},
        errors = {},
        done = false,
        ok = nil,
        result = nil,
        cursor = {block_index = 1, region_index = 1, best = nil,
            direction_index = 1, origin_x = nil, origin_y = nil, needs_offset = false},
        progress = {phase = "packing", done_units = 0, total_units = #blocks},
        stats = {peak_free_regions = #regions, scans = 0},
        port_cells = {},
        buffer_zones = {},
        counters = {origins = 0},
    }
    rebuild_indexes(state)

    if limits.max_free_regions ~= nil and #regions > limits.max_free_regions then
        fail(state, "BP_P_REGION_LIMIT")
    elseif #blocks == 0 then
        finish(state)
    end
    return state
end

function Pack.step(state, budget)
    if state.done then return state end
    budget = budget or {ops = 0}

    while not state.done do
        local block = state.blocks[state.cursor.block_index]
        if block == nil then
            finish(state)
            break
        end

        if state.cursor.region_index <= #state.regions then
            if budget.ops == nil or budget.ops <= 0 then break end
            local region = state.regions[state.cursor.region_index]
            if state.cursor.direction_index == 1 and state.cursor.origin_x == nil
                and not region_can_beat(state, block, region) then
                state.cursor.region_index = state.cursor.region_index + 1
                reset_region_cursor(state.cursor)
            elseif scan_one(state, block, region) then
                state.stats.scans = state.stats.scans + 1
                budget.ops = budget.ops - math.min(budget.ops, #block.ports > 0 and PORT_ORIGIN_OPS or 1)
            else
                state.cursor.region_index = state.cursor.region_index + 1
                reset_region_cursor(state.cursor)
            end
            if budget.ops <= 0 then break end
        else
            place(state, block)
        end
    end
    return state
end

--Best Short Side Fit: the smaller leftover side decides, the larger breaks the tie, coordinates break that tie
function Pack.bssf_score(free, w, h)
    local leftover_w, leftover_h = free.w - w, free.h - h
    return math.min(leftover_w, leftover_h), math.max(leftover_w, leftover_h)
end

return Pack
