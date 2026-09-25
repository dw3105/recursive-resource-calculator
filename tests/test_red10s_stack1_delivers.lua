--Round 36: red science 10/s with hands at the speed a force with no stack research gets (fast inserter 2.31/s;
--tests/golden/cases/player-red-science-10s-stack1). The gear foundry then needs four output hands side by side.
--Two route rules make it build, and this test fails without either one:
--  * an output-hand demand with no path gets one restart with any source heading (route.lua fail_demand);
--  * no side-fed underground entrance anywhere (route.lua crossing_targets): the validator refuses a side-fed
--    entrance whose feeding lane lands on the blocked half, and a map-edge belt carries both lanes.
local H = require "tests.harness"

H.test("S10 red science 10/s at stack-1 hand speed delivers a blueprint", function()
    local out = os.tmpname()
    os.execute("lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-10s-stack1/prepared_input.json --output " .. out .. " >/dev/null 2>&1")
    local f = io.open(out); local text = f and f:read("*a") or ""; if f then f:close() end
    os.remove(out)
    H.equal(text:find('"ok":%s*true') ~= nil, true, "generate returns ok=true")
end)

H.done("test_red10s_stack1_delivers")
