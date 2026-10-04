--PR1 fails on base code: publication burial is still a stub, so this direct work-table pass lays no pair.
local H = require "tests.harness"
local PipeRuns = require "logic.bp.pipe_runs"
local Grid = require "logic.bp.grid"

local function work_line(first_x, last_x, opts)
    opts = opts or {}
    local work = {pipe = {pipe = "fluid/pipe", underground = "fluid/pipe-ground",
            underground_max_distance = opts.reach or 10},
        segments = {}, entities = {}, bindings = {}, segments_by_cell = {}, entity_by_segment = {},
        underground_cells = {}, port_cells = {}, segment_serial = 0, entity_serial = 0}
    local function add(x, y, flow, allocation)
        local id = "seg:" .. x .. ":" .. y
        local segment = {segment_id = id, kind = "pipe", flow_id = flow or "fluid/a",
            capacity_per_second = 20, allocations = allocation and {{flow_id = flow or "fluid/a",
                sink = "port:sink", rate_per_second = 5}} or {}}
        local entity = {id = "entity:" .. x .. ":" .. y, name = "fluid/pipe",
            position = {x = x + 0.5, y = y + 0.5}, direction = Grid.EAST, segment_id = id}
        work.segments[#work.segments + 1] = segment
        work.entities[#work.entities + 1] = entity
        work.segments_by_cell[x .. ":" .. y] = segment
        work.entity_by_segment[id] = entity
        if allocation then work.bindings[#work.bindings + 1] = {segment_id = id, flow_id = flow or "fluid/a"} end
        return segment
    end
    local before = add(first_x - 1, 2)
    before.underground = true
    work.entities[#work.entities].direction = Grid.EAST
    work.entities[#work.entities].dir = Grid.EAST
    for x = first_x, last_x do add(x, 2, nil, true) end
    local after = add(last_x + 1, 2)
    after.underground = true
    work.entities[#work.entities].direction = Grid.WEST
    work.entities[#work.entities].dir = Grid.WEST
    if opts.branch_x then add(opts.branch_x, 3) end
    if opts.port_x then work.port_cells[opts.port_x .. ":2"] = {_port_owners = {port = true}} end
    return work
end

local function bury(work)
    return PipeRuns.bury(work, {
        key = function(x, y) return tostring(x) .. ":" .. tostring(y) end,
        coordinate_from_key = function(value)
            local x, y = value:match("^([^:]+):([^:]+)$")
            return tonumber(x), tonumber(y)
        end,
        next_segment_id = function(w) w.segment_serial = w.segment_serial + 1; return "new-seg:" .. w.segment_serial end,
        next_entity_id = function(w) w.entity_serial = w.entity_serial + 1; return "new-entity:" .. w.entity_serial end,
        entity_position = function(x, y) return {x = x + 0.5, y = y + 0.5} end,
        infrastructure = function() return "fluid/pipe-ground" end,
        finite = function(value, fallback) return type(value) == "number" and value or fallback end,
    })
end

local function live_at(work, x, y)
    return work.segments_by_cell[x .. ":" .. y]
end

H.test("PR1 six-tile run becomes one pair and outward ends remain", function()
    local work = work_line(3, 8)
    H.equal(bury(work), 1, "one pair laid")
    local pair = live_at(work, 3, 2)
    H.equal(pair.underground, true, "interior is underground")
    H.equal(live_at(work, 4, 2), nil, "buried middle has no surface segment")
    H.equal(live_at(work, 2, 2).underground, true, "entry connector remains underground")
    H.equal(live_at(work, 9, 2).underground, true, "exit connector remains underground")
    local input, output
    for _, entity in ipairs(work.entities) do
        if entity.segment_id == pair.segment_id then
            if entity.ug_role == "input" then input = entity else output = entity end
        end
    end
    H.equal(input.direction, Grid.WEST, "entry faces outward")
    H.equal(output.direction, Grid.EAST, "exit faces outward")
    H.equal(#work.bindings, 6, "bindings retained")
    for _, binding in ipairs(work.bindings) do H.equal(binding.segment_id, pair.segment_id, "binding moved") end
    H.equal(#pair.allocations, 1, "one allocation per flow and sink")
end)

H.test("PR2 same-flow side branch keeps its tile plain", function()
    local work = work_line(3, 8, {branch_x = 5})
    H.equal(bury(work), 1, "the clean portions can be buried")
    H.equal(live_at(work, 5, 2).underground, nil, "branch tile stays plain")
end)

H.test("PR3 port tile is excluded from a buried span", function()
    local work = work_line(3, 8, {port_x = 5})
    H.equal(bury(work), 1, "remaining clean span is buried")
    H.equal(live_at(work, 5, 2).underground, nil, "port tile stays plain")
end)

H.test("PR4 two-tile run stays unchanged", function()
    local work = work_line(1, 2)
    local before = #work.segments
    H.equal(bury(work), 0, "short run lays no pair")
    H.equal(#work.segments, before, "segment count is unchanged")
    H.equal(live_at(work, 2, 2).underground, nil, "short span stays plain")
end)

H.test("PR5 fourteen-tile run splits at reach", function()
    local work = work_line(1, 14, {reach = 10})
    H.equal(bury(work), 2, "span is split into two pairs")
    local longest = 0
    for _, segment in ipairs(work.segments) do
        if segment.underground and segment.length then longest = math.max(longest, segment.length) end
    end
    H.equal(longest <= 10, true, "no endpoint distance exceeds reach")
end)

--PR6 red on 4a301d4: gray + magenta (legalcopilot-dev 2026-09-28) buried plain pipes (8..10,88) that ran above pair
--(6,88)-(16,88), weaving pair (8,88)-(10,88) into it.
H.test("PR6 a run above an existing same-axis pipe pair is not buried", function()
    local work = work_line(3, 8)
    local outer = {segment_id = "outer", kind = "pipe", flow_id = "fluid/a", underground = true, allocations = {},
        underground_entry_x = 1, underground_entry_y = 2, underground_exit_x = 12, underground_exit_y = 2,
        underground_entry_key = "1:2", underground_exit_key = "12:2"}
    work.segments[#work.segments + 1] = outer
    work.segments_by_cell["1:2"], work.segments_by_cell["12:2"] = outer, outer
    H.equal(bury(work), 0, "no pair woven into the outer pair")
    H.equal(live_at(work, 5, 2) and live_at(work, 5, 2).underground ~= true, true)
end)

H.test("PR-COST blue publish prune: same answer at a fraction of the cost (cached answers + neighbour records)", function()
    --Round 56 gate 2026-10-04: base 5589172 weighted on blue's 1318 pipe cells (one 201 ms publish tick).
    local pipe = assert(io.popen("lua5.2 tests/fixtures/r56/309/prune_tick_cost.lua tests/fixtures/r56/309/blue_prune_work.lua.gz 2>&1"))
    local out = pipe:read("*a"); pipe:close()
    local weighted = tonumber(out:match("WEIGHTED (%d+)"))
    H.equal(out:match("REMOVED (%d+)"), "17", "same pipes removed: " .. out)
    H.equal(out:match("SHA (%x+)"), "f0cae908", "same kept segments and bindings: " .. out)
    H.equal(weighted ~= nil and weighted <= 1600000, true, "prune fits beside the rest of the publish tick: " .. tostring(weighted))
    print("PR-COST")
end)

H.done("test_pipe_runs")
