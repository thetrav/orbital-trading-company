local DAY = 25000

local voting, printed, resolved, research_stub, expansion_stub

local function add_player(index, name)
    table.insert(_G.game.players, { index = index, name = name or ("player" .. index) })
end

local function give_bonds(index, count)
    _G.storage.nauvis.bonds[index] = count
end

local function setup()
    _G.storage = {
        nauvis = { minted = 0, burned = 0, holdings = {}, bonds = {} },
        players = {},
    }
    _G.game = {
        tick = 1000,
        players = {},
        surfaces = { nauvis = { ticks_per_day = DAY } },
        print = function(message) table.insert(printed, message) end,
    }
    _G.prototypes = { technology = {} }

    printed, resolved = {}, {}
    research_stub = {
        available = { "electronics", "logistics", "optics" },
        current = nil,
        pending = nil,
        get_available_technologies = function() return research_stub.available end,
        can_supply = function() return true end,
        current_research_name = function() return research_stub.current end,
        get_next_research = function() return research_stub.pending end,
        set_next_research = function(name)
            research_stub.pending = name
            table.insert(resolved, { kind = "research", key = name })
        end,
    }
    expansion_stub = {
        OPTIONS = {
            { key = "solar_field", label = "Solar field" },
            { key = "iron_mine", label = "Iron mine" },
            { key = "lab_district", label = "Lab district" },
        },
        current_target = nil,
        built_count = function() return 0 end,
        target = function() return expansion_stub.current_target end,
        set_target = function(key)
            expansion_stub.current_target = key
            table.insert(resolved, { kind = "expansion", key = key })
        end,
    }

    package.loaded["scripts.research"] = research_stub
    package.loaded["scripts.nauvis_expansion"] = expansion_stub
    package.loaded["scripts.nauvis"] = nil
    package.loaded["scripts.voting"] = nil
    voting = require("scripts.voting")
    voting.init()
end

local function teardown()
    package.loaded["scripts.research"] = nil
    package.loaded["scripts.nauvis_expansion"] = nil
    package.loaded["scripts.nauvis"] = nil
    package.loaded["scripts.voting"] = nil
    _G.game, _G.storage, _G.prototypes = nil, nil, nil
end

describe("voting", function()
    before_each(setup)
    after_each(teardown)

    it("runs a ballot for one day/night cycle", function()
        add_player(1)
        give_bonds(1, 1)
        assert.is_true(voting.open("expansion"))
        local ballot = voting.active("expansion")
        assert.are.equal(1000, ballot.start_tick)
        assert.are.equal(1000 + DAY, ballot.end_tick)
        assert.are.equal(1, #printed)
    end)

    it("refuses a second ballot of the same kind", function()
        add_player(1)
        give_bonds(1, 1)
        voting.open("expansion")
        local ok = voting.open("expansion")
        assert.is_false(ok)
    end)

    it("weights a vote by bonds held", function()
        add_player(1)
        add_player(2)
        give_bonds(1, 3)
        give_bonds(2, 1)
        voting.open("expansion")

        assert.is_true(voting.cast(1, "expansion", "iron_mine"))
        assert.is_true(voting.cast(2, "expansion", "solar_field"))

        local counts, cast = voting.tally("expansion")
        assert.are.equal(3, counts.iron_mine)
        assert.are.equal(1, counts.solar_field)
        assert.are.equal(0, counts.lab_district)
        assert.are.equal(4, cast)
    end)

    it("refuses a vote from someone holding no bonds", function()
        add_player(1)
        add_player(2)
        give_bonds(1, 1)
        voting.open("expansion")
        local ok = voting.cast(2, "expansion", "iron_mine")
        assert.is_false(ok)
    end)

    it("refuses an option that is not on the ballot", function()
        add_player(1)
        give_bonds(1, 1)
        voting.open("expansion")
        assert.is_false(voting.cast(1, "expansion", "not_a_thing"))
    end)

    it("is not decided while nobody has voted", function()
        add_player(1)
        give_bonds(1, 1)
        voting.open("expansion")
        assert.is_false(voting.decided_early("expansion"))
    end)

    it("is decided once every bond has been cast", function()
        add_player(1)
        give_bonds(1, 2)
        voting.open("expansion")
        voting.cast(1, "expansion", "iron_mine")
        assert.is_true(voting.decided_early("expansion"))
    end)

    it("is decided once the margin outruns the bonds still outstanding", function()
        add_player(1)
        add_player(2)
        add_player(3)
        give_bonds(1, 5)
        give_bonds(2, 1)
        give_bonds(3, 1)
        voting.open("expansion")
        voting.cast(1, "expansion", "iron_mine")
        assert.is_true(voting.decided_early("expansion"))
    end)

    it("is not decided while the outstanding bonds could still force a tie", function()
        add_player(1)
        add_player(2)
        give_bonds(1, 1)
        give_bonds(2, 1)
        voting.open("expansion")
        voting.cast(1, "expansion", "iron_mine")
        assert.is_false(voting.decided_early("expansion"))
    end)

    it("closes on the plurality and applies the result", function()
        add_player(1)
        add_player(2)
        give_bonds(1, 3)
        give_bonds(2, 1)
        voting.open("expansion")
        voting.cast(1, "expansion", "lab_district")
        voting.cast(2, "expansion", "solar_field")
        voting.close("expansion")

        assert.is_nil(voting.active("expansion"))
        assert.are.equal(1, #resolved)
        assert.are.equal("lab_district", resolved[1].key)
    end)

    it("draws a tie from the tied options only", function()
        add_player(1)
        add_player(2)
        give_bonds(1, 1)
        give_bonds(2, 1)
        voting.open("expansion")
        voting.cast(1, "expansion", "iron_mine")
        voting.cast(2, "expansion", "lab_district")
        voting.close("expansion")

        local key = resolved[1].key
        assert.is_true(key == "iron_mine" or key == "lab_district")
    end)

    it("draws at random when nobody voted", function()
        add_player(1)
        give_bonds(1, 1)
        voting.open("expansion")
        voting.close("expansion")

        assert.are.equal(1, #resolved)
        assert.is_not_nil(expansion_stub.target())
    end)

    it("warns once, a minute out, then closes at the deadline", function()
        add_player(1)
        add_player(2)
        give_bonds(1, 1)
        give_bonds(2, 1)
        expansion_stub.current_target = "solar_field"
        research_stub.current = "electronics"
        voting.open("mayor")

        _G.game.tick = 1000 + DAY - voting.WARNING_TICKS - 1
        voting.process()
        assert.is_false(voting.active("mayor").warned)

        _G.game.tick = 1000 + DAY - voting.WARNING_TICKS
        voting.process()
        assert.is_true(voting.active("mayor").warned)
        local warnings = #printed

        voting.process()
        assert.are.equal(warnings, #printed)

        _G.game.tick = 1000 + DAY
        voting.process()
        assert.is_nil(voting.active("mayor"))
    end)

    it("elects a mayor from the bondholders", function()
        add_player(1, "alpha")
        add_player(2, "beta")
        give_bonds(1, 1)
        give_bonds(2, 4)
        voting.open("mayor")
        voting.cast(2, "mayor", "2")
        voting.close("mayor")

        assert.are.equal(2, _G.storage.nauvis.mayor)
    end)

    it("opens the standing ballots when nothing is queued or being built", function()
        add_player(1)
        give_bonds(1, 1)
        voting.process()
        assert.is_not_nil(voting.active("research"))
        assert.is_not_nil(voting.active("expansion"))
    end)

    it("leaves the standing ballots shut while Nauvis is busy", function()
        add_player(1)
        give_bonds(1, 1)
        research_stub.current = "electronics"
        expansion_stub.current_target = "solar_field"
        voting.process()
        assert.is_nil(voting.active("research"))
        assert.is_nil(voting.active("expansion"))
    end)

    it("opens nothing before any player exists", function()
        voting.process()
        assert.is_nil(voting.active("research"))
        assert.is_nil(voting.active("expansion"))
    end)

    it("caps the research ballot at the cheapest few technologies", function()
        add_player(1)
        give_bonds(1, 1)
        research_stub.available = {}
        for index = 1, 20 do
            research_stub.available[index] = "tech-" .. index
        end
        voting.open("research")
        assert.are.equal(8, #voting.active("research").options)
        assert.are.equal("tech-1", voting.active("research").options[1].key)
    end)
end)
