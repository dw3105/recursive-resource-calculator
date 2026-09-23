--Round 27: Groups.reverse_run flips one row run (docs/contracts/row_block.md §Reversal).
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Fixture = require "tests.fixtures.row_block"

local copper, gear, pack = Fixture.COPPER, Fixture.GEAR, Fixture.PACK
local catalog = {entity={assembler={name="assembler",tile_w=3,tile_h=3,etype="assembling-machine"},
    inserter={name="inserter",tile_w=1,tile_h=1,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}},
    inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}, belt={items_per_second=15}}
local function row_block(inputs)
    local ins = {}
    for _, id in ipairs(inputs) do ins[#ins + 1] = {flow_id = id, rate_per_second = 4} end
    local flows = {{flow_id = pack}}
    for _, id in ipairs(inputs) do flows[#flows + 1] = {flow_id = id} end
    local s = Groups.begin({plan = {steps = {{step_id = "science", machine = "assembler", machine_count = 4,
        recipe = "automation-science-pack", inputs = ins, outputs = {{flow_id = pack, rate_per_second = 4}}}},
        flows = flows, ports = {}}, catalog = catalog, _force_multi_flow_hands = true})
    for _ = 1, 8 do if s.done then break end; Groups.step(s, {ops = 1}) end
    for _, c in ipairs(s.result and s.result.candidates or {}) do
        for _, b in ipairs(c.blocks) do if b.row then return b end end
    end
end
local function key(x, y) return tostring(x) .. ":" .. tostring(y) end
local function run_of(block, role)
    for _, run in ipairs(block.belt_runs) do if run.role == role then return run end end
end
local function ports_ok(b)
    for _, p in ipairs(b.ports) do
        local dx, dy = p.attach_dx, p.attach_dy
        local bounded = ((dx == -1 or dx == b.w) and dy >= 0 and dy < b.h) or ((dy == -1 or dy == b.h) and dx >= 0 and dx < b.w)
        if bounded then
            local nx, ny = Grid.dir_vector(p.normal_dir)
            local inward = (dx == -1 and nx == 1) or (dx == b.w and nx == -1) or (dy == -1 and ny == 1) or (dy == b.h and ny == -1)
            if not inward then return false, tostring(p.port_id) .. " normal" end
        elseif not (p.role == "in" and not p.rear) then
            return false, tostring(p.port_id) .. " off boundary"
        end
    end
    return true
end
local function hands_meet_runs(b)
    for _, dir in ipairs({Grid.NORTH, Grid.EAST}) do
        local placed = Groups.materialize(b, {x = 10, y = 20, dir = dir})
        local tiles = {}
        for _, run in ipairs(placed.belt_runs) do
            tiles[run.role] = {}
            for _, t in ipairs(run.tiles) do tiles[run.role][key(t.x, t.y)] = true end
        end
        for _, e in ipairs(placed.entities) do
            if e.kind == "inserter" then
                local dx, dy = Grid.dir_vector(e.dir)
                local at = e.role == "input" and key(e.x - dx, e.y - dy) or key(e.x + dx, e.y + dy)
                if not tiles[e.role == "input" and "in" or "out"][at] then return false end
            end
        end
    end
    return true
end

for _, case in ipairs({{"two inputs", {copper, gear}}, {"one input", {copper}}}) do
    local label, inputs = case[1], case[2]
    H.test("RR1 " .. label .. ": reversing a run twice gives the row back", function()
        local b = row_block(inputs); H.equal(b ~= nil, true, "row exists"); if not b then return end
        for _, role in ipairs({"in", "out"}) do
            local twice = Groups.reverse_run(Groups.reverse_run(b, role), role)
            H.equal(twice ~= nil, true, role .. " reverses")
            local a, z = run_of(b, role), run_of(twice, role)
            H.equal(#a.tiles, #z.tiles, role .. " tile count")
            for i = 1, #a.tiles do H.equal(key(a.tiles[i].x, a.tiles[i].y), key(z.tiles[i].x, z.tiles[i].y), role .. " tile " .. i) end
            H.equal(a.dir, z.dir, role .. " dir")
            for i, p in ipairs(b.ports) do
                H.equal(key(p.attach_dx, p.attach_dy), key(twice.ports[i].attach_dx, twice.ports[i].attach_dy), tostring(p.port_id))
                H.equal(p.travel_dir, twice.ports[i].travel_dir, tostring(p.port_id) .. " travel")
            end
        end
    end)
    H.test("RR2 " .. label .. ": a reversed run flows the other way, still serves every hand, ports stay on the boundary", function()
        local b = row_block(inputs); H.equal(b ~= nil, true, "row exists"); if not b then return end
        for _, role in ipairs({"in", "out"}) do
            local r = Groups.reverse_run(b, role)
            H.equal(run_of(r, role).dir, Grid.dir_opposite(run_of(b, role).dir), role .. " flows the other way")
            local ok, why = ports_ok(r)
            H.equal(ok, true, role .. " ports: " .. tostring(why))
            H.equal(hands_meet_runs(r), true, role .. " hands still meet their run in NORTH and EAST")
            H.equal(b.ports[1].attach_dx ~= nil and run_of(b, role).dir ~= nil, true, "original untouched")
        end
        local out = Groups.reverse_run(b, "out")
        for _, p in ipairs(out.ports) do
            if p.role == "out" then H.equal(p.attach_dx, -1, "reversed output port leaves by the left edge") end
        end
    end)
end
H.test("RR3 a block that is no row is never reversed", function()
    H.equal(Groups.reverse_run({w = 3, h = 3, ports = {}}, "in"), nil, "plain block")
    H.equal(Groups.reverse_run(nil, "in"), nil, "nil block")
end)
H.done("test_row_reverse")
