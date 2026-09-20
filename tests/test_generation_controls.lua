--Controls a caller writes must reach the boundary that honours them.
--A budget number written into a fixture and then dropped makes an unbounded run look bounded, so every control
--case here reads the value Search was actually handed, never the value the caller wrote.
local H = require "tests.harness"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function prepared(sheet_id)
    return {
        schema_version = 1,
        snapshot = {schema_version = 1, sheet_id = sheet_id, state = "current",
            fingerprint = {input = "fixture-input"}, targets = {}, selection = {}},
        solver_result = {schema_version = 1, status = "ok", columns = {}},
        catalog = {schema_version = 1, entity = {}, item = {}, fluid = {}, quality = {}, quality_level = {},
            module = {}, beacon = {}},
        settings = {input_edge = "left", output_edge = "top"}, options = {},
        revisions = {sheet = 0, config = 0},
        surface = "nauvis", force = "player", source_export = {name = "fixture-export"},
    }
end

local function fixture(shape)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()

    local Registry = require "logic.registry"
    local Jobs = require "logic.jobs"
    local pane, sheet = H.fill_sheet({})
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    Registry.generation_provenance = {candidate_sha = "control-fixture", mod_version = "control",
        factorio_branch = shape, packaged = false}
    Registry.calculation = {get = function() return nil end}
    local Generation = require "logic.bp.generation"
    return world, Jobs, Generation, sheet_id
end

--Search is captured at the module table generation.lua already holds, so the recorded input is the one the
--service passes, not a copy built by this test.
local function record_search_input()
    local Search = require "logic.bp.search"
    local seen = {}
    Search.begin = function(input)
        seen[#seen + 1] = clone(input)
        return {phase = "search", progress = {phase = "search", done_units = 0, total_units = 1}}
    end
    Search.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1 end
        state.done, state.ok, state.phase = true, true, "done"
        state.result = {entities = {}, blueprint = "control"}
        state.progress = {phase = "done", done_units = 1, total_units = 1}
    end
    return seen
end

local function run(world, Jobs, Generation, job_id)
    for _ = 1, 80 do
        local status = Generation.status(1, job_id)
        if status and status.state ~= "pending" then return status end
        world.advance_tick(1)
        Jobs.on_tick({tick = world.tick})
    end
    H.equal(false, true, "the control fixture finishes within the bounded tick limit")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " GC1 a search budget in options reaches the search boundary", function()
        local world, Jobs, Generation, sheet_id = fixture(shape)
        local seen = record_search_input()
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id,
            prepared_input = prepared(sheet_id), options = {search_budget = 4321}}
        run(world, Jobs, Generation, job_id)
        H.equal(#seen, 1, "the search starts once")
        H.equal(seen[1].search_budget, 4321, "the search receives the option the caller wrote")
        H.equal(seen[1].options.search_budget, 4321, "the option survives inside the options table")
    end)

    H.test(shape .. " GC2 a top level search budget is forwarded, never dropped", function()
        local world, Jobs, Generation, sheet_id = fixture(shape)
        local seen = record_search_input()
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id,
            prepared_input = prepared(sheet_id), search_budget = 1234}
        run(world, Jobs, Generation, job_id)
        H.equal(#seen, 1, "the search starts once")
        H.equal(seen[1].search_budget, 1234, "the top level control reaches the search boundary")
    end)

    H.test(shape .. " GC3 an option beats the top level spelling of the same control", function()
        local world, Jobs, Generation, sheet_id = fixture(shape)
        local seen = record_search_input()
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id,
            prepared_input = prepared(sheet_id), search_budget = 1234, options = {search_budget = 99}}
        run(world, Jobs, Generation, job_id)
        H.equal(seen[1].search_budget, 99, "the documented options shape wins")
    end)

    H.test(shape .. " GC4 no control means no invented budget", function()
        local world, Jobs, Generation, sheet_id = fixture(shape)
        local seen = record_search_input()
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id,
            prepared_input = prepared(sheet_id)}
        run(world, Jobs, Generation, job_id)
        H.equal(seen[1].search_budget, nil, "an absent control stays absent")
    end)
end

H.done("test_generation_controls")
