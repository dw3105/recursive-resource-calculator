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
    local function pipe(p, limit)
        return {valid = true, insert_fluid = function(spec)
            local amount = math.min(spec.amount, limit or spec.amount)
            p.inserted = p.inserted + amount
            return amount
        end}
    end
    local feeds = {{entity = pipe(a, 2), fluid = "water"}, {entity = pipe(b), fluid = "water"}}
    local pool = Lab.meter_new({["fluid/water"] = 133.6})
    for _ = 1, 3600 do Lab.meter_tick(pool, feeds, 4) end
    near(a.inserted + b.inserted, 8016, 1, "MT3 fluid rate")
    assert(a.inserted > 0 and b.inserted > 0, "MT3 must split across pipes in list order")
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
    assert(not ok and #problems == 2, "MT5 threshold and missing-output judgment")
    assert(table.concat(problems, "|"):find("SHORT item/a", 1, true))
    assert(not table.concat(problems, "|"):find("item/d", 1, true), "MT5 no upper cap: R=1.101 passes")
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
    local function read(path)
        local f = assert(io.open(path, "r")); local value = f:read("*a"); f:close(); return value
    end
    local function section(text, name)
        local start = assert(text:find('"' .. name .. '"%s*:%s*{'))
        local finish = assert(text:find("}", start))
        return text:sub(start, finish)
    end
    local function numeric_map(text)
        local map = {}
        for key, value in text:gmatch('"([^"]+)"%s*:%s*([%d%.eE+%-]+)') do
            map[key] = tonumber(value)
        end
        return map
    end
    local refs = numeric_map(section(read("tests/fixtures/sheets/player-red-green-science-10s.refs.json"), "inputs"))
    local ports = numeric_map(section(read("tests/fixtures/sheets/player-red-green-science-10s.ports.json"), "inputs"))
    for name, rate in pairs(refs) do assert(ports[name] and math.abs(rate - ports[name]) <= 1e-9, "MT6 input mismatch " .. name) end
    for name in pairs(ports) do assert(refs[name] ~= nil, "MT6 missing ref input " .. name) end
    print("MT6")
end
do
    local lanes = {0, 0}
    local entity = {valid = true, get_transport_line = function(lane)
        return {insert_at_back = function(stack) lanes[lane] = lanes[lane] + stack.count; return true end}
    end}
    local pool = Lab.meter_new({["item/ore"] = 1})
    run_item(pool, {{entity = entity, item = "ore"}}, 4, 3600)
    assert(lanes[1] > 0 and math.abs(lanes[1] - lanes[2]) <= 1, "MT7 lanes take turns: " .. lanes[1] .. "/" .. lanes[2])
    print("MT7")
end
do
    assert(Lab.window_ticks({["item/a"] = 10, ["item/b"] = 1}) == 12000, "MT8 window holds 200 units of slowest output")
    assert(Lab.window_ticks({["item/a"] = 10}) == 3600, "MT8 window floor 3600")
    assert(not Lab.warm_ready(nil, 0), "MT8 warm needs two samples")
    assert(not Lab.warm_ready(500, 692), "MT8 growing stock keeps warming")
    assert(Lab.warm_ready(692, 700) and Lab.warm_ready(0, 3), "MT8 flat stock ends warm-up")
    print("MT8")
end
do
    local function run(values, window_s)
        local history, stable, mean = {}, false, nil
        for _, v in ipairs(values) do
            local ok, per = Lab.settle(history, {["item/p"] = v}, {["item/p"] = v}, window_s)
            if ok then stable, mean = true, per["item/p"]; break end
        end
        return stable, mean
    end
    local stable, mean = run({1.01, 0.99, 1.00}, 200)
    assert(stable and math.abs(mean - 1) < 1e-9, "MT9 edge-cut cycle at 200 units settles")
    assert(not run({1.01, 0.99, 1.00}), "MT9 without window length the 1.5% band holds")
    assert(not run({0.97, 0.95, 0.99}, 200), "MT9 a 4% climb does not settle")
    print("MT9")
end
do
    local feeds = {{entity = belt(true).entity, item = "ore"}}
    local pool = {["item/ore"] = {rate = 1.5, credit = 13}}
    assert(#Lab.meter_backlog(pool, feeds, 4, {["item/ore"] = 21}) == 0, "MT10 a standing queue is no backlog")
    assert(#Lab.meter_backlog(pool, feeds, 4, {["item/ore"] = 4}) == 1, "MT10 credit grown 9 > 2 stacks is backlog")
    print("MT10")
end
do
    assert(not Lab.warm_ready(700, 500), "MT11 a draining pre-filled lane keeps warming")
    local function lane(items)
        local l = {items = items, line_length = 1}
        function l.get_contents()
            local by = {}
            for _, n in ipairs(l.items) do by[n] = (by[n] or 0) + 1 end
            local out = {}
            for n, c in pairs(by) do out[#out + 1] = {name = n, count = c} end
            return out
        end
        function l.get_item_count() return #l.items end
        function l.can_insert_at() return #l.items < 4 end
        function l.insert_at(_, stack) l.items[#l.items + 1] = stack.name; return true end
        return l
    end
    local inner, mixed, input = lane({"gear"}), lane({"gear", "plate"}), lane({"ore"})
    local belt = {valid = true, type = "transport-belt", get_max_transport_line_index = function() return 3 end,
        get_transport_line = function(i) return ({inner, mixed, input})[i] end}
    local added = Lab.prefill_inner({belt}, {["item/ore"] = 1}, {["item/pack"] = 1}, 4)
    assert(added == 3 and #inner.items == 4, "MT11 one-kind inner lane filled: " .. added)
    assert(#mixed.items == 2 and #input.items == 1, "MT11 mixed and input lanes untouched")
    print("MT11")
end
print("test_lab_meter 11 passed 0 failed")
