--Routing entities are validated by their physical collision boxes, not by their anchor tiles.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function run(input)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done and ticks < 200000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "route finishes within the footprint test bound")
    return state
end

--This predicate deliberately knows only the published entity name, direction and position.  It does not use any
--router occupancy table, so a result can prove that the physical rectangles really are disjoint.
local function physical_box(entity)
    local name = tostring(entity.name or "")
    local direction = entity.direction or entity.dir or Grid.NORTH
    local splitter = name:find("splitter", 1, true) ~= nil
    local horizontal = direction == Grid.NORTH or direction == Grid.SOUTH
    local width, height
    if splitter then
        width, height = horizontal and 1.9 or 0.9, horizontal and 0.9 or 1.9
    else
        width, height = 0.9, 0.9
    end
    local position = entity.position
    local cx, cy = position.x, position.y
    return {left = cx - width / 2, top = cy - height / 2, right = cx + width / 2, bottom = cy + height / 2}
end

local function overlaps(a, b)
    return a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom
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
        if math.floor(entity.position.x) == x and math.floor(entity.position.y) == y then return entity end
    end
end

local function branch_input()
    return {
        grid = Grid.new(8, 6),
        catalog = {belt = {belt = "transport-belt", splitter = "splitter", items_per_second = 10,
            lane_items_per_second = 5, underground_max_distance = 0}},
        obstacles = {{x = 0, y = 2, w = 5, h = 1, owner = "wall"}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 0, y = 3, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/branch", rate_per_second = 2,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
            }},
            {block_id = "straight", machines = {{step_id = "straight"}}, x = 7, y = 3, w = 1, h = 1, ports = {
                {port_id = "straight-in", role = "in", kind = "item", flow_id = "item/branch", rate_per_second = 1,
                    x = 5, y = 3, travel_dir = Grid.EAST},
            }},
            {block_id = "branch", machines = {{step_id = "branch"}}, x = 5, y = 0, w = 1, h = 1, ports = {
                {port_id = "branch-in", role = "in", kind = "item", flow_id = "item/branch", rate_per_second = 1,
                    attach_dx = 0, attach_dy = 1, normal_dir = Grid.SOUTH, travel_dir = Grid.NORTH},
            }},
        },
        flows = {{flow_id = "item/branch", producers = {{step_id = "source", share_per_second = 2}},
            consumers = {{step_id = "straight", share_per_second = 1}, {step_id = "branch", share_per_second = 1}}}},
    }
end

local function underground_end_input()
    local input = {
        grid = Grid.new(8, 7),
        catalog = {belt = {belt = "transport-belt", underground = "underground-belt", splitter = "splitter",
            items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 0}},
        obstacles = {{x = 0, y = 2, w = 5, h = 1, owner = "wall"}},
        blocks = {
            {block_id = "underground-source", machines = {{step_id = "underground-source"}}, x = 7, y = 5, w = 1, h = 1,
                ports = {{port_id = "underground-out", role = "out", kind = "item", flow_id = "item/shared",
                    rate_per_second = 1, x = 6, y = 5, travel_dir = Grid.NORTH,
                    connection = {connection_type = "underground", direction = Grid.NORTH, max_underground_distance = 5}}}},
            {block_id = "underground-sink", machines = {{step_id = "underground-sink"}}, x = 7, y = 2, w = 1, h = 1,
                ports = {{port_id = "underground-in", role = "in", kind = "item", flow_id = "item/shared",
                    rate_per_second = 1, x = 6, y = 3, travel_dir = Grid.SOUTH,
                    connection = {connection_type = "underground", direction = Grid.SOUTH, max_underground_distance = 5}}}},
            {block_id = "surface-source", machines = {{step_id = "surface-source"}}, x = 0, y = 3, w = 1, h = 1,
                ports = {{port_id = "surface-out", role = "out", kind = "item", flow_id = "item/shared",
                    rate_per_second = 2, attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST}}},
            {block_id = "surface-straight", machines = {{step_id = "surface-straight"}}, x = 7, y = 3, w = 1, h = 1,
                ports = {{port_id = "surface-straight-in", role = "in", kind = "item", flow_id = "item/shared",
                    rate_per_second = 1, x = 5, y = 3, travel_dir = Grid.EAST}}},
            {block_id = "surface-branch", machines = {{step_id = "surface-branch"}}, x = 5, y = 0, w = 1, h = 1,
                ports = {{port_id = "surface-branch-in", role = "in", kind = "item", flow_id = "item/shared",
                    rate_per_second = 1, attach_dx = 0, attach_dy = 1, normal_dir = Grid.SOUTH, travel_dir = Grid.NORTH}}},
        },
        flows = {{flow_id = "item/shared",
            producers = {{step_id = "underground-source", share_per_second = 1},
                {step_id = "surface-source", share_per_second = 2}},
            consumers = {{step_id = "underground-sink", share_per_second = 1},
                {step_id = "surface-straight", share_per_second = 1},
                {step_id = "surface-branch", share_per_second = 1}}}},
    }
    return input
end

local function shared_splitter_input()
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
        },
        flows = {{flow_id = "item/splitters", producers = {{step_id = "source", share_per_second = 3}},
            consumers = {{step_id = "straight", share_per_second = 1}, {step_id = "north", share_per_second = 1},
                {step_id = "far-north", share_per_second = 1}}}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RF1 a splitter claims the second tile beside an existing belt", function()
        local state = run(branch_input())
        H.equal(state.ok, true, "branch route succeeds")
        if not state.ok then return end
        local splitter
        for _, entity in ipairs(state.result.entities) do
            if entity.splitter then splitter = entity; break end
        end
        H.equal(splitter ~= nil, true, "the branch creates a splitter at the turn")
        H.equal(splitter and splitter.position.x, 6, "the splitter is centered across its two tiles")
        H.equal(entity_at(state.result, 5, 2) ~= nil, true, "the branch continues from the splitter")
        assert_no_overlap(state.result, "splitter beside belt")
    end)

    H.test(shape .. " RF2 a splitter never overlaps an underground end", function()
        local state = run(underground_end_input())
        H.equal(state.ok, true, "underground and surface routes succeed")
        if not state.ok then return end
        local underground_end
        for _, entity in ipairs(state.result.entities) do
            if entity.ug_role == "output" then underground_end = entity; break end
        end
        H.equal(underground_end ~= nil, true, "the fixture publishes an underground end")
        local splitter_count = 0
        for _, entity in ipairs(state.result.entities) do
            if entity.splitter then splitter_count = splitter_count + 1 end
        end
        H.equal(splitter_count, 0, "the blocked branch does not become a splitter")
        assert_no_overlap(state.result, "splitter beside underground end")
    end)

    H.test(shape .. " RF3 two splitters never share a covered tile", function()
        local state = run(shared_splitter_input())
        H.equal(state.ok, true, "shared splitter route succeeds")
        if not state.ok then return end
        local splitter_count = 0
        for _, entity in ipairs(state.result.entities) do
            if entity.splitter then splitter_count = splitter_count + 1 end
        end
        H.equal(splitter_count >= 1, true, "the fixture exercises a splitter")
        H.equal(splitter_count, 1, "the second branch does not create a colliding splitter")
        assert_no_overlap(state.result, "two splitter footprints")
    end)
end

H.done("test_route_footprints")
