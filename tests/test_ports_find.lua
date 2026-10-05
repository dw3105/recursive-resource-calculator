--PF1-PF5 (red on player-run-base, 2026-10-05): feed and sink tiles of each Case's delivered sheet from geometry alone
--(tests/game/lib/ports.lua) equal tools/sheet_ports.py's ports.json, which used the generator's port_id.
local H = require "tests.harness"
local Ports = require "tests.game.lib.ports"
local JSON
do
    local g = assert(io.open("tests/golden/generate.lua")); local src = g:read("*a"); g:close()
    local a = assert(src:find("local JSON = {}", 1, true)); local b = assert(src:find("local input_path,", a, true))
    JSON = assert(load(src:sub(a, b - 1) .. "\nreturn JSON"))()
end
local function json(path) local f = assert(io.open(path)); local s = f:read("*a"); f:close(); return JSON.decode(s) end
local function exists(path) local f = io.open(path); if f then f:close() end; return f ~= nil end

local CASES = {"player-am2-chain-repaired", "player-blue-science-10s", "player-green-science-1s", "player-inserter-10s",
    "player-inserter-10s-bulk", "player-inserter-10s-stack1", "player-red-green-science-10s", "player-red-science-10s",
    "player-red-science-10s-bulk", "player-red-science-10s-stack1", "player-red-science-1s", "player-red-science-1s-bulk",
    "player-red-science-1s-foundry", "vanilla-2.1-red-science-1s", "vanilla-2.1-green-science-1s"}

--Vanilla 2.1 Cases have no prepared input: the recipes their sheet binds (tests/game/test_capture.lua:8-16).
local function item(n, a) return {name = n, type = "item", amount = a or 1} end
local VANILLA = {
    recipe = {
        ["automation-science-pack"] = {ingredients = {item("copper-plate"), item("iron-gear-wheel")}, products = {item("automation-science-pack")}},
        ["iron-gear-wheel"] = {ingredients = {item("iron-plate", 2)}, products = {item("iron-gear-wheel")}},
        ["copper-cable"] = {ingredients = {item("copper-plate")}, products = {item("copper-cable", 2)}},
        ["electronic-circuit"] = {ingredients = {item("iron-plate"), item("copper-cable", 3)}, products = {item("electronic-circuit")}},
        ["inserter"] = {ingredients = {item("electronic-circuit"), item("iron-gear-wheel"), item("iron-plate")}, products = {item("inserter")}},
        ["transport-belt"] = {ingredients = {item("iron-plate"), item("iron-gear-wheel")}, products = {item("transport-belt", 2)}},
        ["logistic-science-pack"] = {ingredients = {item("inserter"), item("transport-belt")}, products = {item("logistic-science-pack")}},
    },
    entity = {["assembling-machine-1"] = {tile_w = 3, tile_h = 3}, ["assembling-machine-2"] = {tile_w = 3, tile_h = 3}},
}

local function run(case, edit)
    local base = "tests/fixtures/sheets/" .. case
    local f, want = json(base .. ".entities.json"), json(base .. ".ports.json")
    for _, e in ipairs(f.entities) do e.position = {x = e.x, y = e.y} end
    if edit then f.entities = edit(f.entities) or f.entities end
    local prepared_path = "tests/golden/cases/" .. case .. "/prepared_input.json"
    local catalog, by_machine = VANILLA, {}
    if exists(prepared_path) then
        local prepared = json(prepared_path)
        catalog = prepared.catalog
        for _, col in ipairs(prepared.solver_result.columns or {}) do
            local m = type(col.machine) == "table" and col.machine.name or col.machine
            by_machine[m] = by_machine[m] or {}; table.insert(by_machine[m], col.recipe_name)
        end
    end
    local inputs, outputs = {}, {}
    for n in pairs(want.inputs or {}) do inputs[n] = true end
    for n in pairs(want.targets or {}) do outputs[n] = true end
    local got = Ports.find{entities = f.entities, catalog = catalog, inputs = inputs, outputs = outputs,
        recipes_for = function(m) return by_machine[m] or {} end}
    return got, want
end
local function sig(rows)
    local keys = {}
    for _, v in ipairs(rows) do
        local items = v.items or {v.item or v.fluid}
        for _, n in ipairs(items) do keys[#keys + 1] = table.concat({v.tile[1], v.tile[2], n}, ":") end
    end
    table.sort(keys); return table.concat(keys, "|")
end

H.test("PF1 geometry finds every fixture feed", function()
    local bad = {}
    for _, case in ipairs(CASES) do
        local got, want = run(case)
        if sig(got.feeds) ~= sig(want.feeds) then bad[#bad + 1] = case .. " got=" .. sig(got.feeds) .. " want=" .. sig(want.feeds) .. " problems=" .. table.concat(got.problems, ";") end
    end
    H.equal(#bad, 0, table.concat(bad, "\n"))
    print("PF1")
end)
H.test("PF2 geometry finds every fixture sink", function()
    local bad = {}
    for _, case in ipairs(CASES) do
        local got, want = run(case)
        if sig(got.sinks) ~= sig(want.sinks) then bad[#bad + 1] = case .. " got=" .. sig(got.sinks) .. " want=" .. sig(want.sinks) .. " problems=" .. table.concat(got.problems, ";") end
    end
    H.equal(#bad, 0, table.concat(bad, "\n"))
    print("PF2")
end)
H.test("PF3 fluid feeds of blue and am2", function()
    local blue = run("player-blue-science-10s")
    local am2 = run("player-am2-chain-repaired")
    local fl = {}
    for _, x in ipairs(blue.feeds) do if x.fluid then fl[x.fluid] = true end end
    for _, x in ipairs(am2.feeds) do if x.fluid then fl[x.fluid] = true end end
    H.equal(fl.water and fl["crude-oil"] and fl["molten-iron"], true, "water, crude-oil, molten-iron")
    print("PF3")
end)
H.test("PF4 a feed whose machines are gone is reported, not guessed", function()
    --Remove red-1s's furnaces: the ore hands then feed nothing, so both ore heads must be UNNAMED_HEAD problems.
    local cut = run("player-red-science-1s", function(es)
        local keep = {}
        for _, e in ipairs(es) do if e.name ~= "electric-furnace" then keep[#keep + 1] = e end end
        return keep
    end)
    local named, unnamed = 0, 0
    for _, x in ipairs(cut.feeds) do if x.item == "copper-ore" or x.item == "iron-ore" then named = named + 1 end end
    for _, p in ipairs(cut.problems) do if p:find("UNNAMED_HEAD", 1, true) then unnamed = unnamed + 1 end end
    H.equal(named, 0, "ore feed named without its machines")
    H.equal(unnamed >= 2, true, "both ore heads reported: " .. table.concat(cut.problems, ";"))
    print("PF4")
end)
H.test("PF5 finder never reads port_id", function()
    local f = assert(io.open("tests/game/lib/ports.lua")); local s = f:read("*a"); f:close()
    H.equal(s:find("port_id", 1, true), nil)
    print("PF5")
end)
H.done("test_ports_find")
