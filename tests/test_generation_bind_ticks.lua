--Round 56 engine sample (2026-10-04, 2.0.77): red-1s tick 9 = 245 ms, 152 ms of it the box binding probe (scratch
--surface create + 4 machine probes charged 1 op each) with plan + groups in the same tick. Each engine call now ends
--its tick and the search starts on a fresh tick.
local H = require "tests.harness"
H.new_world(H.shapes()[1])
local Generation = require "logic.bp.generation"
local BoxBinding = require "logic.bp.box_binding"

H.test("GB1 box binding: one engine call per tick, search on a fresh tick", function()
    local created, deleted, fills = 0, 0, {}
    local saved_game, saved_fill = rawget(_G, "game"), BoxBinding.fill
    _G.game = {surfaces = {}, create_surface = function() created = created + 1; return {name = "scratch"} end,
        delete_surface = function() deleted = deleted + 1 end}
    BoxBinding.fill = function(_, steps, provider)
        H.equal(provider() ~= nil, true, "a probe gets the scratch surface")
        fills[#fills + 1] = steps[1].machine .. "/" .. steps[1].recipe
    end
    local ok, err = pcall(function()
        local state = {}
        local work = {input = {catalog = {}}, plan_result = {steps = {
            {machine = "m1", recipe = "r1"}, {machine = "m1", recipe = "r1"}, {machine = "m2", recipe = "r2"}}}}
        local function call()
            local budget = {ops = 4000}
            local done = Generation._bind_step(state, work, budget)
            return done, budget.ops
        end
        local done, left = call()
        H.deep_equal({done, left, created, #fills}, {false, 0, 1, 0}, "tick 1: surface create only")
        done, left = call()
        H.deep_equal({done, left, #fills}, {false, 0, 1}, "tick 2: one probe")
        done, left = call()
        H.deep_equal({done, left, #fills, fills[2]}, {false, 0, 2, "m2/r2"}, "tick 3: seen step costs 1 op, next probe")
        done, left = call()
        H.deep_equal({done, left, deleted}, {true, 0, 1}, "tick 4: surface delete, tick spent")
        H.equal(created, 1, "surface created once")
    end)
    _G.game, BoxBinding.fill = saved_game, saved_fill
    assert(ok, err)
end)

H.test("GB2 box binding: no surface (create fails) still finishes", function()
    local saved_game, saved_fill = rawget(_G, "game"), BoxBinding.fill
    _G.game = {surfaces = {}, create_surface = function() error("no surfaces here") end}
    local calls = 0
    BoxBinding.fill = function() calls = calls + 1 end
    local ok, err = pcall(function()
        local state, done = {}, false
        local work = {input = {catalog = {}}, plan_result = {steps = {{machine = "m1", recipe = "r1"}}}}
        for _ = 1, 5 do
            if done then break end
            done = Generation._bind_step(state, work, {ops = 4000})
        end
        H.deep_equal({done, calls}, {true, 1}, "finishes in a few ticks, probe called once")
    end)
    _G.game, BoxBinding.fill = saved_game, saved_fill
    assert(ok, err)
end)

H.done("test_generation_bind_ticks")
