--Retry (docs/contracts/pipeline_r29.md C1, C9): an invalid layout starts again from groups with every ring one wider,
--at most twice; a pack that does not fit tries the next grid in the same attempt.
local H = require "tests.harness"
local Search = require "logic.bp.search"
local D = require "tests.fixtures.search_doubles"
local Pack = require "logic.bp.pack"
--SR1-SR3 pin the MaxRects contract; SR4-SR5 pin layered pack first, then that same contract from bump 0.
local function with_layered(on, f) local was = Pack.layered; Pack.layered = on
    local ok, a, b = pcall(f); Pack.layered = was; if not ok then error(a, 0) end; return a, b end

local function bumps(list) local r = {} for i, v in ipairs(list) do r[i] = v.ring_bump or 0 end return r end

H.test("SR1 validate fails once: second attempt at ring_bump 1 is delivered", function()
    local state, log = with_layered(false, function()
        return D.run({validate_fails = 1}, function() return D.finish(Search, Search.begin(D.input())) end) end)
    H.equal(state.ok, true, "delivered")
    H.deep_equal(bumps(log.groups), {0, 1}, "groups saw bump 0 then 1")
    H.deep_equal(bumps(log.validate), {0, 1}, "validate saw the same bump")
end)
H.test("SR2 validate always fails: three attempts, bump 0,1,2, then BP_FAIL_NO_LAYOUT with every rejection", function()
    local state, log = with_layered(false, function()
        return D.run({validate_fails = -1}, function() return D.finish(Search, Search.begin(D.input())) end) end)
    H.equal(state.ok, false, "refused")
    H.equal(state.errors[1].code, "BP_FAIL_NO_LAYOUT", "no layout")
    H.deep_equal(bumps(log.groups), {0, 1, 2}, "three attempts")
    H.equal(#log.validate, 3, "validated three times, no fourth")
    local n = 0
    for _, d in ipairs(state.errors[1].reason_details or {}) do n = n + 1 end
    H.equal(n > 0, true, "rejections are reported")
end)
H.test("SR3 pack no-fit grows the grid inside the same attempt", function()
    local state, log = D.run({pack_no_fit = 1}, function() return D.finish(Search, Search.begin(D.input())) end)
    H.equal(state.ok, true, "delivered on the second grid")
    H.equal(#log.pack, 2, "packed twice")
    H.equal(log.pack[2].area.w > log.pack[1].area.w, true, "second grid is larger")
    H.deep_equal(bumps(log.groups), {0, 0}, "grid growth is not a retry")
end)
H.test("SR4 layered first: its rejected layout restarts with MaxRects at bump 0, which is delivered", function()
    local state, log = with_layered(true, function()
        return D.run({validate_fails = 1}, function() return D.finish(Search, Search.begin(D.input())) end) end)
    H.equal(state.ok, true, "delivered")
    H.deep_equal(bumps(log.groups), {0, 0}, "layered at bump 0, then MaxRects at bump 0")
end)
H.test("SR5 layered first, validate always fails: layered once, then MaxRects bump 0,1,2, then BP_FAIL_NO_LAYOUT", function()
    local state, log = with_layered(true, function()
        return D.run({validate_fails = -1}, function() return D.finish(Search, Search.begin(D.input())) end) end)
    H.equal(state.ok, false, "refused")
    H.equal(state.errors[1].code, "BP_FAIL_NO_LAYOUT", "no layout")
    H.deep_equal(bumps(log.groups), {0, 0, 1, 2}, "one layered try, then three MaxRects attempts")
    H.equal(#log.validate, 4, "validated four times, no fifth")
end)
H.done("test_search_retry")
