--The calculator remains the visible home for queued blueprint work, and cancellation only affects that job.
local H = require "tests.harness"

local function find(root, name)
    if root and root.name == name then return root end
    for _, child in ipairs(root and root.children or {}) do
        local found = find(child, name)
        if found then return found end
    end
end

local function fixture(shape)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    local pane = storage[1].sheet_section.sheet_pane
    local sheet = pane.tabs[1].content
    local Registry = require "logic.registry"
    local Snapshot = require "logic.snapshot"
    local snapshot = Snapshot.of_sheet(sheet)
    Registry.calculation = {get = function()
        return {schema_version = 1, player_index = 1, sheet_id = sheet.tags.hxrrc_sheet_id,
            sheet_revision = 0, config_revision = 0, input_fingerprint = snapshot.fingerprint.input,
            result = {status = "ok", columns = {}}}
    end}
    return world, sheet, pane, Registry, require "logic.jobs", require "logic.bp.generation", require "gui.blueprint_dialog"
end

local function click(name, element)
    return event_handlers.on_gui_click[name]({element = element, player_index = 1})
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " JF1 Generate closes the dialog and opens the calculator on its sheet", function()
        local world, sheet, pane = fixture(shape)
        local dialog = require "gui.blueprint_dialog"
        local frame = dialog.open(1, sheet)
        local button = find(frame, "hxrrc_blueprint_generate_button")
        click(button.name, button)
        H.equal(dialog.is_open(1), false, "dialog is closed")
        H.equal(storage[1].calculator.visible, true, "calculator is visible")
        H.equal(game.players[1].opened, storage[1].calculator, "calculator owns focus")
        H.equal(pane.selected_tab_index, 1, "job sheet is selected")
        H.equal(storage[1].blueprint_job ~= nil, true, "blueprint job is running")
        H.equal(world.tick, 0, "click only queues work")
    end)

    H.test(shape .. " JF2 dialog footer says Close and closing leaves a queued job running", function()
        local _, sheet, _, _, _, Generation = fixture(shape)
        local dialog = require "gui.blueprint_dialog"
        local frame = dialog.open(1, sheet)
        local close = find(frame, "hxrrc_blueprint_close_button")
        H.equal(close.caption[1], "gui.close", "footer caption")
        local job_id = Generation.start{player_index = 1, sheet_id = sheet.tags.hxrrc_sheet_id}
        click(close.name, close)
        H.equal(dialog.is_open(1), false, "dialog closed")
        H.equal(storage[1].blueprint_job ~= nil, true, "closing leaves the job running")
        H.equal(Generation.status(1, job_id).state, "pending", "job remains pending")
    end)

    H.test(shape .. " JF3 sheet Cancel cancels a blueprint handle and prevents cursor writes", function()
        local world, sheet, _, _, _, Generation = fixture(shape)
        local dialog = require "gui.blueprint_dialog"
        local frame = dialog.open(1, sheet)
        local button = find(frame, "hxrrc_blueprint_generate_button")
        local _, job_id = dialog.on_generate_clicked({element = button, player_index = 1})
        local cancel = find(sheet, "hxrrc_cancel_button")
        click(cancel.name, cancel)
        H.equal(Generation.status(1, job_id).state, "cancelled", "handle state")
        H.equal(storage[1].blueprint_job, nil, "scheduled blueprint removed")
        H.run_ticks(world, 600)
        H.equal(world.hold_record(1), nil, "no cursor write")
        H.equal(find(sheet, "hxrrc_better_layout_offer"), nil, "no delivery offer")
    end)

    H.test(shape .. " JF4 Compute and Generate both run after a previous Cancel", function()
        local _, sheet = fixture(shape)
        local row = sheet.input_container.children[1]
        row.rate_textfield.text = "1"
        row.hxrrc_desired_item_button.elem_value = {name = "gear", quality = "normal"}
        event_handlers.on_gui_elem_changed[row.hxrrc_desired_item_button.name]({element = row.hxrrc_desired_item_button, player_index = 1})
        local compute = require "gui.sheet".compute_button_of(sheet)
        click(compute.name, compute)
        H.equal(storage[1].calc_jobs[sheet.tags.hxrrc_sheet_id] ~= nil, true, "first Compute queues work")
        local cancel = find(sheet, "hxrrc_cancel_button")
        click(cancel.name, cancel)
        click(compute.name, compute)
        H.equal(storage[1].calc_jobs[sheet.tags.hxrrc_sheet_id] ~= nil, true, "Compute queues again after Cancel")
        click(cancel.name, cancel)
        local dialog = require "gui.blueprint_dialog"
        local frame = dialog.open(1, sheet)
        local button = find(frame, "hxrrc_blueprint_generate_button")
        local ok = click(button.name, button)
        H.equal(ok, true, "Generate starts after Cancel")
        H.equal(storage[1].blueprint_job ~= nil, true, "new blueprint job exists")
    end)

    H.test(shape .. " JF5 closed-dialog failure records a progress note and wraps its error label", function()
        local _, sheet, _, Registry = fixture(shape)
        local dialog = require "gui.blueprint_dialog"
        local frame = dialog.open(1, sheet)
        local label = find(frame, "hxrrc_blueprint_error")
        H.equal(label.style.single_line, false, "error wraps")
        H.equal(label.style.maximal_width, 400, "error width")
        dialog.close(1)
        local noted
        Registry.progress_note = function(player_index, sheet_id, caption) noted = {player_index, sheet_id, caption} end
        dialog.show_generation_failure(1, {sheet_id = sheet.tags.hxrrc_sheet_id, reason_codes = {"BP_FAIL"}, stage = "search"})
        H.equal(noted and noted[2], sheet.tags.hxrrc_sheet_id, "closed-dialog failure reaches sheet note")
    end)

    H.test(shape .. " JF6 reopening the calculator during work selects the job sheet", function()
        local _, sheet, pane, _, Jobs = fixture(shape)
        require "gui.sheet".new(pane)
        local second = pane.tabs[2].content
        Jobs.request_sheet(1, second.tags.hxrrc_sheet_id, {kind = "fake", revisions = {sheet = 0, config = 0}})
        pane.selected_tab_index = 1
        local calculator = require "gui.calculator"
        calculator.toggle(game.players[1])
        calculator.toggle(game.players[1])
        H.equal(pane.selected_tab_index, 2, "running job sheet selected on reopen")
        H.equal(sheet.valid, true, "original sheet remains")
    end)
end

H.done("test_job_flow")
