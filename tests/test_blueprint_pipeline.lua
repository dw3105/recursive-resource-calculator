--The generation service owns the queued job, terminal result and prepared capture from click to layout.
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

local function find(root, name)
    if root and root.name == name then return root end
    for _, child in ipairs(root and root.children or {}) do
        local found = find(child, name)
        if found then return found end
    end
end

local function prepared(sheet_id, revisions)
    return {
        schema_version = 1,
        snapshot = {schema_version = 1, sheet_id = sheet_id, state = "current",
            fingerprint = {input = "fixture-input"}, targets = {}, selection = {}},
        solver_result = {schema_version = 1, status = "ok", columns = {}},
        catalog = {schema_version = 1, entity = {}, item = {}, fluid = {}, quality = {}, quality_level = {},
            module = {}, beacon = {}},
        settings = {input_edge = "left", output_edge = "top"}, options = {},
        revisions = clone(revisions or {sheet = 0, config = 0}),
        surface = "nauvis", force = "player", source_export = {name = "fixture-export"},
    }
end

local function fixture(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}},
        products = {{name = "gear", amount = 1}}})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    if options.control then
        require "control"
        world.handlers.on_init()
    end

    local Registry = require "logic.registry"
    local Jobs = require "logic.jobs"
    local Snapshot = require "logic.snapshot"
    local pane, sheet = H.fill_sheet(options.targets or {})
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    Registry.generation_provenance = {
        candidate_sha = "fixture-candidate", mod_version = "fixture-version", factorio_branch = shape, packaged = false,
    }
    Registry.calculation = options.calculation or {get = function() return nil end}
    local Generation = require "logic.bp.generation"
    return world, Registry, Jobs, Snapshot, Generation, pane, sheet, sheet_id
end

local function tick(world, Jobs, count)
    for _ = 1, count or 1 do
        world.advance_tick(1)
        Jobs.on_tick({tick = world.tick})
    end
end

local function terminal(world, Jobs, Generation, player_index, job_id, limit)
    local status
    for _ = 1, limit or 80 do
        status = Generation.status(player_index, job_id)
        if status and status.state ~= "pending" then return status end
        tick(world, Jobs)
    end
    H.equal(false, true, "generation finishes within the bounded tick limit")
end

local function controlled_search(mode, result)
    local Search = require "logic.bp.search"
    Search.begin = function(input)
        return {phase = "search", progress = {phase = "search", done_units = 0, total_units = 1}, input = input}
    end
    Search.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1 end
        state.done = true
        state.phase = mode == "success" and "done" or "failed"
        state.ok = mode == "success"
        if state.ok then state.result = clone(result or {blueprint = "controlled"})
        else state.errors = {{code = result or "BP_R_PORT_BLOCKED"}} end
        state.progress = {phase = state.phase, done_units = 1, total_units = 1}
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " unit case: a Generate click queues a job and returns at once", function()
        local world, Registry, Jobs, Snapshot, Generation, pane, sheet, sheet_id = fixture(shape)
        local snapshot = Snapshot.of_sheet(sheet)
        Registry.calculation = {get = function()
            return {schema_version = 1, player_index = 1, sheet_id = sheet_id, sheet_revision = 0, config_revision = 0,
                input_fingerprint = snapshot.fingerprint.input, result = {status = "ok", columns = {}}}
        end}
        local Dialog = require "gui.blueprint_dialog"
        local frame = Dialog.open(1, sheet)
        local button = find(frame, "hxrrc_blueprint_generate_button")
        local ok, job_id = Dialog.on_generate_clicked({player_index = 1, element = button})
        H.equal(ok, true, "Generate returns immediately")
        H.equal(type(job_id), "number", "Generate returns a service identity")
        H.equal(storage[1].blueprint_job ~= nil, true, "Generate queues the service job")
        H.equal(Generation.status(1, job_id).state, "pending", "the queued job is not completed in the click")
        H.equal(world.tick, 0, "the click does not advance a tick")
        H.equal(Jobs.progress_of(1, sheet_id) ~= nil, true, "the shared job scheduler sees the request")
    end)

    H.test(shape .. " unit case: registration never replaces another caller's publication", function()
        local _, _, Jobs, _, Generation = fixture(shape)
        local register_calls = 0
        local register = Jobs.register
        Jobs.register = function(...)
            register_calls = register_calls + 1
            return register(...)
        end
        H.equal(Generation.register(), true, "registration remains available")
        H.equal(register_calls, 0, "an idempotent registration does not replace a publication")
    end)

    H.test(shape .. " unit case: job identity is stable from start through terminal status", function()
        local world, _, Jobs, _, Generation, _, _, sheet_id = fixture(shape)
        controlled_search("success")
        local input = prepared(sheet_id)
        local first = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = input}
        H.equal(Generation.status(1, first).job_id, first, "status keeps the generation identity")
        local result = terminal(world, Jobs, Generation, 1, first)
        H.equal(result.job_id, first, "terminal status keeps the same identity")
        H.equal(result.state, "success", "the controlled job succeeds")
    end)

    H.test(shape .. " unit case: cancel stops a queued job without publishing", function()
        local world, _, Jobs, _, Generation, _, _, sheet_id = fixture(shape)
        controlled_search("success")
        local first = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)}
        H.equal(Generation.cancel(1, first), true, "cancel accepts the pending generation")
        local result = Generation.status(1, first)
        H.equal(result.state, "cancelled", "cancel is terminal")
        tick(world, Jobs, 3)
        H.equal(Generation.status(1, first).state, "cancelled", "cancel cannot be overwritten by a later tick")
    end)

    H.test(shape .. " unit case: supersession by a second start on one sheet cancels the first", function()
        local _, _, _, _, Generation, _, _, sheet_id = fixture(shape)
        local first = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)}
        local second = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)}
        H.equal(Generation.status(1, first).state, "cancelled", "the older request is terminal")
        H.equal(Generation.status(1, first).phase, "superseded", "the older request says why")
        H.equal(Generation.status(1, second).state, "pending", "the newer request owns the sheet")
    end)

    H.test(shape .. " unit case: a deleted sheet ends the generation without a publication", function()
        local world, _, Jobs, _, Generation, pane, _, sheet_id = fixture(shape)
        local first = Generation.start{player_index = 1, sheet_id = sheet_id}
        pane.tabs[1].content.valid = false
        tick(world, Jobs)
        local result = Generation.status(1, first)
        H.equal(result.state, "cancelled", "deleted preparation is cancellation")
        H.equal(result.phase, "cancelled", "deleted preparation has a cancellation phase")
        H.equal(Generation.capture(1, first), nil, "a deleted sheet has no prepared capture")
    end)

    H.test(shape .. " unit case: a revision change fails the queued generation", function()
        local world, _, Jobs, _, Generation, _, _, sheet_id = fixture(shape)
        controlled_search("success")
        local first = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)}
        storage[1].sheet_revision[sheet_id] = 1
        local result = terminal(world, Jobs, Generation, 1, first)
        H.equal(result.state, "failure", "revision change is not a success")
        H.equal(result.reason_codes[1], "BP_FAIL_REVISION_CHANGED", "revision failure is explicit")
        H.equal(result.stage, "search", "revision failure is detected at the job boundary")
    end)

    H.test(shape .. " unit case: preparation failure is preflight and search failure is search", function()
        local world, _, Jobs, _, Generation, _, _, sheet_id = fixture(shape)
        local preparation = Generation.start{player_index = 1, sheet_id = sheet_id}
        local preparation_result = terminal(world, Jobs, Generation, 1, preparation)
        H.equal(preparation_result.state, "failure", "missing published calculation fails")
        H.equal(preparation_result.stage, "preflight", "preparation failure is not a search failure")
        H.equal(preparation_result.reason_codes[1], "BP_REJ_SNAPSHOT_STALE", "preparation reports stale input")

        controlled_search("failure", "BP_R_PORT_BLOCKED")
        local search = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)}
        local search_result = terminal(world, Jobs, Generation, 1, search)
        H.equal(search_result.state, "failure", "controlled search failure is terminal")
        H.equal(search_result.stage, "search", "search failure has the search stage")
        H.equal(search_result.reason_codes[1], "BP_R_PORT_BLOCKED", "search reason survives publication")
    end)

    H.test(shape .. " unit case: a busy cursor is retried after a successful search", function()
        local world, _, Jobs, _, Generation, _, _, sheet_id = fixture(shape)
        controlled_search("success", {entities = {{name = "assembler", position = {x = 0, y = 0}}}})
        game.players[1].cursor_stack.set_stack{name = "raw"}
        local first = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id), deliver = true}
        local result = terminal(world, Jobs, Generation, 1, first)
        H.equal(result.state, "success", "a busy cursor does not fail the generation")
        H.equal(storage[1].blueprint_delivery ~= nil, true, "the undelivered result is retained")
        game.players[1].cursor_stack.clear()
        local Delivery = require "gui.blueprint_delivery"
        H.equal(Delivery.retry(1), true, "the retained result is retried")
        H.equal(game.players[1].cursor_stack.is_blueprint_setup(), true, "retry hands over the blueprint")
    end)

    H.test(shape .. " unit case: a prepared capture remains readable after terminal search failure", function()
        local world, _, Jobs, _, Generation, _, _, sheet_id = fixture(shape)
        controlled_search("failure", "BP_R_PORT_BLOCKED")
        local first = Generation.start{player_index = 1, sheet_id = sheet_id,
            prepared_input = prepared(sheet_id), source_kind = "harness"}
        local result = terminal(world, Jobs, Generation, 1, first)
        local capture = Generation.capture(1, first)
        H.equal(result.state, "failure", "layout failure is terminal")
        H.equal(capture ~= nil, true, "preparation was captured before layout")
        H.equal(capture.source_kind, "harness", "capture source kind is retained")
        H.equal(capture.provenance.outcome, "failure", "capture provenance records the terminal outcome")
        H.equal(capture.provenance.stage, "search", "capture provenance records the failed stage")
        H.equal(capture.provenance.reason_codes[1], "BP_R_PORT_BLOCKED", "capture provenance records the reason")
        H.equal(type(capture.source_export) == "table" and capture.source_export.text or nil, nil,
            "capture does not nest export text")
    end)
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " mandatory real-sheet case: a calculated nonzero chain reaches delivered blueprint", function()
        local world, Registry, Jobs, Snapshot, Generation, pane, sheet = fixture(shape,
            {targets = {{item = "gear", rate = 1}}, control = true})
        local ReportSteps = require "logic.report_steps"
        local published_result
        local publish = ReportSteps.publish
        ReportSteps.publish = function(state)
            local ok = publish(state)
            if ok then published_result = clone(state.result) end
            return ok
        end
        local Sheet = require "gui.sheet"
        Sheet.calculate(Sheet.compute_button_of(sheet))
        local calculation_ticks = 0
        while storage[1].calc_jobs and storage[1].calc_jobs[sheet.tags.hxrrc_sheet_id] do
            H.run_ticks(world, 1)
            calculation_ticks = calculation_ticks + 1
            H.equal(calculation_ticks < 600, true, "real calculation finishes within the bound")
        end
        H.equal(published_result ~= nil, true, "real calculation publishes a result")
        local snapshot = Snapshot.of_sheet(sheet)
        Registry.calculation = {get = function()
            return {schema_version = 1, player_index = 1, sheet_id = sheet.tags.hxrrc_sheet_id,
                sheet_revision = 0, config_revision = 0, input_fingerprint = snapshot.fingerprint.input,
                result = published_result}
        end}
        local settings = require("logic.bp.settings").of_sheet(1, sheet.tags.hxrrc_sheet_id)
        local job_id = Generation.start{player_index = 1, sheet_id = sheet.tags.hxrrc_sheet_id, settings = settings, deliver = true}
        local result = Generation.status(1, job_id)
        for _ = 1, 900 do
            if result.state ~= "pending" then break end
            H.run_ticks(world, 1)
            result = Generation.status(1, job_id)
        end
        H.equal(result.state, "success", "the real modules produce a blueprint (" .. tostring(result.stage or result.phase)
            .. ": " .. table.concat(result.reason_codes or {}, ",") .. ")")
        H.equal(game.players[1].cursor_stack.is_blueprint_setup(), true, "the real result is delivered")
        H.equal(game.players[1].cursor_stack.get_blueprint_entities() ~= nil, true, "the delivered blueprint has entities")
    end)
    --A code alone explains nothing. job_step_failed is a raised Lua error, and its message names the file and the
    --line; without this the player sees four words and the message dies inside the job.
    H.test(shape .. " unit case: a failing step reports its raised error, not only its code", function()
        local world, Registry, Jobs, _, Generation, _, sheet, sheet_id = fixture(shape,
            {targets = {{item = "gear", rate = 1}}, control = true})
        local Snapshot = require "logic.snapshot"
        local of_sheet = Snapshot.of_sheet
        Snapshot.of_sheet = function() error("logic/bp/fixture.lua:1: planted failure", 0) end
        local shown = {}
        Registry.generation_failure = function(_, terminal) shown[#shown + 1] = terminal end
        local settings = require("logic.bp.settings").of_sheet(1, sheet_id)
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id, settings = settings, deliver = false}
        local result = terminal(world, Jobs, Generation, 1, job_id, 200)
        Snapshot.of_sheet = of_sheet

        H.equal(result.state, "failure", "the planted error ends the job")
        H.equal(type(result.reason_details), "table", "the terminal result carries its details")
        local seen = false
        for _, reason in ipairs(result.reason_details) do
            if type(reason.detail) == "string" and reason.detail:find("planted failure", 1, true) then seen = true end
        end
        H.equal(seen, true, "the raised message travels with the code")
        H.equal(#shown > 0 and type(shown[1].reason_details), "table", "and reaches the dialog")
        H.equal(result.reason_codes[1], "BP_FAIL_INTERNAL_ERROR", "a raised error is never called a budget")
        H.equal(result.stage, "prepare", "and names the stage it was raised in")
    end)

end

H.done("test_blueprint_pipeline")
