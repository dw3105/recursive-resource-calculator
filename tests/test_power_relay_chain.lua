--PR1-PR4 red on round-52-wave2-base (2026-09-30): power needs a shortest relay chain.
local H = require "tests.harness"
local Power = require "logic.bp.power"
local graph_dump = require "tools.lib.graph_dump"

local function run(state, ops)
    local ticks, worst = 0, 0
    while not state.done and ticks < 2000000 do
        local started = os.clock()
        Power.step(state, {ops = ops})
        worst = math.max(worst, os.clock() - started)
        ticks = ticks + 1
    end
    H.equal(state.done, true, "relay fixture terminates within its bound")
    H.equal(state.result ~= nil, true, "relay fixture publishes")
    return state.result, worst, state
end

local function code(result, wanted)
    for _, err in ipairs(result.errors or {}) do if err.code == wanted then return err end end
end

local function frozen(path, ops)
    local state = graph_dump.load(path)
    local original_poles = #state._work.selected
    local result, worst, final_state = run(state, ops)
    return result, worst, final_state, original_poles
end

H.test("PR1 red-science drawn fixture connects by relay chain", function()
    local result, _, state, original_poles = frozen("tests/fixtures/power_r10s_drawn_state.lua.gz", 2000)
    H.equal(state.ok, true, "red-science power succeeds")
    H.equal(result.components, 1, "red-science poles form one component")
    H.equal(code(result, "BP_PW_DISCONNECTED"), nil, "red-science has no disconnected error")
    print("PR1 relays added: " .. tostring(result.pole_count - original_poles))
end)

H.test("PR2 stack1 drawn fixture connects by relay chain", function()
    local result, _, state, original_poles = frozen("tests/fixtures/power_s1_drawn_state.lua.gz", 2000)
    H.equal(state.ok, true, "stack1 power succeeds")
    H.equal(result.components, 1, "stack1 poles form one component")
    H.equal(code(result, "BP_PW_DISCONNECTED"), nil, "stack1 has no disconnected error")
    print("PR2 relays added: " .. tostring(result.pole_count - original_poles))
end)

local function pole(name, reach)
    return {name = name, quality = "normal", tile_w = 1, tile_h = 1,
        supply_w = 0.5, supply_h = 0.5, wire_reach = reach, max_count = 1}
end

local function tiny(w, h, blockers)
    local occupied = {}
    for _, r in ipairs(blockers or {}) do occupied[#occupied + 1] = {rect = r} end
    return {
        grid_w = w, grid_h = h,
        consumers = {{id = "left", rect = {x = 0, y = 0, w = 1, h = 1}},
            {id = "right", rect = {x = w - 1, y = 0, w = 1, h = 1}}},
        occupied = occupied,
        poles = {pole("short-left", 4.5), pole("short-right", 4.5)},
        limits = {max_poles = 4},
    }
end

H.test("PR3 detour connects in two relays and impossible grid stays bounded", function()
    local detour = tiny(11, 4, {{x = 3, y = 0, w = 3, h = 2}})
    detour.poles[1].fixed_x, detour.poles[1].fixed_y = 0, 0
    detour.poles[2].fixed_x, detour.poles[2].fixed_y = 10, 0
    local result = run(Power.begin(detour), 1)
    H.equal(result.components, 1, "detour joins both poles")
    H.equal(result.pole_count, 4, "detour uses exactly two relay poles")

    local blocked = tiny(11, 2, {{x = 1, y = 0, w = 9, h = 2}})
    blocked.poles[1].fixed_x, blocked.poles[1].fixed_y = 0, 0
    blocked.poles[2].fixed_x, blocked.poles[2].fixed_y = 10, 0
    blocked.limits.max_relay_checks = 256
    local no_path = run(Power.begin(blocked), 1)
    H.equal(no_path.components > 1, true, "wall with no path stays disconnected")
    H.equal(code(no_path, "BP_PW_DISCONNECTED") ~= nil, true, "impossible grid reports disconnection")
    print("PR3 passed")
end)

H.test("PR4 one-op slices match and relay chain steps stay within 16 ms", function()
    local sliced = frozen("tests/fixtures/power_r10s_drawn_state.lua.gz", 1)
    local full_state = graph_dump.load("tests/fixtures/power_r10s_drawn_state.lua.gz")
    local whole = run(full_state, 2000)
    H.deep_equal(sliced.entities, whole.entities, "one-op slicing preserves selected poles")
    --Integrator 2026-09-30: only the relay chain's own steps are bound here. The pre-existing candidate phases run
    --30-43 ms per 2000-op step on this fixture (legalcopilot-dev, loaded host) before any chain work: that shared
    --worst tick is its own round (player ruling Q7). The lane's global 200-op cap per Power.step hid it by slowing
    --every sheet's power stage 10x in ticks, so it was removed.
    local state, worst = graph_dump.load("tests/fixtures/power_s1_drawn_state.lua.gz"), 0
    while not state.done do
        local in_chain = state.cursor.phase == "chain"
        local started = os.clock()
        Power.step(state, {ops = 2000})
        if in_chain then worst = math.max(worst, os.clock() - started) end
    end
    print(string.format("PR4 worst stack1 chain Power.step: %.3f ms", worst * 1000))
    H.equal(worst <= 0.016, true, "2000-op relay chain steps stay within 16 ms")
end)

H.done("test_power_relay_chain")
