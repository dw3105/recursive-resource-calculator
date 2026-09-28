--Guard for lane 259 (2026-09-28): NOT red on base -- the synthetic layout never offered the rear entry; the fault
--was measured only on player-inserter-10s-stack1 (pair (31,32)->(24,32), branch at (25,32)), proven there by a
--whole-sheet run. UR1 guards the shape, UR2 guards riding a same-flow pair.
--UR1 was designed to fail on round-45-w3: a same-flow branch can enter a belt underground output from its buried rear.
--UR2 protects the existing allow_ride behavior while checking the rear-entry rule.
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"

local function finish(input)
    local state, ticks = Route.begin(input), 0
    while not state.done and ticks < 30000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "route completes")
    return state
end

local function input()
    local flow = "item/circuit"
    local function block(id, x, y, role, pid, dir, connection)
        local sign = role == "out" and 1 or -1
        return {block_id=id, machines={{step_id=id}}, x=x, y=y, w=1, h=1, ports={{
            port_id=pid, role=role, kind="item", flow_id=flow, rate_per_second=1,
            attach_dx=sign, attach_dy=0, normal_dir=role == "out" and Grid.WEST or Grid.EAST,
            travel_dir=dir, connection=connection,
        }}}
    end
    local underground_source = {connection_type="underground", direction=Grid.WEST, max_underground_distance=8}
    local underground_sink = {connection_type="underground", direction=Grid.EAST, max_underground_distance=8}
    return {grid=Grid.new(40,40), obstacles={{x=0,y=31,w=40,h=1,owner="wall"},
        {x=0,y=33,w=40,h=1,owner="wall"}}, catalog={belt={belt="basic-belt", underground="basic-underground",
        items_per_second=10, underground_max_distance=8}},
        blocks={
            block("pair-source",30,32,"out","pair-out",Grid.WEST,underground_source),
            block("pair-sink",25,32,"in","pair-in",Grid.WEST,underground_sink),
            block("branch-source",25,24,"out","branch-out",Grid.SOUTH),
            block("branch-sink",21,32,"in","branch-in",Grid.WEST),
        },
        flows={{flow_id=flow,is_fluid=false,
            producers={{step_id="pair-source",share_per_second=1},{step_id="branch-source",share_per_second=1}},
            consumers={{step_id="pair-sink",share_per_second=1},{step_id="branch-sink",share_per_second=1}}}},
    }
end

local function check_no_rear_entry(state, entry_x, exit_x, y)
    local bad = false
    for _, entity in ipairs(state.result.entities or {}) do
        if entity.name == "basic-belt" and entity.flow_id == "item/circuit" then
            local x, ey = math.floor(entity.position.x), math.floor(entity.position.y)
            local dx, dy = Grid.dir_vector(entity.direction)
            if ey == y and x > exit_x and x < entry_x then bad = true end
            if x == exit_x + dx and ey == y + dy then bad = true end
        end
    end
    H.equal(bad, false, "no circuit belt enters the underground output from its rear")
end

H.test("UR1 same-flow branch cannot enter a westbound pair exit from the rear", function()
    local state = finish(input())
    H.equal(state.ok, true, "both circuit demands route")
    for _,e in ipairs(state.result.entities or {}) do if e.ug_role then print("UG",e.ug_role,e.position.x,e.position.y,e.direction) elseif e.name=="basic-belt" then print("B",e.position.x,e.position.y,e.direction,e.flow_id) end end
    check_no_rear_entry(state, 31, 24, 32)
end)

H.test("UR2 same-flow underground pair ride remains available", function()
    local state = finish(input())
    local pair = false
    for _, segment in ipairs(state.work.segments or {}) do
        if segment.underground and segment.flow_id == "item/circuit"
            and segment.underground_entry_x == 31 and segment.underground_exit_x == 24 then pair = true end
    end
    H.equal(pair, true, "same-flow westbound underground pair is retained")
    H.equal(state.ok, true, "allow_ride fallback completes")
end)

H.done("test_route_ug_exit_rear")
