--Legacy panel elements are repaired by the same ten-tick path used in game.
local H = require "tests.harness"

local function world_for(shape)
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate")
    world.add_machine({name = "furnace", categories = {"smelting"}, speed = 1})
    world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "plate", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    return world, storage[1].sheet_section.sheet_pane.tabs[1].content
end

local function named(parent, name)
    for _, child in ipairs(parent and parent.children or {}) do
        if child.name == name then return child end
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PS1 legacy canceled label is swept within ten ticks without disturbing report", function()
        local world, sheet = world_for(shape)
        local legacy = H.legacy_save(sheet)
        local report = sheet.output_flow.add{type = "label", name = "report", caption = "old report"}
        local ProgressPanel = require "gui.progress_panel"
        ProgressPanel.set_offer(sheet, "stale-job", {sequence = 1, entities = 2})
        ProgressPanel.set_best(sheet, 2)
        H.run_ticks(world, 10)
        H.equal(legacy.valid, false, "legacy label is destroyed")
        H.equal(sheet.output_flow.children[1], report, "report remains first in output")
        H.equal(#sheet.output_flow.children, 1, "output has only its report")
        H.equal(named(sheet, "hxrrc_progress_best"), nil, "stale best-layout line is removed")
        H.equal(named(sheet, "hxrrc_better_layout_offer"), nil, "stale delivery offer is removed")
        local Sheet = require "gui.sheet"
        H.equal(Sheet.progressbar_of(sheet).visible, false, "stale bar is hidden")
        H.equal(Sheet.cancel_button_of(sheet).visible, false, "stale Cancel is hidden")
        H.equal(named(sheet, "hxrrc_progress_status"), nil, "stale status is removed")
    end)

    H.test(shape .. " PS2 explicit sweep is published for every sheet", function()
        local _, sheet = world_for(shape)
        local old = H.legacy_save(sheet, {visible_controls = false})
        local pane = sheet.parent
        require("gui.sheet").new(pane)
        local second_sheet = pane.tabs[2].content
        local second_old = H.legacy_save(second_sheet, {visible_controls = false})
        require("logic.registry").progress_sweep(1)
        H.equal(old.valid, false, "registry sweep removes the first sheet's legacy label")
        H.equal(second_old.valid, false, "registry sweep removes every sheet's legacy label")
    end)

    H.test(shape .. " PS3 a real red science generation shows its bar by the tenth tick", function()
        local world = H.new_world(shape)
        world.add_default_infrastructure()
        world.add_blueprint_item()
        world.add_player(1)
        world.init()
        require "control"
        world.handlers.on_init()
        local pane, sheet = H.fill_sheet({})
        storage[1].sheet_section = {sheet_pane = pane}
        local sid = sheet.tags.hxrrc_sheet_id
        storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
        require("logic.registry").calculation = {get = function() return nil end}
        local input = assert(io.open("tests/golden/cases/player-red-science-1s/prepared_input.json", "r"))
        local prepared = helpers.json_to_table(input:read("*a")); input:close()
        prepared.snapshot = prepared.snapshot or {}; prepared.snapshot.sheet_id = sid
        prepared.revisions = {sheet = 0, config = 0}
        local id = require("logic.bp.generation").start{player_index = 1, sheet_id = sid, prepared_input = prepared}
        H.equal(id ~= nil, true, "the real red science input starts")
        H.run_ticks(world, 10)
        local Sheet = require "gui.sheet"
        H.equal(Sheet.progressbar_of(sheet).visible, true, "the running generation shows its bar")
        H.equal(Sheet.cancel_button_of(sheet).visible, true, "the running generation shows Cancel")
    end)
end

H.done("test_panel_sweep")
