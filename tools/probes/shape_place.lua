-- Does placing the dummy marker entity turn into the real shape, centred so
-- that the footprint the player saw is the footprint they get?
local shape_place = require("scripts.shape_place")
local shape_registry = require("scripts.shape_registry")

local M = {}

local SHAPE = "red_flask_factory"
local WANT_ORIGIN = { x = 100, y = 100 }

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks(WANT_ORIGIN, 4)
    surface.force_generate_chunk_requests()
    shape_place.init()

    local marker_name = shape_place.MARKER_PREFIX .. SHAPE
    local proto = prototypes.entity[marker_name]
    if not proto then
        log("PROBE FAIL: no marker prototype " .. marker_name)
        return
    end
    log(string.format("PROBE marker %s tile=%dx%d", marker_name, proto.tile_width, proto.tile_height))
    log("PROBE item exists: " .. tostring(prototypes.item[shape_place.ITEM_PREFIX .. SHAPE] ~= nil))

    local layers = {}
    for layer in pairs(proto.collision_mask.layers or {}) do layers[#layers + 1] = layer end
    log("PROBE collision layers: " .. (next(layers) and table.concat(layers, ",") or "NONE"))

    -- The footprint highlight needs a non-empty mask, but placement must still
    -- never be blocked by whatever is already standing there.
    local blocker_at = { WANT_ORIGIN.x + 5.5, WANT_ORIGIN.y + 5.5 }
    surface.set_tiles { { name = "refined-concrete", position = { WANT_ORIGIN.x + 5, WANT_ORIGIN.y + 5 } } }
    local blocker = surface.create_entity {
        name = "steel-chest", position = blocker_at, force = "Nauvis",
    }
    log("PROBE blocker created: " .. tostring(blocker ~= nil))
    log("PROBE can place over blocker: " .. tostring(surface.can_place_entity {
        name = marker_name,
        position = { WANT_ORIGIN.x + proto.tile_width / 2, WANT_ORIGIN.y + proto.tile_height / 2 },
        force = "Nauvis",
    }))

    -- Place the marker so its footprint's top-left is exactly WANT_ORIGIN.
    local centre = {
        x = WANT_ORIGIN.x + proto.tile_width / 2,
        y = WANT_ORIGIN.y + proto.tile_height / 2,
    }
    local marker = surface.create_entity {
        name = marker_name, position = centre, force = "Nauvis",
    }
    if not marker then
        log("PROBE FAIL: could not create marker")
        return
    end

    local def = shape_registry.get(SHAPE)
    local computed = shape_place.origin_from_marker(def, centre)
    log(string.format("PROBE origin_from_marker -> %d,%d (want %d,%d)",
        computed.x, computed.y, WANT_ORIGIN.x, WANT_ORIGIN.y))

    local handled = shape_place.on_marker_built(marker, nil)
    log("PROBE handled=" .. tostring(handled) .. " marker_gone=" .. tostring(not marker.valid))

    -- The gear assembler sits at shape-local {18.5, 3.5}.
    local gear = surface.find_entity("assembling-machine-1",
        { WANT_ORIGIN.x + 18.5, WANT_ORIGIN.y + 3.5 })
    log("PROBE gear assembler at expected spot: " .. tostring(gear ~= nil)
        .. (gear and (" recipe=" .. tostring(gear.get_recipe() and gear.get_recipe().name)) or ""))

    local placed = surface.find_entities_filtered {
        area = {
            left_top = { x = WANT_ORIGIN.x - 1, y = WANT_ORIGIN.y - 1 },
            right_bottom = { x = WANT_ORIGIN.x + 23, y = WANT_ORIGIN.y + 15 },
        },
        name = "assembling-machine-1",
    }
    log("PROBE assemblers placed: " .. #placed)

    local supply, intake = 0, 0
    for _, data in pairs(storage.supply_belts or {}) do
        local e = data.entity
        if e and e.valid and e.position.x > WANT_ORIGIN.x then
            supply = supply + 1
            log(string.format("PROBE supply at %.1f,%.1f left=%s right=%s",
                e.position.x, e.position.y, tostring(data.left), tostring(data.right)))
        end
    end
    for _, data in pairs(storage.intake_belts or {}) do
        local e = data.entity
        if e and e.valid and e.position.x > WANT_ORIGIN.x then intake = intake + 1 end
    end
    log("PROBE registered supply=" .. supply .. " intake=" .. intake)

    -- The click path itself cannot be probed: on_built_entity is not raisable
    -- through script, and a headless --create map has no player to click with.
    -- What that path depends on is the event field name, which the shipped API
    -- definitions settle -- EventData.on_built_entity has `entity`, and no
    -- `created_entity` at all.
end

return M
