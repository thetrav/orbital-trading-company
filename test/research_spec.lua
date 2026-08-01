local mock = require("test.factorio_mock")

local function load_research()
    package.loaded["scripts.research"] = nil
    package.loaded["scripts.nauvis"] = nil
    return require("scripts.research")
end

describe("research frontier", function()
    after_each(function()
        mock.teardown()
    end)

    it("lists technologies whose prerequisites are all researched", function()
        mock.setup {
            ["electronics"] = { researched = true },
            ["logistics"] = {},
            ["military"] = {},
            ["logistics-2"] = { prerequisites = { "logistics" } },
        }
        local research = load_research()

        local available = research.get_available_technologies()
        local names = {}
        for _, name in ipairs(available) do names[name] = true end

        assert.is_true(names["logistics"])
        assert.is_true(names["military"])
        assert.is_nil(names["electronics"], "already researched should be excluded")
        assert.is_nil(names["logistics-2"], "unmet prerequisite should be excluded")
    end)

    it("is not empty at game start when only the trigger techs are researched", function()
        mock.setup {
            ["steam-power"] = { researched = true },
            ["electronics"] = { researched = true },
            ["automation-science-pack"] = { researched = true },
            ["logistics"] = {},
            ["stone-wall"] = {},
            ["military"] = {},
        }
        local research = load_research()

        assert.is_true(#research.get_available_technologies() > 0)
    end)

    it("excludes trigger technologies, which a lab cannot research", function()
        mock.setup {
            ["logistics"] = {},
            ["steel-axe"] = { ingredients = {} },
        }
        local research = load_research()

        local names = {}
        for _, name in ipairs(research.get_available_technologies()) do names[name] = true end

        assert.is_true(names["logistics"])
        assert.is_nil(names["steel-axe"], "trigger techs have no research units")
    end)

    it("orders the frontier cheapest first", function()
        mock.setup {
            ["expensive"] = { unit_count = 500, unit_energy = 60 },
            ["cheap"] = { unit_count = 10, unit_energy = 5 },
            ["middling"] = { unit_count = 100, unit_energy = 30 },
        }
        local research = load_research()

        assert.are.same({ "cheap", "middling", "expensive" }, research.get_available_technologies())
    end)
end)

describe("nauvis research selection", function()
    after_each(function()
        mock.teardown()
    end)

    it("starts idle rather than auto-picking a technology", function()
        local force = mock.setup {
            ["logistics"] = {},
            ["military"] = {},
        }
        local research = load_research()
        research.init()

        assert.is_nil(force.current_research)
        assert.is_nil(research.current_research_name())
    end)

    it("starts researching what a player applies", function()
        local force = mock.setup { ["logistics"] = {} }
        local research = load_research()
        research.init()

        local ok = research.set_next_research("logistics")

        assert.is_true(ok)
        assert.are.equal("logistics", research.current_research_name())
        assert.are.equal("logistics", force.current_research.name)
    end)

    it("queues a choice as next while something is already researching", function()
        local force = mock.setup {
            ["logistics"] = {},
            ["military"] = {},
        }
        local research = load_research()
        research.init()
        research.set_next_research("logistics")

        research.set_next_research("military")

        assert.are.equal("logistics", research.current_research_name(), "current is untouched")
        assert.are.equal("military", research.get_next_research())

        force.current_research = nil
        force.technologies["logistics"].researched = true
        research.start_pending_research()

        assert.are.equal("military", research.current_research_name())
        assert.is_nil(research.get_next_research(), "pending is consumed once started")
    end)

    it("refuses a technology whose prerequisites are unmet", function()
        mock.setup {
            ["logistics"] = {},
            ["logistics-2"] = { prerequisites = { "logistics" } },
        }
        local research = load_research()
        research.init()

        local ok, err = research.set_next_research("logistics-2")

        assert.is_false(ok)
        assert.is_string(err)
        assert.is_nil(research.current_research_name())
    end)

    it("refuses an already-researched technology", function()
        mock.setup { ["logistics"] = { researched = true } }
        local research = load_research()
        research.init()

        local ok = research.set_next_research("logistics")

        assert.is_false(ok)
    end)

    it("reports whether nauvis can supply a technology's packs", function()
        mock.setup {
            ["logistics"] = {},
            ["logistics-2"] = { ingredients = {
                { name = "automation-science-pack", amount = 1 },
                { name = "logistic-science-pack", amount = 1 },
            } },
        }
        local research = load_research()

        assert.is_true(research.can_supply("logistics"))
        assert.is_false(research.can_supply("logistics-2"), "nauvis makes only red science")
    end)
end)
