--PP1 fails on base code: PipeRuns has no redundant plain-pipe pruning pass.
local H = require "tests.harness"
local PipeRuns = require "logic.bp.pipe_runs"
local Grid = require "logic.bp.grid"

print("PP1 pipe prune regression cases")

local function make_work()
    return {segments = {}, entities = {}, bindings = {}, segments_by_cell = {}, port_cells = {}}
end

local function add(work, x, y, opts)
    opts = opts or {}
    local k, id = tostring(x) .. ":" .. tostring(y), "seg:" .. x .. ":" .. y
    local segment = {segment_id = id, kind = "pipe", flow_id = opts.flow or "fluid/a"}
    if opts.underground then
        segment.underground = true
        segment.underground_entry_key = opts.entry
        segment.underground_exit_key = opts.exit
    end
    work.segments[#work.segments + 1] = segment
    work.segments_by_cell[k] = segment
    if opts.entity then
        local entity = {segment_id = id, position = {x = x + 0.5, y = y + 0.5}, direction = opts.direction or Grid.EAST}
        work.entities[#work.entities + 1] = entity
    end
    return segment
end

local function helpers()
    return {
        key = function(x, y) return tostring(x) .. ":" .. tostring(y) end,
        coordinate_from_key = function(k)
            local x, y = k:match("^([^:]+):([^:]+)$")
            return tonumber(x), tonumber(y)
        end,
    }
end

local function at(work, x, y) return work.segments_by_cell[x .. ":" .. y] end

H.test("PP1 blue reroute square drops only its redundant corner", function()
    local work = make_work()
    for _, p in ipairs({{42,11},{43,11},{44,11},{41,12},{42,12},{43,12},{43,13}}) do add(work, p[1], p[2]) end
    H.equal(PipeRuns.prune_redundant(work, helpers()), 1, "one tile removed")
    H.equal(at(work, 42, 11), nil, "redundant corner gone")
    H.equal(#work.segments, 6, "other pipes remain")
end)

H.test("PP2 straight line is retained", function()
    local work = make_work()
    for x = 1, 5 do add(work, x, 0) end
    H.equal(PipeRuns.prune_redundant(work, helpers()), 0, "nothing removed")
    H.equal(#work.segments, 5, "line remains")
end)

H.test("PP3 a port corner is never pruned", function()
    local work = make_work()
    for _, p in ipairs({{0,0},{1,0},{1,1},{0,1}}) do add(work, p[1], p[2]) end
    work.port_cells["0:0"] = {_port_owners = {port = true}}
    H.equal(PipeRuns.prune_redundant(work, helpers()), 1, "other redundant corner can be pruned")
    H.equal(at(work, 0, 0) ~= nil, true, "port corner remains")
end)

H.test("PP4 a pipe beside a closed underground side is not linked there", function()
    local work = make_work()
    local ground = add(work, 0, 0, {underground = true, entry = "0:0", exit = "4:0", entity = true, direction = Grid.EAST})
    local far = add(work, 4, 0, {underground = true, entry = "0:0", exit = "4:0", entity = true, direction = Grid.WEST})
    work.segments_by_cell["4:0"] = far
    add(work, 0, 1)
    H.equal(PipeRuns.prune_redundant(work, helpers()), 0, "closed side does not create redundant link")
    H.equal(at(work, 0, 1) ~= nil, true, "adjacent pipe remains")
    H.equal(ground.underground, true, "underground endpoint remains")
end)

H.test("PP5 removed tile bindings move to a surviving segment", function()
    local work = make_work()
    for _, p in ipairs({{0,0},{1,0},{1,1},{0,1}}) do add(work, p[1], p[2]) end
    work.bindings[1] = {segment_id = at(work, 0, 0).segment_id}
    H.equal(PipeRuns.prune_redundant(work, helpers()), 1, "one corner removed")
    H.equal(work.bindings[1].segment_id, at(work, 1, 0).segment_id, "binding moved to first neighbour")
end)

H.done("test_pipe_prune")
