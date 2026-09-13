local Report = require "gui.report"
local Solver = require "logic.solver"
local InputContainer = require "gui.input_container"
local compute_power_and_pollution = require "logic.compute_power_and_pollution"

local Sheet = {}

local function update_sheet_title(sheet_pane, sheet_index)
    local sheet_and_flow = sheet_pane.tabs[sheet_index]
    local item_name = sheet_and_flow.content.input_container.children[1].hxrrc_desired_item_button.elem_value
    sheet_and_flow.tab.caption = item_name and prototypes.item[item_name].localised_name or {"hxrrc.empty_sheet"}
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
    add_compute_button(sheet_flow)

    --Output section:
    local output_flow = sheet_flow.add{type = "flow", name = "output_flow"}
    output_flow.style.horizontally_stretchable = true
    output_flow.style.vertically_stretchable = true
end

function Sheet.delete_selected_sheet(sheet_pane)
    if #sheet_pane.tabs > 1 then
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

    update_sheet_title(sheet_pane, sheet_index)

    local production_rates_by_product_full_name = InputContainer.get_desired_production_rates_by_full_item_name(sheet_flow.input_container)

    if not production_rates_by_product_full_name then --Empty sheet
        sheet_flow.output_flow.clear()
        return
    end

    local recipe_rates_by_recipe_name, solved_rates_by_product_full_name, unsolved_rates_by_product_full_name = Solver.solve_for(production_rates_by_product_full_name, sheet_flow.player_index)
    if not recipe_rates_by_recipe_name then
        --Matrix unsolved
        game.get_player(sheet_flow.player_index).create_local_flying_text{text = {"hxrrc.system_with_no_solution_error"}, create_at_cursor = true}
        return
    end

    local energy_consumption, pollution = compute_power_and_pollution(sheet_flow.player_index, recipe_rates_by_recipe_name)
    
    local output_flow = sheet_flow.output_flow
    output_flow.clear()
    Report.new(output_flow, recipe_rates_by_recipe_name, solved_rates_by_product_full_name, unsolved_rates_by_product_full_name, energy_consumption, pollution)
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

return Sheet