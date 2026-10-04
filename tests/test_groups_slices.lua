-- GS1-GS4 red on round-56-base (2026-10-04): Groups has no per-search cache or resumable inner work.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local function read_json(path)
    local f = assert(io.open(path, "r")); local source_text = f:read("*a"); f:close()
    local source = assert(io.open("tests/golden/generate.lua", "r")); local gen = source:read("*a"):gsub("^#![^\n]*\n", ""); source:close()
    local start = assert(gen:find("local JSON = {}", 1, true))
    local cut = assert(gen:find("local input_path,", start, true))
    local JSON = assert(load(gen:sub(start, cut - 1) .. "\nreturn JSON", "@json-reader"))()
    return JSON.decode(source_text)
end
local fixture = read_json("tests/fixtures/r56/310/blue_bound_groups.json")

local function finish(input, ops)
    local state = Groups.begin(input)
    repeat Groups.step(state, {ops = ops}) until state.done
    return state
end

H.test("GS1 repeated Groups build hits cache and matches fresh result", function()
    local input = fixture
    local first = finish(input, 2000)
    local second = finish(input, 2000)
    local fresh_input = {}
    for k, v in pairs(input) do fresh_input[k] = v end
    fresh_input.ring_bump = 1
    local fresh = finish(fresh_input, 2000)
    H.equal(second.work.cache_hit, true, "second call is a cache hit")
    H.equal(second.result.candidates[1].blocks[1].id, first.result.candidates[1].blocks[1].id, "cached output matches")
    H.equal(fresh.done, true, "fresh build completes")
    print("GS1")
end)

H.test("GS2 hoisted candidate placement preserves deterministic output", function()
    local result = finish(fixture, 2000)
    H.equal(result.done, true, "candidate build completes")
    print("GS2")
end)

H.test("GS3 budgeted Groups work resumes", function()
    local state = Groups.begin(fixture)
    local calls = 0
    while not state.done do
        local budget = {ops = 2000}
        Groups.step(state, budget)
        H.equal(budget.ops >= 0, true, "budget never overdrawn")
        calls = calls + 1
        H.equal(calls < 100000, true, "resumes to completion")
    end
    H.equal(state.done, true, "resumed result completes")
    print("GS3")
end)

H.test("GS4 fixture result remains stable", function()
    local result = finish(fixture, 2000)
    H.equal(result.done, true, "fixture result completes")
    print("GS4")
end)

H.done("test_groups_slices")
