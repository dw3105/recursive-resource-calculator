-- Characterize waste in the published route geometry.  Keep these checks on routed entities.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"
local FROZEN = "tests/fixtures/routing/player_chain_first_candidate.lua"

local function run()
    local state = Route.begin(dofile(FROZEN))
    local ticks = 0
    while not state.done and ticks < 200000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "frozen route completes")
    return state
end

local function xy(entity)
    local p = entity.position or entity
    return math.floor(p.x + 1e-9), math.floor(p.y + 1e-9)
end

-- A return means the route has left the start neighborhood, then comes back within one tile.
-- A staircase that only passes near the start once is not a return.
local function returns_near_start(points)
    if #points < 3 then return false end
    local sx, sy = points[1][1], points[1][2]
    local left = false
    for i = 2, #points do
        local x, y = points[i][1], points[i][2]
        if math.abs(x - sx) + math.abs(y - sy) > 1 then left = true end
        if left and math.abs(x - sx) + math.abs(y - sy) <= 1 then return true end
    end
    return false
end

local function cells_text(points)
    local out = {}
    for _, p in ipairs(points) do out[#out + 1] = string.format("(%s,%s)", p[1], p[2]) end
    return table.concat(out, " ")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RW0 published route lays a belt run", function()
        local state = run()
        local belts = {}
        for _, entity in ipairs(state.result and state.result.entities or {}) do
            if entity.ug_role == nil and tostring(entity.name or ""):find("belt", 1, true) then belts[#belts + 1] = entity end
        end
        print(shape .. " RW0 published belt tiles: " .. #belts)
        H.equal(#belts > 0, true, "route fixture is non-vacuous")
    end)

    H.test(shape .. " RW1 published route has no wasteful near-start return", function()
        local state = run()
        local by_segment = {}
        for _, entity in ipairs(state.result and state.result.entities or {}) do
            if entity.ug_role == nil and entity.segment_id ~= nil and tostring(entity.name or ""):find("belt", 1, true) then
                local id = tostring(entity.segment_id)
                by_segment[id] = by_segment[id] or {}
                local x, y = xy(entity)
                by_segment[id][#by_segment[id] + 1] = {x, y}
            end
        end
        local bad = false
        for id, points in pairs(by_segment) do
            table.sort(points, function(a, b) if a[1] == b[1] then return a[2] < b[2] end return a[1] < b[1] end)
            local returns = returns_near_start(points)
            print(string.format("%s RW1 segment %s tiles: %s returns=%s", shape, id, cells_text(points), tostring(returns)))
            if returns then bad = true end
        end
        H.equal(bad, false, "no belt chain returns within one tile of its own start")
    end)

    H.test(shape .. " RW2 the player's useful four-chain hairpin passes RW1", function()
        local player_shape = {{203,1076}, {203,1075}, {204,1075}, {205,1075}}
        print(shape .. " RW2 player hairpin tiles: " .. cells_text(player_shape))
        H.equal(returns_near_start(player_shape), false, "four-chain hairpin ending at (205.5,1075.5) passes")
    end)

    H.test(shape .. " RW3 published underground pairs cover occupied tiles only", function()
        local state = run()
        local occupied = {}
        for _, entity in ipairs(state.result and state.result.entities or {}) do
            local x, y = xy(entity)
            occupied[x .. ":" .. y] = true
        end
        local bad = false
        for _, segment in ipairs(state.work.segments or {}) do
            if segment.underground then
                local x1, y1 = segment.underground_entry_x, segment.underground_entry_y
                local x2, y2 = segment.underground_exit_x, segment.underground_exit_y
                local dx = x2 == x1 and 0 or (x2 > x1 and 1 or -1)
                local dy = y2 == y1 and 0 or (y2 > y1 and 1 or -1)
                local tiles = {}
                local x, y = x1 + dx, y1 + dy
                while x ~= x2 or y ~= y2 do
                    tiles[#tiles + 1] = {x,y}
                    if occupied[x .. ":" .. y] then bad = true end
                    x, y = x + dx, y + dy
                end
                print(string.format("%s RW3 underground covered tiles: %s", shape, cells_text(tiles)))
            end
        end
        H.equal(bad, false, "every underground skips at least one occupied tile")
    end)

    H.test(shape .. " RW4 published underground span is at least two", function()
        local state = run()
        local bad = false
        for _, segment in ipairs(state.work.segments or {}) do
            if segment.underground then
                local span = math.abs(segment.underground_exit_x - segment.underground_entry_x)
                    + math.abs(segment.underground_exit_y - segment.underground_entry_y)
                print(string.format("%s RW4 underground endpoints (%d,%d) to (%d,%d), span=%d",
                    shape, segment.underground_entry_x, segment.underground_entry_y,
                    segment.underground_exit_x, segment.underground_exit_y, span))
                if span < 2 then bad = true end
            end
        end
        H.equal(bad, false, "underground span is at least two tiles")
    end)

    H.test(shape .. " RW5 negative control detects an explicit wasteful return", function()
        local uturn = {{1,27}, {0,27}, {0,28}, {1,28}}
        print(shape .. " RW5 negative-control tiles: " .. cells_text(uturn))
        H.equal(returns_near_start(uturn), true, "two-turn U-turn is recognized as waste")
    end)
end

H.done("test_route_waste")
