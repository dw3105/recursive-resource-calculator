--Runs one tests/game/*.lua file OFFLINE on the tests/harness.lua mock, with the FactorioTest globals the headless run
--provides (describe/it/test, before_each/after_each/before_all/after_all, async/done/on_tick/after_ticks, luassert-style
--assert, serpent.line, remote). Lanes check game tests with this only; they never run headless Factorio (player rule
--2026-09-26). The mock is not the engine: a file green here still runs headless at the integrator's merge.
--usage: lua5.2 tests/game/offline.lua tests/game/<file>.lua ["<describe> > <it>"]
--last line: offline-game <file> <n> passed <m> failed
package.path = "./?.lua;" .. package.path
local file, only = arg[1], arg[2]
if not file then io.stderr:write("usage: lua5.2 tests/game/offline.lua tests/game/<file>.lua [\"<describe> > <it>\"]\n") os.exit(2) end

local H = require "tests.harness"

--Fixture modules the stage step writes (tools/game_stage.sh): prepared input JSON and expected entity lines.
local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
for line in (read("tests/game/fixtures.txt") or ""):gmatch("[^\n]+") do
    local case = line:match("^%s*([^#%s][^%s]*)")
    if case then
        local module = case:gsub("-", "_")
        package.preload["tests.game.fixtures." .. module] = function()
            return assert(read("tests/golden/cases/" .. case .. "/prepared_input.json"), "no prepared input for " .. case)
        end
        package.preload["tests.game.fixtures." .. module .. "_expected"] = function()
            return assert(read("tests/game/expected/" .. case .. ".txt"), "no expected lines for " .. case)
        end
    end
end

--A small vanilla-named world: the names the game tests type into a sheet exist here too.
local world = H.new_world(os.getenv("RRC_SHAPE") or "2.0")
world.add_item("iron-plate")
world.add_item("copper-plate")
world.add_item("iron-gear-wheel")
world.add_item("automation-science-pack")
world.add_item("coal", {value = 4e6, category = "chemical"})
world.add_machine({name = "assembling-machine-1", categories = {"crafting"}, speed = 0.5})
world.add_machine({name = "assembling-machine-2", categories = {"crafting"}, speed = 0.75})
world.add_recipe({name = "iron-gear-wheel", category = "crafting", energy = 0.5,
    ingredients = {{name = "iron-plate", amount = 2}}, products = {{name = "iron-gear-wheel", amount = 1}}})
world.add_recipe({name = "automation-science-pack", category = "crafting", energy = 5,
    ingredients = {{name = "copper-plate", amount = 1}, {name = "iron-gear-wheel", amount = 1}},
    products = {{name = "automation-science-pack", amount = 1}}})
--Green science chain, modules and a beacon: what the lane test files type or pick in the real game.
world.add_item("copper-cable")
world.add_item("electronic-circuit")
world.add_item("logistic-science-pack")
world.add_recipe({name = "copper-cable", category = "crafting", energy = 0.5,
    ingredients = {{name = "copper-plate", amount = 1}}, products = {{name = "copper-cable", amount = 2}}})
world.add_recipe({name = "electronic-circuit", category = "crafting", energy = 0.5,
    ingredients = {{name = "iron-plate", amount = 1}, {name = "copper-cable", amount = 3}},
    products = {{name = "electronic-circuit", amount = 1}}})
world.add_module("speed-module", "speed", {speed = 0.2})
world.add_module("productivity-module", "productivity", {productivity = 0.04})
world.add_beacon({name = "beacon"})
world.add_default_infrastructure()
--Placing items of the default infrastructure, as vanilla has them (inserter and belt recipes need them).
for _, name in ipairs({"transport-belt", "inserter"}) do
    if not prototypes.item[name] then world.add_item(name) end
end
world.add_recipe({name = "inserter", category = "crafting", energy = 0.5,
    ingredients = {{name = "electronic-circuit", amount = 1}, {name = "iron-gear-wheel", amount = 1}, {name = "iron-plate", amount = 1}},
    products = {{name = "inserter", amount = 1}}})
world.add_recipe({name = "transport-belt", category = "crafting", energy = 0.5,
    ingredients = {{name = "iron-plate", amount = 1}, {name = "iron-gear-wheel", amount = 1}},
    products = {{name = "transport-belt", amount = 2}}})
world.add_recipe({name = "logistic-science-pack", category = "crafting", energy = 6,
    ingredients = {{name = "inserter", amount = 1}, {name = "transport-belt", amount = 1}},
    products = {{name = "logistic-science-pack", amount = 1}}})
world.add_blueprint_item()
world.add_player(1)
world.init()

--The staged copy is packaged (tools/game_stage.sh writes logic/build_id.lua), so rrc-engine-test registers there.
package.loaded["logic.build_id"] = {candidate_sha = "offline", mod_version = "offline", factorio_branch = "2.0", packaged = true}
local interfaces = {}
remote = {interfaces = interfaces,
    add_interface = function(name, functions) interfaces[name] = functions end,
    remove_interface = function(name) interfaces[name] = nil end,
    call = function(name, method, ...) return interfaces[name][method](...) end}

local function line(value, depth)
    depth = depth or 0
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" or depth > 4 then return tostring(value) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. " = " .. line(value[k], depth + 1) end
    return "{" .. table.concat(parts, ", ") .. "}"
end
serpent = {line = function(value) return line(value) end, block = function(value) return line(value) end}

require "control"
world.handlers.on_init()

--luassert subset the game tests use. Plain assert(v, msg) still works.
local plain_assert = assert
local function fail(msg, default) error((msg or default), 3) end
local function deep(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not deep(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local A = {}
function A.are_equal(want, got, msg) if want ~= got then fail(msg, "expected " .. line(want) .. " got " .. line(got)) end end
function A.are_not_equal(want, got, msg) if want == got then fail(msg, "values equal " .. line(got)) end end
function A.are_same(want, got, msg) if not deep(want, got) then fail(msg, "expected " .. line(want) .. " got " .. line(got)) end end
function A.is_true(v, msg) if v ~= true then fail(msg, "expected true got " .. line(v)) end end
function A.is_false(v, msg) if v ~= false then fail(msg, "expected false got " .. line(v)) end end
function A.is_nil(v, msg) if v ~= nil then fail(msg, "expected nil got " .. line(v)) end end
function A.is_not_nil(v, msg) if v == nil then fail(msg, "expected a value got nil") end end
function A.is_truthy(v, msg) if not v then fail(msg, "expected truthy got " .. line(v)) end end
function A.is_falsy(v, msg) if v then fail(msg, "expected falsy got " .. line(v)) end end
function A.has_error(fn, msg) if pcall(fn) then fail(msg, "expected an error") end end
function A.has_no_error(fn, msg) local ok, err = pcall(fn) if not ok then fail(msg, "unexpected error " .. tostring(err)) end end
A.equal, A.equals, A.same, A.is_equal = A.are_equal, A.are_equal, A.are_same, A.are_equal
A.truthy, A.falsy, A.has_errors, A.errors = A.is_truthy, A.is_falsy, A.has_error, A.has_error
assert = setmetatable(A, {__call = function(_, ...) return plain_assert(...) end})

--Test tree and the FactorioTest run semantics: a test is async once it calls async() (ends at done()) or registers
--on_tick/after_ticks (ends when every tick function returned false). Default timeout 36000 ticks, as control.lua sets.
local root = {name = nil, children = {}, before_each = {}, after_each = {}, before_all = {}, after_all = {}}
local current = root
local run
function describe(name, fn)
    local block = {name = name, parent = current, children = {}, before_each = {}, after_each = {}, before_all = {}, after_all = {}}
    current.children[#current.children + 1] = block
    local saved = current
    current = block
    fn()
    current = saved
end
local function add_test(name, fn, mode)
    current.children[#current.children + 1] = {name = name, fn = fn, parent = current, test = true, mode = mode}
end
test = setmetatable({skip = function(name, fn) add_test(name, fn, "skip") end, todo = function(name) add_test(name, nil, "todo") end},
    {__call = function(_, name, fn) add_test(name, fn) end})
it = test
function before_each(fn) current.before_each[#current.before_each + 1] = fn end
function after_each(fn) current.after_each[#current.after_each + 1] = fn end
function before_all(fn) current.before_all[#current.before_all + 1] = fn end
function after_all(fn) current.after_all[#current.after_all + 1] = fn end
function async(timeout) run.async, run.explicit, run.timeout = true, true, timeout or run.timeout end
function done() if not run.async then error('"done" can only be used when test is async', 2) end run.done = true end
function on_tick(fn) run.async = true run.ticks[#run.ticks + 1] = fn end
function after_ticks(n, fn)
    local finish = n
    on_tick(function(tick) if tick >= finish then fn() return false end end)
end
function ticks_between_tests() end
function tags() end

dofile(file)

local passed, failed, skipped = 0, 0, 0
local function path_of(node)
    local names = {}
    while node and node.name do table.insert(names, 1, node.name) node = node.parent end
    return table.concat(names, " > ")
end
local function hooks(node, key, outer_first)
    local chain = {}
    while node do table.insert(chain, outer_first and 1 or #chain + 1, node) node = node.parent end
    local list = {}
    for _, n in ipairs(chain) do for _, fn in ipairs(n[key]) do list[#list + 1] = fn end end
    return list
end
local function run_test(node)
    local name = path_of(node)
    if only and name ~= only then return end
    if node.mode then skipped = skipped + 1 print("SKIP " .. name) return end
    run = {async = false, explicit = false, done = false, ticks = {}, timeout = 36000}
    local ok, err = true, nil
    for _, fn in ipairs(hooks(node.parent, "before_each", true)) do
        if ok then ok, err = xpcall(fn, debug.traceback) end
    end
    if ok then ok, err = xpcall(node.fn, debug.traceback) end
    local start, waited = world.tick, 0
    while ok and run.async and not (run.explicit and run.done) and (run.explicit or #run.ticks > 0) do
        waited = waited + 1
        if waited > run.timeout then ok, err = false, "test timed out after " .. run.timeout .. " ticks" break end
        H.run_ticks(world, 1)
        local keep = {}
        for _, fn in ipairs(run.ticks) do
            local fn_ok, result = xpcall(function() return fn(world.tick - start) end, debug.traceback)
            if not fn_ok then ok, err = false, result break end
            if result ~= false then keep[#keep + 1] = fn end
        end
        run.ticks = keep
    end
    for _, fn in ipairs(hooks(node.parent, "after_each", false)) do
        local hook_ok, hook_err = xpcall(fn, debug.traceback)
        if ok and not hook_ok then ok, err = false, hook_err end
    end
    if ok then passed = passed + 1 print("PASS " .. name)
    else failed = failed + 1 print("FAIL " .. name .. "\n  " .. tostring(err):gsub("\n", "\n  ")) end
end
local function walk(block)
    for _, fn in ipairs(block.before_all) do fn() end
    for _, child in ipairs(block.children) do
        if child.test then run_test(child) else walk(child) end
    end
    for _, fn in ipairs(block.after_all) do fn() end
end
walk(root)
print(string.format("offline-game %s %d passed %d failed %d skipped", file, passed, failed, skipped))
os.exit((failed == 0 and passed > 0) and 0 or 1)
