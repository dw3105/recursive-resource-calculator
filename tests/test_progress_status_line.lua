--The progress sentence has its own wrapping row and the bar carries only a percentage.
local H = require "tests.harness"

local function named(parent, name)
    for _, child in ipairs(parent and parent.children or {}) do
        if child.name == name then return child end
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PSL-01 real red science job separates percent and status", function()
        local world = H.new_world(shape)
        world.add_default_infrastructure(); world.add_blueprint_item(); world.add_player(1); world.init()
        require "control"; world.handlers.on_init()
        local pane, sheet = H.fill_sheet({}); storage[1].sheet_section = {sheet_pane = pane}
        local sid = sheet.tags.hxrrc_sheet_id
        storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
        require("logic.registry").calculation = {get = function() return nil end}
        local f = assert(io.open("tests/golden/cases/player-red-science-1s/prepared_input.json", "r"))
        local prepared = helpers.json_to_table(f:read("*a")); f:close()
        prepared.snapshot = prepared.snapshot or {}; prepared.snapshot.sheet_id = sid
        prepared.revisions = {sheet = 0, config = 0}
        local id = require("logic.bp.generation").start{player_index=1, sheet_id=sid, prepared_input=prepared}
        H.equal(id ~= nil, true, "real job starts")
        local bar, ended = require("gui.sheet").progressbar_of(sheet), false
        for _ = 1, 20000 do
            H.run_ticks(world, 1)
            local job = storage[1].blueprint_job
            if job and job.progress then
                local status = named(sheet, "hxrrc_progress_status")
                if status then
                    H.equal(bar.caption[1], "hxrrc.progress_bar_percent", "bar caption is percent only")
                    H.equal(status.style.single_line, false, "status can wrap")
                    H.equal(type(status.style.maximal_width), "number", "status has a width limit")
                    H.equal(status.style.maximal_width <= 400, true, "status width is at most 400")
                    break
                end
            end
            if not job or job.done then ended = true; break end
        end
        H.equal(named(sheet, "hxrrc_progress_status") ~= nil, true, "status appears during the job")
        for _ = 1, 20000 do
            if not storage[1].blueprint_job then ended = true; break end
            H.run_ticks(world, 1)
        end
        H.equal(ended, true, "real job finishes")
        H.run_ticks(world, 10)
        H.equal(named(sheet, "hxrrc_progress_status"), nil, "status is removed after job ends")
    end)

    H.test(shape .. " PSL-02 legacy sheet gets status when a job shows", function()
        local world = H.new_world(shape)
        world.add_item("ore"); world.add_item("plate")
        world.add_machine({name="furnace", categories={"smelting"}, speed=1})
        world.add_recipe({name="plate", category="smelting", ingredients={{name="ore", amount=1}}, products={{name="plate", amount=1}}})
        world.add_player(1); world.init(); require "control"; world.handlers.on_init()
        local sheet = storage[1].sheet_section.sheet_pane.tabs[1].content
        H.legacy_save(sheet)
        local controls = sheet.hxrrc_sheet_controls
        controls.export_cell.destroy(); controls.blueprint_cell.destroy()
        controls.progress_cell.destroy(); controls.cancel_cell.destroy()
        require("gui.sheet").add_missing_controls(sheet.parent)
        local ProgressPanel = require "gui.progress_panel"
        ProgressPanel.update(sheet, {kind="blueprint", stage_key="pack", attempt=1, attempts=3, fraction=.4})
        local status = named(sheet, "hxrrc_progress_status")
        H.equal(status ~= nil, true, "legacy sheet has status")
        H.equal(status:get_index_in_parent(), sheet.hxrrc_sheet_controls:get_index_in_parent()+1, "status follows controls grid")
    end)
end
H.done("test_progress_status_line")
