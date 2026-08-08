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

-- One colour for buys and the other for sells, never "both": in circuit control
-- a signal's *value* is now a price limit rather than a quantity, so an item
-- appearing on a wire read for both purposes would be a buy cap and a sell floor
-- at once. `M.set_wire` keeps the two apart.
local WIRES = {
    green = { defines.wire_connector_id.circuit_green },
    red = { defines.wire_connector_id.circuit_red },
}

M.WIRE_NAMES = { "green", "red" }

local function other_wire(wire)
    return wire == "green" and "red" or "green"
end

--- Bring a stored silo up to the current shape. Orders gained price limits and
--- the single `wire` became one per side, so a save from before either exists
--- has to be filled in rather than read as "no limit, no wire".
local function normalise(data)
    local circuit = data.circuit or {}
    if not circuit.buy_wire then
        -- The old single wire drove both sides. Keep it for buys and put sells on
        -- the other colour, because sharing one is exactly what is now ambiguous.
        local wire = circuit.wire == "red" and "red" or "green"
        circuit.buy_wire = wire
        circuit.sell_wire = other_wire(wire)
    end
    circuit.wire = nil
    circuit.enabled = circuit.enabled or false
    data.circuit = circuit
    -- A pre-limit order carries no cap, which reads as "no limit" rather than as
    -- "never trade": a save must not silently stop trading on upgrade.
    for _, order in ipairs(data.buy or {}) do
        order.quantity = order.quantity or 1
    end
    return data
end

M.normalise = normalise

function M.init()
    storage.trading_silos = storage.trading_silos or {}
    for _, data in pairs(storage.trading_silos) do
        normalise(data)
        M.apply_read_contents(data)
    end
end

function M.register(entity)
    if not entity or not entity.valid then return end
    if entity.name ~= M.NAME then return end

    storage.trading_silos = storage.trading_silos or {}
    storage.trading_silos[entity.unit_number] = normalise {
        entity = entity,
        force_name = entity.force.name,
        buy = {},
        sell = {},
        circuit = { enabled = false, buy_wire = "green", sell_wire = "red" },
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

--- A price limit typed into the panel. Blank or zero clears it, which means "no
--- limit" -- an empty field is a choice the player can see and undo, unlike a
--- missing circuit signal, which is indistinguishable from a zero and so has to
--- mean "do not trade".
function M.set_limit(data, side, index, value)
    local order = data[side] and data[side][index]
    if not order then return false end
    local limit = math.floor(tonumber(value) or 0)
    order.limit = limit > 0 and limit or nil
    return true
end

--- A wired container broadcasts its own contents onto the network. Harmless when
--- a signal meant a quantity; fatal now that it means a **price**, because the
--- silo's own stock is added to the cap the player set -- 200 iron plate in the
--- box turns a limit of 150 into a limit of 350.
---
--- So circuit control switches the broadcast off. A silo not under circuit
--- control keeps it, because there the wire is not carrying orders and reading
--- the box's contents is a perfectly good thing to want.
local function apply_read_contents(data)
    local entity = data.entity
    if not entity or not entity.valid then return end
    local behavior = entity.get_or_create_control_behavior()
    if behavior and behavior.object_name == "LuaContainerControlBehavior" then
        behavior.read_contents = not data.circuit.enabled
    end
end

M.apply_read_contents = apply_read_contents

function M.set_circuit_enabled(data, enabled)
    data.circuit.enabled = enabled and true or false
    apply_read_contents(data)
    return true
end

--- Which side of the wire a colour is read for. The two sides can never share a
--- colour, so picking one for a side pushes the other side off it.
function M.set_wire(data, side, wire)
    if wire ~= "green" and wire ~= "red" then return false end
    local circuit = data.circuit
    local other = side == "buy" and "sell" or "buy"
    circuit[side .. "_wire"] = wire
    if circuit[other .. "_wire"] == wire then
        circuit[other .. "_wire"] = other_wire(wire)
    end
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

local function sorted_names(signals)
    local names = {}
    for name in pairs(signals) do names[#names + 1] = name end
    table.sort(names)
    return names
end

--- The orders in force this tick, each `{ item, limit, quantity }`.
---
--- `limit` is a **max** buy price and a **min** sell price; nil means unbounded.
--- `quantity` is the buy target, or nil for "fill whatever the inventory will
--- take", which is what makes slot filters and the limiter bar the quantity
--- control under circuit input.
---
--- Circuit control replaces the stored configuration rather than merging with
--- it. The buy wire and the sell wire are read separately and a signal's value
--- is the price limit for that item; an item with no signal is **not traded**,
--- because a zero signal and an absent one are the same thing on a wire and
--- "buy at up to nothing" is not a sensible order.
function M.resolve(data)
    local force = data.entity.valid and data.entity.force or nil
    local function allowed(item_name)
        return force and item_filter.is_item_allowed(item_name, force)
    end

    local buy, sell = {}, {}

    if not data.circuit.enabled then
        for _, order in ipairs(data.buy) do
            if allowed(order.item) then
                buy[#buy + 1] = { item = order.item, quantity = order.quantity, limit = order.limit }
            end
        end
        for _, order in ipairs(data.sell) do
            if allowed(order.item) then
                sell[#sell + 1] = { item = order.item, limit = order.limit }
            end
        end
        return buy, sell
    end

    local buy_signals = read_signals(data.entity, data.circuit.buy_wire)
    for _, name in ipairs(sorted_names(buy_signals)) do
        if buy_signals[name] > 0 and allowed(name) then
            buy[#buy + 1] = { item = name, limit = buy_signals[name] }
        end
    end

    local sell_signals = read_signals(data.entity, data.circuit.sell_wire)
    for _, name in ipairs(sorted_names(sell_signals)) do
        if sell_signals[name] > 0 and allowed(name) then
            sell[#sell + 1] = { item = name, limit = sell_signals[name] }
        end
    end

    return buy, sell
end

--- What one unit costs to buy and fetches to sell, at the current market price.
--- Exported so the panel can show the player the number their limit is compared
--- against rather than the raw market price.
function M.buy_price(item_name)
    return math.floor(utils.get_price(item_name) * M.BUY_MULTIPLIER + 0.5)
end

function M.sell_price(item_name)
    return math.floor(utils.get_price(item_name) * M.SELL_MULTIPLIER + 0.5)
end

local function run_buys(data, company, inventory, orders)
    for _, order in ipairs(orders) do
        local price = utils.get_price(order.item)
        local buy_price = math.floor(price * M.BUY_MULTIPLIER + 0.5)
        -- An order with no quantity fills whatever the inventory will still take,
        -- which `get_insertable_count` works out from the slot filters and the
        -- limiter bar for us.
        local deficit = order.quantity
            and (order.quantity - inventory.get_item_count(order.item))
            or inventory.get_insertable_count(order.item)
        if order.limit and buy_price > order.limit then deficit = 0 end
        if deficit > 0 and buy_price > 0 then
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
        -- Compared against what a unit actually fetches, which is the number the
        -- panel shows, not the raw market price.
        if order.limit and M.sell_price(order.item) < order.limit then held = 0 end
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
