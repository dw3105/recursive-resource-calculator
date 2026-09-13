--Sheet inputs: empty sheets, the same item entered in several rows, fluid targets
local H = require "tests.harness"

local function gear_world(shape)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.init()
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B5 a sheet with no targets clears its output", function()
        gear_world(shape)
        local report = H.run_sheet({})
        H.equal(report, nil, "report on empty sheet")
    end)

    H.test(shape .. " B13 V9 the same item in two rows is summed across time units", function()
        gear_world(shape)
        local report = H.run_sheet({{item = "gear", rate = 60, unit = "/m"}, {item = "gear", rate = 2, unit = "/s"}})
        H.near(report.rows["item/gear"].rate, 3, "gear rate")
        H.near(report.rows["item/raw"].rate, 3, "raw demand")
    end)
end

--Gear world plus a fluid made from raw: 1 raw gives 10 lube per craft
local function lube_world(shape)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_fluid("lube")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_recipe({name = "lube", category = "crafting", energy = 1, ingredients = {{name = "raw", amount = 1}},
        products = {{type = "fluid", name = "lube", amount = 10}}})
    world.add_player(1)
    world.init()
    return world
end

local function new_sheet_pane()
    local sheet_pane = H.gui_root({type = "tabbed-pane", name = "sheet_pane"}, 1)
    require("gui.sheet").new(sheet_pane)
    sheet_pane.selected_tab_index = 1
    return sheet_pane
end

local function children_named(element, name)
    local found = {}
    for index, child in ipairs(element.children) do
        if child.name == name then found[#found + 1] = index end
    end
    return found
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " G1a a fluid target is solved like an item target", function()
        lube_world(shape)
        local report = H.run_sheet({{fluid = "lube", rate = 20, unit = "/s"}})
        assert(report, "no report")
        H.near(report.rows["fluid/lube"].rate, 20, "lube rate")
        H.near(report.rows["fluid/lube"].machines, 2, "lube crafts")
        H.near(report.rows["item/raw"].rate, 2, "raw demand")
    end)

    H.test(shape .. " G1b picking a fluid clears the item of its row and the reverse, even when writes re-fire", function()
        lube_world(shape)
        local input_container = new_sheet_pane().tabs[1].content.input_container
        H.refire_on_script_set = true --each write below stands for one player action and raises its handler once
        local row = input_container.children[1]
        row.hxrrc_desired_item_button.elem_value = "gear"
        H.equal(#input_container.children, 2, "rows after the first item")
        row.hxrrc_desired_fluid_button.elem_value = "lube"
        H.equal(row.hxrrc_desired_item_button.elem_value, nil, "item cleared by fluid")
        H.equal(row.hxrrc_desired_fluid_button.elem_value, "lube", "fluid kept")
        H.equal(#input_container.children, 2, "row kept when its item is cleared")
        row.hxrrc_desired_item_button.elem_value = "gear"
        H.equal(row.hxrrc_desired_fluid_button.elem_value, nil, "fluid cleared by item")
        H.equal(row.hxrrc_desired_item_button.elem_value, "gear", "item kept")
        H.equal(#input_container.children, 2, "rows after switching back")
        row.hxrrc_desired_fluid_button.elem_value = "lube"
        row.hxrrc_desired_fluid_button.elem_value = nil
        H.equal(#input_container.children, 1, "emptied non-last row destroyed")
        H.equal(input_container.children[1].hxrrc_desired_item_button.elem_value, nil, "remaining row is the empty one")
    end)

    H.test(shape .. " G1c a target whose fluid was removed by a mod is left out", function()
        lube_world(shape)
        local sheet_pane, sheet_flow = H.fill_sheet({{fluid = "lube", rate = 20, unit = "/s"}, {item = "gear", rate = 1, unit = "/s"}})
        prototypes.fluid.lube = nil
        local rates = require("gui.input_container").get_desired_production_rates_by_full_item_name(sheet_flow.input_container)
        H.equal(rates["fluid/lube"], nil, "removed fluid rate")
        H.near(rates["item/gear"], 1, "gear rate kept")
        require("gui.sheet").calculate(sheet_flow.hxrrc_compute_button)
        local report = H.parse_report(sheet_flow.output_flow)
        assert(report, "no report")
        assert(report.rows["item/gear"], "gear row missing")
        H.equal(report.rows["fluid/lube"], nil, "removed fluid row")
    end)

    H.test(shape .. " G1d a sheet whose first target is a fluid is titled after the fluid", function()
        lube_world(shape)
        local _, sheet_pane = H.run_sheet({{fluid = "lube", rate = 20, unit = "/s"}})
        H.equal(sheet_pane.tabs[1].tab.caption[1], "fluid-name.lube", "tab title")
    end)

    H.test(shape .. " G1e rows saved without a fluid button get exactly one on configuration change", function()
        local world = lube_world(shape)
        require "control"
        world.handlers.on_init()
        local input_container = storage[1].sheet_section.sheet_pane.tabs[1].content.input_container
        input_container.children[1].hxrrc_desired_item_button.elem_value = "gear"
        event_handlers.on_gui_elem_changed["hxrrc_desired_item_button"]({element = input_container.children[1].hxrrc_desired_item_button, player_index = 1})
        for _, row in ipairs(input_container.children) do --what a 1.1.11 save holds
            for index = #row.children, 1, -1 do
                if row.children[index].name == "hxrrc_desired_fluid_button" then row.children[index].destroy() end
            end
        end
        for _ = 1, 2 do
            world.handlers.on_configuration_changed({mod_changes = {}})
            while storage.computation_stack[1] do world.handlers.events[defines.events.on_tick]({tick = 0}) end
        end
        H.equal(#input_container.children, 2, "rows")
        for row_index, row in ipairs(input_container.children) do
            local found = children_named(row, "hxrrc_desired_fluid_button")
            H.equal(#found, 1, "fluid buttons in row " .. row_index)
            H.equal(found[1], 4, "fluid button position in row " .. row_index)
        end
        local last_row = input_container.children[2]
        last_row.rate_textfield.text = "20"
        last_row.time_unit_dropdown.selected_index = 2
        last_row.hxrrc_desired_fluid_button.elem_value = "lube"
        local sheet_flow = storage[1].sheet_section.sheet_pane.tabs[1].content
        require("gui.sheet").calculate(sheet_flow.hxrrc_compute_button)
        local report = H.parse_report(sheet_flow.output_flow)
        assert(report and report.rows["fluid/lube"], "no lube row after repair")
        H.near(report.rows["fluid/lube"].rate, 20, "repaired row computes")
    end)
end

H.done("test_input")
