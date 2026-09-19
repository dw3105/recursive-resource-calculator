--A real sliced calculation publishes its plain record, and Generation consumes that registered record during
--preparation. This file stops before layout completion: Search is not the subject of this proof.
local H = require "tests.harness"

local function base_world(shape)
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate")
    world.add_machine({name = "furnace", categories = {"smelting"}, speed = 1, energy_kw = 100})
    world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}},
        products = {{name = "plate", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    local pane, sheet = H.fill_sheet({{item = "plate", rate = 3, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    return world, sheet, sheet_id
end

local function finish_calculation(world, sheet_id)
    local Jobs = require "logic.jobs"
    local Pipeline = require "logic.calc_pipeline"
    Jobs.OPS_PER_TICK = 1
    Pipeline.start(storage[1].sheet_section.sheet_pane.tabs[1].content)
    for _ = 1, 1200 do
        if not (storage[1].calc_jobs and storage[1].calc_jobs[sheet_id]) then return end
        H.run_ticks(world, 1)
    end
    H.equal(storage[1].calc_jobs and storage[1].calc_jobs[sheet_id], nil,
        "the real sliced calculation finishes within the bounded handoff case")
end

local function wait_for_capture(world, Generation, job_id)
    for _ = 1, 1800 do
        local capture = Generation.capture(1, job_id)
        if capture then return capture end
        H.run_ticks(world, 1)
    end
    return nil
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " record handoff: a real sliced calculation reaches generation preparation", function()
        local world, sheet, sheet_id = base_world(shape)
        local Registry = require "logic.registry"
        local Calculation = require "logic.calculation_result"
        finish_calculation(world, sheet_id)

        H.equal(Registry.calculation, Calculation, "preparation uses the registered CalculationResult module")
        local record = Calculation.get(1, sheet_id)
        H.equal(record ~= nil, true, "the sliced calculation publishes a record")
        H.equal(storage[1].calc_results[sheet_id].input_fingerprint, record.input_fingerprint,
            "the published storage record keeps its input fingerprint")

        local Settings = require "logic.bp.settings"
        local Generation = require "logic.bp.generation"
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id,
            settings = Settings.of_sheet(1, sheet_id), deliver = false}
        local capture = wait_for_capture(world, Generation, job_id)
        H.equal(capture ~= nil, true, "preparation captures before layout completion")
        H.equal(capture.source_kind, "runtime", "the capture came from the real preparation path")
        H.deep_equal(capture.solver_result, record.result, "preparation reads the published solver result")
        H.equal(capture.snapshot.fingerprint.input, record.input_fingerprint,
            "preparation checks the calculation's input fingerprint")
        H.equal(capture.snapshot.state, "current", "the current calculation is accepted by preparation")
        H.equal(Generation.cancel(1, job_id), true, "the handoff proof cancels before asserting a layout")

        local stale_by_revision, revision_reason = Calculation.get(1, sheet_id,
            {sheet_revision = 1, config_revision = 0, input_fingerprint = record.input_fingerprint})
        H.equal(stale_by_revision, nil, "a changed sheet revision is not handed to preparation")
        H.equal(revision_reason, "BP_REJ_SNAPSHOT_STALE", "revision mismatch is explicit")
        local stale_by_fingerprint, fingerprint_reason = Calculation.get(1, sheet_id,
            {sheet_revision = 0, config_revision = 0, input_fingerprint = "different-input"})
        H.equal(stale_by_fingerprint, nil, "a changed input fingerprint is not handed to preparation")
        H.equal(fingerprint_reason, "BP_REJ_SNAPSHOT_STALE", "fingerprint mismatch is explicit")
    end)
end

H.done("test_generation_record_handoff")
