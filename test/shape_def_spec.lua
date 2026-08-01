local mock = require("test.factorio_mock")
local shape_def = require("scripts.shape_def")
local shape_runs = require("scripts.shape_runs")
local connector = require("scripts.shapes.connector")
local registry = require("scripts.shape_registry")

-- The pre-capture procedural generators, kept under tools/ so the migration
-- stays checkable. Every shape below must still produce what they produced.
local legacy = {
    hub = require("tools.legacy_shapes.hub"),
    corridor = require("tools.legacy_shapes.corridor"),
    iron_asteroid = require("tools.legacy_shapes.iron_asteroid"),
    water_connection = require("tools.legacy_shapes.water_connection"),
}

local DIRS = { "east", "west", "north", "south" }
local OPPOSITE = { east = "west", west = "east", north = "south", south = "north" }
local GATE = { x = 0, y = 0 }

local function key(x, y)
    return x .. "," .. y
end

local function set_of(list, transform)
    local set = {}
    for _, item in ipairs(list) do
        local x, y = transform(item)
        set[key(x, y)] = true
    end
    return set
end

local function count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local function difference(a, b)
    local only = {}
    for k in pairs(a) do
        if not b[k] then only[#only + 1] = k end
    end
    table.sort(only)
    return only
end

local function assert_same_set(expected, actual, label)
    assert.same({}, difference(expected, actual), label .. ": missing from new output")
    assert.same({}, difference(actual, expected), label .. ": extra in new output")
end

--- Everything the def + its connector lay down in the world, as coordinate sets.
local function built(shape, dir)
    local def = registry.get(shape)
    local origin, steps = shape_def.origin_for_gate(def, GATE, dir)
    local world = shape_def.transform(def, origin, steps)

    local tiles_by_name = {}
    for _, layer in ipairs(world.tile_layers) do
        tiles_by_name[layer.name] = tiles_by_name[layer.name] or {}
        for _, t in ipairs(layer.tiles) do
            tiles_by_name[layer.name][key(t[1], t[2])] = true
        end
    end

    local walls = {}
    for _, e in ipairs(world.entities) do
        if e.name == "otc-platform-wall" then
            walls[key(math.floor(e.position[1]), math.floor(e.position[2]))] = true
        end
    end

    local gap = def.connection and def.connection.connector ~= false and def.connection.gap or 0
    local ctiles, cwalls = connector.get_positions(GATE, dir, gap)
    for _, t in ipairs(ctiles) do
        tiles_by_name["otc-platform"] = tiles_by_name["otc-platform"] or {}
        tiles_by_name["otc-platform"][key(t[1], t[2])] = true
    end
    for _, w in ipairs(cwalls) do
        walls[key(w[1], w[2])] = true
    end

    local resources = {}
    for _, r in ipairs(world.resources) do
        resources[key(r.position[1], r.position[2])] = r.name
    end

    return {
        tiles = tiles_by_name,
        walls = walls,
        resources = resources,
        origin = origin,
        steps = steps,
        world = world,
    }
end

local function flat_tiles(built_result)
    local all = {}
    for _, set in pairs(built_result.tiles) do
        for k in pairs(set) do all[k] = true end
    end
    return all
end

describe("shape_runs", function()
    it("round-trips tile positions through run compression", function()
        local tiles = { { 1, 0 }, { 2, 0 }, { 3, 0 }, { 5, 0 }, { -1, 4 } }
        local expanded = shape_runs.expand(shape_runs.compress(tiles))
        assert_same_set(set_of(tiles, function(t) return t[1], t[2] end),
            set_of(expanded, function(t) return t[1], t[2] end), "runs")
    end)

    it("merges only contiguous runs", function()
        local runs = shape_runs.compress { { 1, 0 }, { 2, 0 }, { 4, 0 } }
        assert.equals(2, #runs)
    end)
end)

describe("shape_def rotation", function()
    before_each(function() mock.setup_defines() end)
    after_each(function() mock.teardown() end)

    it("returns to the identity after four quarter turns", function()
        for x = -3, 3 do
            for y = -3, 3 do
                local rx, ry = shape_def.rotate_tile(x, y, 4)
                assert.equals(x, rx)
                assert.equals(y, ry)
                local px, py = shape_def.rotate_point(x + 0.5, y + 0.5, 4)
                assert.equals(x + 0.5, px)
                assert.equals(y + 0.5, py)
            end
        end
    end)

    it("keeps a tile and its centre point in step", function()
        for steps = 0, 3 do
            local tx, ty = shape_def.rotate_tile(3, -5, steps)
            local px, py = shape_def.rotate_point(3.5, -4.5, steps)
            assert.equals(tx + 0.5, px)
            assert.equals(ty + 0.5, py)
        end
    end)

    it("rotates factorio directions a quarter turn at a time", function()
        assert.equals(defines.direction.south, shape_def.rotate_direction(defines.direction.east, 1))
        assert.equals(defines.direction.north, shape_def.rotate_direction(defines.direction.south, 2))
        assert.equals(defines.direction.east, shape_def.rotate_direction(defines.direction.east, 4))
    end)

    it("rotates sides along the codebase's y-flipped compass", function()
        assert.equals("north", shape_def.rotate_side("east", 1))
        assert.equals("west", shape_def.rotate_side("east", 2))
        assert.equals("east", shape_def.rotate_side("east", 4))
    end)
end)

describe("shape connections", function()
    it("lands each shape's connection anchor exactly gap tiles from the gate", function()
        for _, name in ipairs(registry.names()) do
            local def = registry.get(name)
            if def.connection then
                for _, dir in ipairs(DIRS) do
                    local origin, steps = shape_def.origin_for_gate(def, GATE, dir)
                    local ax, ay = shape_def.rotate_tile(def.connection.position.x, def.connection.position.y, steps)
                    local vec = shape_def.DIR_VECTOR[dir]
                    assert.equals(GATE.x + vec.x * def.connection.gap, origin.x + ax,
                        name .. " " .. dir .. " anchor x")
                    assert.equals(GATE.y + vec.y * def.connection.gap, origin.y + ay,
                        name .. " " .. dir .. " anchor y")
                end
            end
        end
    end)

    it("produces no connector tunnel for shapes that bake their own", function()
        for _, name in ipairs { "corridor", "iron_asteroid", "copper_asteroid" } do
            local def = registry.get(name)
            assert.is_false(def.connection.connector)
        end
    end)
end)

describe("captured shapes match the generators they replaced", function()
    it("hub", function()
        for _, dir in ipairs(DIRS) do
            local cx = (dir == "east" and 9) or (dir == "west" and -9) or 0
            local cy = (dir == "north" and 9) or (dir == "south" and -9) or 0
            local tiles, walls = legacy.hub.get_positions(cx, cy, OPPOSITE[dir], GATE)
            local result = built("hub", dir)
            assert_same_set(set_of(tiles, function(t) return t[1], t[2] end),
                flat_tiles(result), "hub " .. dir .. " tiles")
            assert_same_set(set_of(walls, function(w) return w[1], w[2] end),
                result.walls, "hub " .. dir .. " walls")
        end
    end)

    it("corridor", function()
        for _, dir in ipairs(DIRS) do
            local tiles, walls = legacy.corridor.get_positions(GATE, dir)
            local result = built("corridor", dir)
            assert_same_set(set_of(tiles, function(t) return t[1], t[2] end),
                flat_tiles(result), "corridor " .. dir .. " tiles")
            assert_same_set(set_of(walls, function(w) return w[1], w[2] end),
                result.walls, "corridor " .. dir .. " walls")
        end
    end)

    it("water_connection", function()
        for _, dir in ipairs(DIRS) do
            local cx = (dir == "east" and 5) or (dir == "west" and -5) or 0
            local cy = (dir == "north" and 5) or (dir == "south" and -5) or 0
            local tiles, walls = legacy.water_connection.get_positions(cx, cy, OPPOSITE[dir], GATE)
            local result = built("water_connection", dir)
            assert_same_set(set_of(tiles, function(t) return t[1], t[2] end),
                flat_tiles(result), "water " .. dir .. " tiles")
            assert_same_set(set_of(walls, function(w) return w[1], w[2] end),
                result.walls, "water " .. dir .. " walls")
        end
    end)

    it("iron and copper asteroids", function()
        for _, dir in ipairs(DIRS) do
            local tiles, resources, walls = legacy.iron_asteroid.get_positions(GATE, dir)
            local result = built("iron_asteroid", dir)
            assert_same_set(set_of(tiles, function(t) return t[1], t[2] end),
                flat_tiles(result), "asteroid " .. dir .. " tiles")
            assert_same_set(set_of(walls, function(w) return w[1], w[2] end),
                result.walls, "asteroid " .. dir .. " walls")

            for _, r in ipairs(resources) do
                assert.equals("iron-ore", result.resources[key(r[1], r[2])],
                    "asteroid " .. dir .. " ore at " .. key(r[1], r[2]))
            end
            assert.equals(#resources, count(result.resources))

            local copper = built("copper_asteroid", dir)
            for k, name in pairs(copper.resources) do
                assert.equals("copper-ore", name, "copper asteroid ore at " .. k)
            end
        end
    end)

    -- The factory is authored rather than migrated: it was widened from 32 to 33
    -- tiles so its gate sits on the centre line and rotation stops shifting it.
    it("factory is a square room with an airlock stub", function()
        local def = registry.get("factory")
        assert.same({ { -17, -16 }, { 16, 16 } }, shape_def.tile_bounds(def))

        local result = built("factory", "east")
        for _, dir in ipairs(DIRS) do
            local other = built("factory", dir)
            assert.equals(count(flat_tiles(result)), count(flat_tiles(other)),
                "factory " .. dir .. " tile count")
            assert.equals(count(result.walls), count(other.walls),
                "factory " .. dir .. " wall count")
        end
    end)
end)

describe("rooms sit square on the gate they were bought from", function()
    -- A room whose width across the connection axis is even puts its gate half a
    -- tile off centre, and rotating it then shifts the whole room sideways. Every
    -- shape must stay centred on the gate in all four directions.
    it("centres every shape across its connection axis", function()
        for _, name in ipairs(registry.names()) do
            local def = registry.get(name)
            if def.connection then
                for _, dir in ipairs(DIRS) do
                    local across_x = (dir == "north" or dir == "south")
                    local low, high
                    for k in pairs(flat_tiles(built(name, dir))) do
                        local x, y = k:match("^(-?%d+),(-?%d+)$")
                        local v = tonumber(across_x and x or y)
                        low = math.min(low or v, v)
                        high = math.max(high or v, v)
                    end
                    local gate_coord = across_x and GATE.x or GATE.y
                    assert.equals(gate_coord, (low + high) / 2,
                        name .. " " .. dir .. " is off centre (spans " .. low .. ".." .. high .. ")")
                end
            end
        end
    end)
end)

describe("shape definitions", function()
    it("declare a hook that exists", function()
        local hooks = {
            room_gates = true, orbital_station = true, station_interior = true,
            starting_room = true, nauvis_production_room = true, nauvis_mine_block = true,
        }
        for _, name in ipairs(registry.names()) do
            local def = registry.get(name)
            if def.hook then
                assert.is_true(hooks[def.hook] == true, name .. " names unknown hook " .. def.hook)
            end
        end
    end)

    it("give every gate a side so rotation can follow it", function()
        for _, name in ipairs(registry.names()) do
            for _, e in ipairs(registry.get(name).entities or {}) do
                if e.role == "gate" or e.role == "computer" then
                    assert.is_string(e.side, name .. " has a " .. e.role .. " without a side")
                end
            end
        end
    end)

    it("keep every entity on a valid placement grid", function()
        for _, name in ipairs(registry.names()) do
            for _, e in ipairs(registry.get(name).entities or {}) do
                local fx = e.position[1] % 0.5
                local fy = e.position[2] % 0.5
                assert.equals(0, fx, name .. " entity " .. e.name .. " has an off-grid x")
                assert.equals(0, fy, name .. " entity " .. e.name .. " has an off-grid y")
            end
        end
    end)
end)
