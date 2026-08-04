local nauvis, stock

local function setup()
    _G.storage = {
        stock = { items = {} },
        players = {},
        prices = { ["iron-plate"] = 200, ["copper-plate"] = 300 },
    }
    package.loaded["scripts.stock"] = nil
    package.loaded["scripts.utils"] = nil
    package.loaded["scripts.nauvis"] = nil
    stock = require("scripts.stock")
    nauvis = require("scripts.nauvis")
    nauvis.init()
end

local function teardown()
    package.loaded["scripts.stock"] = nil
    package.loaded["scripts.utils"] = nil
    package.loaded["scripts.nauvis"] = nil
    _G.storage = nil
end

local function set_supply(amount)
    _G.storage.nauvis.minted = amount
    _G.storage.nauvis.burned = 0
end

local function give_player(index, credits, bonds)
    _G.storage.players[index] = { personal_credits = credits }
    _G.storage.nauvis.bonds[index] = bonds
end

describe("nauvis bonds", function()
    before_each(setup)
    after_each(teardown)

    it("values the world as the money supply plus the warehouse at base prices", function()
        set_supply(10000)
        stock.set("iron-plate", 50)
        stock.set("copper-plate", 10)
        assert.are.equal(10000 + 50 * 200 + 10 * 300, nauvis.total_value())
    end)

    it("prices an unheld item at the fallback rather than skipping it", function()
        set_supply(0)
        stock.set("unpriced-thing", 3)
        assert.are.equal(300, nauvis.total_value())
    end)

    it("scales the price with the bonds already held", function()
        set_supply(100000)
        give_player(1, 0, 1)
        give_player(2, 0, 4)
        assert.are.equal(4 * nauvis.bond_price(1), nauvis.bond_price(2))
    end)

    it("charges more for each successive bond despite the burn", function()
        set_supply(100000)
        give_player(1, 60000, 1)

        local previous = 0
        for _ = 1, 5 do
            local price = nauvis.bond_price(1)
            assert.is_true(price > previous,
                string.format("bond %d cost %d, which is not more than %d",
                    nauvis.get_bonds(1) + 1, price, previous))
            previous = price
            assert.is_true(nauvis.buy_bond(1))
        end
        assert.are.equal(6, nauvis.get_bonds(1))
    end)

    it("gets dearer as Nauvis's warehouse fills, not just as credits are minted", function()
        set_supply(10000)
        give_player(1, 0, 1)
        local empty = nauvis.bond_price(1)

        stock.set("copper-plate", 100)
        assert.are.equal(empty + math.floor(100 * 300 * 0.03 + 0.5), nauvis.bond_price(1))
    end)

    it("floors the price when the world is worth nothing", function()
        set_supply(0)
        give_player(1, 0, 1)
        assert.are.equal(100, nauvis.bond_price(1))
    end)

    it("floors the price when the money supply has gone negative", function()
        _G.storage.nauvis.minted = 0
        _G.storage.nauvis.burned = 50000
        give_player(1, 0, 1)
        assert.are.equal(100, nauvis.bond_price(1))
    end)

    it("debits the buyer, burns the price and issues the bond", function()
        set_supply(100000)
        give_player(1, 10000, 1)
        local price = nauvis.bond_price(1)

        local ok, charged = nauvis.buy_bond(1)
        assert.is_true(ok)
        assert.are.equal(price, charged)
        assert.are.equal(10000 - price, _G.storage.players[1].personal_credits)
        assert.are.equal(price, _G.storage.nauvis.burned)
        assert.are.equal(2, nauvis.get_bonds(1))
    end)

    it("refuses a purchase the buyer cannot afford", function()
        set_supply(100000)
        give_player(1, 10, 1)
        local ok = nauvis.buy_bond(1)
        assert.is_false(ok)
        assert.are.equal(1, nauvis.get_bonds(1))
        assert.are.equal(0, _G.storage.nauvis.burned)
    end)

    it("issues every player exactly one bond, once", function()
        nauvis.ensure_bonds(7)
        nauvis.add_bonds(7, 2)
        nauvis.ensure_bonds(7)
        assert.are.equal(3, nauvis.get_bonds(7))
    end)
end)
