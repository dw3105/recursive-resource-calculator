local ModuleGUI = require "gui.modulegui"
local ModuleSetup = require "logic.module_setup"
local Utils = require "logic.utils"

local Report = {}

local function format_by_precision(float, player_index)
    local precision = settings.get_player_settings(player_index)["hxrrc-displayed-floating-point-precision"].value

    return string.format("%." .. precision .. "f", float)
end

--Whole machines: bumps to the next integer only for a fraction above rounding noise, keeps float range for huge counts, never shows -0
local function rounded_up_count_text(amount)
    local rounded = math.floor(amount)
    if amount - rounded > 1e-9 * math.max(1, math.abs(amount)) then
        rounded = rounded + 1
    end
    return rounded == 0 and "0" or string.format("%.0f", rounded)
end

local function add_header(report, caption, tooltip)
    local header = report.add{type = "flow"}
    header.style.horizontally_stretchable = true
    header.style.horizontal_align = "center"
    local label = header.add{type = "label", caption = caption, tooltip = tooltip}
    label.style.right_padding = 4
end

--energy_consumption and pollution nil: totals of a result that cannot be trusted are not shown; unsolvable says why in place of the energy
local function setup_headers(report, energy_consumption, pollution, unsolvable)
    add_header(report, {"", {"hxrrc.consumption"}, ":"}, {"hxrrc.consumption_header_tooltip"})
    if energy_consumption then
        report.add{type = "label", caption = format_by_precision(energy_consumption / 1000000, report.player_index) .. " MW"}
    else
        report.add{type = "label", caption = unsolvable and {"hxrrc.system_with_no_solution_error"} or {"hxrrc.totals_unavailable"}}
    end

    add_header(report, {"", {"hxrrc.pollution"}, ":"}, {"hxrrc.pollution_header_tooltip"})
    report.add{type = "flow", name = "pollution_flow"}

    if pollution then
        report.pollution_flow.add{type = "label", caption = format_by_precision(pollution * 60, report.player_index) .. " /m"}
    else
        report.pollution_flow.add{type = "label", caption = {"hxrrc.totals_unavailable"}}
    end

    for _, caption in ipairs({
        {"hxrrc.production_rates_table_header"},
        {"hxrrc.machine_counts_table_header"},
        {"hxrrc.modules"},
        {"hxrrc.recipes_used_table_header"}}) do
            add_header(report, caption)
    end
end

local function split_product_name(product_full_name)
    local slash_position = string.find(product_full_name, "/", 1, true)
    return product_full_name:sub(1, slash_position - 1), product_full_name:sub(slash_position + 1)
end

--nil once the mod adding the item or fluid is removed
local function prototype_of(product_full_name)
    local type, short_name = split_product_name(product_full_name)
    if type == "item" then
        return prototypes.item[short_name]
    end
    return prototypes.fluid[short_name]
end

--production_rate nil: a row of a result without rates
local function add_item_cell(report, product_full_name, production_rate)
    local item_cell = report.add{type = "flow"}
    item_cell.style.horizontally_stretchable = true

    local prototype = prototype_of(product_full_name)
    item_cell.add{type = "sprite", sprite = product_full_name, tooltip = prototype.localised_name}

    item_cell.add{type = "label", caption = production_rate and (format_by_precision(production_rate, report.player_index) .. " /s") or ""}
end

local function add_byproduct_widgets(report)
    report.add{type = "label", caption = {"hxrrc.byproduct"}}
    report.add{type = "empty-widget"}
    report.add{type = "empty-widget"}
end

local function add_recipe_cell(report, product_full_name, recipe)
    local recipe_cell = report.add{type = "flow"}
    recipe_cell.style.horizontally_stretchable = true
    local type, product_short_name = split_product_name(product_full_name)
    recipe_cell.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_recipe_button",
        tooltip = {"hxrrc.empty_the_recipe_button"},
        elem_tooltip = recipe and {type = "recipe", name = recipe.name},
        elem_type = "recipe",
        recipe = recipe and recipe.name,
        tags = {product_full_name = product_full_name}, --used in Calculator.on_gui_elem_changed
        elem_filters = {
            {
                filter = type == "item" and "has-product-item" or "has-product-fluid",
                elem_filters = {{filter = "name", name = product_short_name}},
            },
        },
    }
end

--One filter per category the recipe can be crafted through; filters in a list combine with "or"
local function crafting_category_filters(recipe)
    local filters = {}
    for _, category in ipairs(Utils.recipe_categories(recipe)) do
        filters[#filters + 1] = {filter = "crafting-category", crafting_category = category}
    end
    return filters
end

--reason: locale key shown in place of the machine count, for a row whose count cannot be trusted or does not exist
local function add_machine_cell(report, crafting_machine, recipe, recipe_rate, crafting_machine_identifier, round_up_machines, reason, product_full_name)
    local pi = report.player_index
    local machine_cell = report.add{type = "flow"}
    machine_cell.style.horizontally_stretchable = true
    --the machine:
    machine_cell.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_crafting_machine_button",
        elem_type = "entity-with-quality",
        ["entity-with-quality"] = {name = crafting_machine.name, quality = crafting_machine_identifier.quality},
        --snapshot for refused changes on a stale report, and the row the button belongs to
        tags = {name = crafting_machine.name, quality = crafting_machine_identifier.quality, recipe_name = recipe.name, product_full_name = product_full_name},
        elem_filters = crafting_category_filters(recipe),
        enabled = #Utils.crafting_machines_for(recipe) > 1,
    }

    --the machine amount:
    local label = machine_cell.add{type = "label", name = "label"}
    if reason then
        label.caption = {"hxrrc." .. reason}
        return
    end
    local machine_amount = Utils.machine_amount(recipe, recipe_rate, crafting_machine, pi, crafting_machine_identifier.quality)
    if round_up_machines then --labels only: rates, energy and pollution stay exact
        label.caption = " x " .. rounded_up_count_text(machine_amount)
        label.tooltip = format_by_precision(machine_amount, pi)
    else
        label.caption = " x " .. format_by_precision( machine_amount, pi)
    end
end

--A row of a recipe the system uses. Rates are nil on a diagnostic row: its editors are all there, its numbers are not.
local function add_row_for_solved_product(report, product_full_name, product_rate, recipe_rate, round_up_machines, reason)
    local pi = report.player_index
    local recipe = storage[pi].recipes_by_product_full_name[product_full_name]

    add_item_cell(report, product_full_name, product_rate)

    --Crafting machine and module cells:
    local crafting_machine_identifier = storage[pi].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name]
    if not crafting_machine_identifier then --the recipe only supports manual crafting:
        report.add{type = "label", caption = {"hxrrc." .. (reason or "not_automatically_craftable")}}
        report.add{type = "empty-widget"}
    else
        local crafting_machine = prototypes.entity[crafting_machine_identifier.name]
        add_machine_cell(report, crafting_machine, recipe, recipe_rate, crafting_machine_identifier, round_up_machines, reason, product_full_name)
        ModuleGUI.new(report, recipe, crafting_machine, crafting_machine_identifier, product_full_name)
    end

    add_recipe_cell(report, product_full_name, recipe)
end

local function add_row_for_unsolved_product(report, unsolved_product_full_name, unsolved_product_rate)
    add_item_cell(report, unsolved_product_full_name, unsolved_product_rate)

    if unsolved_product_rate < 0 then
        add_byproduct_widgets(report)
    else --TODO See what happens for undecomposable products
        report.add{type = "label", caption = {"hxrrc.unselected_recipe"}}
        report.add{type = "empty-widget"}
        add_recipe_cell(report, unsolved_product_full_name)
    end
end

local function new_table(parent)
    return parent.add{type = "table", name = "report", column_count = 4, draw_horizontal_lines = true, draw_vertical_lines = true}
end

--A solved result (see Solver.solve_for). energy_consumption and pollution are nil when the result is infeasible, and the header then shows no totals.
--round_up_machines: show machine counts as whole machines (nil or false keeps exact counts)
function Report.new(parent, result, energy_consumption, pollution, round_up_machines)
    local report = new_table(parent)

    setup_headers(report, energy_consumption, pollution)

    --Rows whose item or fluid was removed by a mod are left out: their sprites and filters would refer to missing prototypes
    for _, column in ipairs(result.columns) do
        local product_full_name = column.product_full_name
        if prototype_of(product_full_name) then
            add_row_for_solved_product(report, product_full_name, result.solved_rates[product_full_name], result.recipe_rates[column.recipe_name],
                round_up_machines, result.reasons_by_column[column.recipe_name])
        end
    end

    --Holds exactly the products without a solved row, including byproducts whose bound recipe is not used here
    for product_full_name, product_rate in pairs(result.unsolved_rates) do
        if prototype_of(product_full_name) then
            add_row_for_unsolved_product(report, product_full_name, product_rate)
        end
    end
end

--A result without rates: one row per used recipe with its reason and every editor it has in a solved report, so the cause can be fixed from here
function Report.new_diagnostic(parent, result)
    local report = new_table(parent)

    setup_headers(report, nil, nil, result.status == "unsolvable")

    for _, column in ipairs(result.columns) do
        if prototype_of(column.product_full_name) then
            --a row without a reason still shows a blank label where its count would be
            add_row_for_solved_product(report, column.product_full_name, nil, nil, false, result.reasons_by_column[column.recipe_name] or "no_rate")
        end
    end
end

--The recipe a machine button acts on, from its tags, while its row's product is still bound to that recipe; nil for a stale button or one built before rows were tagged
local function current_recipe_name_of(choose_crafting_machine_button)
    local tags = choose_crafting_machine_button.tags
    if not (tags.recipe_name and tags.product_full_name) then
        return nil
    end
    local bound_recipe = storage[choose_crafting_machine_button.player_index].recipes_by_product_full_name[tags.product_full_name]
    if bound_recipe and bound_recipe.valid and bound_recipe.name == tags.recipe_name then
        return tags.recipe_name
    end
end

--The machine a refused change puts back: the button's snapshot, unless that machine no longer exists; a removed quality falls back to normal
local function restored_machine(choose_crafting_machine_button)
    local tags = choose_crafting_machine_button.tags
    if tags.name and prototypes.entity[tags.name] then
        local quality = tags.quality and prototypes.quality[tags.quality] and tags.quality or nil
        return {name = tags.name, quality = quality}
    end
end

local function is_same_machine(a, b)
    if not a or not b then
        return not a and not b
    end
    return a.name == b.name and a.quality == b.quality
end

function Report.handle_crafting_machine_change(event)
    local player_index = event.player_index
    local choose_crafting_machine_button = event.element
    local new_machine_identifier = choose_crafting_machine_button.elem_value
    local restore_target = restored_machine(choose_crafting_machine_button)

    --a refused change restores the button, which may raise this event again: the restored value is then a no-op
    if is_same_machine(new_machine_identifier, restore_target) then
        return false
    end

    local recipe_name = current_recipe_name_of(choose_crafting_machine_button)
    local old_machine_identifier = recipe_name and storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name]
    if not old_machine_identifier then --stale report: the row's recipe changed or was removed by a mod
        if restore_target then
            choose_crafting_machine_button.elem_value = restore_target
        end
        return false
    end

    if not new_machine_identifier then
        game.get_player(player_index).create_local_flying_text{text = {"hxrrc.cannot_empty_a_choose_crafting_machine_button_error"}, create_at_cursor = true}
        choose_crafting_machine_button.elem_value = old_machine_identifier
        return false
    elseif new_machine_identifier.name == old_machine_identifier.name and new_machine_identifier.quality == old_machine_identifier.quality then
        return false
    end

    storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name] = new_machine_identifier
    ModuleSetup.sanitize(player_index, recipe_name) --the new machine may have fewer slots or refuse some modules
    local tags = choose_crafting_machine_button.tags
    choose_crafting_machine_button.tags = {name = new_machine_identifier.name, quality = new_machine_identifier.quality,
        recipe_name = tags.recipe_name, product_full_name = tags.product_full_name}

    return true
end

function Report.handle_recipe_binding_change(event)
    local pi = event.player_index
    local button = event.element
    local product_full_name = button.tags.product_full_name
    local old_recipe = storage[pi].recipes_by_product_full_name[product_full_name]
    local name_of_old_recipe = old_recipe and old_recipe.name
    local name_of_new_recipe = button.elem_value

    if name_of_old_recipe == name_of_new_recipe then
        return false
    elseif name_of_new_recipe and storage[pi].product_full_names_by_recipe_name[name_of_new_recipe] then
        game.get_player(pi).create_local_flying_text{text = {"hxrrc.recipe_already_used_by_another_product_error"}, create_at_cursor = true}
        button.elem_value = name_of_old_recipe
        return false
    end

    storage[pi].recipes_by_product_full_name[product_full_name] = name_of_new_recipe and prototypes.recipe[name_of_new_recipe]
    if name_of_new_recipe then
        storage[pi].product_full_names_by_recipe_name[name_of_new_recipe] = product_full_name
    end
    if name_of_old_recipe then
        storage[pi].product_full_names_by_recipe_name[name_of_old_recipe] = nil
    end

    return true
end

--Exposed for offline tests only
Report._rounded_up_count_text = rounded_up_count_text

return Report