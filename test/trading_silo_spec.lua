local mock = require("test.factorio_mock")

local GREEN = 3
local RED = 4

local function make_inventory(capacity)
    local inv = { items = {}, held = 0, capacity = capacity or 10000 }
    inv.get_item_count = function(name) return inv.items[name] or 0 end
    inv.insert = function(stack)
        local room = inv.capacity - inv.held
        local count = math.min(stack.count, room)
        if count <= 0 then return 0 end
        inv.items[stack.name] = (inv.items[stack.name] or 0) + count
        inv.held = inv.held + count
        return count
    end
    inv.remove = function(stack)
        local count = math.min(inv.items[stack.name] or 0, stack.count)
        if count <= 0 then return 0 end
        inv.items[stack.name] = inv.items[stack.name] - count
        inv.held = inv.held - count
        return count
    end
    return inv
end

local function setup_globals()
    _G.game = { forces = {}, connected_players = {}, players = {} }
    _G.storage = {}
    _G.defines = {
        inventory = { chest = 1 },
        wire_connector_id = { circuit_green = GREEN, circuit_red = RED },
        input_action = { start_research = 1, cancel_research = 2, move_research = 3 },
    }
    _G.prototypes = { item = {} }
    for _, name in ipairs({ "iron-ore", "copper-ore", "stone" }) do
        _G.prototypes.item[name] = {
            name = name,
            type = "item",
            subgroup = { name = "raw-resource" },
        }
    end
end

local function load_modules()
    for _, name in ipairs({
        "scripts.trading_silo", "scripts.utils", "scripts.stock", "scripts.nauvis",
        "scripts.supply_demand", "scripts.trading_history", "scripts.item_filter",
        "scripts.research",
    }) do
        package.loaded[name] = nil
    end
    local trading_silo = require("scripts.trading_silo")
    require("scripts.stock").init()
    require("scripts.nauvis").init()
    require("scripts.supply_demand").init()
    require("scripts.trading_history").init()
    trading_silo.init()
    return trading_silo, require("scripts.stock")
end

--- A silo owned by a company with `credits`, holding `inventory`, wired to
--- `signals` (a wire connector id -> signal list table).
local function make_silo(trading_silo, opts)
    opts = opts or {}
    local force = { name = "Acme", recipes = {} }
    _G.game.forces["Acme"] = force
    storage.companies = { Acme = { credits = opts.credits or 1000000 } }

    local inventory = make_inventory(opts.capacity)
    local signals = opts.signals or {}
    local entity = {
        valid = true,
        name = "otc-trading-silo",
        unit_number = 1,
        force = force,
        get_inventory = function() return inventory end,
        get_circuit_network = function(connector)
            if not signals[connector] then return nil end
            return { signals = signals[connector] }
        end,
    }

    local data = trading_silo.register(entity)
    return data, inventory
end

local function signal(name, count)
    return { signal = { type = "item", name = name }, count = count }
end

describe("trading silo", function()
    local trading_silo, stock

    before_each(function()
        setup_globals()
        trading_silo, stock = load_modules()
        -- A stocked warehouse floors every price at 1 credit, which keeps the
        -- credit arithmetic in these specs readable.
        storage.prices = { ["iron-ore"] = 100, ["copper-ore"] = 100, ["stone"] = 100 }
        stock.set("iron-ore", 1000000)
        stock.set("copper-ore", 1000000)
        stock.set("stone", 1000000)
    end)

    after_each(function()
        mock.teardown()
    end)

    it("buys up to the maintained quantity and then stops", function()
        local data, inventory = make_silo(trading_silo)
        trading_silo.add_buy(data, "iron-ore", 10)

        trading_silo.process()
        assert.equals(10, inventory.get_item_count("iron-ore"))
        assert.equals(1000000 - 10, storage.companies.Acme.credits)

        trading_silo.process()
        assert.equals(10, inventory.get_item_count("iron-ore"))
        assert.equals(1000000 - 10, storage.companies.Acme.credits)
    end)

    it("tops up again after a withdrawal", function()
        local data, inventory = make_silo(trading_silo)
        trading_silo.add_buy(data, "iron-ore", 10)
        trading_silo.process()

        inventory.remove({ name = "iron-ore", count = 4 })
        trading_silo.process()

        assert.equals(10, inventory.get_item_count("iron-ore"))
    end)

    it("buys only what the company can afford", function()
        local data, inventory = make_silo(trading_silo, { credits = 5 })
        trading_silo.add_buy(data, "iron-ore", 100)

        trading_silo.process()

        assert.equals(5, inventory.get_item_count("iron-ore"))
        assert.equals(0, storage.companies.Acme.credits)
    end)

    it("buys only what Nauvis holds", function()
        stock.set("stone", 3)
        local data, inventory = make_silo(trading_silo)
        trading_silo.add_buy(data, "stone", 100)

        trading_silo.process()

        assert.equals(3, inventory.get_item_count("stone"))
        assert.equals(0, stock.get("stone"))
    end)

    it("buys only what fits, and pays for no more", function()
        local data, inventory = make_silo(trading_silo, { capacity = 7 })
        trading_silo.add_buy(data, "iron-ore", 100)

        trading_silo.process()

        assert.equals(7, inventory.get_item_count("iron-ore"))
        assert.equals(1000000 - 7, storage.companies.Acme.credits)
    end)

    it("serves buy orders in list order when credits run short", function()
        local data, inventory = make_silo(trading_silo, { credits = 5 })
        trading_silo.add_buy(data, "iron-ore", 10)
        trading_silo.add_buy(data, "copper-ore", 10)

        trading_silo.process()

        assert.equals(5, inventory.get_item_count("iron-ore"))
        assert.equals(0, inventory.get_item_count("copper-ore"))
    end)

    it("sells everything of a listed type", function()
        local data, inventory = make_silo(trading_silo)
        inventory.insert({ name = "copper-ore", count = 40 })
        trading_silo.add_sell(data, "copper-ore")

        trading_silo.process()

        assert.equals(0, inventory.get_item_count("copper-ore"))
        assert.equals(1000040, stock.get("copper-ore"))
        assert.equals(1000000 + 40, storage.companies.Acme.credits)
    end)

    it("refuses an item that is already on either list", function()
        local data = make_silo(trading_silo)
        assert.is_true(trading_silo.add_buy(data, "iron-ore", 10))
        assert.is_false(trading_silo.add_sell(data, "iron-ore"))
        assert.is_true(trading_silo.add_sell(data, "copper-ore"))
        assert.is_false(trading_silo.add_buy(data, "copper-ore", 10))
        assert.equals(1, #data.buy)
        assert.equals(1, #data.sell)
    end)

    it("reorders and removes rows", function()
        local data = make_silo(trading_silo)
        trading_silo.add_buy(data, "iron-ore", 1)
        trading_silo.add_buy(data, "copper-ore", 2)
        trading_silo.add_buy(data, "stone", 3)

        trading_silo.move(data, "buy", 3, -1)
        assert.equals("stone", data.buy[2].item)
        assert.is_false(trading_silo.move(data, "buy", 1, -1))

        trading_silo.remove(data, "buy", 1)
        assert.equals(2, #data.buy)
        assert.equals("stone", data.buy[1].item)
    end)

    describe("circuit control", function()
        it("reads a positive signal as a buy target and a negative one as a sell", function()
            local data = make_silo(trading_silo, {
                signals = { [GREEN] = { signal("iron-ore", 250), signal("copper-ore", -1), signal("stone", 0) } },
            })
            data.circuit.enabled = true

            local buy, sell = trading_silo.resolve(data)

            assert.equals(1, #buy)
            assert.equals("iron-ore", buy[1].item)
            assert.equals(250, buy[1].quantity)
            assert.equals(1, #sell)
            assert.equals("copper-ore", sell[1].item)
        end)

        it("replaces the stored configuration rather than merging with it", function()
            local data = make_silo(trading_silo, {
                signals = { [GREEN] = { signal("stone", 5) } },
            })
            trading_silo.add_buy(data, "iron-ore", 10)
            trading_silo.add_sell(data, "copper-ore")
            data.circuit.enabled = true

            local buy, sell = trading_silo.resolve(data)

            assert.equals(1, #buy)
            assert.equals("stone", buy[1].item)
            assert.equals(0, #sell)

            data.circuit.enabled = false
            buy, sell = trading_silo.resolve(data)
            assert.equals("iron-ore", buy[1].item)
            assert.equals("copper-ore", sell[1].item)
        end)

        it("reads only the selected wire", function()
            local data = make_silo(trading_silo, {
                signals = {
                    [GREEN] = { signal("iron-ore", 10) },
                    [RED] = { signal("copper-ore", 20) },
                },
            })
            data.circuit.enabled = true

            data.circuit.wire = "green"
            local buy = trading_silo.resolve(data)
            assert.equals(1, #buy)
            assert.equals("iron-ore", buy[1].item)

            data.circuit.wire = "red"
            buy = trading_silo.resolve(data)
            assert.equals(1, #buy)
            assert.equals("copper-ore", buy[1].item)
        end)

        it("sums both wires, so opposing signals cancel towards one side", function()
            local data = make_silo(trading_silo, {
                signals = {
                    [GREEN] = { signal("iron-ore", 100) },
                    [RED] = { signal("iron-ore", -30), signal("copper-ore", -5) },
                },
            })
            data.circuit.enabled = true
            data.circuit.wire = "both"

            local buy, sell = trading_silo.resolve(data)

            assert.equals(1, #buy)
            assert.equals(70, buy[1].quantity)
            assert.equals(1, #sell)
            assert.equals("copper-ore", sell[1].item)
        end)

        it("buys and sells from resolved signals", function()
            local data, inventory = make_silo(trading_silo, {
                signals = { [GREEN] = { signal("iron-ore", 12), signal("copper-ore", -1) } },
            })
            inventory.insert({ name = "copper-ore", count = 6 })
            data.circuit.enabled = true

            trading_silo.process()

            assert.equals(12, inventory.get_item_count("iron-ore"))
            assert.equals(0, inventory.get_item_count("copper-ore"))
        end)
    end)
end)
