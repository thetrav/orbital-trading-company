local M = {}

local MARKET_PERIOD = 10
local SENSITIVITY = 0.01
local DECAY = 0.95

function M.init()
    storage.supply_demand = {
        tick_counter = 0,
        period_buys = {},
        period_sells = {},
        price_offsets = {},
    }
end

function M.record_buy(item_name, count)
    if not storage.supply_demand then return end
    local period_buys = storage.supply_demand.period_buys
    period_buys[item_name] = (period_buys[item_name] or 0) + count
end

function M.record_sell(item_name, count)
    if not storage.supply_demand then return end
    local period_sells = storage.supply_demand.period_sells
    period_sells[item_name] = (period_sells[item_name] or 0) + count
end

function M.process_tick()
    if not storage.supply_demand then return end
    storage.supply_demand.tick_counter = storage.supply_demand.tick_counter + 1

    if storage.supply_demand.tick_counter >= MARKET_PERIOD then
        M.end_period()
        storage.supply_demand.tick_counter = 0
    end
end

function M.end_period()
    local sd = storage.supply_demand
    local offsets = sd.price_offsets

    local all_items = {}
    for item_name, _ in pairs(sd.period_buys) do
        all_items[item_name] = true
    end
    for item_name, _ in pairs(sd.period_sells) do
        all_items[item_name] = true
    end

    for item_name, _ in pairs(all_items) do
        local bought = sd.period_buys[item_name] or 0
        local sold = sd.period_sells[item_name] or 0
        local demand = bought - sold

        local current_offset = offsets[item_name] or 0
        local new_offset = current_offset + demand * SENSITIVITY
        new_offset = new_offset * DECAY

        if math.abs(new_offset) < 0.01 then
            new_offset = 0
        end

        offsets[item_name] = new_offset
    end

    sd.period_buys = {}
    sd.period_sells = {}
end

function M.get_offset(item_name)
    if not storage.supply_demand then return 0 end
    return storage.supply_demand.price_offsets[item_name] or 0
end

function M.get_effective_price(item_name, base_price)
    local offset = M.get_offset(item_name)
    return math.max(1, math.floor(base_price + offset + 0.5))
end

return M
