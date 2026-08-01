local shape_io = require("scripts.shape_io")
local registry = require("scripts.shape_registry")

local function tile_keys(layers)
    local out = {}
    for _, layer in ipairs(layers or {}) do
        local keys = {}
        for _, t in ipairs(layer.tiles) do
            keys[#keys + 1] = t[1] .. "," .. t[2]
        end
        table.sort(keys)
        out[#out + 1] = { name = layer.name, correct = layer.correct, tiles = keys }
    end
    return out
end

local function reload(def)
    local source = shape_io.serialize(def)
    local chunk, err = load(source, "@" .. (def.name or "shape") .. ".lua")
    assert(chunk, err)
    return chunk(), source
end

describe("shape_io", function()
    it("round-trips every captured shape without losing anything", function()
        for _, name in ipairs(registry.names()) do
            local def = registry.get(name)
            local copy = reload(def)

            assert.equals(def.name, copy.name, name .. " name")
            assert.equals(def.format, copy.format, name .. " format")
            assert.equals(def.hook, copy.hook, name .. " hook")
            assert.same(def.connection, copy.connection, name .. " connection")
            assert.same(def.clearance_box, copy.clearance_box, name .. " clearance box")
            assert.same(def.anchors, copy.anchors, name .. " anchors")
            assert.same(def.resources, copy.resources, name .. " resources")
            assert.same(def.entities, copy.entities, name .. " entities")
            assert.same(tile_keys(def.tile_layers), tile_keys(copy.tile_layers), name .. " tiles")
            assert.same(tile_keys(def.hidden_tiles), tile_keys(copy.hidden_tiles), name .. " hidden tiles")
        end
    end)

    it("keeps large resource amounts out of scientific notation", function()
        local def = {
            format = 1,
            name = "amounts",
            resources = { { name = "iron-ore", position = { 0, 0 }, amount = 2000000000 } },
        }
        local source = select(2, reload(def))
        assert.is_truthy(source:find("amount = 2000000000", 1, true))
    end)

    it("wraps entity rows that would otherwise run long", function()
        local def = {
            format = 1,
            name = "wrapping",
            entities = { {
                name = "a-very-long-entity-name-that-goes-on-and-on-and-on",
                position = { -123.5, -456.5 },
                direction = 12,
                role = "return_teleporter",
                recipe = "another-quite-long-recipe-name-here",
                skip_create = true,
            } },
        }
        local copy, source = reload(def)
        assert.same(def.entities, copy.entities)
        for line in source:gmatch("[^\n]+") do
            assert.is_true(#line <= 120, "line too long: " .. line)
        end
    end)
end)
