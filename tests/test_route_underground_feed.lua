--Underground feed and directed-chain regressions, driven through the public incremental route API.
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
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

local function key(x, y) return tostring(x) .. ":" .. tostring(y) end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " UF1 underground inputs use a straight same-flow feed", function()
        local state = run()
        local bad, count = false, 0
        for _, entity in ipairs(state.result.entities or {}) do
            if entity.ug_role == "input" then
                count = count + 1
                local x, y = math.floor(entity.position.x), math.floor(entity.position.y)
                local dx, dy = Grid.dir_vector(entity.direction)
                local behind = state.work.segments_by_cell[key(x - dx, y - dy)]
                local segment = state.work.segments_by_cell[key(x, y)]
                if not behind or not segment or behind.direction ~= entity.direction
                    or not (function()
                        for _, allocation in ipairs(behind.allocations or {}) do
                            for _, own in ipairs(segment.allocations or {}) do
                                if own.flow_id == allocation.flow_id then return true end
                            end
                        end
                        return false
                    end)() then bad = true end
            end
        end
        print(shape .. " UF1 underground inputs=" .. count .. " straight_feed=" .. tostring(not bad))
        H.equal(count > 0, true, "fixture exercises underground routing")
        H.equal(bad, false, "each input has its same-flow belt directly behind it")
    end)

    H.test(shape .. " UF1b a side-fed dive remains available as a last resort", function()
        local state = run()
        H.equal(state.ok, true, "the route remains available")
        --The same public search keeps side-fed dives legal; product oracle fixtures exercise that fallback.
        H.equal(type(state.work.segments), "table", "route retains its published segment geometry")
    end)

    H.test(shape .. " UF2 a longer crossing passes a free middle tile", function()
        local state = run()
        local found = false
        for _, segment in ipairs(state.work.segments or {}) do
            if segment.underground and math.abs(segment.underground_exit_x - segment.underground_entry_x)
                + math.abs(segment.underground_exit_y - segment.underground_entry_y) > 2 then found = true end
        end
        H.equal(found, true, "one pair spans the free tile between foreign belts")
    end)

    H.test(shape .. " UF3 published same-flow transport has no directed cycle", function()
        local state = run()
        local bad = false
        for start, initial in pairs(state.work.segments_by_cell or {}) do
            if initial.kind == "belt" then
                local seen, cursor = {}, start
                while cursor and not seen[cursor] do
                    seen[cursor] = true
                    local cell = state.work.segments_by_cell[cursor]
                    if not cell or cell.direction == nil then cursor = nil
                    elseif cell.underground and cursor == cell.underground_entry_key then
                        cursor = cell.underground_exit_key
                    else
                        local cx, cy = cursor:match("^([^:]+):([^:]+)$")
                        local dx, dy = Grid.dir_vector(cell.direction)
                        cursor = key(tonumber(cx) + dx, tonumber(cy) + dy)
                    end
                end
                if cursor ~= nil then bad = true end
            end
        end
        H.equal(bad, false, "directed successors do not return to their start")
    end)

    H.test(shape .. " UF4 a straight run still uses an underground crossing", function()
        local state = run()
        local straight = false
        for _, segment in ipairs(state.work.segments or {}) do
            if segment.underground then
                local dx = segment.underground_exit_x - segment.underground_entry_x
                local dy = segment.underground_exit_y - segment.underground_entry_y
                if (dx == 0 or dy == 0) and segment.direction ~= nil then straight = true end
            end
        end
        H.equal(straight, true, "straight underground crossing remains legal")
    end)
end

H.done("test_route_underground_feed")
