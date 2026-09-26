--Choose row run directions toward their flow partners. Called after pack and before Groups.materialize.
local RunDir = {}

local Grid = require "logic.bp.grid"

local NORTH, EAST, SOUTH, WEST = Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

function RunDir.reverse(block, role)
    local row = block and block.row
    if not row or row.first_x == nil or row.last_x == nil then return nil end
    local axis = row.first_x + row.last_x
    if axis + 1 ~= block.w then return nil end
    local result = copy(block)
    local function mirror_x(x) return axis - x end
    local function flip(d)
        if d == EAST then return WEST elseif d == WEST then return EAST end
        return d
    end
    local found = false
    for _, run in ipairs(result.belt_runs or {}) do
        if run.role == role then
            found = true
            local tiles = {}
            for index = #run.tiles, 1, -1 do
                local t = run.tiles[index]
                tiles[#tiles + 1] = {x = mirror_x(t.x), y = t.y}
            end
            run.tiles, run.dir = tiles, flip(run.dir)
            if run.head then run.head = {x = mirror_x(run.head.x), y = run.head.y} end
            for _, feed in ipairs(run.feeds or {}) do
                feed.side_tile = {x = mirror_x(feed.side_tile.x), y = feed.side_tile.y}
                feed.travel_dir = flip(feed.travel_dir)
            end
            if run.port then
                run.port = {x = mirror_x(run.port.x), y = run.port.y, travel_dir = flip(run.port.travel_dir)}
            end
            run.reversed = not run.reversed
        end
    end
    if not found then return nil end
    local prefix = "row:" .. role .. ":"
    for _, port in ipairs(result.ports or {}) do
        if port.row_port and tostring(port.port_id):sub(1, #prefix) == prefix then
            port.attach_dx = mirror_x(port.attach_dx)
            port.normal_dir, port.travel_dir = flip(port.normal_dir), flip(port.travel_dir)
        end
    end
    return result
end

local function manhattan(a, b) return math.abs(a.x - b.x) + math.abs(a.y - b.y) end
local function entry_id(entry)
    return entry and (entry.step_id or entry.id or entry.block_id)
end

function RunDir.choose(block, placement, all_blocks, all_placements, grid, flows, input_edge, output_edge)
    if not block.row then return block end
    local placed_by_id = {}
    for index, other in ipairs(all_blocks or {}) do
        local p = all_placements[index]
        if p then placed_by_id[other.id or other.block_id] = {block = other, placement = p} end
    end
    local result = block
    local function port_point(candidate, port)
        local q = Grid.place_port(candidate, placement, port)
        return {x = q.x, y = q.y}
    end
    local function partners(role, flow_id)
        local f
        for _, candidate in ipairs(flows or {}) do
            if (candidate.flow_id or candidate.id) == flow_id then f = candidate; break end
        end
        local entries = f and (role == "out" and f.consumers or f.producers) or {}
        local points = {}
        for _, entry in ipairs(entries or {}) do
            local id = entry_id(entry)
            if id == "$external" then
                local edge = role == "out" and output_edge or input_edge
                local axis_x = edge == "left" and 0 or edge == "right" and grid.w - 1
                local axis_y = edge == "top" and 0 or edge == "bottom" and grid.h - 1
                if axis_x then
                    points[#points + 1] = {x = axis_x, y = math.max(0, math.min(grid.h - 1, placement.y))}
                else
                    points[#points + 1] = {x = math.max(0, math.min(grid.w - 1, placement.x)), y = axis_y or 0}
                end
            else
                local found = placed_by_id[id]
                if found then
                    points[#points + 1] = {x = found.placement.x + found.block.w / 2,
                        y = found.placement.y + found.block.h / 2}
                end
            end
        end
        return points
    end
    for _, role in ipairs({"in", "out"}) do
        local original_port, original_run
        for _, p in ipairs(result.ports or {}) do
            if p.row_port and p.role == role and (role ~= "out" or tostring(p.port_id):find("row:out:", 1, true)) then
                original_port = p; break
            end
        end
        for _, run in ipairs(result.belt_runs or {}) do if run.role == role then original_run = run; break end end
        if original_port and original_run then
            local targets = {}
            for _, fid in ipairs(original_run.flows or {}) do
                for _, point in ipairs(partners(role, fid)) do targets[#targets + 1] = point end
            end
            if role == "in" and original_port.rear ~= true then
                local feeds = original_run.feeds or {}
                if #feeds > 0 then
                    local x, y = 0, 0
                    for _, feed in ipairs(feeds) do x, y = x + feed.side_tile.x, y + feed.side_tile.y end
                    original_port = {attach_dx = x / #feeds, attach_dy = y / #feeds, normal_dir = Grid.WEST}
                end
            end
            if #targets > 0 then
                local reversed = RunDir.reverse(result, role)
                if reversed then
                    local rp
                    for _, p in ipairs(reversed.ports or {}) do
                        if p.row_port and p.role == role and (role ~= "out" or tostring(p.port_id):find("row:out:", 1, true)) then rp = p; break end
                    end
                    if rp then
                        local a, b = port_point(result, original_port), port_point(reversed, rp)
                        local da, db = math.huge, math.huge
                        for _, target in ipairs(targets) do
                            da, db = math.min(da, manhattan(a, target)), math.min(db, manhattan(b, target))
                        end
                        local valid = true
                        for _, p in ipairs(reversed.ports or {}) do
                            if p.row_port and p.role == role then
                                local q = Grid.place_port(reversed, placement, p)
                                local vx, vy = Grid.dir_vector(q.dir)
                                for _, tile in ipairs({{x = q.x, y = q.y}, {x = q.x + vx, y = q.y + vy}}) do
                                    if tile.x < 1 or tile.y < 1 or tile.x >= grid.w - 1 or tile.y >= grid.h - 1 then valid = false end
                                    for _, other in ipairs(all_blocks or {}) do
                                        local op = placed_by_id[other.id or other.block_id]
                                        if op and other ~= block and tile.x >= op.placement.x and tile.y >= op.placement.y
                                            and tile.x < op.placement.x + other.w and tile.y < op.placement.y + other.h then valid = false end
                                    end
                                end
                            end
                        end
                        if valid and db < da then result = reversed end
                    end
                end
            end
        end
    end
    return result
end

return RunDir
