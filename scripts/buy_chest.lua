local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local market_gui = require("scripts.market_gui")

local M = {}

local BUY_CHEST_NAME = "otc-buy-chest"
local COMBINATOR_NAME = "constant-combinator"
local BUY_MULTIPLIER = 1.05

local function find_combinator_above(chest)
    local pos = chest.position
    local search_area = {
        { pos.x - 0.5, pos.y - 1.5 },
        { pos.x + 0.5, pos.y - 0.5 },
    }
    local entities = chest.surface.find_entities_filtered {
        area = search_area,
        name = COMBINATOR_NAME,
        force = chest.force,
    }
    return entities[1]
end

local function connect_combinator_to_chest(combinator, chest)
    if combinator and combinator.valid and chest and chest.valid then
        local combinator_out = combinator.get_wire_connector(defines.wire_connector_id.circuit_green, true)
        local chest_in = chest.get_wire_connector(defines.wire_connector_id.circuit_green, true)
        if combinator_out and chest_in then
            combinator_out.connect_to(chest_in, false, defines.wire_origin.player)
        end
    end
end

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

    local combinator = find_combinator_above(entity)
    if not combinator then return end

    connect_combinator_to_chest(combinator, entity)

    storage.buy_chests = storage.buy_chests or {}
    storage.buy_chests[entity.unit_number] = {
        chest = entity,
        combinator = combinator,
    }
end

function M.unregister(unit_number)
    if not storage.buy_chests then return end
    storage.buy_chests[unit_number] = nil
end

function M.process()
    if not storage.buy_chests then return end

    for unit_number, data in pairs(storage.buy_chests) do
        if not data.chest.valid or not data.combinator.valid then
            storage.buy_chests[unit_number] = nil
        else
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
                            local player = game.connected_players[1]
                            if player then
                                local player_data = storage.players and storage.players[player.index]
                                if player_data then
                                    local buy_price = math.floor(utils.get_price(item_name) * BUY_MULTIPLIER + 0.5)
                                    local can_afford = math.floor(player_data.credits / buy_price)
                                    local to_buy = math.min(deficit, can_afford)
                                    if to_buy > 0 then
                                        local inserted = inventory.insert({ name = item_name, count = to_buy })
                                        if inserted > 0 then
                                            player_data.credits = player_data.credits - inserted * buy_price
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
    end
end

return M
