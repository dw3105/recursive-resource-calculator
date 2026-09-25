--Round 36 (red science 10/s, 2026-09-25), rules found on the player's sheet. None names a flow: each holds for any
--edge-fed flow with several sinks.
local H = require "tests.harness"

--Route's exact input for the sheet's route call 1 on current search code, frozen by
--`lua5.2 tools/capture_stage_input.lua tests/golden/cases/player-red-science-10s/prepared_input.json <out> route 1`.
local function routed_and_tidied()
    H.new_world(H.shapes()[1])
    local f = assert(io.open("tests/fixtures/route_red10s_edge_split_call1.json"))
    local root = helpers.json_to_table(f:read("*a")); f:close()
    local Route = require "logic.bp.route"
    local state = Route.begin(root)
    while not state.done do Route.step(state, {ops = 100000}) end
    H.equal(state.ok, true, "route finishes")
    local tidy = Route.tidy_begin(state, {})
    while not tidy.done do Route.tidy_step(tidy, {ops = 100000}) end
    return tidy.work
end

--T1: tidy lifts a path to try a cheaper one. A tile that also carries ANOTHER sink's rate is shared even when that
--sink's own path walk misses it (a one-tile branch into an underground entrance). Lifting it deleted that sink's
--allocation: with route.lua before 23af5ac the second sink of the two-sink edge flow is left with no rate.
H.test("T1 every bound sink keeps an allocation after tidy", function()
    local work = routed_and_tidied()
    local have = {}
    for _, segment in ipairs(work.segments) do
        for _, allocation in ipairs(segment.allocations or {}) do have[allocation.flow_id .. "|" .. tostring(allocation.sink)] = true end
    end
    local missing = {}
    for _, binding in ipairs(work.bindings) do
        local key = binding.flow_id .. "|" .. tostring(binding.sink)
        if not have[key] then missing[#missing + 1] = key end
    end
    table.sort(missing)
    H.equal(table.concat(missing, " "), "", "no binding lost its rate")
end)

--T3: after an attempt starves an edge flow, every edge flow with several sinks gets one terminal per sink.
H.test("T3 a marked edge flow is sized one terminal per sink", function()
    H.new_world(H.shapes()[1])
    local Search = require "logic.bp.search"
    local flow = {flow_id = "item/x", producers = {{step_id = "$external", share_per_second = 2}},
        consumers = {{step_id = "a", share_per_second = 1}, {step_id = "b", share_per_second = 1}}}
    local network = {role = "in", port = {flow_id = "item/x", role = "in"}, flow = flow}
    local plain = {work = {input = {}}}
    H.equal(Search.terminals_for_demand(plain, network).count, 1, "unmarked: one terminal feeds both sinks")
    local marked = {work = {input = {}, edge_split_flows = {["item/x"] = true}}}
    H.equal(Search.terminals_for_demand(marked, network).count, 2, "marked: one terminal per sink")
end)

H.done("test_red10s_edge_rules")
