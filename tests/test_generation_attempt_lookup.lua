--The per-sheet attempt is the durable bridge between a Generate click and a later debug export.
--Every attempt in this file comes from the real dialog or Generation service; the test never plants an id in storage.
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
            fingerprint = {input = "attempt-input-" .. tostring(sheet_id)}, targets = {}, selection = {}},
        solver_result = {schema_version = 1, status = "ok", columns = {}},
        catalog = {schema_version = 1, entity = {}, item = {}, fluid = {}, quality = {}, quality_level = {},
            module = {}, beacon = {}},
        settings = {input_edge = "left", output_edge = "top"}, options = {},
        revisions = clone(revisions or {sheet = 0, config = 0}),
        surface = "nauvis", force = "player", source_export = {name = "attempt-fixture"},
    }
end

local function fixture(shape, sheet_count)
    local world = H.new_world(shape)
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()

    local Registry = require "logic.registry"
    local Snapshot = require "logic.snapshot"
    local sheets = {}
    local pane, sheet = H.fill_sheet({}, 1)
    sheets[sheet.tags.hxrrc_sheet_id] = sheet
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 3}
    storage[1].config_revision = 7
    if sheet_count == 2 then
        local _, other = H.fill_sheet({}, 1)
        sheets[other.tags.hxrrc_sheet_id] = other
    end
    Registry.calculation = {get = function(_, requested_sheet_id)
        local requested = sheets[requested_sheet_id] or sheet
        local snapshot = Snapshot.of_sheet(requested)
        return {schema_version = 1, player_index = 1, sheet_id = requested_sheet_id,
            sheet_revision = (storage[1].sheet_revision or {})[requested_sheet_id] or 0,
            config_revision = storage[1].config_revision or 0,
            input_fingerprint = snapshot.fingerprint.input,
            result = {schema_version = 1, status = "ok", columns = {}}}
    end}
    local Generation = require "logic.bp.generation"
    return world, Registry, Snapshot, Generation, sheet, sheet_id, sheets
end

local function failing_search()
    local Search = require "logic.bp.search"
    Search.begin = function(input)
        return {phase = "search", progress = {phase = "search", done_units = 0, total_units = 1}, input = input}
    end
    Search.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1 end
        state.done, state.ok, state.phase = true, false, "failed"
        state.errors = {{code = "BP_R_PORT_BLOCKED", detail = "attempt-detail", flow_id = "attempt-flow"}}
        state.progress = {phase = "failed", done_units = 1, total_units = 1}
    end
end

local function click_generate(Dialog, sheet)
    local frame = Dialog.open(1, sheet)
    local button = find(frame, "hxrrc_blueprint_generate_button")
    return event_handlers.on_gui_click[button.name]({element = button, player_index = 1})
end

local function terminal(world, Generation, job_id, limit)
    for _ = 1, limit or 400 do
        local result = Generation.status(1, job_id)
        if result and result.state ~= "pending" then return result end
        H.run_ticks(world, 1)
    end
    H.equal(false, true, "the scheduler reaches a terminal generation state")
end

--The red proof runs this test against the pre-lane service. Missing lookup APIs are an assertion failure, never an
--unhandled Lua error, so the proof distinguishes the known gap from a broken fixture.
local function lookup(Generation, player_index, sheet_id)
    local reader = Generation.lookup or Generation.attempt
    if type(reader) ~= "function" then return nil end
    return reader(player_index, sheet_id)
end

local function custom_settings(sheet_id)
    local Settings = require "logic.bp.settings"
    local settings = Settings.of_sheet(1, sheet_id)
    settings.input_edge, settings.output_edge = "right", "bottom"
    Settings.store(1, sheet_id, settings)
    return Settings.of_sheet(1, sheet_id)
end

for _, shape in ipairs(H.shapes()) do
    H.test("AL1", function()
        local world, Registry, _, Generation, sheet, sheet_id = fixture(shape)
        failing_search()
        local Dialog = require "gui.blueprint_dialog"
        local ok, job_id = click_generate(Dialog, sheet)
        H.equal(ok, true, "the real dialog handler accepts Generate")
        terminal(world, Generation, job_id)
        H.equal(storage[1].blueprint_job, nil, "the normal scheduler cleanup removes the terminal queue entry")
        local attempt = lookup(Generation, 1, sheet_id)
        H.equal(attempt ~= nil, true, "the generation service exposes a durable sheet lookup")
        H.equal(attempt.state, "failure", "the terminal failure remains addressable for its sheet")
        H.equal(attempt.job_id, job_id, "the lookup returns the dialog's attempt")
        H.equal(Registry.generation, Generation, "the generation service is published for later export")
        local payload = require "logic.export_payload".build(1, sheet)
        H.equal(payload.prepared_input ~= nil, true, "a post-failure export can still find the prepared attempt")
    end)

    H.test("AL2", function()
        local world, _, Snapshot, Generation, sheet, sheet_id = fixture(shape)
        local expected_settings = custom_settings(sheet_id)
        failing_search()
        local Dialog = require "gui.blueprint_dialog"
        local ok, job_id = click_generate(Dialog, sheet)
        H.equal(ok, true, "the real handler starts the configured attempt")
        terminal(world, Generation, job_id)
        local attempt = lookup(Generation, 1, sheet_id)
        H.equal(attempt ~= nil, true, "the terminal attempt is addressable")
        H.deep_equal(attempt.settings, expected_settings, "the attempt keeps the actual dialog settings")
        H.equal(attempt.prepared_input_identity.input_fingerprint, Snapshot.of_sheet(sheet).fingerprint.input,
            "the prepared-input identity is recorded")
        H.equal(attempt.prepared_input_identity.sheet_id, sheet_id, "the prepared input names its sheet")
        H.equal(attempt.sheet_id, sheet_id, "the record names its sheet")
        H.equal(attempt.revisions.sheet, 3, "the record keeps the sheet revision")
        H.equal(attempt.revisions.config, 7, "the record keeps the configuration revision")
        H.equal(attempt.state, "failure", "the terminal state is explicit")
        H.equal(attempt.reason_codes[1], "BP_R_PORT_BLOCKED", "the search reason code is retained")
    end)

    H.test("AL3", function()
        local world, _, _, Generation, sheet, sheet_id = fixture(shape)
        failing_search()
        local Dialog = require "gui.blueprint_dialog"
        local _, job_id = click_generate(Dialog, sheet)
        terminal(world, Generation, job_id)
        package.loaded["logic.bp.generation"] = nil
        local Reloaded = require "logic.bp.generation"
        local attempt = lookup(Reloaded, 1, sheet_id)
        H.equal(attempt ~= nil, true, "the reloaded service exposes the durable lookup")
        H.equal(attempt.job_id, job_id, "the durable lookup survives a service reload")
        H.equal(attempt.state, "failure", "the terminal state survives reload")
        H.equal(attempt.reason_details[1].detail, "attempt-detail", "reason details survive reload")
        H.equal(attempt.reason_details[1].flow_id, "attempt-flow", "diagnostic identity survives reload")
    end)

    H.test("AL4", function()
        local _, _, _, Generation, sheet, sheet_id = fixture(shape)
        local Dialog = require "gui.blueprint_dialog"
        local ok, job_id = click_generate(Dialog, sheet)
        H.equal(ok, true, "Generate returns before the first scheduler tick")
        local attempt = lookup(Generation, 1, sheet_id)
        H.equal(attempt ~= nil, true, "the queued attempt is addressable")
        H.equal(attempt.job_id, job_id, "the click records its own attempt immediately")
        H.equal(attempt.state == "pending" or attempt.state == "queued", true,
            "a pre-tick attempt is honestly pending or queued")
    end)

    H.test("AL5", function()
        local _, _, _, Generation, _, sheet_id, sheets = fixture(shape, 2)
        local other_id
        for candidate in pairs(sheets) do if candidate ~= sheet_id then other_id = candidate end end
        local first = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)}
        local second = Generation.start{player_index = 1, sheet_id = other_id, prepared_input = prepared(other_id)}
        local first_attempt = lookup(Generation, 1, sheet_id)
        H.equal(first_attempt ~= nil, true, "the first sheet has an explicit attempt")
        H.equal(first_attempt.job_id, first, "the first sheet keeps its own attempt")
        H.equal(first_attempt.sheet_id, sheet_id, "the lookup does not cross sheets")
        local other_attempt = lookup(Generation, 1, other_id)
        H.equal(other_attempt ~= nil, true, "the other sheet has its own explicit attempt")
        H.equal(other_attempt.job_id, second, "the other sheet gets the newer attempt")
    end)

    H.test("AL6", function()
        local _, _, _, Generation, _, sheet_id = fixture(shape)
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)}
        H.equal(Generation.cancel(1, job_id), true, "the service cancels the pending attempt")
        local attempt = lookup(Generation, 1, sheet_id)
        H.equal(attempt ~= nil, true, "the cancelled attempt remains addressable")
        H.equal(attempt.job_id, job_id, "the cancelled attempt is not dropped")
        H.equal(attempt.state, "cancelled", "cancellation is a named terminal state")
    end)

    H.test("AL7", function()
        local _, _, _, Generation, _, sheet_id = fixture(shape)
        local attempt = lookup(Generation, 1, sheet_id .. "-never-started")
        H.equal(attempt ~= nil, true, "the service returns an explicit absence record")
        H.equal(type(attempt), "table", "absence is an explicit record")
        H.equal(attempt.state, "absent", "absence has a named state")
        H.equal(attempt.present, false, "absence is not confused with nil data")
        H.equal(attempt.sheet_id, sheet_id .. "-never-started", "the absent record names the requested sheet")
    end)

    H.test("AL8", function()
        local _, _, _, Generation, _, sheet_id = fixture(shape)
        local job_id = Generation.start{player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)}
        H.equal(storage[1].blueprint_job ~= nil, true, "the transient queued discovery remains present")
        H.equal(storage[1].blueprint_job.state.input.generation_job_id, job_id,
            "the transient job still carries the generation identity")
        local attempt = lookup(Generation, 1, sheet_id)
        H.equal(attempt ~= nil, true, "the queued attempt remains addressable")
        H.equal(attempt.state, "pending", "durability adds to, rather than replaces, the queue")
    end)
end

H.done("test_generation_attempt_lookup")
