local PLATFORM_SIZE = 10
local PLATFORM_HALF = PLATFORM_SIZE / 2

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

script.on_init(function()
    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_skip_intro", true)
        remote.call("freeplay", "set_disable_crashsite", true)
    end

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
    end
end)

script.on_event(defines.events.on_chunk_generated, function(event)
    if event.surface.index ~= 1 then return end
    build_platform(event.surface, event.area)
end)
