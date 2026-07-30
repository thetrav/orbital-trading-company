local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local market_gui = require("scripts.market_gui")
local supply_demand = require("scripts.supply_demand")

local M = {}

local BUY_CHEST_NAME = "otc-buy-chest"
local BUY_MULTIPLIER = 1.01

local function read_circuit_signals(chest)
    local signals = {}
    local green_id = chest.get_circuit_network(defines.wire_connector_id.circuit_green)
    if green_id then
        for _, sig in pairs(green_id.signals or {}) do
            if sig.signal and sig.signal.name then
                signals[sig.signal.name] = (signals[sig.signal.name] or 0) + sig.count
            end
        end
    end
    local red_id = chest.get_circuit_network(defines.wire_connector_id.circuit_red)
    if red_id then
        for _, sig in pairs(red_id.signals or {}) do
            if sig.signal and sig.signal.name then
                signals[sig.signal.name] = (signals[sig.signal.name] or 0) + sig.count
            end
        end
    end
    return signals
end

function M.register(entity)
    if not entity or not entity.valid then return end
    if entity.name ~= BUY_CHEST_NAME then return end

    local cb = entity.get_or_create_control_behavior()
    cb.read_contents = false

    storage.buy_chests = storage.buy_chests or {}
    storage.buy_chests[entity.unit_number] = {
        chest = entity,
        force_name = entity.force.name,
    }
end

function M.unregister(unit_number)
    if not storage.buy_chests then return end
    storage.buy_chests[unit_number] = nil
end

function M.process()
    if not storage.buy_chests then return end

    for unit_number, data in pairs(storage.buy_chests) do
        if not data.chest.valid then
            storage.buy_chests[unit_number] = nil
        else
            local force_name = data.force_name
            if not force_name then
                if data.chest.valid then
                    data.force_name = data.chest.force.name
                    force_name = data.force_name
                else
                    goto continue
                end
            end
            local company = storage.companies and storage.companies[force_name]
            if not company then goto continue end

            local signals = read_circuit_signals(data.chest)
            local cb = data.chest.get_or_create_control_behavior()
            if cb.read_contents then cb.read_contents = false end
            if next(signals) then
                local inventory = data.chest.get_inventory(defines.inventory.chest)

                for item_name, desired in pairs(signals) do
                    if item_filter.is_item_allowed(item_name, data.chest.force) then
                        local current = inventory.get_item_count(item_name)
                        local deficit = desired - current

                        if deficit > 0 then
                            local buy_price = math.floor(utils.get_price(item_name) * BUY_MULTIPLIER + 0.5)
                            local can_afford = math.floor(company.credits / buy_price)
                            local to_buy = math.min(deficit, can_afford)
                            if to_buy > 0 then
                                local inserted = inventory.insert({ name = item_name, count = to_buy })
                                if inserted > 0 then
                                    company.credits = company.credits - inserted * buy_price
                                    supply_demand.record_buy(item_name, inserted)
                                    market_gui.update_all_forces_credits()
                                end
                            end
                        end
                    end
                end
            end
        end
        ::continue::
    end
end

return M
