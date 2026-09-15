local Utils = require "logic.utils"
local Burners = require "logic.burners"

local Solver = {}

--Machine, research and module bonuses add up, and the total is capped by the recipe
local function get_productivity_bonus_for_recipe(recipe, player_index)
    local player_recipe = game.players[player_index].force.recipes[recipe.name]
    local research_bonus = player_recipe and player_recipe.productivity_bonus or 0
    local crafting_machine_identifier = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name]
    local effect_receiver = crafting_machine_identifier and prototypes.entity[crafting_machine_identifier.name].effect_receiver --optional in the API
    local machine_bonus = effect_receiver and effect_receiver.base_effect.productivity or 0
    local module_bonus = Utils.recipe_effects(player_index, recipe.name).productivity
    return math.min(math.max(machine_bonus + research_bonus + module_bonus, 0), recipe.maximum_productivity)
end

--The column key of a product's binding, when the walk follows it. Inputs follow any binding; outputs follow only a binding picked to
--get rid of them (a consumer recipe or a burner), so byproducts bound to a producer stay out of the system as before.
local function followed_binding(product_full_name, as_output, player_storage)
    if player_storage.burners_by_product_full_name[product_full_name] then
        return Burners.COLUMN_PREFIX .. product_full_name
    end
    local recipe = player_storage.recipes_by_product_full_name[product_full_name]
    if recipe and (not as_output or player_storage.consumer_product_full_names[product_full_name]) then
        return recipe.name
    end
end

--The columns the targets need, found breadth first over every column kind; a key is visited once, so cyclic bindings terminate.
--Each column: {recipe_name (the column key: a recipe name or Burners.COLUMN_PREFIX .. product), product_full_name, consumer, burner, net_amounts}
local function collect_columns(production_rates_by_product_full_name, player_index)
    local player_storage = storage[player_index]
    local columns, queue, visited = {}, {}, {}
    local function enqueue(key, product_full_name)
        if key and not visited[key] then
            visited[key] = true
            queue[#queue + 1] = {key = key, product_full_name = product_full_name}
        end
    end
    for product_full_name, _ in pairs(production_rates_by_product_full_name) do
        enqueue(followed_binding(product_full_name, false, player_storage), product_full_name)
    end

    local head = 1
    while queue[head] do
        local entry = queue[head]
        head = head + 1
        local burner = player_storage.burners_by_product_full_name[entry.product_full_name]
        local column, inputs, outputs
        if burner and entry.key == Burners.COLUMN_PREFIX .. entry.product_full_name then
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
                net_amounts = Utils.net_amounts_by_full_name(recipe, get_productivity_bonus_for_recipe(recipe, player_index))}
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
            enqueue(followed_binding(product_full_name, false, player_storage), product_full_name)
        end
        for _, product_full_name in ipairs(outputs) do
            enqueue(followed_binding(product_full_name, true, player_storage), product_full_name)
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

--Net amount per craft of a product in a recipe at the productivity the solver uses now; nil when the recipe nets none of it
function Solver.net_amount_of(recipe, product_full_name, player_index)
    return Utils.net_amounts_by_full_name(recipe, get_productivity_bonus_for_recipe(recipe, player_index))[product_full_name]
end

--Solves the sheet's targets. Returns {status, columns, recipe_rates, solved_rates, unsolved_rates, reasons_by_column}:
--  status "ok": every rate is usable; "infeasible": reasons_by_column names the columns at fault, with rates only when the system was solved;
--  "unsolvable": the equations have no single answer, no rates.
--  columns: the used columns in matrix order, known before solving (see collect_columns); burner columns carry burner = {name, quality}.
--  recipe_rates and reasons_by_column are keyed by column key: a recipe name, or Burners.COLUMN_PREFIX .. product for a burner.
function Solver.solve_for(production_rates_by_product_full_name, player_index)
    local columns = collect_columns(production_rates_by_product_full_name, player_index)
    local reasons_by_column = {}
    for _, column in ipairs(columns) do
        --checked before solving: a consumer netting zero leaves its product's equation empty, and the solve would fail without saying why
        local net_amount = column.net_amounts[column.product_full_name]
        if column.consumer and not (net_amount and net_amount < 0) then
            reasons_by_column[column.recipe_name] = "consumer_no_longer_consumes"
        end
    end
    if next(reasons_by_column) then
        return {status = "infeasible", columns = columns, reasons_by_column = reasons_by_column}
    end

    local matrix = prepare_matrix(columns, production_rates_by_product_full_name)
    local original_matrix = copy_matrix(matrix) --gauss_solve eliminates in place
    local solutions_by_column_index = gauss_solve(matrix)
    if not solutions_by_column_index then
        return {status = "unsolvable", columns = columns, reasons_by_column = reasons_by_column}
    end

    local recipe_rates_by_recipe_name = {}
    for column_index, column in ipairs(columns) do
        recipe_rates_by_recipe_name[column.recipe_name] = solutions_by_column_index[column_index]
    end
    reasons_by_column = backwards_reasons(original_matrix, columns, solutions_by_column_index)

    local solved_rates_by_product_full_name, unsolved_rates_by_product_full_name = compute_product_rates(columns, solutions_by_column_index, production_rates_by_product_full_name)
    return {
        status = next(reasons_by_column) and "infeasible" or "ok",
        columns = columns,
        recipe_rates = recipe_rates_by_recipe_name,
        solved_rates = solved_rates_by_product_full_name,
        unsolved_rates = unsolved_rates_by_product_full_name,
        reasons_by_column = reasons_by_column,
    }
end

--Exposed for offline tests only
Solver._gauss_solve = gauss_solve
Solver._solve_once = solve_once
Solver._worst_residual = worst_residual
Solver._backwards_reasons = backwards_reasons

return Solver
