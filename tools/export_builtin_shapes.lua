-- Renders the built-in shapes into the captured-shape data format under
-- scripts/shapes/.
--
--     lua tools/export_builtin_shapes.lua
--
-- Most are migrations of the generators that predate the capture tool, vendored
-- under tools/legacy_shapes/ so the conversion stays reproducible; a few (the
-- factory, the orbital station) are authored here instead. Everything is plain
-- Lua; no game API is used.
-- Entity positions are snapped exactly the way create_entity snaps them, using
-- tile sizes read from script-output/data-raw-dump.json (see ODD_SIZED below).

package.path = "./?.lua;" .. package.path

local shape_io = require("scripts.shape_io")

local direction = { north = 0, east = 4, south = 8, west = 12 }

-- Entities whose tile footprint is odd on that axis snap to tile centres;
-- even footprints snap to tile corners. Sourced from data-raw-dump.json.
local ODD_SIZED = {
    ["otc-platform-wall"] = true, ["gate"] = true, ["otc-gate-computer"] = true,
    ["otc-water-pump"] = true, ["rocket-silo"] = true, ["otc-teleporter"] = true,
    ["otc-trading-silo"] = true, ["constant-combinator"] = true,
    ["solar-panel"] = true, ["assembling-machine-1"] = true, ["lab"] = true,
    ["transport-belt"] = true, ["inserter"] = true, ["otc-supply-belt"] = true,
    ["otc-intake-belt"] = true, ["electric-mining-drill"] = true,
    ["otc-company-monitor"] = true,
    ["accumulator"] = false, ["substation"] = false,
}

local function snap(name, x, y)
    local odd = ODD_SIZED[name]
    if odd == nil then
        error("unknown entity footprint: " .. tostring(name))
    end
    if odd then
        return { math.floor(x) + 0.5, math.floor(y) + 0.5 }
    end
    return { math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function walls_to_entities(walls, out)
    out = out or {}
    local seen = {}
    for _, w in ipairs(walls) do
        local key = w[1] .. "," .. w[2]
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = { name = "otc-platform-wall", position = snap("otc-platform-wall", w[1], w[2]) }
        end
    end
    return out
end

local function platform_layer(tiles, correct)
    return { name = "otc-platform", correct = correct, tiles = tiles }
end

--- Split a list of {x, y, tile_name} triples into one layer per tile name,
--- preserving first-seen order so the applied layering matches the original.
local function layers_from_named_tiles(tiles, correct)
    local order, by_name = {}, {}
    for _, t in ipairs(tiles) do
        local name = t[3]
        if not by_name[name] then
            by_name[name] = {}
            order[#order + 1] = name
        end
        local bucket = by_name[name]
        bucket[#bucket + 1] = { t[1], t[2] }
    end
    local layers = {}
    for _, name in ipairs(order) do
        layers[#layers + 1] = { name = name, correct = correct, tiles = by_name[name] }
    end
    return layers
end

local function rect(x1, y1, x2, y2)
    local tiles = {}
    for x = x1, x2 do
        for y = y1, y2 do
            tiles[#tiles + 1] = { x, y }
        end
    end
    return tiles
end

local function gate_entity(x, y, side, extra)
    local e = {
        name = "gate",
        position = snap("gate", x, y),
        side = side,
        role = "gate",
        skip_create = true,
    }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

local function computer_entity(x, y, side)
    return {
        name = "otc-gate-computer",
        position = snap("otc-gate-computer", x, y),
        side = side,
        role = "computer",
        skip_create = true,
    }
end

local defs = {}

------------------------------------------------------------------ hub --------
do
    local hub = require("tools.legacy_shapes.hub")
    local tiles, walls = hub.get_positions(0, 0, "west", { x = -6, y = 0 })
    local entities = walls_to_entities(walls)
    for _, side in ipairs { "east", "west", "north", "south" } do
        local gx = (side == "east" and 6) or (side == "west" and -6) or 0
        local gy = (side == "north" and 6) or (side == "south" and -6) or 0
        entities[#entities + 1] = gate_entity(gx, gy, side)
        if side ~= "west" then
            local cdx = (side == "east" and 1) or (side == "west" and -1) or 0
            local cdy = (side == "north" and 1) or (side == "south" and -1) or 0
            entities[#entities + 1] = computer_entity(gx + cdx, gy + cdy, side)
        end
    end
    defs.hub = {
        format = 1,
        name = "hub",
        hook = "room_gates",
        connection = { position = { x = -6, y = 0 }, side = "west", gap = 3, connector = true },
        clearance_box = { { -7, -7 }, { 7, 7 } },
        tile_layers = { platform_layer(tiles, false) },
        entities = entities,
    }
end

-------------------------------------------------------------- corridor -------
do
    local corridor = require("tools.legacy_shapes.corridor")
    local tiles, walls = corridor.get_positions({ x = 0, y = 0 }, "east")
    local entities = walls_to_entities(walls)
    entities[#entities + 1] = gate_entity(3, 0, "west")
    entities[#entities + 1] = gate_entity(24, 0, "east")
    entities[#entities + 1] = computer_entity(25, 0, "east")
    defs.corridor = {
        format = 1,
        name = "corridor",
        hook = "room_gates",
        connection = { position = { x = 0, y = 0 }, side = "west", gap = 0, connector = false },
        clearance_box = { { 2, -2 }, { 25, 2 } },
        tile_layers = { platform_layer(tiles, false) },
        entities = entities,
    }
end

--------------------------------------------------------------- factory -------
-- Authored rather than migrated. The room used to be 32 tiles wide, which put
-- its gate half a tile off centre: a true rotation then landed the room one tile
-- across from where the old mirrored code put it. 33 tiles is symmetric about
-- the gate axis, so all four directions agree.
do
    local R = 16
    local tiles = rect(-R, -R, R, R)
    local walls = {}
    for y = -R, R do
        if y ~= 0 then walls[#walls + 1] = { -R, y } end
        walls[#walls + 1] = { R, y }
    end
    for x = -R + 1, R - 1 do
        walls[#walls + 1] = { x, -R }
        walls[#walls + 1] = { x, R }
    end

    -- Airlock stub outside the west wall, matching the hub's.
    for _, dy in ipairs { -1, 0, 1 } do
        tiles[#tiles + 1] = { -R - 1, dy }
        if dy ~= 0 then walls[#walls + 1] = { -R - 1, dy } end
    end

    local entities = walls_to_entities(walls)
    entities[#entities + 1] = gate_entity(-R, 0, "west")
    defs.factory = {
        format = 1,
        name = "factory",
        hook = "room_gates",
        connection = { position = { x = -R, y = 0 }, side = "west", gap = 3, connector = true },
        clearance_box = { { -R - 1, -R }, { R, R } },
        tile_layers = { platform_layer(tiles, false) },
        entities = entities,
    }
end

-------------------------------------------------------------- asteroids ------
local function asteroid_def(name, ore)
    local iron = require("tools.legacy_shapes.iron_asteroid")
    local tiles, resources, walls = iron.get_positions({ x = 0, y = 0 }, "east")
    local entities = walls_to_entities(walls)
    entities[#entities + 1] = gate_entity(3, 0, "east")
    local res = {}
    for _, r in ipairs(resources) do
        res[#res + 1] = { name = ore, position = { r[1], r[2] }, amount = r[4] }
    end
    return {
        format = 1,
        name = name,
        hook = "room_gates",
        connection = { position = { x = 0, y = 0 }, side = "west", gap = 0, connector = false },
        clearance_box = { { 2, -6 }, { 15, 6 } },
        -- The asteroid lays natural tiles over out-of-map, so every layer wants
        -- the transition correction pass.
        tile_layers = layers_from_named_tiles(tiles, true),
        entities = entities,
        resources = res,
    }
end
defs.iron_asteroid = asteroid_def("iron_asteroid", "iron-ore")
defs.copper_asteroid = asteroid_def("copper_asteroid", "copper-ore")

------------------------------------------------------ water_connection -------
do
    local water = require("tools.legacy_shapes.water_connection")
    local tiles, walls = water.get_positions(0, 0, "west", { x = -3, y = 0 })
    local entities = walls_to_entities(walls)
    entities[#entities + 1] = {
        name = "otc-water-pump",
        position = snap("otc-water-pump", 0, 0),
        direction = direction.east,
        role = "pump",
    }
    defs.water_connection = {
        format = 1,
        name = "water_connection",
        connection = { position = { x = -3, y = 0 }, side = "west", gap = 2, connector = true },
        clearance_box = { { -4, -4 }, { 4, 4 } },
        clear_area = true,
        tile_layers = { platform_layer(tiles, false) },
        entities = entities,
    }
end

------------------------------------------------------- orbital station -------
do
    local walls = {}
    for y = -7, 7 do
        if y ~= 0 then walls[#walls + 1] = { -7, y } end
        walls[#walls + 1] = { 7, y }
    end
    for x = -7, 7 do
        walls[#walls + 1] = { x, -7 }
        walls[#walls + 1] = { x, 7 }
    end
    local entities = walls_to_entities(walls)
    entities[#entities + 1] = gate_entity(-7, 0, "west")
    entities[#entities + 1] = {
        name = "rocket-silo",
        position = snap("rocket-silo", 0, 0),
        role = "silo",
    }
    entities[#entities + 1] = {
        name = "otc-teleporter",
        position = snap("otc-teleporter", -5, 0),
        direction = direction.north,
        role = "teleporter",
        skip_create = true,
    }
    defs.orbital_station = {
        format = 1,
        name = "orbital_station",
        hook = "orbital_station",
        connection = {
            position = { x = -7, y = 0 }, side = "west", gap = 2,
            connector = true, connector_correct = true,
        },
        clearance_box = { { -7, -7 }, { 7, 7 } },
        clear_area = true,
        tile_layers = {
            platform_layer(rect(-7, -7, 7, 7), true),
            { name = "concrete", correct = true, tiles = rect(-5, -5, 5, 5) },
            { name = "refined-hazard-concrete-left", correct = true, tiles = rect(-4, -4, 4, 4) },
        },
        entities = entities,
    }
end

--------------------------------------------- orbital station interior --------
do
    local walls = {}
    for y = -7, 7 do
        walls[#walls + 1] = { -7, y }
        walls[#walls + 1] = { 7, y }
    end
    for x = -7, 7 do
        walls[#walls + 1] = { x, -7 }
        if x ~= 0 then walls[#walls + 1] = { x, 7 } end
    end
    walls[#walls + 1] = { -1, 8 }
    walls[#walls + 1] = { 1, 8 }
    local entities = walls_to_entities(walls)
    entities[#entities + 1] = gate_entity(0, 7, "south")
    entities[#entities + 1] = computer_entity(0, 8, "south")
    entities[#entities + 1] = {
        name = "otc-trading-silo",
        position = snap("otc-trading-silo", 0, 0),
        role = "silo",
    }
    entities[#entities + 1] = {
        name = "otc-teleporter",
        position = snap("otc-teleporter", 0, 5),
        direction = direction.west,
        role = "return_teleporter",
        skip_create = true,
    }
    defs.station_interior = {
        format = 1,
        name = "station_interior",
        hook = "station_interior",
        destroy_decoratives = false,
        clearance_box = { { -7, -7 }, { 7, 8 } },
        tile_layers = {
            platform_layer(rect(-7, -7, 7, 7), false),
            { name = "refined-concrete", correct = false, tiles = rect(-1, 8, 1, 8) },
            { name = "concrete", correct = false, tiles = rect(-5, -5, 5, 5) },
            { name = "refined-hazard-concrete-left", correct = false, tiles = rect(-4, -4, 4, 4) },
        },
        entities = entities,
        anchors = {
            arrival = { position = { x = 0, y = 6 } },
        },
    }
end

--------------------------------------------------- nauvis starting room ------
do
    local R, WR = 5, 6
    local airlocks = {
        { gate = { 6, 0 }, computer = { 7, 0 } },
        { gate = { -6, 0 }, computer = { -7, 0 } },
        { gate = { 0, 6 }, computer = { 0, 7 } },
    }
    local function is_entity_position(x, y)
        for _, a in ipairs(airlocks) do
            if (a.gate[1] == x and a.gate[2] == y) or (a.computer[1] == x and a.computer[2] == y) then
                return true
            end
        end
        return false
    end

    local tiles, walls = {}, {}
    for x = -WR, WR do
        for y = -WR, WR do
            if (math.abs(x) <= R and math.abs(y) <= R) or math.abs(x) == WR or math.abs(y) == WR then
                tiles[#tiles + 1] = { x, y }
            end
            if (math.abs(x) == WR or math.abs(y) == WR) and not is_entity_position(x, y) then
                walls[#walls + 1] = { x, y }
            end
        end
    end
    local entities = walls_to_entities(walls)
    entities[#entities + 1] = {
        name = "otc-company-monitor",
        position = snap("otc-company-monitor", 4, 4),
        role = "company_monitor",
        skip_create = true,
    }
    defs.nauvis_starting_room = {
        format = 1,
        name = "nauvis_starting_room",
        hook = "starting_room",
        clear_area = true,
        clearance_box = { { -WR, -WR }, { WR, WR } },
        tile_layers = { platform_layer(tiles, true) },
        entities = entities,
        notes = {
            "Airlock gates and computers are placed by scripts/platform_gates.lua,",
            "not by this definition -- their tiles are left free of walls.",
        },
    }
end

------------------------------------------------ nauvis production room -------
do
    local ROOM = { left = -12, right = 12, top = -26, bottom = -10 }
    local tiles = rect(ROOM.left - 1, ROOM.top - 1, ROOM.right + 1, ROOM.bottom + 1)
    local walls = {}
    for x = ROOM.left - 1, ROOM.right + 1 do
        for y = ROOM.top - 1, ROOM.bottom + 1 do
            if x == ROOM.left - 1 or x == ROOM.right + 1 or y == ROOM.top - 1 or y == ROOM.bottom + 1 then
                walls[#walls + 1] = { x, y }
            end
        end
    end
    local entities = walls_to_entities(walls)

    local function add(name, x, y, extra)
        local e = { name = name, position = snap(name, x, y) }
        for k, v in pairs(extra or {}) do e[k] = v end
        entities[#entities + 1] = e
    end

    for _, x in ipairs { -11, -7, -3, 1, 5, 9 } do add("solar-panel", x, -25) end
    for _, x in ipairs { -11, -7 } do add("solar-panel", x, -22) end
    for _, x in ipairs { -4, -2, 0, 2, 4, 6, 8 } do add("accumulator", x + 1, -22) end
    for _, x in ipairs { -9, 0, 9 } do add("substation", x, -18) end

    add("assembling-machine-1", -3.5, -14.5, { recipe = "iron-gear-wheel" })
    add("assembling-machine-1", 0.5, -14.5, { recipe = "automation-science-pack" })
    add("lab", 0.5, -10.5, { role = "lab" })

    add("otc-supply-belt", -8, -15, { direction = direction.east, belt_type = "output" })
    add("transport-belt", -7, -15, { direction = direction.east, role = "supply", item = "iron-plate" })
    add("otc-supply-belt", 4, -15, { direction = direction.west, belt_type = "output" })
    add("transport-belt", 3, -15, { direction = direction.west, role = "supply", item = "copper-plate" })

    add("inserter", -6, -15, { direction = direction.west })
    add("inserter", -2, -15, { direction = direction.west })
    add("inserter", 2, -15, { direction = direction.east })
    add("inserter", 0, -13, { direction = direction.north })

    defs.nauvis_production_room = {
        format = 1,
        name = "nauvis_production_room",
        hook = "nauvis_production_room",
        clearance_box = { { ROOM.left - 1, ROOM.top - 1 }, { ROOM.right + 1, ROOM.bottom + 1 } },
        tile_layers = { platform_layer(tiles, true) },
        entities = entities,
        notes = {
            "Applied at world origin {0, 0}; coordinates are absolute Nauvis positions.",
            "role=supply transport belts are registered against their item by the hook.",
        },
    }
end

------------------------------------------------------- nauvis mine block -----
local function mine_block_def(name, ore)
    local SIZE = 8
    local left, top = 0, 0
    local right, bottom = SIZE - 1, SIZE - 1
    local ground = rect(left - 2, top - 2, right + 2, bottom + 10)

    local resources = {}
    for x = left, right do
        for y = top, bottom do
            resources[#resources + 1] = { name = ore, position = { x, y }, amount = 2000000000 }
        end
    end

    local entities = {}
    local function add(ename, x, y, extra)
        local e = { name = ename, position = snap(ename, x, y) }
        for k, v in pairs(extra or {}) do e[k] = v end
        entities[#entities + 1] = e
    end

    for _, offset in ipairs { 1, 5 } do
        add("electric-mining-drill", left + offset, top + 1,
            { direction = direction.south, role = "drill" })
        -- The drill's drop position is one tile below its southern edge.
        add("otc-intake-belt", left + offset, top + 3,
            { direction = direction.south, belt_type = "input", role = "intake" })
    end

    add("substation", right + 2, top + 1)
    add("substation", left - 1, bottom + 6)
    for _, row in ipairs { bottom + 3, bottom + 7 } do
        for _, offset in ipairs { 0, 3, 6 } do
            add("solar-panel", left + offset, row)
        end
    end
    for _, offset in ipairs { -1, 1, 3, 5, 7 } do
        add("accumulator", left + offset + 1, bottom + 10)
    end

    return {
        format = 1,
        name = name,
        hook = "nauvis_mine_block",
        clearance_box = { { left - 2, top - 2 }, { right + 2, bottom + 10 } },
        tile_layers = { { name = "grass-1", correct = true, tiles = ground } },
        entities = entities,
        resources = resources,
        notes = {
            "Applied at the block's world position; local {0, 0} is the ore patch corner.",
            "role=intake belts are registered as stock intakes by the hook.",
        },
    }
end
defs.nauvis_mine_iron = mine_block_def("nauvis_mine_iron", "iron-ore")
defs.nauvis_mine_copper = mine_block_def("nauvis_mine_copper", "copper-ore")
defs.nauvis_mine_coal = mine_block_def("nauvis_mine_coal", "coal")

--------------------------------------------------------------- write out -----
local names = {}
for name in pairs(defs) do names[#names + 1] = name end
table.sort(names)

for _, name in ipairs(names) do
    local path = "scripts/shapes/" .. name .. ".lua"
    local file = assert(io.open(path, "w"))
    file:write(shape_io.serialize(defs[name]))
    file:close()
    print("wrote " .. path)
end
