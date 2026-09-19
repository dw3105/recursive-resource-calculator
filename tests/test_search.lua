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
        grids = {{w = 6, h = 4, roboports = {
            {x = 0, y = 0, w = 1, h = 1},
            {x = 2, y = 2, w = 1, h = 1},
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

local function finish_with_validation_scores(input, label)
    local scores = {}
    local original_step = Validate.step
    Validate.step = function(stage, budget)
        original_step(stage, budget)
        if stage.done and stage.ok then scores[#scores + 1] = clone(stage.result.score) end
    end

    local ok, state_or_error = pcall(function()
        local state = Search.begin(input)
        local ticks = 0
        while not state.done and ticks < 600 do
            ticks = ticks + 1
            Search.step(state, {ops = 100000})
        end
        H.equal(state.done, true, label .. " finishes within the test bound; stopped in phase " .. tostring(state.phase))
        return state
    end)
    Validate.step = original_step
    if not ok then error(state_or_error) end
    return state_or_error, scores
end

local function comparison_catalog()
    local catalog = base_catalog()
    catalog.entity["wide-assembler"] = {
        name = "wide-assembler", tile_w = 2, tile_h = 1, energy_usage_w = 1,
        collision_box = box(), collision_mask = {"item-layer"},
    }
    return catalog
end

local function comparison_group(signature)
    return {signature = signature, name = "beacon", count_per_machine = 1, has_speed_module = false, modules = {}}
end

local function comparison_plan()
    return {steps = {
        {step_id = "a", machine = "assembler", machine_count = 1, power_w = 1, modules = {},
            beacon_groups = {comparison_group("group-a")}},
        {step_id = "b", machine = "wide-assembler", machine_count = 1, power_w = 1, modules = {},
            beacon_groups = {comparison_group("group-b")}},
    }, flows = {}, ports = {}}
end

local function comparison_input(orderings, grid)
    return {
        plan = comparison_plan(), catalog = comparison_catalog(), pole = pole(), include_roboports = false,
        grids = {grid or {w = 3, h = 4}}, block_orderings = clone(orderings),
    }
end

local function comparison_order(first, second)
    return {{first, second}, {second, first}}
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
        H.equal(state.errors[1].code, "BP_FAIL_NO_LAYOUT_GRID_LIMIT", "slot exhaustion reports no layout")
        H.equal(distinct_port_cells(state.work.perimeter_ports), true, "slot exhaustion never stacks ports")
        H.equal(#state.work.perimeter_ports, 1, "slot exhaustion keeps only the available perimeter slot")
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

    H.test(shape .. " BP-20 a larger grid that needs fewer beacons wins", function()
        local state = finish(input_for(shared_plan()))
        H.equal(state.ok, true, "the multi-grid search succeeds")
        H.equal(state.incumbent.score.beacon_count, 1, "the larger grid admits the one-beacon grouping")
        H.equal(state.result ~= nil, true, "the best complete candidate is serialized")
    end)

    H.test(shape .. " BP-20 the better candidate found second wins", function()
        local state, scores = finish_with_validation_scores(
            comparison_input(comparison_order("block:a", "block:b")), "second-candidate comparison search")
        H.equal(state.ok, true, "the comparison search succeeds")
        H.equal(#scores, 2, "exactly two candidates were validated")
        H.equal(Validate.compare(scores[2], scores[1]), -1, "the second candidate ranks ahead of the first")
        H.equal(Validate.compare(state.incumbent.score, scores[2]), 0,
            "the incumbent is the candidate Validate.compare ranks first")
    end)

    H.test(shape .. " BP-20 the better first candidate survives a worse follow-up", function()
        local state, scores = finish_with_validation_scores(
            comparison_input(comparison_order("block:b", "block:a")), "first-candidate comparison search")
        H.equal(state.ok, true, "the mirror comparison search succeeds")
        H.equal(#scores, 2, "exactly two candidates were validated")
        H.equal(Validate.compare(scores[1], scores[2]), -1, "the first candidate ranks ahead of the second")
        H.equal(Validate.compare(state.incumbent.score, scores[1]), 0,
            "the incumbent never changes to the worse follow-up")
    end)

    H.test(shape .. " BP-20 equal beacon counts defer to footprint area", function()
        local state, scores = finish_with_validation_scores(
            comparison_input(comparison_order("block:a", "block:b"), {w = 3, h = 5}),
            "footprint tie-break search")
        H.equal(state.ok, true, "the tie-break search succeeds")
        H.equal(#scores, 2, "two candidates were validated for the tie-break")
        H.equal(scores[1].beacon_count, scores[2].beacon_count, "the candidates tie on beacon count")
        H.equal(scores[1].footprint_area < scores[2].footprint_area, true,
            "the first candidate has the smaller footprint")
        H.equal(Validate.compare(scores[1], scores[2]), -1, "footprint area decides the beacon-count tie")
        H.equal(Validate.compare(state.incumbent.score, scores[1]), 0,
            "the incumbent keeps the smaller-footprint candidate")
    end)

    H.test(shape .. " BP-15 exhausting the search budget is not no-layout", function()
        local state = finish(input_for(one_step_plan(), {grids = {{w = 2, h = 2}}, max_ops = 1}), 100000)
        H.equal(state.ok, false, "the bounded search fails")
        H.equal(state.errors[1].code, "BP_FAIL_SEARCH_BUDGET", "budget exhaustion has the budget failure")
        H.equal(state.errors[1].code == "BP_FAIL_NO_LAYOUT_GRID_LIMIT", false,
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

H.done("test_search")
