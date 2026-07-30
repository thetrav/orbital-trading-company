local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local market_gui = require("scripts.market_gui")
local supply_demand = require("scripts.supply_demand")

local M = {}

local SELL_CHEST_NAME = "otc-sell-chest"
local SELL_MULTIPLIER = 0.99

function M.register(entity)
    if not entity or not entity.valid then return end
    if entity.name ~= SELL_CHEST_NAME then return end

    storage.sell_chests = storage.sell_chests or {}
    storage.sell_chests[entity.unit_number] = {
        chest = entity,
        force_name = entity.force.name,
    }
end

function M.unregister(unit_number)
    if not storage.sell_chests then return end
    storage.sell_chests[unit_number] = nil
end

function M.process()
    if not storage.sell_chests then return end

    for unit_number, data in pairs(storage.sell_chests) do
        if not data.chest.valid then
            storage.sell_chests[unit_number] = nil
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

            local inventory = data.chest.get_inventory(defines.inventory.chest)
            local contents = inventory.get_contents()
            if #contents > 0 then
                for _, item in pairs(contents) do
                    if item_filter.is_item_allowed(item.name, data.chest.force) then
                        local removed = inventory.remove({ name = item.name, count = item.count })
                        if removed > 0 then
                            local price = utils.get_price(item.name)
                            local sell_value = math.floor(removed * price * SELL_MULTIPLIER + 0.5)
                            company.credits = company.credits + sell_value
                            supply_demand.record_sell(item.name, removed)
                            market_gui.update_all_forces_credits()
                        end
                    end
                end
            end
        end
        ::continue::
    end
end

return M
