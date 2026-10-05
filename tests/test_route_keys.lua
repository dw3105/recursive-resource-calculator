-- KY1, KY2 and KY4 fail on round-46-base: repeated vector allocations, 5.04 KB/step, and full entity scans.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"
local PipeRuns = require "logic.bp.pipe_runs"

H.test("KY1 dir_vector reuses its constant tables", function()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local checksum = 0
    local dirs = {Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}
    for i = 1, 10000 do
        local x, y = Grid.dir_vector(dirs[(i - 1) % 4 + 1])
        checksum = checksum + x + y
    end
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    H.equal(checksum, 0, "all direction vectors were read")
    H.equal(growth <= 16, true, "garbage growth KB: " .. tostring(growth))
    print("KY1")
end)

H.test("KY2 and KY3 checkpoint garbage and canonical output", function()
    local command = "lua5.2 -e 'arg={[0]=\"tools/ckpt.lua\",\"resume\",\"tests/fixtures/route_snaps/green_tidy.lua.gz\",\"--patch\",\"docs/tasks/r46_probes/p_garbage.lua\"}; dofile(\"tools/ckpt.lua\"); local g=_G.__garbage; if g then io.write(string.format(\"GARBAGE steps=%d kb_per_step=%.3f\\n\",g.n,g.kb/g.n)) end' 2>&1"
    local pipe = assert(io.popen(command, "r"))
    local output = pipe:read("*a")
    local ok = pipe:close()
    H.equal(ok, true, "checkpoint resume exited successfully: " .. output)
    local kb = tonumber(output:match("kb_per_step=([%d%.]+)"))
    H.equal(kb ~= nil and kb <= 1.4, true, "garbage KB/step: " .. tostring(kb))
    H.equal(output:match("sha=([0-9a-f]+)"), "fa1856a9c0dd345d3bbd5c6c15c1bcc56ff84b6d2f2b44b14b6eef169a607444", "canonical sha")
    H.equal((tonumber(output:match("ticks=(%d+)")) or math.huge) <= 1444, true, "checkpoint ticks never above base 1444")
    H.equal(output:match("entities=(%d+)") or output:match("entities: (%d+)"), "299", "checkpoint entities")
    print("KY2")
    print("KY3")
end)

local function helpers()
    return {
        key = function(x, y) return tostring(x) .. ":" .. tostring(y) end,
        coordinate_from_key = function(k)
            local x, y = k:match("^([^:]+):([^:]+)$")
            return tonumber(x), tonumber(y)
        end,
    }
end

H.test("KY4 prune uses tile lookup and preserves removed set", function()
    local work = {segments = {}, entities = {}, bindings = {}, segments_by_cell = {}, port_cells = {}}
    local function add(x, y, with_entity)
        local id, key = "seg:" .. x .. ":" .. y, tostring(x) .. ":" .. tostring(y)
        local segment = {segment_id = id, kind = "pipe", flow_id = "fluid/a", underground = with_entity == "ug" or nil}
        work.segments[#work.segments + 1] = segment
        work.segments_by_cell[key] = segment
        if with_entity then
            work.entities[#work.entities + 1] = {segment_id = id, position = {x = x + 0.5, y = y + 0.5}, direction = Grid.EAST}
        end
    end
    for _, p in ipairs({{42,11},{43,11},{44,11},{41,12},{42,12},{43,12},{43,13}}) do add(p[1], p[2], true) end
    for i = 1, 50 do add(100 + i * 3, 100, true) end
    --Underground pipes make opens_to read the entity on the tile (base scanned all 57 entities per call).
    add(45, 11, "ug")
    PipeRuns._count_visits, PipeRuns._visits = true, 0
    local removed = PipeRuns.prune_redundant(work, helpers())
    PipeRuns._count_visits = false
    H.equal(removed, 1, "same single redundant corner as the baseline fixture shape")
    H.equal(work.segments_by_cell["42:11"], nil, "baseline removed coordinate")
    H.equal((PipeRuns._visits or 0) >= 1, true, "opens_to looked up an underground entity through the tile index")
    H.equal(PipeRuns._visits <= 4, true, "max candidate entity visits for one opens_to call")
    print("KY4")
end)

H.test("KY5 coordinate keys preserve legacy strings", function()
    for _, p in ipairs({{-9001, -77}, {0, 0}, {123456789, 987654321}}) do
        H.equal(Route._coordinate_key(p[1], p[2]), tostring(p[1]) .. ":" .. tostring(p[2]), "coordinate key")
    end
    print("KY5")
end)

H.done("test_route_keys")
