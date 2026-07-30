local M = {}

local HISTORY_LENGTH = 60
local TOTAL_KEY = "__total__"

function M.init()
    storage.trading_history = storage.trading_history or {}
    storage.trading_history_head = 0
end

local function get_force_history(force_name)
    storage.trading_history[force_name] = storage.trading_history[force_name] or {}
    return storage.trading_history[force_name]
end

local function record_slot(force_name, item_name, count_bought, count_sold, price_per_unit)
    local history = get_force_history(force_name)
    local item_history = history[item_name]
    if not item_history then
        item_history = {}
        history[item_name] = item_history
    end
    local idx = storage.trading_history_head + 1
    local slot = item_history[idx]
    if not slot then
        slot = { bought = count_bought, sold = count_sold, price = price_per_unit }
        item_history[idx] = slot
    else
        slot.bought = slot.bought + count_bought
        slot.sold = slot.sold + count_sold
        slot.price = price_per_unit
    end
end

function M.record_buy(force_name, item_name, count, price_per_unit)
    record_slot(force_name, item_name, count, 0, price_per_unit)
    record_slot(force_name, TOTAL_KEY, count, 0, price_per_unit)
end

function M.record_sell(force_name, item_name, count, price_per_unit)
    record_slot(force_name, item_name, 0, count, price_per_unit)
    record_slot(force_name, TOTAL_KEY, 0, count, price_per_unit)
end

function M.advance_second()
    storage.trading_history_head = (storage.trading_history_head + 1) % HISTORY_LENGTH
    local head_idx = storage.trading_history_head + 1
    for _, force_history in pairs(storage.trading_history) do
        for _, item_history in pairs(force_history) do
            item_history[head_idx] = nil
        end
    end
end

function M.get_slot(force_name, item_name, age)
    local history = get_force_history(force_name)
    local item_history = history[item_name]
    if not item_history then return nil end
    local idx = (storage.trading_history_head - age) % HISTORY_LENGTH
    return item_history[idx + 1]
end

function M.income_from_slot(slot)
    if not slot or not slot.price or slot.price <= 0 then return 0 end
    return slot.sold * slot.price * 0.99
end

function M.expense_from_slot(slot)
    if not slot or not slot.price or slot.price <= 0 then return 0 end
    return slot.bought * slot.price * 1.01
end

function M.get_total_history(force_name)
    local history = get_force_history(force_name)
    return history[TOTAL_KEY]
end

function M.get_all_item_names(force_name)
    local history = get_force_history(force_name)
    local names = {}
    for name in pairs(history) do
        if name ~= TOTAL_KEY then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function M.get_all_forces()
    local forces = {}
    for force_name in pairs(storage.trading_history) do
        table.insert(forces, force_name)
    end
    table.sort(forces)
    return forces
end

return M