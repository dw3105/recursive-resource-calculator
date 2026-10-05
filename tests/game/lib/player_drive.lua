--Replays a prepared Case through the controls a player uses. No calculation selection is written directly.
local S = require "tests.game.support"
local Sheet = require "gui.sheet"

local Drive = {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

function Drive.case_def(prepared)
    local snapshot = prepared.snapshot or {}
    local columns = (prepared.solver_result or {}).columns or {}
    local targets = {}
    for _, target in ipairs(snapshot.targets or {}) do
        targets[#targets + 1] = {full_name = target.full_name, rate_per_second = target.rate_per_second,
            quality = target.quality or "normal", type = target.type}
    end
    local def_columns = {}
    for _, column in ipairs(columns) do
        def_columns[#def_columns + 1] = {product_full_name = column.product_full_name, recipe_name = column.recipe_name,
            consumer = column.consumer == true, machine = copy(column.machine), setup = copy(column.setup or {})}
    end
    local options = copy(prepared.options or {})
    return {targets = targets, columns = def_columns, settings = copy(prepared.settings or {}), options = options,
        round_up = options.round_up, start_leftovers = options.start_leftovers,
        edges = {input = (prepared.settings or {}).input_edge or options.input_edge,
            output = (prepared.settings or {}).output_edge or options.output_edge},
        force = prepared.environment and prepared.environment.force or prepared.force,
        qualities = prepared.qualities or {}}
end

function Drive.vanilla_def(case)
    local green = case == "vanilla-2.1-green-science-1s"
    if not green and case ~= "vanilla-2.1-red-science-1s" then error("unknown vanilla Case " .. tostring(case)) end
    local binds = { ["item/iron-gear-wheel"] = "iron-gear-wheel", ["item/copper-cable"] = "copper-cable",
        ["item/electronic-circuit"] = "electronic-circuit", ["item/transport-belt"] = "transport-belt",
        ["item/inserter"] = "inserter", ["item/automation-science-pack"] = "automation-science-pack",
        ["item/logistic-science-pack"] = "logistic-science-pack" }
    return {targets = {{full_name = green and "item/logistic-science-pack" or "item/automation-science-pack",
        rate_per_second = 1, quality = "normal", type = "item"}}, columns = {}, binds = binds,
        settings = {}, options = {round_up = false, start_leftovers = "byproduct"},
        edges = {input = "left", output = "top"}, force = {}, qualities = {}}
end

local function click(el)
    if not el then error("GUI element not found") end
    local fn = event_handlers.on_gui_click[el.name]
    if not fn then error("no click handler for " .. tostring(el.name)) end
    fn({element = el, player_index = 1, tick = game.tick, button = defines.mouse_button_type.left})
end
local function select_picker(name, quality)
    local picker = storage[1].module_picker
    if not picker then error("picker did not open for " .. name) end
    local choice
    for _, flow in ipairs(picker.frame.picker_scroll.picker_grid.children) do
        local b = flow.children[1]
        if b.tags.choice == name then choice = b; break end
    end
    if not choice then error("picker has no choice " .. name) end
    click(choice)
    if quality and quality ~= "normal" then
        local q
        for _, flow in ipairs(picker.frame.picker_qualities.children) do
            local b = flow.children[1]
            if b.tags.quality == quality then q = b; break end
        end
        if not q then error("picker has no unlocked quality " .. quality) end
        click(q)
    end
    click(S.find(picker.frame, "hxrrc_picker_confirm_button"))
end
local function idle()
    return (storage[1].backlogged_computation_count or 0) == 0 and #(storage.calc_jobs or {}) == 0
end

function Drive.setup(def, done_fn)
    local sheet = S.first_sheet()
    for recipe, bonus in pairs((def.force or {}).research or {}) do
        local r = game.forces.player.recipes[recipe]
        if r then r.productivity_bonus = bonus end
    end
    for i, target in ipairs(def.targets or {}) do
        local row = sheet.input_container.children[i]
        if not row then error("missing target row " .. i) end
        row.rate_textfield.text = string.format("%.17g", target.rate_per_second)
        row.time_unit_dropdown.selected_index = 2
        local button = target.type == "fluid" and row.hxrrc_desired_fluid_button or row.hxrrc_desired_item_button
        button.elem_value = target.type == "fluid" and target.full_name:gsub("^fluid/", "") or {name = target.full_name:gsub("^item/", ""), quality = target.quality}
        event_handlers.on_gui_elem_changed[button.name]({element = button, player_index = 1})
    end
    for full_name, recipe in pairs(def.binds or {}) do
        local el
        --The initially built report exposes bindings for products with one known recipe.
        local output = sheet.output_flow
        el = output and S.find(output, "hxrrc_choose_recipe_button")
        if el and el.tags.product_full_name == full_name then
            el.elem_value = recipe
            event_handlers.on_gui_elem_changed[el.name]({element = el, player_index = 1})
        end
    end
    local controls = S.find(sheet, "hxrrc_round_up_machines_checkbox")
    if controls then
        controls.state = def.round_up == true
        event_handlers.on_gui_checked_state_changed[controls.name]({element = controls, player_index = 1})
    end
    local steps, at = {}, 1
    for _, col in ipairs(def.columns or {}) do
        if col.recipe_name then steps[#steps + 1] = {name = "recipe " .. col.recipe_name, kind = "recipe", column = col} end
        steps[#steps + 1] = {name = "machine " .. tostring(col.recipe_name), kind = "machine", column = col}
        for i, module in ipairs((col.setup or {}).modules or {}) do
            if module then steps[#steps + 1] = {name = "module " .. col.recipe_name .. " " .. i, kind = "module", column = col, index = i, value = module} end
        end
    end
    local waited = 0
    on_tick(function()
        if not idle() then
            waited = waited + 1
            if waited >= 600 then error("timed out waiting for recompute before " .. ((steps[at] or {}).name or "compute")) end
            return true
        end
        waited = 0
        local step = steps[at]
        if not step then
            local compute = S.find(sheet, "hxrrc_compute_button")
            click(compute)
            if idle() then done_fn(sheet); return false end
            return true
        end
        local col = step.column
        if step.kind == "recipe" then
            local b = S.find(sheet.output_flow, "hxrrc_choose_recipe_button")
            while b and b.tags.product_full_name ~= col.product_full_name do
                --find recursively by exact tag since product rows are rebuilt each pass
                b = nil
                local function visit(e)
                    if e.name == "hxrrc_choose_recipe_button" and e.tags.product_full_name == col.product_full_name then b = e end
                    for _, child in ipairs(e.children or {}) do visit(child) end
                end
                visit(sheet.output_flow)
            end
            if not b then error("recipe button missing for " .. col.recipe_name) end
            b.elem_value = col.recipe_name
            event_handlers.on_gui_elem_changed[b.name]({element = b, player_index = 1})
        elseif step.kind == "machine" then
            local b
            local function visit(e)
                if e.name == "hxrrc_choose_crafting_machine_button" and e.tags.recipe_name == col.recipe_name then b = e end
                for _, child in ipairs(e.children or {}) do visit(child) end
            end
            visit(sheet.output_flow)
            if not b then error("machine button missing for " .. col.recipe_name) end
            click(b); select_picker(col.machine.name, col.machine.quality)
        else
            local b
            local function visit(e)
                if e.name == "hxrrc_choose_module_button" and e.tags.recipe_name == col.recipe_name and e.tags.index == step.index then b = e end
                for _, child in ipairs(e.children or {}) do visit(child) end
            end
            visit(sheet.output_flow)
            if not b then error("module slot missing for " .. col.recipe_name) end
            click(b); select_picker(step.value.name, step.value.quality)
        end
        at = at + 1
        return true
    end)
end

function Drive.generate(sheet, def)
    click(S.find(sheet, "hxrrc_generate_blueprint_button"))
    local dialog = game.players[1].gui.screen
    for _, key in ipairs({"roboport", "pole", "belt", "inserter", "long_inserter", "pipe", "underground_pipe"}) do
        local button = S.find(dialog, "hxrrc_blueprint_" .. key .. "_button")
        local setting = def.settings[key]
        if button and setting then button.elem_value = setting.name; event_handlers.on_gui_elem_changed[button.name]({element = button, player_index = 1}) end
    end
    local function edge(key, value)
        local b = S.find(dialog, "hxrrc_blueprint_" .. key .. "_edge_dropdown")
        local map = {left = 1, right = 2, top = 3, bottom = 4}
        if b and map[value] then b.selected_index = map[value]; event_handlers.on_gui_selection_state_changed[b.name]({element = b, player_index = 1}) end
    end
    edge("input", (def.edges or {}).input); edge("output", (def.edges or {}).output)
    click(S.find(dialog, "hxrrc_blueprint_generate_button"))
end

return Drive
