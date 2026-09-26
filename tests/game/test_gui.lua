local S = require "tests.game.support"
local Calculator = require "gui.calculator"
local Sheet = require "gui.sheet"
local BlueprintDialog = require "gui.blueprint_dialog"
local ModulePicker = require "gui.module_picker"

local function close_calculator()
    local player = S.player()
    if BlueprintDialog.is_open(1) then
        BlueprintDialog.close(1)
    end
    if player.cursor_stack and player.cursor_stack.valid_for_read then
        player.cursor_stack.clear()
    end
    if storage[1] and storage[1].calculator and storage[1].calculator.valid and storage[1].calculator.visible then
        Calculator.toggle(player)
    end
end

describe("gui", function()
    after_each(close_calculator)

    it("toggle opens and closes twice", function()
        local player = S.player()
        local calculator = storage[1].calculator
        Calculator.toggle(player)
        assert.are_equal(true, calculator.visible, "first toggle opens")
        Calculator.toggle(player)
        assert.are_equal(false, calculator.visible, "second toggle closes")
        Calculator.toggle(player)
        assert.are_equal(true, calculator.visible, "third toggle opens")
        Calculator.toggle(player)
        assert.are_equal(false, calculator.visible, "fourth toggle closes")
    end)

    it("new sheet tab and delete", function()
        local calculator = storage[1].calculator
        local pane = S.sheet_pane()
        local before = #pane.tabs
        local add = S.find(calculator, "hxrrc_new_sheet_button")
        assert.is_not_nil(add, "new sheet button exists")
        event_handlers.on_gui_click[add.name]({element = add, player_index = 1})
        assert.are_equal(before + 1, #pane.tabs, "new tab added")
        pane.selected_tab_index = #pane.tabs
        local delete = S.find(calculator, "hxrrc_delete_sheet_button")
        assert.is_not_nil(delete, "delete sheet button exists")
        event_handlers.on_gui_click[delete.name]({element = delete, player_index = 1})
        assert.are_equal(before, #pane.tabs, "new tab deleted")
    end)

    it("every sheet cell button responds", function()
        local sheet = S.first_sheet()
        local export = Sheet.export_button_of(sheet)
        local blueprint = Sheet.blueprint_button_of(sheet)
        local cancel = Sheet.cancel_button_of(sheet)
        for _, button in ipairs({export, blueprint, cancel}) do
            assert.is_not_nil(button, "sheet cell button exists")
            assert.is_true(button.valid, "sheet cell button is valid")
            assert.is_true(button.name ~= nil and button.name ~= "", "sheet cell button has a name")
        end
        event_handlers.on_gui_click[blueprint.name]({element = blueprint, player_index = 1})
        assert.is_true(BlueprintDialog.is_open(1), "blueprint dialog opened")
        local close = S.find(game.players[1].gui.screen, "hxrrc_blueprint_close_button")
        assert.is_not_nil(close, "blueprint close button exists")
        event_handlers.on_gui_click[close.name]({element = close, player_index = 1})
        assert.is_true(not BlueprintDialog.is_open(1), "blueprint dialog closed")
    end)

    it("no duplicate sibling names", function()
        local function check_siblings(element)
            local names = {}
            for _, child in pairs(element.children or {}) do
                if child.name and child.name ~= "" then
                    assert.is_nil(names[child.name], "duplicate sibling name: " .. child.name)
                    names[child.name] = true
                end
                check_siblings(child)
            end
        end
        check_siblings(storage[1].calculator)
    end)

    it("module picker opens and closes", function()
        local sheet = S.first_sheet()
        S.bind("item/automation-science-pack", "automation-science-pack")
        --The real game defaults to assembling-machine-1, which has no module slots, so its report row has no module
        --button (headless 2.0.77 + 2.1.20, round 42). Pick a machine with slots, as a player would.
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["automation-science-pack"] = {name = "assembling-machine-2"}
        S.fill_row(sheet, 1, "automation-science-pack", 1, "/s")
        S.calculate(sheet)
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            local button = S.find(sheet.output_flow, "hxrrc_choose_module_button")
            assert.is_not_nil(button, "report module button exists")
            --A slot is a plain button that opens the picker (headless: elem_value on it raises "Only callable on
            --choose-elem-button."), so both runs click it.
            event_handlers.on_gui_click[button.name]({element = button, player_index = 1})
            assert.is_not_nil(storage[1].module_picker, "module picker opened")
            ModulePicker.close(1, false)
            close_calculator()
        end, "report rows")
    end)

    it("removed player data is dropped", function()
        local data = storage[1]
        Calculator.toggle(S.player())
        Calculator.toggle(S.player())
        assert.is_true(storage[1] == data, "player data survives a calculator toggle cycle")
    end)
end)
