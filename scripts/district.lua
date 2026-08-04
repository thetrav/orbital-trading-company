local shape_def = require("scripts.shape_def")
local shape_registry = require("scripts.shape_registry")
local platform = require("scripts.platform")

local M = {}

-- Everything otc builds on Nauvis packs into one grid of **modules**. A module
-- is 22 x 20 and a sub-cell is a quarter of it, sized to the mine block, so
-- four mines share a module and everything larger takes one whole. Nothing is
-- asked to match exactly -- a shape that leaves slack in its cell just leaves
-- slack.
local SUB_W, SUB_H = 11, 10
local MODULE_W, MODULE_H = SUB_W * 2, SUB_H * 2
local MODULES_PER_ROW = 4

-- The gap between modules is two tiles: exactly the concrete path, and exactly
-- the pole standing on it. That makes the pitch 24 x 22.
local GUTTER = 2
local PITCH_X, PITCH_Y = MODULE_W + GUTTER, MODULE_H + GUTTER

-- Nauvis grows north from the compound, companies grow south. Row 0 of each
-- clears the compound walls with the path to spare.
local ZONES = {
    nauvis = { row0 = -21, heading = -1 },
    company = { row0 = 21, heading = 1 },
}

-- Power moves on big poles standing in the gutters, one at each corner of a
-- module. Corner to corner is 24 tiles across and 22 down, inside a big pole's
-- 30-tile wire reach, and every shape's own substation is inside its 18-tile
-- reach of a corner -- so nothing else is needed and no pole stands in a room.
local POLE = "big-electric-pole"
local PATH_TILE = "concrete"
local CLEARED_TYPES = { "tree", "simple-entity", "cliff", "fish" }

-- The ground under a module. Nauvis is a green world, so the district lays a
-- mix of its grasses rather than a slab: shapes that want something harder --
-- the flask factory and the lab both do -- lay their own floor on top.
local GRASS = { "grass-1", "grass-2", "grass-3", "grass-4" }
local GRASS_PATCH = 4
local HASH_MOD = 1048573

M.SUB_W, M.SUB_H = SUB_W, SUB_H
M.MODULE_W, M.MODULE_H = MODULE_W, MODULE_H

function M.init()
    local state = storage.district or {}
    -- The pre-module district numbered slots in rings and paved every one of
    -- them. Nothing of that survives; a save from before it starts over.
    if state.taken or state.next then
        state = {}
    end
    state.zones = state.zones or {}
    state.poles = state.poles or {}
    state.paths = state.paths or {}
    state.ground = state.ground or {}
    state.slots = state.slots or {}
    storage.district = state
    return state
end

local function state()
    return storage.district or M.init()
end

local function zone_state(name)
    local st = state()
    local zone = st.zones[name]
    if not zone then
        zone = { next = 0, open = {} }
        st.zones[name] = zone
    end
    return zone
end

--- Modules fill a row of MODULES_PER_ROW centred on the compound, then start a
--- new row further out. `zone` decides which way "further out" is.
function M.module_centre(n, zone_name)
    local zone = ZONES[zone_name or "nauvis"] or ZONES.nauvis
    local col = (n % MODULES_PER_ROW) - (MODULES_PER_ROW - 1) / 2
    local row = math.floor(n / MODULES_PER_ROW)
    return {
        x = col * PITCH_X,
        y = zone.row0 + zone.heading * row * PITCH_Y,
    }
end

--- How many sub-cells across and down a shape needs. A shape too big for a
--- whole module is still given one and allowed to overhang into the path.
function M.footprint(def)
    local box = def.clearance_box or shape_def.tile_bounds(def)
    if not box then return 1, 1 end
    local w = box[2][1] - box[1][1] + 1
    local h = box[2][2] - box[1][2] + 1
    return math.min(2, math.ceil(w / SUB_W)), math.min(2, math.ceil(h / SUB_H))
end

--- Centre of the `index`th sub-cell of the given size within a module.
function M.sub_centre(centre, cols, rows, index)
    local across = 2 / cols
    local w, h = cols * SUB_W, rows * SUB_H
    return {
        x = centre.x - MODULE_W / 2 + w * (index % across + 0.5),
        y = centre.y - MODULE_H / 2 + h * (math.floor(index / across) + 0.5),
    }
end

--- Take the next sub-cell that fits this shape. Each size keeps its own
--- part-filled module per zone, so mine blocks queue up four to a module
--- however many other things are built between them. `square` is for a shape
--- that will be rotated in its cell: the cell has to hold it either way round,
--- so it is claimed by the longer of its two sides.
function M.claim(def, zone_name, square)
    zone_name = zone_name or "nauvis"
    local zone = zone_state(zone_name)
    local cols, rows = M.footprint(def)
    if square then
        cols = math.max(cols, rows)
        rows = cols
    end
    local key = cols .. "x" .. rows
    local capacity = (2 / cols) * (2 / rows)

    local open = zone.open[key]
    if not open or open.used >= capacity then
        open = { module = zone.next, used = 0 }
        zone.next = zone.next + 1
        zone.open[key] = open
    end

    local index = open.used
    open.used = index + 1
    local centre = M.module_centre(open.module, zone_name)
    return M.sub_centre(centre, cols, rows, index), centre
end

--- Where a shape's origin goes for its clearance box to sit centred in a cell.
--- A shape as wide as its cell lands half a tile either way; rounding down puts
--- the overhang on the side the cell has, rather than out over the path.
function M.origin_for(def, centre, steps)
    local box = def.clearance_box or shape_def.tile_bounds(def)
    if not box then return { x = centre.x, y = centre.y } end
    local x1, y1 = shape_def.rotate_tile(box[1][1], box[1][2], steps or 0)
    local x2, y2 = shape_def.rotate_tile(box[2][1], box[2][2], steps or 0)
    return {
        x = math.floor(centre.x - (x1 + x2) / 2),
        y = math.floor(centre.y - (y1 + y2) / 2),
    }
end

--- Which way a shape's gate ends up pointing. The wall nearest `target` is the
--- one that gets the airlock: whichever axis the target is further along wins,
--- so a room out at the end of a row opens along the row and one straight out
--- from the compound opens back towards it.
local function dir_towards(centre, target)
    local dx, dy = target.x - centre.x, target.y - centre.y
    if math.abs(dx) >= math.abs(dy) then
        return dx >= 0 and "east" or "west"
    end
    -- The compass here is the codebase's y-flipped one: north is +y.
    return dy >= 0 and "north" or "south"
end

--- Quarter turns that swing a shape's gate round to face `target`.
function M.facing_steps(def, centre, target)
    local side = def.connection and def.connection.side
    if not side then
        for _, e in ipairs(def.entities or {}) do
            if e.role == "gate" and e.side then
                side = e.side
                break
            end
        end
    end
    if not side then return 0 end
    return (shape_def.steps_for_dir(dir_towards(centre, target))
        - shape_def.steps_for_dir(side)) % 4
end

--- Which grass a tile gets. Integer arithmetic against a prime modulus, so the
--- mix is the same on every peer -- a float hash could differ between platforms
--- and desync the moment a module is laid.
local function grass_at(x, y)
    local px = math.floor(x / GRASS_PATCH) % 4096
    local py = math.floor(y / GRASS_PATCH) % 4096
    local h = (px * 1021 + py * 3571 + 104729) % HASH_MOD
    h = (h * 8191) % HASH_MOD
    h = (h * 65537) % HASH_MOD
    return GRASS[h % #GRASS + 1]
end

local function box_of(centre, w, h)
    return centre.x - w / 2, centre.y - h / 2, centre.x + w / 2 - 1, centre.y + h / 2 - 1
end

local function clear_area(surface, area)
    for _, type_name in ipairs(CLEARED_TYPES) do
        for _, entity in ipairs(surface.find_entities_filtered { area = area, type = type_name }) do
            if entity.valid then entity.destroy() end
        end
    end
    surface.destroy_decoratives { area = area }
end

--- Lay a module's ground. Done once per module, before anything is built on it,
--- and it is what stops a cell that generated as a lake from drowning a shape.
local function lay_ground(surface, centre)
    local st = state()
    local key = centre.x .. "," .. centre.y
    if st.ground[key] then return end
    st.ground[key] = true

    local left, top, right, bottom = box_of(centre, MODULE_W, MODULE_H)
    clear_area(surface, { { left, top }, { right + 1, bottom + 1 } })
    local tiles = {}
    for x = left, right do
        for y = top, bottom do
            tiles[#tiles + 1] = { name = grass_at(x, y), position = { x, y } }
        end
    end
    surface.set_tiles(tiles)
end

--- The gutter round a module, as the inclusive tile bounds of the whole ring:
--- the module's own content sits GUTTER tiles inside it on every side. A module
--- shares each strip with its neighbour, which is why the ring is a gutter
--- wider than the pitch.
local function ring(centre)
    return centre.x - MODULE_W / 2 - GUTTER, centre.x + MODULE_W / 2 + GUTTER - 1,
        centre.y - MODULE_H / 2 - GUTTER, centre.y + MODULE_H / 2 + GUTTER - 1
end

function M.ring_box(centre)
    local left, right, top, bottom = ring(centre)
    return { { left, top }, { right, bottom } }
end

--- Lay the walkway the power line stands on: the whole gutter, all the way
--- round. Tiles already laid are skipped, so the edge a module shares with its
--- neighbour is paved once.
local function lay_path(surface, segments)
    local paths = state().paths
    local tiles = {}
    for _, segment in ipairs(segments) do
        clear_area(surface, { { segment[1][1], segment[1][2] },
            { segment[2][1] + 1, segment[2][2] + 1 } })
        for x = segment[1][1], segment[2][1] do
            for y = segment[1][2], segment[2][2] do
                local key = x .. "," .. y
                if not paths[key] then
                    paths[key] = true
                    tiles[#tiles + 1] = { name = PATH_TILE, position = { x, y } }
                end
            end
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles) end
end

--- Exported because a mayor-sited building is off the grid entirely and still
--- has to run its own corners into the same deduped pole list.
function M.ensure_pole(surface, x, y)
    local poles = state().poles
    local key = x .. "," .. y
    if poles[key] then return end
    poles[key] = true
    local pole = surface.create_entity {
        name = POLE,
        position = { x, y },
        force = "Nauvis",
        create_build_effect_smoke = false,
    }
    if pole then
        pole.minable = false
        pole.destructible = false
    end
end

--- Run the line round a module. Poles and path are both deduped, so a module
--- built next to one that already exists adds only the side that is new.
local function connect(surface, centre)
    local left, right, top, bottom = ring(centre)
    lay_path(surface, {
        { { left, top }, { left + GUTTER - 1, bottom } },
        { { right - GUTTER + 1, top }, { right, bottom } },
        { { left, top }, { right, top + GUTTER - 1 } },
        { { left, bottom - GUTTER + 1 }, { right, bottom } },
    })
    -- A 2x2 pole sits on the tile pair it is named after and the one before it,
    -- so these four stand squarely in the gutter strips laid above.
    for _, x in ipairs { left + GUTTER - 1, right } do
        for _, y in ipairs { top + GUTTER - 1, bottom } do
            M.ensure_pole(surface, x, y)
        end
    end
end

function M.chart(surface, centre, force)
    local box = M.ring_box(centre)
    local area = { { box[1][1] - 2, box[1][2] - 2 }, { box[2][1] + 2, box[2][2] + 2 } }
    if force then
        force.chart(surface, area)
        return
    end
    for _, f in pairs(game.forces) do
        f.chart(surface, area)
    end
end

--- Charts every module built so far, for a force that did not exist when they
--- went up.
function M.chart_all(surface, force)
    for _, slot in ipairs(state().slots) do
        M.chart(surface, { x = slot.module_x, y = slot.module_y }, force)
    end
end

--- Claim a cell, build the shape in it, and run the power line to it. `owner`
--- is the force the shape belongs to; the poles and the path always belong to
--- Nauvis, because the grid is state infrastructure everyone shares.
--- `opts.zone` picks which way the district grows: "nauvis" north, "company"
--- south. `opts.face_towards` is a world position the shape's gate should open
--- onto, which rotates the shape in its cell.
function M.build(surface, shape_name, owner, opts)
    local def = shape_registry.get(shape_name)
    if not def then
        log("district: unknown shape " .. tostring(shape_name))
        return nil
    end
    opts = opts or {}

    local centre, module_centre = M.claim(def, opts.zone, opts.face_towards ~= nil)
    lay_ground(surface, module_centre)

    local steps = opts.face_towards and M.facing_steps(def, centre, opts.face_towards) or 0
    local origin = M.origin_for(def, centre, steps)
    local ctx = platform.build_shape(surface, shape_name, origin, owner, {
        steps = steps,
        owned_by_force = opts.owned_by_force,
        context = opts.context,
    })
    connect(surface, module_centre)

    local st = state()
    st.slots[#st.slots + 1] = {
        x = centre.x,
        y = centre.y,
        module_x = module_centre.x,
        module_y = module_centre.y,
        shape = shape_name,
        owner = owner,
    }
    M.chart(surface, module_centre)
    return ctx, origin, centre
end

return M
