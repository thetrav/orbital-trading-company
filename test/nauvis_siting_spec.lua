local mock = require("test.factorio_mock")

-- A surface stand-in with just the two queries `validate` runs: everything in
-- the world is a flat list, filtered here the way the real API filters it.
local function make_surface(entities, water_tiles)
    return {
        name = "nauvis",
        entities = entities or {},
        find_entities_filtered = function(filter)
            local found = {}
            for _, entity in ipairs(entities or {}) do
                local ok = true
                if filter.area then
                    local x, y = entity.position.x, entity.position.y
                    ok = x >= filter.area[1][1] and x <= filter.area[2][1]
                        and y >= filter.area[1][2] and y <= filter.area[2][2]
                end
                if filter.position and filter.radius then
                    local dx = entity.position.x - filter.position.x
                    local dy = entity.position.y - filter.position.y
                    ok = ok and (dx * dx + dy * dy) <= filter.radius * filter.radius
                end
                if filter.type then ok = ok and entity.type == filter.type end
                if filter.force then ok = ok and entity.force == filter.force end
                if ok then found[#found + 1] = entity end
            end
            return found
        end,
        count_tiles_filtered = function(filter)
            local count = 0
            for _, tile in ipairs(water_tiles or {}) do
                if tile[1] >= filter.area[1][1] and tile[1] <= filter.area[2][1]
                    and tile[2] >= filter.area[1][2] and tile[2] <= filter.area[2][2] then
                    count = count + 1
                end
            end
            return count
        end,
    }
end

-- Wire reach is a getter on the real prototype, not a field, because 2.0 makes
-- it quality-dependent.
local function pole(x, y, reach)
    local distance = reach or 30
    return {
        valid = true,
        name = "big-electric-pole",
        type = "electric-pole",
        force = "Nauvis",
        position = { x = x, y = y },
        prototype = {
            get_max_wire_distance = function() return distance end,
            set_reach = function(value) distance = value end,
        },
    }
end

local BOX = { { 0, 0 }, { 9, 9 } }

describe("nauvis_siting.validate", function()
    local siting

    before_each(function()
        mock.setup {}
        _G.prototypes.entity = {
            ["big-electric-pole"] = { get_max_wire_distance = function() return 30 end },
        }
        package.loaded["scripts.nauvis_siting"] = nil
        siting = require("scripts.nauvis_siting")
        siting.init()
    end)

    after_each(function()
        mock.teardown()
    end)

    it("accepts empty ground in reach of the grid", function()
        local surface = make_surface { pole(-10, -10) }
        assert.is_true(siting.validate(surface, BOX))
    end)

    it("rejects a site with water in the footprint", function()
        local surface = make_surface({ pole(-10, -10) }, { { 4, 4 } })
        local ok, reason = siting.validate(surface, BOX)
        assert.is_false(ok)
        assert.is_truthy(string.find(reason, "water"))
    end)

    it("clears scenery rather than refusing it", function()
        local surface = make_surface {
            pole(-10, -10),
            { valid = true, name = "tree-01", type = "tree", force = "neutral", position = { x = 3, y = 3 } },
            { valid = true, name = "rock-huge", type = "simple-entity", force = "neutral", position = { x = 5, y = 2 } },
        }
        assert.is_true(siting.validate(surface, BOX))
    end)

    it("rejects a building in the footprint", function()
        local surface = make_surface {
            pole(-10, -10),
            { valid = true, name = "assembling-machine-1", type = "assembling-machine",
                force = "Nauvis", position = { x = 5, y = 5 } },
        }
        local ok, reason = siting.validate(surface, BOX)
        assert.is_false(ok)
        assert.is_truthy(string.find(reason, "assembling%-machine%-1"))
    end)

    it("rejects a player standing on the site", function()
        local surface = make_surface {
            pole(-10, -10),
            { valid = true, name = "character", type = "character", force = "player",
                position = { x = 2, y = 2 } },
        }
        local ok, reason = siting.validate(surface, BOX)
        assert.is_false(ok)
        assert.is_truthy(string.find(reason, "standing"))
    end)

    it("rejects a site near enemies even when the footprint itself is clear", function()
        local surface = make_surface {
            pole(-10, -10),
            { valid = true, name = "biter-spawner", type = "unit-spawner", force = "enemy",
                position = { x = 14, y = 5 } },
        }
        local ok, reason = siting.validate(surface, BOX)
        assert.is_false(ok)
        assert.is_truthy(string.find(reason, "enemy"))
    end)

    it("rejects a site out of the power grid's reach", function()
        local surface = make_surface { pole(-60, -60) }
        local ok, reason = siting.validate(surface, BOX)
        assert.is_false(ok)
        assert.is_truthy(string.find(reason, "power grid"))
    end)

    it("measures reach against the shorter of the two poles", function()
        -- A substation 25 tiles out is inside a big pole's 30 but outside its
        -- own 18, so it cannot be the link.
        local substation = pole(-24, -1, 18)
        substation.name = "substation"
        assert.is_false(siting.validate(make_surface { substation }, BOX))
        substation.prototype.set_reach(30)
        assert.is_true(siting.validate(make_surface { substation }, BOX))
    end)
end)

describe("nauvis_siting.pole_positions", function()
    it("puts a 2x2 pole clear of the footprint on every corner", function()
        mock.setup {}
        package.loaded["scripts.nauvis_siting"] = nil
        local siting = require("scripts.nauvis_siting")
        local positions = siting.pole_positions(BOX)
        assert.are.equal(4, #positions)
        for _, position in ipairs(positions) do
            -- Occupied tiles are (x-1, x) and (y-1, y): none may fall inside.
            local inside_x = position.x >= BOX[1][1] and position.x - 1 <= BOX[2][1]
            local inside_y = position.y >= BOX[1][2] and position.y - 1 <= BOX[2][2]
            assert.is_false(inside_x and inside_y)
        end
        mock.teardown()
    end)
end)
