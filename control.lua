local platform_gates = require("scripts.platform_gates")
local pricing = require("scripts.pricing")
local market_gui = require("scripts.market_gui")
local expand_gui = require("scripts.expand_gui")
local buy_chest = require("scripts.buy_chest")
local sell_chest = require("scripts.sell_chest")
local supply_demand = require("scripts.supply_demand")

local BUY_CHEST_NAME = "otc-buy-chest"
local SELL_CHEST_NAME = "otc-sell-chest"

local function clear_enemies()
    local nauvis = game.surfaces["nauvis"]
    if nauvis then
        for _, entity in ipairs(nauvis.find_entities_filtered{force = "enemy"}) do
            if entity.valid then entity.destroy() end
        end
    end
end

local function build_starting_room(surface)
    local R = 5
    local WR = R + 1

    local entities = surface.find_entities_filtered{area = {{-WR, -WR}, {WR, WR}}}
    for _, entity in ipairs(entities) do
        if entity.valid then
            entity.destroy()
        end
    end

    local tiles = {}
    for x = -WR, WR do
        for y = -WR, WR do
            if (math.abs(x) <= R and math.abs(y) <= R) or math.abs(x) == WR or math.abs(y) == WR then
                table.insert(tiles, {name = "otc-platform", position = {x, y}})
            end
        end
    end
    surface.set_tiles(tiles, true)
    surface.destroy_decoratives{area = {{-WR, -WR}, {WR, WR}}}

    for x = -WR, WR do
        for y = -WR, WR do
            if math.abs(x) == WR or math.abs(y) == WR then
                if not platform_gates.is_entity_position(x, y) then
                    local wall = surface.create_entity{
                        name = "otc-platform-wall",
                        position = {x, y},
                        force = "player",
                    }
                    if wall then
                        wall.minable = false
                        wall.destructible = false
                    end
                end
            end
        end
    end

    platform_gates.init_gates_for_surface(surface)
    platform_gates.place_gate_controls(surface)
end

script.on_init(function()
    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_skip_intro", true)
        remote.call("freeplay", "set_disable_crashsite", true)
    end

    storage.players = {}

    supply_demand.init()

    clear_enemies()
    game.map_settings.pollution.enabled = false
    game.map_settings.enemy_expansion.enabled = false

    local nauvis = game.surfaces["nauvis"]
    if nauvis then
        build_starting_room(nauvis)
    end

    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_created_items", {
            ["iron-plate"] = 8,
            ["stone-furnace"] = 1,
            ["burner-inserter"] = 2,
        })
    end

    storage.prices = pricing.calculate()
end)

script.on_load(function()
    storage.prices = pricing.calculate()
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        market_gui.init_player(player)
        expand_gui.init_player(player)
    end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player then
        if not player.gui.screen.otc_credits_frame then
            market_gui.init_player(player)
        end
        if not player.gui.screen.otc_expand_frame then
            expand_gui.init_player(player)
        end
    end
end)

script.on_configuration_changed(function() end)

script.on_nth_tick(1, function()
    buy_chest.process()
    sell_chest.process()
    supply_demand.process_tick()
    for _, player in pairs(game.connected_players) do
        expand_gui.check_proximity(player)
    end
end)

script.on_event(defines.events.on_built_entity, function(event)
    buy_chest.register(event.created_entity)
    sell_chest.register(event.created_entity)
end)

script.on_event(defines.events.on_gui_opened, function(event)
    local entity = event.entity
    local player = game.get_player(event.player_index)
    if not entity or not entity.valid or not player then return end

    if platform_gates.try_open_gate_computer(entity, player, expand_gui) then
        return
    end

    if entity.name == "rocket-silo" then
        local un = entity.unit_number
        if un and storage.rocket_silos and storage.rocket_silos[un] then
            player.opened = nil
        end
    end
end)

script.on_event(defines.events.on_player_driving_changed_state, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local vehicle = player.vehicle
    if not vehicle then return end
    if vehicle.name ~= "otc-teleporter" then return end

    local station_name = storage.otc_teleporters and storage.otc_teleporters[vehicle.unit_number]
    if station_name then
        local station = game.surfaces[station_name]
        if station then
            player.teleport({0, 6}, station)
            player.driving = false
            player.print("Teleported to orbital station.")
        end
        return
    end

    local return_data = storage.otc_return_teleporters and storage.otc_return_teleporters[vehicle.unit_number]
    if return_data then
        local surface = game.surfaces[return_data.surface]
        if surface then
            player.teleport(return_data.position, surface)
            player.driving = false
            player.print("Teleported back to Nauvis.")
        end
    end
end)

script.on_event(defines.events.on_entity_died, function(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    local name = entity.name
    if name == BUY_CHEST_NAME then
        buy_chest.unregister(entity.unit_number)
    elseif name == SELL_CHEST_NAME then
        sell_chest.unregister(entity.unit_number)
    elseif name == "rocket-silo" then
        if storage.rocket_silos then
            storage.rocket_silos[entity.unit_number] = nil
        end
    elseif name == "otc-teleporter" then
        if storage.otc_teleporters then
            storage.otc_teleporters[entity.unit_number] = nil
        end
        if storage.otc_return_teleporters then
            storage.otc_return_teleporters[entity.unit_number] = nil
        end
    end
end)

script.on_event(defines.events.on_player_mined_entity, function(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    local name = entity.name
    if name == BUY_CHEST_NAME then
        buy_chest.unregister(entity.unit_number)
    elseif name == SELL_CHEST_NAME then
        sell_chest.unregister(entity.unit_number)
    elseif name == "rocket-silo" then
        if storage.rocket_silos then
            storage.rocket_silos[entity.unit_number] = nil
        end
    elseif name == "otc-teleporter" then
        if storage.otc_teleporters then
            storage.otc_teleporters[entity.unit_number] = nil
        end
        if storage.otc_return_teleporters then
            storage.otc_return_teleporters[entity.unit_number] = nil
        end
    end
end)


script.on_event(defines.events.on_gui_click, function(event)
    if event.element.name == "otc_market_search_button" then
        local player = game.get_player(event.player_index)
        if not player then return end
        local frame = player.gui.screen.otc_market_frame
        if not frame then return end
        local search_frame = frame.title_flow.otc_market_search_frame
        if not search_frame then return end
        local drag = frame.title_flow.otc_market_drag
        search_frame.visible = not search_frame.visible
        if search_frame.visible then
            if drag then
                drag.style.horizontally_stretchable = false
                drag.style.width = 24
            end
        else
            local field = search_frame.otc_market_search
            if field then field.text = "" end
            if drag then
                drag.style.width = nil
                drag.style.horizontally_stretchable = true
            end
            market_gui.rebuild_market_list(player)
        end
    end

    local filter_mode = string.match(event.element.name, "^otc_market_filter_(.+)$")
    if filter_mode then
        local player = game.get_player(event.player_index)
        if not player then return end
        local player_data = storage.players and storage.players[player.index]
        if player_data then
            player_data.market_filter = filter_mode
        end
        market_gui.rebuild_market_list(player)
    end

    local shape_name = string.match(event.element.name, "^otc_shape_(.+)$")
    if shape_name then
        local player = game.get_player(event.player_index)
        if not player then return end
        expand_gui.handle_selection_change(player, shape_name)
        return
    end

    if event.element.name == "otc_expand_close" then
        local player = game.get_player(event.player_index)
        if not player then return end
        expand_gui.close(player)
    end

    if event.element.name == "otc_expand_buy_button" then
        local player = game.get_player(event.player_index)
        if not player then return end
        expand_gui.handle_buy_expansion(player)
    end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local item_name = string.match(event.element.name, "^otc_pin_(.+)$")
    if item_name then
        local player = game.get_player(event.player_index)
        if not player then return end
        local player_data = storage.players and storage.players[player.index]
        if not player_data then return end
        player_data.pinned_items = player_data.pinned_items or {}
        if event.element.state then
            player_data.pinned_items[item_name] = true
        else
            player_data.pinned_items[item_name] = nil
        end
        market_gui.rebuild_market_list(player)
    end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
    if event.element.name == "otc_market_search" then
        local player = game.get_player(event.player_index)
        if player then
            market_gui.rebuild_market_list(player)
        end
    end
end)
