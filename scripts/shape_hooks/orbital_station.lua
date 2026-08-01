local shape_def = require("scripts.shape_def")
local shape_registry = require("scripts.shape_registry")
local room_builder = require("scripts.room_builder")
local room_gates = require("scripts.shape_hooks.room_gates")
local station_interior = require("scripts.shape_hooks.station_interior")

local M = {}

local function new_station_surface(name)
    return game.create_surface(name, {
        peaceful_mode = true,
        width = 0,
        height = 0,
        starting_area = 0,
        terrain_segmentation = 0,
        water = 0,
        autoplace_controls = {},
        autoplace_settings = {
            tile = { settings = { ["out-of-map"] = {} }, treat_missing_as_default = false },
            decorative = { settings = {}, treat_missing_as_default = false },
            entity = { settings = {}, treat_missing_as_default = false },
        },
    })
end

--- The launch bay on Nauvis, plus the orbital surface it teleports to.
function M.run(ctx)
    room_gates.run(ctx)

    storage.otc_station_index = (storage.otc_station_index or 0) + 1
    local station_name = "otc-station-" .. storage.otc_station_index
    log("orbital_station: creating surface " .. station_name)

    local silo = (ctx.roles.silo or {})[1]
    if silo and silo.entity then
        storage.rocket_silos = storage.rocket_silos or {}
        storage.rocket_silos[silo.entity.unit_number] = station_name
    end

    local teleporter_entry = (ctx.roles.teleporter or {})[1]
    local teleporter
    if teleporter_entry then
        teleporter = ctx.surface.create_entity {
            name = teleporter_entry.def.name,
            position = teleporter_entry.def.position,
            direction = teleporter_entry.def.direction,
            force = room_builder.get_surface_force(ctx.surface, ctx.force_name, "teleporter"),
        }
        if teleporter then
            storage.otc_teleporters = storage.otc_teleporters or {}
            storage.otc_teleporters[teleporter.unit_number] = station_name
            teleporter_entry.entity = teleporter
        end
    end

    local station_surface = new_station_surface(station_name)
    storage.station_forces = storage.station_forces or {}
    storage.station_forces[station_name] = ctx.force_name
    log("orbital_station: surface created, requesting chunk generation")
    station_surface.request_to_generate_chunks({ 0, 0 }, 4)
    station_surface.force_generate_chunk_requests()
    log("orbital_station: chunk generation done, building platform")

    local return_target
    if teleporter then
        -- The return pad drops the player beside the launch teleporter, on the
        -- side that stays inside the room whichever way the bay is rotated.
        local dx, dy = shape_def.rotate_point(0, 1, ctx.steps)
        return_target = {
            surface = ctx.surface.name,
            position = { teleporter.position.x + dx, teleporter.position.y + dy },
        }
    end

    local interior = shape_registry.get("station_interior")
    local interior_ctx = shape_def.apply(station_surface, interior, { x = 0, y = 0 }, 0, {
        force_name = ctx.force_name,
    })
    interior_ctx.station_name = station_name
    interior_ctx.return_target = return_target
    station_interior.run(interior_ctx)

    ctx.station_name = station_name
    ctx.station_surface = station_surface
end

return M
