-- Published splitter physics: inspect blueprint entities and cross-check their trunk segments.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function input()
    return {
        grid = Grid.new(8, 6),
        catalog = {belt = {belt = "transport-belt", splitter = "splitter", items_per_second = 10,
            lane_items_per_second = 5, underground_max_distance = 0}},
        obstacles = {{x = 0, y = 2, w = 5, h = 1, owner = "wall"}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 0, y = 3, w = 1, h = 1, ports = {{
                port_id = "source-out", role = "out", kind = "item", flow_id = "item/splitters", rate_per_second = 3,
                attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST}}},
            {block_id = "straight", machines = {{step_id = "straight"}}, x = 7, y = 3, w = 1, h = 1, ports = {{
                port_id = "straight-in", role = "in", kind = "item", flow_id = "item/splitters", rate_per_second = 1,
                x = 5, y = 3, travel_dir = Grid.EAST}}},
            {block_id = "north", machines = {{step_id = "north"}}, x = 5, y = 0, w = 1, h = 1, ports = {{
                port_id = "south-in", role = "in", kind = "item", flow_id = "item/splitters", rate_per_second = 1,
                attach_dx = 0, attach_dy = 1, normal_dir = Grid.SOUTH, travel_dir = Grid.NORTH}}},
            {block_id = "far-north", machines = {{step_id = "far-north"}}, x = 6, y = 0, w = 1, h = 1, ports = {{
                port_id = "east-in", role = "in", kind = "item", flow_id = "item/splitters", rate_per_second = 1,
                attach_dx = 0, attach_dy = 1, normal_dir = Grid.SOUTH, travel_dir = Grid.NORTH}}},
        },
        flows = {{flow_id = "item/splitters", producers = {{step_id = "source", share_per_second = 3}},
            consumers = {{step_id = "straight", share_per_second = 1}, {step_id = "north", share_per_second = 1},
                {step_id = "far-north", share_per_second = 1}}}},
    }
end

local function run()
    local state, ticks = Route.begin(input()), 0
    while not state.done and ticks < 200000 do ticks = ticks + 1; Route.step(state, {ops = 100000}) end
    H.equal(state.done, true, "splitter physics route completes")
    H.equal(state.ok, true, "splitter physics route succeeds")
    return state
end

local function is_splitter(e)
    return e.splitter == true or tostring(e.name):find("splitter", 1, true) ~= nil
end

local function witness(state, e)
    local p, d = e.position, e.direction or e.dir
    local x1, y1, x2, y2
    if d == Grid.NORTH or d == Grid.SOUTH then
        x1, y1, x2, y2 = math.floor(p.x - 0.5), math.floor(p.y), math.floor(p.x + 0.5), math.floor(p.y)
    elseif d == Grid.EAST or d == Grid.WEST then
        x1, y1, x2, y2 = math.floor(p.x), math.floor(p.y - 0.5), math.floor(p.x), math.floor(p.y + 0.5)
    end
    local function key(x, y) return tostring(x) .. ":" .. tostring(y) end
    local segment = x1 and (state.work.segments_by_cell[key(x1, y1)] or state.work.segments_by_cell[key(x2, y2)])
    local dx, dy = Grid.dir_vector(d)
    local feed, feed_heading
    if segment then
        for _, tile in ipairs({{x1, y1}, {x2, y2}}) do
            for _, step in ipairs({{0, -1, Grid.NORTH}, {1, 0, Grid.EAST}, {0, 1, Grid.SOUTH}, {-1, 0, Grid.WEST}}) do
                local neighbor = state.work.segments_by_cell[key(tile[1] + step[1], tile[2] + step[2])]
                if neighbor and neighbor.kind == "belt" and neighbor.direction == step[3] then
                    feed, feed_heading = neighbor, neighbor.direction
                end
            end
        end
    end
    local covers = string.format("(%s,%s)+(%s,%s)", tostring(x1), tostring(y1), tostring(x2), tostring(y2))
    local desc = string.format("entity=%s position=(%.1f,%.1f) facing=%s covers=%s trunk_direction=%s feeding_belt_heading=%s",
        tostring(e.id), p.x, p.y, tostring(d), covers, tostring(segment and segment.direction), tostring(feed_heading))
    return {entity=e, segment=segment, x1=x1, y1=y1, x2=x2, y2=y2, dx=dx, dy=dy,
        feed=feed, feed_heading=feed_heading, desc=desc}
end

local function passes_facing(w)
    return w.segment ~= nil and (w.entity.direction or w.entity.dir) == w.segment.direction
end

for _, shape in ipairs(H.shapes()) do
    local state = run()
    local splitters = {}
    for _, e in ipairs(state.result.entities or {}) do if is_splitter(e) then splitters[#splitters + 1] = e end end

    H.test(shape .. " SP0 fixture publishes a splitter", function()
        H.equal(#splitters > 0, true, "SP0 published splitter count=" .. tostring(#splitters))
    end)
    H.test(shape .. " SP1 published splitter faces its trunk direction", function()
        H.equal(#splitters > 0, true, "SP1 requires a published splitter")
        for _, e in ipairs(splitters) do
            local w = witness(state, e)
            H.equal(w.segment ~= nil, true, "SP1 missing trunk segment; " .. w.desc)
            H.equal(e.direction or e.dir, w.segment and w.segment.direction, "SP1 " .. w.desc)
        end
    end)
    H.test(shape .. " SP2 published footprint matches facing", function()
        H.equal(#splitters > 0, true, "SP2 requires a published splitter")
        for _, e in ipairs(splitters) do
            local w, d = witness(state, e), e.direction or e.dir
            local trunk_direction = w.segment and w.segment.direction
            local message = "SP2 " .. w.desc
            if trunk_direction == Grid.NORTH or trunk_direction == Grid.SOUTH then
                H.equal(d == trunk_direction, true, message .. "; published facing follows trunk axis")
                H.equal(e.position.x % 1, 0, message .. "; north/south facing has whole x")
                H.equal(e.position.y % 1, 0.5, message .. "; north/south facing has half y")
                H.equal(w.y1, w.y2, message .. "; tiles span east-west")
                H.equal(math.abs(w.x2 - w.x1), 1, message .. "; tiles are distinct east-west neighbors")
            else
                H.equal(trunk_direction == Grid.EAST or trunk_direction == Grid.WEST, true, message .. "; trunk direction is cardinal")
                H.equal(d == trunk_direction, true, message .. "; published facing follows trunk axis")
                H.equal(e.position.x % 1, 0.5, message .. "; east/west facing has half x")
                H.equal(e.position.y % 1, 0, message .. "; east/west facing has whole y")
                H.equal(w.x1, w.x2, message .. "; tiles span north-south")
                H.equal(math.abs(w.y2 - w.y1), 1, message .. "; tiles are distinct north-south neighbors")
            end
        end
    end)
    H.test(shape .. " SP3 feeding belt enters splitter from its back", function()
        H.equal(#splitters > 0, true, "SP3 requires a published splitter")
        for _, e in ipairs(splitters) do
            local w = witness(state, e)
            H.equal(w.segment ~= nil, true, "SP3 missing trunk segment; " .. w.desc)
            H.equal(w.feed ~= nil, true, "SP3 no belt on the splitter back tile; " .. w.desc)
            H.equal(w.feed_heading, e.direction or e.dir, "SP3 side-feed check; " .. w.desc)
        end
    end)
    H.test(shape .. " SP4 trunk continues beyond splitter", function()
        H.equal(#splitters > 0, true, "SP4 requires a published splitter")
        for _, e in ipairs(splitters) do
            local w = witness(state, e)
            local front1 = state.work.segments_by_cell[tostring(w.x1 + w.dx) .. ":" .. tostring(w.y1 + w.dy)]
            local front2 = state.work.segments_by_cell[tostring(w.x2 + w.dx) .. ":" .. tostring(w.y2 + w.dy)]
            local continues = w.segment ~= nil and ((front1 and front1.kind == "belt") or (front2 and front2.kind == "belt"))
            H.equal(continues, true, "SP4 trunk has no same-segment tile beyond splitter; " .. w.desc)
        end
    end)
    H.test(shape .. " SP5 hand-built turning splitter is caught by shared facing rule", function()
        local fake = {id="negative-control-turning-splitter", splitter=true, name="splitter", direction=Grid.WEST,
            position={x=4.0,y=3.5}}
        local trunk = {segment_id="negative-control-trunk", direction=Grid.NORTH}
        local fake_state = {work={segments_by_cell={ ["3:3"]=trunk, ["4:3"]=trunk }}}
        local w = witness(fake_state, fake)
        H.equal(passes_facing(w), false, "SP5 negative control must fail shared facing rule; " .. w.desc)
    end)
end
H.done("test_route_splitter_physics")
