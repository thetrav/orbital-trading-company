local platform_gates = require("scripts.platform_gates")
local pricing = require("scripts.pricing")
local market_gui = require("scripts.market_gui")
local expand_gui = require("scripts.expand_gui")
local buy_chest = require("scripts.buy_chest")
local sell_chest = require("scripts.sell_chest")
local supply_demand = require("scripts.supply_demand")
local company_gui = require("scripts.company_gui")
local trading_history = require("scripts.trading_history")
local trading_gui = require("scripts.trading_gui")

local BUY_CHEST_NAME = "otc-buy-chest"
local SELL_CHEST_NAME = "otc-sell-chest"
local NAUVIS_FORCE = "Nauvis"

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
                        force = NAUVIS_FORCE,
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
    platform_gates.place_gate_controls(surface, NAUVIS_FORCE)

    local monitor = surface.create_entity{
        name = "otc-company-monitor",
        position = {4, 4},
        force = NAUVIS_FORCE,
        icon = { type = "space-location", name = "nauvis" },
    }
    if monitor then
        monitor.minable = false
        monitor.destructible = false
        local behavior = monitor.get_or_create_control_behavior()
        behavior.set_message(-1, { text = "Company Management" })
    end
end

local function ensure_company_setup()
    if not storage.companies then
        storage.companies = {}
    end
    if not storage.companies[NAUVIS_FORCE] then
        storage.companies[NAUVIS_FORCE] = { credits = 0 }
    end
    if not game.forces[NAUVIS_FORCE] then
        game.create_force(NAUVIS_FORCE)
    end
    for _, force in pairs(game.forces) do
        force.set_cease_fire(game.forces[NAUVIS_FORCE], true)
        force.set_friend(game.forces[NAUVIS_FORCE], true)
    end
    if not storage.station_forces then
        storage.station_forces = {}
    end
    if storage.players then
        for _, pd in pairs(storage.players) do
            if pd.credits and not pd.company then
                local legacy_name = "Default"
                if not storage.companies[legacy_name] then
                    if not game.forces[legacy_name] then
                        game.create_force(legacy_name)
                        for _, force in pairs(game.forces) do
                            force.set_cease_fire(game.forces[legacy_name], true)
                            force.set_friend(game.forces[legacy_name], true)
                        end
                    end
                    storage.companies[legacy_name] = { credits = pd.credits }
                end
                pd.company = legacy_name
                pd.credits = nil
            end
        end
    end
    for _, data in pairs(storage.buy_chests or {}) do
        local c = data.chest
        ---@diagnostic disable-next-line: undefined-field
        if not data.force_name and c and c.valid then
            ---@diagnostic disable-next-line: undefined-field
            data.force_name = c.force.name
        end
    end
    for unit_number, data in pairs(storage.sell_chests or {}) do
        if type(data) == "userdata" then
            ---@diagnostic disable-next-line: undefined-field
            if data.valid then
                storage.sell_chests[unit_number] = {
                    chest = data,
                    ---@diagnostic disable-next-line: undefined-field
                    force_name = data.force.name,
                }
            end
        else
            local c = data.chest
            if c and not data.force_name and c.valid then
                data.force_name = c.force.name
            end
        end
    end
end

script.on_init(function()
    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_skip_intro", true)
        remote.call("freeplay", "set_disable_crashsite", true)
    end

    storage.players = {}

    supply_demand.init()
    trading_history.init()
    ensure_company_setup()

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
        storage.players = storage.players or {}
        if not storage.players[player.index] then
            storage.players[player.index] = {}
        end
        player.insert{name = "storage-tank", count = 1}
        player.insert{name = "pipe-to-ground", count = 2}
    end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player then
        player.set_shortcut_toggled("otc-trading", false)
    end
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "otc-trading" then
        local player = game.get_player(event.player_index)
        if not player then return end
        if player.gui.screen.otc_trading_frame then
            trading_gui.close(player)
        else
            trading_gui.create_trading_gui(player)
        end
    end
end)

script.on_event(defines.events.on_research_finished, function()
    for _, player in pairs(game.connected_players) do
        local player_data = storage.players and storage.players[player.index]
        if player_data then
            player_data.allowed_items = nil
        end
        if player.gui.screen.otc_market_frame then
            market_gui.rebuild_market_list(player)
        end
    end
end)

script.on_nth_tick(60, function()
    trading_history.advance_second()
    trading_gui.refresh()
end)

script.on_configuration_changed(function()
    ensure_company_setup()
end)

local market_refresh_counter = 0
local MARKET_REFRESH_INTERVAL = 30

script.on_nth_tick(1, function()
    buy_chest.process()
    sell_chest.process()
    supply_demand.process_tick()
    for _, player in pairs(game.connected_players) do
        expand_gui.check_proximity(player)
    end
    for _, surface in pairs(game.surfaces) do
        for _, pump in ipairs(surface.find_entities_filtered{name = "otc-water-pump"}) do
            if pump.valid then
                pump.fluidbox[1] = {name = "water", amount = 100}
            end
        end
    end
    market_refresh_counter = market_refresh_counter + 1
    if market_refresh_counter >= MARKET_REFRESH_INTERVAL then
        market_refresh_counter = 0
        for _, player in pairs(game.connected_players) do
            if player.gui.screen.otc_market_frame then
                market_gui.refresh_market_prices(player)
            end
        end
    end
end)

script.on_event(defines.events.on_built_entity, function(event)
    buy_chest.register(event.created_entity)
    sell_chest.register(event.created_entity)
end)

script.on_event(defines.events.on_selected_entity_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local entity = player.selected
    if not entity or not entity.valid then return end
    if entity.name == "otc-company-monitor" then
        company_gui.open(player)
    end
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
    if event.element.name == "otc_company_create" then
        local player = game.get_player(event.player_index)
        if player then company_gui.handle_create(player) end
        return
    end

    if event.element.name == "otc_company_close" then
        local player = game.get_player(event.player_index)
        if player then company_gui.close(player) end
        return
    end

    local join_name = string.match(event.element.name, "^otc_company_join_(.+)$")
    if join_name then
        local player = game.get_player(event.player_index)
        if player then company_gui.handle_join(player, join_name) end
        return
    end

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
        return
    end

    if event.element.name == "otc_trading_close" then
        local player = game.get_player(event.player_index)
        if player then trading_gui.close(player) end
        return
    end

    if event.element.name == "otc_expand_buy_button" then
        local player = game.get_player(event.player_index)
        if not player then return end
        expand_gui.handle_buy_expansion(player)
    end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    if event.element.name == "otc_trading_force_dropdown" then
        local element = event.element
        local force_name = element.items and element.items[element.selected_index]
        if force_name then
            trading_gui.handle_force_change(player, force_name)
        end
        return
    end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    local item_name = string.match(event.element.name, "^otc_pin_(.+)$")
    if item_name then
        player_data.pinned_items = player_data.pinned_items or {}
        if event.element.state then
            player_data.pinned_items[item_name] = true
        else
            player_data.pinned_items[item_name] = nil
        end
        market_gui.rebuild_market_list(player)
        return
    end

    local series_name = string.match(event.element.name, "^otc_series_(.+)$")
    if series_name then
        local kind, item_name = string.match(series_name, "^(%a+)_(.+)$")
        if kind == "income" or kind == "expense" or kind == "profit" then
            trading_gui.handle_series_toggle(player, kind, item_name, event.element.state)
            return
        end
    end

end)

script.on_event(defines.events.on_gui_text_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    if event.element.name == "otc_market_search" then
        market_gui.rebuild_market_list(player)
    elseif event.element.name == "otc_trading_search" then
        trading_gui.handle_search(player, event.element.text)
    end
end)
