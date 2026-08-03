local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local supply_demand = require("scripts.supply_demand")
local trading_history = require("scripts.trading_history")
local nauvis = require("scripts.nauvis")
local stock = require("scripts.stock")

local M = {}

M.NAME = "otc-trading-silo"
M.BUY_MULTIPLIER = 1.01
M.SELL_MULTIPLIER = 0.99

local WIRES = {
    green = { defines.wire_connector_id.circuit_green },
    red = { defines.wire_connector_id.circuit_red },
    both = { defines.wire_connector_id.circuit_green, defines.wire_connector_id.circuit_red },
}

function M.init()
    storage.trading_silos = storage.trading_silos or {}
end

function M.register(entity)
    if not entity or not entity.valid then return end
    if entity.name ~= M.NAME then return end

    storage.trading_silos = storage.trading_silos or {}
    storage.trading_silos[entity.unit_number] = {
        entity = entity,
        force_name = entity.force.name,
        buy = {},
        sell = {},
        circuit = { enabled = false, wire = "green" },
    }
    return storage.trading_silos[entity.unit_number]
end

function M.unregister(unit_number)
    if not storage.trading_silos then return end
    storage.trading_silos[unit_number] = nil
end

function M.get(unit_number)
    if not storage.trading_silos then return nil end
    return storage.trading_silos[unit_number]
end

function M.is_listed(data, item_name)
    for _, order in ipairs(data.buy) do
        if order.item == item_name then return true end
    end
    for _, order in ipairs(data.sell) do
        if order.item == item_name then return true end
    end
    return false
end

function M.add_buy(data, item_name, quantity)
    if M.is_listed(data, item_name) then return false end
    data.buy[#data.buy + 1] = { item = item_name, quantity = math.max(1, math.floor(quantity or 1)) }
    return true
end

function M.add_sell(data, item_name)
    if M.is_listed(data, item_name) then return false end
    data.sell[#data.sell + 1] = { item = item_name }
    return true
end

function M.set_quantity(data, index, quantity)
    local order = data.buy[index]
    if not order then return false end
    order.quantity = math.max(1, math.floor(quantity or 1))
    return true
end

function M.remove(data, side, index)
    local list = data[side]
    if not list or not list[index] then return false end
    table.remove(list, index)
    return true
end

function M.move(data, side, index, delta)
    local list = data[side]
    if not list then return false end
    local target = index + delta
    if not list[index] or not list[target] then return false end
    list[index], list[target] = list[target], list[index]
    return true
end

local function read_signals(entity, wire)
    local signals = {}
    for _, connector in ipairs(WIRES[wire] or WIRES.green) do
        local network = entity.get_circuit_network(connector)
        if network then
            for _, sig in pairs(network.signals or {}) do
                if sig.signal and sig.signal.name and sig.signal.type ~= "virtual" then
                    signals[sig.signal.name] = (signals[sig.signal.name] or 0) + sig.count
                end
            end
        end
    end
    return signals
end

--- The orders in force this tick. Circuit control replaces the stored
--- configuration rather than merging with it: a positive signal is a buy target,
--- a negative one sells all of that item, zero is ignored.
function M.resolve(data)
    local force = data.entity.valid and data.entity.force or nil
    local function allowed(item_name)
        return force and item_filter.is_item_allowed(item_name, force)
    end

    local buy, sell = {}, {}

    if not data.circuit.enabled then
        for _, order in ipairs(data.buy) do
            if allowed(order.item) then
                buy[#buy + 1] = { item = order.item, quantity = order.quantity }
            end
        end
        for _, order in ipairs(data.sell) do
            if allowed(order.item) then
                sell[#sell + 1] = { item = order.item }
            end
        end
        return buy, sell
    end

    local signals = read_signals(data.entity, data.circuit.wire)
    local names = {}
    for name in pairs(signals) do names[#names + 1] = name end
    table.sort(names)

    local bought = {}
    for _, name in ipairs(names) do
        if signals[name] > 0 and allowed(name) then
            buy[#buy + 1] = { item = name, quantity = signals[name] }
            bought[name] = true
        end
    end
    for _, name in ipairs(names) do
        if signals[name] < 0 and not bought[name] and allowed(name) then
            sell[#sell + 1] = { item = name }
        end
    end

    return buy, sell
end

local function run_buys(data, company, inventory, orders)
    for _, order in ipairs(orders) do
        local deficit = order.quantity - inventory.get_item_count(order.item)
        if deficit > 0 then
            local price = utils.get_price(order.item)
            local buy_price = math.floor(price * M.BUY_MULTIPLIER + 0.5)
            local affordable = math.floor(company.credits / buy_price)
            local to_buy = math.min(deficit, affordable, stock.get(order.item))
            if to_buy > 0 then
                local inserted = inventory.insert({ name = order.item, count = to_buy })
                if inserted > 0 then
                    stock.take(order.item, inserted)
                    local spent = inserted * buy_price
                    company.credits = company.credits - spent
                    nauvis.burn(spent, "trading_silo:" .. data.force_name)
                    supply_demand.record_buy(order.item, inserted)
                    trading_history.record_buy(data.force_name, order.item, inserted, price)
                end
            end
        end
    end
end

local function run_sells(data, company, inventory, orders)
    for _, order in ipairs(orders) do
        local held = inventory.get_item_count(order.item)
        if held > 0 then
            local removed = inventory.remove({ name = order.item, count = held })
            if removed > 0 then
                local price = utils.get_price(order.item)
                stock.add(order.item, removed)
                local value = math.floor(removed * price * M.SELL_MULTIPLIER + 0.5)
                company.credits = company.credits + value
                nauvis.mint(value, "trading_silo:" .. data.force_name)
                supply_demand.record_sell(order.item, removed)
                trading_history.record_sell(data.force_name, order.item, removed, price)
            end
        end
    end
end

function M.process()
    if not storage.trading_silos then return end

    for unit_number, data in pairs(storage.trading_silos) do
        if not data.entity.valid then
            storage.trading_silos[unit_number] = nil
        else
            local company = storage.companies and storage.companies[data.force_name]
            if company then
                local inventory = data.entity.get_inventory(defines.inventory.chest)
                if inventory then
                    local buy, sell = M.resolve(data)
                    run_buys(data, company, inventory, buy)
                    run_sells(data, company, inventory, sell)
                end
            end
        end
    end
end

return M
