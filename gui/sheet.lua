local Report = require "gui.report"
local Solver = require "logic.solver"
local InputContainer = require "gui.input_container"
local compute_power_and_pollution = require "logic.compute_power_and_pollution"
local QualityLoops = require "logic.quality_loops"
local Utils = require "logic.utils"
local ModulePicker = require "gui.module_picker"

local Sheet = {}

local function update_sheet_title(sheet_pane, sheet_index)
    local sheet_and_flow = sheet_pane.tabs[sheet_index]
    local first_row = sheet_and_flow.content.input_container.children[1]
    local item = first_row.hxrrc_desired_item_button.elem_value
    local item_name = item and item.name
    local fluid_name = first_row.hxrrc_desired_fluid_button.elem_value
    --nil once the mod adding the item or fluid is removed
    local prototype = (item_name and prototypes.item[item_name]) or (fluid_name and prototypes.fluid[fluid_name])
    sheet_and_flow.tab.caption = prototype and prototype.localised_name or {"hxrrc.empty_sheet"}
end

local function add_round_up_checkbox(sheet_flow, index)
    sheet_flow.add{
        type = "checkbox",
        name = "hxrrc_round_up_machines_checkbox",
        caption = {"hxrrc.round_up_machines"},
        tooltip = {"hxrrc.round_up_machines_tooltip"},
        state = false,
        index = index,
    }
end

--The sheet's choice for items quality loops return at their start quality when the start recipe takes no items (Factorio 2.0 only)
local START_LEFTOVER_MODES = {"byproduct", "craft", "recycle"}

--The row's layout: label and drop-down side by side, centered like the checkbox and the compute button. Also applied to rows built before 1.1.27.
local function style_start_leftovers_row(row)
    row.style.horizontally_stretchable = true
    row.style.vertical_align = "center"
    row.style.horizontal_align = "center"
    row.style.horizontal_spacing = 8
end

--A row of label and drop-down, hidden until the sheet targets an item above normal quality (only then can a loop use the choice)
local function add_start_leftovers_row(sheet_flow, index)
    local row = sheet_flow.add{type = "flow", name = "hxrrc_start_leftovers_row", direction = "horizontal", index = index, visible = false}
    style_start_leftovers_row(row)
    row.add{type = "label", caption = {"hxrrc.start_leftovers_caption"}, tooltip = {"hxrrc.start_leftovers_tooltip"}}
    row.add{
        type = "drop-down",
        name = "hxrrc_start_leftovers_dropdown",
        tooltip = {"hxrrc.start_leftovers_tooltip"},
        items = {{"hxrrc.start_leftovers_byproduct"}, {"hxrrc.start_leftovers_craft"}, {"hxrrc.start_leftovers_recycle"}},
        selected_index = 1,
    }
    return row
end

--The row found by name among the children: 2.1 sheets have none, and a sheet saved by 1.1.23 has a flat drop-down until repaired
local function start_leftovers_row_of(sheet_flow)
    for _, child in ipairs(sheet_flow.children) do
        if child.name == "hxrrc_start_leftovers_row" then return child end
    end
end

--Shows the row only while the sheet has a target above normal quality; the hidden row keeps its choice
function Sheet.update_start_leftovers_visibility(sheet_flow)
    local row = start_leftovers_row_of(sheet_flow)
    if row then
        row.visible = InputContainer.has_quality_target(sheet_flow.input_container)
    end
end

local function add_compute_button(sheet_flow)
    sheet_flow.add{
        type = "button",
        name = "hxrrc_compute_button",
        caption = {"hxrrc.compute_button_caption"},
    }
end

function Sheet.new(sheet_pane)
    local sheet = sheet_pane.add{type = "tab", caption = {"hxrrc.empty_sheet"}}
    local sheet_flow = sheet_pane.add{type = "flow", direction = "vertical"}
    sheet_pane.add_tab(sheet, sheet_flow)

    sheet_flow.style.horizontal_align = "center"

    --Input section:
    InputContainer.build_and_add_to(sheet_flow)
    add_round_up_checkbox(sheet_flow)
    if not Utils.IS_2_1 then
        add_start_leftovers_row(sheet_flow)
    end
    add_compute_button(sheet_flow)

    --Output section:
    local output_flow = sheet_flow.add{type = "flow", name = "output_flow"}
    output_flow.style.horizontally_stretchable = true
    output_flow.style.vertically_stretchable = true
end

function Sheet.delete_selected_sheet(sheet_pane)
    if #sheet_pane.tabs > 1 then
        ModulePicker.close(sheet_pane.player_index, true) --its slot may be on the sheet going away
        local tab_and_sheet = sheet_pane.tabs[sheet_pane.selected_tab_index]
        sheet_pane.remove_tab(tab_and_sheet.tab)
        tab_and_sheet.tab.destroy()

        local sheet_flow = tab_and_sheet.content
        sheet_flow.destroy()

        sheet_pane.selected_tab_index = 1
    else
        game.get_player(sheet_pane.player_index).create_local_flying_text{text = {"hxrrc.cannot_remove_all_sheets_error"}, create_at_cursor = true}
    end
end

--Performs the calculator computation for the sheet that either owns the passed compute_button or belongs to the given sheet_pane and has the given sheet_index (if compute_button is not nil, the two other arguments are ignored; if it is nil, the other two arguments are used and thus must be specified)
function Sheet.calculate(compute_button, sheet_pane, sheet_index)
    local sheet_flow
    if compute_button then
        sheet_flow = compute_button.parent
        sheet_pane = sheet_flow.parent
        sheet_index = sheet_pane.selected_tab_index
    else
        local sheet_and_flow = sheet_pane.tabs[sheet_index]
        sheet_flow = sheet_and_flow.content
    end

    --the sheet's report is cleared below, on every path, so a picker for one of its slots goes first
    ModulePicker.close(sheet_flow.player_index, true)
    update_sheet_title(sheet_pane, sheet_index)

    local production_rates_by_product_full_name, product_parts = InputContainer.get_desired_production_rates_by_full_item_name(sheet_flow.input_container)

    if next(production_rates_by_product_full_name) == nil then --Empty sheet
        sheet_flow.output_flow.clear()
        return
    end

    local mode = "byproduct"
    for _, child in ipairs(sheet_flow.children) do --found by name among the children: absent on 2.1 sheets; read whether the row is shown or not
        if child.name == "hxrrc_start_leftovers_dropdown" then
            mode = START_LEFTOVER_MODES[child.selected_index] or mode
        elseif child.name == "hxrrc_start_leftovers_row" then
            mode = START_LEFTOVER_MODES[child.hxrrc_start_leftovers_dropdown.selected_index] or mode
        end
    end
    local result = Solver.solve_for(production_rates_by_product_full_name, sheet_flow.player_index, product_parts, {start_leftovers = mode})

    --every loop the solve used keeps exactly the configuration it was solved with (new, unchanged or repaired), before power and the report read it
    for _, column in ipairs(result.columns) do
        if column.quality_loop and column.quality_loop.config then
            QualityLoops.store(sheet_flow.player_index, column.quality_loop.key, column.quality_loop.config)
        end
    end

    --the previous report goes in every case, so no totals or controls of an earlier state stay on screen
    local output_flow = sheet_flow.output_flow
    output_flow.clear()

    if result.status == "unsolvable" then
        game.get_player(sheet_flow.player_index).create_local_flying_text{text = {"hxrrc.system_with_no_solution_error"}, create_at_cursor = true}
    end

    if not result.recipe_rates then
        Report.new_diagnostic(output_flow, result)
        return
    end

    --totals only for a result whose every rate is usable
    local energy_consumption, pollution
    if result.status == "ok" then
        energy_consumption, pollution = compute_power_and_pollution(sheet_flow.player_index, result.columns, result.recipe_rates)
    end
    Report.new(output_flow, result, energy_consumption, pollution, sheet_flow.hxrrc_round_up_machines_checkbox.state)
end

--Adds controls that sheets saved by older versions lack; finds them by name (the engine returns nil for a missing child), so it is safe on every configuration change
function Sheet.add_missing_controls(sheet_pane)
    for _, tab_and_content in ipairs(sheet_pane.tabs) do
        local sheet_flow = tab_and_content.content
        InputContainer.repair_rows(sheet_flow.input_container)

        local compute_button_index, has_round_up_checkbox, flat_dropdown, row
        for index, child in ipairs(sheet_flow.children) do
            if child.name == "hxrrc_compute_button" then compute_button_index = index end
            if child.name == "hxrrc_round_up_machines_checkbox" then has_round_up_checkbox = true end
            if child.name == "hxrrc_start_leftovers_dropdown" then flat_dropdown = child end
            if child.name == "hxrrc_start_leftovers_row" then row = child end
        end
        if compute_button_index and not has_round_up_checkbox then
            add_round_up_checkbox(sheet_flow, compute_button_index)
            compute_button_index = compute_button_index + 1
        end
        if not Utils.IS_2_1 then
            if flat_dropdown then
                --1.1.23 kept the drop-down itself in the sheet: the row takes its place and its choice
                local selected_index = flat_dropdown.selected_index
                local index = flat_dropdown.get_index_in_parent()
                flat_dropdown.destroy()
                add_start_leftovers_row(sheet_flow, index).hxrrc_start_leftovers_dropdown.selected_index = selected_index
            elseif row then
                --1.1.25 put a stretching spacer between the label and the drop-down; the drop-down and its choice stay
                for index = #row.children, 1, -1 do
                    if row.children[index].type == "empty-widget" then row.children[index].destroy() end
                end
                style_start_leftovers_row(row)
            elseif compute_button_index then
                add_start_leftovers_row(sheet_flow, compute_button_index)
            end
        end
        Sheet.update_start_leftovers_visibility(sheet_flow)
    end
end

--GUI change added in 1.1.0: the sheets' input flow element was replaced with a new input container that supports multiple desired items with their respective production rates.
--Note: Before 1.0.6 time_unit_dropdown elements did not exist
function Sheet._repair_old_sheets()
    for player_index, _ in pairs(game.players) do
        for _, tab_and_contents in ipairs(storage[player_index].sheet_section.sheet_pane.tabs) do
            local sheet_flow = tab_and_contents.content
            local old_input_flow = sheet_flow.input_flow

            local rate_text = old_input_flow.hxrrc_input_textfield.text
            local old_time_unit_dropdown = old_input_flow.hxrrc_time_unit_dropdown
            local selected_index = old_time_unit_dropdown and old_time_unit_dropdown.selected_index or 2
            local item = old_input_flow.item_input_button.elem_value

            old_input_flow.destroy()

            local input_container = InputContainer.build_and_add_to(sheet_flow)
            InputContainer._add_existing_row(input_container, rate_text, selected_index, item)

            add_compute_button(sheet_flow)

            sheet_flow.swap_children(1, 2)
            sheet_flow.swap_children(2, 3)
        end
    end
end

event_handlers.on_gui_click["hxrrc_compute_button"] = function(event)
    Sheet.calculate(event.element)
    storage[event.player_index].calculator.force_auto_center()
end

--Recomputes only the sheet owning the drop-down; nothing here writes the selection, so the event cannot loop
event_handlers.on_gui_selection_state_changed["hxrrc_start_leftovers_dropdown"] = function(event)
    local parent = event.element.parent
    local sheet_flow = parent.name == "hxrrc_start_leftovers_row" and parent.parent or parent --an unrepaired 1.1.23 drop-down sits in the sheet itself
    Sheet.calculate(sheet_flow.hxrrc_compute_button)
    storage[event.player_index].calculator.force_auto_center()
end

--Recomputes only the sheet owning the checkbox; nothing here writes the state, so the event cannot loop
event_handlers.on_gui_checked_state_changed["hxrrc_round_up_machines_checkbox"] = function(event)
    Sheet.calculate(event.element.parent.hxrrc_compute_button)
    storage[event.player_index].calculator.force_auto_center()
end

--input_container must not require the sheet back, so the sheet hands it the update to run when a target changes
InputContainer.on_target_changed = Sheet.update_start_leftovers_visibility

return Sheet