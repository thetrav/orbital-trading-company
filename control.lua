local platform_gates = require("scripts.platform_gates")
local platform = require("scripts.platform")
local shape_capture = require("scripts.shape_capture")
local shape_config = require("scripts.shape_config")
local shape_place = require("scripts.shape_place")
local nauvis_guard = require("scripts.nauvis_guard")
local pricing = require("scripts.pricing")
local market_gui = require("scripts.market_gui")
local expand_gui = require("scripts.expand_gui")
local buy_chest = require("scripts.buy_chest")
local sell_chest = require("scripts.sell_chest")
local supply_demand = require("scripts.supply_demand")
local company_gui = require("scripts.company_gui")
local company = require("scripts.company")
local nauvis = require("scripts.nauvis")
local trading_history = require("scripts.trading_history")
local trading_gui = require("scripts.trading_gui")
local stock = require("scripts.stock")
local nauvis_industry = require("scripts.nauvis_industry")
local nauvis_expansion = require("scripts.nauvis_expansion")
local company_facilities = require("scripts.company_facilities")
local district = require("scripts.district")
local research = require("scripts.research")
local supply_belts = require("scripts.supply_belts")

local BUY_CHEST_NAME = "otc-buy-chest"
local SELL_CHEST_NAME = "otc-sell-chest"
local NAUVIS_FORCE = "Nauvis"
local STARTING_PERSONAL_CREDITS = 10000

-- Nauvis generates as a normal world now, so nests come with it. Autoplace is
-- turned down in data-final-fixes, peaceful mode stops anything that survives
-- from hunting, and on_chunk_generated sweeps newly revealed ground -- players
-- are free to walk out and explore, and there must be nothing out there to
-- meet them.
local function clear_enemies(surface, area)
    surface = surface or game.surfaces["nauvis"]
    if not surface then return end
    local filter = { force = "enemy" }
    if area then filter.area = area end
    for _, entity in ipairs(surface.find_entities_filtered(filter)) do
        if entity.valid then entity.destroy() end
    end
end

local function make_peaceful()
    local surface = game.surfaces["nauvis"]
    if surface then surface.peaceful_mode = true end
    game.map_settings.pollution.enabled = false
    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.enemy_evolution.enabled = false
end

local function build_starting_room(surface)
    platform.build_shape(surface, "nauvis_starting_room", {x = 0, y = 0}, NAUVIS_FORCE)
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

    stock.init()
    research.init()
    district.init()
    company_facilities.init()
    nauvis_expansion.init()

    local nauvis_is_new = storage.nauvis == nil
    nauvis.init()
    if nauvis_is_new then
        storage.nauvis.minted = storage.nauvis.minted + (storage.companies[NAUVIS_FORCE].credits or 0)
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
            if pd.personal_credits == nil then
                pd.personal_credits = 0
            end
        end
    end

    for name, comp in pairs(storage.companies) do
        if not company.is_state(name) and not comp.holders then
            local members = {}
            if storage.players then
                for idx, pd in pairs(storage.players) do
                    if pd.company == name then table.insert(members, idx) end
                end
            end
            table.sort(members)

            local total_shares = math.max(math.floor((comp.credits or 0) / company.SHARE_PAR), 1)
            comp.holders = {}
            if #members > 0 then
                local per = math.floor(total_shares / #members)
                local remainder = total_shares - per * #members
                for i, idx in ipairs(members) do
                    local shares = per + (i == 1 and remainder or 0)
                    comp.holders[idx] = {
                        shares = shares,
                        role = (i == 1) and "manager" or "member",
                        joined_tick = 0,
                    }
                end
            end

            comp.founded_tick = comp.founded_tick or 0
            comp.treasury_shares = 0
            comp.shares_issued = total_shares
            comp.pending = comp.pending or {}
            comp.auctions = comp.auctions or {}
            comp.receivership = #members == 0
            comp.valuation = comp.valuation
                or { tick = 0, cash = 0, assets = 0, inventory = 0, earnings = 0, total = 0, per_share = 0 }
            comp.ledger = comp.ledger or {}
        end
    end

    for name, comp in pairs(storage.companies) do
        if not company.is_state(name) and comp.holders then
            local sum = (comp.treasury_shares or 0) + nauvis.get_holding(name)
            for _, holder in pairs(comp.holders) do
                sum = sum + holder.shares
            end
            comp.shares_issued = sum
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
    shape_capture.init()
    shape_config.init()
    shape_place.init()
    nauvis_guard.init()
    ensure_company_setup()

    clear_enemies()
    make_peaceful()

    local nauvis_surface = game.surfaces["nauvis"]
    if nauvis_surface then
        build_starting_room(nauvis_surface)
    end
    nauvis_industry.ensure_built()

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

shape_capture.register_commands()
shape_config.register_commands()
shape_place.register_commands()

script.on_event(defines.events.on_player_selected_area, function(event)
    shape_capture.on_selected_area(event, false)
    shape_config.on_selected_area(event, false)
end)

script.on_event(defines.events.on_player_alt_selected_area, function(event)
    shape_capture.on_selected_area(event, true)
    shape_config.on_selected_area(event, true)
end)

-- Right-drag. Only the capture tool defines a reverse selection, and it means
-- the same thing there as shift+left-drag: entities, no tiles.
script.on_event(defines.events.on_player_reverse_selected_area, function(event)
    shape_capture.on_selected_area(event, true)
end)

script.on_event(defines.events.on_player_alt_reverse_selected_area, function(event)
    shape_capture.on_selected_area(event, true)
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        storage.players = storage.players or {}
        if not storage.players[player.index] then
            storage.players[player.index] = {}
        end
        local player_data = storage.players[player.index]
        if player_data.personal_credits == nil then
            player_data.personal_credits = STARTING_PERSONAL_CREDITS
            nauvis.mint(STARTING_PERSONAL_CREDITS, "starting_grant")
        end
        market_gui.create_credits_gui(player)
        research.lock_player_research(player)
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

script.on_event(defines.events.on_player_rotated_entity, function(event)
    -- Rotating an underground belt flips it between entrance and exit; a supply
    -- belt must stay an exit, so the rotation is turned back into a 180 degree
    -- turn. The rebuild changes unit_number, so the config tag moves with it.
    local entity = event.entity
    if not entity or not entity.valid then return end
    if nauvis_guard.on_rotated(event) then return end
    local old = entity.unit_number
    local rebuilt = supply_belts.enforce_exit(entity)
    if rebuilt then shape_config.migrate(old, rebuilt) end
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
    local player = game.get_player(event.player_index)
    if player then shape_place.handle_cursor_changed(player) end
end)

script.on_event(defines.events.on_player_display_scale_changed, function(event)
    local player = game.get_player(event.player_index)
    if player then trading_gui.handle_display_scale_changed(player) end
end)

script.on_event(defines.events.on_research_finished, function(event)
    research.handle_research_finished(event.research.force)
    for _, player in pairs(game.connected_players) do
        local player_data = storage.players and storage.players[player.index]
        if player_data then
            player_data.allowed_items = nil
        end
        if player.gui.screen.otc_market_frame then
            market_gui.rebuild_market_list(player)
        end
        company_gui.refresh_nauvis_tab(player)
    end
end)

script.on_nth_tick(60, function()
    trading_history.advance_second()
    trading_gui.refresh()
    research.start_pending_research()
    nauvis_expansion.process()
end)

script.on_event(defines.events.on_chunk_generated, function(event)
    if event.surface.name ~= "nauvis" then return end
    clear_enemies(event.surface, event.area)
end)

script.on_configuration_changed(function()
    clear_enemies()
    make_peaceful()
    shape_capture.init()
    shape_config.init()
    shape_place.init()
    nauvis_guard.init()
    ensure_company_setup()
    nauvis_industry.ensure_built()
end)

local market_refresh_counter = 0
local MARKET_REFRESH_INTERVAL = 30

script.on_nth_tick(1, function()
    buy_chest.process()
    sell_chest.process()
    supply_belts.process()
    supply_demand.process_tick()
    research.sync_all_progress()
    market_gui.update_all_forces_credits()
    for _, player in pairs(game.connected_players) do
        expand_gui.check_proximity(player)
        company_gui.check_proximity(player)
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
            company_gui.refresh_nauvis_stock(player)
        end
    end
end)

script.on_event(defines.events.on_built_entity, function(event)
    -- 2.0 renamed this field; `created_entity` reads nil and silently disables
    -- everything below it.
    local entity = event.entity
    if entity and entity.valid and shape_place.on_marker_built(entity, event.player_index) then
        return
    end
    if nauvis_guard.on_built(entity, event.player_index) then return end
    if research.block_lab(entity, event.player_index) then return end
    buy_chest.register(entity)
    sell_chest.register(entity)
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
    if nauvis_guard.on_built(event.entity, nil) then return end
    research.block_lab(event.entity, nil)
end)

script.on_event(defines.events.on_pre_player_mined_item, function(event)
    nauvis_guard.on_pre_mined(event)
end)

script.on_event(defines.events.on_pre_entity_settings_pasted, function(event)
    nauvis_guard.on_pre_settings_pasted(event)
end)

script.on_event(defines.events.on_entity_settings_pasted, function(event)
    nauvis_guard.on_settings_pasted(event)
end)

script.on_event(defines.events.on_marked_for_deconstruction, function(event)
    nauvis_guard.on_marked_for_deconstruction(event)
end)

script.on_event(defines.events.on_marked_for_upgrade, function(event)
    nauvis_guard.on_marked_for_upgrade(event)
end)

script.on_event(defines.events.on_picked_up_item, function(event)
    nauvis_guard.on_picked_up(event)
end)

script.on_event(defines.events.on_player_fast_transferred, function(event)
    nauvis_guard.on_fast_transferred(event)
end)

script.on_event(defines.events.on_selected_entity_changed, function(event)
    local player = game.get_player(event.player_index)
    if player then nauvis_guard.on_hover(player) end
end)

script.on_event(defines.events.on_gui_opened, function(event)
    local entity = event.entity
    local player = game.get_player(event.player_index)
    if not entity or not entity.valid or not player then return end

    if nauvis_guard.on_gui_opened(player, entity) then return end

    if platform_gates.try_open_gate_computer(entity, player, expand_gui) then
        return
    end

    if entity.name == "otc-company-monitor" then
        player.opened = nil
        company_gui.open(player, entity)
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
            player.teleport(platform.station_arrival_position(), station)
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
    if nauvis_guard.on_mined(event) then return end
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
    if event.element.name == "otc_shape_config_close" then
        local player = game.get_player(event.player_index)
        if player then shape_config.close(player) end
        return
    end

    if event.element.name == "otc_place_close" then
        local player = game.get_player(event.player_index)
        if player then shape_place.close(player) end
        return
    end

    local place_shape = string.match(event.element.name, "^otc_place_shape_(.+)$")
    if place_shape then
        local player = game.get_player(event.player_index)
        if player then shape_place.handle_selection(player, place_shape) end
        return
    end

    if string.match(event.element.name, "^otc_company_") then
        local player = game.get_player(event.player_index)
        if player then company_gui.handle_click(player, event.element.name) end
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

    local scale_key = string.match(event.element.name, "^otc_trading_scale_(.+)$")
    if scale_key then
        local player = game.get_player(event.player_index)
        if player then trading_gui.handle_scale_button(player, scale_key) end
        return
    end

    if event.element.name == "otc_expand_buy_button" then
        local player = game.get_player(event.player_index)
        if not player then return end
        expand_gui.handle_buy_expansion(player)
    end
end)

script.on_event(defines.events.on_gui_selected_tab_changed, function(event)
    local player = game.get_player(event.player_index)
    if player then company_gui.handle_tab_changed(player, event.element) end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
    local unit_number, lane = string.match(event.element.name, "^otc_shape_config_item_(%d+)_(%a+)$")
    if unit_number then
        local player = game.get_player(event.player_index)
        if player then
            shape_config.handle_item_change(player, tonumber(unit_number), lane, event.element.elem_value)
        end
    end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local config_unit = string.match(event.element.name, "^otc_shape_config_role_(%d+)$")
    if config_unit then
        shape_config.handle_role_change(player, tonumber(config_unit), event.element.selected_index)
        return
    end
    if event.element.name == "otc_trading_force_dropdown" then
        local element = event.element
        local force_name = element.items and element.items[element.selected_index]
        if force_name then
            trading_gui.handle_force_change(player, force_name)
        end
        return
    end
    if event.element.name == "otc_company_nauvis_research" then
        company_gui.handle_research_selection(player, event.element)
        return
    end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    if event.element.name == "otc_place_clear" then
        shape_place.handle_clear_toggle(player, event.element.state)
        return
    end

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
