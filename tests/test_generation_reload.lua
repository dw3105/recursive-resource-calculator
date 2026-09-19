--Generation lifecycle across a supported control.lua reparse (the save remains in storage).
local H = require "tests.harness"

local function prepared(sheet_id, snapshot)
    snapshot = snapshot or {schema_version = 1, sheet_id = sheet_id, state = "current",
        fingerprint = {input = "reload-input"}, targets = {}, selection = {}}
    snapshot.state = "current"
    return {
        schema_version = 1,
        snapshot = snapshot,
        solver_result = {schema_version = 1, status = "ok", columns = {}},
        catalog = {schema_version = 1, entity = {}, item = {}, fluid = {}, quality = {}, quality_level = {},
            module = {}, beacon = {}},
        settings = {input_edge = "left", output_edge = "top"}, options = {},
        revisions = {sheet = 0, config = 0}, surface = "nauvis", force = "player",
        source_export = {name = "reload-export"},
    }
end

local function fixture(shape)
    local world = H.new_world(shape)
    world.add_player(1)
    world.add_player(2)
    world.init()
    require "control"
    world.handlers.on_init()
    local pane, sheet = H.fill_sheet({}, 1)
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    local pane_two, sheet_two = H.fill_sheet({}, 2)
    storage[2].sheet_section = {sheet_pane = pane_two}
    local sheet_id_two = sheet_two.tags.hxrrc_sheet_id
    storage[2].sheet_revision = {[sheet_id_two] = 0}
    storage[2].config_revision = 0
    world.add_item("raw")
    world.add_blueprint_item()
    return world, sheet, sheet_id, sheet_two, sheet_id_two
end

local function controlled_search()
    local Search = require "logic.bp.search"
    Search.begin = function(input)
        return {phase = "search", progress = {phase = "search", done_units = 0, total_units = 1}, input = input}
    end
    Search.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1 end
        state.done, state.ok, state.phase = true, true, "done"
        state.result = {entities = {{name = "assembler", position = {x = 0, y = 0}}}}
        state.progress = {phase = "done", done_units = 1, total_units = 1}
    end
end

--This is the supported reload path for the harness: control.lua is parsed again, its process-local callbacks are
--rebuilt, and the existing world/storage stand in for the save loaded by Factorio.
local function reload_control()
    package.loaded["control"] = nil
    package.loaded["logic.bp.generation"] = nil
    package.loaded["logic.engine_test_api"] = nil
    require "control"
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " lifecycle unit case: a pending generation survives the supported control reload", function()
        local world, sheet, sheet_id, sheet_two, sheet_id_two = fixture(shape)
        controlled_search()
        local Generation = require "logic.bp.generation"
        local Snapshot = require "logic.snapshot"
        local first = Generation.start{player_index = 1, sheet_id = sheet_id,
            prepared_input = prepared(sheet_id, Snapshot.of_sheet(sheet))}
        H.equal(Generation.status(1, first).state, "pending", "the job is pending before reload")
        H.equal(storage[1].blueprint_job ~= nil, true, "the saved job is present before reload")

        reload_control()
        local ReloadedGeneration = require "logic.bp.generation"
        local after_reload = ReloadedGeneration.status(1, first)
        H.equal(after_reload ~= nil, true, "the saved job still has an owner after reload")
        H.equal(after_reload.state, "pending", "the saved job resumes after reload")

        for _ = 1, 8 do
            H.run_ticks(world, 1)
            local result = ReloadedGeneration.status(1, first)
            if result and result.state ~= "pending" then break end
        end
        H.equal(ReloadedGeneration.status(1, first).state, "success", "the resumed job publishes exactly once")
        H.equal(ReloadedGeneration.capture(1, first) ~= nil, true, "the capture remains addressable after reload")

        reload_control()
        ReloadedGeneration = require "logic.bp.generation"
        H.equal(ReloadedGeneration.status(1, first).state, "success", "the terminal result survives another reload")
        storage[1].sheet_revision[sheet_id] = 1
        H.equal(ReloadedGeneration.capture(1, first).snapshot.state, "stale",
            "a capture with a changed sheet revision is never served as current")

        local second = ReloadedGeneration.start{player_index = 2, sheet_id = sheet_id_two,
            prepared_input = prepared(sheet_id_two, Snapshot.of_sheet(sheet_two))}
        H.equal(second > first, true, "a reload never reuses an earlier job id for different work")
        H.equal(ReloadedGeneration.status(1, second), nil, "player one cannot read player two's job")
        H.equal(ReloadedGeneration.status(2, first), nil, "player two cannot read player one's job")
    end)

    H.test(shape .. " lifecycle unit case: an occupied-cursor delivery retry survives reload", function()
        local world, sheet, sheet_id = fixture(shape)
        controlled_search()
        local Snapshot = require "logic.snapshot"
        local Generation = require "logic.bp.generation"
        game.players[1].cursor_stack.set_stack{name = "raw"}
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id,
            prepared_input = prepared(sheet_id, Snapshot.of_sheet(sheet)), deliver = true}
        for _ = 1, 8 do
            H.run_ticks(world, 1)
            if Generation.status(1, job_id).state ~= "pending" then break end
        end
        H.equal(Generation.status(1, job_id).state, "success", "the result succeeds while the cursor is occupied")
        H.equal(storage[1].blueprint_delivery ~= nil, true, "delivery keeps the result for retry")

        reload_control()
        game.players[1].cursor_stack.clear()
        local Delivery = require "gui.blueprint_delivery"
        H.equal(Delivery.retry(1), true, "the occupied-cursor result retries after reload")
        H.equal(storage[1].blueprint_delivery, nil, "a successful retry clears the saved delivery")
        H.equal(game.players[1].cursor_stack.is_blueprint_setup(), true, "retry publishes the same blueprint")
    end)
end

H.done("test_generation_reload")
