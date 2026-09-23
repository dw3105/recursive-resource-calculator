--Shared fixture for round 26 (docs/contracts/row_block.md): one placed science row, built by hand.
--Four touching 3x3 assembling-machine-3 on automation-science-pack; a paired input hand (copper-plate +
--iron-gear-wheel) on each machine's top face and an output hand on its bottom face, all in the middle column;
--an input run with a head tile fed from both sides, an output run with one port.
--RowFixture.science_row(dir, ox, oy) returns world data for dir = Grid.NORTH or Grid.EAST at origin (ox, oy).
local Grid = require "logic.bp.grid"
local RowFixture = {}

local COPPER, GEAR, PACK = "item/copper-plate", "item/iron-gear-wheel", "item/automation-science-pack"
RowFixture.COPPER, RowFixture.GEAR, RowFixture.PACK = COPPER, GEAR, PACK

--North frame, relative to the origin:
--  row y = 0: input run, head at x = 0, tiles x = 0..11, travelling EAST; hand pickups at x = 2, 5, 8, 11
--  row y = 1: input hands at x = 2, 5, 8, 11
--  rows y = 2..4: machines at x = 1, 4, 7, 10 (3 wide, touching)
--  row y = 5: output hands at x = 2, 5, 8, 11
--  row y = 6: output run x = 2..11 travelling EAST; its port at (12, 6)
--  copper feeds the head from its left (north) side (0, -1) travelling SOUTH;
--  gears feed it from its right (south) side (0, 1) travelling NORTH.
local function north_frame()
    local frame = {machines = {}, inserters = {}, runs = {}}
    local in_tiles, out_tiles, in_hands, out_hands = {}, {}, {}, {}
    for x = 0, 11 do in_tiles[#in_tiles + 1] = {x = x, y = 0} end
    for x = 2, 11 do out_tiles[#out_tiles + 1] = {x = x, y = 6} end
    for i = 0, 3 do
        local mx = 1 + 3 * i
        local machine_id = "m:machine:automation-science-pack:" .. (i + 1)
        frame.machines[#frame.machines + 1] = {id = machine_id, kind = "machine", name = "assembling-machine-3",
            recipe = "automation-science-pack", step_id = "automation-science-pack", x = mx, y = 2, w = 3, h = 3}
        local hx = mx + 1
        local input_id = "m:inserter:automation-science-pack:" .. (i + 1) .. ":input:1"
        local output_id = "m:inserter:automation-science-pack:" .. (i + 1) .. ":output:2"
        frame.inserters[#frame.inserters + 1] = {id = input_id, kind = "inserter", name = "inserter",
            role = "input", machine_id = machine_id, flow_ids = {COPPER, GEAR}, x = hx, y = 1, w = 1, h = 1,
            pickup = {x = hx, y = 0}, drop = {x = hx, y = 2}}
        frame.inserters[#frame.inserters + 1] = {id = output_id, kind = "inserter", name = "inserter",
            role = "output", machine_id = machine_id, flow_id = PACK, x = hx, y = 5, w = 1, h = 1,
            pickup = {x = hx, y = 4}, drop = {x = hx, y = 6}}
        in_hands[#in_hands + 1], out_hands[#out_hands + 1] = input_id, output_id
    end
    frame.runs[1] = {role = "in", flows = {COPPER, GEAR}, tiles = in_tiles, dir = Grid.EAST, head = {x = 0, y = 0},
        feeds = {{flow_id = COPPER, side_tile = {x = 0, y = -1}, travel_dir = Grid.SOUTH},
                 {flow_id = GEAR, side_tile = {x = 0, y = 1}, travel_dir = Grid.NORTH}},
        hand_ids = in_hands}
    frame.runs[2] = {role = "out", flows = {PACK}, tiles = out_tiles, dir = Grid.EAST,
        port = {x = 12, y = 6, travel_dir = Grid.EAST}, hand_ids = out_hands}
    return frame
end

--Turn a north-frame point 90 degrees clockwise about the origin: (x, y) -> (-y, x); then translate.
local function place_point(p, dir, ox, oy)
    if dir == Grid.EAST then return {x = ox - p.y, y = oy + p.x} end
    return {x = ox + p.x, y = oy + p.y}
end
local function place_rect(r, dir, ox, oy)
    if dir == Grid.EAST then return {x = ox - (r.y + r.h - 1), y = oy + r.x, w = r.h, h = r.w} end
    return {x = ox + r.x, y = oy + r.y, w = r.w, h = r.h}
end
local function place_dir(d, dir) return dir == Grid.EAST and Grid.rotate_dir(d, Grid.EAST) or d end

function RowFixture.science_row(dir, ox, oy)
    dir, ox, oy = dir or Grid.NORTH, ox or 0, oy or 0
    local frame, world = north_frame(), {machines = {}, inserters = {}, belt_runs = {}, ports = {}}
    for _, m in ipairs(frame.machines) do
        local r = place_rect(m, dir, ox, oy)
        local copy = {}; for k, v in pairs(m) do copy[k] = v end
        copy.x, copy.y, copy.w, copy.h = r.x, r.y, r.w, r.h
        copy.position = {x = r.x + r.w / 2, y = r.y + r.h / 2}
        world.machines[#world.machines + 1] = copy
    end
    for _, h in ipairs(frame.inserters) do
        local p = place_point(h, dir, ox, oy)
        local copy = {}; for k, v in pairs(h) do copy[k] = v end
        copy.x, copy.y = p.x, p.y
        copy.position = {x = p.x + 0.5, y = p.y + 0.5}
        local pick, drop = place_point(h.pickup, dir, ox, oy), place_point(h.drop, dir, ox, oy)
        copy.pickup, copy.drop = nil, nil
        copy.pickup_position = {x = pick.x + 0.5, y = pick.y + 0.5}
        copy.drop_position = {x = drop.x + 0.5, y = drop.y + 0.5}
        world.inserters[#world.inserters + 1] = copy
    end
    for _, run in ipairs(frame.runs) do
        local placed = {role = run.role, flows = run.flows, dir = place_dir(run.dir, dir), tiles = {},
            hand_ids = run.hand_ids}
        for _, t in ipairs(run.tiles) do placed.tiles[#placed.tiles + 1] = place_point(t, dir, ox, oy) end
        if run.head then placed.head = place_point(run.head, dir, ox, oy) end
        if run.feeds then
            placed.feeds = {}
            for _, f in ipairs(run.feeds) do
                local p = place_point(f.side_tile, dir, ox, oy)
                placed.feeds[#placed.feeds + 1] = {flow_id = f.flow_id, side_tile = p,
                    travel_dir = place_dir(f.travel_dir, dir)}
                world.ports[#world.ports + 1] = {port_id = "row:in:" .. f.flow_id, role = "in", flow_id = f.flow_id,
                    x = p.x, y = p.y, travel_dir = place_dir(f.travel_dir, dir)}
            end
        end
        if run.port then
            local p = place_point(run.port, dir, ox, oy)
            placed.port = {x = p.x, y = p.y, travel_dir = place_dir(run.port.travel_dir, dir)}
            world.ports[#world.ports + 1] = {port_id = "row:out:" .. run.flows[1], role = "out",
                flow_id = run.flows[1], x = p.x, y = p.y, travel_dir = placed.port.travel_dir}
        end
        world.belt_runs[#world.belt_runs + 1] = placed
    end
    return world
end

return RowFixture
