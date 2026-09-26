--Shared helpers for tests/game/*. Runs headless (FactorioTest, tools/game_test.sh) and offline (tests/game/offline.lua
--on the tests/harness.lua mock). Lanes read it, never change it. Parse-time requires only.
local Sheet = require "gui.sheet"
local Generation = require "logic.bp.generation"

local S = {}

function S.player() return game.players[1] end

--The calculator every player gets on init, and its first sheet (on_init builds one per player).
function S.sheet_pane() return storage[1].sheet_section.sheet_pane end
function S.first_sheet()
    local pane = S.sheet_pane()
    pane.selected_tab_index = 1
    return pane.tabs[1].content
end
function S.sheet_id(sheet) return sheet.tags.hxrrc_sheet_id end

function S.find(root, name)
    if root == nil then return nil end
    if root.name == name then return root end
    for _, child in pairs(root.children or {}) do
        local found = S.find(child, name)
        if found then return found end
    end
end

--Types one target into row `index` of a sheet the way a player does: rate, unit, then the item button event.
function S.fill_row(sheet, index, item, rate, unit)
    local row = sheet.input_container.children[index or 1]
    row.rate_textfield.text = string.format("%.17g", rate)
    row.time_unit_dropdown.selected_index = unit == "/m" and 1 or 2
    local button = row.hxrrc_desired_item_button
    button.elem_value = button.elem_type == "item-with-quality" and {name = item, quality = "normal"} or item
    event_handlers.on_gui_elem_changed[button.name]({element = button, player_index = 1})
    return row
end

--Binds a product to the recipe that makes it, as the report's recipe button stores it (harness world.bind). A fresh
--sheet has no binding, so its report lists raw needs only and generation refuses BP_REJ_NO_ACTIVE_STEPS.
function S.bind(product_full_name, recipe_name)
    local data = storage[1]
    data.recipes_by_product_full_name[product_full_name] = prototypes.recipe[recipe_name]
    data.product_full_names_by_recipe_name[recipe_name] = product_full_name
end

function S.calculate(sheet)
    return Sheet.calculate(Sheet.compute_button_of(sheet))
end

function S.report_rows(sheet)
    local out = sheet.output_flow
    return out and #out.children or 0
end

--Polls pred every tick (FactorioTest on_tick); calls then_fn once pred holds; fails after max_ticks.
function S.wait_until(pred, max_ticks, then_fn, what)
    local waited = 0
    on_tick(function()
        waited = waited + 1
        if pred() then then_fn(); return false end
        if waited >= max_ticks then error("timed out after " .. max_ticks .. " ticks: " .. tostring(what)) end
    end)
end

function S.generation_state(job_id)
    local status = Generation.status(1, job_id)
    return status and status.state, status
end

--"<name> <x> <y> <direction>" per entity, sorted, %.1f positions: the same lines tools/game_expect.sh writes.
function S.entity_lines(blueprint_string)
    local json = helpers.decode_string(blueprint_string:sub(2))
    local bp = helpers.json_to_table(json).blueprint
    local lines = {}
    for _, e in ipairs(bp.entities or {}) do
        lines[#lines + 1] = string.format("%s %.1f %.1f %d", e.name, e.position.x, e.position.y, e.direction or 0)
    end
    table.sort(lines)
    return lines
end

function S.split_lines(text)
    local lines = {}
    for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
    return lines
end

--Golden fixtures staged by tools/game_stage.sh (offline.lua builds the same modules from the case files). Test files
--require tests.game.fixtures.<case> and tests.game.fixtures.<case>_expected at file top (Factorio forbids require
--after control.lua parsing) and pass the strings here.
function S.prepared_input(json_text) return helpers.json_to_table(json_text) end

return S
