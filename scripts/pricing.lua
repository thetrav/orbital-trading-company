local M = {}

local BASE_ORE_PRICE = 100
local TIME_COST_PER_SECOND = 10
local FURNACE_POWER = 90000
local COAL_FUEL_VALUE = 4000000

local function calculate_recipe_cost(recipe, prices)
    local ingredient_cost = 0
    for _, ingredient in pairs(recipe.ingredients) do
        local price = prices[ingredient.name] or 0
        ingredient_cost = ingredient_cost + ingredient.amount * price
    end

    local fuel_cost = 0
    local ok, categories = pcall(function() return recipe.categories end)
    if ok and categories then
        for _, cat in pairs(categories) do
            if cat == "smelting" then
                fuel_cost = recipe.energy * FURNACE_POWER / COAL_FUEL_VALUE * (prices["coal"] or BASE_ORE_PRICE)
                break
            end
        end
    end

    local time_cost = recipe.energy * TIME_COST_PER_SECOND

    local total = ingredient_cost + fuel_cost + time_cost

    local total_results = 0
    for _, product in pairs(recipe.products) do
        total_results = total_results + product.amount
    end

    if total_results == 0 then return {} end

    local cost_per_unit = math.floor(total / total_results + 0.5)

    local result_costs = {}
    for _, product in pairs(recipe.products) do
        result_costs[product.name] = cost_per_unit
    end
    return result_costs
end

function M.calculate()
    local prices = {}
    local item_depth = {}

    for name, prototype in pairs(prototypes.item) do
        if prototype.subgroup and prototype.subgroup.name == "raw-resource" then
            prices[name] = BASE_ORE_PRICE
            item_depth[name] = 0
        end
    end

    for _, recipe in pairs(prototypes.recipe) do
        if recipe.enabled then
            local result_costs = calculate_recipe_cost(recipe, prices)
            for result_name, cost in pairs(result_costs) do
                if not prices[result_name] then
                    prices[result_name] = cost
                    item_depth[result_name] = 0
                end
            end
        end
    end

    local processed_techs = {}
    local remaining_techs = {}
    for name, tech in pairs(prototypes.technology) do
        remaining_techs[name] = tech
    end

    local max_iterations = 100
    local iteration = 0
    while next(remaining_techs) and iteration < max_iterations do
        iteration = iteration + 1
        local level_techs = {}

        for name, tech in pairs(remaining_techs) do
            local all_prereqs_met = true
            for _, prereq in pairs(tech.prerequisites) do
                if not processed_techs[prereq.name] then
                    all_prereqs_met = false
                    break
                end
            end
            if all_prereqs_met then
                table.insert(level_techs, tech)
            end
        end

        if #level_techs == 0 then break end

        for _, tech in pairs(level_techs) do
            processed_techs[tech.name] = true
            remaining_techs[tech.name] = nil

            for _, effect in pairs(tech.effects) do
                if effect.type == "unlock-recipe" then
                    local recipe = prototypes.recipe[effect.recipe]
                    if recipe then
                        local result_costs = calculate_recipe_cost(recipe, prices)
                        for result_name, cost in pairs(result_costs) do
                            if not prices[result_name] then
                                prices[result_name] = cost
                                item_depth[result_name] = iteration
                            elseif item_depth[result_name] == iteration then
                                if cost < prices[result_name] then
                                    prices[result_name] = cost
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return prices
end

return M
