-- Regression tests for metered sheet feeds and refs. Each case fails on base code. 2026-10-05.
package.path = "./?.lua;" .. package.path
local Lab = require "tests.game.lib.lab"

local function near(actual, expected, tolerance, message)
    assert(math.abs(actual - expected) <= tolerance, message .. ": " .. tostring(actual))
end
local function belt(refuse)
    local b = {inserted = 0, refuse = refuse}
    b.entity = {valid = true, get_transport_line = function()
        return {insert_at_back = function(stack)
            if b.refuse then return false end
            b.inserted = b.inserted + stack.count
            return true
        end}
    end}
    return b
end
local function run_item(pool, feeds, stack, ticks)
    for _ = 1, ticks do Lab.meter_tick(pool, feeds, stack) end
end

do
    local f = belt(false)
    local feeds = {{entity = f.entity, item = "ore"}}
    local pool = Lab.meter_new({["item/ore"] = 7.5})
    run_item(pool, feeds, 4, 3600)
    near(f.inserted, 450, 4, "MT1 item rate")
    print("MT1")
end
do
    local first, second = belt(true), belt(false)
    local feeds = {{entity = first.entity, item = "ore"}, {entity = second.entity, item = "ore"}}
    local pool = Lab.meter_new({["item/ore"] = 7.5})
    run_item(pool, feeds, 4, 3600)
    near(first.inserted + second.inserted, 450, 4, "MT2 refused feed")
    print("MT2")
end
do
    local a, b = {inserted = 0}, {inserted = 0}
    local function pipe(p)
        return {valid = true, insert_fluid = function(spec) p.inserted = p.inserted + spec.amount; return spec.amount end}
    end
    local feeds = {{entity = pipe(a), fluid = "water"}, {entity = pipe(b), fluid = "water"}}
    local pool = Lab.meter_new({["fluid/water"] = 133.6})
    for _ = 1, 3600 do Lab.meter_tick(pool, feeds, 4) end
    near(a.inserted + b.inserted, 8016, 1, "MT3 fluid rate")
    assert(a.inserted > 0 and b.inserted == 0, "MT3 must use pipes in list order")
    print("MT3")
end
do
    local blocked = belt(true)
    local feeds = {{entity = blocked.entity, item = "ore"}}
    local pool = Lab.meter_new({["item/ore"] = 60})
    for _ = 1, 20 do Lab.meter_tick(pool, feeds, 4) end
    assert(#Lab.meter_backlog(pool, feeds, 4) == 1, "MT4 backlog should fire")
    local clear = Lab.meter_new({["item/ore"] = 1})
    Lab.meter_tick(clear, feeds, 4)
    assert(#Lab.meter_backlog(clear, feeds, 4) == 0, "MT4 backlog should stay silent")
    print("MT4")
end
do
    local ok, problems, lines = Lab.judge({["item/a"] = 0.979, ["item/b"] = 0.98, ["item/c"] = 1.1, ["item/d"] = 1.101},
        { ["item/a"] = 1, ["item/b"] = 1, ["item/c"] = 1, ["item/d"] = 1, ["item/missing"] = 1 })
    assert(not ok and #problems == 3, "MT5 threshold and missing-output judgment")
    assert(table.concat(problems, "|"):find("SHORT item/a", 1, true))
    assert(table.concat(problems, "|"):find("OVER item/d", 1, true))
    assert(table.concat(problems, "|"):find("SHORT item/missing", 1, true))
    assert(#lines == 5)
    local pass = Lab.judge({["item/b"] = 0.98, ["item/c"] = 1.1}, { ["item/b"] = 1, ["item/c"] = 1 })
    assert(pass, "MT5 inclusive threshold boundary")
    print("MT5")
end
do
    local cases = {"player-am2-chain-repaired", "player-blue-science-10s", "player-green-science-1s", "player-inserter-10s",
        "player-inserter-10s-bulk", "player-inserter-10s-stack1", "player-red-green-science-10s", "player-red-science-10s",
        "player-red-science-10s-bulk", "player-red-science-10s-stack1", "player-red-science-1s", "player-red-science-1s-bulk",
        "player-red-science-1s-foundry", "vanilla-2.1-red-science-1s", "vanilla-2.1-green-science-1s"}
    for _, case in ipairs(cases) do
        local f = assert(io.open("tests/fixtures/sheets/" .. case .. ".refs.json", "r"), "missing refs " .. case)
        f:close()
    end
    local p = io.open("tests/fixtures/sheets/player-magenta-science-10s.refs.json", "r")
    assert(not p, "magenta must remain without refs")
    print("MT6")
end
