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

local function copy_block(block)
    return {
        block_id = block.block_id ~= nil and block.block_id or block.id,
        w = block.w,
        h = block.h,
        allowed_dirs = copy_directions(block.allowed_dirs),
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

local function scan_region(state, block, region)
    for _, direction in ipairs(block.allowed_dirs) do
        local w, h = Grid.rotate_size(block.w, block.h, direction)
        if region.w >= w and region.h >= h then
            local short_side, long_side = Pack.bssf_score(region, w, h)
            local candidate = {
                x = region.x, y = region.y, dir = direction, w = w, h = h,
                short_side = short_side, long_side = long_side,
            }
            if better(candidate, state.cursor.best) then state.cursor.best = candidate end
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
    }
    state.placements[#state.placements + 1] = placement

    local next_regions = {}
    for _, region in ipairs(state.regions) do
        local pieces = Grid.subtract(region, placement)
        for _, piece in ipairs(pieces) do next_regions[#next_regions + 1] = piece end
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
