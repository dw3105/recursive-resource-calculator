-- LP1 fails on base code: bury leaves a dead-end plain pipe after underground pairing.
local H = require "tests.harness"
local PipeRuns = require "logic.bp.pipe_runs"

local function work(with_demands)
    local w = {segments = {}, entities = {}, bindings = {}, segments_by_cell = {}, port_cells = {},
        pipe = {underground_max_distance = 10}}
    if with_demands then w.demands = {{source = "src", sink = "dst"}} end
    local function add(x, y, id, kind)
        local seg = {segment_id = id, kind = "pipe", flow_id = "fluid/molten-iron"}
        w.segments[#w.segments + 1] = seg; w.segments_by_cell[x .. ":" .. y] = seg
        w.entities[#w.entities + 1] = {segment_id = id, name = "pipe", position = {x=x+0.5,y=y+0.5}}
        return seg
    end
    -- The end tile is a degree-one spur. Source/sink terminals and a reserved port are protected.
    add(0, 0, "source")
    add(1, 0, "run")
    add(2, 0, "stub")
    add(1, 1, "sink")
    w.endpoint_by_id = {source = true, sink = true}
    w.port_cells["1:1"] = {_port_owners = {p=true}}
    return w
end
local h = {
    key = function(x,y) return x .. ":" .. y end,
    coordinate_from_key = function(k) local x,y=k:match("^([^:]+):([^:]+)$"); return tonumber(x),tonumber(y) end,
    finite = function(v,d) return tonumber(v) or d end,
    next_segment_id = function() return "new-segment" end,
    next_entity_id = function() return "new-entity" end,
    entity_position = function(x,y) return {x=x+0.5,y=y+0.5} end,
    infrastructure = function() return "pipe" end,
}

H.test("LP1 route burial removes dead-end plain pipes and preserves endpoints and port cells", function()
    local w = work(true)
    PipeRuns.bury(w, h)
    H.equal(w.segments_by_cell["2:0"], nil, "dead-end stub removed")
    H.equal(w.segments_by_cell["0:0"] ~= nil, true, "source endpoint retained")
    H.equal(w.segments_by_cell["1:1"] ~= nil, true, "port tile retained")
end)
H.test("LP2 synthetic work without demands is unchanged", function()
    local w = work(false); local n = #w.segments
    PipeRuns.bury(w, h)
    H.equal(#w.segments, n, "synthetic segments unchanged")
    H.equal(w.segments_by_cell["2:0"] ~= nil, true, "stub retained")
end)
H.done("test_pipe_leaf_prune")
