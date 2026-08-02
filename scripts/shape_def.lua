local M = {}

M.FORMAT = 1

M.DIR_TO_STEPS = { east = 0, north = 1, west = 2, south = 3 }
M.STEPS_TO_DIR = { [0] = "east", [1] = "north", [2] = "west", [3] = "south" }
M.DIR_VECTOR = {
    east = { x = 1, y = 0 },
    west = { x = -1, y = 0 },
    north = { x = 0, y = 1 },
    south = { x = 0, y = -1 },
}
M.OPPOSITE = { east = "west", west = "east", north = "south", south = "north" }

M.DEFAULT_CORRECT_TILES = {
    ["otc-platform"] = false,
}

function M.correct_default(tile_name)
    local explicit = M.DEFAULT_CORRECT_TILES[tile_name]
    if explicit ~= nil then return explicit end
    return true
end

local function norm_steps(steps)
    return ((steps or 0) % 4 + 4) % 4
end

function M.steps_for_dir(dir)
    return M.DIR_TO_STEPS[dir or "east"] or 0
end

function M.rotate_point(x, y, steps)
    for _ = 1, norm_steps(steps) do
        x, y = -y, x
    end
    return x, y
end

function M.rotate_tile(x, y, steps)
    for _ = 1, norm_steps(steps) do
        x, y = -y - 1, x
    end
    return x, y
end

function M.rotate_direction(direction, steps)
    if direction == nil then return nil end
    return (direction + 4 * norm_steps(steps)) % 16
end

function M.rotate_side(side, steps)
    local base = M.DIR_TO_STEPS[side]
    if not base then return side end
    return M.STEPS_TO_DIR[(base + norm_steps(steps)) % 4]
end

--- World position that def-local {0,0} maps to, such that the def's connection
--- anchor sits `gap` tiles past `gate_pos` in direction `dir`.
function M.origin_for_gate(def, gate_pos, dir)
    local steps = M.steps_for_dir(dir)
    local conn = def.connection or { position = { x = 0, y = 0 }, gap = 0 }
    local gap = conn.gap or 0
    local vec = M.DIR_VECTOR[dir]
    if not vec then return nil end
    local cx, cy = M.rotate_tile(conn.position.x, conn.position.y, steps)
    return {
        x = gate_pos.x + vec.x * gap - cx,
        y = gate_pos.y + vec.y * gap - cy,
    }, steps
end

--- Materialise a def into world coordinates. Pure: no game API touched.
function M.transform(def, origin, steps)
    steps = norm_steps(steps)
    local ox, oy = origin.x, origin.y
    local out = {
        tile_layers = {},
        hidden_tiles = {},
        entities = {},
        resources = {},
        anchors = {},
    }

    local function place_tiles(src, dst)
        for _, layer in ipairs(src or {}) do
            local tiles = {}
            for _, t in ipairs(layer.tiles) do
                local x, y = M.rotate_tile(t[1], t[2], steps)
                tiles[#tiles + 1] = { ox + x, oy + y }
            end
            dst[#dst + 1] = {
                name = layer.name,
                correct = layer.correct,
                tiles = tiles,
            }
        end
    end
    place_tiles(def.tile_layers, out.tile_layers)
    place_tiles(def.hidden_tiles, out.hidden_tiles)

    for _, e in ipairs(def.entities or {}) do
        local x, y = M.rotate_point(e.position[1], e.position[2], steps)
        local copy = {}
        for k, v in pairs(e) do copy[k] = v end
        copy.position = { ox + x, oy + y }
        copy.direction = M.rotate_direction(e.direction, steps)
        if e.side then copy.side = M.rotate_side(e.side, steps) end
        out.entities[#out.entities + 1] = copy
    end

    for _, r in ipairs(def.resources or {}) do
        local x, y = M.rotate_tile(r.position[1], r.position[2], steps)
        out.resources[#out.resources + 1] = {
            name = r.name,
            position = { ox + x, oy + y },
            amount = r.amount,
        }
    end

    for name, a in pairs(def.anchors or {}) do
        local x, y = M.rotate_tile(a.position.x, a.position.y, steps)
        out.anchors[name] = {
            position = { x = ox + x, y = oy + y },
            side = a.side and M.rotate_side(a.side, steps) or nil,
        }
    end

    return out
end

--- Clearance box in world coordinates, as {{left, top}, {right, bottom}}.
function M.clearance_box(def, origin, steps)
    local box = def.clearance_box
    if not box then
        box = M.tile_bounds(def)
        if not box then return nil end
    end
    local x1, y1 = M.rotate_tile(box[1][1], box[1][2], steps)
    local x2, y2 = M.rotate_tile(box[2][1], box[2][2], steps)
    return {
        { origin.x + math.min(x1, x2), origin.y + math.min(y1, y2) },
        { origin.x + math.max(x1, x2), origin.y + math.max(y1, y2) },
    }
end

--- Inclusive tile extent of the def in local coordinates.
function M.tile_bounds(def)
    local left, top, right, bottom
    local function visit(x, y)
        if not left then
            left, top, right, bottom = x, y, x, y
            return
        end
        if x < left then left = x end
        if y < top then top = y end
        if x > right then right = x end
        if y > bottom then bottom = y end
    end
    for _, layer in ipairs(def.tile_layers or {}) do
        for _, t in ipairs(layer.tiles) do visit(t[1], t[2]) end
    end
    if not left then return nil end
    return { { left, top }, { right, bottom } }
end

local function fix(entity)
    if entity then
        entity.minable = false
        entity.destructible = false
    end
    return entity
end

function M.apply_tile_layers(surface, layers)
    for _, layer in ipairs(layers) do
        local tiles = {}
        for _, t in ipairs(layer.tiles) do
            tiles[#tiles + 1] = { name = layer.name, position = { t[1], t[2] } }
        end
        local correct = layer.correct
        if correct == nil then correct = M.correct_default(layer.name) end
        surface.set_tiles(tiles, correct)
    end
end

--- Build the def into the world. Returns a context table for hooks.
--- opts: force_name, extra_tile_layers, extra_entities, skip_existing_walls
function M.apply(surface, def, origin, steps, opts)
    opts = opts or {}
    local world = M.transform(def, origin, steps)
    local force_name = opts.force_name or "player"

    M.apply_tile_layers(surface, world.hidden_tiles)
    M.apply_tile_layers(surface, world.tile_layers)
    M.apply_tile_layers(surface, opts.extra_tile_layers or {})

    if def.destroy_decoratives ~= false then
        local box = M.clearance_box(def, origin, steps)
        if box then
            surface.destroy_decoratives { area = { { box[1][1], box[1][2] }, { box[2][1] + 1, box[2][2] + 1 } } }
        end
    end

    local ctx = {
        surface = surface,
        def = def,
        origin = origin,
        steps = steps,
        force_name = force_name,
        anchors = world.anchors,
        entities = {},
        roles = {},
    }

    -- Resources go down before entities: a mining drill binds to the ore under
    -- it when it is created, and reports no minable resources forever if the
    -- patch arrives afterwards.
    for _, r in ipairs(world.resources) do
        surface.create_entity {
            name = r.name,
            position = { r.position[1] + 0.5, r.position[2] + 0.5 },
            amount = r.amount,
        }
    end

    for _, e in ipairs(world.entities) do
        -- skip_create entities are described by the shape but built by its hook,
        -- because they need registering in storage as well as placing.
        local created
        if not e.skip_create then
            local resolved = opts.force_resolver and opts.force_resolver(e) or force_name
            created = M.create_entity(surface, e, resolved)
        end
        ctx.entities[#ctx.entities + 1] = { def = e, entity = created }
        if e.role then
            local bucket = ctx.roles[e.role]
            if not bucket then
                bucket = {}
                ctx.roles[e.role] = bucket
            end
            bucket[#bucket + 1] = { def = e, entity = created }
        end
    end

    return ctx
end

function M.create_entity(surface, e, force_name)
    if e.name == "otc-platform-wall" then
        local existing = surface.find_entity("otc-platform-wall", e.position)
        if existing then return existing end
    end
    local args = {
        name = e.name,
        position = e.position,
        force = e.force or force_name,
        create_build_effect_smoke = false,
    }
    if e.direction then args.direction = e.direction end
    if e.belt_type then args.type = e.belt_type end
    -- A supply belt hands items out; it is never an entrance, whatever an old
    -- capture happens to say.
    if e.name == "otc-supply-belt" then args.type = "output" end
    for key, value in pairs(e.create_args or {}) do
        args[key] = value
    end
    local created = surface.create_entity(args)
    if not created then return nil end
    if e.recipe then created.set_recipe(e.recipe) end
    if e.minable ~= true then fix(created) end
    return created
end

--- True when the clearance box is free of blocking entities.
function M.can_place(surface, def, origin, steps)
    local box = M.clearance_box(def, origin, steps)
    if not box then return false end
    local area = { { box[1][1], box[1][2] }, { box[2][1] + 1, box[2][2] + 1 } }
    for _, entity in ipairs(surface.find_entities_filtered { area = area }) do
        if entity.valid and entity.type ~= "item-on-ground" and entity.name ~= "tile-ghost" then
            return false
        end
    end
    return true
end

local TILE_GHOST = { r = 0, g = 0.1, b = 0.3, a = 0.12 }
local WALL_GHOST = { r = 0.9, g = 0.9, b = 1, a = 0.85 }
local RESOURCE_GHOST = { r = 0.8, g = 0.5, b = 0.2, a = 1 }

M.PREVIEW_TILE_TINT = {
    ["otc-platform"] = TILE_GHOST,
    concrete = { r = 0.5, g = 0.45, b = 0.4, a = 0.2 },
    ["refined-concrete"] = { r = 0.5, g = 0.45, b = 0.4, a = 0.2 },
    ["refined-hazard-concrete-left"] = { r = 0.45, g = 0.35, b = 0.2, a = 0.2 },
    ["dirt-7"] = { r = 0.4, g = 0.3, b = 0.2, a = 0.25 },
}

--- Ghost rendering of a def for a single player. Returns render objects.
function M.preview(surface, player, def, origin, steps, extra)
    local world = M.transform(def, origin, steps)
    local renderings = {}

    local function draw_tiles(layers)
        for _, layer in ipairs(layers) do
            local tint = M.PREVIEW_TILE_TINT[layer.name] or TILE_GHOST
            for _, t in ipairs(layer.tiles) do
                renderings[#renderings + 1] = rendering.draw_rectangle {
                    color = tint,
                    left_top = { t[1], t[2] + 1 },
                    right_bottom = { t[1] + 1, t[2] },
                    filled = true,
                    surface = surface,
                    players = { player },
                }
            end
        end
    end
    draw_tiles(world.tile_layers)
    draw_tiles((extra or {}).tile_layers or {})

    for _, r in ipairs(world.resources) do
        renderings[#renderings + 1] = rendering.draw_sprite {
            sprite = "entity/" .. r.name,
            tint = RESOURCE_GHOST,
            target = { position = { r.position[1] + 0.5, r.position[2] + 0.5 } },
            surface = surface,
            players = { player },
        }
    end

    for _, e in ipairs(world.entities) do
        if e.preview ~= false then
            renderings[#renderings + 1] = rendering.draw_sprite {
                sprite = "entity/" .. e.name,
                tint = WALL_GHOST,
                target = { position = { e.position[1], e.position[2] } },
                orientation = e.direction and (e.direction / 16) or nil,
                surface = surface,
                players = { player },
            }
        end
    end

    for _, e in ipairs((extra or {}).entities or {}) do
        renderings[#renderings + 1] = rendering.draw_sprite {
            sprite = "entity/" .. e.name,
            tint = WALL_GHOST,
            target = { position = { e.position[1], e.position[2] } },
            orientation = e.direction and (e.direction / 16) or nil,
            surface = surface,
            players = { player },
        }
    end

    return renderings
end

return M
