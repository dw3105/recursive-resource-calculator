--The seam between two lanes: the durable per-sheet attempt (092) and the debug export (091).
--
--Neither lane could prove this. 092 stops at Generation.lookup; 091 ran on a base where that function did not
--exist yet and therefore wrote an honest "absent" marker. The player's whole complaint lives exactly here: they
--press Generate, the search fails, they press Export debug, and the export must carry that attempt.
--
--Every attempt below comes from the real dialog handler and the real scheduler. Nothing plants an id in storage
--and nothing stubs Generation.capture, because tests/golden/capture_case.lua:90-92 does plant one, and that is
--why this gap survived a whole round of green export tests.
local H = require "tests.harness"

local function find(root, name)
    if root and root.name == name then return root end
    for _, child in ipairs(root and root.children or {}) do
        local found = find(child, name)
        if found then return found end
    end
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
    local other
    if sheet_count == 2 then
        local _, extra = H.fill_sheet({}, 1)
        other = extra
        sheets[extra.tags.hxrrc_sheet_id] = extra
        storage[1].sheet_revision[extra.tags.hxrrc_sheet_id] = 3
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
    return world, Generation, sheet, sheet_id, other
end

--A search that fails the way the player's did: terminal, with a stage reason the export must carry.
local function failing_search()
    local Search = require "logic.bp.search"
    Search.begin = function(input)
        return {phase = "search", progress = {phase = "search", done_units = 0, total_units = 1}, input = input}
    end
    Search.step = function(state, budget)
        if budget.ops > 0 then budget.ops = budget.ops - 1 end
        state.done, state.ok, state.phase = true, false, "failed"
        state.errors = {{code = "BP_FAIL_SEARCH_BUDGET", detail = "integration-detail"}}
        state.progress = {phase = "failed", done_units = 1, total_units = 1}
    end
end

local function click_generate(sheet)
    local Dialog = require "gui.blueprint_dialog"
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

--Always through the ordinary export path, then through the ordinary decoder, exactly as a player's paste travels.
local function exported(sheet)
    local ExportPayload = require "logic.export_payload"
    local payload = ExportPayload.build(1, sheet)
    H.equal(type(payload), "table", "the export path produced a payload")
    local decoded, reason = H.decode_export(assert(ExportPayload.encode(payload)))
    H.equal(decoded ~= nil, true, "the encoded export decodes (" .. tostring(reason) .. ")")
    return decoded
end

local function attempt_of(decoded)
    return type(decoded) == "table" and type(decoded.generation) == "table" and decoded.generation or nil
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " XI1 a failed generation reaches the export after the queue has cleaned up", function()
        local world, Generation, sheet, sheet_id = fixture(shape)
        failing_search()
        local _, job_id = click_generate(sheet)
        local result = terminal(world, Generation, job_id)
        H.equal(result.state, "failure", "the scheduler really failed")
        --logic/jobs.lua:405-407 clears data.blueprint_job while servicing, and :423-426 restores it only for a
        --job that is not terminal. This is the exact moment a player presses Export debug.
        H.equal(storage[1].blueprint_job, nil, "the transient slot is empty, as it is in the reported case")

        local attempt = attempt_of(exported(sheet))
        H.equal(attempt ~= nil, true, "the export carries a generation section")
        if attempt == nil then return end
        H.equal(attempt.status ~= "absent", true,
            "a terminal attempt is never exported as absent; saw " .. tostring(attempt.status))
        H.equal(tostring(attempt.sheet_id or (attempt.snapshot or {}).sheet_id), tostring(sheet_id),
            "the exported attempt belongs to the exported sheet")
    end)

    H.test(shape .. " XI2 the exported attempt carries its terminal state and reason codes", function()
        local world, Generation, sheet = fixture(shape)
        failing_search()
        local _, job_id = click_generate(sheet)
        terminal(world, Generation, job_id)
        local attempt = attempt_of(exported(sheet))
        H.equal(attempt ~= nil, true, "the export carries a generation section")
        if attempt == nil then return end
        H.equal(attempt.state or attempt.status, "failure", "terminal state survives the export")
        local codes = attempt.reason_codes or {}
        H.equal(codes[1], "BP_FAIL_SEARCH_BUDGET", "the reason code survives the export")
    end)

    H.test(shape .. " XI3 the exported attempt carries its own settings and revisions", function()
        local world, Generation, sheet, sheet_id = fixture(shape)
        local Settings = require "logic.bp.settings"
        local chosen = Settings.of_sheet(1, sheet_id)
        chosen.input_edge, chosen.output_edge = "right", "bottom"
        Settings.store(1, sheet_id, chosen)
        failing_search()
        local _, job_id = click_generate(sheet)
        terminal(world, Generation, job_id)
        local attempt = attempt_of(exported(sheet))
        H.equal(attempt ~= nil, true, "the export carries a generation section")
        if attempt == nil then return end
        local settings = attempt.settings or {}
        H.equal(settings.input_edge, "right", "the attempt's own input edge survives, never a default")
        H.equal(settings.output_edge, "bottom", "the attempt's own output edge survives, never a default")
        local revisions = attempt.revisions or {}
        H.equal(revisions.sheet, 3, "the attempt's sheet revision survives")
        H.equal(revisions.config, 7, "the attempt's config revision survives")
    end)

    H.test(shape .. " XI4 immediately after the click the export names the queued attempt, never a finished one", function()
        local _, _, sheet, sheet_id = fixture(shape)
        failing_search()
        local ok = click_generate(sheet)
        H.equal(ok, true, "the click enqueued an attempt")
        --gui/blueprint_dialog.lua:306-321 only enqueues, and Generation.start opens at pending/queued.
        local attempt = attempt_of(exported(sheet))
        H.equal(attempt ~= nil, true, "the export carries a generation section")
        if attempt == nil then return end
        H.equal(attempt.status ~= "absent", true, "a queued attempt is never absent")
        local named = attempt.state or attempt.status
        H.equal(named == "pending" or named == "queued", true,
            "a queued attempt is named queued or pending, never presented as a result; saw " .. tostring(named))
        H.equal(tostring(attempt.sheet_id or (attempt.snapshot or {}).sheet_id), tostring(sheet_id),
            "the queued attempt belongs to the exported sheet")
    end)

    H.test(shape .. " XI5 another sheet's newer attempt never reaches this sheet's export", function()
        local world, Generation, sheet, sheet_id, other = fixture(shape, 2)
        failing_search()
        local _, first = click_generate(sheet)
        terminal(world, Generation, first)
        local _, second = click_generate(other)
        terminal(world, Generation, second)

        local attempt = attempt_of(exported(sheet))
        H.equal(attempt ~= nil, true, "the export carries a generation section")
        if attempt == nil then return end
        local exported_sheet = tostring(attempt.sheet_id or (attempt.snapshot or {}).sheet_id)
        H.equal(exported_sheet, tostring(sheet_id),
            "the newer attempt on the other sheet is never borrowed; saw " .. exported_sheet)
    end)
end

H.done("test_export_attempt_integration")
