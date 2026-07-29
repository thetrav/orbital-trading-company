local platform = require("scripts.platform")
local platform_gates = require("scripts.platform_gates")
local pricing = require("scripts.pricing")
local market_gui = require("scripts.market_gui")
local store_gui = require("scripts.store_gui")
local buy_chest = require("scripts.buy_chest")
local sell_chest = require("scripts.sell_chest")
local supply_demand = require("scripts.supply_demand")

local BUY_CHEST_NAME = "otc-buy-chest"
local SELL_CHEST_NAME = "otc-sell-chest"
local BUY_CHEST_POSITION = { x = -3, y = 0 }
local SELL_CHEST_POSITION = { x = 2, y = 0 }

script.on_init(function()
    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_skip_intro", true)
        remote.call("freeplay", "set_disable_crashsite", true)
    end

    storage.players = {}

    platform_gates.init_gates()
    supply_demand.init()

    local surface = game.surfaces[1]
    game.map_settings.pollution.enabled = false
    game.map_settings.enemy_expansion.enabled = false

    local mgs = surface.map_gen_settings
    mgs.width = 0
    mgs.height = 0
    mgs.starting_area = 0
    mgs.terrain_segmentation = 0
    mgs.water = 0
    mgs.cliff_settings.cliff_elevation_interval = 0
    mgs.cliff_settings.richness = 0
    mgs.peaceful_mode = true
    mgs.no_enemies_mode = true
    mgs.autoplace_controls = {}
    surface.map_gen_settings = mgs

    local radius = 160
    platform.build_platform(surface, {
        left_top = {x = -radius, y = -radius},
        right_bottom = {x = radius, y = radius}
    })

    platform_gates.place_gate_controls(surface)

    for _, player in pairs(game.connected_players) do
        player.teleport({0.5, 0.5}, surface)
        market_gui.init_player(player)
        store_gui.init_player(player)
    end

    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_created_items", {
            ["iron-plate"] = 8,
            ["pistol"] = 1,
            ["firearm-magazine"] = 10,
            ["stone-furnace"] = 1,
            ["burner-inserter"] = 2,
            ["constant-combinator"] = 1,
        })
    end

    local chest = surface.create_entity {
        name = BUY_CHEST_NAME,
        position = BUY_CHEST_POSITION,
        force = "player",
    }
    if chest then
        chest.minable = false
        chest.destructible = false
        buy_chest.register(chest)
    end

    local sell_chest_entity = surface.create_entity {
        name = SELL_CHEST_NAME,
        position = SELL_CHEST_POSITION,
        force = "player",
    }
    if sell_chest_entity then
        sell_chest_entity.minable = false
        sell_chest_entity.destructible = false
        sell_chest.register(sell_chest_entity)
    end

    storage.prices = pricing.calculate()
end)

script.on_load(function()
    storage.prices = pricing.calculate()
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    market_gui.init_player(player)
    store_gui.init_player(player)
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player then
        if not player.gui.screen.otc_credits_frame then
            market_gui.init_player(player)
        end
        if not player.gui.screen.otc_store_frame then
            store_gui.init_player(player)
        end
    end
end)

script.on_event(defines.events.on_chunk_generated, function(event)
    if event.surface.index ~= 1 then return end
    platform.build_platform(event.surface, event.area)
end)

script.on_nth_tick(1, function()
    buy_chest.process()
    sell_chest.process()
    supply_demand.process_tick()
end)

script.on_event(defines.events.on_built_entity, function(event)
    buy_chest.register(event.created_entity)
    sell_chest.register(event.created_entity)
end)

platform_gates.register_events(script.on_event, store_gui)

script.on_event(defines.events.on_entity_died, function(event)
    if event.entity.name == BUY_CHEST_NAME then
        buy_chest.unregister(event.entity.unit_number)
    elseif event.entity.name == SELL_CHEST_NAME then
        sell_chest.unregister(event.entity.unit_number)
    end
end)

script.on_event(defines.events.on_player_mined_entity, function(event)
    if event.entity.name == BUY_CHEST_NAME then
        buy_chest.unregister(event.entity.unit_number)
    elseif event.entity.name == SELL_CHEST_NAME then
        sell_chest.unregister(event.entity.unit_number)
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

    if event.element.name == "otc_store_close" then
        local player = game.get_player(event.player_index)
        if not player then return end
        store_gui.close(player)
    end

    if event.element.name == "otc_store_buy_expansion" then
        local player = game.get_player(event.player_index)
        if not player then return end
        store_gui.handle_buy_expansion(player)
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
