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

local function pole(x, y)
    return {
        valid = true,
        name = "big-electric-pole",
        type = "electric-pole",
        force = "Nauvis",
        position = { x = x, y = y },
    }
end

local BOX = { { 0, 0 }, { 9, 9 } }

describe("nauvis_siting.validate", function()
    local siting

    before_each(function()
        mock.setup {}
        package.loaded["scripts.nauvis_siting"] = nil
        siting = require("scripts.nauvis_siting")
        siting.init()
    end)

    after_each(function()
        mock.teardown()
    end)

    it("accepts empty ground", function()
        assert.is_true(siting.validate(make_surface {}, BOX))
    end)

    it("accepts ground nowhere near anything already built", function()
        -- Distance from the rest of the world used to be a rule, and the grid it
        -- produced is exactly what it was removed for.
        assert.is_true(siting.validate(make_surface { pole(-600, -600) }, BOX))
    end)

    it("ignores enemies, which no longer bear on a site", function()
        local surface = make_surface {
            { valid = true, name = "biter-spawner", type = "unit-spawner", force = "enemy",
                position = { x = 14, y = 5 } },
        }
        assert.is_true(siting.validate(surface, BOX))
    end)

    it("rejects a site with water in the footprint", function()
        local surface = make_surface({}, { { 4, 4 } })
        local ok, reason = siting.validate(surface, BOX)
        assert.is_false(ok)
        assert.is_truthy(string.find(reason, "water"))
    end)

    it("clears scenery rather than refusing it", function()
        local surface = make_surface {
            { valid = true, name = "tree-01", type = "tree", force = "neutral", position = { x = 3, y = 3 } },
            { valid = true, name = "rock-huge", type = "simple-entity", force = "neutral", position = { x = 5, y = 2 } },
        }
        assert.is_true(siting.validate(surface, BOX))
    end)

    it("rejects a building in the footprint", function()
        local surface = make_surface {
            { valid = true, name = "assembling-machine-1", type = "assembling-machine",
                force = "Nauvis", position = { x = 5, y = 5 } },
        }
        local ok, reason = siting.validate(surface, BOX)
        assert.is_false(ok)
        assert.is_truthy(string.find(reason, "assembling%-machine%-1"))
    end)

    it("rejects a player standing on the site", function()
        local surface = make_surface {
            { valid = true, name = "character", type = "character", force = "player",
                position = { x = 2, y = 2 } },
        }
        local ok, reason = siting.validate(surface, BOX)
        assert.is_false(ok)
        assert.is_truthy(string.find(reason, "standing"))
    end)
end)

-- The state and each company queue independently, so a request waiting on a
-- mayor must not block a company placing its own launch bay, and neither may
-- read the other's completion.
describe("nauvis_siting request clients", function()
    local siting

    local function player(index, force_name)
        return { index = index, force = { name = force_name }, surface = { name = "nauvis" } }
    end

    before_each(function()
        mock.setup {}
        _G.game.print = function() end
        _G.game.forces.Acme = { name = "Acme", print = function() end }
        _G.game.get_player = function(index) return { index = index, name = "P" .. index } end
        _G.storage.nauvis = { mayor = nil, bonds = {}, holdings = {} }
        package.loaded["scripts.nauvis_siting"] = nil
        siting = require("scripts.nauvis_siting")
        siting.init()
    end)

    after_each(function()
        mock.teardown()
    end)

    local function company_request()
        return siting.request {
            client = "company:Acme", shape = "orbital_station", label = "launch bay",
            force_name = "Acme", owned_by_force = true, sited_by = "Acme", border = "stone-path",
        }
    end

    it("keeps one request per client", function()
        assert.is_true(siting.request { shape = "solar_field", label = "Solar field", tag = "solar_field" })
        assert.is_true(company_request())
        assert.are.equal("solar_field", siting.pending().shape)
        assert.are.equal("orbital_station", siting.pending("company:Acme").shape)
        assert.are.equal(2, #siting.list())
    end)

    it("refuses a second request for the same client", function()
        assert.is_true(siting.request { shape = "solar_field", label = "Solar field" })
        assert.is_false(siting.request { shape = "nauvis_lab", label = "Lab district" })
        assert.are.equal("solar_field", siting.pending().shape)
    end)

    it("survives repeated state reads", function()
        -- `completed` is an empty table, not nil, so a migration keyed on the
        -- legacy fields being absent would wipe the requests on the next call.
        assert.is_true(company_request())
        siting.init()
        siting.pending()
        assert.is_not_nil(siting.pending("company:Acme"))
    end)

    it("migrates a save that carried a single request", function()
        _G.storage.nauvis_siting = { request = { shape = "solar_field", label = "Solar field" }, holder = 7 }
        package.loaded["scripts.nauvis_siting"] = nil
        local migrated = require("scripts.nauvis_siting")
        assert.are.equal("solar_field", migrated.pending().shape)
        assert.are.equal("nauvis", migrated.pending().client)
    end)

    it("lets the owning force site its own build, and nobody else", function()
        company_request()
        local request = siting.pending("company:Acme")
        assert.is_true(siting.can_site(player(1, "Acme"), request))
        assert.is_false(siting.can_site(player(2, "Other"), request))
    end)

    it("leaves a company build alone when a mayor is in office", function()
        company_request()
        _G.storage.nauvis.mayor = 9
        assert.is_true(siting.can_site(player(1, "Acme"), siting.pending("company:Acme")))
    end)

    it("still reserves the state's own works for the mayor", function()
        siting.request { shape = "solar_field", label = "Solar field" }
        _G.storage.nauvis.mayor = 9
        assert.is_true(siting.can_site(player(9, "Acme"), siting.pending()))
        assert.is_false(siting.can_site(player(1, "Acme"), siting.pending()))
        assert.is_nil(siting.reason_denied(player(9, "Acme")))
    end)

    it("hands each completion only to the client that asked", function()
        siting.request { shape = "solar_field", label = "Solar field", tag = "solar_field" }
        company_request()
        storage.nauvis_siting.completed["company:Acme"] = { tag = "launch bay" }
        assert.is_nil(siting.take_completed())
        assert.are.equal("launch bay", siting.take_completed("company:Acme").tag)
        assert.is_nil(siting.take_completed("company:Acme"))
    end)
end)

-- Siting used to lay a big pole on each corner of every footprint and refuse any
-- site out of wire reach of an existing one. Both are gone: the poles read as a
-- grid stamped over the landscape, and the reach rule is what forced every new
-- build to huddle against the last.
describe("nauvis_siting power", function()
    it("has no pole placement left to configure", function()
        mock.setup {}
        package.loaded["scripts.nauvis_siting"] = nil
        local siting = require("scripts.nauvis_siting")
        assert.is_nil(siting.pole_positions)
        assert.is_nil(siting.grid_link)
        mock.teardown()
    end)
end)
