local platform_gates = require("scripts.platform_gates")
local room_builder = require("scripts.room_builder")
local shape_def = require("scripts.shape_def")
local shape_registry = require("scripts.shape_registry")
local shape_hooks = require("scripts.shape_hooks.init")
local connector = require("scripts.shapes.connector")
local nauvis_guard = require("scripts.nauvis_guard")

local M = {}

local function connector_gap(def)
    local conn = def.connection
    if not conn or conn.connector == false then return 0 end
    return conn.gap or 0
end

local function connector_extras(def, gate_pos, dir)
    local gap = connector_gap(def)
    if gap < 2 then return nil end
    local extras = connector.get_extras(gate_pos, dir, gap)
    local conn = def.connection
    if conn.connector_correct ~= nil then
        extras.tile_layers[1].correct = conn.connector_correct
    end
    return extras
end

--- Clearance box widened to cover the connector tunnel, in world coordinates.
local function full_box(def, origin, steps, gate_pos, dir)
    local box = shape_def.clearance_box(def, origin, steps)
    if not box then return nil end
    local gap = connector_gap(def)
    if gap >= 2 and gate_pos then
        local vec = shape_def.DIR_VECTOR[dir]
        for i = 1, gap - 1 do
            local x = gate_pos.x + vec.x * i
            local y = gate_pos.y + vec.y * i
            local wide = (vec.x ~= 0) and 1 or 0
            local tall = (vec.x ~= 0) and 0 or 1
            box[1][1] = math.min(box[1][1], x - tall)
            box[1][2] = math.min(box[1][2], y - wide)
            box[2][1] = math.max(box[2][1], x + tall)
            box[2][2] = math.max(box[2][2], y + wide)
        end
    end
    return box
end

--- Build a shape definition into the world and run its hook.
--- `extra` is merged into the hook context so callers can pass things a
--- definition cannot carry (a station name, a return teleport target).
function M.place_shape(surface, def, origin, steps, force_name, opts)
    opts = opts or {}

    local ctx = shape_def.apply(surface, def, origin, steps, {
        force_name = force_name,
        extra_tile_layers = opts.extra_tile_layers,
        force_resolver = function(entity)
            return room_builder.get_surface_force(surface, force_name, entity.role)
        end,
    })

    for _, wall in ipairs(opts.extra_walls or {}) do
        room_builder.place_wall(surface, wall, force_name)
    end

    for key, value in pairs(opts.context or {}) do
        ctx[key] = value
    end
    shape_hooks.run(def.hook, ctx)
    nauvis_guard.harden_shape(ctx)
    return ctx
end

--- Build a registered shape at a fixed world position with no rotation.
function M.build_shape(surface, shape_name, origin, force_name, opts)
    local def = shape_registry.get(shape_name)
    if not def then
        log("unknown shape: " .. tostring(shape_name))
        return nil
    end
    if def.clear_area then
        local box = shape_def.clearance_box(def, origin, 0)
        if box then room_builder.clear_area(surface, box) end
    end
    return M.place_shape(surface, def, origin, 0, force_name, opts)
end

function M.show_preview(surface, player, gate_pos, shape)
    local def = shape_registry.get(shape)
    if not def then return {} end

    local key = surface.name .. ":" .. gate_pos.x .. "," .. gate_pos.y
    local dir = platform_gates.get_gate_dir(key)
    if not dir then return {} end

    local origin, steps = shape_def.origin_for_gate(def, gate_pos, dir)
    if not origin then return {} end

    return shape_def.preview(surface, player, def, origin, steps, connector_extras(def, gate_pos, dir))
end

function M.clear_preview(objects)
    for _, obj in ipairs(objects) do
        if obj.valid then
            obj:destroy()
        end
    end
end

function M.expand_from_gate(surface, gate_pos, shape, force_name)
    shape = shape or "hub"
    force_name = force_name or "player"

    local def = shape_registry.get(shape)
    if not def then return false end

    local key = surface.name .. ":" .. gate_pos.x .. "," .. gate_pos.y
    local dir = platform_gates.get_gate_dir(key)
    if not dir then return false end

    local origin, steps = shape_def.origin_for_gate(def, gate_pos, dir)
    if not origin then return false end

    if def.clear_area then
        -- Clearing covers the connector too, since the tunnel has to be carved
        -- out of whatever is between the gate and the room.
        local box = full_box(def, origin, steps, gate_pos, dir)
        if not box then return false end
        room_builder.clear_area(surface, box)
    else
        -- The occupancy check covers only the room. The connector runs from the
        -- buying gate, so it always contains that gate's own computer.
        local box = shape_def.clearance_box(def, origin, steps)
        if not box then return false end
        local area = { { box[1][1], box[1][2] }, { box[2][1] + 1, box[2][2] + 1 } }
        for _, entity in ipairs(surface.find_entities_filtered { area = area }) do
            if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
                return false, "Not enough space!"
            end
        end
    end

    platform_gates.destroy_gate_control(key)

    local extras = connector_extras(def, gate_pos, dir)
    local extra_walls = {}
    if extras then
        for _, e in ipairs(extras.entities) do
            extra_walls[#extra_walls + 1] = { math.floor(e.position[1]), math.floor(e.position[2]) }
        end
    end

    M.place_shape(surface, def, origin, steps, force_name, {
        extra_tile_layers = extras and extras.tile_layers or nil,
        extra_walls = extra_walls,
        context = { gate_pos = gate_pos, gate_dir = dir },
    })

    return true
end

--- Where a teleporting player lands on an orbital station, from the station
--- shape's `arrival` anchor.
function M.station_arrival_position()
    local def = shape_registry.get("station_interior")
    local anchor = def and def.anchors and def.anchors.arrival
    if not anchor then return { 0, 6 } end
    return { anchor.position.x + 0.5, anchor.position.y + 0.5 }
end

M.is_nauvis = room_builder.is_nauvis
M.get_surface_force = room_builder.get_surface_force

return M
