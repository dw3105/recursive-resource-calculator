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

local function digest(value)
    local start = assert(io.open("tests/golden/generate.lua", "r")); local gen = start:read("*a"):gsub("^#![^\n]*\n", ""); start:close()
    local first = assert(gen:find("local JSON = {}", 1, true))
    local last = assert(gen:find("local input_path,", first, true))
    local JSON = assert(load(gen:sub(first, last - 1) .. "\nreturn JSON", "@json-encoder"))()
    local path = os.tmpname(); local f = assert(io.open(path, "wb")); f:write(JSON.encode(value)); f:close()
    local pipe = assert(io.popen("sha256sum " .. string.format("%q", path), "r"))
    local sha = assert(pipe:read("*l")):match("^(%w+)"); pipe:close(); os.remove(path)
    return sha
end
local fixture = read_json("tests/fixtures/r56/310/blue_bound_groups.json")
local am2 = read_json("tests/fixtures/r56/310/groups_am2.json")

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
    H.equal(second.cache_hit, true, "second call is a cache hit")
    H.equal(digest(second.result), digest(first.result), "cached output matches fresh result")
    H.equal(fresh.done, true, "fresh build completes")
    print("GS1")
end)

H.test("GS2 hoisted candidate placement preserves deterministic output", function()
    local result = finish(fixture, 2000)
    H.equal(result.done, true, "candidate build completes")
    H.equal(digest(result.result), "e1d66712b1f3b0d613a1001f88e3e886d28ab67fa9346015e48460aa5eacab0d", "candidate output equals base bytes")
    local source = assert(io.open("logic/bp/groups.lua", "r")); local code = source:read("*a"); source:close()
    H.equal(code:find("local world_boxes = {}", 1, true) ~= nil, true, "machine boxes are hoisted")
    H.equal(code:find("local pickup_dx, pickup_dy = Grid.rotate_vector", 1, true) ~= nil, true, "direction rotations are hoisted")
    print("GS2")
end)

H.test("GS3 budgeted Groups work resumes", function()
    local resumable = {}
    for k, v in pairs(fixture) do resumable[k] = v end
    resumable.ring_bump = 2
    local state = Groups.begin(resumable)
    local one_shot = finish(resumable, 2000)
    local calls = 0
    while not state.done do
        local budget = {ops = 2000}
        Groups.step(state, budget)
        H.equal(budget.ops >= 0, true, "budget never overdrawn")
        calls = calls + 1
        H.equal(calls < 100000, true, "resumes to completion")
    end
    H.equal(state.done, true, "resumed result completes")
    H.equal(digest(state.result), digest(one_shot.result), "resume preserves placements")
    print("GS3")
end)

H.test("GS4 fixture result remains stable", function()
    local blue = finish(fixture, 2000)
    local vanilla = finish(am2, 2000)
    H.equal(blue.done, true, "blue fixture result completes")
    H.equal(vanilla.done, true, "am2 fixture result completes")
    H.equal(digest(blue.result), "e1d66712b1f3b0d613a1001f88e3e886d28ab67fa9346015e48460aa5eacab0d", "blue Groups result base sha")
    H.equal(digest(vanilla.result), "6ae5b0071bad533995139d9789273014c7ab6ace5f254c0c888af3e945926b0d", "groups am2 result base sha")
    print("GS4")
end)

H.done("test_groups_slices")
