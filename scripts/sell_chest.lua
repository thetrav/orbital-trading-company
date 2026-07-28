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
    storage.sell_chests[entity.unit_number] = entity
end

function M.unregister(unit_number)
    if not storage.sell_chests then return end
    storage.sell_chests[unit_number] = nil
end

function M.process()
    if not storage.sell_chests then return end

    for unit_number, chest in pairs(storage.sell_chests) do
        if not chest.valid then
            storage.sell_chests[unit_number] = nil
        else
            local inventory = chest.get_inventory(defines.inventory.chest)
            local contents = inventory.get_contents()
            if #contents > 0 then
                local player = game.connected_players[1]
                if player then
                    local player_data = storage.players and storage.players[player.index]
                    if player_data then
                        for _, item in pairs(contents) do
                            if item_filter.is_item_allowed(item.name, chest.force) then
                                local removed = inventory.remove({ name = item.name, count = item.count })
                                if removed > 0 then
                                    local sell_value = math.floor(removed * utils.get_price(item.name) * SELL_MULTIPLIER + 0.5)
                                    player_data.credits = player_data.credits + sell_value
                                    supply_demand.record_sell(item.name, removed)
                                    market_gui.update_credits_gui(player.index)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

return M
