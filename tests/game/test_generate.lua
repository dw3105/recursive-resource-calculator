local S = require "tests.game.support"
local Generation = require "logic.bp.generation"
local Calculator = require "gui.calculator"
local BlueprintDialog = require "gui.blueprint_dialog"
local BlueprintDelivery = require "gui.blueprint_delivery"
local Sheet = require "gui.sheet"

local function bind_science()
    local recipes = {
        {"automation-science-pack", "automation-science-pack"},
        {"logistic-science-pack", "logistic-science-pack"},
        {"iron-gear-wheel", "iron-gear-wheel"},
        {"copper-plate", "copper-plate"},
        {"iron-plate", "iron-plate"},
        {"transport-belt", "transport-belt"},
        {"inserter", "inserter"},
        {"electronic-circuit", "electronic-circuit"},
    }
    for _, entry in ipairs(recipes) do S.bind("item/" .. entry[1], entry[2]) end
end

local function calculate(sheet, item, rate)
    bind_science()
    S.fill_row(sheet, 1, item, rate, "/s")
    S.calculate(sheet)
end

local function click_generate(sheet)
    local dialog = assert(BlueprintDialog.open(1, sheet))
    local button = S.find(dialog, "hxrrc_blueprint_generate_button")
    assert.is_not_nil(button, "generate button")
    event_handlers.on_gui_click[button.name]({element = button, player_index = 1})
end

describe("generate", function()
    after_each(function()
        local player = S.player()
        if player and player.clear_cursor then player.clear_cursor() end
        BlueprintDialog.close(1)
        if storage[1] and storage[1].calculator and storage[1].calculator.visible then Calculator.toggle(player) end
    end)

    it("red and green calculate", function()
        local sheet = S.first_sheet()
        bind_science()
        S.fill_row(sheet, 1, "automation-science-pack", 1, "/s")
        S.fill_row(sheet, 2, "logistic-science-pack", 1, "/s")
        S.calculate(sheet)
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            assert.is_true(S.report_rows(sheet) > 0)
        end, "red and green report rows")
    end)

    it("generate button delivers to cursor", function()
        local sheet = S.first_sheet()
        calculate(sheet, "automation-science-pack", 1)
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            click_generate(sheet)
            S.wait_until(function() return storage[1].blueprint_job == nil end, 36000, function()
                local cursor = S.player().cursor_stack
                assert.is_true(cursor.valid_for_read and cursor.is_blueprint and cursor.is_blueprint_setup())
                assert.is_true(#cursor.get_blueprint_entities() > 0)
            end, "blueprint delivery")
        end, "calculation report")
    end)

    it("blueprint builds as ghosts", function()
        local sheet = S.first_sheet()
        calculate(sheet, "automation-science-pack", 1)
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            click_generate(sheet)
            S.wait_until(function() return storage[1].blueprint_job == nil end, 36000, function()
                local cursor = S.player().cursor_stack
                assert.is_true(cursor.valid_for_read and cursor.is_blueprint and cursor.is_blueprint_setup())
                local count = #cursor.get_blueprint_entities()
                assert.is_true(count > 0)
                if not RRC_OFFLINE then
                    local surface = game.surfaces[1]
                    local ghosts = cursor.build_blueprint{surface = surface, force = "player", position = {200, 200},
                        build_mode = defines.build_mode.forced}
                    assert.are_equal(count, #ghosts, "each blueprint entity becomes a ghost")
                    for _, ghost in ipairs(surface.find_entities_filtered{area = {{190, 190}, {210, 210}}, type = "entity-ghost"}) do
                        ghost.destroy()
                    end
                end
            end, "blueprint ghosts")
        end, "calculation report")
    end)

    it("cancel mid-run stops the job", function()
        local sheet = S.first_sheet()
        calculate(sheet, "automation-science-pack", 1)
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            local id = assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(sheet), deliver = true})
            on_tick(function()
                Generation.cancel(1, id)
                local state = S.generation_state(id)
                assert.are_equal("cancelled", state)
                assert.is_nil(storage[1].blueprint_job)
                local ticks = 0
                on_tick(function()
                    ticks = ticks + 1
                    if ticks >= 600 then
                        assert.is_nil(storage[1].blueprint_job)
                        assert.is_false(S.player().cursor_stack.valid_for_read)
                        return false
                    end
                end)
                return false
            end)
        end, "calculation report")
    end)

    it("progress caption shows percent only", function()
        local sheet = S.first_sheet()
        calculate(sheet, "automation-science-pack", 1)
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            assert(Generation.start{player_index = 1, sheet_id = S.sheet_id(sheet), deliver = true})
            on_tick(function()
                local bar = Sheet.progressbar_of(sheet)
                local caption = bar and bar.caption or ""
                assert.is_true(type(caption) == "table" and caption[1] == "hxrrc.progress_bar_percent"
                    and type(caption[2]) == "number", "caption is percent only: " .. serpent.line(caption))
                local caption_text = serpent.line(caption):lower()
                for _, word in ipairs({"pack", "route", "tidy", "validate"}) do
                    assert.is_nil(caption_text:find(word, 1, true), "caption contains no phase words")
                end
                return false
            end)
        end, "calculation report")
    end)

    it("busy cursor keeps result pending then retry delivers", function()
        local sheet = S.first_sheet()
        calculate(sheet, "automation-science-pack", 1)
        local cursor = S.player().cursor_stack
        cursor.set_stack{name = "iron-plate", count = 1}
        S.wait_until(function() return S.report_rows(sheet) > 0 end, 600, function()
            click_generate(sheet)
            S.wait_until(function() return storage[1].blueprint_job == nil end, 36000, function()
                assert.is_not_nil(storage[1].blueprint_delivery)
                S.player().clear_cursor()
                assert.is_true(BlueprintDelivery.retry(1))
                assert.is_true(cursor.valid_for_read and cursor.is_blueprint and cursor.is_blueprint_setup())
            end, "pending blueprint delivery")
        end, "calculation report")
    end)
end)
