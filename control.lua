local PLATFORM_SIZE = 10
local PLATFORM_HALF = PLATFORM_SIZE / 2
local STARTING_CREDITS = 1000

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
