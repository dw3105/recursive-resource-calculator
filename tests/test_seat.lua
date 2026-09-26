-- Every scenario here fails on round-39-base: Seat.run is a stub and approach_open is false.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Hands = require "logic.bp.hands"
local Seat = require "logic.bp.seat"

local function machine_fixture(duplicates)
    local materialized = {entities = {}, ports = {}}
    local grid = {w = 16, h = 20}
    for index, y in ipairs({2, 10}) do
        local mid = "m" .. index
        materialized.entities[#materialized.entities + 1] =
            {id = mid, kind = "machine", x = 2, y = y, w = 5, h = 5}
        local specs = {{flow = "calcite", port = "c" .. index}, {flow = "ore" .. index, port = "o" .. index}}
        if duplicates and index == 1 then specs[#specs + 1] = {flow = "ore1", port = "o1b"} end
        for j, spec in ipairs(specs) do
            local hand_id = spec.port .. "h"
            local hy = y + (j == 1 and 1 or 3)
            local hand = {id = "m:" .. hand_id, kind = "inserter", name = "inserter",
                x = 7, y = hy, w = 1, h = 1, machine_id = mid, dir = Grid.WEST,
                position = {x = 7.5, y = hy + 0.5}, pickup_position = {x = 8.5, y = hy + 0.5},
                drop_position = {x = 7.5, y = hy + 0.5}}
            materialized.entities[#materialized.entities + 1] = hand
            materialized.ports[#materialized.ports + 1] = {port_id = spec.port, inserter_id = hand_id,
                role = "in", kind = "item", flow_id = spec.flow, x = 8, y = hy,
                attach_dx = 6, attach_dy = hy - y, normal_dir = Grid.EAST, travel_dir = Grid.EAST}
        end
    end
    Hands.offer_slides(materialized, grid)
    local flows = {{flow_id = "calcite", producers = {{step_id = "$external"}}}}
    for i = 1, 2 do flows[#flows + 1] = {flow_id = "ore" .. i, producers = {{step_id = "$external"}}} end
    return materialized, grid, flows
end

H.test("SE1 shared flow faces the other machine, then own flows face outer rows", function()
    local m, grid, flows = machine_fixture(false)
    H.equal(type(m.ports[1].hop_options), "table", "real hop choices supplied")
    H.equal(Seat.run(m, grid, flows, "left"), 4, "all four hands moved")
    local by_port = {}
    for _, port in ipairs(m.ports) do by_port[port.port_id] = port end
    H.equal(by_port.c1.x, 0); H.equal(by_port.c1.y, 6, "first shared port faces second machine")
    H.equal(by_port.c2.x, 0); H.equal(by_port.c2.y, 10, "second shared port faces first machine")
    H.equal(by_port.o1.x, 0); H.equal(by_port.o1.y, 2, "own flow uses outer row")
    H.equal(by_port.o2.x, 0); H.equal(by_port.o2.y, 14, "own flow uses outer row")
end)

H.test("SE2 two hands for one flow on one machine stay put", function()
    local m, grid, flows = machine_fixture(true)
    local old = {}
    for _, p in ipairs(m.ports) do old[p.port_id] = {p.x, p.y} end
    H.equal(Seat.run(m, grid, flows, "left"), 3, "only the unrelated eligible hands move")
    for _, id in ipairs({"o1", "o1b"}) do
        local p
        for _, candidate in ipairs(m.ports) do if candidate.port_id == id then p = candidate end end
        H.equal(p.x, old[id][1], id .. " x unchanged"); H.equal(p.y, old[id][2], id .. " y unchanged")
    end
end)

H.test("SE3 row ports are never seated", function()
    local m, grid, flows = machine_fixture(false)
    local row = m.ports[1]
    row.row_port = true
    local x, y = row.x, row.y
    Seat.run(m, grid, flows, "left")
    H.equal(row.x, x, "row port x unchanged"); H.equal(row.y, y, "row port y unchanged")
end)

H.test("SE4 approach tile is open", function()
    H.equal(Seat.approach_open({work = {}}), true)
end)

H.done("test_seat")
