-- JN1-JN6 exercise the route undo journal and frozen route checkpoints. Red on base: tidy
-- checkpoints take hundreds of snapshots and append_normal_path has no journal rollback.
local H = require "tests.harness"
local Graph = require "tools.lib.graph_dump"
local Route = require "logic.bp.route"

local function capture(command)
    local p = assert(io.popen(command .. " 2>&1", "r"))
    local s = p:read("*a")
    local ok = p:close()
    H.equal(ok, true, "command succeeds: " .. command)
    return s
end
local function resume(fixture, extra)
    return capture("lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/" .. fixture .. " " .. (extra or ""))
end
local digests = {}
for line in io.lines("tests/fixtures/route_snaps/r46_digests.txt") do
    local name, sha = line:match("^([^ ]+) ok=true ticks=%d+ sha=(%w+)")
    if name then digests[name] = sha end
end
for _, fixture in ipairs({"green_tidy.lua.gz", "ins10_tidy2.lua.gz"}) do
    local out = resume(fixture)
    H.equal(out:match("sha=(%w+)"), digests[fixture], "JN1 " .. fixture .. " frozen digest")
end
local tmp = os.tmpname()
resume("ins10_tidy2.lua.gz", "--until phase=validate --save " .. tmp)
local saved = Graph.load(tmp)
os.remove(tmp)
local counters = saved.state.work.route_state.counters
    or saved.state.work.counters or saved.state.counters
H.equal(counters ~= nil and counters.route_snapshots <= 20, true, "JN2 tidy snapshots <= 20")
local restart = resume("stack1_restart27.lua.gz", "--until kind=route-restart")
H.equal(restart:match("END ok=%w+ ticks=(%d+)"), "9133", "JN3 base restart checkpoint tick")

local function clone(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}; if seen[v] then return seen[v] end
    local r = {}; seen[v] = r
    for k, x in pairs(v) do r[clone(k, seen)] = clone(x, seen) end
    return r
end
local function equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}; if seen[a] == b then return true end; seen[a] = b
    for k, v in pairs(a) do if not equal(v, b[k], seen) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local nested = {entities = {}, segments = {}, bindings = {}, segments_by_cell = {}, entity_by_segment = {},
    underground_cells = {}, splitter_blocked_cells = {}, entity_serial = 3, segment_serial = 4}
H.equal(Route._test.journal_open ~= nil and Route._test.journal_rollback ~= nil and Route._test.journal_commit ~= nil,
    true, "JN5 journal helpers exported")
local before = clone(nested)
Route._test.journal_open(nested)
Route._test.jset(nested, nested, "entity_serial", 20)
Route._test.journal_open(nested)
Route._test.jinsert(nested, nested.entities, {id = 1})
Route._test.journal_commit(nested)
Route._test.journal_rollback(nested)
H.equal(equal(nested, before), true, "JN5 inner commit is undone by outer rollback")

local f = assert(io.open("logic/bp/route.lua", "r")); local src = f:read("*a"); f:close()
H.equal(src:find("local snapshot = route_snapshot(work)", 1, true) == nil, true, "JN6 append path has no snapshot")
H.equal(src:find("jset(work", 1, true) ~= nil, true, "JN6 journal mutation helpers are used")

H.done("test_route_journal2")
