--Round-up checkbox: whole machine counts on labels only, per sheet, on old saves, at zero and at huge counts
local H = require "tests.harness"

local function gear_world(shape, energy, speed)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = speed or 1})
    world.add_recipe({name = "gear", category = "crafting", energy = energy or 1, ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.init()
    return world
end

local function control_gear_world(shape)
    local world = gear_world(shape)
    require "control"
    world.handlers.on_init()
    return world
end

local function drain_ticks(world)
    while storage.computation_stack[1] do world.handlers.events[defines.events.on_tick]({tick = 0}) end
end

--Types a gear target into the first row of the sheet at sheet_index, as a player would
local function type_gear_target(sheet_pane, sheet_index, rate)
    local row = sheet_pane.tabs[sheet_index].content.input_container.children[1]
    row.rate_textfield.text = rate
    row.time_unit_dropdown.selected_index = 2
    row.hxrrc_desired_item_button.elem_value = {name = "gear"}
    event_handlers.on_gui_elem_changed["hxrrc_desired_item_button"]({element = row.hxrrc_desired_item_button, player_index = 1})
end

local function sheet_report(sheet_pane, sheet_index)
    return H.parse_report(sheet_pane.tabs[sheet_index].content.output_flow)
end

local function child_indexes(element, name)
    local found = {}
    for index, child in ipairs(element.children) do
        if child.name == name then found[#found + 1] = index end
    end
    return found
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " G6a round-up changes the machine label only", function()
        gear_world(shape)
        local off = H.run_sheet({{item = "gear", rate = 2.4, unit = "/s"}})
        H.near(off.rows["item/gear"].machines, 2.4, "machines when off")
        H.equal(off.rows["item/gear"].machine_tooltip, nil, "no tooltip when off")
        gear_world(shape)
        local on = H.run_sheet({{item = "gear", rate = 2.4, unit = "/s"}}, 1, {round_up = true})
        H.equal(on.rows["item/gear"].machine_caption, " x 3", "caption when on")
        H.near(tonumber(on.rows["item/gear"].machine_tooltip), 2.4, "exact count in tooltip")
        H.near(on.energy_mw, off.energy_mw, "energy unchanged by rounding")
        H.near(on.pollution_per_minute, off.pollution_per_minute, "pollution unchanged by rounding")
        H.near(on.rows["item/gear"].rate, off.rows["item/gear"].rate, "rate unchanged by rounding")
    end)

    H.test(shape .. " G6b rounding noise just above a whole count does not add a machine", function()
        gear_world(shape, 1.1, 0.5)
        local report = H.run_sheet({{item = "gear", rate = 25, unit = "/s"}}, 1, {round_up = true})
        H.equal(report.rows["item/gear"].machine_caption, " x 55", "25 * 1.1 / 0.5")
    end)

    H.test(shape .. " G6c toggling a sheet's checkbox recomputes that sheet only", function()
        local world = control_gear_world(shape)
        local Sheet = require "gui.sheet"
        local sheet_pane = storage[1].sheet_section.sheet_pane
        Sheet.new(sheet_pane)
        for sheet_index = 1, 2 do
            type_gear_target(sheet_pane, sheet_index, "2.4")
            Sheet.calculate(nil, sheet_pane, sheet_index)
        end
        sheet_pane.selected_tab_index = 2
        local checkbox = sheet_pane.tabs[2].content.hxrrc_round_up_machines_checkbox
        checkbox.state = true
        world.handlers.events[defines.events.on_gui_checked_state_changed]({element = checkbox, player_index = 1})
        H.equal(sheet_report(sheet_pane, 2).rows["item/gear"].machine_caption, " x 3", "toggled sheet")
        H.near(sheet_report(sheet_pane, 1).rows["item/gear"].machines, 2.4, "other sheet")
        H.equal(sheet_report(sheet_pane, 1).rows["item/gear"].machine_tooltip, nil, "other sheet not rounded")
    end)

    H.test(shape .. " G6d sheets saved without the checkbox get exactly one on configuration change", function()
        local world = control_gear_world(shape)
        local sheet_pane = storage[1].sheet_section.sheet_pane
        local sheet_flow = sheet_pane.tabs[1].content
        for index = #sheet_flow.children, 1, -1 do --what a 1.1.11 save holds
            if sheet_flow.children[index].name == "hxrrc_round_up_machines_checkbox" then sheet_flow.children[index].destroy() end
        end
        for _ = 1, 2 do
            world.handlers.on_configuration_changed({mod_changes = {}})
            drain_ticks(world)
        end
        local checkboxes = child_indexes(sheet_flow, "hxrrc_round_up_machines_checkbox")
        H.equal(#checkboxes, 1, "checkboxes")
        H.equal(checkboxes[1] + 1, child_indexes(sheet_flow, "hxrrc_compute_button")[1], "checkbox right before Compute")
        H.equal(sheet_flow.hxrrc_round_up_machines_checkbox.state, false, "repaired checkbox starts off")
        type_gear_target(sheet_pane, 1, "2.4")
        sheet_flow.hxrrc_round_up_machines_checkbox.state = true
        require("gui.sheet").calculate(sheet_flow.hxrrc_compute_button)
        H.equal(sheet_report(sheet_pane, 1).rows["item/gear"].machine_caption, " x 3", "repaired sheet rounds")
    end)

    H.test(shape .. " G6e a zero machine count reads 0", function()
        local world = H.new_world(shape)
        world.add_item("p")
        world.add_item("q")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "p-maker", category = "crafting", ingredients = {}, products = {{name = "p", amount = 1}}})
        world.add_recipe({name = "q-maker", category = "crafting", ingredients = {}, products = {{name = "q", amount = 1}, {name = "p", amount = 1}}})
        world.add_player(1)
        world.init()
        world.bind("item/p", "p-maker")
        world.bind("item/q", "q-maker")
        local report = H.run_sheet({{item = "p", rate = 1, unit = "/s"}, {item = "q", rate = 1, unit = "/s"}}, 1, {round_up = true})
        assert(report, "no report")
        H.equal(report.rows["item/p"].machine_caption, " x 0", "p-maker caption")
    end)

    --Solver side is a guard: the row order pairs() produces varies per process
    H.test(shape .. " G6f an order that fits the equations but not the machine count does not add a machine", function()
        local world = H.new_world(shape)
        for _, item in ipairs({"p", "q", "r"}) do world.add_item(item) end
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 0.1})
        world.add_recipe({name = "r1", category = "crafting", energy = 0.3, ingredients = {{name = "p", amount = 1}},
            products = {{name = "p", amount = 1}, {name = "q", amount = 1, p = 1e-5}, {name = "r", amount = 1}}})
        world.add_recipe({name = "r2", category = "crafting", energy = 0.3, ingredients = {},
            products = {{name = "p", amount = 1}, {name = "q", amount = 65535}, {name = "r", amount = 1000}}})
        world.add_recipe({name = "r3", category = "crafting", energy = 0.3, ingredients = {}, products = {{name = "p", amount = 1}, {name = "r", amount = 1000}}})
        world.add_player(1)
        world.init()
        world.bind("item/p", "r1")
        world.bind("item/q", "r2")
        world.bind("item/r", "r3")
        local report = H.run_sheet({{item = "p", rate = 2, unit = "/s"}, {item = "q", rate = 65535 + 1e-5, unit = "/s"}, {item = "r", rate = 2001, unit = "/s"}}, 1, {round_up = true})
        assert(report, "no report")
        for _, product in ipairs({"item/p", "item/q", "item/r"}) do
            H.equal(report.rows[product].machine_caption, " x 3", product .. " caption")
        end
    end)

    H.test(shape .. " G6h a machine count beyond integer range still renders", function()
        gear_world(shape)
        local report = H.run_sheet({{item = "gear", rate = 1e19, unit = "/s"}}, 1, {round_up = true})
        assert(report, "no report")
        H.equal(report.rows["item/gear"].machine_caption, " x 10000000000000000000", "caption")
    end)
end

H.test("G6g rounded counts keep float range, drop rounding noise and never read -0", function()
    H.new_world("2.0")
    local rounded_up_count_text = require("gui.report")._rounded_up_count_text
    H.equal(rounded_up_count_text(-0.0), "0", "negative zero")
    H.equal(rounded_up_count_text(1e19), "10000000000000000000", "beyond integer range")
    H.equal(rounded_up_count_text(25 * 1.1 / 0.5), "55", "noise above a whole count")
    H.equal(rounded_up_count_text(2.4), "3", "fraction")
end)

H.done("test_round_up")
