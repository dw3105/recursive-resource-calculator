--Replays a prepared Case through the controls a player uses. No calculation selection is written directly.
local S = require "tests.game.support"

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
    local environment = prepared.environment or {}
    local force = type(environment.force) == "table" and copy(environment.force)
        or type(prepared.force) == "table" and copy(prepared.force) or {}
    return {targets = targets, columns = def_columns, settings = copy(prepared.settings or {}), options = options,
        round_up = options.round_up, start_leftovers = options.start_leftovers,
        edges = {input = (prepared.settings or {}).input_edge or options.input_edge,
            output = (prepared.settings or {}).output_edge or options.output_edge},
        force = force, qualities = copy(environment.qualities or prepared.qualities or {})}
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
local function right_click(el)
    if not el then error("GUI element not found") end
    local fn = event_handlers.on_gui_click[el.name]
    if not fn then error("no click handler for " .. tostring(el.name)) end
    fn({element = el, player_index = 1, tick = game.tick, button = defines.mouse_button_type.right})
end
local function find(root, name, predicate)
    if not root then return nil end
    if root.name == name and (not predicate or predicate(root)) then return root end
    for _, child in pairs(root.children or {}) do
        local found = find(child, name, predicate)
        if found then return found end
    end
end
local function find_owned(root, name, recipe, group, index)
    local function visit(element, owner)
        if element.tags and element.tags.recipe_name then owner = element.tags.recipe_name end
        if element.name == name and owner == recipe
            and (group == nil or element.tags.group == group)
            and (index == nil or element.tags.index == index) then return element end
        for _, child in pairs(element.children or {}) do
            local found = visit(child, owner)
            if found then return found end
        end
    end
    return root and visit(root, nil)
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
    local pane = S.sheet_pane()
    local new_sheet = S.find(game.players[1].gui.screen.hxrrc_calculator, "hxrrc_new_sheet_button")
    if not new_sheet then error("new sheet button missing") end
    click(new_sheet)
    pane.selected_tab_index = #pane.tabs
    local sheet = pane.tabs[pane.selected_tab_index].content
    local research = (def.force or {}).research or {}
    local research_names = {}
    for recipe in pairs(research) do research_names[#research_names + 1] = recipe end
    table.sort(research_names)
    local force = game.forces and game.forces.player
    for _, research_name in ipairs(research_names) do
        local level = research[research_name]
        local technology = force and force.technologies and force.technologies[research_name]
        if technology then
            if type(level) == "boolean" then technology.researched = level
            elseif type(level) == "number" and level > 0 then technology.researched = true end
        end
    end
    local quality_names = {}
    for name, enabled in pairs(def.qualities or {}) do
        local quality = type(name) == "number" and enabled or name
        if type(quality) == "string" then quality_names[#quality_names + 1] = quality end
    end
    for _, target in ipairs(def.targets or {}) do
        if target.quality and target.quality ~= "normal" then quality_names[#quality_names + 1] = target.quality end
    end
    for _, col in ipairs(def.columns or {}) do
        if col.machine and col.machine.quality and col.machine.quality ~= "normal" then quality_names[#quality_names + 1] = col.machine.quality end
        for _, module in ipairs((col.setup or {}).modules or {}) do
            if module and module.quality and module.quality ~= "normal" then quality_names[#quality_names + 1] = module.quality end
        end
        for _, group in ipairs((col.setup or {}).beacons or {}) do
            if group.quality and group.quality ~= "normal" then quality_names[#quality_names + 1] = group.quality end
            for _, module in ipairs(group.modules or {}) do
                if module and module.quality and module.quality ~= "normal" then quality_names[#quality_names + 1] = module.quality end
            end
        end
    end
    table.sort(quality_names)
    local unlocked = {}
    for _, quality in ipairs(quality_names) do
        if not unlocked[quality] and force and force.unlock_quality then force.unlock_quality(quality); unlocked[quality] = true end
    end
    local steps, at = {}, 1
    for i, target in ipairs(def.targets or {}) do steps[#steps + 1] = {name = "target " .. target.full_name, kind = "target", index = i, value = target} end
    if #(def.targets or {}) > 0 then steps[#steps + 1] = {name = "initial compute", kind = "compute"} end
    local bind_names = {}
    for full_name in pairs(def.binds or {}) do bind_names[#bind_names + 1] = full_name end
    table.sort(bind_names)
    for _, full_name in ipairs(bind_names) do steps[#steps + 1] = {name = "binding " .. full_name, kind = "binding", full_name = full_name, recipe = def.binds[full_name]} end
    for _, col in ipairs(def.columns or {}) do
        if col.recipe_name and not (def.binds and def.binds[col.product_full_name]) then steps[#steps + 1] = {name = "recipe " .. col.recipe_name, kind = "recipe", column = col} end
        steps[#steps + 1] = {name = "machine " .. tostring(col.recipe_name), kind = "machine", column = col}
        local current_setup = (storage[1].module_setups_by_recipe_name or {})[col.recipe_name] or {}
        local module_indexes = {}
        for index in pairs(current_setup.modules or {}) do if type(index) == "number" then module_indexes[#module_indexes + 1] = index end end
        table.sort(module_indexes)
        for _, index in ipairs(module_indexes) do
            local module = current_setup.modules[index]
            if module and module.name then steps[#steps + 1] = {name = "clear module " .. col.recipe_name .. " " .. index, kind = "clear_module", column = col, index = index} end
        end
        for index in ipairs(current_setup.beacons or {}) do
            steps[#steps + 1] = {name = "clear beacon " .. col.recipe_name .. " " .. index, kind = "clear_beacon", column = col, index = index}
        end
        for i, module in ipairs((col.setup or {}).modules or {}) do
            if module and module.name then steps[#steps + 1] = {name = "module " .. col.recipe_name .. " " .. i, kind = "module", column = col, index = i, value = module} end
        end
        for gi, group in ipairs((col.setup or {}).beacons or {}) do
            steps[#steps + 1] = {name = "beacon " .. col.recipe_name .. " " .. gi, kind = "beacon", column = col, index = gi, value = group}
            steps[#steps + 1] = {name = "beacon count " .. col.recipe_name .. " " .. gi, kind = "beacon_count", column = col, index = gi, value = group}
            for mi, module in ipairs(group.modules or {}) do
                steps[#steps + 1] = {name = "beacon module " .. col.recipe_name .. " " .. gi .. " " .. mi, kind = "beacon_module", column = col, index = gi, module_index = mi, value = module}
            end
        end
    end
    if def.round_up ~= nil then steps[#steps + 1] = {name = "round-up setting", kind = "round_up"} end
    if def.start_leftovers ~= nil then steps[#steps + 1] = {name = "leftovers setting", kind = "leftovers"} end
    local waited, final_compute_started = 0, false
    on_tick(function()
        if not idle() then
            waited = waited + 1
            if waited >= 600 then error("timed out waiting for recompute before " .. ((steps[at] or {}).name or "compute")) end
            return true
        end
        waited = 0
        local step = steps[at]
        if not step then
            if not final_compute_started then
                click(S.find(sheet, "hxrrc_compute_button"))
                final_compute_started = true
            end
            if idle() then done_fn(sheet); return false end
            waited = waited + 1
            if waited >= 600 then error("timed out waiting for recompute before compute") end
            return true
        end
        local col = step.column
        if step.kind == "target" then
            local row = sheet.input_container.children[step.index]
            if not row then error("missing target row " .. step.index) end
            row.rate_textfield.text = string.format("%.17g", step.value.rate_per_second)
            row.time_unit_dropdown.selected_index = 2
            local b = step.value.type == "fluid" and row.hxrrc_desired_fluid_button or row.hxrrc_desired_item_button
            b.elem_value = step.value.type == "fluid" and step.value.full_name:gsub("^fluid/", "") or {name = step.value.full_name:gsub("^item/", ""), quality = step.value.quality or "normal"}
            event_handlers.on_gui_elem_changed[b.name]({element = b, player_index = 1})
        elseif step.kind == "compute" then
            click(S.find(sheet, "hxrrc_compute_button"))
        elseif step.kind == "binding" or step.kind == "recipe" then
            local full_name = step.full_name or col.product_full_name
            local b = find(sheet.output_flow, "hxrrc_choose_recipe_button", function(e) return e.tags.product_full_name == full_name end)
            local recipe_name = step.recipe or col.recipe_name
            if b then
                b.elem_value = recipe_name
                event_handlers.on_gui_elem_changed[b.name]({element = b, player_index = 1})
            else
                local recipes_by_product = storage[1].recipes_by_product_full_name
                local current = recipes_by_product[full_name]
                if not current or current.name ~= recipe_name then error("recipe button missing for " .. tostring(col and col.recipe_name or recipe_name)) end
            end
        elseif step.kind == "machine" then
            local b = find(sheet.output_flow, "hxrrc_choose_crafting_machine_button", function(e) return e.tags.recipe_name == col.recipe_name end)
            if not b then error("machine button missing for " .. col.recipe_name) end
            click(b); select_picker(col.machine.name, col.machine.quality)
        elseif step.kind == "module" then
            local b = find_owned(sheet.output_flow, "hxrrc_choose_module_button", col.recipe_name, nil, step.index)
            if not b then error("module slot missing for " .. col.recipe_name) end
            click(b); select_picker(step.value.name, step.value.quality)
        elseif step.kind == "clear_module" then
            local b = find_owned(sheet.output_flow, "hxrrc_choose_module_button", col.recipe_name, nil, step.index)
            if not b then error("module slot missing for " .. col.recipe_name) end
            right_click(b)
        elseif step.kind == "clear_beacon" then
            local b = find_owned(sheet.output_flow, "hxrrc_choose_beacon_button", col.recipe_name, step.index)
            if not b then error("beacon button missing for " .. col.recipe_name) end
            right_click(b)
        elseif step.kind == "beacon" then
            local b = find_owned(sheet.output_flow, "hxrrc_choose_beacon_button", col.recipe_name, step.index)
            if not b then error("beacon button missing for " .. col.recipe_name) end
            click(b); select_picker(step.value.name, step.value.quality)
        elseif step.kind == "beacon_count" then
            local count = find_owned(sheet.output_flow, "hxrrc_beacon_count_textfield", col.recipe_name, step.index)
            if count and count.text ~= tostring(step.value.count) then
                count.text = tostring(step.value.count)
                event_handlers.on_gui_confirmed[count.name]({element = count, player_index = 1})
            end
        elseif step.kind == "beacon_module" then
            local slot = find_owned(sheet.output_flow, "hxrrc_choose_beacon_module_button", col.recipe_name, step.index, step.module_index)
            if not slot then error("beacon module slot missing for " .. col.recipe_name .. " " .. step.module_index) end
            click(slot); select_picker(step.value.name, step.value.quality)
        elseif step.kind == "round_up" then
            local c = S.find(sheet, "hxrrc_round_up_machines_checkbox")
            if c and c.state ~= (def.round_up == true) then c.state = def.round_up == true; event_handlers.on_gui_checked_state_changed[c.name]({element = c, player_index = 1}) end
        elseif step.kind == "leftovers" then
            local c = S.find(sheet, "hxrrc_start_leftovers_dropdown")
            local index = ({byproduct = 1, craft = 2, recycle = 3})[def.start_leftovers]
            if c and index and c.selected_index ~= index then c.selected_index = index; event_handlers.on_gui_selection_state_changed[c.name]({element = c, player_index = 1}) end
        end
        at = at + 1
        return true
    end)
end

local function value_text(value)
    if value == nil then return "nil" end
    if type(value) ~= "table" then return tostring(value) end
    local fields, keys = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do fields[#fields + 1] = tostring(key) .. "=" .. value_text(value[key]) end
    return "{" .. table.concat(fields, ",") .. "}"
end
local function module_list(list)
    local out = {}
    for i, module in pairs(list or {}) do
        if type(i) == "number" and module and module.name then
            out[i] = {name = module.name, quality = module.quality or "normal"}
        end
    end
    return out
end
local function beacon_list(list)
    local out = {}
    for i, beacon in ipairs(list or {}) do
        out[i] = {name = beacon.name, quality = beacon.quality or "normal", count = beacon.count,
            modules = module_list(beacon.modules)}
    end
    return out
end
function Drive.compare(def)
    local player = storage[1]
    local diffs = {}
    local columns = copy(def.columns or {})
    table.sort(columns, function(a, b) return tostring(a.recipe_name) < tostring(b.recipe_name) end)
    local function check(recipe, field, want, got)
        if value_text(want) ~= value_text(got) then
            diffs[#diffs + 1] = string.format("%s: %s want %s got %s", tostring(recipe), field, value_text(want), value_text(got))
        end
    end
    for _, col in ipairs(columns) do
        local recipe = col.recipe_name
        local product = player.product_full_names_by_recipe_name[recipe] or col.product_full_name
        local bound = player.recipes_by_product_full_name[product]
        check(recipe, "recipe", recipe, bound and bound.name)
        local machine = player.identifiers_of_chosen_crafting_machines_by_recipe_name[recipe]
        check(recipe, "machine", col.machine and {name = col.machine.name, quality = col.machine.quality or "normal"},
            machine and {name = machine.name, quality = machine.quality or "normal"})
        local setup = (player.module_setups_by_recipe_name or {})[recipe] or {}
        check(recipe, "modules", module_list((col.setup or {}).modules), module_list(setup.modules))
        check(recipe, "beacons", beacon_list((col.setup or {}).beacons), beacon_list(setup.beacons))
    end
    return diffs
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
