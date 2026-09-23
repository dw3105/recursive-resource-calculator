--A routed result must be publishable: no two of its physical entity boxes may overlap.
local H = require "tests.harness"

local Geometry = require "logic.bp.geometry"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local FROZEN = "tests/fixtures/routing/player_chain_first_candidate.lua"
local EPSILON = 1e-9

local function run(input, label)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done and ticks < 200000 do
        ticks = ticks + 1
        Route.step(state, {ops = 1000000})
    end
    H.equal(state.done, true, label .. " route finishes within the collision-test bound")
    H.equal(state.ok, true, label .. " route succeeds")
    return state.ok and state.result or nil
end

local function is_splitter(entity)
    return entity.splitter == true or tostring(entity.name or ""):find("splitter", 1, true) ~= nil
end

local function is_underground(entity)
    return entity.ug_role ~= nil or entity.ug_pair_id ~= nil
end

local function measured_counts(result)
    local counts = {entities = 0, belts = 0, undergrounds = 0, splitters = 0}
    for _, entity in ipairs(result.entities or {}) do
        counts.entities = counts.entities + 1
        if is_splitter(entity) then
            counts.splitters = counts.splitters + 1
        elseif is_underground(entity) then
            counts.undergrounds = counts.undergrounds + 1
        else
            counts.belts = counts.belts + 1
        end
    end
    return counts
end

local function report(label, result)
    local counts = measured_counts(result)
    print(label .. " entities=" .. tostring(counts.entities)
        .. " belts=" .. tostring(counts.belts)
        .. " undergrounds=" .. tostring(counts.undergrounds)
        .. " splitters=" .. tostring(counts.splitters))
    return counts
end

--Geometry.center is position-first and falls back to x + w/2, y + h/2. That matters here because the
--public geometry contract accepts both placed entities and planner members.
local function physical_box(entity)
    local cx, cy = Geometry.center(entity)
    local direction = entity.direction or entity.dir or Grid.NORTH
    local splitter = is_splitter(entity)
    local horizontal = direction == Grid.NORTH or direction == Grid.SOUTH
    local width, height
    if splitter then
        width, height = horizontal and 1.9 or 0.9, horizontal and 0.9 or 1.9
    else
        width, height = 0.9, 0.9
    end
    return {left = cx - width / 2, top = cy - height / 2,
        right = cx + width / 2, bottom = cy + height / 2}
end

local function overlaps(left, right)
    return left.left < right.right and right.left < left.right
        and left.top < right.bottom and right.top < left.bottom
end

local function assert_no_overlap(result, label)
    local boxes = {}
    for index, entity in ipairs(result.entities or {}) do
        boxes[index] = {entity = entity, box = physical_box(entity)}
    end
    for left = 1, #boxes do
        for right = left + 1, #boxes do
            H.equal(overlaps(boxes[left].box, boxes[right].box), false,
                label .. " has no physical overlap between " .. tostring(boxes[left].entity.id)
                    .. " and " .. tostring(boxes[right].entity.id))
        end
    end
end

local function entity_at(result, x, y)
    for _, entity in ipairs(result.entities or {}) do
        local cx, cy = Geometry.center(entity)
        if math.floor(cx) == x and math.floor(cy) == y then return entity end
    end
    return nil
end

--The shared-trunk shape from test_route_footprints, plus a second routed flow standing immediately east of the
--vertical splitter's two-tile footprint. The neighbouring flow is deliberately routed, so the test still drives
--Route rather than seeding a fake published entity.
local function splitter_neighbour_input()
    return {
        grid = Grid.new(8, 6),
        catalog = {belt = {belt = "transport-belt", splitter = "splitter", items_per_second = 10,
            lane_items_per_second = 5, underground_max_distance = 0}},
        obstacles = {{x = 0, y = 2, w = 5, h = 1, owner = "wall"}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 0, y = 3, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/splitters", rate_per_second = 3,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
            }},
            {block_id = "straight", machines = {{step_id = "straight"}}, x = 7, y = 3, w = 1, h = 1, ports = {
                {port_id = "straight-in", role = "in", kind = "item", flow_id = "item/splitters", rate_per_second = 1,
                    x = 5, y = 3, travel_dir = Grid.EAST},
            }},
            {block_id = "north", machines = {{step_id = "north"}}, x = 5, y = 0, w = 1, h = 1, ports = {
                {port_id = "south-in", role = "in", kind = "item", flow_id = "item/splitters", rate_per_second = 1,
                    attach_dx = 0, attach_dy = 1, normal_dir = Grid.SOUTH, travel_dir = Grid.NORTH},
            }},
            {block_id = "far-north", machines = {{step_id = "far-north"}}, x = 6, y = 0, w = 1, h = 1, ports = {
                {port_id = "east-in", role = "in", kind = "item", flow_id = "item/splitters", rate_per_second = 1,
                    attach_dx = 0, attach_dy = 1, normal_dir = Grid.SOUTH, travel_dir = Grid.NORTH},
            }},
            {block_id = "neighbour-sink", machines = {{step_id = "neighbour-sink"}}, x = 7, y = 0, w = 1, h = 1,
                ports = {{port_id = "neighbour-in", role = "in", kind = "item", flow_id = "item/neighbour",
                    rate_per_second = 1, x = 7, y = 1, travel_dir = Grid.NORTH}}},
        },
        perimeter_ports = {{port_id = "neighbour-source", role = "in", kind = "item", flow_id = "item/neighbour",
            rate_per_second = 1, x = 7, y = 2, travel_dir = Grid.NORTH}},
        flows = {
            {flow_id = "item/splitters", producers = {{step_id = "source", share_per_second = 3}},
                consumers = {{step_id = "straight", share_per_second = 1}, {step_id = "north", share_per_second = 1},
                    {step_id = "far-north", share_per_second = 1}}},
            {flow_id = "item/neighbour", producers = {{step_id = "$external", port_id = "neighbour-source", share_per_second = 1}},
                consumers = {{step_id = "neighbour-sink", share_per_second = 1}}},
        },
    }
end

local function underground_input()
    return {
        grid = Grid.new(8, 3),
        catalog = {belt = {belt = "transport-belt", underground = "underground-belt", items_per_second = 10,
            lane_items_per_second = 5, underground_max_distance = 5}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 0, y = 1, w = 1, h = 1, ports = {{
                port_id = "source-out", role = "out", kind = "item", flow_id = "item/underground", rate_per_second = 1,
                attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST,
                connection = {connection_type = "underground", direction = Grid.EAST, max_underground_distance = 5},
            }}},
            {block_id = "sink", machines = {{step_id = "sink"}}, x = 5, y = 1, w = 1, h = 1, ports = {{
                port_id = "sink-in", role = "in", kind = "item", flow_id = "item/underground", rate_per_second = 1,
                attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST,
                connection = {connection_type = "underground", direction = Grid.WEST, max_underground_distance = 5},
            }}},
        },
        flows = {{flow_id = "item/underground", producers = {{step_id = "source", share_per_second = 1}},
            consumers = {{step_id = "sink", share_per_second = 1}}}},
    }
end

local function is_integer(value)
    return math.abs(value - math.floor(value + 0.5)) <= EPSILON
end

local function is_half_integer(value)
    return math.abs(value - (math.floor(value) + 0.5)) <= EPSILON
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RX1 the frozen candidate publishes no colliding pair", function()
        local result = run(dofile(FROZEN), "RX1")
        if not result then return end
        local counts = report("RX1", result)
        --91 to 93 and 6 to 8 on 2026-09-22, legalcopilot-dev: one more underground PAIR, because a run that
        --meets a foreign flow head-on now dives under it instead of converting that cell into a splitter
        --that turns, which no splitter does.  Belt count and splitter count are unchanged, so this is the
        --crossing being paid for honestly and nothing else moved.
        H.equal(counts.entities, 93, "RX1 entity count")
        --85 to 84 and 0 to 1 splitter on 2026-09-22, legalcopilot-dev: a trunk may now run straight through
        --a sink's own empty port tile, so continuation reaches further and the one demand that still has to
        --leave the trunk forks.  Entity total is unchanged at 93.
        H.equal(counts.belts, 84, "RX1 belt count")
        H.equal(counts.undergrounds, 8, "RX1 underground endpoint count")
        H.equal(counts.splitters, 1, "RX1 splitter count")
        assert_no_overlap(result, "RX1")
    end)

    H.test(shape .. " RX2 a splitter beside a routed neighbouring belt has no collision", function()
        local result = run(splitter_neighbour_input(), "RX2")
        if not result then return end
        local counts = report("RX2", result)
        H.equal(counts.splitters, 1, "RX2 genuinely builds one splitter")
        H.equal(entity_at(result, 7, 2) ~= nil, true, "RX2 has the neighbouring belt on the splitter's east side")
        assert_no_overlap(result, "RX2")
    end)

    H.test(shape .. " RX3 every splitter is centred on two orthogonal tiles", function()
        local result = run(splitter_neighbour_input(), "RX3")
        if not result then return end
        local counts = report("RX3", result)
        H.equal(counts.splitters >= 1, true, "RX3 exercises a splitter")
        for _, entity in ipairs(result.entities or {}) do
            if is_splitter(entity) then
                local cx, cy = Geometry.center(entity)
                local direction = entity.direction or entity.dir or Grid.NORTH
                local side = Grid.rotate_dir(Grid.EAST, direction)
                local side_x, side_y = Grid.dir_vector(side)
                --The long physical axis is whole-tile centred; the perpendicular axis is half-tile centred.
                --This is the centre of the two tile centres, and catches the historical half-tile-east shift.
                if side_x ~= 0 then
                    H.equal(is_integer(cx), true, "RX3 horizontal splitter has an integer span-axis centre")
                    H.equal(is_half_integer(cy), true, "RX3 horizontal splitter has a half-integer other-axis centre")
                    local anchor = side_x > 0 and math.floor(cx - 0.5) or math.floor(cx + 0.5)
                    local neighbour = anchor + side_x
                    H.equal(neighbour - anchor, side_x, "RX3 horizontal splitter covers its orthogonal neighbour")
                    H.equal(math.abs(((anchor + 0.5) + (neighbour + 0.5)) / 2 - cx) <= EPSILON, true,
                        "RX3 horizontal splitter centre is the two tile centres")
                    H.equal(cy, math.floor(cy) + 0.5, "RX3 horizontal splitter covers one y tile")
                else
                    H.equal(is_half_integer(cx), true, "RX3 vertical splitter has a half-integer other-axis centre")
                    H.equal(is_integer(cy), true, "RX3 vertical splitter has an integer span-axis centre")
                    local anchor = side_y > 0 and math.floor(cy - 0.5) or math.floor(cy + 0.5)
                    local neighbour = anchor + side_y
                    H.equal(neighbour - anchor, side_y, "RX3 vertical splitter covers its orthogonal neighbour")
                    H.equal(math.abs(((anchor + 0.5) + (neighbour + 0.5)) / 2 - cy) <= EPSILON, true,
                        "RX3 vertical splitter centre is the two tile centres")
                    H.equal(cx, math.floor(cx) + 0.5, "RX3 vertical splitter covers one x tile")
                end
            end
        end
    end)

    H.test(shape .. " RX4 underground endpoints are one-tile paired entities", function()
        local result = run(underground_input(), "RX4")
        if not result then return end
        local counts = report("RX4", result)
        H.equal(counts.undergrounds, 2, "RX4 publishes one underground pair")
        local by_id = {}
        for _, entity in ipairs(result.entities or {}) do by_id[tostring(entity.id)] = entity end
        for _, entity in ipairs(result.entities or {}) do
            if is_underground(entity) then
                local cx, cy = Geometry.center(entity)
                local box = physical_box(entity)
                H.equal(is_half_integer(cx), true, "RX4 endpoint x is centred in one tile")
                H.equal(is_half_integer(cy), true, "RX4 endpoint y is centred in one tile")
                H.equal(math.abs(box.right - box.left - 0.9) <= EPSILON, true,
                    "RX4 endpoint width is one tile footprint")
                H.equal(math.abs(box.bottom - box.top - 0.9) <= EPSILON, true,
                    "RX4 endpoint height is one tile footprint")
                H.equal(box.left > math.floor(cx), true, "RX4 endpoint stays inside its tile horizontally")
                H.equal(box.right < math.floor(cx) + 1, true, "RX4 endpoint stays inside its tile horizontally")
                H.equal(box.top > math.floor(cy), true, "RX4 endpoint stays inside its tile vertically")
                H.equal(box.bottom < math.floor(cy) + 1, true, "RX4 endpoint stays inside its tile vertically")
                local partner = by_id[tostring(entity.ug_pair_id)]
                H.equal(partner ~= nil, true, "RX4 endpoint names an existing partner")
                if partner then
                    H.equal(overlaps(box, physical_box(partner)), false,
                        "RX4 endpoint does not overlap its own partner")
                end
            end
        end
    end)
end

H.done("test_route_collision")
