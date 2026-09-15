local Utils = require "logic.utils"
local Burners = require "logic.burners"
local QualityId = require "logic.quality_id"
local QualityLoop = require "logic.quality_loop"
local QualityLoops = require "logic.quality_loops"

local Solver = {}

--Column key prefix of a quality loop; the rest is the target's identity
Solver.LOOP_PREFIX = "quality-loop:"

--Machine, research and module bonuses add up, and the total is capped by the recipe; machine_identifier nil is hand crafting
local function productivity_bonus(recipe, machine_identifier, setup, player_index)
    local player_recipe = game.players[player_index].force.recipes[recipe.name]
    local research_bonus = player_recipe and player_recipe.productivity_bonus or 0
    local effect_receiver = machine_identifier and prototypes.entity[machine_identifier.name].effect_receiver --optional in the API
    local machine_bonus = effect_receiver and effect_receiver.base_effect.productivity or 0
    local module_bonus = Utils.setup_effects(setup).productivity
    return math.min(math.max(machine_bonus + research_bonus + module_bonus, 0), recipe.maximum_productivity)
end

--The column key of a product's binding, when the walk follows it. Inputs follow any binding; outputs follow only a binding picked to
--get rid of them (a consumer recipe or a burner), so byproducts bound to a producer stay out of the system as before.
--An item above normal quality (it has parts) is made by its quality loop once its item has a producer, whether or not the loop was configured
--before (a target's, or an ingredient's of another loop); as an output it is never followed.
local function followed_binding(product_full_name, as_output, player_storage, product_parts, player_index)
    local parts = product_parts[product_full_name]
    if parts then
        if not as_output and QualityLoops.producer_of(player_index, parts.name) then
            return Solver.LOOP_PREFIX .. product_full_name
        end
        return nil
    end
    if player_storage.burners_by_product_full_name[product_full_name] then
        return Burners.COLUMN_PREFIX .. product_full_name
    end
    local recipe = player_storage.recipes_by_product_full_name[product_full_name]
    if recipe and (not as_output or player_storage.consumer_product_full_names[product_full_name]) then
        return recipe.name
    end
end

local function split_full_name(full_name)
    local slash = string.find(full_name, "/", 1, true)
    return full_name:sub(1, slash - 1), full_name:sub(slash + 1)
end

--The quality effect a stage's machine gives: its setup's and its own base effect, none when hand-crafted or when the recipe forbids quality (P10)
local function stage_quality_effect(stage)
    if not stage.machine then
        return 0
    end
    local allowed_effects = stage.recipe.allowed_effects
    if allowed_effects and allowed_effects.quality == false then
        return 0
    end
    local effect_receiver = stage.prototype.effect_receiver
    local base = effect_receiver and effect_receiver.base_effect.quality or 0
    return Utils.setup_effects(stage.setup).quality + base
end

--The quality chain with each quality's next_probability and whether the player's force unlocked it
local function chain_data(player_index)
    local chain = QualityLoop.chain()
    local force = game.players[player_index].force
    local next_probabilities, unlocked, indexes = {}, {}, {}
    for index, quality in ipairs(chain) do
        next_probabilities[index] = index < #chain and quality.next_probability or 0
        unlocked[index] = force.is_quality_unlocked(quality.name)
        indexes[quality.name] = index
    end
    return chain, next_probabilities, unlocked, indexes
end

--Net amounts per craft of a recipe crafted at normal quality by a machine with a setup. With a quality effect (Factorio 2.0), each item product's
--expected amount is spread over the qualities it can come out at before the ingredients are taken off, so an item that is both ingredient and
--product nets gross output at normal minus what the recipe takes. product_parts, when given, gains the parts of every item above normal.
local function column_net_amounts(recipe, identifier, setup, player_index, product_parts)
    local bonus = productivity_bonus(recipe, identifier, setup, player_index)
    local quality_effect = 0
    if not Utils.IS_2_1 then --quality mechanics of 2.1 are not verified
        quality_effect = stage_quality_effect({recipe = recipe, machine = identifier, prototype = identifier and prototypes.entity[identifier.name], setup = setup})
    end
    if not (quality_effect > 0) then
        return Utils.net_amounts_by_full_name(recipe, bonus)
    end
    local chain, next_probabilities, unlocked = chain_data(player_index)
    local shares = QualityLoop.distribution(next_probabilities, unlocked, 1, quality_effect)
    local net_amounts, gross_by_item = {}, {}
    for _, product in ipairs(recipe.products) do
        if product.type == "item" then
            gross_by_item[product.name] = (gross_by_item[product.name] or 0) + Utils.product_amount(product, bonus)
        elseif product.type == "fluid" then
            local full_name = "fluid/" .. product.name
            net_amounts[full_name] = (net_amounts[full_name] or 0) + Utils.product_amount(product, bonus)
        end
    end
    for item_name, gross in pairs(gross_by_item) do
        for tier, share in pairs(shares) do
            local full_name = "item/" .. item_name
            if tier > 1 then
                full_name = QualityId.encode(item_name, chain[tier].name)
                if product_parts then product_parts[full_name] = {type = "item", name = item_name, quality = chain[tier].name} end
            end
            net_amounts[full_name] = (net_amounts[full_name] or 0) + gross * share
        end
    end
    for _, ingredient in ipairs(recipe.ingredients) do
        local full_name = ingredient.type .. "/" .. ingredient.name
        net_amounts[full_name] = (net_amounts[full_name] or 0) - ingredient.amount
    end
    for full_name, net_amount in pairs(net_amounts) do
        if net_amount == 0 then net_amounts[full_name] = nil end
    end
    return net_amounts
end

--One craft tier's part of a loop: the stage's quality effect, net target output, item ingredients and byproducts, fluids, at its own productivity
local function craft_tier_spec(stage, item_name, player_index)
    local net = Utils.net_amounts_by_full_name(stage.recipe, productivity_bonus(stage.recipe, stage.machine, stage.setup, player_index))
    local spec = {quality_effect = stage_quality_effect(stage), output = net["item/" .. item_name] or 0,
        ingredients = {}, fluid_ingredients = {}, byproducts = {}, fluid_products = {}}
    for full_name, net_amount in pairs(net) do
        local product_type, name = split_full_name(full_name)
        local entry = {name = name, amount = math.abs(net_amount)}
        if product_type == "item" and name ~= item_name then
            table.insert(net_amount < 0 and spec.ingredients or spec.byproducts, entry)
        elseif product_type == "fluid" then
            table.insert(net_amount < 0 and spec.fluid_ingredients or spec.fluid_products, entry)
        end
    end
    table.sort(spec.ingredients, function(a, b) return a.name < b.name end) --a fixed order, so equal ties always resolve alike
    return spec
end

--Adds a balance result's flows per target to net amounts: items by identity (parts of those above normal recorded), fluids plain
local function add_balance_nets(net_amounts, result, chain, product_parts, weight)
    weight = weight or 1
    for name, amounts_by_tier in pairs(result.items) do
        for tier, amount in pairs(amounts_by_tier) do
            local quality_name = chain[tier + result.offset].name
            local full_name = "item/" .. name
            if quality_name ~= "normal" then
                full_name = QualityId.encode(name, quality_name)
                product_parts[full_name] = {type = "item", name = name, quality = quality_name}
            end
            net_amounts[full_name] = (net_amounts[full_name] or 0) + weight * amount
        end
    end
    for name, amount in pairs(result.fluids) do
        net_amounts["fluid/" .. name] = (net_amounts["fluid/" .. name] or 0) + weight * amount
    end
end

--A balance result's tiers with their quality names, chances keyed by chain position like loop_info.chain
local function balance_tiers(result, chain)
    for index, tier in ipairs(result.tiers) do
        tier.quality = chain[index + result.offset].name
        for _, field in ipairs({"craft_chances", "recycle_chances", "assist_chances"}) do
            if tier[field] then
                local shifted = {}
                for slice_index, share in pairs(tier[field]) do shifted[slice_index + result.offset] = share end
                tier[field] = shifted
            end
        end
    end
    return result.tiers
end

--The column of the quality loop making the target key (parts: its item and quality), built from the loop's normalized configuration, which the
--column keeps for power, pollution, the report and storing. Its net amounts are per target item; items it takes or leaves above normal quality get
--their parts added to product_parts. column.quality_loop: {key, item, quality, config, chain, craft_recipe_name, recycle_recipe_name,
--tiers = {{quality, crafts, recycle_crafts, x, craft_chances, recycle_chances}}, reason}; chances are indexed by chain position.
--config: tests only, a raw configuration to build from in place of the normalized one (the guards must hold without normalizing)
local function loop_column(player_index, key, parts, product_parts, config, options)
    local loop_info = {key = key, item = parts.name, quality = parts.quality}
    local column = {recipe_name = Solver.LOOP_PREFIX .. key, product_full_name = key, consumer = false, quality_loop = loop_info,
        net_amounts = {[key] = 1}}
    if Utils.IS_2_1 then --quality mechanics of 2.1 are not verified
        loop_info.reason = "quality_loop_unavailable"
        return column
    end
    config = config or QualityLoops.normalized(player_index, key, parts)
    loop_info.config = config
    local craft_recipe = QualityLoops.producer_of(player_index, parts.name)
    loop_info.craft_recipe_name = craft_recipe.name
    loop_info.recycle_recipe_name = config.recycle_recipe_name

    local chain, next_probabilities, unlocked, indexes = chain_data(player_index)
    local reason, consumed = QualityLoop.tier_recipe_refusal(craft_recipe, parts.name, indexes[config.start_quality or "normal"] or 1)
    if not reason and config.recycle_recipe_name then
        reason, consumed = QualityLoop.recycler_refusal(prototypes.recipe[config.recycle_recipe_name], parts.name)
    end
    if reason then
        loop_info.reason = reason
        return column
    end

    loop_info.chain = chain
    local target = indexes[parts.quality]
    if not target then
        loop_info.reason = "quality_target_unreachable"
        return column
    end
    local start = indexes[config.start_quality or "normal"]

    --a tier above the start without a recipe crafts nothing: fine for a pure quality roll, but recycling would return items nothing uses
    local craft_tiers = {}
    for index = start or 1, target do
        local stage = QualityLoops.stage(player_index, config, "craft", chain[index].name)
        if stage then
            craft_tiers[index - (start or 1) + 1] = craft_tier_spec(stage, parts.name, player_index)
        elseif config.recycle_recipe_name then
            loop_info.reason = "quality_loop_tier_recipe_missing"
            return column
        else
            craft_tiers[index - (start or 1) + 1] = {none = true, quality_effect = 0, output = 0, ingredients = {}, fluid_ingredients = {}, byproducts = {}, fluid_products = {}}
        end
    end

    local recycle_spec
    local recycle = QualityLoops.stage(player_index, config, "recycle")
    if recycle then
        local bonus = productivity_bonus(recycle.recipe, recycle.machine, recycle.setup, player_index)
        recycle_spec = {quality_effect = stage_quality_effect(recycle), consumed = consumed, yields = {}, fluid_ingredients = {}, fluid_products = {}}
        for _, product in ipairs(recycle.recipe.products) do
            if product.type == "item" then
                recycle_spec.yields[product.name] = (recycle_spec.yields[product.name] or 0) + Utils.product_amount(product, bonus)
            elseif product.type == "fluid" then
                recycle_spec.fluid_products[#recycle_spec.fluid_products + 1] = {name = product.name, amount = Utils.product_amount(product, bonus)}
            end
        end
        for _, ingredient in ipairs(recycle.recipe.ingredients) do
            if ingredient.type == "fluid" then
                recycle_spec.fluid_ingredients[#recycle_spec.fluid_ingredients + 1] = {name = ingredient.name, amount = ingredient.amount}
            end
        end
    end

    --items recycling returns at the start quality, when the start recipe takes no items: left over, crafted by assist crafts, or recycled into
    --themselves in the recycler pool (the sheet's choice); otherwise the start crafts take what they use and the choice changes nothing
    local mode = options and options.start_leftovers or "byproduct"
    loop_info.start_leftovers = mode
    loop_info.start_takes_no_items = craft_tiers[1] ~= nil and not craft_tiers[1].none and #craft_tiers[1].ingredients == 0 --no tier 1: an unsanitized start the balance refuses
    local assist_spec, ingredient_recycles
    if loop_info.start_takes_no_items and mode == "craft" then
        local assist = QualityLoops.stage(player_index, config, "assist")
        if not assist then
            loop_info.reason = "quality_loop_assist_recipe_missing"
            return column
        end
        assist_spec = craft_tier_spec(assist, parts.name, player_index)
    elseif loop_info.start_takes_no_items and mode == "recycle" and recycle_spec then
        ingredient_recycles, loop_info.ingredient_recycles, loop_info.kept_ingredients = {}, {}, {}
        local names = {}
        for name, _ in pairs(recycle_spec.yields) do
            if name ~= parts.name then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local recipe = QualityLoops.self_recycle_recipe(name)
            if recipe and recycle.machine and Utils.can_craft(recycle.machine.name, recipe) then
                --its own recipe on the pool's machine, with the pool's modules as that recipe allows them
                local stage = {recipe = recipe, machine = recycle.machine, prototype = recycle.prototype,
                    setup = QualityLoops.fitted_setup_copy(recycle.setup, recycle.machine, recipe)}
                local bonus = productivity_bonus(recipe, stage.machine, stage.setup, player_index)
                local consumed, yield = 0, 0
                for _, ingredient in ipairs(recipe.ingredients) do
                    if ingredient.type == "item" then consumed = consumed + ingredient.amount end
                end
                for _, product in ipairs(recipe.products) do
                    if product.type == "item" then yield = yield + Utils.product_amount(product, bonus) end
                end
                ingredient_recycles[name] = {quality_effect = stage_quality_effect(stage), consumed = consumed, yield = yield}
                loop_info.ingredient_recycles[name] = {recipe_name = recipe.name, setup = stage.setup}
            else
                loop_info.kept_ingredients[#loop_info.kept_ingredients + 1] = name
            end
        end
    end

    --what fed parts need to be built from another start tier (see candidate_parts)
    loop_info.part_spec = {next_probabilities = next_probabilities, unlocked = unlocked, start = start, target = target, craft_tiers = craft_tiers,
        recycle_spec = recycle_spec, chain = chain}
    local result = QualityLoop.balance({next_probabilities = next_probabilities, unlocked = unlocked, start = start, target = target, item = parts.name,
        craft = {tiers = craft_tiers}, recycle = recycle_spec, assist = assist_spec, ingredient_recycles = ingredient_recycles})
    if result.reason then
        loop_info.reason = result.reason
        return column
    end
    add_balance_nets(column.net_amounts, result, chain, product_parts)
    loop_info.tiers = balance_tiers(result, chain)
    return column
end

--Candidate fed parts of a loop column (Amendment M3): for each tier q above the start whose recipe takes items, the loop crafted from q with the same
--settings, which makes the target from items at q made elsewhere on the sheet. Each: {index (chain position of q), quality, nets per target,
--tiers, feed (the identities at q it takes, sorted)}. None for a loop refused before its balance, or refused by it for any reason but reachability.
local function candidate_parts(column, product_parts)
    local info = column.quality_loop
    local spec = info.part_spec
    local found = {}
    if not spec or (info.reason and info.reason ~= "quality_target_unreachable") then
        return found
    end
    for q = spec.start + 1, spec.target do
        local tier_spec = spec.craft_tiers[q - spec.start + 1]
        if not tier_spec.none and #tier_spec.ingredients > 0 then
            local craft_tiers = {}
            for index = q, spec.target do craft_tiers[index - q + 1] = spec.craft_tiers[index - spec.start + 1] end
            local result = QualityLoop.balance({next_probabilities = spec.next_probabilities, unlocked = spec.unlocked, start = q, target = spec.target,
                item = info.item, craft = {tiers = craft_tiers}, recycle = spec.recycle_spec})
            if not result.reason then
                local nets = {[info.key] = 1}
                add_balance_nets(nets, result, spec.chain, product_parts)
                local quality_name = spec.chain[q].name
                local feed, feed_items = {}, {}
                for _, ingredient in ipairs(tier_spec.ingredients) do
                    local identity = QualityId.encode(ingredient.name, quality_name)
                    product_parts[identity] = {type = "item", name = ingredient.name, quality = quality_name}
                    feed[#feed + 1] = identity
                    feed_items[identity] = ingredient.name
                end
                table.sort(feed)
                found[#found + 1] = {index = q, quality = quality_name, nets = nets, tiers = balance_tiers(result, spec.chain), feed = feed, feed_items = feed_items}
            end
        end
    end
    return found
end

--Tests only: walk the queue last in, first out, to show the columns found do not depend on visiting order
Solver._reverse_visit_order = false

--The columns the targets need, found breadth first over every column kind; a key is visited once, so cyclic bindings terminate.
--Each column: {recipe_name (the column key: a recipe name, Burners.COLUMN_PREFIX .. product, or Solver.LOOP_PREFIX .. identity), product_full_name,
--consumer, burner, quality_loop, net_amounts}. A loop column's quality_loop.parts lists its eligible fed parts (M3).
--Discovery runs to a closure: candidate forced loops (unreachable alone) pull in the producers of the items their upper tiers take; fed parts become
--eligible when every identity they take is made by some column or eligible part and is no column's bound product (a least fixpoint computed afresh
--each pass, so the visiting order and self-feeding cycles cannot change it); each eligible part pulls in the producers and consumers of its normal
--items and fluids. It ends when a pass finds nothing new.
local function collect_columns(production_rates_by_product_full_name, player_index, product_parts, options)
    local player_storage = storage[player_index]
    local columns, queue, visited = {}, {}, {}
    local pending = 0
    local function enqueue(key, product_full_name)
        if key and not visited[key] then
            visited[key] = true
            queue[#queue + 1] = {key = key, product_full_name = product_full_name}
            pending = pending + 1
        end
    end
    local target_names = {}
    for product_full_name, _ in pairs(production_rates_by_product_full_name) do target_names[#target_names + 1] = product_full_name end
    table.sort(target_names)
    for _, product_full_name in ipairs(target_names) do
        enqueue(followed_binding(product_full_name, false, player_storage, product_parts, player_index), product_full_name)
    end

    local parts_by_column = {}
    local head = 1
    local function walk()
        while pending > 0 do
            local entry
            if Solver._reverse_visit_order then
                for index = #queue, 1, -1 do
                    if queue[index] then entry = queue[index]; queue[index] = false; break end
                end
            else
                while not queue[head] do head = head + 1 end
                entry = queue[head]
                queue[head] = false
                head = head + 1
            end
            pending = pending - 1
            local burner = player_storage.burners_by_product_full_name[entry.product_full_name]
            local column, inputs, outputs
            if entry.key == Solver.LOOP_PREFIX .. entry.product_full_name then
                column = loop_column(player_index, entry.product_full_name, product_parts[entry.product_full_name], product_parts, nil, options)
                inputs, outputs = {}, {}
                for product_full_name, net_amount in pairs(column.net_amounts) do
                    if product_full_name ~= entry.product_full_name then
                        table.insert(net_amount < 0 and inputs or outputs, product_full_name)
                    end
                end
                parts_by_column[column] = candidate_parts(column, product_parts)
            elseif burner and entry.key == Burners.COLUMN_PREFIX .. entry.product_full_name then
                column = {recipe_name = entry.key, product_full_name = entry.product_full_name, consumer = false, burner = burner,
                    net_amounts = Burners.net_amounts(entry.product_full_name, burner)}
                inputs = {entry.product_full_name}
                outputs = {}
                for product_full_name, net_amount in pairs(column.net_amounts) do
                    if net_amount > 0 then outputs[#outputs + 1] = product_full_name end
                end
            else
                local recipe = prototypes.recipe[entry.key]
                local product_full_name = player_storage.product_full_names_by_recipe_name[entry.key]
                column = {recipe_name = entry.key, product_full_name = product_full_name,
                    consumer = player_storage.consumer_product_full_names[product_full_name] == true,
                    net_amounts = column_net_amounts(recipe, player_storage.identifiers_of_chosen_crafting_machines_by_recipe_name[entry.key],
                        player_storage.module_setups_by_recipe_name[entry.key], player_index, product_parts)}
                inputs, outputs = {}, {}
                for _, ingredient in ipairs(recipe.ingredients) do
                    inputs[#inputs + 1] = ingredient.type .. "/" .. ingredient.name
                end
                for _, product in ipairs(recipe.products) do
                    if product.type ~= "research-progress" then
                        outputs[#outputs + 1] = product.type .. "/" .. product.name
                    end
                end
            end
            columns[#columns + 1] = column
            for _, product_full_name in ipairs(inputs) do
                enqueue(followed_binding(product_full_name, false, player_storage, product_parts, player_index), product_full_name)
            end
            for _, product_full_name in ipairs(outputs) do
                enqueue(followed_binding(product_full_name, true, player_storage, product_parts, player_index), product_full_name)
            end
        end
    end

    local seeded, expanded = {}, {}
    local eligible
    walk()
    while true do
        --candidate forced loops: the producers of what their upper tiers take
        for _, column in ipairs(columns) do
            local info = column.quality_loop
            if info and info.reason == "quality_target_unreachable" and info.part_spec and not seeded[column] then
                seeded[column] = true
                local spec = info.part_spec
                for q = spec.start + 1, spec.target do
                    for _, ingredient in ipairs(spec.craft_tiers[q - spec.start + 1].ingredients) do
                        local full_name = "item/" .. ingredient.name
                        enqueue(followed_binding(full_name, false, player_storage, product_parts, player_index), full_name)
                    end
                end
            end
        end
        walk()

        --eligible parts: the least fixpoint over the columns found so far
        local bound, sources = {}, {}
        for _, column in ipairs(columns) do
            if column.product_full_name then bound[column.product_full_name] = true end
            for full_name, net_amount in pairs(column.net_amounts) do
                if net_amount > 0 then sources[full_name] = true end
            end
        end
        eligible = {}
        local grew = true
        while grew do
            grew = false
            for _, column in ipairs(columns) do
                for _, part in ipairs(parts_by_column[column] or {}) do
                    if not eligible[part] then
                        local fits = true
                        for _, identity in ipairs(part.feed) do
                            if not sources[identity] or bound[identity] then fits = false end
                        end
                        if fits then
                            eligible[part] = true
                            grew = true
                            for full_name, net_amount in pairs(part.nets) do
                                if net_amount > 0 then sources[full_name] = true end
                            end
                        end
                    end
                end
            end
        end

        --what eligible parts take and leave at normal quality, and their fluids, follow the bindings as any column's do; qualities above normal never
        for _, column in ipairs(columns) do
            for _, part in ipairs(parts_by_column[column] or {}) do
                if eligible[part] and not expanded[part] then
                    expanded[part] = true
                    local names = {}
                    for full_name, _ in pairs(part.nets) do names[#names + 1] = full_name end
                    table.sort(names)
                    for _, full_name in ipairs(names) do
                        if not product_parts[full_name] and full_name ~= column.product_full_name then
                            enqueue(followed_binding(full_name, part.nets[full_name] > 0, player_storage, product_parts, player_index), full_name)
                        end
                    end
                end
            end
        end
        if pending == 0 then
            break
        end
    end

    for _, column in ipairs(columns) do
        local parts_found = {}
        for _, part in ipairs(parts_by_column[column] or {}) do
            if eligible[part] then parts_found[#parts_found + 1] = part end
        end
        if column.quality_loop and #parts_found > 0 then
            column.quality_loop.parts = parts_found
        end
    end
    return columns
end

--Line i is the equation of column i's bound product
local function prepare_matrix(columns, production_rates_by_product_full_name)
    local N = #columns
    local A = {}
    local line_numbers_by_product_full_name = {}
    for i, column in ipairs(columns) do
        A[i] = {}
        line_numbers_by_product_full_name[column.product_full_name] = i
        A[i][N+1] = (production_rates_by_product_full_name[column.product_full_name] or 0)
    end

    --One coefficient per product and column: the column's net amount of that product, so repeated entries and catalysts count once
    for column_index, column in ipairs(columns) do
        for product_full_name, net_amount in pairs(column.net_amounts) do
            local line = line_numbers_by_product_full_name[product_full_name]
            if line then
                A[line][column_index] = net_amount
            end
        end
    end

    return A
end

local function to_nil_if_zero(x)
    return x ~= 0 and x or nil
end

local function copy_matrix(A)
    local copy = {}
    for i, line in ipairs(A) do
        copy[i] = {}
        for column, value in pairs(line) do
            copy[i][column] = value
        end
    end
    return copy
end

--Lines and their magnitudes always move together; both strategies swap only through here
local function swap_lines(A, magnitudes, i, k)
    A[i], A[k] = A[k], A[i]
    magnitudes[i], magnitudes[k] = magnitudes[k], magnitudes[i]
end

--A pivot tiny against the largest magnitude its entry passed through is what is left of a cancellation, i.e. rounding noise;
--a small pivot that never cancelled stays valid at any scale
local function is_noise(A, magnitudes, line, column)
    local value = A[line][column]
    return not value or math.abs(value) <= 1e-9 * magnitudes[line][column]
end

--Gaussian elimination with one of two line choices per column:
--"today" keeps the line unless its pivot is noise, then takes the line below that went through the least cancellation (ties: the larger pivot);
--"largest" takes the largest pivot that is not noise.
--Also returns whether "today" chose exactly what "largest" would have chosen, in which case "largest" would repeat the same arithmetic.
local function solve_once(A, strategy)
    local N = #A

    --magnitudes[line][column] is the largest magnitude a coefficient passed through during elimination.
    --Coefficients themselves are never pruned, so small but meaningful ones keep their value.
    local magnitudes = {}
    for i, line in ipairs(A) do
        magnitudes[i] = {}
        for column, coefficient in pairs(line) do
            if column <= N then
                magnitudes[i][column] = math.abs(coefficient)
            end
        end
    end

    local same_choices_as_largest = true
    for i = 1, N do
        if strategy == "largest" then
            local best
            for k = i, N do
                if not is_noise(A, magnitudes, k, i) and (not best or math.abs(A[k][i]) > math.abs(A[best][i])) then
                    best = k
                end
            end
            if best and best ~= i then
                swap_lines(A, magnitudes, i, best)
            end
        elseif not is_noise(A, magnitudes, i, i) then
            for k = i + 1, N do
                if not is_noise(A, magnitudes, k, i) and math.abs(A[k][i]) > math.abs(A[i][i]) then
                    same_choices_as_largest = false
                    break
                end
            end
        else
            same_choices_as_largest = false
            local best, best_ratio
            for k = i + 1, N do
                local value = A[k][i]
                if value then
                    local ratio = math.abs(value) / magnitudes[k][i]
                    if not best or ratio > best_ratio or (ratio == best_ratio and math.abs(value) > math.abs(A[best][i])) then
                        best, best_ratio = k, ratio
                    end
                end
            end
            if best then
                swap_lines(A, magnitudes, i, best)
            end
        end

        if is_noise(A, magnitudes, i, i) then
            return nil, same_choices_as_largest --matrix unsolvable for now
        end
        local pivot_value = A[i][i]

        for k = i + 1, N do
            local k_coefficient = A[k][i]
            if k_coefficient then
                local factor = k_coefficient / pivot_value
                for column, pivot_line_value in pairs(A[i]) do
                    A[k][column] = to_nil_if_zero((A[k][column] or 0) - pivot_line_value * factor)
                    if column <= N then
                        magnitudes[k][column] = math.max(magnitudes[k][column] or 0, math.abs(factor) * magnitudes[i][column])
                    end
                end
                A[k][i] = nil --eliminated, whatever rounding left behind
            end
        end
    end

    --every line is now upper triangular, so only columns right of the pivot and left of the right-hand side take part
    local solution_values_by_column = {}
    for i = N, 1, -1 do
        local partial_solution_value = A[i][N+1] or 0
        for column, coefficient in pairs(A[i]) do
            if i < column and column <= N then
                partial_solution_value = partial_solution_value - coefficient * solution_values_by_column[column]
            end
        end
        solution_values_by_column[i] = partial_solution_value / A[i][i]
    end

    return solution_values_by_column, same_choices_as_largest
end

--Largest relative miss of a solution over the original equations, or nil when an equation misses by more than 1e-9 of its largest term.
--The comparison is written so that inf and nan, from the solution or from an overflowing product, fail it.
local function worst_residual(original, solution)
    local N = #original
    local worst = 0
    for _, line in ipairs(original) do
        local demand = line[N+1] or 0
        local sum, scale = 0, math.abs(demand)
        for column, coefficient in pairs(line) do
            if column <= N then
                local term = coefficient * solution[column]
                sum = sum + term
                scale = math.max(scale, math.abs(term))
            end
        end
        local miss = math.abs(sum - demand)
        local relative = miss == 0 and 0 or miss / scale
        if not (relative <= 1e-9) then
            return
        end
        worst = math.max(worst, relative)
    end
    return worst
end

local function agree(a, b)
    for i = 1, #a do
        if math.abs(a[i] - b[i]) > 1e-9 * math.max(1, math.abs(a[i]), math.abs(b[i])) then
            return false
        end
    end
    return true
end

--A small miss over the equations does not bound the error of each rate, so unless the current line order already made largest-pivot choices,
--the system is also solved in largest-pivot order. Both fitting and agreeing: the current order's numbers; both fitting but differing: the
--better fit, ties keeping the current order.
local function gauss_solve(A)
    local original = copy_matrix(A)
    local today, same_choices_as_largest = solve_once(A, "today")
    local today_residual = today and worst_residual(original, today)
    if today and same_choices_as_largest then
        return today_residual and today or nil
    end

    local largest = solve_once(copy_matrix(original), "largest")
    local largest_residual = largest and worst_residual(original, largest)
    if today_residual and largest_residual then
        if agree(today, largest) or today_residual <= largest_residual then
            return today
        end
        return largest
    end
    return (today_residual and today) or (largest_residual and largest) or nil
end

--Solved products (bound to a used recipe) are reported at their recipe's own net output, so intermediates keep a rate even though their global balance is zero.
--Every other product is reported at its global demand minus supply (negative means byproduct).
local function compute_product_rates(columns, rates_by_column_index, production_rates_of_final_products_by_product_full_name)
    local solved_rates = {}
    local unsolved_rates = {}

    for final_product_full_name, production_rate in pairs(production_rates_of_final_products_by_product_full_name) do
        unsolved_rates[final_product_full_name] = production_rate
    end

    for column_index, column in ipairs(columns) do
        local recipe_rate = rates_by_column_index[column_index]
        local net_amounts = column.net_amounts
        local bound_product_full_name = column.product_full_name
        solved_rates[bound_product_full_name] = recipe_rate * (net_amounts[bound_product_full_name] or 0)
        for product_full_name, net_amount in pairs(net_amounts) do
            unsolved_rates[product_full_name] = (unsolved_rates[product_full_name] or 0) - recipe_rate * net_amount
        end
    end

    for product_full_name, rate in pairs(unsolved_rates) do
        if solved_rates[product_full_name] or math.abs(rate) < 1e-9 then
            unsolved_rates[product_full_name] = nil
        end
    end

    return solved_rates, unsolved_rates
end

local function is_finite(x)
    return x == x and x ~= math.huge and x ~= -math.huge
end

--Columns whose rate is not finite or runs backwards. Line c of the matrix is the equation of column c's bound product, so a column's rate is
--judged against the rounding of its own equation: the largest term of that line (or its demand) over the column's own coefficient.
--A huge rate elsewhere in the system never widens it.
local function backwards_reasons(original_matrix, columns, solution)
    local N = #original_matrix
    local reasons_by_column = {}
    for c = 1, N do
        local rate = solution[c]
        if not is_finite(rate) then
            reasons_by_column[columns[c].recipe_name] = "rate_not_finite"
        else
            local line = original_matrix[c]
            local scale = math.abs(line[N + 1] or 0)
            for column, coefficient in pairs(line) do
                if column <= N and is_finite(solution[column]) then
                    scale = math.max(scale, math.abs(coefficient * solution[column]))
                end
            end
            local own_coefficient = line[c]
            local tolerance = (own_coefficient and own_coefficient ~= 0) and 1e-9 * scale / math.abs(own_coefficient) or 1e-9
            if rate < -tolerance then
                reasons_by_column[columns[c].recipe_name] = "recipe_runs_backwards"
            end
        end
    end
    return reasons_by_column
end

--Net amount per craft of a product in a recipe with its chosen machine and setup, quality spread included, as the solver uses it now; nil when none
function Solver.net_amount_of(recipe, product_full_name, player_index)
    local player_storage = storage[player_index]
    return column_net_amounts(recipe, player_storage.identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name],
        player_storage.module_setups_by_recipe_name[recipe.name], player_index)[product_full_name]
end

--Solves the sheet's targets. Returns {status, columns, recipe_rates, solved_rates, unsolved_rates, reasons_by_column}:
--  status "ok": every rate is usable; "infeasible": reasons_by_column names the columns at fault, with rates only when the system was solved;
--  "unsolvable": the equations have no single answer, no rates.
--  columns: the used columns in matrix order, known before solving (see collect_columns); burner columns carry burner = {name, quality}.
--  recipe_rates and reasons_by_column are keyed by column key: a recipe name, or Burners.COLUMN_PREFIX .. product for a burner.
--  product_parts: {[full name] = {type, name, quality}} for every item above normal quality the result names (see QualityId); others are "type/name".
--product_parts: the parts of the targets above normal quality
--  feed_rounds: rounds of the share search when loops use higher-quality items made elsewhere (M3), else nil.
--options: {start_leftovers = "byproduct" (default) | "craft" | "recycle"}, the sheet's choice for items loops return at their start quality
function Solver.solve_for(production_rates_by_product_full_name, player_index, product_parts, options)
    local parts = {} --the targets' parts, joined by those of the items loops leave above normal quality
    for full_name, target_parts in pairs(product_parts or {}) do parts[full_name] = target_parts end
    product_parts = parts
    local columns = collect_columns(production_rates_by_product_full_name, player_index, product_parts, options)

    --loops with fed parts: a loop unreachable alone is forced to make its target from them; any other keeps its own crafts to mix with them
    local mixed = {}
    for _, column in ipairs(columns) do
        local info = column.quality_loop
        if info and info.parts then
            if info.reason == "quality_target_unreachable" then
                info.reason, info.forced = nil, true
            end
            if not info.reason then
                column.base_nets, column.base_tiers = column.net_amounts, info.tiers
                mixed[#mixed + 1] = column
            end
        end
    end

    local reasons_by_column = {}
    for _, column in ipairs(columns) do
        --checked before solving: a consumer netting zero leaves its product's equation empty, and the solve would fail without saying why
        local net_amount = column.net_amounts[column.product_full_name]
        if column.consumer and not (net_amount and net_amount < 0) then
            reasons_by_column[column.recipe_name] = "consumer_no_longer_consumes"
        end
        --a loop that cannot be balanced has no usable column
        if column.quality_loop and column.quality_loop.reason then
            reasons_by_column[column.recipe_name] = column.quality_loop.reason
        end
    end
    if next(reasons_by_column) then
        return {status = "infeasible", columns = columns, reasons_by_column = reasons_by_column, product_parts = product_parts}
    end

    local function finish(matrix_solution, original_matrix, extra)
        local recipe_rates_by_recipe_name = {}
        for column_index, column in ipairs(columns) do
            recipe_rates_by_recipe_name[column.recipe_name] = matrix_solution[column_index]
        end
        local reasons = backwards_reasons(original_matrix, columns, matrix_solution)
        local solved_rates_by_product_full_name, unsolved_rates_by_product_full_name = compute_product_rates(columns, matrix_solution, production_rates_by_product_full_name)
        local result = {
            status = next(reasons) and "infeasible" or "ok",
            columns = columns,
            recipe_rates = recipe_rates_by_recipe_name,
            solved_rates = solved_rates_by_product_full_name,
            unsolved_rates = unsolved_rates_by_product_full_name,
            reasons_by_column = reasons,
            product_parts = product_parts,
        }
        for key, value in pairs(extra or {}) do result[key] = value end
        return result
    end

    local function solve_once()
        local matrix = prepare_matrix(columns, production_rates_by_product_full_name)
        local original_matrix = copy_matrix(matrix) --gauss_solve eliminates in place
        return gauss_solve(matrix), original_matrix
    end

    if #mixed == 0 then
        local solution, original_matrix = solve_once()
        if not solution then
            return {status = "unsolvable", columns = columns, reasons_by_column = reasons_by_column, product_parts = product_parts}
        end
        return finish(solution, original_matrix)
    end
    return Solver._solve_with_feed(columns, mixed, production_rates_by_product_full_name, product_parts, solve_once, finish)
end

--Round limit of the share search (M3); tests lower it
Solver.FEED_ROUND_LIMIT = 50
--A shortage counts once above this share of the identity's largest flow plus an absolute floor (items per second): a loop reusing its own
--leftovers nets an identity to almost nothing, so a relative tolerance alone would judge rounding as shortage
local FEED_TOLERANCE, FEED_FLOOR = 1e-12, 1e-12

--Sets a mixed loop column's nets and tiers for share levels theta (by feed identity): parts filled from the top tier down, each up to the lowest level
--of the identities it takes and to what higher parts left; a forced loop's remainder goes to its lowest part; the rest from its own crafts.
local function mix(column, theta)
    local info = column.quality_loop
    local parts = info.parts
    local used = 0
    for index = #parts, 1, -1 do
        local part = parts[index]
        local level = 1
        for _, identity in ipairs(part.feed) do level = math.min(level, theta[identity]) end
        part.share = math.max(0, math.min(level, 1 - used))
        used = used + part.share
    end
    if info.forced then
        parts[1].share = parts[1].share + (1 - used)
        used = 1
    end
    local own = 1 - used
    local nets = {}
    if own > 0 then
        for full_name, amount in pairs(column.base_nets) do nets[full_name] = own * amount end
    end
    for _, part in ipairs(parts) do
        if part.share > 0 then
            for full_name, amount in pairs(part.nets) do nets[full_name] = (nets[full_name] or 0) + part.share * amount end
        end
    end
    nets[column.product_full_name] = 1
    column.net_amounts = nets

    --tiers from the start to the target, each the same mix of own crafts and parts
    local spec = info.part_spec
    local tiers, by_quality = {}, {}
    for index = spec.start, spec.target do
        local tier = {quality = spec.chain[index].name, crafts = 0, recycle_crafts = 0, x = 0}
        tiers[#tiers + 1] = tier
        by_quality[tier.quality] = tier
    end
    local function add_tiers(source_tiers, weight)
        for _, source in ipairs(source_tiers or {}) do
            local tier = by_quality[source.quality]
            tier.crafts = tier.crafts + weight * source.crafts
            tier.recycle_crafts = tier.recycle_crafts + weight * source.recycle_crafts
            tier.x = tier.x + weight * source.x
            tier.craft_chances = tier.craft_chances or source.craft_chances
            tier.recycle_chances = tier.recycle_chances or source.recycle_chances
            if source.assist_crafts then
                tier.assist_crafts = (tier.assist_crafts or 0) + weight * source.assist_crafts
                tier.assist_chances = source.assist_chances
            end
            for name, crafts in pairs(source.ingredient_recycles or {}) do
                tier.ingredient_recycles = tier.ingredient_recycles or {}
                tier.ingredient_recycles[name] = (tier.ingredient_recycles[name] or 0) + weight * crafts
            end
        end
    end
    if own > 0 then add_tiers(column.base_tiers, own) end
    for _, part in ipairs(parts) do
        if part.share > 0 then add_tiers(part.tiers, part.share) end
    end
    for _, tier in ipairs(tiers) do
        tier.craft_chances = tier.craft_chances or {}
    end
    info.tiers = tiers
    --what the loop takes from the rest of the sheet at each tier, per target: {[quality] = {{identity, item, amount}}}, own leftovers it reuses not listed
    info.feed = {}
    for _, part in ipairs(parts) do
        for _, identity in ipairs(part.feed) do
            local taken = -(nets[identity] or 0)
            if taken > FEED_TOLERANCE * part.share * math.abs(part.nets[identity] or 0) + FEED_FLOOR then --rounding of reused leftovers is not a take
                info.feed[part.quality] = info.feed[part.quality] or {}
                table.insert(info.feed[part.quality], {identity = identity, item = part.feed_items[identity], amount = taken})
            end
        end
    end
end

--The sheet solve when loops mix fed parts (M3): one share level per feed identity, found per identity by a bracketed root search (Illinois regula falsi)
--of its shortage, identity by identity in sorted order, until no level moves. A forced loop short of an identity only other forced loops take may
--rebind that item's producer to the identity once. Calculator limits give quality_feed_solve_limit; a real shortage quality_loop_outside_supply_short.
function Solver._solve_with_feed(columns, mixed, rates, product_parts, solve_once, finish)
    local identities, seen = {}, {}
    for _, column in ipairs(mixed) do
        for _, part in ipairs(column.quality_loop.parts) do
            for _, identity in ipairs(part.feed) do
                if not seen[identity] then
                    seen[identity] = true
                    identities[#identities + 1] = identity
                end
            end
        end
    end
    table.sort(identities)

    local function stop(reason, selected)
        local reasons = {}
        for _, column in ipairs(selected or mixed) do reasons[column.recipe_name] = reason end
        for _, column in ipairs(mixed) do column.net_amounts = column.base_nets or {[column.product_full_name] = 1} end
        return {status = "infeasible", columns = columns, reasons_by_column = reasons, product_parts = product_parts}
    end

    local theta = {}
    for _, identity in ipairs(identities) do theta[identity] = 1 end
    --shortage of an identity at the current levels (positive: the sheet takes more than it makes) and the size of its largest flow
    local last_solution, last_matrix
    local function shortage(identity)
        for _, column in ipairs(mixed) do mix(column, theta) end
        local solution, original_matrix = solve_once()
        if not solution then
            return nil
        end
        last_solution, last_matrix = solution, original_matrix
        local h, scale = rates[identity] or 0, math.abs(rates[identity] or 0)
        for index, column in ipairs(columns) do
            local flow = solution[index] * (column.net_amounts[identity] or 0)
            h = h - flow
            scale = math.max(scale, math.abs(flow))
        end
        return h, scale
    end

    local short = {}
    local rounds = 0
    local function search()
        short = {}
        rounds = 0
        for _, identity in ipairs(identities) do theta[identity] = 1 end
        local moved = true
        while moved do
            rounds = rounds + 1
            if rounds > Solver.FEED_ROUND_LIMIT then
                return false
            end
            moved = false
            for _, identity in ipairs(identities) do
                local before = theta[identity]
                theta[identity] = 1
                local high, high_scale = shortage(identity)
                if not high then return false end
                local level = 1
                if high > FEED_TOLERANCE * high_scale + FEED_FLOOR then
                    theta[identity] = 0
                    local low, low_scale = shortage(identity)
                    if not low then return false end
                    if low > FEED_TOLERANCE * low_scale + FEED_FLOOR then
                        short[identity] = true --only forced loops take it, and even alone they take more than the sheet makes
                        level = 0
                    else
                        --a bracket [a, b] with shortage(a) <= 0 < shortage(b) kept at every step, so the search cannot alternate
                        local a, fa, b, fb, side = 0, low, 1, high, 0
                        local found
                        for _ = 1, 100 do
                            local t = (a * fb - b * fa) / (fb - fa)
                            theta[identity] = t
                            local ft, scale = shortage(identity)
                            if not ft then return false end
                            if math.abs(ft) <= FEED_TOLERANCE * scale + FEED_FLOOR or b - a <= 1e-15 then
                                found = t
                                break
                            end
                            if ft > 0 then
                                b, fb = t, ft
                                if side == 1 then fa = fa / 2 end
                                side = 1
                            else
                                a, fa = t, ft
                                if side == -1 then fb = fb / 2 end
                                side = -1
                            end
                        end
                        if not found then return false end
                        level = found
                    end
                end
                theta[identity] = level
                if math.abs(level - before) > 1e-12 then moved = true end
            end
        end
        return true
    end

    local function forced_takers(identity)
        local takers, all_forced = {}, true
        for index, column in ipairs(columns) do
            if (column.net_amounts[identity] or 0) < 0 and last_solution[index] > 0 then
                takers[#takers + 1] = column
                if not (column.quality_loop and column.quality_loop.forced) then all_forced = false end
            end
        end
        return takers, all_forced
    end

    if not search() then
        return stop("quality_feed_solve_limit")
    end
    local rebound = {}
    if next(short) then
        --rebinding once: the producer of the item whose identity forced loops lack is solved for that identity instead
        for identity, _ in pairs(short) do
            local _, all_forced = forced_takers(identity)
            local item_full_name = "item/" .. product_parts[identity].name
            local producers = {}
            for _, column in ipairs(columns) do
                if column.product_full_name == item_full_name and (column.net_amounts[identity] or 0) > 0 then producers[#producers + 1] = column end
            end
            if all_forced and #producers == 1 then
                producers[1].binding_full_name = item_full_name --its recipe, machine and modules stay those of the item's binding
                producers[1].product_full_name = identity
                rebound[#rebound + 1] = {column = producers[1], item = item_full_name}
            end
        end
        if #rebound > 0 and not search() then
            return stop("quality_feed_solve_limit")
        end
    end
    for _, column in ipairs(mixed) do mix(column, theta) end
    local solution, original_matrix = solve_once()
    if not solution then
        return stop("quality_feed_solve_limit")
    end
    last_solution = solution

    --final check: no feed identity short, and none left over while a loop could still take more of it
    local lacking = {}
    for _, identity in ipairs(identities) do
        local h, scale = rates[identity] or 0, 0
        for index, column in ipairs(columns) do
            local flow = solution[index] * (column.net_amounts[identity] or 0)
            h = h - flow
            scale = math.max(scale, math.abs(flow))
        end
        if h > 1e-9 * scale + FEED_FLOOR then
            lacking[identity] = true
        elseif h < -(1e-9 * scale + FEED_FLOOR) and theta[identity] < 1 then
            return stop("quality_feed_solve_limit")
        end
    end
    for _, entry in ipairs(rebound) do
        local h, scale = rates[entry.item] or 0, 0
        for index, column in ipairs(columns) do
            local flow = solution[index] * (column.net_amounts[entry.item] or 0)
            h = h - flow
            scale = math.max(scale, math.abs(flow))
        end
        if h > 1e-9 * scale + FEED_FLOOR then
            for identity, _ in pairs(short) do lacking[identity] = true end
        end
    end
    if next(lacking) then
        local forced = {}
        for identity, _ in pairs(lacking) do
            for _, column in ipairs((forced_takers(identity))) do
                if column.quality_loop and column.quality_loop.forced then forced[#forced + 1] = column end
            end
        end
        return stop("quality_loop_outside_supply_short", #forced > 0 and forced or nil)
    end
    return finish(solution, original_matrix, {feed_rounds = rounds})
end

Solver.productivity_bonus = productivity_bonus

--Exposed for offline tests only
Solver._gauss_solve = gauss_solve
Solver._solve_once = solve_once
Solver._worst_residual = worst_residual
Solver._backwards_reasons = backwards_reasons
Solver._loop_column = loop_column

return Solver
