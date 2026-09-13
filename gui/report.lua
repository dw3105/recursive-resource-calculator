local ModuleGUI = require "gui.modulegui"
local Utils = require "logic.utils"

local Report = {}

local function format_by_precision(float, player_index)
    local precision = settings.get_player_settings(player_index)["hxrrc-displayed-floating-point-precision"].value

    return string.format("%." .. precision .. "f", float)
end

local function add_header(report, caption, tooltip)
    local header = report.add{type = "flow"}
    header.style.horizontally_stretchable = true
    header.style.horizontal_align = "center"
    local label = header.add{type = "label", caption = caption, tooltip = tooltip}
    label.style.right_padding = 4
end

local function setup_headers(report, energy_consumption, pollution)
    add_header(report, {"", {"hxrrc.consumption"}, ":"}, {"hxrrc.consumption_header_tooltip"})
    report.add{type = "label", caption = format_by_precision(energy_consumption / 1000000, report.player_index) .. " MW"}

    add_header(report, {"", {"hxrrc.pollution"}, ":"}, {"hxrrc.pollution_header_tooltip"})
    report.add{type = "flow", name = "pollution_flow"}

    report.pollution_flow.add{type = "label", caption = format_by_precision(pollution * 60, report.player_index) .. " /m"}

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

local function add_item_cell(report, product_full_name, production_rate)
    local item_cell = report.add{type = "flow"}
    item_cell.style.horizontally_stretchable = true

    local type, short_name = split_product_name(product_full_name)

    local prototype = type == "item" and prototypes.item[short_name] or prototypes.fluid[short_name]
    item_cell.add{type = "sprite", sprite = product_full_name, tooltip = prototype.localised_name}

    item_cell.add{type = "label", caption = format_by_precision(production_rate, report.player_index) .. " /s"}
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

local function add_machine_cell(report, crafting_machine, recipe, recipe_rate, crafting_machine_identifier)
    local pi = report.player_index
    local machine_cell = report.add{type = "flow"}
    machine_cell.style.horizontally_stretchable = true
    --the machine:
    machine_cell.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_crafting_machine_button",
        elem_type = "entity-with-quality",
        ["entity-with-quality"] = {name = crafting_machine.name, quality = crafting_machine_identifier.quality},
        elem_filters = {{filter = "crafting-category", crafting_category = Utils.recipe_category(recipe)}},
        enabled = #storage.crafting_machines_by_category[Utils.recipe_category(recipe)] > 1,
    }

    --the machine amount:
    local machine_amount = Utils.machine_amount(recipe, recipe_rate, crafting_machine, pi, crafting_machine_identifier.quality)
    local label = machine_cell.add{type = "label", name = "label"}
    label.caption = " x " .. format_by_precision( machine_amount, pi)
end

local function add_row_for_solved_product(report, product_full_name, product_rate, recipe_rate)
    local pi = report.player_index
    local recipe = storage[pi].recipes_by_product_full_name[product_full_name]

    add_item_cell(report, product_full_name, product_rate)

    --Crafting machine and module cells:
    local crafting_machine_identifier = storage[pi].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name]
    if not crafting_machine_identifier then --the recipe only supports manual crafting:
        report.add{type = "label", caption = {"hxrrc.not_automatically_craftable"}}
        report.add{type = "empty-widget"}
    else
        local crafting_machine = prototypes.entity[crafting_machine_identifier.name]
        add_machine_cell(report, crafting_machine, recipe, recipe_rate, crafting_machine_identifier)
        ModuleGUI.new(report, recipe.name, crafting_machine.allowed_effects)
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

function Report.new(parent, recipe_rates_by_recipe_name, solved_rates_by_product_full_name, unsolved_rates_by_product_full_name, energy_consumption, pollution)
    local report = parent.add{type = "table", name = "report", column_count = 4, draw_horizontal_lines = true, draw_vertical_lines = true}
    local pi = report.player_index

    setup_headers(report, energy_consumption, pollution)

    for recipe_name, recipe_rate in pairs(recipe_rates_by_recipe_name) do
        local product_full_name = storage[pi].product_full_names_by_recipe_name[recipe_name]
        add_row_for_solved_product(report, product_full_name, solved_rates_by_product_full_name[product_full_name], recipe_rate)
    end

    --Holds exactly the products without a solved row, including byproducts whose bound recipe is not used here
    for product_full_name, product_rate in pairs(unsolved_rates_by_product_full_name) do
        add_row_for_unsolved_product(report, product_full_name, product_rate)
    end
end

local function get_recipe_name_associated_to(choose_crafting_machine_button)
    local machine_cell = choose_crafting_machine_button.parent
    local report = machine_cell.parent
    local recipe_cell = report.children[machine_cell.get_index_in_parent() + 2]
    return recipe_cell.hxrrc_choose_recipe_button.elem_value
end

function Report.handle_crafting_machine_change(event)
    local player_index = event.player_index
    local choose_crafting_machine_button = event.element
    local recipe_name = get_recipe_name_associated_to(choose_crafting_machine_button)
    local old_machine_identifier = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name]
    local new_machine_identifier = choose_crafting_machine_button.elem_value

    if not new_machine_identifier then
        game.get_player(player_index).create_local_flying_text{text = {"hxrrc.cannot_empty_a_choose_crafting_machine_button_error"}, create_at_cursor = true}
        choose_crafting_machine_button.elem_value = old_machine_identifier
        return false
    elseif new_machine_identifier.name == old_machine_identifier.name and new_machine_identifier.quality == old_machine_identifier.quality then
        return false
    end

    storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name] = new_machine_identifier

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

return Report