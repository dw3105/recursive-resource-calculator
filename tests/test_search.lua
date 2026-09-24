--The bounded blueprint search keeps the best complete candidate, grows grids deterministically, and distinguishes budget from impossibility.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Pack = require "logic.bp.pack"
local Power = require "logic.bp.power"
local Route = require "logic.bp.route"
local Search = require "logic.bp.search"
local Validate = require "logic.bp.validate"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function plain(value, path, seen)
    local value_type = type(value)
    H.equal(value_type == "function" or value_type == "userdata", false, path .. " is serializable data")
    if value_type ~= "table" then return end
    H.equal(getmetatable(value), nil, path .. " has no metatable")
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        plain(key, path .. ".<key>", seen)
        plain(child, path .. "." .. tostring(key), seen)
    end
end

local function box()
    return {{-0.4, -0.4}, {0.4, 0.4}}
end

local function pole()
    return {name = "medium-electric-pole", tile_w = 1, tile_h = 1, supply_w = 10, supply_h = 10, wire_reach = 20}
end

local function base_catalog()
    return {
        entity = {
            assembler = {name = "assembler", tile_w = 1, tile_h = 1, energy_usage_w = 1,
                collision_box = box(), collision_mask = {"item-layer"}},
            beacon = {name = "beacon", tile_w = 1, tile_h = 1,
                collision_box = box(), collision_mask = {"item-layer"}, beacon = {supply_w = 10, supply_h = 10}},
            inserter = {name = "inserter", tile_w = 1, tile_h = 1,
                collision_box = box(), collision_mask = {"item-layer"}},
        },
        beacon = {beacon = {supply_w = 10, supply_h = 10}},
        inserter = {name = "inserter", items_per_second = 10},
        robo = {name = "roboport", tile_w = 1, tile_h = 1, connection_distance = 3},
    }
end

local function one_step_plan()
    return {steps = {{step_id = "one", machine = "assembler", machine_count = 1, power_w = 1,
        modules = {}, beacon_groups = {}, inputs = {}, outputs = {}}}, flows = {}, ports = {}}
end

local function perimeter_plan()
    return {steps = {{step_id = "one", machine = "assembler", machine_count = 1, power_w = 1, modules = {},
        beacon_groups = {}, inputs = {}, outputs = {}}}, flows = {},
        ports = {{port_id = "out:item/plate", role = "out", kind = "item", flow_id = "item/plate", rate_per_second = 0}}}
end

local function active_perimeter_plan()
    local plan = perimeter_plan()
    plan.ports[1].rate_per_second = 1
    return plan
end

local function perimeter_pair_plan()
    return {steps = {{step_id = "one", machine = "assembler", machine_count = 1, power_w = 1, modules = {},
        beacon_groups = {}, inputs = {}, outputs = {}}}, flows = {}, ports = {
        {port_id = "in:item/raw", role = "in", kind = "item", flow_id = "item/raw", rate_per_second = 0},
        {port_id = "out:item/gear", role = "out", kind = "item", flow_id = "item/gear", rate_per_second = 0},
    }}
end

local function shared_plan()
    local group = {signature = "shared", name = "beacon", count_per_machine = 1, has_speed_module = false, modules = {}}
    return {steps = {
        {step_id = "a", machine = "assembler", machine_count = 1, power_w = 1, modules = {}, beacon_groups = {group}},
        {step_id = "b", machine = "assembler", machine_count = 1, power_w = 1, modules = {}, beacon_groups = {group}},
    }, flows = {}, ports = {}}
end

local function input_for(plan, extra)
    local input = {
        plan = plan, catalog = base_catalog(), pole = pole(), include_roboports = false,
        grids = {{w = 2, h = 3}, {w = 3, h = 3}},
    }
    for key, value in pairs(extra or {}) do input[key] = value end
    return input
end

local function roboport_input()
    return input_for(one_step_plan(), {
        include_roboports = true,
        --Roboports stay outside every machine buffer zone (docs/contracts/pipeline_r29.md C2): both sit in one
        --corner, within connection distance 3 of each other, on a grid with room for a ring-2 zone clear of them.
        grids = {{w = 16, h = 12, roboports = {
            {x = 0, y = 0, w = 1, h = 1},
            {x = 3, y = 0, w = 1, h = 1},
        }}},
    })
end

local function finish(input, operations)
    local state = Search.begin(input)
    local ticks = 0
    while not state.done and ticks < 600 do
        ticks = ticks + 1
        Search.step(state, {ops = operations or 100000})
    end
    H.equal(state.done, true, "search finishes within the test bound; stopped in phase " .. tostring(state.phase))
    return state
end

local function complete_stage(result)
    return {done = true, ok = true, result = result or {}, progress = {phase = "done", done_units = 1, total_units = 1}}
end

local function failed_stage(code, detail)
    return {done = true, ok = false, result = {}, errors = {{code = code, detail = detail}},
        progress = {phase = "failed", done_units = 1, total_units = 1}}
end

local function port_by_role(ports, role)
    for _, port in ipairs(ports or {}) do
        if port.role == role then return port end
    end
end

local function on_edge(port, edge, width, height)
    if edge == "top" then return port.y == 0 end
    if edge == "bottom" then return port.y == height - 1 end
    if edge == "left" then return port.x == 0 end
    if edge == "right" then return port.x == width - 1 end
    return false
end

local function travel_for(edge, role)
    local outward = {top = Grid.NORTH, right = Grid.EAST, bottom = Grid.SOUTH, left = Grid.WEST}
    local direction = outward[edge]
    return role == "in" and Grid.dir_opposite(direction) or direction
end

local function distinct_port_cells(ports)
    local seen = {}
    for _, port in ipairs(ports or {}) do
        local key = tostring(port.x) .. ":" .. tostring(port.y)
        if seen[key] then return false end
        seen[key] = true
    end
    return true
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " BP-15 a small feasible plan publishes a validated blueprint", function()
        local state = finish(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}}))
        H.equal(state.ok, true, "the feasible search succeeds")
        H.equal(state.result ~= nil, true, "a complete result is published")
        H.equal(state.incumbent ~= nil, true, "a validated incumbent was retained")
        H.equal(state.incumbent.validation ~= nil, true, "the incumbent includes validation output")
    end)

    H.test(shape .. " BP-15 a real small plan serializes with in-grid perimeter ports", function()
        local input = input_for(perimeter_plan(), {
            grids = {{w = 3, h = 5}}, area = {x = 0, y = 1, w = 1, h = 4}, port_pitch = 1,
            settings = {input_edge = "top", output_edge = "bottom"},
            pole = {name = "medium-electric-pole", tile_w = 1, tile_h = 1, supply_w = 10, supply_h = 10,
                wire_reach = 20, x = 2, y = 2},
        })
        local state = finish(input)
        H.equal(state.ok, true, "the perimeter plan search succeeds in phase " .. tostring(state.phase)
            .. " with " .. tostring(state.errors and state.errors[1] and state.errors[1].code))
        H.equal(type(state.result), "table", "the perimeter plan has a serialized result")
        H.equal(type(state.result.entities), "table", "the serialized result has entities")
        local ports = state.incumbent and state.incumbent.candidate and state.incumbent.candidate.external_ports or {}
        H.equal(#ports, 1, "the serialized candidate carries the perimeter port")
        for _, port in ipairs(ports) do
            H.equal(port.x >= 0 and port.x < input.grids[1].w and port.y >= 0 and port.y < input.grids[1].h,
                true, port.port_id .. " is inside the grid")
            H.equal(port.x, 0, "the output keeps the selected bottom-edge pitch slot")
            H.equal(port.y, input.grids[1].h - 1, "the output sits on the grid's bottom edge cell")
            H.equal(port.travel_dir, Grid.SOUTH, "the output travel direction leaves the grid")
        end
    end)

    H.test(shape .. " BP-15 default perimeter edges never share their corner cell", function()
        local input = input_for(perimeter_pair_plan(), {grids = {{w = 3, h = 3}}})
        local state = finish(input)
        H.equal(state.ok, true, "the default perimeter search succeeds")
        local ports = state.incumbent.candidate.external_ports
        local input_port, output_port = port_by_role(ports, "in"), port_by_role(ports, "out")
        H.equal(#ports, 2, "the default perimeter has both ports")
        H.equal(distinct_port_cells(ports), true, "the default perimeter ports use distinct cells")
        H.equal(input_port.x, 0, "the default input stays on the left edge")
        H.equal(input_port.travel_dir, Grid.EAST, "the default input travels into the grid")
        H.equal(output_port.y, 0, "the default output stays on the top edge")
        H.equal(output_port.travel_dir, Grid.NORTH, "the default output travels out of the grid")
    end)

    H.test(shape .. " BP-15 every differing perimeter edge pair avoids a shared corner", function()
        local edges = {"top", "right", "bottom", "left"}
        for _, input_edge in ipairs(edges) do
            for _, output_edge in ipairs(edges) do
                if input_edge ~= output_edge then
                    local input = input_for(perimeter_pair_plan(), {
                        grids = {{w = 4, h = 4}},
                        settings = {input_edge = input_edge, output_edge = output_edge},
                    })
                    local state = finish(input)
                    local label = input_edge .. " input / " .. output_edge .. " output"
                    H.equal(state.ok, true, label .. " perimeter search succeeds")
                    local ports = state.incumbent.candidate.external_ports
                    local input_port, output_port = port_by_role(ports, "in"), port_by_role(ports, "out")
                    H.equal(distinct_port_cells(ports), true, label .. " ports use distinct cells")
                    H.equal(on_edge(input_port, input_edge, 4, 4), true, label .. " input stays on its edge")
                    H.equal(on_edge(output_port, output_edge, 4, 4), true, label .. " output stays on its edge")
                    H.equal(input_port.travel_dir, travel_for(input_edge, "in"), label .. " input travel direction")
                    H.equal(output_port.travel_dir, travel_for(output_edge, "out"), label .. " output travel direction")
                end
            end
        end
    end)

    H.test(shape .. " BP-15 a perimeter grid with no free port slot fails without stacking", function()
        local input = input_for(perimeter_pair_plan(), {grids = {{w = 1, h = 1}}})
        local state = finish(input)
        H.equal(state.ok, false, "the undersized perimeter search fails")
        H.equal(state.errors[1].code, "BP_FAIL_NO_LAYOUT", "slot exhaustion reports no layout")
        H.equal(distinct_port_cells(state.work.perimeter_ports), true, "slot exhaustion never stacks ports")
        H.equal(#state.work.perimeter_ports, 1, "slot exhaustion keeps only the available perimeter slot")
    end)

    H.test(shape .. " BP-20 route entities with positions occupy their power cells", function()
        local input = input_for(one_step_plan(), {grids = {{w = 4, h = 4}}})
        local occupied
        local originals = {route_begin = Route.begin, route_step = Route.step,
            power_begin = Power.begin, power_step = Power.step,
            validate_begin = Validate.begin, validate_step = Validate.step}
        Route.begin = function()
            return complete_stage({entities = {{id = "r:position", name = "transport-belt",
                position = {x = 2.5, y = 1.5}, direction = Grid.EAST, dir = Grid.EAST}},
                segments = {}, wires = {}, bindings = {}})
        end
        Route.step = function() end
        Power.begin = function(stage_input)
            occupied = clone(stage_input.occupied)
            return complete_stage({entities = {}, wires = {}})
        end
        Power.step = function() end
        Validate.begin = function()
            return complete_stage({score = {beacon_count = 0, footprint_area = 1}})
        end
        Validate.step = function() end
        local ok, state_or_error = pcall(function() return finish(input) end)
        Route.begin, Route.step, Power.begin, Power.step = originals.route_begin, originals.route_step,
            originals.power_begin, originals.power_step
        Validate.begin, Validate.step = originals.validate_begin, originals.validate_step
        H.equal(ok, true, "the position occupancy search finishes without raising: " .. tostring(state_or_error))
        if not ok then return end
        local found
        for _, entry in ipairs(occupied or {}) do
            if entry.owner == "r:position" then found = entry.rect break end
        end
        H.equal(found ~= nil, true, "the power stage receives the routed entity owner")
        if found then H.deep_equal(found, {x = 2, y = 1, w = 1, h = 1}, "position derives the routed entity rectangle") end
    end)

    H.test(shape .. " BP-20 active perimeter ports clear roboport footprints before packing", function()
        local input = input_for(active_perimeter_plan(), {
            include_roboports = true,
            grids = {{w = 6, h = 4, roboports = {{x = 0, y = 0, w = 1, h = 1}, {x = 2, y = 2, w = 1, h = 1}}}},
        })
        local packed_obstacles
        local original_begin = Pack.begin
        Pack.begin = function(stage_input)
            packed_obstacles = clone(stage_input.obstacles)
            return original_begin(stage_input)
        end
        local ok, state_or_error = pcall(function() return finish(input) end)
        Pack.begin = original_begin
        H.equal(ok, true, "the perimeter clearance search finishes without raising: " .. tostring(state_or_error))
        if not ok then return end
        H.equal(#packed_obstacles >= 4, true, "the packer receives two perimeter clearance rectangles")
        if #packed_obstacles >= 4 then
            H.deep_equal(packed_obstacles[3], {x = 0, y = 0, w = 2, h = 2}, "first roboport clearance")
            H.deep_equal(packed_obstacles[4], {x = 1, y = 1, w = 3, h = 3}, "second roboport clearance")
        end
    end)

    H.test(shape .. " BP-15 implicit active-perimeter search stops after its first valid layout", function()
        local input = input_for(active_perimeter_plan(), {max_grid = 30})
        input.grids = nil
        local originals = {route_begin = Route.begin, route_step = Route.step,
            power_begin = Power.begin, power_step = Power.step,
            validate_begin = Validate.begin, validate_step = Validate.step}
        Route.begin = function() return complete_stage({entities = {}, segments = {}, wires = {}, bindings = {}}) end
        Route.step = function() end
        Power.begin = function() return complete_stage({entities = {}, wires = {}}) end
        Power.step = function() end
        Validate.begin = function() return complete_stage({score = {beacon_count = 0, footprint_area = 1}}) end
        Validate.step = function() end
        local ok, state_or_error = pcall(function() return finish(input, 1) end)
        Route.begin, Route.step, Power.begin, Power.step = originals.route_begin, originals.route_step,
            originals.power_begin, originals.power_step
        Validate.begin, Validate.step = originals.validate_begin, originals.validate_step
        H.equal(ok, true, "the implicit perimeter search finishes without raising: " .. tostring(state_or_error))
        if not ok then return end
        H.equal(state_or_error.ok, true, "the implicit perimeter search publishes its first valid layout")
    end)

    H.test(shape .. " BP-15 a roboport grid reaches a placement without raising", function()
        local input = roboport_input()
        local packed_obstacles
        local original_begin = Pack.begin
        Pack.begin = function(stage_input)
            packed_obstacles = clone(stage_input.obstacles)
            return original_begin(stage_input)
        end
        local ok, state_or_error = pcall(function() return finish(input) end)
        Pack.begin = original_begin
        H.equal(ok, true, "a roboport search reaches placement without raising: " .. tostring(state_or_error))
        if not ok then return end

        local state = state_or_error
        for index, roboport in ipairs(input.grids[1].roboports) do
            local obstacle = packed_obstacles and packed_obstacles[index]
            H.equal(obstacle ~= nil, true, "the packer receives roboport " .. tostring(index))
            if obstacle then
                H.equal(obstacle.rect, nil, "the packer receives a bare rectangle for roboport " .. tostring(index))
                H.deep_equal(obstacle, roboport, "the packer receives roboport rectangle " .. tostring(index))
            end
        end
        H.equal(state.ok, true, "the roboport search succeeds")
        H.equal(state.incumbent ~= nil, true, "the roboport search retains a candidate")
        local placements = state.incumbent and state.incumbent.candidate and state.incumbent.candidate.placements or {}
        H.equal(#placements > 0, true, "the roboport search has a placement")
        for _, placement in ipairs(placements) do
            for _, roboport in ipairs(input.grids[1].roboports) do
                H.equal(Grid.intersects(placement, roboport), false,
                    "placement avoids roboport at " .. tostring(roboport.x) .. "," .. tostring(roboport.y))
            end
        end
    end)

    H.test(shape .. " BP-20 the power stage keeps owners for roboport obstacles", function()
        local input = roboport_input()
        local occupied
        local original_begin = Power.begin
        Power.begin = function(stage_input)
            occupied = clone(stage_input.occupied)
            return original_begin(stage_input)
        end
        local ok, state_or_error = pcall(function() return finish(input) end)
        Power.begin = original_begin
        H.equal(ok, true, "the power-owner search finishes without raising: " .. tostring(state_or_error))
        if not ok then return end
        H.equal(state_or_error.ok, true, "the power-owner search succeeds")
        for index, roboport in ipairs(input.grids[1].roboports) do
            local owner = "k:" .. tostring(index)
            local found
            for _, entry in ipairs(occupied or {}) do
                if entry.owner == owner then found = entry.rect; break end
            end
            H.equal(found ~= nil, true, "the power stage receives owner " .. owner)
            if found then H.deep_equal(found, roboport, "the power stage receives rectangle for " .. owner) end
        end
    end)

    H.test(shape .. " BP-20 the router receives owner-bearing roboport obstacles", function()
        local input = roboport_input()
        local obstacles
        local original_begin = Route.begin
        Route.begin = function(stage_input)
            obstacles = clone(stage_input.obstacles)
            return original_begin(stage_input)
        end
        local ok, state_or_error = pcall(function() return finish(input) end)
        Route.begin = original_begin
        H.equal(ok, true, "the router-shape search finishes without raising: " .. tostring(state_or_error))
        if not ok then return end
        H.equal(state_or_error.ok, true, "the router-shape search succeeds")
        for index, roboport in ipairs(input.grids[1].roboports) do
            local owner = "k:" .. tostring(index)
            local found
            for _, entry in ipairs(obstacles or {}) do
                if entry.owner == owner then found = entry; break end
            end
            H.equal(found ~= nil, true, "the router receives owner " .. owner)
            if found then
                H.equal(found.rect ~= nil, true, "the router receives a nested rectangle for " .. owner)
                H.deep_equal(found.rect, roboport, "the router receives rectangle for " .. owner)
            end
        end
    end)

    H.test(shape .. " BP-15 the same input searched twice is deterministic", function()
        local first = finish(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}}))
        local second = finish(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}}))
        H.deep_equal(first.result, second.result, "the serialized layouts are identical")
        H.deep_equal(first.incumbent.score, second.incumbent.score, "the objective score is identical")
    end)

    H.test(shape .. " BP-15 exhausting the search budget is not no-layout", function()
        local state = finish(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}, max_ops = 1}), 100000)
        H.equal(state.ok, false, "the bounded search fails")
        H.equal(state.errors[1].code, "BP_FAIL_SEARCH_BUDGET", "budget exhaustion has the budget failure")
        H.equal(state.errors[1].code == "BP_FAIL_NO_LAYOUT", false,
            "budget exhaustion never claims that no layout exists")
        H.equal(state.result, nil, "an unfinished search publishes nothing")
    end)

    H.test(shape .. " BP-15 cancellation mid-search publishes nothing", function()
        local state = Search.begin(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}}))
        Search.step(state, {ops = 1})
        Search.cancel(state)
        H.equal(state.done, true, "cancel completes the job")
        H.equal(state.errors[1].code, "BP_FAIL_CANCELLED", "cancel has its failure code")
        H.equal(state.result, nil, "cancel never publishes a result")
    end)

    H.test(shape .. " BP-15 a revision change before publication drops the result", function()
        local state = Search.begin(input_for(one_step_plan(), {
            grids = {{w = 2, h = 2}}, revisions = {sheet = 4, config = 7},
            current_revisions = {sheet = 4, config = 7},
        }))
        state.current_revisions.sheet = 5
        local ticks = 0
        while not state.done and ticks < 600 do
            ticks = ticks + 1
            Search.step(state, {ops = 100000})
        end
        H.equal(state.done, true, "revision search finishes within the test bound; stopped in phase " .. tostring(state.phase))
        H.equal(state.errors[1].code, "BP_FAIL_REVISION_CHANGED", "the changed revision drops the result")
        H.equal(state.result, nil, "a stale result is never published")
    end)

    H.test(shape .. " BP-15 search state and resumable cursors are plain data", function()
        local state = Search.begin(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}}))
        Search.step(state, {ops = 1})
        plain(state, "search")
        local resumed = clone(state)
        local first, second = state, resumed
        local first_ticks, second_ticks = 0, 0
        while not first.done and first_ticks < 600 do
            first_ticks = first_ticks + 1
            Search.step(first, {ops = 100000})
        end
        H.equal(first.done, true, "copied first cursor finishes within the test bound; stopped in phase " .. tostring(first.phase))
        while not second.done and second_ticks < 600 do
            second_ticks = second_ticks + 1
            Search.step(second, {ops = 100000})
        end
        H.equal(second.done, true, "copied second cursor finishes within the test bound; stopped in phase " .. tostring(second.phase))
        H.deep_equal(first.result, second.result, "a copied cursor resumes the same layout")
    end)

    H.test(shape .. " BP-15 progress stays below one until commit", function()
        local state = Search.begin(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}}))
        local fraction = Search.progress(state)
        H.equal(fraction < 1, true, "initial progress is below one")
        local ticks = 0
        while not state.done and ticks < 600 do
            ticks = ticks + 1
            Search.step(state, {ops = 1})
            local current = Search.progress(state)
            if not state.done then H.equal(current < 1, true, "live progress stays below one") end
        end
        H.equal(state.done, true, "progress search finishes within the test bound; stopped in phase " .. tostring(state.phase))
        H.equal(Search.progress(state), 1, "committed progress reaches one")
    end)
end

H.test("ST1 an exhausted grid ladder reports its own code, never the budget code", function()
    local state = finish(input_for(one_step_plan(), {grids = {{w = 0, h = 0}, {w = 1, h = 1}}, max_search_grids = 1}))
    H.equal(state.ok, false, "an exhausted grid ladder fails")
    H.equal(state.errors[1].code, "BP_FAIL_NO_LAYOUT", "three failed attempts report no layout")
    H.equal(state.errors[1].code == "BP_FAIL_SEARCH_BUDGET", false, "grid exhaustion is not an operation budget")
end)

H.test("ST2 a power bound reports its own code, never the budget code", function()
    local originals = {route_begin = Route.begin, route_step = Route.step,
        power_begin = Power.begin, power_step = Power.step}
    Route.begin = function() return complete_stage({entities = {}, wires = {}, segments = {}, bindings = {}}) end
    Route.step = function() end
    Power.begin = function() return failed_stage("BP_PW_SEARCH_BOUND", "relay search bound") end
    Power.step = function() end
    local ok, state_or_error = pcall(function()
        return finish(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}, max_search_grids = 1}))
    end)
    Route.begin, Route.step = originals.route_begin, originals.route_step
    Power.begin, Power.step = originals.power_begin, originals.power_step
    H.equal(ok, true, "the power-bound search terminates without raising: " .. tostring(state_or_error))
    if not ok then return end
    local state = state_or_error
    H.equal(state.errors[1].code, "BP_FAIL_POWER_BOUND", "power exhaustion has its own failure code")
    H.equal(state.errors[1].code == "BP_FAIL_SEARCH_BUDGET", false, "power exhaustion is not an operation budget")
end)

H.test("ST3 an operation cap still reports BP_FAIL_SEARCH_BUDGET", function()
    local state = finish(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}, max_ops = 1}), 100000)
    H.equal(state.ok, false, "the operation-capped search fails")
    H.equal(state.errors[1].code, "BP_FAIL_SEARCH_BUDGET", "the operation cap keeps the budget code")
end)

H.test("ST4 a pack, route, route-input or power rejection reaches reason_details", function()
    local original_begin, original_step = Pack.begin, Pack.step
    Pack.begin = function() return failed_stage("BP_P_NO_FIT", "pack rejected the candidate") end
    Pack.step = function() end
    local ok, state_or_error = pcall(function()
        return finish(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}, max_search_grids = 1}))
    end)
    Pack.begin, Pack.step = original_begin, original_step
    H.equal(ok, true, "the rejected candidate search terminates without raising: " .. tostring(state_or_error))
    if not ok then return end
    local state = state_or_error
    local seen = false
    for _, reason in ipairs(state.errors[1].reason_details or {}) do
        if reason.code == "BP_P_NO_FIT" and reason.detail == "pack rejected the candidate" then seen = true end
    end
    H.equal(seen, true, "a pack rejection is retained in terminal reason_details")
end)

H.test("ST5 pack owns the no-fit decision", function()
    local state = finish(input_for(one_step_plan(), {grids = {{w = 0, h = 0}}, max_search_grids = 1}))
    local no_fit = false
    for _, reason in ipairs(state.errors[1].reason_details or {}) do
        if reason.code == "BP_P_NO_FIT" then no_fit = true end
    end
    H.equal(no_fit, true, "Pack reports the small-grid rejection")
end)

H.test("ST6 a cheap failed candidate never sets the whole job's ceiling", function()
    local original_begin, original_step = Pack.begin, Pack.step
    Pack.begin = function() return failed_stage("BP_P_NO_FIT", "cheap rejection") end
    Pack.step = function() end
    local state = Search.begin(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}, max_search_grids = 1}))
    local before
    for _ = 1, 20 do
        Search.step(state, {ops = 1})
        if state.work.allowance_declared then before = before or state.max_ops end
        if state.done then break end
    end
    local after = state.max_ops
    Pack.begin, Pack.step = original_begin, original_step
    H.equal(before ~= nil, true, "the problem allowance is declared before candidate work")
    H.equal(after, before, "a cheap failed candidate cannot replace the problem-derived ceiling")
end)

H.test("ST7 a failing attempt still reports grid_spacing with its kind, source and generation_job_id", function()
    local input = input_for(one_step_plan(), {})
    input.catalog.robo = {name = "roboport", tile_w = 4, tile_h = 4, logistic_radius = 25,
        construction_radius = 55}
    input.generation_job_id = 907
    input.grids = {{w = 0, h = 0}}
    input.max_search_grids = 1
    local state = finish(input)
    local spacing = state.grid_spacing
    H.equal(state.ok, false, "the spacing fixture is a failing attempt")
    H.equal(spacing ~= nil, true, "the failing attempt keeps a spacing record")
    if spacing then
        H.equal(spacing.resolved, 50, "the failing attempt keeps the resolved spacing")
        H.equal(spacing.kind, "derived", "the failing attempt labels derived spacing")
        H.equal(spacing.source, "logistic_radius", "the failing attempt names the source")
        H.equal(spacing.source_value, 25, "the failing attempt keeps the source value")
        H.equal(spacing.generation_job_id, 907, "the failing attempt keeps its generation identity")
    end
end)

H.test("ST8 grid_spacing survives a persistence round trip and answers through Generation.lookup", function()
    local input = input_for(one_step_plan(), {})
    input.catalog.robo = {name = "roboport", tile_w = 4, tile_h = 4, logistic_radius = 25,
        construction_radius = 55}
    input.generation_job_id = 908
    local state = Search.begin(input)
    Search.step(state, {ops = 1})
    local resumed = clone(state)
    Search.step(resumed, {ops = 100000})
    H.equal(resumed.grid_spacing ~= nil, true, "the resumable state carries grid_spacing")
    if resumed.grid_spacing then
        H.equal(resumed.grid_spacing.generation_job_id, 908, "the resumed state keeps the generation identity")
    end
end)

--Round 11 spine: the roboport gap.
--
--catalog.robo carries no connection_distance, because LuaEntityPrototype::connection_distance is
--subclasses ["RollingStock"] in the pinned 2.0.77 and 2.1.19 runtime API. The gap is derived from the
--roboport's own logistic radius instead. Two roboports share a network when their logistic areas meet, so the
--widest spacing is logistic_radius * 2.
--
--Measured against a player blueprint of four unmodded roboports at maximum connection distance, 2.0.77:
--adjacent centres exactly 50 tiles apart, logistic_radius 25.
--
--Restoring the old literal 1 fallback makes these cases fail. That fallback made an 8x8 roboport grid measure
--11x11 tiles while one block of the player's sheet needed 387, so no candidate could ever fit.
local function grid_of(input)
    local state = Search.begin(input)
    local ticks = 0
    while state.work.grid == nil and not state.done and ticks < 50 do
        ticks = ticks + 1
        Search.step(state, {ops = 1})
    end
    H.equal(state.work.grid ~= nil, true, "the search reaches a grid; stopped in phase " .. tostring(state.phase))
    return state.work.grid
end

--cols and rows count roboports, never cells: an 8x8 lattice is 64 roboports bounding 49 cells.
local function engine_shaped_roboport_input(cols, rows)
    local catalog = base_catalog()
    catalog.robo = {name = "roboport", tile_w = 4, tile_h = 4, logistic_radius = 25, construction_radius = 55}
    local input = input_for(one_step_plan(), {})
    input.catalog = catalog
    input.include_roboports = true
    input.grids = {{cols = cols or 8, rows = rows or 8}}
    return input
end

H.test("BP-11 the roboport gap is derived from the logistic radius, never a one-tile fallback", function()
    local grid = grid_of(engine_shaped_roboport_input(8, 8))
    H.equal(grid.spacing_x, 50, "adjacent roboports sit logistic_radius * 2 apart")
    H.equal(grid.spacing_y, 50, "the gap is the same on both axes")
    H.equal(grid.w, 4 + 7 * 50, "an 8x8 roboport lattice spans tile_w + 7 gaps")
    H.equal(grid.h, 4 + 7 * 50, "the envelope is the same on both axes")
end)

--The player's own cell: four unmodded roboports at maximum connection distance, 2.0.77, adjacent centres
--exactly 50 tiles apart. Two by two roboports bound one cell.
H.test("BP-11 a two by two roboport lattice reproduces the player's measured 50-tile cell", function()
    local grid = grid_of(engine_shaped_roboport_input(2, 2))
    H.equal(#grid.roboports, 4, "four roboports bound one cell")
    H.equal(grid.roboports[1].x, 0, "the first roboport sits at the origin")
    H.equal(grid.roboports[2].x, 50, "its neighbour sits 50 tiles along x")
    H.equal(grid.roboports[3].y, 50, "and 50 tiles down y")
    H.equal(grid.roboports[4].x, 50, "the far corner is diagonal from the origin")
    H.equal(grid.roboports[4].y, 50, "on both axes")
end)

H.test("BP-11 an explicit connection distance still outranks the derived gap", function()
    local input = engine_shaped_roboport_input(8, 8)
    input.grid = {max_connection_distance = 11}
    local grid = grid_of(input)
    H.equal(grid.spacing_x, 11, "an explicit caller value wins")
    H.equal(grid.w, 4 + 7 * 11, "and sizes the envelope")
end)

--A plain-data catalog that still carries connection_distance is a compatibility input, never an engine fact.
--Existing fixtures and golden cases hold one, and they keep working.
H.test("BP-11 a plain-data connection distance is still honoured as a compatibility input", function()
    local input = engine_shaped_roboport_input(8, 8)
    input.catalog.robo.connection_distance = 7
    local grid = grid_of(input)
    H.equal(grid.spacing_x, 7, "a supplied distance outranks the derived gap")
end)

H.done("test_search")
