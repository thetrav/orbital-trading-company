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

function M.get_price(item_name)
    if storage.prices and storage.prices[item_name] then
        return storage.prices[item_name]
    end
    return BASE_ORE_PRICE
end

return M
