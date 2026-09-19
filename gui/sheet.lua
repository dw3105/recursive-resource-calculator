local Report = require "gui.report"
local Registry = require "logic.registry"
local Solver = require "logic.solver"
local InputContainer = require "gui.input_container"
local compute_power_and_pollution = require "logic.compute_power_and_pollution"
local QualityLoops = require "logic.quality_loops"
local Utils = require "logic.utils"
local ModulePicker = require "gui.module_picker"
local ExportDialog = require "gui.export_dialog"
local BlueprintDialog = require "gui.blueprint_dialog"
local ProgressPanel = require "gui.progress_panel"

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

--The sheet's choice for items quality loops return at their start quality when the start recipe takes no items (Factorio 2.0 only)
local START_LEFTOVER_MODES = {"byproduct", "craft", "recycle"}

local CONTROLS_NAME = "hxrrc_sheet_controls"

--The sheet's controls as a two-column grid the sheet centers: base-quality label | drop-down (Factorio 2.0 only), round-up checkbox | Compute.
--The first column aligns right and the second left, so the two rows line up. Every control sits in a cell flow that always exists: only the
--contents are hidden, never a cell, so the grid keeps its columns. state: {round_up, selected_index}, carried over from an older layout.
local function add_sheet_controls(sheet_flow, index, state)
    state = state or {}
    local controls = sheet_flow.add{type = "table", name = CONTROLS_NAME, column_count = 2, index = index}
    controls.style.horizontal_spacing = 8
    --column_alignments is read-only; its entries are written by index
    controls.style.column_alignments[1] = "middle-right"
    controls.style.column_alignments[2] = "middle-left"
    local function cell(name)
        local flow = controls.add{type = "flow", name = name, direction = "horizontal"}
        flow.style.vertical_align = "center"
        return flow
    end
    if not Utils.IS_2_1 then
        cell("start_leftovers_label_cell").add{type = "label", name = "hxrrc_start_leftovers_label", caption = {"hxrrc.start_leftovers_caption"},
            tooltip = {"hxrrc.start_leftovers_tooltip"}, visible = false}
        cell("start_leftovers_dropdown_cell").add{
            type = "drop-down",
            name = "hxrrc_start_leftovers_dropdown",
            tooltip = {"hxrrc.start_leftovers_tooltip"},
            items = {{"hxrrc.start_leftovers_byproduct"}, {"hxrrc.start_leftovers_craft"}, {"hxrrc.start_leftovers_recycle"}},
            selected_index = START_LEFTOVER_MODES[state.selected_index] and state.selected_index or 1,
            visible = false,
        }
    end
    cell("round_up_cell").add{
        type = "checkbox",
        name = "hxrrc_round_up_machines_checkbox",
        caption = {"hxrrc.round_up_machines"},
        tooltip = {"hxrrc.round_up_machines_tooltip"},
        state = state.round_up == true,
    }
    cell("compute_cell").add{type = "button", name = "hxrrc_compute_button", caption = {"hxrrc.compute_button_caption"}}
    --Round 8. Each control gets its own cell flow: the engine refuses two children of one parent sharing a name,
    --and a hidden cell would collapse the column, so cells always exist and only their contents are hidden.
    cell("export_cell").add{type = "button", name = "hxrrc_export_button", caption = {"hxrrc.export_button_caption"},
        tooltip = {"hxrrc.export_button_tooltip"}}
    cell("blueprint_cell").add{type = "button", name = "hxrrc_generate_blueprint_button", caption = {"hxrrc.blueprint_button_caption"},
        tooltip = {"hxrrc.blueprint_button_tooltip"}}
    cell("progress_cell").add{type = "progressbar", name = "hxrrc_calc_progressbar", value = 0, visible = false}
    cell("cancel_cell").add{type = "button", name = "hxrrc_cancel_button", caption = {"hxrrc.calc_cancel"}, visible = false}
    return controls
end

--The round 8 controls, so a sheet saved by an older version can be repaired one cell at a time rather than rebuilt
local NEW_CELLS = {
    {cell = "export_cell", build = function(flow)
        flow.add{type = "button", name = "hxrrc_export_button", caption = {"hxrrc.export_button_caption"}, tooltip = {"hxrrc.export_button_tooltip"}}
    end},
    {cell = "blueprint_cell", build = function(flow)
        flow.add{type = "button", name = "hxrrc_generate_blueprint_button", caption = {"hxrrc.blueprint_button_caption"},
            tooltip = {"hxrrc.blueprint_button_tooltip"}}
    end},
    {cell = "progress_cell", build = function(flow)
        flow.add{type = "progressbar", name = "hxrrc_calc_progressbar", value = 0, visible = false}
    end},
    {cell = "cancel_cell", build = function(flow)
        flow.add{type = "button", name = "hxrrc_cancel_button", caption = {"hxrrc.calc_cancel"}, visible = false}
    end},
}

--The grid of a sheet, found by name among its children (nil on a sheet saved before 1.1.31 until repaired)
local function controls_of(sheet_flow)
    for _, child in ipairs(sheet_flow.children) do
        if child.name == CONTROLS_NAME then return child end
    end
end

--The sheet flow owning an element: the ancestor whose parent is the sheet pane
function Sheet.sheet_flow_of(element)
    while element.parent and element.parent.type ~= "tabbed-pane" do
        element = element.parent
    end
    return element
end

function Sheet.compute_button_of(sheet_flow)
    return controls_of(sheet_flow).compute_cell.hxrrc_compute_button
end

function Sheet.round_up_checkbox_of(sheet_flow)
    return controls_of(sheet_flow).round_up_cell.hxrrc_round_up_machines_checkbox
end

--A control of the round 8 cells, or nil on a sheet not yet repaired
local function cell_child_of(sheet_flow, cell_name)
    local controls = controls_of(sheet_flow)
    for _, cell in ipairs(controls and controls.children or {}) do
        if cell.name == cell_name then return cell.children[1] end
    end
end

function Sheet.export_button_of(sheet_flow) return cell_child_of(sheet_flow, "export_cell") end
function Sheet.blueprint_button_of(sheet_flow) return cell_child_of(sheet_flow, "blueprint_cell") end
function Sheet.progressbar_of(sheet_flow) return cell_child_of(sheet_flow, "progress_cell") end
function Sheet.cancel_button_of(sheet_flow) return cell_child_of(sheet_flow, "cancel_cell") end

--The sheet's own identity, stable across a save: what a job, a snapshot and a stored blueprint setting are keyed by
function Sheet.id_of(sheet_flow)
    local tags = sheet_flow.tags
    return tags and tags.hxrrc_sheet_id or nil
end

--Gives a sheet flow an id if it has none. Tags read back as a copy, so the whole table is assigned, never a field.
local function ensure_sheet_id(sheet_flow)
    local tags = sheet_flow.tags or {}
    if tags.hxrrc_sheet_id then return tags.hxrrc_sheet_id end
    storage.next_sheet_id = (storage.next_sheet_id or 0) + 1
    tags.hxrrc_sheet_id = "sheet-" .. storage.next_sheet_id
    sheet_flow.tags = tags
    return tags.hxrrc_sheet_id
end
Sheet._ensure_sheet_id = ensure_sheet_id

--The base-quality drop-down, or nil on Factorio 2.1, where it is not built
local function start_leftovers_dropdown_of(sheet_flow)
    local controls = controls_of(sheet_flow)
    for _, cell in ipairs(controls and controls.children or {}) do
        if cell.name == "start_leftovers_dropdown_cell" then return cell.children[1] end
    end
end

--Shows the base-quality label and drop-down only while the sheet has a target above normal quality (only then can a loop use the choice); the
--hidden drop-down keeps its choice, and the cells stay
function Sheet.update_start_leftovers_visibility(sheet_flow)
    local controls = controls_of(sheet_flow)
    if not controls then
        return
    end
    local shown = InputContainer.has_quality_target(sheet_flow.input_container)
    for _, cell in ipairs(controls.children) do
        if cell.name == "start_leftovers_label_cell" or cell.name == "start_leftovers_dropdown_cell" then
            for _, child in ipairs(cell.children) do child.visible = shown end
        end
    end
end

--Only the pre-1.1.0 repair (Sheet._repair_old_sheets) still adds a lone Compute button; Sheet.add_missing_controls then moves it into the grid
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

    ensure_sheet_id(sheet_flow)

    --Input section:
    InputContainer.build_and_add_to(sheet_flow)
    add_sheet_controls(sheet_flow)

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
--The sheet flow the two calling conventions of Sheet.calculate name
local function sheet_flow_from(compute_button, sheet_pane, sheet_index)
    if compute_button then
        local sheet_flow = Sheet.sheet_flow_of(compute_button)
        return sheet_flow, sheet_flow.parent, sheet_flow.parent.selected_tab_index
    end
    return sheet_pane.tabs[sheet_index].content, sheet_pane, sheet_index
end

--What a sheet asks for, read out of its controls into plain data. No solving, no writing: a caller that only
--needs the inputs (the debug export, a blueprint request) must not have to run a calculation to see them.
function Sheet.read_inputs(sheet_flow)
    local rates, product_parts = InputContainer.get_desired_production_rates_by_full_item_name(sheet_flow.input_container)
    local dropdown = start_leftovers_dropdown_of(sheet_flow) --absent on 2.1; read whether it is shown or not
    return {
        sheet_id = Sheet.id_of(sheet_flow),
        player_index = sheet_flow.player_index,
        rates = rates,
        product_parts = product_parts,
        options = {
            start_leftovers = dropdown and START_LEFTOVER_MODES[dropdown.selected_index] or "byproduct",
            round_up = Sheet.round_up_checkbox_of(sheet_flow).state,
        },
        empty = next(rates) == nil,
    }
end

--Puts a finished result on screen. Separated from solving so the work can arrive from a job that ran across many
--ticks; the order here is the one the synchronous path always had, and the report is cleared on every path.
function Sheet.publish_result(sheet_flow, result, inputs)
    local player_index = sheet_flow.player_index
    --every loop the solve used keeps exactly the configuration it was solved with (new, unchanged or repaired), before power and the report read it
    for _, column in ipairs(result.columns) do
        if column.quality_loop and column.quality_loop.config then
            QualityLoops.store(player_index, column.quality_loop.key, column.quality_loop.config)
        end
    end

    --the previous report goes in every case, so no totals or controls of an earlier state stay on screen
    local output_flow = sheet_flow.output_flow
    output_flow.clear()

    if result.status == "unsolvable" then
        game.get_player(player_index).create_local_flying_text{text = {"hxrrc.system_with_no_solution_error"}, create_at_cursor = true}
    end

    if not result.recipe_rates then
        Report.new_diagnostic(output_flow, result)
        return
    end

    --totals only for a result whose every rate is usable
    local energy_consumption, pollution
    if result.status == "ok" then
        energy_consumption, pollution = compute_power_and_pollution(player_index, result.columns, result.recipe_rates)
    end
    Report.new(output_flow, result, energy_consumption, pollution, (inputs and inputs.options.round_up) or Sheet.round_up_checkbox_of(sheet_flow).state)
end

--Solves one sheet and shows the result. Still synchronous, and still what async_calls[1] runs; lane W3-calc
--replaces the middle of it with a job, which is why reading and publishing are their own functions.
function Sheet.begin_calculation(compute_button, sheet_pane, sheet_index)
    local sheet_flow
    sheet_flow, sheet_pane, sheet_index = sheet_flow_from(compute_button, sheet_pane, sheet_index)

    --the sheet's report is cleared below, on every path, so a picker for one of its slots goes first
    ModulePicker.close(sheet_flow.player_index, true)
    update_sheet_title(sheet_pane, sheet_index)

    local inputs = Sheet.read_inputs(sheet_flow)
    if inputs.empty then --Empty sheet
        sheet_flow.output_flow.clear()
        return
    end

    local result = Solver.solve_for(inputs.rates, inputs.player_index, inputs.product_parts,
        {start_leftovers = inputs.options.start_leftovers})
    Sheet.publish_result(sheet_flow, result, inputs)
end

--Kept as the name control.lua's async_calls[1] holds, so a job queued in a save from an older version still runs
function Sheet.calculate(compute_button, sheet_pane, sheet_index)
    return Sheet.begin_calculation(compute_button, sheet_pane, sheet_index)
end

--The controls older layouts kept directly in the sheet flow: 1.1.23 a flat drop-down, 1.1.25 to 1.1.30 a label and drop-down row, all of them a
--round-up checkbox (from 1.0.x) and a Compute button
local OLD_CONTROL_NAMES = {
    hxrrc_round_up_machines_checkbox = true,
    hxrrc_start_leftovers_dropdown = true,
    hxrrc_start_leftovers_row = true,
    hxrrc_compute_button = true,
}

--Adds controls that sheets saved by older versions lack; finds them by name (the engine returns nil for a missing child), so it is safe on every
--configuration change. A sheet without the grid gets one where its first old control was, carrying over the checkbox state and the drop-down choice;
--elements cannot change parent, so the old controls are destroyed.
function Sheet.add_missing_controls(sheet_pane)
    for _, tab_and_content in ipairs(sheet_pane.tabs) do
        local sheet_flow = tab_and_content.content
        InputContainer.repair_rows(sheet_flow.input_container)

        if not controls_of(sheet_flow) then
            local state, first_index, old = {round_up = false, selected_index = 1}, nil, {}
            for index, child in ipairs(sheet_flow.children) do
                if OLD_CONTROL_NAMES[child.name] then
                    first_index = first_index or index
                    old[#old + 1] = child
                    if child.name == "hxrrc_round_up_machines_checkbox" then
                        state.round_up = child.state
                    elseif child.name == "hxrrc_start_leftovers_dropdown" then
                        state.selected_index = child.selected_index
                    elseif child.name == "hxrrc_start_leftovers_row" then
                        for _, inner in ipairs(child.children) do
                            if inner.name == "hxrrc_start_leftovers_dropdown" then state.selected_index = inner.selected_index end
                        end
                    end
                end
            end
            for _, child in ipairs(old) do child.destroy() end
            add_sheet_controls(sheet_flow, first_index or sheet_flow.input_container.get_index_in_parent() + 1, state)
        else
            --The grid is there but may predate a control: add each missing cell on its own, so an older sheet keeps
            --its checkbox state and its drop-down choice instead of being rebuilt around them
            local controls = controls_of(sheet_flow)
            local present = {}
            for _, cell in ipairs(controls.children) do present[cell.name] = cell end
            for _, entry in ipairs(NEW_CELLS) do
                if not present[entry.cell] then
                    local flow = controls.add{type = "flow", name = entry.cell, direction = "horizontal"}
                    flow.style.vertical_align = "center"
                    entry.build(flow)
                elseif #present[entry.cell].children == 0 then
                    entry.build(present[entry.cell])
                end
            end
        end
        ensure_sheet_id(sheet_flow)
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

--Recomputes only the sheet owning the control; nothing here writes the control, so the event cannot loop
local function recompute_own_sheet(event)
    Sheet.calculate(Sheet.compute_button_of(Sheet.sheet_flow_of(event.element)))
    storage[event.player_index].calculator.force_auto_center()
end

--Round 8 controls. Each one delegates: the sheet owns where a button sits, the feature module owns what it does.
event_handlers.on_gui_click["hxrrc_export_button"] = function(event)
    ExportDialog.on_export_clicked(event)
end

event_handlers.on_gui_click["hxrrc_generate_blueprint_button"] = function(event)
    BlueprintDialog.on_generate_clicked(event)
end

event_handlers.on_gui_click["hxrrc_cancel_button"] = function(event)
    ProgressPanel.on_cancel_clicked(event)
end

event_handlers.on_gui_selection_state_changed["hxrrc_start_leftovers_dropdown"] = recompute_own_sheet
event_handlers.on_gui_checked_state_changed["hxrrc_round_up_machines_checkbox"] = recompute_own_sheet

--input_container must not require the sheet back, so the sheet hands it the update to run when a target changes
InputContainer.on_target_changed = Sheet.update_start_leftovers_visibility

--Published for gui/progress_panel.lua, which this module requires: Factorio refuses require in a handler.
Registry.sheet = Sheet

return Sheet