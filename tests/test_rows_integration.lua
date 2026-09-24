--Round 26 integration: the row block (docs/contracts/row_block.md) as groups, pack and materialize hand it on.
--Each case pins one defect measured 2026-09-23 on legalcopilot-dev when lanes 180-182 first met the
--player's sheet (int/r26, 402207b): every one of them passed its own lane's tests.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Pack = require "logic.bp.pack"
local Grid = require "logic.bp.grid"
local Fixture = require "tests.fixtures.row_block"

local copper, gear, pack = Fixture.COPPER, Fixture.GEAR, Fixture.PACK
local catalog = {entity={assembler={name="assembler",tile_w=3,tile_h=3,etype="assembling-machine"},
    inserter={name="inserter",tile_w=1,tile_h=1,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}},
    inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}, belt={items_per_second=15}}
local function plan()
    local ins = {{flow_id=copper,rate_per_second=4},{flow_id=gear,rate_per_second=4}}
    return {steps={{step_id="science",machine="assembler",machine_count=4,recipe="automation-science-pack",inputs=ins,
        outputs={{flow_id=pack,rate_per_second=4}}}}, flows={{flow_id=copper},{flow_id=gear},{flow_id=pack}}, ports={}}
end
local function candidates()
    local s = Groups.begin({plan=plan(), catalog=catalog, _force_multi_flow_hands=true})
    for _ = 1, 8 do if s.done then break end; Groups.step(s, {ops=1}) end
    return s.result and s.result.candidates or {}
end
local function row_block()
    for _, c in ipairs(candidates()) do for _, b in ipairs(c.blocks) do if b.row then return b end end end
end
local function key(x, y) return tostring(x) .. ":" .. tostring(y) end

H.test("RI1 both hands of a row move items the same way (top belt -> machine -> bottom belt)", function()
    local b = row_block(); H.equal(b ~= nil, true, "row exists"); if not b then return end
    for _, hand in ipairs(b.inserters) do H.equal(hand.dir, Grid.SOUTH, tostring(hand.id) .. " dir") end
end)

H.test("RI2 every hand meets its run in both orientations (run tiles rotate as cells)", function()
    local b = row_block(); H.equal(b ~= nil, true, "row exists"); if not b then return end
    for _, dir in ipairs({Grid.NORTH, Grid.EAST}) do
        local placed = Groups.materialize(b, {x = 10, y = 20, dir = dir})
        local run_tiles = {}
        for _, run in ipairs(placed.belt_runs) do
            run_tiles[run.role] = {}
            for _, t in ipairs(run.tiles) do run_tiles[run.role][key(t.x, t.y)] = true end
        end
        local hands = 0
        for _, e in ipairs(placed.entities) do
            if e.kind == "inserter" then
                hands = hands + 1
                local dx, dy = Grid.dir_vector(e.dir)
                if e.role == "input" then
                    H.equal(run_tiles["in"][key(e.x - dx, e.y - dy)], true, "input pickup on in-run, dir " .. dir)
                else
                    H.equal(run_tiles["out"][key(e.x + dx, e.y + dy)], true, "output drop on out-run, dir " .. dir)
                end
            end
        end
        H.equal(hands, 8, "eight hands placed")
    end
end)

H.test("RI3 row ports sit on the block boundary with inward normals, except the interior head feed", function()
    local b = row_block(); H.equal(b ~= nil, true, "row exists"); if not b then return end
    local interior = 0
    for _, p in ipairs(b.ports) do
        H.equal(p.row_port, true, tostring(p.port_id) .. " is a row port")
        local dx, dy = p.attach_dx, p.attach_dy
        local bounded = ((dx == -1 or dx == b.w) and dy >= 0 and dy < b.h) or ((dy == -1 or dy == b.h) and dx >= 0 and dx < b.w)
        if bounded then
            local nx, ny = Grid.dir_vector(p.normal_dir)
            local inward = (dx == -1 and nx == 1) or (dx == b.w and nx == -1) or (dy == -1 and ny == 1) or (dy == b.h and ny == -1)
            H.equal(inward, true, tostring(p.port_id) .. " normal points into the block")
        else
            interior = interior + 1
            H.equal(p.role, "in", tostring(p.port_id) .. " interior port is a head feed")
        end
        if p.role == "out" then H.equal(dx, b.w, "output port is the tile after the run's end, on the right edge") end
    end
    H.equal(interior, 1, "exactly one interior head feed")
end)

H.test("RI4 grouping emits exactly the row candidate", function()
    local list = candidates()
    H.equal(#list, 1, "one candidate")
    H.equal(list[1] and list[1].id, "one", "stable candidate id")
    H.equal(list[1] and list[1].blocks[1].row ~= nil, true, "eligible machines use a row")
end)

H.test("RI5 pack keeps a row's ports and their approach tiles off the grid's outer ring", function()
    local b = row_block(); H.equal(b ~= nil, true, "row exists"); if not b then return end
    --Rear port + approach on one end, output port + approach on the other, each off the outer ring: 3 tiles a side.
    local area = Grid.rect(0, 0, b.w + 8, b.w + 8)
    local state, steps = Pack.begin({area = area, blocks = {b}, obstacles = {}, limits = {}}), 0
    while not state.done and steps < 100000 do Pack.step(state, {ops = 64}); steps = steps + 1 end
    H.equal(state.ok, true, "row packs")
    local placement = state.placements and state.placements[1]
    H.equal(placement ~= nil, true, "placed"); if not placement then return end
    for _, p in ipairs(b.ports) do
        local at = Grid.place_port(b, placement, p)
        local inner = at.x > area.x and at.y > area.y and at.x < area.x + area.w - 1 and at.y < area.y + area.h - 1
        H.equal(inner, true, tostring(p.port_id) .. " off the outer ring at " .. at.x .. "," .. at.y)
    end
end)

H.done("test_rows_integration")
