local mock = require("test.factorio_mock")
local shape_def = require("scripts.shape_def")
local registry = require("scripts.shape_registry")

--- Records the order of every world-building call shape_def.apply makes.
local function recording_surface()
    local surface = { name = "nauvis", calls = {} }

    function surface.set_tiles(tiles, correct)
        surface.calls[#surface.calls + 1] = {
            kind = "tiles", name = tiles[1] and tiles[1].name, count = #tiles, correct = correct,
        }
    end

    function surface.destroy_decoratives()
        surface.calls[#surface.calls + 1] = { kind = "decoratives" }
    end

    function surface.find_entity()
        return nil
    end

    function surface.create_entity(args)
        surface.calls[#surface.calls + 1] = {
            kind = args.amount and "resource" or "entity",
            name = args.name,
            position = args.position,
            direction = args.direction,
            force = args.force,
        }
        return {
            valid = true,
            name = args.name,
            position = args.position,
            unit_number = #surface.calls,
            set_recipe = function() end,
        }
    end

    return surface
end

local function kinds(surface)
    local out = {}
    for _, call in ipairs(surface.calls) do out[#out + 1] = call.kind end
    return out
end

local function first_index(surface, kind)
    for i, call in ipairs(surface.calls) do
        if call.kind == kind then return i end
    end
end

describe("shape_def.apply", function()
    before_each(function() mock.setup_defines() end)
    after_each(function() mock.teardown() end)

    it("lays ore before the drills that mine it", function()
        local surface = recording_surface()
        shape_def.apply(surface, registry.get("nauvis_mine_iron"), { x = -120, y = -4 }, 0,
            { force_name = "Nauvis" })

        local ore = first_index(surface, "resource")
        local entity = first_index(surface, "entity")
        assert.is_number(ore)
        assert.is_number(entity)
        assert.is_true(ore < entity,
            "resources must be created before entities; a drill built first finds nothing to mine")
    end)

    it("lays tiles before anything is built on them", function()
        local surface = recording_surface()
        shape_def.apply(surface, registry.get("nauvis_mine_iron"), { x = 0, y = 0 }, 0,
            { force_name = "Nauvis" })

        local order = kinds(surface)
        assert.equals("tiles", order[1])
        for i, kind in ipairs(order) do
            if kind == "tiles" then
                assert.is_true(i < (first_index(surface, "resource") or math.huge),
                    "tile layer applied after resources")
            end
        end
    end)

    it("applies each tile layer with the correction flag the shape asked for", function()
        local surface = recording_surface()
        shape_def.apply(surface, registry.get("orbital_station"), { x = 0, y = 0 }, 0,
            { force_name = "player" })

        local seen = {}
        for _, call in ipairs(surface.calls) do
            if call.kind == "tiles" then seen[call.name] = call.correct end
        end
        assert.is_true(seen["otc-platform"])
        assert.is_true(seen["concrete"])
        assert.is_true(seen["refined-hazard-concrete-left"])

        local hub = recording_surface()
        shape_def.apply(hub, registry.get("hub"), { x = 0, y = 0 }, 0, { force_name = "player" })
        for _, call in ipairs(hub.calls) do
            if call.kind == "tiles" then
                assert.is_false(call.correct, "otc-platform must not run tile correction")
            end
        end
    end)

    it("does not build the entities a hook is responsible for", function()
        local surface = recording_surface()
        local ctx = shape_def.apply(surface, registry.get("hub"), { x = 0, y = 0 }, 0,
            { force_name = "player" })

        for _, call in ipairs(surface.calls) do
            assert.is_not.equals("gate", call.name)
            assert.is_not.equals("otc-gate-computer", call.name)
        end
        assert.equals(4, #ctx.roles.gate)
        for _, entry in ipairs(ctx.roles.gate) do
            assert.is_nil(entry.entity)
        end
    end)

    it("routes each entity through the caller's force resolver", function()
        local surface = recording_surface()
        shape_def.apply(surface, registry.get("nauvis_production_room"), { x = 0, y = 0 }, 0, {
            force_name = "player",
            force_resolver = function() return "Nauvis" end,
        })

        for _, call in ipairs(surface.calls) do
            if call.kind == "entity" then
                assert.equals("Nauvis", call.force)
            end
        end
    end)
end)
