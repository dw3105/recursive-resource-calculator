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
--inner work so one module call stays short even when the search budget is large. Eighteen charged ops per
--linked origin keeps expensive candidate batches below 0.06 s while retaining roughly 8 us per op.
local PORT_ORIGIN_OPS = 18
Pack.DRAWN_GAP = 4

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
        --A fluid port is the pipe tile in front of the machine's fluid box: no other tile connects to it.
        fluid_pinned = port.fluid_pinned == true or nil,
        pinned = port.inserter_id ~= nil or port.row_port == true or port.fluid_pinned == true,
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

local function zones_avoid_blockers(state, zones)
    for _, zone in ipairs(zones) do
        for _, blocker in ipairs(state.zone_blockers) do
            --The whole ring, not only the machine footprint (docs/contracts/pipeline_r29.md C2).
            if Grid.intersects(Buffer.zone(zone.rect, zone.ring), blocker) then return false end
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
    state.failed = true
    state.progress.phase = "packing"
    set_result(state)
end

local function drawn_turn(state, block)
    if state.trial and tostring(state.trial.block_id) == tostring(block.block_id) then return state.trial.dir end
    return state.drawing and state.drawing.turn_of and state.drawing.turn_of[block.block_id]
end

local function finish(state)
    state.done = true
    state.ok = true
    state.progress.phase = "packing"
    set_result(state)
end

local function better(candidate, best)
    if best == nil then return true end
    if candidate.link_cost ~= nil and best.link_cost ~= nil and candidate.link_cost ~= best.link_cost then
        return candidate.link_cost < best.link_cost
    end
    if candidate.short_side ~= best.short_side then return candidate.short_side < best.short_side end
    if candidate.long_side ~= best.long_side then return candidate.long_side < best.long_side end
    if candidate.link_cost ~= nil then
        if candidate.y ~= best.y then return candidate.y < best.y end
        if candidate.x ~= best.x then return candidate.x < best.x end
    else
        if candidate.x ~= best.x then return candidate.x < best.x end
        if candidate.y ~= best.y then return candidate.y < best.y end
    end
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
        local interior_row_feed = (port.row_port or port.fluid_pinned) and not bounded_slot(slot, block.w, block.h)
        --Authored hand drop points can also sit inside the opaque envelope: the envelope includes the
        --members around the machine, while the drop tile is still a real empty tile. Preserve its authored
        --direction and let the free-cell/approach checks below prove that it can be used.
        local interior_pinned = port.pinned and port.normal_dir ~= nil
            and not bounded_slot(slot, block.w, block.h)
        if not bounded_slot(slot, block.w, block.h) and not interior_row_feed and not interior_pinned then return end
        local key = slot_key(slot.attach_dx, slot.attach_dy)
        if seen[key] then return end
        seen[key] = true
        local normal = (interior_row_feed or interior_pinned) and slot.normal_dir
            or normal_for_slot(slot, block.w, block.h)
        local travel = (interior_row_feed or interior_pinned) and port.travel_dir
            or (port.role == "in" and normal or Grid.dir_opposite(normal))
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

local function port_tile(block, placement, endpoint)
    if endpoint.port_id ~= nil then
        for i, port in ipairs(block.ports or {}) do
            if tostring(port.port_id) == tostring(endpoint.port_id) then
                local slot = placement.port_slots and placement.port_slots[i]
                if slot then return world_slot(block, placement.x, placement.y, placement.dir, slot) end
                break
            end
        end
    end
    return placement.x + math.floor(placement.w / 2), placement.y + math.floor(placement.h / 2)
end

local function linked_cost(state, block, candidate)
    local cost = 0
    for _, link in ipairs(state.links_by_block[tostring(block.block_id)] or {}) do
        local mine = link.a.block_id ~= nil and tostring(link.a.block_id) == tostring(block.block_id) and link.a or link.b
        local other = mine == link.a and link.b or link.a
        local x, y = port_tile(block, candidate, mine)
        if other.edge then
            if other.edge == "left" then cost = cost + (x - state.area.x)
            elseif other.edge == "right" then cost = cost + (state.area.x + state.area.w - 1 - x)
            elseif other.edge == "top" then cost = cost + (y - state.area.y)
            elseif other.edge == "bottom" then cost = cost + (state.area.y + state.area.h - 1 - y) end
        else
            local partner = state.placement_by_id[tostring(other.block_id)]
            if partner then
                local pb = state.block_by_id[tostring(other.block_id)]
                local px, py
                if pb then px, py = port_tile(pb, partner, other)
                else px, py = partner.x + math.floor(partner.w / 2), partner.y + math.floor(partner.h / 2) end
                cost = cost + math.abs(x - px) + math.abs(y - py)
            end
        end
    end
    local box = state.placed_bbox
    --Growth is measured as half-perimeter (w + h), in tiles like the link distances. Area growth (tiles squared)
    --outweighed every distance and strung the player's sheet into one 280-entity strip (2026-09-24).
    local old_span = box and box.w + box.h or 0
    local minx, miny = box and math.min(box.x, candidate.x) or candidate.x,
        box and math.min(box.y, candidate.y) or candidate.y
    local maxx, maxy = box and math.max(box.x + box.w, candidate.x + candidate.w) or candidate.x + candidate.w,
        box and math.max(box.y + box.h, candidate.y + candidate.h) or candidate.y + candidate.h
    return cost + math.max(0, (maxx-minx)+(maxy-miny) - old_span)
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
                and (port.row_port or port.fluid_pinned or bounded_slot(port, block.w, block.h)) then
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

local link_bound
local function scan_origin(state, block, region, direction, x, y)
            local w, h = Grid.rotate_size(block.w, block.h, direction)
            local key = tostring(block.block_id) .. ":" .. direction .. ":" .. x .. ":" .. y
            local score_short, score_long = Pack.bssf_score(region, w, h)
            local old = state.origin_seen[key]
            if old then
                if old.candidate then
                    local c = old.candidate
                    if score_short < c.short_side or (score_short == c.short_side and score_long < c.long_side) then
                        c.short_side, c.long_side = score_short, score_long
                        if better(c, state.cursor.best) then state.cursor.best = c end
                    end
                end
                return old.offset_scan == true
            end
            state.origin_seen[key] = {}
            state.counters.origins = state.counters.origins + 1
            if not placement_avoids_port_cells(state, x, y, w, h) then return false end
            if state.has_links and not state.disable_link_cut and state.cursor.best
                and link_bound(state, block, x, y, w, h) > state.cursor.best.link_cost then
                state.origin_seen[key].cut = true
                return false
            end
            state.counters.evaluated_origins = state.counters.evaluated_origins + 1
            local buffer_zones = rotate_buffer_zones(block, x, y, direction)
            if not buffer_zones_fit(state, buffer_zones) or not zones_avoid_blockers(state, buffer_zones) then
                state.origin_seen[key].offset_scan = true
                return true
            end
            local short_side, long_side = score_short, score_long
            local candidate = {x=x,y=y,dir=direction,w=w,h=h,short_side=short_side,long_side=long_side}
            local slots
            if #block.ports > 0 then
                local reason
                slots, reason = choose_port_slots(state, block, x, y, direction)
                if not slots then
                    if reason == "pinned-free" then state.origin_seen[key].offset_scan = true; return true end
                    return false
                end
                candidate.port_slots = slots
            end
            if state.has_links then candidate.link_cost = linked_cost(state, block, candidate) end
            state.origin_seen[key].candidate = candidate
            if better(candidate, state.cursor.best) then state.cursor.best = candidate end
            return false
end

-- Lower bound on every linked endpoint's distance to any port tile on the candidate rectangle.
link_bound = function(state, block, x, y, w, h)
    local total = 0
    for _, link in ipairs(state.links_by_block[tostring(block.block_id)] or {}) do
        local mine = link.a.block_id ~= nil and tostring(link.a.block_id) == tostring(block.block_id) and link.a or link.b
        local other = mine == link.a and link.b or link.a
        local px, py
        if other.edge then
            if other.edge == "left" then total = total + math.max(0, x - 1 - state.area.x)
            elseif other.edge == "right" then total = total + math.max(0, state.area.x + state.area.w - 1 - (x + w))
            elseif other.edge == "top" then total = total + math.max(0, y - 1 - state.area.y)
            elseif other.edge == "bottom" then total = total + math.max(0, state.area.y + state.area.h - 1 - (y + h)) end
        else
            local partner = other.block_id and state.placement_by_id[tostring(other.block_id)]
            if partner then
                local pb = state.block_by_id[tostring(other.block_id)]
                if pb then px, py = port_tile(pb, partner, other)
                else px, py = partner.x + math.floor(partner.w / 2), partner.y + math.floor(partner.h / 2) end
            end
        end
        if px then total = total + math.max(0, x - 1 - px, px - (x + w))
            + math.max(0, y - 1 - py, py - (y + h)) end
    end
    local box = state.placed_bbox
    local old = box and box.w + box.h or 0
    local minx, miny = box and math.min(box.x, x) or x, box and math.min(box.y, y) or y
    local maxx, maxy = box and math.max(box.x + box.w, x + w) or x + w,
        box and math.max(box.y + box.h, y + h) or y + h
    return total + math.max(0, maxx - minx + maxy - miny - old)
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
                c.needs_offset = pinned_failed or state.has_links
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


--Layered pack: a block's layer is the longest link chain from raw input to it. Layers are columns going right
--from the input edge; inside its column a block aims at the mean row of its placed partners' ports. It takes the
--nearest legal origin to that target, then looks EXTRA more rings out and keeps the lowest link cost. Buffer
--rings already keep blocks apart, so no free-rectangle search is needed. On by default (player placed red 148 and
--green 305 in game, 2026-09-25); RRC_PACK=maxrects turns it off.
Pack.mode = (os and os.getenv and os.getenv("RRC_PACK")) or "layered"
Pack.layered = Pack.mode ~= "maxrects"
local EXTRA = tonumber(os and os.getenv and os.getenv("RRC_PACK_EXTRA") or "") or 8

local function layered_order(state)
    local ids, pos = {}, {}
    for i, b in ipairs(state.blocks) do ids[i] = tostring(b.block_id); pos[ids[i]] = i end
    local preds = {}
    for _, link in ipairs(state.links) do
        if link.a.block_id ~= nil and link.b.block_id ~= nil then
            local from, to = tostring(link.a.block_id), tostring(link.b.block_id)
            preds[to] = preds[to] or {}; preds[to][from] = true
        end
    end
    local layer = {}
    for _, id in ipairs(ids) do layer[id] = 0 end
    for _ = 1, #ids do
        for _, id in ipairs(ids) do
            for from in pairs(preds[id] or {}) do
                if layer[from] and layer[from] + 1 > layer[id] then layer[id] = layer[from] + 1 end
            end
        end
    end
    local maxl = 0
    for _, id in ipairs(ids) do if layer[id] > maxl then maxl = layer[id] end end
    local order = {}
    for i, b in ipairs(state.blocks) do order[i] = b end
    table.sort(order, function(a, b)
        local la, lb = layer[tostring(a.block_id)], layer[tostring(b.block_id)]
        if la ~= lb then return la < lb end
        return pos[tostring(a.block_id)] < pos[tostring(b.block_id)]
    end)
    state.blocks, state.layer_of, state.max_layer = order, layer, maxl
end

local function layered_target(state, block)
    if state.mode == "sugiyama" then
        local id, drawing = tostring(block.block_id), state.drawing or {}
        local L, rank = drawing.layer_of and drawing.layer_of[block.block_id], drawing.rank_of and drawing.rank_of[block.block_id]
        L, rank = L or 1, rank or 1
        local edge = state.input_edge or "left"
        local horizontal = edge == "left" or edge == "right"
        local positive = edge == "left" or edge == "top"
        local total, across = 0, 0
        local maxdepth = {}
        for _, b in ipairs(state.blocks) do
            local bl = drawing.layer_of and drawing.layer_of[b.block_id]
            if bl then
                local d = drawn_turn(state, b) or 0
                local w, h = Grid.rotate_size(b.w, b.h, d)
                maxdepth[bl] = math.max(maxdepth[bl] or 0, horizontal and w or h)
                if bl == L and (drawing.rank_of[b.block_id] or 0) < rank then
                    across = across + (horizontal and h or w) + Pack.DRAWN_GAP
                end
            end
        end
        local specials = {}
        for _, list in ipairs({drawing.sources or {}, drawing.outputs or {}, drawing.dummies or {}}) do
            for _, item in ipairs(list) do
                local sl, sr = item.layer or 1, item.rank or 0
                if sl == L and sr < rank then specials[sr] = true end
            end
        end
        for _ in pairs(specials) do across = across + 1 end
        for layer = 1, L - 1 do total = total + (maxdepth[layer] or 0) + Pack.DRAWN_GAP end
        local start = positive and (horizontal and state.area.x or state.area.y) or
            (horizontal and state.area.x + state.area.w or state.area.y + state.area.h)
        local prefw, prefh = Grid.rotate_size(block.w, block.h, drawn_turn(state, block) or 0)
        local dim = horizontal and prefw or prefh
        local ax = state.area.x + across
        local ay = horizontal and (state.area.y + across) or (start + (positive and total or -total - dim))
        if horizontal then ax = positive and (start + total) or (start - total - dim) end
        if edge == "right" then ax = start - total - dim end
        if edge == "bottom" then ay = start - total - dim end
        ax = math.max(state.area.x, math.min(ax, state.area.x + state.area.w - prefw))
        ay = math.max(state.area.y, math.min(ay, state.area.y + state.area.h - prefh))
        return ax, ay
    end
    local L = state.layer_of[tostring(block.block_id)]
    local area = state.area
    local far, peer_right, n = nil, nil, 0
    local sum, future_sum, future_n = 0, 0, 0
    for _, pl in ipairs(state.placements) do
        local pl_layer = state.layer_of[tostring(pl.block_id)]
        if pl_layer < L then far = math.max(far or 0, pl.x + pl.w) end
        if pl_layer == L then peer_right = math.max(peer_right or 0, pl.x + pl.w) end
    end
    for _, link in ipairs(state.links_by_block[tostring(block.block_id)] or {}) do
        local mine = link.a.block_id ~= nil and tostring(link.a.block_id) == tostring(block.block_id) and link.a or link.b
        local other = mine == link.a and link.b or link.a
        local partner = other.block_id and state.placement_by_id[tostring(other.block_id)]
        if partner then
            local pb = state.block_by_id[tostring(other.block_id)]
            local px, py = port_tile(pb, partner, other)
            sum = sum + py; n = n + 1
        elseif other.block_id ~= nil then
            local pb = state.block_by_id[tostring(other.block_id)]
            if pb then
                local py = math.floor(pb.h / 2)
                for _, port in ipairs(pb.ports or {}) do
                    if tostring(port.port_id) == tostring(other.port_id) then
                        py = port.attach_dy or py
                        future_sum = future_sum + py
                        future_n = future_n + 1
                        break
                    end
                end
            end
        end
    end
    local x = far and far + 1 or (future_n == 0 and peer_right and peer_right + 1 or area.x + 1)
    local y
    if n > 0 then y = math.floor(sum / n + 0.5) - math.floor(block.h / 2)
    elseif future_n > 0 then y = math.floor(future_sum / future_n + 0.5) - math.floor(block.h / 2)
    else y = area.y + math.floor((area.h - block.h) / 2) end
    return x, y
end

--Drawn dummy tiles depend on the drawing and the area only, never on the candidate origin: build them once per pack
--(round 51 integration: rebuilding them per origin made Pack.step take 128 ms on magenta, legalcopilot-dev
--2026-09-30). Returns {[layer] = {{x, y}, ...}}.
local function drawn_dummy_tiles(state)
    if state.dummy_tiles then return state.dummy_tiles end
    local drawing, tiles = state.drawing or {}, {}
    local horizontal = state.input_edge == "left" or state.input_edge == "right"
    local positive = state.input_edge == "left" or state.input_edge == "top"
    local layer_depth, by_layer = {}, {}
    for _, b in ipairs(state.blocks) do
        local bl = drawing.layer_of and drawing.layer_of[b.block_id]
        if bl then
            local bw, bh = Grid.rotate_size(b.w, b.h, drawn_turn(state, b) or 0)
            layer_depth[bl] = math.max(layer_depth[bl] or 0, horizontal and bw or bh)
            local list = by_layer[bl] or {}
            by_layer[bl] = list
            list[#list + 1] = {rank = drawing.rank_of and drawing.rank_of[b.block_id] or math.huge, across = horizontal and bh or bw}
        end
    end
    local specials = {}
    for _, list in ipairs({drawing.sources or {}, drawing.outputs or {}, drawing.dummies or {}}) do
        for _, item in ipairs(list) do
            local l = item.layer or 1
            specials[l] = specials[l] or {}
            specials[l][#specials[l] + 1] = item.rank or 0
        end
    end
    for _, dummy in ipairs(drawing.dummies or {}) do
        local L, rank = dummy.layer or 1, dummy.rank or 1
        local rank_offset = 0
        for _, b in ipairs(by_layer[L] or {}) do
            if b.rank < rank then rank_offset = rank_offset + b.across + Pack.DRAWN_GAP end
        end
        for _, r in ipairs(specials[L] or {}) do if r < rank then rank_offset = rank_offset + 1 end end
        local layer_offset = 0
        for layer = 1, L - 1 do layer_offset = layer_offset + (layer_depth[layer] or 0) + Pack.DRAWN_GAP end
        local base = (horizontal and state.area.y or state.area.x) + rank_offset
        local flow = horizontal and state.area.x or state.area.y
        flow = positive and (flow + layer_offset) or (flow - layer_offset - 1)
        tiles[L] = tiles[L] or {}
        tiles[L][#tiles[L] + 1] = {x = horizontal and flow or base, y = horizontal and base or flow}
    end
    state.dummy_tiles = tiles
    return tiles
end

--One origin test. Returns the candidate (or nil) and the ops it cost: a cheap reject costs 1, an origin that
--reaches port slot choice costs PORT_ORIGIN_OPS like a MaxRects origin, a legal one twice that.
local function layered_legal(state, block, x, y, direction, tx, ty)
    local w, h = Grid.rotate_size(block.w, block.h, direction)
    local area = state.area
    if x < area.x or y < area.y or x + w > area.x + area.w or y + h > area.y + area.h then return nil, 1 end
    for cy = y, y + h - 1 do for cx = x, x + w - 1 do
        if not state.free_cell_index[cell_key(cx, cy)] then return nil, 1 end
    end end
    if not placement_avoids_port_cells(state, x, y, w, h) then return nil, 1 end
    local zones = rotate_buffer_zones(block, x, y, direction)
    if not buffer_zones_fit(state, zones) or not zones_avoid_blockers(state, zones) then return nil, 1 end
    local candidate = {x = x, y = y, dir = direction, w = w, h = h,
        short_side = math.abs(x - tx) + math.abs(y - ty), long_side = 0}
    if #block.ports > 0 then
        local slots = choose_port_slots(state, block, x, y, direction)
        if not slots then return nil, PORT_ORIGIN_OPS end
        candidate.port_slots = slots
    end
    candidate.link_cost = linked_cost(state, block, candidate)
    if state.mode == "sugiyama" then
        local id = block.block_id
        local L, rank = state.drawing.layer_of[id] or 1, state.drawing.rank_of[id] or 1
        local horizontal = state.input_edge == "left" or state.input_edge == "right"
        local P = horizontal and h or w
        local broken, covered = 0, 0
        local coord = horizontal and (y + h / 2) or (x + w / 2)
        for _, placed in ipairs(state.placements) do
            if (state.drawing.layer_of[placed.block_id] or 1) == L then
                local pr = state.drawing.rank_of[placed.block_id] or 1
                local pc = horizontal and (placed.y + placed.h / 2) or (placed.x + placed.w / 2)
                if (rank > pr and coord < pc) or (rank < pr and coord > pc) then broken = broken + 1 end
            end
        end
        for _, tile in ipairs(drawn_dummy_tiles(state)[L] or {}) do
            if x <= tile.x and tile.x < x + w and y <= tile.y and tile.y < y + h then covered = covered + 1 end
        end
        local preferred = drawn_turn(state, block)
        candidate.link_cost = candidate.link_cost + P * (broken + covered + (preferred ~= nil and direction ~= preferred and 1 or 0))
    end
    --A legal origin also pays for its link cost: twice a port origin keeps a tick near MaxRects' worst.
    return candidate, 2 * PORT_ORIGIN_OPS
end

--Walks Manhattan rings around the target, one origin at a time, so a tick stops when its ops run out and the
--next tick resumes at the same origin. Returns true once the walk is over; cursor.best then holds the pick.
local function layered_scan(state, block, budget)
    local ring = state.cursor.ring
    if ring == nil then
        local tx, ty = layered_target(state, block)
        ring = {tx = tx, ty = ty, r = 0, dx = 0, side = 1, di = 1, rmax = state.area.w + state.area.h}
        state.cursor.ring, state.cursor.best = ring, nil
        state.counters.origins = state.counters.origins + 1
    end
    local dirs = block.allowed_dirs
    while budget.ops > 0 do
        if ring.r > ring.rmax or (ring.found_r and ring.r > ring.found_r + EXTRA) then return true end
        local rest = ring.r - math.abs(ring.dx)
        local dy = (rest == 0 or ring.side == 1) and -rest or rest
        state.counters.evaluated_origins = state.counters.evaluated_origins + 1
        local c, cost = layered_legal(state, block, ring.tx + ring.dx, ring.ty + dy, dirs[ring.di], ring.tx, ring.ty)
        budget.ops = budget.ops - math.min(budget.ops, cost)
        if c then
            ring.found_r = ring.found_r or ring.r
            if better(c, state.cursor.best) then state.cursor.best = c end
        end
        --advance: direction, then the second dy of this dx, then dx, then the ring
        ring.di = ring.di + 1
        if ring.di > #dirs then
            ring.di = 1
            if ring.side == 1 and rest ~= 0 then ring.side = 2
            else
                ring.side = 1
                ring.dx = ring.dx + 1
                if ring.dx > ring.r then ring.r = ring.r + 1; ring.dx = -ring.r end
            end
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
    if state.has_links then return true end
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

local function start_place(state, block)
    local candidate = state.cursor.best
    if candidate == nil then
        local trial = state.trial and tostring(state.trial.block_id) == tostring(block.block_id)
        fail(state, trial and "BP_P_TRIAL_PIN" or "BP_P_NO_FIT", block.block_id)
        return
    end

    local placement = {
        block_id = block.block_id,
        x = candidate.x, y = candidate.y, dir = candidate.dir,
        w = candidate.w, h = candidate.h,
        port_slots = candidate.port_slots,
    }
    state.placements[#state.placements + 1] = placement
    state.placement_by_id[tostring(block.block_id)] = placement
    local box = state.placed_bbox
    if box then
        local x, y = math.min(box.x, placement.x), math.min(box.y, placement.y)
        local right, bottom = math.max(box.x + box.w, placement.x + placement.w), math.max(box.y + box.h, placement.y + placement.h)
        state.placed_bbox = {x = x, y = y, w = right - x, h = bottom - y}
    else
        state.placed_bbox = {x = placement.x, y = placement.y, w = placement.w, h = placement.h}
    end
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
    state.pending_place = {block = block, reserved = reserved, region_index = 1, regions = {}, stage = "subtract"}
end

local function begin_prune(rects)
    local order = {}
    for i, rect in ipairs(rects) do order[i] = {index = i, rect = rect, area = rect.w * rect.h} end
    table.sort(order, function(a, b)
        if a.area ~= b.area then return a.area > b.area end
        return a.index < b.index
    end)
    return {rects = rects, order = order, maximal = {}, keep = {}, position = 1, compare_index = 1}
end

local function continue_prune(p, budget)
    while p.position <= #p.order and budget.ops > 0 do
        local item = p.order[p.position]
        local larger = p.maximal[p.compare_index]
        if larger then
            local r = item.rect
            if larger.x <= r.x and larger.y <= r.y and larger.x + larger.w >= r.x + r.w
                and larger.y + larger.h >= r.y + r.h then
                p.contained = true
                p.compare_index = #p.maximal + 1
            else p.compare_index = p.compare_index + 1 end
        else
            if not p.contained then p.keep[item.index] = true; p.maximal[#p.maximal + 1] = item.rect end
            p.position, p.compare_index, p.contained = p.position + 1, 1, false
        end
        budget.ops = budget.ops - 1
    end
    if p.position <= #p.order then return nil end
    local out = {}
    for i, rect in ipairs(p.rects) do if p.keep[i] then out[#out + 1] = rect end end
    return out
end

local function finish_place(state, pending)
    local block, candidate = pending.block, state.cursor.best
    local placement = state.placements[#state.placements]
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
    state.regions = pending.pruned
    pending.stage = "index"
    pending.free = {}
    pending.region_index, pending.x, pending.y = 1, nil, nil
    pending.port_index = 1
end

local function complete_place(state)
    local block = state.pending_place.block
    if #state.regions > state.stats.peak_free_regions then
        state.stats.peak_free_regions = #state.regions
    end

    state.cursor.block_index = state.cursor.block_index + 1
    state.cursor.region_index = 1
    reset_region_cursor(state.cursor)
    state.cursor.best = nil
    state.origin_seen = {}
    state.progress.done_units = state.progress.done_units + 1
    state.pending_place = nil

    local limit = state.limits.max_free_regions
    if limit ~= nil and #state.regions > limit then
        fail(state, "BP_P_REGION_LIMIT")
    end
end

local function place_step(state, budget)
    local p = state.pending_place
    while budget.ops > 0 and p do
        if p.stage == "subtract" then
            if p.region_index > #state.regions then p.stage = "prune"; p.prune = begin_prune(p.regions)
            else
                local pieces = Grid.subtract(state.regions[p.region_index], p.reserved)
                for _, piece in ipairs(pieces) do p.regions[#p.regions + 1] = piece end
                p.region_index = p.region_index + 1
                budget.ops = budget.ops - 1
            end
        elseif p.stage == "prune" then
            local result = continue_prune(p.prune, budget)
            if result then p.pruned = result; finish_place(state, p) end
        elseif p.stage == "index" then
            if p.region_index > #state.regions then
                state.free_cell_index = p.free
                p.stage, p.port_index, p.ports = "ports", 1, {}
            else
                local r = state.regions[p.region_index]
                if p.y == nil then p.x, p.y = r.x, r.y end
                p.free[cell_key(p.x, p.y)] = true
                p.x = p.x + 1
                if p.x >= r.x + r.w then p.x = r.x; p.y = p.y + 1 end
                if p.y >= r.y + r.h then p.region_index = p.region_index + 1; p.x, p.y = nil, nil end
                budget.ops = budget.ops - 1
            end
        elseif p.stage == "ports" then
            local cell = state.port_cells[p.port_index]
            if cell then
                p.ports[cell_key(cell.x, cell.y)] = true
                p.port_index = p.port_index + 1
                budget.ops = budget.ops - 1
            else
                state.port_cell_index, state.port_cell_count = p.ports, #state.port_cells
                complete_place(state)
                return
            end
        end
        if state.done then break end
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
    local links, links_by_block, block_by_id = {}, {}, {}
    for _, b in ipairs(blocks) do block_by_id[tostring(b.block_id)] = b end
    for _, source in ipairs(input.links or {}) do
        local link = {a = source.a or {}, b = source.b or {}}
        links[#links + 1] = link
        for _, endpoint in ipairs({link.a, link.b}) do
            if endpoint.block_id ~= nil then
                local key = tostring(endpoint.block_id)
                links_by_block[key] = links_by_block[key] or {}
                links_by_block[key][#links_by_block[key] + 1] = link
            end
        end
    end
    local state = {
        area = area,
        obstacles = obstacles,
        zone_blockers = copy_rects(input.zone_blockers),
        blocks = blocks,
        links = links, links_by_block = links_by_block, block_by_id = block_by_id,
        placement_by_id = {}, has_links = #links > 0, layered = input.layered == true,
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
        counters = {origins = 0, evaluated_origins = 0},
        origin_seen = {}, disable_link_cut = input.disable_link_cut == true,
        mode = input.mode, drawing = input.drawing, input_edge = input.input_edge,
        pins = {}, trial = input.mode == "sugiyama" and input.trial or nil,
    }
    if input.mode == "sugiyama" then
        for id, pin in pairs(input.pins or {}) do state.pins[tostring(id)] = pin end
    end
    rebuild_indexes(state)
    if state.mode == "sugiyama" then
        local pos = {}; for i,b in ipairs(blocks) do
            pos[tostring(b.block_id)] = i
            if state.trial and tostring(state.trial.block_id) == tostring(b.block_id) then
                b.allowed_dirs = {state.trial.dir}
            else
                b.allowed_dirs = input.forced_dir ~= nil and {input.forced_dir} or {0,4,8,12}
            end
        end
        table.sort(blocks, function(a,b)
            local ap = state.pins[tostring(a.block_id)] ~= nil
            local bp = state.pins[tostring(b.block_id)] ~= nil
            if ap ~= bp then return ap end
            local at = state.trial and tostring(state.trial.block_id) == tostring(a.block_id)
            local bt = state.trial and tostring(state.trial.block_id) == tostring(b.block_id)
            if at ~= bt then return not at end
            local la,lb=(state.drawing.layer_of or {})[a.block_id],(state.drawing.layer_of or {})[b.block_id]
            la,lb=la or math.huge,lb or math.huge
            if la~=lb then return la<lb end
            local ra,rb=(state.drawing.rank_of or {})[a.block_id],(state.drawing.rank_of or {})[b.block_id]
            if ra and rb and ra~=rb then return ra<rb end
            if (ra~=nil)~=(rb~=nil) then return ra~=nil end
            return pos[tostring(a.block_id)]<pos[tostring(b.block_id)]
        end)
        state.layered=true
    elseif state.layered and state.has_links then layered_order(state) end

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
        if state.pending_place then
            if budget.ops == nil or budget.ops <= 0 then break end
            place_step(state, budget)
            if budget.ops <= 0 then break end
        else
        local block = state.blocks[state.cursor.block_index]
        if block == nil then
            finish(state)
            break
        end

        local pin = state.pins[tostring(block.block_id)]
        if pin ~= nil then
            local candidate = layered_legal(state, block, pin.x, pin.y, pin.dir, pin.x, pin.y)
            if candidate == nil then
                fail(state, "BP_P_TRIAL_PIN", block.block_id)
            else
                state.cursor.best = candidate
                start_place(state, block)
            end
        elseif state.mode == "sugiyama" or (state.layered and state.has_links) then
            if budget.ops == nil or budget.ops <= 0 then break end
            if layered_scan(state, block, budget) then
                state.cursor.ring = nil
                start_place(state, block)
            end
        elseif state.cursor.region_index <= #state.regions then
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
            start_place(state, block)
        end
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
