-- GS1-GS9 red on round-56-310b-base (2026-10-04): Groups cache ownership, key cost, and inner slices.
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

local function finish(input, ops, cache)
    local state = Groups.begin(input, cache)
    repeat Groups.step(state, {ops = ops}) until state.done
    return state
end

H.test("GS5 Groups without caller cache never hits", function()
    local first, second = Groups.begin(fixture), Groups.begin(fixture)
    H.equal(first.cache_hit, nil, "first uncached begin misses")
    H.equal(second.cache_hit, nil, "second uncached begin misses")
    local source = assert(io.open("logic/bp/groups.lua", "r")); local code = source:read("*a"); source:close()
    H.equal(code:find("groups_cache", 1, true), nil, "no module cache remains")
    print("GS5")
end)

H.test("GS6 key work is charged and bounded", function()
    local cache, calls, original = {}, 0, _G.tostring
    _G.tostring = function(value) calls = calls + 1; return original(value) end
    --Integrator 2026-10-04: the key is built in begin; the first step's bucket build is charged real work.
    Groups.begin(fixture, cache)
    _G.tostring = original
    H.equal(calls <= 200, true, "begin (cache key) uses at most 200 tostring calls: " .. calls)
    print("GS6")
end)

H.test("GS7 cache is plain data and survives JSON round trip", function()
    local cache = {}
    local first = finish(fixture, 4000, cache)
    local encoded = assert(io.open("tests/golden/generate.lua", "r")); local gen = encoded:read("*a"):gsub("^#![^\n]*\n", ""); encoded:close()
    local start = assert(gen:find("local JSON = {}", 1, true)); local cut = assert(gen:find("local input_path,", start, true))
    local JSON = assert(load(gen:sub(start, cut - 1) .. "\nreturn JSON", "@json-cache"))()
    local roundtrip = JSON.decode(JSON.encode(cache))
    local function plain(value, seen)
        if type(value) == "function" or type(value) == "userdata" then return false end
        if type(value) ~= "table" then return true end
        if getmetatable(value) ~= nil then return false end
        seen = seen or {}; if seen[value] then return true end; seen[value] = true
        for key, child in pairs(value) do if not plain(key, seen) or not plain(child, seen) then return false end end
        return true
    end
    H.equal(plain(cache), true, "cache contains plain data")
    H.equal(plain(roundtrip), true, "round trip contains plain data")
    local hit = Groups.begin(fixture, roundtrip)
    H.equal(hit.cache_hit, true, "round-tripped cache hits")
    H.equal(digest(hit.result), digest(first.result), "round-tripped result matches")
    print("GS7")
end)

H.test("GS8 each blue step stays below the weighted instruction limit", function()
    --Integrator 2026-10-04: measured in a clean lua5.2 process; tests.harness replaces _G.type with a Lua function
    --(+25% instructions on Groups) that the engine does not have.
    local pipe = assert(io.popen("lua5.2 tests/fixtures/r56/310/groups_tick_cost.lua tests/fixtures/r56/310/blue_bound_groups.json 4000 2>&1"))
    local out = pipe:read("*a"); pipe:close()
    local worst = tonumber(out:match("WORST (%d+)"))
    H.equal(worst ~= nil and worst <= 2440000, true, "every Groups step fits the 50 ms model: " .. tostring(worst) .. " " .. out)
    print("GS8")
end)

H.test("GS9 a bucket larger than budget still progresses", function()
    local input = {}; for key, value in pairs(fixture) do input[key] = value end
    local state = Groups.begin(input)
    local calls = 0
    while not state.done do
        local before = state.work.build and state.work.build.bucket_index or 0
        local had_build = state.work.build ~= nil
        Groups.step(state, {ops = 50})
        calls = calls + 1
        H.equal(calls < 100000, true, "small budget completes")
        H.equal((state.work.build and state.work.build.bucket_index or 0) > before
            or (not had_build and state.work.build ~= nil) or state.done,
            true, "oversized bucket makes progress")
    end
    H.equal(digest(state.result), "e1d66712b1f3b0d613a1001f88e3e886d28ab67fa9346015e48460aa5eacab0d", "small-budget result matches base")
    print("GS9")
end)

H.test("GS1 repeated Groups build hits cache and matches fresh result", function()
    local input = fixture
    local cache = {}
    local first = finish(input, 2000, cache)
    local second = finish(input, 2000, cache)
    local fresh_input = {}
    for k, v in pairs(input) do fresh_input[k] = v end
    fresh_input.ring_bump = 1
    local fresh = finish(fresh_input, 2000, {})
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

H.test("GS10 cache save and hit share the read-only input, own answer copied", function()
    local cache = {}
    local first = finish(fixture, 4000, cache)
    local saved = cache.entries[first.work.cache_key]
    H.equal(saved.work.input == fixture, true, "cache entry shares stage input (no catalog copy)")
    H.equal(saved.result ~= first.result, true, "cache entry owns its result copy")
    local hit = Groups.begin(fixture, cache)
    H.equal(hit.cache_hit, true, "second begin hits")
    H.equal(hit.work.input.catalog == fixture.catalog, true, "hit shares catalog")
    H.equal(hit.result ~= saved.result, true, "hit owns its result copy")
    H.equal(digest(hit.result), digest(first.result), "hit result equals fresh result")
    print("GS10")
end)

H.test("GS11 am2 Groups with caller cache: every step fits the 50 ms model (cache save + hand search)", function()
    --Round 56 gate 2026-10-04: base 3078466 weighted (cache copy of the stage input + per-cell member scans).
    local pipe = assert(io.popen("lua5.2 tests/fixtures/r56/310/groups_tick_cost.lua tests/fixtures/r56/310/groups_am2.json 4000 cache 2>&1"))
    local out = pipe:read("*a"); pipe:close()
    local worst = tonumber(out:match("WORST (%d+)"))
    H.equal(worst ~= nil and worst <= 2440000, true, "every am2 Groups step fits the 50 ms model: " .. tostring(worst) .. " " .. out)
    print("GS11")
end)

H.done("test_groups_slices")
