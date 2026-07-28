local PLATFORM_SIZE = 10
local PLATFORM_HALF = PLATFORM_SIZE / 2
local STARTING_CREDITS = 1000
local BUY_CHEST_NAME = "otc-buy-chest"
local COMBINATOR_NAME = "constant-combinator"
local BUY_CHEST_POSITION = { x = -4, y = 0 }
local COMBINATOR_POSITION = { x = -4, y = -1 }

local function is_in_platform(x, y)
    return x >= -PLATFORM_HALF and x < PLATFORM_HALF
       and y >= -PLATFORM_HALF and y < PLATFORM_HALF
end

local function build_platform(surface, area)
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local tile_name = is_in_platform(x, y) and "concrete" or "out-of-map"
            table.insert(tiles, {name = tile_name, position = {x, y}})
        end
    end
    surface.set_tiles(tiles, true)
end

local function format_credits(amount)
    local formatted = tostring(amount)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function create_credits_gui(player)
    if player.gui.screen.otc_credits_frame then
        player.gui.screen.otc_credits_frame.destroy()
    end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_credits_frame",
        direction = "vertical",
    }
    frame.style.size = {120, 70}
    frame.style.padding = 4
    frame.style.bottom_padding = 8

    local title_flow = frame.add {
        type = "flow",
        name = "title_flow",
        direction = "horizontal",
    }
    title_flow.style.vertical_align = "center"
    title_flow.drag_target = frame

    title_flow.add {
        type = "label",
        style = "frame_title",
        caption = "Credits",
        ignored_by_interaction = true,
    }

    local drag = title_flow.add {
        type = "empty-widget",
        style = "draggable_space",
        ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.horizontally_stretchable = true

    local player_data = storage.players and storage.players[player.index]
    local credits = player_data and player_data.credits or STARTING_CREDITS
    local label = frame.add {
        type = "label",
        name = "otc_credits_label",
        caption = format_credits(credits),
    }
    label.style.font = "default-listbox"
    label.style.horizontal_align = "center"
    label.style.horizontally_stretchable = true

    return frame
end

local function init_player(player)
    storage.players = storage.players or {}
    if not storage.players[player.index] then
        storage.players[player.index] = { credits = STARTING_CREDITS }
    end
    create_credits_gui(player)
end

local function update_credits_gui(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    local frame = player.gui.screen.otc_credits_frame
    if not frame then return end
    local label = frame.otc_credits_label
    if not label then return end
    local player_data = storage.players and storage.players[player_index]
    local credits = player_data and player_data.credits or 0
    label.caption = format_credits(credits)
end

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

local function register_buy_chest(entity)
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

local function unregister_buy_chest(unit_number)
    if not storage.buy_chests then return end
    storage.buy_chests[unit_number] = nil
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

local function process_buy_chests()
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
                    local current = inventory.get_item_count(item_name)
                    local deficit = desired - current

                    if deficit > 0 then
                        local player = game.connected_players[1]
                        if player then
                            local player_data = storage.players and storage.players[player.index]
                            if player_data then
                                local can_afford = math.min(deficit, player_data.credits)
                                if can_afford > 0 then
                                    local inserted = inventory.insert({ name = item_name, count = can_afford })
                                    if inserted > 0 then
                                        player_data.credits = player_data.credits - inserted
                                        update_credits_gui(player.index)
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

script.on_init(function()
    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_skip_intro", true)
        remote.call("freeplay", "set_disable_crashsite", true)
    end

    storage.players = {}

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
    build_platform(surface, {
        left_top = {x = -radius, y = -radius},
        right_bottom = {x = radius, y = radius}
    })

    for _, player in pairs(game.connected_players) do
        player.teleport({0.5, 0.5}, surface)
        init_player(player)
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
        register_buy_chest(chest)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    init_player(player)
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player and not player.gui.screen.otc_credits_frame then
        init_player(player)
    end
end)

script.on_event(defines.events.on_chunk_generated, function(event)
    if event.surface.index ~= 1 then return end
    build_platform(event.surface, event.area)
end)

script.on_nth_tick(1, function()
    process_buy_chests()
end)

script.on_event(defines.events.on_built_entity, function(event)
    register_buy_chest(event.created_entity)
end)

script.on_event(defines.events.on_entity_died, function(event)
    if event.entity.name == BUY_CHEST_NAME then
        unregister_buy_chest(event.entity.unit_number)
    end
end)

script.on_event(defines.events.on_player_mined_entity, function(event)
    if event.entity.name == BUY_CHEST_NAME then
        unregister_buy_chest(event.entity.unit_number)
    end
end)
