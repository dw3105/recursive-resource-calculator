local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Search = require "logic.bp.search"

local function best(slots, port)
    local first = Search._port_first_belt(port)
    local consumers = first and {first} or {}
    local chosen, cost
    for _, slot in ipairs(slots) do
        local next_cost = Search._slot_cost(slot, consumers)
        if cost == nil or next_cost < cost then chosen, cost = slot, next_cost end
    end
    return chosen
end

H.test("out port prices the exit from its first eastbound belt tile", function()
    local slots = {}
    for x = 0, 20 do slots[#slots + 1] = {x = x, y = 0} end
    local slot = best(slots, {role = "out", x = 19, y = 9, travel_dir = Grid.EAST})
    H.equal(slot.x, 20, "the top output aligns with first belt tile (20,9)")
end)

H.test("in port prices the entry from the tile behind its west edge", function()
    local slots = {}
    for y = 0, 10 do slots[#slots + 1] = {x = 0, y = y} end
    local slot = best(slots, {role = "in", x = 5, y = 5, travel_dir = Grid.EAST})
    H.equal(slot.y, 5, "the left input aligns with its first belt tile at y=5")
    H.equal(slot.x, 0, "the input remains on the left edge")
end)

H.done("test_search_exit_slot")
