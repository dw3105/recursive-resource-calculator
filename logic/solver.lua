local Utils = require "logic.utils"

local Solver = {}

local function determine_used_recipes(recipe, used_recipe_name_set, player_index)
    if not recipe or used_recipe_name_set[recipe.name] then
        return
    end

    used_recipe_name_set[recipe.name] = true

    for _, ingredient in ipairs(recipe.ingredients) do
        local ingridient_full_name = ingredient.type .. "/" .. ingredient.name
        local ingridient_recipe = storage[player_index].recipes_by_product_full_name[ingridient_full_name]
        determine_used_recipes(ingridient_recipe, used_recipe_name_set, player_index)
    end
end

--Machine, research and module bonuses add up, and the total is capped by the recipe
local function get_productivity_bonus_for_recipe(recipe, player_index)
    local player_recipe = game.players[player_index].force.recipes[recipe.name]
    local research_bonus = player_recipe and player_recipe.productivity_bonus or 0
    local crafting_machine_identifier = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name]
    local effect_receiver = crafting_machine_identifier and prototypes.entity[crafting_machine_identifier.name].effect_receiver --optional in the API
    local machine_bonus = effect_receiver and effect_receiver.base_effect.productivity or 0
    local module_bonus = storage[player_index].module_preferences_by_recipe_name[recipe.name].effects.productivity
    return math.min(math.max(machine_bonus + research_bonus + module_bonus, 0), recipe.maximum_productivity)
end

local function prepare_matrix(used_recipe_name_list, production_rates_by_product_full_name, net_amounts_by_recipe_name, player_index)
    local N = #used_recipe_name_list
    local A = {}
    local line_numbers_by_product_full_name = {}
    for i, recipe_name in ipairs(used_recipe_name_list) do
        A[i] = {}

        local product_full_name = storage[player_index].product_full_names_by_recipe_name[recipe_name]
        line_numbers_by_product_full_name[product_full_name] = i
        A[i][N+1] = (production_rates_by_product_full_name[product_full_name] or 0)
    end

    --One coefficient per product and recipe: the recipe's net amount of that product, so repeated entries and catalysts count once
    for column, recipe_name in ipairs(used_recipe_name_list) do
        for product_full_name, net_amount in pairs(net_amounts_by_recipe_name[recipe_name]) do
            local line = line_numbers_by_product_full_name[product_full_name]
            if line then
                A[line][column] = net_amount
            end
        end
    end

    return A
end

local function to_nil_if_zero(x)
    return x ~= 0 and x or nil
end

local function gauss_solve(A)
    local N = #A

    --magnitudes[line][column] is the largest magnitude a coefficient passed through during elimination.
    --A pivot tiny against it is what is left of a cancellation, i.e. rounding noise; a small pivot that never cancelled stays valid at any scale.
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

    for i = 1, N do
        local pivot_value = A[i][i]
        if not pivot_value or math.abs(pivot_value) <= 1e-9 * magnitudes[i][i] then
            return --matrix unsolvable for now
        end

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

    return solution_values_by_column
end

--Solved products (bound to a used recipe) are reported at their recipe's own net output, so intermediates keep a rate even though their global balance is zero.
--Every other product is reported at its global demand minus supply (negative means byproduct).
local function compute_product_rates(recipe_rates_by_recipe_name, net_amounts_by_recipe_name, production_rates_of_final_products_by_product_full_name, player_index)
    local solved_rates = {}
    local unsolved_rates = {}

    for final_product_full_name, production_rate in pairs(production_rates_of_final_products_by_product_full_name) do
        unsolved_rates[final_product_full_name] = production_rate
    end

    for recipe_name, recipe_rate in pairs(recipe_rates_by_recipe_name) do
        local net_amounts = net_amounts_by_recipe_name[recipe_name]
        local bound_product_full_name = storage[player_index].product_full_names_by_recipe_name[recipe_name]
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

--Returns recipe rates, the rates of solved products and the rates of all other products involved
function Solver.solve_for(production_rates_by_product_full_name, player_index)
    local used_recipe_name_set = {}
    for product_full_name, _ in pairs(production_rates_by_product_full_name) do
        determine_used_recipes(storage[player_index].recipes_by_product_full_name[product_full_name], used_recipe_name_set, player_index)
    end

    local used_recipe_name_list = {}
    local net_amounts_by_recipe_name = {}
    for recipe_name, _ in pairs(used_recipe_name_set) do
        table.insert(used_recipe_name_list, recipe_name)
        local recipe = prototypes.recipe[recipe_name]
        net_amounts_by_recipe_name[recipe_name] = Utils.net_amounts_by_full_name(recipe, get_productivity_bonus_for_recipe(recipe, player_index))
    end

    local solutions_by_recipe_index = gauss_solve(prepare_matrix(used_recipe_name_list, production_rates_by_product_full_name, net_amounts_by_recipe_name, player_index))
    if not solutions_by_recipe_index then
        return
    end

    local recipe_rates_by_recipe_name = {}
    for recipe_index, recipe_name in ipairs(used_recipe_name_list) do
        recipe_rates_by_recipe_name[recipe_name] = solutions_by_recipe_index[recipe_index]
    end

    local solved_rates_by_product_full_name, unsolved_rates_by_product_full_name = compute_product_rates(recipe_rates_by_recipe_name, net_amounts_by_recipe_name, production_rates_by_product_full_name, player_index)
    return recipe_rates_by_recipe_name, solved_rates_by_product_full_name, unsolved_rates_by_product_full_name
end

--Exposed for offline tests only
Solver._gauss_solve = gauss_solve

return Solver
