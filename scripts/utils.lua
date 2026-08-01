local stock = require("scripts.stock")

local M = {}

local BASE_ORE_PRICE = 100

function M.format_number(amount)
    local formatted = tostring(amount)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

function M.get_base_price(item_name)
    if storage.prices and storage.prices[item_name] then
        return storage.prices[item_name]
    end
    return BASE_ORE_PRICE
end

function M.get_price(item_name)
    local base = M.get_base_price(item_name)
    local anchor = base
    local supply_demand = package.loaded["scripts.supply_demand"]
    if supply_demand then
        anchor = base + supply_demand.get_offset(item_name)
    end
    local price = anchor * stock.scarcity(item_name)
    local ceiling = math.max(1, math.floor(base * stock.SCARCITY_CAP + 0.5))
    return math.max(1, math.min(ceiling, math.floor(price + 0.5)))
end

function M.get_stock(item_name)
    return stock.get(item_name)
end

function M.get_price_offset(item_name)
    local supply_demand = package.loaded["scripts.supply_demand"]
    if supply_demand then
        return supply_demand.get_offset(item_name)
    end
    return 0
end

return M
