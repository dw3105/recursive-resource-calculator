-- IW1/IW2 red on base: route tidy repeats refused options and snapshots trials that cannot start.
-- IW3 red on base: a refused binding must be retried after another binding improves the world.
-- IW4 red on base: expose and verify the pure lift predicate against lift_binding.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Graph = require "tools.lib.graph_dump"
local Grid = require "logic.bp.grid"

local function capture(command)
    local p = assert(io.popen(command .. " 2>&1", "r"))
    local out = p:read("*a")
    local ok = p:close()
    H.equal(ok, true, "subprocess succeeds: " .. command)
    return out
end
local function resume(fixture, save)
    local command = "lua5.2 tools/ckpt.lua resume tests/fixtures/route_snaps/" .. fixture
    if save then command = command .. " --until phase=validate --save " .. string.format("%q", save) end
    return capture(command)
end
local function result_fields(out)
    return out:match("ticks=(%d+).-[\r\n]"), out:match("sha=(%w+)")
end
local function saved_counters(path)
    local dump = Graph.load(path)
    return dump.state.work.counters
end

local green_save, ins_save = os.tmpname(), os.tmpname()
local green = resume("green_tidy.lua.gz", green_save)
local green_ticks, green_sha = result_fields(green)
H.equal(green_sha, "6b65a1d1c6408dc4d805159f33345d2b8b901da398ffc3ca846d2f6f6d464976", "IW1 green digest")
H.truthy(tonumber(green_ticks) and tonumber(green_ticks) <= 700, "IW1 green tidy ticks <= 700")
local gc = saved_counters(green_save)
H.truthy((gc.trial_steps or math.huge) <= 40000, "IW1 green tidy trial steps <= 40000")
os.remove(green_save)
print("IW1 green fixture meets digest, tick, and trial step limits")

local ins = resume("ins10_tidy2.lua.gz", ins_save)
local _, ins_sha = result_fields(ins)
H.equal(ins_sha, "00cee6970e7757c4fe7039f946a0bda80e6be6a866e431798b769207545b9103", "IW2 ins10 digest")
local ic = saved_counters(ins_save)
H.truthy((ic.route_snapshots or math.huge) <= 600, "IW2 tidy route snapshots <= 600")
os.remove(ins_save)
print("IW2 ins10 fixture meets digest and snapshot limit")

local retry = {improved = 0, retry_seen = {}}
local a, b = {"s1", "k1", 1}, {"s2", "k2", 1}
H.equal(Route._test.retry_binding_skipped(retry, a), false, "IW3 first retry is eligible")
H.equal(Route._test.retry_binding_skipped(retry, a), true, "IW3 duplicate retry in same world is skipped")
H.equal(Route._test.retry_binding_skipped(retry, b), false, "IW3 second binding can retry")
retry.improved = retry.improved + 1
H.equal(Route._test.retry_binding_skipped(retry, a), false, "IW3 earlier binding retries after kept reroute")
print("IW3 retry dedupe resets after improvement")

local function clone(value)
    local path = os.tmpname()
    Graph.dump(value, path)
    local copy = Graph.load(path)
    os.remove(path)
    return copy
end
local function deep_equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do if not deep_equal(v, b[k], seen) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function routed()
    return Route.begin({grid = Grid.new(10, 6), catalog = {belt = {belt = "basic-belt", underground = "basic-underground", splitter = "basic-splitter",
        items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 5}}, blocks = {
        {block_id = "p", machines = {{step_id = "p"}}, x = 7, y = 1, w = 1, h = 1, ports = {{port_id = "p-out", role = "out", kind = "item", flow_id = "f", rate_per_second = 1, attach_dx = 0, attach_dy = 1, normal_dir = Grid.NORTH, travel_dir = Grid.SOUTH}}},
        {block_id = "c", machines = {{step_id = "c"}}, x = 1, y = 2, w = 1, h = 1, ports = {{port_id = "c-in", role = "in", kind = "item", flow_id = "f", rate_per_second = 1, attach_dx = 1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.WEST}}}},
        flows = {{flow_id = "f", producers = {{step_id = "p", share_per_second = 1}}, consumers = {{step_id = "c", share_per_second = 1}}}}, tidy = false})
end
local state = routed()
while not state.done do Route.step(state, {ops = 100000}) end
local work = state.work
local binding = work.bindings[1]
local before = clone(work)
local check = Route._test.lift_check(work, binding, false)
H.equal(deep_equal(work, before), true, "IW4 lift_check leaves work unchanged")
local mutating = clone(work)
local bcopy = mutating.bindings[1]
local actual = Route._test.lift_binding(mutating, bcopy, false) ~= nil
H.equal(check, actual, "IW4 lift_check agrees for this binding")
local refusing = clone(work)
local rb = refusing.bindings[1]
for _, seg in ipairs(refusing.segments) do seg.fixed = true end
local refused_check = Route._test.lift_check(refusing, rb, false)
local refusing2 = clone(refusing)
local refused_actual = Route._test.lift_binding(refusing2, refusing2.bindings[1], false) ~= nil
H.equal(refused_check, refused_actual, "IW4 lift_check agrees for refusing binding")
H.equal(refused_check, false, "IW4 fixed route refuses lift")
print("IW4 lift check is pure and agrees on accepting and refusing cases")
H.done("test_route_improve_waste")
