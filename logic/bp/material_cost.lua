-- Pure raw-resource cost calculation. Prototype access belongs in logic/catalog.lua.
local MaterialCost = {}
local VISIT_LIMIT = 100000

local function sorted_keys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function MaterialCost.compute(graph, names)
    local memo, state, costs = {}, {}, {}
    local visits = 0
    local function cost_item(root)
        if memo[root] ~= nil then return memo[root] end
        local stack = {{name = root, index = 1, sum = 0, ingredients = nil}}
        while #stack > 0 do
            visits = visits + 1
            if visits > VISIT_LIMIT then error("material cost visit limit exceeded") end
            local frame = stack[#stack]
            local item = frame.name
            if memo[item] ~= nil then
                table.remove(stack)
            elseif frame.ingredients == nil then
                state[item] = true
                local recipe_name = graph.recipe_of and graph.recipe_of[item]
                local recipe = recipe_name and graph.recipes and graph.recipes[recipe_name]
                local product_amount
                if recipe then
                    for _, product in ipairs(recipe.products or {}) do
                        if product.name == item then product_amount = product.amount; break end
                    end
                end
                if not recipe or type(product_amount) ~= "number" or product_amount <= 0 then
                    memo[item], state[item] = 1, nil
                    table.remove(stack)
                else
                    frame.ingredients = recipe.ingredients or {}
                    frame.divisor = product_amount
                end
            elseif frame.index > #frame.ingredients then
                memo[item] = frame.sum / frame.divisor
                state[item] = nil
                table.remove(stack)
            else
                local ingredient = frame.ingredients[frame.index]
                local name, amount = ingredient.name, ingredient.amount
                if memo[name] ~= nil then
                    frame.sum = frame.sum + amount * memo[name]
                    frame.index = frame.index + 1
                elseif state[name] then
                    -- A back edge counts the repeated item as a leaf for this ingredient.
                    frame.sum = frame.sum + amount
                    frame.index = frame.index + 1
                else
                    stack[#stack + 1] = {name = name, index = 1, sum = 0, ingredients = nil}
                end
            end
        end
        return memo[root]
    end

    local requested = names or sorted_keys(graph.place)
    for _, entity in ipairs(requested) do
        local item = graph.place and graph.place[entity]
        if item then costs[entity] = cost_item(item) end
    end
    return costs
end

function MaterialCost.parse_fixture(text)
    local result = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local entity, value = line:match("^%s*MATERIAL%s+(%S+)%s+([%+%-]?[%d%.]+)%s*$")
        if entity then
            local cost = tonumber(value)
            if cost and cost > 0 and cost < math.huge then result[entity] = cost end
        end
    end
    return result
end

function MaterialCost.of_entity(catalog, name)
    return catalog and catalog.material and catalog.material[name] or nil
end

return MaterialCost
