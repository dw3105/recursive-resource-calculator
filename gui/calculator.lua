local Report = require "gui.report"
local Sheet = require "gui.sheet"
local ModuleGUI = require "gui.modulegui"
local Calculator = {}

function Calculator.build(player)
    --Main frame:
    local calculator = player.gui.screen.add{
        type = "frame",
        name = "hxrrc_calculator",
        caption = {"hxrrc.calculator_title"},
        visible = false,
    }
    storage[player.index].calculator = calculator
    calculator.auto_center = true
    local main_scroll_area = calculator.add{type = "scroll-pane", direction = "horizontal", name = "main_scroll_area"}
    local main_scroll_area_flow = main_scroll_area.add{type = "flow", direction = "horizontal", name = "main_scroll_area_flow"}

    --Sheet section:
    local sheet_section = main_scroll_area_flow.add{type = "flow", direction = "vertical", name = "sheet_section"}
    storage[player.index].sheet_section = sheet_section
    sheet_section.style.horizontally_stretchable = true
    --Sheet addition and removal buttons:
    local sheet_buttons_flow = sheet_section.add{type = "flow", direction = "horizontal"}
    sheet_buttons_flow.style.horizontal_align = "right"
    sheet_buttons_flow.style.horizontally_stretchable = true
    sheet_buttons_flow.add{
        type = "button",
        name = "hxrrc_new_sheet_button",
        caption = {"hxrrc.new_sheet"},
        tooltip = {"hxrrc.add_new_sheet"},
    }
    sheet_buttons_flow.add{
        type = "button",
        name = "hxrrc_delete_sheet_button",
        caption = {"hxrrc.delete_sheet"},
        tooltip = {"hxrrc.delete_selected_sheet"},
    }
    --Sheet pane and first sheet:
    local sheet_pane = sheet_section.add{type = "tabbed-pane", name = "sheet_pane"}
    Sheet.new(sheet_pane)
    sheet_pane.selected_tab_index = 1
end

function Calculator.auto_center(player_index)
    storage[player_index].calculator.force_auto_center()
end

event_handlers.on_gui_click["hxrrc_new_sheet_button"] = function(event)
    Sheet.new(event.element.parent.parent.sheet_pane)
    storage[event.player_index].calculator.force_auto_center()
end

event_handlers.on_gui_click["hxrrc_delete_sheet_button"] = function(event)
    Sheet.delete_selected_sheet(event.element.parent.parent.sheet_pane)
    storage[event.player_index].calculator.force_auto_center()
end

function Calculator.toggle(player)
    local calculator = player.gui.screen.hxrrc_calculator
    calculator.visible = not calculator.visible
    player.opened = calculator.visible and calculator or nil
end

function Calculator.recompute_everything(player_index)
    local sheet_pane = storage[player_index].sheet_section.sheet_pane

    for sheet_index, _ in ipairs(sheet_pane.tabs) do
        storage.computation_stack[#storage.computation_stack+1] = {player_index = player_index, call_id = 1, parameters = {false, sheet_pane, sheet_index}}
        storage[player_index].backlogged_computation_count = storage[player_index].backlogged_computation_count + 1
    end

    storage.computation_stack[#storage.computation_stack+1] = {player_index = player_index, call_id = 2, parameters = {player_index}}
    storage[player_index].backlogged_computation_count = storage[player_index].backlogged_computation_count + 1
end

event_handlers.on_gui_elem_changed["hxrrc_choose_module_button"] = function(event)
    if ModuleGUI.on_module_button_changed(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_elem_changed["hxrrc_choose_beacon_button"] = function(event)
    if ModuleGUI.on_beacon_button_changed(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_elem_changed["hxrrc_choose_beacon_module_button"] = function(event)
    if ModuleGUI.on_beacon_module_button_changed(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_confirmed["hxrrc_beacon_count_textfield"] = function(event)
    if ModuleGUI.on_beacon_count_confirmed(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_confirmed["hxrrc_beacon_sharing_textfield"] = function(event)
    if ModuleGUI.on_beacon_sharing_confirmed(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_elem_changed["hxrrc_choose_recipe_button"] = function(event)
    if Report.handle_recipe_binding_change(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_elem_changed["hxrrc_choose_burner_button"] = function(event)
    if Report.handle_burner_change(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_elem_changed["hxrrc_choose_burner_entity_button"] = function(event)
    if Report.handle_burner_entity_change(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_elem_changed["hxrrc_choose_loop_machine_button"] = function(event)
    if Report.handle_loop_machine_change(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_elem_changed["hxrrc_choose_recycle_recipe_button"] = function(event)
    if Report.handle_recycle_recipe_change(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

event_handlers.on_gui_elem_changed["hxrrc_choose_crafting_machine_button"] = function(event)
    if Report.handle_crafting_machine_change(event) then
        Calculator.recompute_everything(event.player_index)
    end
end

return Calculator