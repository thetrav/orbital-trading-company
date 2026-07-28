local platform = require("scripts.platform")
local pricing = require("scripts.pricing")
local market_gui = require("scripts.market_gui")
local buy_chest = require("scripts.buy_chest")
local sell_chest = require("scripts.sell_chest")
local supply_demand = require("scripts.supply_demand")

local BUY_CHEST_NAME = "otc-buy-chest"
local SELL_CHEST_NAME = "otc-sell-chest"
local COMBINATOR_NAME = "constant-combinator"
local BUY_CHEST_POSITION = { x = -4, y = 0 }
local COMBINATOR_POSITION = { x = -4, y = -1 }
local SELL_CHEST_POSITION = { x = 4, y = 0 }

script.on_init(function()
    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_skip_intro", true)
        remote.call("freeplay", "set_disable_crashsite", true)
    end

    storage.players = {}

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

    for _, player in pairs(game.connected_players) do
        player.teleport({0.5, 0.5}, surface)
        market_gui.init_player(player)
    end

    local combinator = surface.create_entity {
        name = COMBINATOR_NAME,
        position = COMBINATOR_POSITION,
        force = "player",
    }
    if combinator then
        combinator.minable = false
        combinator.destructible = false

        local behaviour = combinator.get_or_create_control_behavior()
        local section = behaviour.get_section(1)
        section.set_slot(1, { value = { type = "item", name = "iron-ore", quality = "normal" }, min = 1 })
        section.set_slot(2, { value = { type = "item", name = "coal", quality = "normal" }, min = 1 })
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
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player and not player.gui.screen.otc_credits_frame then
        market_gui.init_player(player)
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
        local search_frame = frame.otc_market_search_frame
        if not search_frame then return end
        search_frame.visible = not search_frame.visible
        if not search_frame.visible then
            local field = search_frame.otc_market_search
            if field then field.text = "" end
            market_gui.rebuild_market_list(player)
        end
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
