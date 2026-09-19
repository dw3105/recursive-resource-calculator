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

local DIRECTIONS = {Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}

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
        attach_dx = finite(port.attach_dx), attach_dy = finite(port.attach_dy),
        normal_dir = finite(port.normal_dir), travel_dir = finite(port.travel_dir),
    }
end

local function copy_block(block)
    local ports = {}
    for index, port in ipairs(block.ports or block.block_ports or {}) do
        ports[index] = copy_port(port, index)
    end
    return {
        block_id = block.block_id ~= nil and block.block_id or block.id,
        w = block.w,
        h = block.h,
        allowed_dirs = copy_directions(block.allowed_dirs),
        ports = ports,
    }
end

local function copy_rects(rects)
    local result = {}
    for index, rect in ipairs(rects or {}) do result[index] = copy_rect(rect) end
    return result
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
    local result, seen = {}, {}
    local function add(slot)
        if not bounded_slot(slot, block.w, block.h) then return end
        local key = slot_key(slot.attach_dx, slot.attach_dy)
        if seen[key] then return end
        seen[key] = true
        local normal = normal_for_slot(slot, block.w, block.h)
        local travel = port.role == "in" and normal or Grid.dir_opposite(normal)
        result[#result + 1] = {
            attach_dx = slot.attach_dx, attach_dy = slot.attach_dy,
            normal_dir = normal, travel_dir = travel,
        }
    end
    if port.attach_dx ~= nil and port.attach_dy ~= nil then
        add({attach_dx = port.attach_dx, attach_dy = port.attach_dy, normal_dir = port.normal_dir})
    end
    for _, slot in ipairs(edge_slots(block.w, block.h)) do add(slot) end
    return result
end

local function cell_is_free(state, x, y)
    if x < state.area.x or y < state.area.y
        or x >= state.area.x + state.area.w or y >= state.area.y + state.area.h then
        return false
    end
    for _, cell in ipairs(state.port_cells or {}) do
        if cell.x == x and cell.y == y then return false end
    end
    for _, region in ipairs(state.regions) do
        if x >= region.x and y >= region.y and x < region.x + region.w and y < region.y + region.h then
            return true
        end
    end
    return false
end

local function placement_avoids_port_cells(state, x, y, w, h)
    for _, cell in ipairs(state.port_cells or {}) do
        if cell.x >= x and cell.y >= y and cell.x < x + w and cell.y < y + h then return false end
    end
    return true
end

local function world_slot(block, x, y, direction, slot)
    local dx, dy = Grid.rotate_rect(slot.attach_dx, slot.attach_dy, 1, 1, block.w, block.h, direction)
    return x + dx, y + dy
end

local function choose_port_slots(state, block, x, y, direction)
    local entries = {}
    local placed_w, placed_h = Grid.rotate_size(block.w, block.h, direction)
    for index, port in ipairs(block.ports or {}) do
        local options = {}
        for _, slot in ipairs(port_slots(block, port)) do
            -- attach_dx/attach_dy stay in the source frame.  Since the validator applies its edge predicate to
            -- the placed envelope too, only retain slots that are legal in both frames.  Groups reserves both
            -- source axes for its port row; this guard also keeps direct Pack callers safe for rectangles.
            local placed_normal = normal_for_slot(slot, placed_w, placed_h)
            if bounded_slot(slot, placed_w, placed_h) and placed_normal == slot.normal_dir then
                local world_x, world_y = world_slot(block, x, y, direction, slot)
                local travel = Grid.rotate_dir(slot.travel_dir, direction)
                local dx, dy = Grid.dir_vector(travel)
                local approach_x, approach_y = world_x, world_y
                if port.role == "in" then approach_x, approach_y = approach_x - dx, approach_y - dy
                else approach_x, approach_y = approach_x + dx, approach_y + dy end
                -- The endpoint itself must be free, and the first cell on the route side must also exist. This
                -- is what makes an edge port routable: an input needs a predecessor inside the grid, an output
                -- needs its first successor inside it.
                if cell_is_free(state, world_x, world_y) and cell_is_free(state, approach_x, approach_y) then
                    options[#options + 1] = {slot = slot, x = world_x, y = world_y}
                end
            end
        end
        if #options == 0 then return nil end
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

local function scan_region(state, block, region)
    for _, direction in ipairs(block.allowed_dirs) do
        local w, h = Grid.rotate_size(block.w, block.h, direction)
        local x, y = region.x, region.y
        if region.w >= w and region.h >= h and placement_avoids_port_cells(state, x, y, w, h) then
            local short_side, long_side = Pack.bssf_score(region, w, h)
            local candidate = {
                x = x, y = y, dir = direction, w = w, h = h,
                short_side = short_side, long_side = long_side,
            }
            if #block.ports == 0 then
                if better(candidate, state.cursor.best) then state.cursor.best = candidate end
            else
                candidate.port_slots = choose_port_slots(state, block, region.x, region.y, direction)
                if candidate.port_slots and better(candidate, state.cursor.best) then
                    state.cursor.best = candidate
                end
            end
        end
    end
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

    local next_regions = {}
    for _, region in ipairs(state.regions) do
        local pieces = Grid.subtract(region, placement)
        for _, piece in ipairs(pieces) do next_regions[#next_regions + 1] = piece end
    end
    for _, slot in ipairs(candidate.port_slots or {}) do
        local x, y = world_slot(block, candidate.x, candidate.y, candidate.dir, slot)
        state.port_cells[#state.port_cells + 1] = {x = x, y = y}
    end
    state.regions = Grid.prune(next_regions)
    if #state.regions > state.stats.peak_free_regions then
        state.stats.peak_free_regions = #state.regions
    end

    state.cursor.block_index = state.cursor.block_index + 1
    state.cursor.region_index = 1
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
        cursor = {block_index = 1, region_index = 1, best = nil},
        progress = {phase = "packing", done_units = 0, total_units = #blocks},
        stats = {peak_free_regions = #regions, scans = 0},
        port_cells = {},
    }

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
            state.cursor.region_index = state.cursor.region_index + 1
            state.stats.scans = state.stats.scans + 1
            budget.ops = budget.ops - 1
            scan_region(state, block, region)
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
