local ModuleGUI = require "gui.modulegui"
local ModuleSetup = require "logic.module_setup"
local Solver = require "logic.solver"
local Burners = require "logic.burners"
local Utils = require "logic.utils"
local QualityLoop = require "logic.quality_loop"
local QualityLoops = require "logic.quality_loops"

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

--nil once the mod adding the item or fluid is removed; parts: those of an item above normal quality, whose full name is never split
local function prototype_of(product_full_name, parts)
    if parts then
        return prototypes.item[parts.name]
    end
    local type, short_name = split_product_name(product_full_name)
    if type == "item" then
        return prototypes.item[short_name]
    end
    return prototypes.fluid[short_name]
end

--production_rate nil: a row of a result without rates. An item above normal quality (parts given) shows its quality on a sprite-button.
local function add_item_cell(report, product_full_name, production_rate, parts)
    local item_cell = report.add{type = "flow"}
    item_cell.style.horizontally_stretchable = true

    local prototype = prototype_of(product_full_name, parts)
    if parts then
        item_cell.add{type = "sprite-button", sprite = "item/" .. parts.name, quality = parts.quality, tooltip = prototype.localised_name}
    else
        item_cell.add{type = "sprite", sprite = product_full_name, tooltip = prototype.localised_name}
    end

    item_cell.add{type = "label", caption = production_rate and (format_by_precision(production_rate, report.player_index) .. " /s") or ""}
end

--consumer: the button picks a recipe that consumes the product (any recipe with it as ingredient) instead of one that makes it
local function add_recipe_cell(report, product_full_name, recipe, consumer)
    local recipe_cell = report.add{type = "flow"}
    recipe_cell.style.horizontally_stretchable = true
    local type, product_short_name = split_product_name(product_full_name)
    recipe_cell.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_recipe_button",
        tooltip = consumer and {"hxrrc.choose_consumer_tooltip"} or {"hxrrc.empty_the_recipe_button"},
        elem_tooltip = recipe and {type = "recipe", name = recipe.name},
        elem_type = "recipe",
        recipe = recipe and recipe.name,
        tags = {product_full_name = product_full_name, consumer = consumer or nil}, --used in Report.handle_recipe_binding_change
        elem_filters = {
            {
                filter = (consumer and "has-ingredient-" or "has-product-") .. type,
                elem_filters = {{filter = "name", name = product_short_name}},
            },
        },
    }
    --a product to get rid of may also be burnt, when some entity accepts it as fuel
    local accepted = consumer and Burners.accepted_names(product_full_name) or {}
    if #accepted > 0 then
        local burner = storage[report.player_index].burners_by_product_full_name[product_full_name]
        local value = burner and {name = burner.name, quality = burner.quality}
        recipe_cell.add{
            type = "choose-elem-button",
            name = "hxrrc_choose_burner_button",
            tooltip = {"hxrrc.choose_burner_tooltip"},
            elem_type = "entity-with-quality",
            ["entity-with-quality"] = value,
            elem_filters = {{filter = "name", name = accepted}},
            tags = {product_full_name = product_full_name},
        }
    end
    return recipe_cell
end

local function add_byproduct_widgets(report, product_full_name)
    report.add{type = "label", caption = {"hxrrc.byproduct"}}
    report.add{type = "empty-widget"}
    add_recipe_cell(report, product_full_name, nil, true)
end

--A row of a product burnt as fuel: the entity and how many burn it at their maximum draw, no modules, and the controls to change how it is disposed of
local function add_row_for_burner(report, column, product_rate, rate, round_up_machines, reason)
    local pi = report.player_index
    local product_full_name, burner = column.product_full_name, column.burner
    add_item_cell(report, product_full_name, product_rate)

    local machine_cell = report.add{type = "flow"}
    machine_cell.style.horizontally_stretchable = true
    machine_cell.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_burner_entity_button",
        elem_type = "entity-with-quality",
        ["entity-with-quality"] = {name = burner.name, quality = burner.quality},
        elem_filters = {{filter = "name", name = Burners.accepted_names(product_full_name)}},
        tags = {name = burner.name, quality = burner.quality, product_full_name = product_full_name}, --snapshot for refused changes on a stale report
    }
    local label = machine_cell.add{type = "label", name = "label"}
    if reason then
        label.caption = {"hxrrc." .. reason}
    else
        local units_per_entity = Burners.draw(product_full_name, burner)
        local count = rate / units_per_entity
        if round_up_machines then
            label.caption = " x " .. rounded_up_count_text(count)
        else
            label.caption = " x " .. format_by_precision(count, pi)
        end
        label.tooltip = {"hxrrc.burner_count_tooltip", format_by_precision(count, pi)}
    end

    report.add{type = "empty-widget"}
    add_recipe_cell(report, product_full_name, nil, true)
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
        elem_filters = crafting_category_filters(recipe), --always enabled: with one machine, its quality can still be picked
    }

    --the machine amount:
    local label = machine_cell.add{type = "label", name = "label"}
    if reason then
        label.caption = {"hxrrc." .. reason}
        return
    end
    local machine_amount = Utils.machine_amount(recipe, recipe_rate, crafting_machine, crafting_machine_identifier.quality,
        storage[pi].module_setups_by_recipe_name[recipe.name])
    if round_up_machines then --labels only: rates, energy and pollution stay exact
        label.caption = " x " .. rounded_up_count_text(machine_amount)
        label.tooltip = format_by_precision(machine_amount, pi)
    else
        label.caption = " x " .. format_by_precision( machine_amount, pi)
    end
end

--A row of a column the system uses. Rates are nil on a diagnostic row: its editors are all there, its numbers are not.
local function add_row_for_solved_product(report, column, product_rate, recipe_rate, round_up_machines, reason)
    if column.burner then
        add_row_for_burner(report, column, product_rate, recipe_rate, round_up_machines, reason)
        return
    end
    local product_full_name = column.product_full_name
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

    add_recipe_cell(report, product_full_name, recipe, storage[pi].consumer_product_full_names[product_full_name])
end

local add_recycle_recipe_button

--loops: the loop infos crafting this row's item, when it is a normal item a loop leaves over (see Report.new)
local function add_row_for_unsolved_product(report, unsolved_product_full_name, unsolved_product_rate, parts, loops)
    add_item_cell(report, unsolved_product_full_name, unsolved_product_rate, parts)

    if parts then
        --bindings are kept by plain item names, so an item above normal quality is made through its item's producer and has no consumer or burner control
        if unsolved_product_rate < 0 then
            report.add{type = "label", caption = {"hxrrc.byproduct"}}
            report.add{type = "empty-widget"}
            report.add{type = "empty-widget"}
        else
            report.add{type = "label", caption = {"hxrrc.unselected_recipe"}}
            report.add{type = "empty-widget"}
            add_recipe_cell(report, "item/" .. parts.name)
        end
    elseif unsolved_product_rate < 0 and loops then
        --a consumer or burner would replace the item's producer binding and break its loops: its excess is recycled by a loop instead
        report.add{type = "label", caption = {"hxrrc.byproduct"}}
        report.add{type = "empty-widget"}
        local recipe_cell = report.add{type = "flow", direction = "vertical"}
        recipe_cell.style.horizontally_stretchable = true
        for _, info in ipairs(loops) do
            local quality = prototypes.quality[info.quality]
            add_recycle_recipe_button(recipe_cell.add{type = "flow"}, info.key, info.item, info.config.recycle_recipe_name,
                {"", {"hxrrc.choose_recycle_recipe_tooltip"}, "\n", quality and quality.localised_name or info.quality})
        end
    elseif unsolved_product_rate < 0 then
        add_byproduct_widgets(report, unsolved_product_full_name)
    else --TODO See what happens for undecomposable products
        report.add{type = "label", caption = {"hxrrc.unselected_recipe"}}
        report.add{type = "empty-widget"}
        add_recipe_cell(report, unsolved_product_full_name)
    end
end

--Upgrade chances of one craft or recycle from a tier, one line per tier it can end at
local function chances_tooltip(chain, chances)
    local tooltip = {"", {"hxrrc.quality_chances_tooltip"}}
    for index, quality in ipairs(chain) do
        local share = chances[index]
        if share and share > 0 and #tooltip < 20 then --a localised string takes at most 20 parameters
            tooltip[#tooltip + 1] = {"", "\n", quality.localised_name, ": ", string.format("%.4g", share * 100) .. "%"}
        end
    end
    return tooltip
end

--Chances of the quality loop's recycle line or pool, one line per tier
local function per_tier_tooltip(header, chain_names, counts, pi)
    local tooltip = {"", {header}}
    for index, entry in ipairs(counts) do
        if #tooltip < 20 then --a localised string takes at most 20 parameters
            tooltip[#tooltip + 1] = {"", "\n", prototypes.quality[entry.quality].localised_name, ": ", format_by_precision(entry.count, pi)}
        end
    end
    return tooltip
end

--A loop's machine button: tier nil for the recycler pool
local function add_loop_machine_button(line, info, stage_name, stage, tier)
    line.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_loop_machine_button",
        elem_type = "entity-with-quality",
        ["entity-with-quality"] = {name = stage.machine.name, quality = stage.machine.quality},
        elem_filters = crafting_category_filters(stage.recipe), --always enabled: with one machine, its quality can still be picked
        --snapshot for refused changes on a stale report, and the loop stage the button edits
        tags = {name = stage.machine.name, quality = stage.machine.quality, loop_key = info.key, stage = stage_name, tier = tier, recipe_name = stage.recipe.name},
    }
end

local function count_caption(machine_amount, round_up_machines, pi)
    return " x " .. (round_up_machines and rounded_up_count_text(machine_amount) or format_by_precision(machine_amount, pi))
end

--The module editor of a loop stage (tier nil for the recycler pool), in a flow of its own tagged with the stage
local function add_loop_module_cell(report, info, stage_name, stage, tier)
    local cell = report.add{type = "flow", direction = "vertical", tags = {stage = stage_name, tier = tier}}
    if stage and stage.machine then
        ModuleGUI.new(cell, stage.recipe, stage.prototype, stage.machine, info.key, {loop_key = info.key, stage = stage_name, tier = tier})
    else
        cell.add{type = "empty-widget"}
    end
end

--The loop's recipe control: the recipe its item is bound to and the quality its ingredients come at
local function add_loop_recipe_cell(report, info)
    local pi = report.player_index
    local recipe = QualityLoops.producer_of(pi, info.item)
    local shown = {name = recipe and recipe.name, quality = info.config.start_quality}
    local recipe_cell = report.add{type = "flow"}
    recipe_cell.style.horizontally_stretchable = true
    recipe_cell.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_loop_recipe_button",
        tooltip = {"hxrrc.choose_loop_recipe_tooltip"},
        elem_tooltip = recipe and {type = "recipe", name = recipe.name},
        elem_type = "recipe-with-quality",
        ["recipe-with-quality"] = shown.name and {name = shown.name, quality = shown.quality},
        elem_filters = {{filter = "has-product-item", elem_filters = {{filter = "name", name = info.item}}}},
        tags = {product_full_name = "item/" .. info.item, loop_key = info.key, shown = shown}, --the whole value shown, for Report.handle_loop_recipe_change
    }
end

--A loop's recycle recipe control. It lists the recipes taking the item in the categories of the recipes that can recycle it: in vanilla exactly its
--recycling recipe; anything else listed is refused on pick. Disabled, with a hint, when no recipe can recycle the item and none is set.
function add_recycle_recipe_button(parent, loop_key, item, recycle_recipe_name, tooltip)
    local takes_item = {filter = "has-ingredient-item", elem_filters = {{filter = "name", name = item}}}
    local filters = {}
    for _, category in ipairs(QualityLoops.recycle_recipe_categories(item)) do
        filters[#filters + 1] = takes_item
        filters[#filters + 1] = {filter = "category", category = category, mode = "and"}
    end
    local enabled = #filters > 0 or recycle_recipe_name ~= nil
    return parent.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_recycle_recipe_button",
        tooltip = enabled and tooltip or {"hxrrc.no_recycle_recipe_tooltip"},
        elem_type = "recipe",
        recipe = recycle_recipe_name,
        elem_filters = #filters > 0 and filters or {takes_item},
        enabled = enabled,
        tags = {loop_key = loop_key, recipe_name = recycle_recipe_name},
    }
end

--A tier's recipe control above the loop's start quality: the recipe the tier crafts with (QualityLoops.tier_recipe); emptied, it is chosen automatically
local function add_tier_recipe_cell(report, info, tier_quality)
    local recipe_cell = report.add{type = "flow"}
    recipe_cell.style.horizontally_stretchable = true
    local recipe = QualityLoops.tier_recipe(report.player_index, info.config, tier_quality)
    local shown = recipe and recipe.name
    recipe_cell.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_tier_recipe_button",
        tooltip = {"hxrrc.choose_tier_recipe_tooltip"},
        elem_type = "recipe",
        recipe = shown,
        elem_filters = {{filter = "has-product-item", elem_filters = {{filter = "name", name = info.item}}}},
        tags = {loop_key = info.key, tier = tier_quality, shown = shown}, --the recipe shown, for Report.handle_tier_recipe_change
    }
end

--The row of the assist crafts, right after the start tier's: items recycling returns at the start quality crafted into the item by another recipe
local function add_assist_row(report, info, first_tier, recipe_rate, round_up_machines, solved)
    local pi = report.player_index
    local stage = QualityLoops.stage(pi, info.config, "assist")
    local start = info.config.start_quality
    local item_cell = report.add{type = "flow", tags = {loop_key = info.key, assist = true}}
    item_cell.style.horizontally_stretchable = true
    item_cell.add{type = "sprite-button", sprite = "item/" .. info.item, quality = start, tooltip = prototypes.item[info.item].localised_name}
    item_cell.add{type = "label", caption = {"hxrrc.assist_row"}}
    local machine_cell = report.add{type = "flow", direction = "vertical"}
    local line = machine_cell.add{type = "flow", direction = "horizontal", tags = {stage = "assist"}}
    if stage and stage.machine then
        add_loop_machine_button(line, info, "assist", stage)
        local label = line.add{type = "label", caption = ""}
        if solved and first_tier.assist_crafts then
            label.caption = count_caption(Utils.machine_amount(stage.recipe, first_tier.assist_crafts * recipe_rate, stage.prototype, stage.machine.quality, stage.setup),
                round_up_machines, pi)
            label.tooltip = chances_tooltip(info.chain, first_tier.assist_chances or {})
        end
    elseif stage then
        line.add{type = "label", caption = {"hxrrc.not_automatically_craftable"}}
    else
        line.add{type = "label", caption = ""}
    end
    add_loop_module_cell(report, info, "assist", stage)
    local recipe_cell = report.add{type = "flow"}
    local shown = stage and stage.recipe.name
    recipe_cell.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_assist_recipe_button",
        tooltip = {"hxrrc.choose_assist_recipe_tooltip"},
        elem_type = "recipe",
        recipe = shown,
        elem_filters = {{filter = "has-product-item", elem_filters = {{filter = "name", name = info.item}}}},
        tags = {loop_key = info.key, shown = shown}, --the recipe shown, for Report.handle_assist_recipe_change
    }
end

--The rows of a quality loop: one per tier from the recipe's quality to the target, each with its crafting machines, their count and upgrade chances,
--its own module editor, and the recyclers running at that tier; then the recycler pool with the total, the recycler editors and the recycle recipe.
--A loop with a reason, or without rates, shows the same rows with every editor and no counts, the reason in the first craft line.
local function add_rows_for_quality_loop(report, column, recipe_rate, round_up_machines, reason)
    local pi = report.player_index
    local info = column.quality_loop
    local config = info.config
    local item_prototype = prototypes.item[info.item]

    if not config then --Factorio 2.1: quality loops are not calculated
        local item_cell = report.add{type = "flow"}
        item_cell.add{type = "sprite-button", sprite = "item/" .. info.item, quality = info.quality, tooltip = item_prototype.localised_name,
            tags = {loop_key = info.key, tier = info.quality}}
        item_cell.add{type = "label", caption = ""}
        local machine_cell = report.add{type = "flow", direction = "vertical"}
        machine_cell.add{type = "flow", tags = {stage = "craft"}}.add{type = "label", caption = {"hxrrc." .. reason}}
        report.add{type = "empty-widget"}
        add_recipe_cell(report, "item/" .. info.item, QualityLoops.producer_of(pi, info.item))
        return
    end

    local solved = not reason and recipe_rate and info.tiers
    local tiers = {}
    if solved then
        tiers = info.tiers
    else
        for _, quality in ipairs(QualityLoops.tier_names(config)) do tiers[#tiers + 1] = {quality = quality} end
    end
    local recycle = QualityLoops.stage(pi, config, "recycle")
    local recycler_counts, recycler_total = {}, 0

    for index, tier in ipairs(tiers) do
        local stage = QualityLoops.stage(pi, config, "craft", tier.quality)
        local item_cell = report.add{type = "flow"}
        item_cell.style.horizontally_stretchable = true
        item_cell.add{type = "sprite-button", sprite = "item/" .. info.item, quality = tier.quality ~= "normal" and tier.quality or nil,
            tooltip = item_prototype.localised_name, tags = {loop_key = info.key, tier = tier.quality}}
        item_cell.add{type = "label", caption = solved and (format_by_precision(tier.x * recipe_rate, pi) .. " /s") or ""}

        local machine_cell = report.add{type = "flow", direction = "vertical"}
        machine_cell.style.horizontally_stretchable = true
        local craft_line = machine_cell.add{type = "flow", direction = "horizontal", tags = {stage = "craft"}}
        if stage and stage.machine then
            add_loop_machine_button(craft_line, info, "craft", stage, tier.quality)
        end
        local craft_label = craft_line.add{type = "label", caption = ""}
        if index == 1 and reason then
            craft_label.caption = {"hxrrc." .. reason}
        elseif not (stage and stage.machine) then
            craft_label.caption = {"hxrrc.not_automatically_craftable"}
        elseif solved then
            craft_label.caption = count_caption(Utils.machine_amount(stage.recipe, tier.crafts * recipe_rate, stage.prototype, stage.machine.quality, stage.setup),
                round_up_machines, pi)
            craft_label.tooltip = chances_tooltip(info.chain, tier.craft_chances)
        end

        if recycle and index < #tiers then
            local recycle_line = machine_cell.add{type = "flow", direction = "horizontal", tags = {stage = "recycle"}}
            local recycle_label
            if recycle.machine then
                recycle_line.add{type = "sprite-button", sprite = "entity/" .. recycle.machine.name, quality = recycle.machine.quality,
                    tooltip = recycle.prototype.localised_name}
                recycle_label = recycle_line.add{type = "label", caption = ""}
                if solved then
                    local count = Utils.machine_amount(recycle.recipe, tier.recycle_crafts * recipe_rate, recycle.prototype, recycle.machine.quality, recycle.setup)
                    recycler_counts[#recycler_counts + 1] = {quality = tier.quality, count = count}
                    recycler_total = recycler_total + count
                    recycle_label.caption = count_caption(count, round_up_machines, pi)
                    recycle_label.tooltip = chances_tooltip(info.chain, tier.recycle_chances)
                end
            else
                recycle_line.add{type = "label", caption = {"hxrrc.not_automatically_craftable"}}
            end
        end

        add_loop_module_cell(report, info, "craft", stage, tier.quality)
        if index == 1 then
            add_loop_recipe_cell(report, info)
        else
            add_tier_recipe_cell(report, info, tier.quality)
        end
        if index == 1 and info.start_takes_no_items and info.start_leftovers == "craft" then
            add_assist_row(report, info, tier, recipe_rate, round_up_machines, solved)
        end
    end

    --the recycler pool: every tier's recyclers are one set of machines with one setup
    local pool_cell = report.add{type = "flow", tags = {loop_key = info.key, pool = true}}
    pool_cell.style.horizontally_stretchable = true
    pool_cell.add{type = "label", caption = {"hxrrc.recycler_pool"}}
    pool_cell.add{type = "label", caption = ""}
    local machine_cell = report.add{type = "flow", direction = "vertical"}
    local pool_line = machine_cell.add{type = "flow", direction = "horizontal", tags = {stage = "recycle"}}
    if recycle and recycle.machine then
        add_loop_machine_button(pool_line, info, "recycle", recycle)
        local label = pool_line.add{type = "label", caption = ""}
        if solved then
            local tooltip = per_tier_tooltip("hxrrc.recycler_pool_tooltip", info.chain, recycler_counts, pi)
            --items recycled into themselves: machines from each recipe's own work
            local names = {}
            for name, _ in pairs(tiers[1] and tiers[1].ingredient_recycles or {}) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do
                local recycler = info.ingredient_recycles[name]
                local recipe = prototypes.recipe[recycler.recipe_name]
                local count = Utils.machine_amount(recipe, tiers[1].ingredient_recycles[name] * recipe_rate, recycle.prototype, recycle.machine.quality, recycler.setup)
                recycler_total = recycler_total + count
                if #tooltip < 20 then tooltip[#tooltip + 1] = {"", "\n", recipe.localised_name, ": ", format_by_precision(count, pi)} end
            end
            for _, name in ipairs(info.kept_ingredients or {}) do
                if #tooltip < 20 then tooltip[#tooltip + 1] = {"", "\n", {"hxrrc.recycler_pool_ingredient_kept", prototypes.item[name].localised_name}} end
            end
            label.caption = count_caption(recycler_total, round_up_machines, pi)
            label.tooltip = tooltip
        end
    elseif recycle then
        pool_line.add{type = "label", caption = {"hxrrc.not_automatically_craftable"}}
    else
        pool_line.add{type = "label", caption = ""}
    end
    add_loop_module_cell(report, info, "recycle", recycle)
    local recipe_cell = report.add{type = "flow"}
    add_recycle_recipe_button(recipe_cell, info.key, info.item, config.recycle_recipe_name, {"hxrrc.choose_recycle_recipe_tooltip"})
end

local function new_table(parent)
    return parent.add{type = "table", name = "report", column_count = 4, draw_horizontal_lines = true, draw_vertical_lines = true}
end

--A solved result (see Solver.solve_for). energy_consumption and pollution are nil when the result is infeasible, and the header then shows no totals.
--round_up_machines: show machine counts as whole machines (nil or false keeps exact counts)
function Report.new(parent, result, energy_consumption, pollution, round_up_machines)
    local report = new_table(parent)

    setup_headers(report, energy_consumption, pollution)

    --the loops crafting each item, in column order; a 2.1 loop recycles nothing, so its item's excess keeps the ordinary controls
    local loops_by_item_full_name = {}
    for _, column in ipairs(result.columns) do
        local info = column.quality_loop
        if info and info.reason ~= "quality_loop_unavailable" and info.config and prototypes.item[info.item] then
            local full_name = "item/" .. info.item
            loops_by_item_full_name[full_name] = loops_by_item_full_name[full_name] or {}
            table.insert(loops_by_item_full_name[full_name], info)
        end
    end

    --Rows whose item or fluid was removed by a mod are left out: their sprites and filters would refer to missing prototypes
    for _, column in ipairs(result.columns) do
        local product_full_name = column.product_full_name
        if column.quality_loop then
            if prototypes.item[column.quality_loop.item] then
                add_rows_for_quality_loop(report, column, result.recipe_rates[column.recipe_name], round_up_machines,
                    result.reasons_by_column[column.recipe_name])
            end
        elseif prototype_of(product_full_name) then
            add_row_for_solved_product(report, column, result.solved_rates[product_full_name], result.recipe_rates[column.recipe_name],
                round_up_machines, result.reasons_by_column[column.recipe_name])
        end
    end

    --Holds exactly the products without a solved row, including byproducts whose bound recipe is not used here
    for product_full_name, product_rate in pairs(result.unsolved_rates) do
        local parts = result.product_parts and result.product_parts[product_full_name]
        if prototype_of(product_full_name, parts) then
            add_row_for_unsolved_product(report, product_full_name, product_rate, parts, not parts and loops_by_item_full_name[product_full_name] or nil)
        end
    end
end

--A result without rates: one row per used recipe with its reason and every editor it has in a solved report, so the cause can be fixed from here
function Report.new_diagnostic(parent, result)
    local report = new_table(parent)

    setup_headers(report, nil, nil, result.status == "unsolvable")

    for _, column in ipairs(result.columns) do
        if column.quality_loop then
            if prototypes.item[column.quality_loop.item] then
                add_rows_for_quality_loop(report, column, nil, false, result.reasons_by_column[column.recipe_name] or "no_rate")
            end
        elseif prototype_of(column.product_full_name) then
            --a row without a reason still shows a blank label where its count would be
            add_row_for_solved_product(report, column, nil, nil, false, result.reasons_by_column[column.recipe_name] or "no_rate")
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

--The locale key (without "hxrrc.") refusing to bind a product to a recipe, or nil: one recipe serves one product, and a consumer must consume it.
--recipe_name nil (emptying) is always allowed.
function Report.validate_binding(player_index, product_full_name, recipe_name, consumer)
    if not recipe_name then
        return nil
    end
    local owner = storage[player_index].product_full_names_by_recipe_name[recipe_name]
    if owner and owner ~= product_full_name then
        return "recipe_already_used_by_another_product_error"
    end
    if consumer then
        local net_amount = Solver.net_amount_of(prototypes.recipe[recipe_name], product_full_name, player_index)
        if not (net_amount and net_amount < 0) then
            return "recipe_does_not_consume_error"
        end
    end
end

--Binds a product to a recipe (nil unbinds), replacing its previous recipe or burner binding; checks come first, from Report.validate_binding
function Report.apply_binding(player_index, product_full_name, recipe_name, consumer)
    local player_storage = storage[player_index]
    local old_recipe = player_storage.recipes_by_product_full_name[product_full_name]
    if old_recipe then
        player_storage.product_full_names_by_recipe_name[old_recipe.name] = nil
    end
    player_storage.recipes_by_product_full_name[product_full_name] = recipe_name and prototypes.recipe[recipe_name]
    if recipe_name then
        player_storage.product_full_names_by_recipe_name[recipe_name] = product_full_name
        player_storage.burners_by_product_full_name[product_full_name] = nil --a product has one binding: a recipe or a burner
    end
    player_storage.consumer_product_full_names[product_full_name] = (recipe_name and consumer) or nil
end

--Returns true when the binding changed. A consumer button binds a recipe that consumes the product and flags it; any other button binds a producer.
--Each button shows only a binding of its own kind, so clearing a consumer button leaves a producer binding alone and the other way round.
function Report.handle_recipe_binding_change(event)
    local pi = event.player_index
    local player_storage = storage[pi]
    local button = event.element
    local product_full_name = button.tags.product_full_name
    local consumer = button.tags.consumer == true
    local old_recipe = player_storage.recipes_by_product_full_name[product_full_name]
    local name_of_old_recipe = old_recipe and old_recipe.name
    local shown_recipe_name = (player_storage.consumer_product_full_names[product_full_name] == true) == consumer and name_of_old_recipe or nil
    local name_of_new_recipe = button.elem_value

    --a refused pick restores the button, which may raise this event again: the restored value is then a no-op
    if shown_recipe_name == name_of_new_recipe then
        return false
    end
    local error_key = Report.validate_binding(pi, product_full_name, name_of_new_recipe, consumer)
    if error_key then
        game.get_player(pi).create_local_flying_text{text = {"hxrrc." .. error_key}, create_at_cursor = true}
        button.elem_value = shown_recipe_name
        return false
    end
    Report.apply_binding(pi, product_full_name, name_of_new_recipe, consumer)
    return true
end

local function same_entity(a, b)
    if not a or not b then
        return not a and not b
    end
    return a.name == b.name and (a.quality or "normal") == (b.quality or "normal")
end

local function as_identifier(value)
    return value and {name = value.name, quality = value.quality ~= "normal" and value.quality or nil}
end

--Returns true when the product's burner binding changed. Picking an entity replaces any recipe binding of the product; emptying removes the burner.
--Every refusal restores the stored binding, so a re-raised event is a no-op.
function Report.handle_burner_change(event)
    local pi = event.player_index
    local player_storage = storage[pi]
    local button = event.element
    local product_full_name = button.tags.product_full_name
    local current = player_storage.burners_by_product_full_name[product_full_name]
    local picked = as_identifier(button.elem_value)
    if same_entity(picked, current) then
        return false
    end
    if picked and not Burners.accepts(picked.name, product_full_name) then
        button.elem_value = current and {name = current.name, quality = current.quality}
        return false
    end

    if picked then
        local old_recipe = player_storage.recipes_by_product_full_name[product_full_name]
        if old_recipe then
            player_storage.product_full_names_by_recipe_name[old_recipe.name] = nil
        end
        player_storage.recipes_by_product_full_name[product_full_name] = nil
        player_storage.consumer_product_full_names[product_full_name] = nil
    end
    player_storage.burners_by_product_full_name[product_full_name] = picked
    return true
end

--Returns true when the burning entity of a current burner binding changed. A button whose binding changed or went since it was built is stale:
--refused and restored from its snapshot, as is emptying it or picking an entity that cannot burn the product.
function Report.handle_burner_entity_change(event)
    local pi = event.player_index
    local button = event.element
    local tags = button.tags
    local snapshot = tags.name and storage.burner_names[tags.name] and
        {name = tags.name, quality = tags.quality and prototypes.quality[tags.quality] and tags.quality or nil} or nil
    local picked = as_identifier(button.elem_value)
    if same_entity(picked, snapshot) then
        return false
    end
    local function restore()
        button.elem_value = snapshot and {name = snapshot.name, quality = snapshot.quality}
        return false
    end
    local burners = storage[pi].burners_by_product_full_name
    local current = burners[tags.product_full_name]
    if not current or not same_entity(current, {name = tags.name, quality = tags.quality}) then
        return restore()
    end
    if not picked then
        game.get_player(pi).create_local_flying_text{text = {"hxrrc.cannot_empty_a_choose_crafting_machine_button_error"}, create_at_cursor = true}
        return restore()
    end
    if not Burners.accepts(picked.name, tags.product_full_name) then
        return restore()
    end
    burners[tags.product_full_name] = picked
    button.tags = {name = picked.name, quality = picked.quality, product_full_name = tags.product_full_name}
    return true
end

--Returns true when a loop stage's machine changed. A button whose loop, stage recipe or machine changed since it was built is stale: refused
--and restored from its snapshot, as is emptying it or picking a machine that cannot craft the stage's recipe.
function Report.handle_loop_machine_change(event)
    local pi = event.player_index
    local button = event.element
    local tags = button.tags
    local snapshot = tags.name and prototypes.entity[tags.name] and
        {name = tags.name, quality = tags.quality and prototypes.quality[tags.quality] and tags.quality or nil} or nil
    local picked = as_identifier(button.elem_value)
    --a refused change restores the button, which may raise this event again: the restored value is then a no-op
    if same_entity(picked, snapshot) then
        return false
    end
    local function restore()
        button.elem_value = snapshot and {name = snapshot.name, quality = snapshot.quality}
        return false
    end
    local loop = storage[pi].quality_loops_by_key[tags.loop_key]
    local stage = loop and (tags.stage ~= "craft" or QualityLoops.crafts_at(loop, tags.tier)) and QualityLoops.stage(pi, loop, tags.stage, tags.tier)
    if not (stage and stage.machine and stage.recipe.name == tags.recipe_name and same_entity(stage.machine, {name = tags.name, quality = tags.quality})) then
        return restore()
    end
    if not picked then
        game.get_player(pi).create_local_flying_text{text = {"hxrrc.cannot_empty_a_choose_crafting_machine_button_error"}, create_at_cursor = true}
        return restore()
    end
    if not Utils.can_craft(picked.name, stage.recipe) then
        return restore()
    end
    local settings = tags.stage == "craft" and loop.crafts[tags.tier] or tags.stage == "assist" and loop.assist or loop.recycle
    settings.machine = picked
    ModuleSetup.sanitize_setup(settings.setup, picked, stage.recipe) --the new machine may have fewer slots or refuse some modules
    button.tags = {name = picked.name, quality = picked.quality, loop_key = tags.loop_key, stage = tags.stage, tier = tags.tier, recipe_name = tags.recipe_name}
    return true
end

--A recipe-with-quality value as {name, quality}, quality nil for normal whether the engine gives a name or a prototype
local function recipe_value(value)
    if not value then
        return nil
    end
    local quality = type(value.quality) == "table" and value.quality.name or value.quality
    return {name = value.name, quality = quality ~= "normal" and quality or nil}
end

--Returns true when a loop's recipe or the quality its ingredients come at changed. The button keeps the whole value it showed: it is stale unless
--the item is still bound to that recipe and the loop still starts at that quality. The picked recipe and quality are checked together before
--anything is stored; any refusal restores the shown value. Emptying unbinds the item and keeps the loop's configuration.
function Report.handle_loop_recipe_change(event)
    local pi = event.player_index
    local button = event.element
    local tags = button.tags
    local shown = tags.shown or {}
    local picked = recipe_value(button.elem_value)
    if (picked and picked.name) == shown.name and (picked and picked.quality) == shown.quality then
        return false
    end
    local function restore()
        local name = shown.name and prototypes.recipe[shown.name] and shown.name
        local quality = shown.quality and prototypes.quality[shown.quality] and shown.quality or nil
        button.elem_value = name and {name = name, quality = quality} or nil
        return false
    end
    local function refuse(error_key)
        game.get_player(pi).create_local_flying_text{text = {"hxrrc." .. error_key}, create_at_cursor = true}
        return restore()
    end
    local loop = storage[pi].quality_loops_by_key[tags.loop_key]
    local bound = loop and QualityLoops.producer_of(pi, loop.item)
    if not loop or (bound and bound.name) ~= shown.name or loop.start_quality ~= shown.quality then
        return restore()
    end

    if not picked then
        Report.apply_binding(pi, tags.product_full_name, nil, false)
        button.tags = {product_full_name = tags.product_full_name, loop_key = tags.loop_key, shown = {quality = shown.quality}}
        return true
    end
    if picked.name ~= shown.name then
        local error_key = Report.validate_binding(pi, tags.product_full_name, picked.name, false)
        if error_key then
            return refuse(error_key)
        end
    end
    if picked.quality then
        local indexes = {}
        for index, quality in ipairs(QualityLoop.chain()) do indexes[quality.name] = index end
        if not (prototypes.quality[picked.quality] and indexes[picked.quality] and indexes[loop.quality] and indexes[picked.quality] <= indexes[loop.quality]) then
            return refuse("start_quality_above_target_error")
        end
    end

    if picked.quality then
        local index
        for chain_index, quality in ipairs(QualityLoop.chain()) do
            if quality.name == picked.quality then index = chain_index end
        end
        if QualityLoop.tier_recipe_refusal(prototypes.recipe[picked.name], loop.item, index) == "quality_loop_recipe_without_item_ingredient" then
            return refuse("start_quality_needs_item_recipe_error")
        end
    end

    if picked.name ~= shown.name then
        Report.apply_binding(pi, tags.product_full_name, picked.name, false)
    end
    loop.start_quality = picked.quality
    button.tags = {product_full_name = tags.product_full_name, loop_key = tags.loop_key, shown = {name = picked.name, quality = picked.quality}}
    return true
end

--Returns true when the recipe a loop tier crafts with changed. The button keeps the recipe it showed: it is stale unless the loop still crafts at that
--tier, above its start quality, with that recipe. A pick that cannot craft the tier is refused; emptying goes back to the automatic choice. The tier's
--machine and modules are fitted to the recipe it now uses.
function Report.handle_tier_recipe_change(event)
    local pi = event.player_index
    local button = event.element
    local tags = button.tags
    local picked = button.elem_value
    if picked == tags.shown then
        return false
    end
    local function restore()
        button.elem_value = tags.shown and prototypes.recipe[tags.shown] and tags.shown or nil
        return false
    end
    local loop = storage[pi].quality_loops_by_key[tags.loop_key]
    if not (loop and QualityLoops.crafts_at(loop, tags.tier) and tags.tier ~= (loop.start_quality or "normal")) then
        return restore()
    end
    local current = QualityLoops.tier_recipe(pi, loop, tags.tier)
    if (current and current.name) ~= tags.shown then
        return restore()
    end
    if picked then
        local index
        for chain_index, quality in ipairs(QualityLoop.chain()) do
            if quality.name == tags.tier then index = chain_index end
        end
        if QualityLoop.tier_recipe_refusal(prototypes.recipe[picked], loop.item, index) then
            game.get_player(pi).create_local_flying_text{text = {"hxrrc.tier_recipe_refused_error"}, create_at_cursor = true}
            return restore()
        end
    end
    loop.crafts[tags.tier] = loop.crafts[tags.tier] or {setup = ModuleSetup.new_setup()}
    local settings = loop.crafts[tags.tier]
    settings.recipe_name = picked
    local recipe = QualityLoops.tier_recipe(pi, loop, tags.tier)
    if recipe then
        if not (settings.machine and Utils.can_craft(settings.machine.name, recipe)) then
            local chosen = storage[pi].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name]
            settings.machine = chosen and Utils.can_craft(chosen.name, recipe) and {name = chosen.name, quality = chosen.quality} or nil
        end
        if settings.machine then
            ModuleSetup.sanitize_setup(settings.setup, settings.machine, recipe)
        else
            settings.setup = ModuleSetup.new_setup()
        end
    end
    button.tags = {loop_key = tags.loop_key, tier = tags.tier, shown = recipe and recipe.name}
    return true
end

--Returns true when the recipe of a loop's assist crafts changed. Stale unless the loop's assist recipe is still the one shown; a pick that does not make
--the item from items is refused; emptying goes back to the automatic choice. The machine and modules are fitted to the recipe now used.
function Report.handle_assist_recipe_change(event)
    local pi = event.player_index
    local button = event.element
    local tags = button.tags
    local picked = button.elem_value
    if picked == tags.shown then
        return false
    end
    local function restore()
        button.elem_value = tags.shown and prototypes.recipe[tags.shown] and tags.shown or nil
        return false
    end
    local loop = storage[pi].quality_loops_by_key[tags.loop_key]
    local current = loop and QualityLoops.assist_recipe(pi, loop)
    if not loop or (current and current.name) ~= tags.shown then
        return restore()
    end
    if picked and QualityLoop.tier_recipe_refusal(prototypes.recipe[picked], loop.item, 2) then
        game.get_player(pi).create_local_flying_text{text = {"hxrrc.tier_recipe_refused_error"}, create_at_cursor = true}
        return restore()
    end
    loop.assist = loop.assist or {setup = ModuleSetup.new_setup()}
    local settings = loop.assist
    settings.recipe_name = picked
    settings.setup = settings.setup or ModuleSetup.new_setup()
    local recipe = QualityLoops.assist_recipe(pi, loop)
    if recipe then
        if not (settings.machine and Utils.can_craft(settings.machine.name, recipe)) then
            local chosen = storage[pi].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name]
            settings.machine = chosen and Utils.can_craft(chosen.name, recipe) and {name = chosen.name, quality = chosen.quality} or nil
        end
        if settings.machine then
            ModuleSetup.sanitize_setup(settings.setup, settings.machine, recipe)
        else
            settings.setup = ModuleSetup.new_setup()
        end
    end
    button.tags = {loop_key = tags.loop_key, shown = recipe and recipe.name}
    return true
end

--Returns true when a loop's recycle recipe changed. Emptying the button stops recycling; a pick that cannot recycle the item is refused.
--A button built before the loop's recycle recipe last changed is stale and restored.
function Report.handle_recycle_recipe_change(event)
    local pi = event.player_index
    local button = event.element
    local tags = button.tags
    local snapshot = tags.recipe_name and prototypes.recipe[tags.recipe_name] and tags.recipe_name or nil
    local picked = button.elem_value
    if picked == snapshot then
        return false
    end
    local function restore()
        button.elem_value = snapshot
        return false
    end
    local loop = storage[pi].quality_loops_by_key[tags.loop_key]
    if not loop or loop.recycle_recipe_name ~= tags.recipe_name then
        return restore()
    end
    local recycle = loop.recycle
    if picked then
        local recipe = prototypes.recipe[picked]
        if QualityLoop.recycler_refusal(recipe, loop.item) then
            game.get_player(pi).create_local_flying_text{text = {"hxrrc.recycle_recipe_refused_error"}, create_at_cursor = true}
            return restore()
        end
        loop.recycle_recipe_name = picked
        if not (recycle.machine and Utils.can_craft(recycle.machine.name, recipe)) then
            recycle.machine = Utils.get_any_crafting_machine_identifier_for(recipe)
        end
        if recycle.machine then
            ModuleSetup.sanitize_setup(recycle.setup, recycle.machine, recipe)
        else
            recycle.setup = ModuleSetup.new_setup()
        end
    else
        loop.recycle_recipe_name = nil
        recycle.machine = nil
        recycle.setup = ModuleSetup.new_setup()
    end
    button.tags = {loop_key = tags.loop_key, recipe_name = picked}
    return true
end

--Exposed for offline tests only
Report._rounded_up_count_text = rounded_up_count_text

return Report