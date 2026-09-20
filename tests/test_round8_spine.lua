--The spine: the controls, ids and hooks round 8 lanes build on, and the promise that nothing else moved yet
local H = require "tests.harness"

local function sheet_world(shape)
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate")
    world.add_machine({name = "furnace", categories = {"smelting"}, speed = 2})
    world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}},
        products = {{name = "plate", amount = 1}}})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " SP1 a new sheet carries the four round 8 controls, each in its own cell", function()
        local world = sheet_world(shape)
        local Sheet = require "gui.sheet"
        local _, sheet_flow = H.fill_sheet({})

        local export = Sheet.export_button_of(sheet_flow)
        H.equal(export.name, "hxrrc_export_button", "the export button is there")
        H.equal(export.caption[1], "hxrrc.export_button_caption", "with its caption")
        H.equal(export.tooltip[1], "hxrrc.export_button_tooltip", "and its tooltip")
        H.equal(Sheet.blueprint_button_of(sheet_flow).name, "hxrrc_generate_blueprint_button", "the blueprint button is there")

        local bar = Sheet.progressbar_of(sheet_flow)
        H.equal(bar.type, "progressbar", "the progress bar is a progressbar")
        H.equal(bar.value, 0, "it starts empty")
        H.equal(bar.visible, false, "and hidden until work runs")
        H.equal(Sheet.cancel_button_of(sheet_flow).visible, false, "Cancel is hidden with it")
    end)

    H.test(shape .. " SP2 a sheet saved before round 8 gains the cells without losing its state", function()
        local world = sheet_world(shape)
        local Sheet = require "gui.sheet"
        local sheet_pane, sheet_flow = H.fill_sheet({})
        Sheet.round_up_checkbox_of(sheet_flow).state = true

        --an older layout: the grid without any of the round 8 cells
        local controls = sheet_flow.hxrrc_sheet_controls
        for _, name in ipairs({"export_cell", "blueprint_cell", "progress_cell", "cancel_cell"}) do
            controls[name].destroy()
        end
        H.equal(Sheet.export_button_of(sheet_flow), nil, "the older sheet has no export button")

        Sheet.add_missing_controls(sheet_pane)

        H.equal(Sheet.export_button_of(sheet_flow).name, "hxrrc_export_button", "repair adds the export button")
        H.equal(Sheet.blueprint_button_of(sheet_flow).name, "hxrrc_generate_blueprint_button", "and the blueprint button")
        H.equal(Sheet.progressbar_of(sheet_flow).type, "progressbar", "and the bar")
        H.equal(Sheet.cancel_button_of(sheet_flow).name, "hxrrc_cancel_button", "and Cancel")
        H.equal(Sheet.round_up_checkbox_of(sheet_flow).state, true, "the checkbox kept its state")
        H.equal(Sheet.compute_button_of(sheet_flow).name, "hxrrc_compute_button", "Compute survived the repair")
    end)

    H.test(shape .. " SP3 repairing twice adds nothing, which the engine would refuse", function()
        local world = sheet_world(shape)
        local Sheet = require "gui.sheet"
        local sheet_pane, sheet_flow = H.fill_sheet({})
        local before = #sheet_flow.hxrrc_sheet_controls.children
        Sheet.add_missing_controls(sheet_pane)
        Sheet.add_missing_controls(sheet_pane)
        H.equal(#sheet_flow.hxrrc_sheet_controls.children, before, "the cell count did not grow")
    end)

    H.test(shape .. " SP4 every sheet has its own stable id", function()
        local world = sheet_world(shape)
        local Sheet = require "gui.sheet"
        local sheet_pane = H.fill_sheet({})
        local first = Sheet.id_of(sheet_pane.tabs[1].content)
        H.equal(type(first), "string", "a sheet has an id")
        Sheet.new(sheet_pane)
        local second = Sheet.id_of(sheet_pane.tabs[2].content)
        H.equal(second ~= first, true, "a second sheet gets a different id")
        Sheet.add_missing_controls(sheet_pane)
        H.equal(Sheet.id_of(sheet_pane.tabs[1].content), first, "repair does not renumber an existing sheet")
    end)

    H.test(shape .. " SP5 reading a sheet's inputs neither solves nor writes", function()
        local world = sheet_world(shape)
        local Sheet = require "gui.sheet"
        local _, sheet_flow = H.fill_sheet({{item = "plate", rate = 30, unit = "/m"}})

        local inputs = Sheet.read_inputs(sheet_flow)
        H.equal(inputs.empty, false, "the sheet has a target")
        H.near(inputs.rates["item/plate"], 0.5, "30 a minute is half a second")
        H.equal(inputs.options.round_up, false, "the round-up setting comes along")
        H.equal(inputs.options.start_leftovers, "byproduct", "so does the leftovers choice")
        H.equal(type(inputs.sheet_id), "string", "and the sheet's id")
        H.equal(#sheet_flow.output_flow.children, 0, "reading built no report")
    end)

    H.test(shape .. " SP6 the old entry point still solves and shows a report", function()
        local world = sheet_world(shape)
        local Sheet = require "gui.sheet"
        local report, sheet_pane = H.run_sheet({{item = "plate", rate = 1, unit = "/s"}})
        local sheet_flow = sheet_pane.tabs[1].content
        H.near(report.rows["item/ore"].rate, 1, "the ore demand is solved")
        H.near(report.rows["item/plate"].machines, 0.5, "and the machine count")
        H.equal(#sheet_flow.output_flow.children > 0, true, "a report is on screen")
    end)

    H.test(shape .. " SP7 the scheduler and the reset action are wired, and the third job id is free", function()
        local world = sheet_world(shape)
        require "control"
        H.equal(type(async_calls[3]), "function", "a third async call id exists for jobs")
        H.equal(type(event_handlers.on_gui_click.hxrrc_export_button), "function", "the export button has a handler")
        H.equal(type(event_handlers.on_gui_click.hxrrc_generate_blueprint_button), "function", "so does the blueprint button")
        H.equal(type(event_handlers.on_gui_click.hxrrc_cancel_button), "function", "so does Cancel")
        H.equal(type(event_handlers.on_gui_click.hxrrc_reset_setups_button), "function", "so does the reset action")
        --the stubs do nothing yet, and a tick with them wired must still be quiet
        H.run_ticks(world, 3)
    end)

    H.test(shape .. " SP8 the build identity of a source checkout can never pass as a release candidate", function()
        local world = sheet_world(shape)
        local EngineTestApi = require "logic.engine_test_api"
        local build = EngineTestApi.build_id()
        --Same rule in both trees: a checkout claims nothing, a package names exactly what it was built from.
        if build.packaged then
            H.equal(type(build.candidate_sha) == "string" and #build.candidate_sha == 40, true,
                "a packaged tree names its candidate, saw " .. tostring(build.candidate_sha))
            H.equal(build.candidate_sha ~= "dev", true, "a package never reports the checkout identity")
        else
            H.equal(build.packaged, false, "a checkout is not packaged")
            H.equal(build.candidate_sha, "dev", "and names no candidate")
        end
    end)
end

H.done("test_round8_spine")
