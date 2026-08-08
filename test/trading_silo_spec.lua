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
    -- The real one works this out from the slot filters and the limiter bar;
    -- here there is only the flat capacity, which is enough to pin that an order
    -- with no quantity fills whatever room is left.
    inv.get_insertable_count = function() return inv.capacity - inv.held end
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
    local behavior = { object_name = "LuaContainerControlBehavior", read_contents = true }
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
        -- A wired container broadcasts its contents; circuit control has to turn
        -- that off so the silo's own stock is not added to the price signal.
        get_or_create_control_behavior = function()
            return behavior
        end,
    }

    local data = trading_silo.register(entity)
    return data, inventory, behavior
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

    describe("price limits", function()
        it("skips a buy whose price is above the max", function()
            local data, inventory = make_silo(trading_silo)
            stock.set("iron-ore", 500)
            trading_silo.add_buy(data, "iron-ore", 10)
            local price = trading_silo.buy_price("iron-ore")

            trading_silo.set_limit(data, "buy", 1, price - 1)
            trading_silo.process()
            assert.equals(0, inventory.get_item_count("iron-ore"))

            trading_silo.set_limit(data, "buy", 1, price)
            trading_silo.process()
            assert.equals(10, inventory.get_item_count("iron-ore"))
        end)

        it("skips a sell whose price is below the min", function()
            local data, inventory = make_silo(trading_silo)
            inventory.insert({ name = "copper-ore", count = 20 })
            trading_silo.add_sell(data, "copper-ore")
            local price = trading_silo.sell_price("copper-ore")

            trading_silo.set_limit(data, "sell", 1, price + 1)
            trading_silo.process()
            assert.equals(20, inventory.get_item_count("copper-ore"))

            trading_silo.set_limit(data, "sell", 1, price)
            trading_silo.process()
            assert.equals(0, inventory.get_item_count("copper-ore"))
        end)

        it("treats a blank limit as no limit rather than as never trade", function()
            local data, inventory = make_silo(trading_silo)
            stock.set("iron-ore", 500)
            trading_silo.add_buy(data, "iron-ore", 5)
            trading_silo.set_limit(data, "buy", 1, 999999)
            trading_silo.set_limit(data, "buy", 1, nil)
            assert.is_nil(data.buy[1].limit)

            trading_silo.process()
            assert.equals(5, inventory.get_item_count("iron-ore"))
        end)
    end)

    describe("circuit control", function()
        it("reads each side's own wire, the signal value being the price limit", function()
            local data = make_silo(trading_silo, {
                signals = {
                    [GREEN] = { signal("iron-ore", 250), signal("stone", 0) },
                    [RED] = { signal("copper-ore", 80) },
                },
            })
            data.circuit.enabled = true
            trading_silo.set_wire(data, "buy", "green")

            local buy, sell = trading_silo.resolve(data)

            assert.equals(1, #buy)
            assert.equals("iron-ore", buy[1].item)
            assert.equals(250, buy[1].limit)
            -- No quantity: the inventory's filters and bar decide how much.
            assert.is_nil(buy[1].quantity)
            assert.equals(1, #sell)
            assert.equals("copper-ore", sell[1].item)
            assert.equals(80, sell[1].limit)
        end)

        it("never reads one colour for both sides", function()
            local data = make_silo(trading_silo)
            trading_silo.set_wire(data, "buy", "green")
            trading_silo.set_wire(data, "sell", "green")
            assert.equals("green", data.circuit.sell_wire)
            assert.equals("red", data.circuit.buy_wire)

            trading_silo.set_wire(data, "buy", "green")
            assert.equals("green", data.circuit.buy_wire)
            assert.equals("red", data.circuit.sell_wire)
        end)

        it("does not trade an item with no signal", function()
            local data = make_silo(trading_silo, {
                signals = { [GREEN] = { signal("iron-ore", 250) } },
            })
            trading_silo.add_buy(data, "stone", 10)
            trading_silo.add_sell(data, "copper-ore")
            data.circuit.enabled = true
            trading_silo.set_wire(data, "buy", "green")

            local buy, sell = trading_silo.resolve(data)
            assert.equals(1, #buy)
            assert.equals("iron-ore", buy[1].item)
            assert.equals(0, #sell)
        end)

        it("replaces the stored configuration rather than merging with it", function()
            local data = make_silo(trading_silo, {
                signals = { [GREEN] = { signal("stone", 5000) } },
            })
            trading_silo.add_buy(data, "iron-ore", 10)
            trading_silo.add_sell(data, "copper-ore")
            data.circuit.enabled = true
            trading_silo.set_wire(data, "buy", "green")

            local buy, sell = trading_silo.resolve(data)
            assert.equals(1, #buy)
            assert.equals("stone", buy[1].item)
            assert.equals(0, #sell)

            data.circuit.enabled = false
            buy, sell = trading_silo.resolve(data)
            assert.equals("iron-ore", buy[1].item)
            assert.equals("copper-ore", sell[1].item)
        end)

        it("fills whatever room the inventory has left when there is no quantity", function()
            local data, inventory = make_silo(trading_silo, {
                capacity = 40,
                signals = { [GREEN] = { signal("iron-ore", 5000) } },
            })
            stock.set("iron-ore", 500)
            data.circuit.enabled = true
            trading_silo.set_wire(data, "buy", "green")

            trading_silo.process()
            assert.equals(40, inventory.get_item_count("iron-ore"))
        end)

        it("honours the signal as a price cap", function()
            local data, inventory = make_silo(trading_silo, {
                capacity = 40,
                signals = { [GREEN] = { signal("iron-ore", 1) } },
            })
            stock.set("iron-ore", 500)
            data.circuit.enabled = true
            trading_silo.set_wire(data, "buy", "green")

            trading_silo.process()
            assert.equals(0, inventory.get_item_count("iron-ore"))
        end)

        it("sells off the sell wire at or above the signalled floor", function()
            local data, inventory = make_silo(trading_silo, {
                signals = { [RED] = { signal("copper-ore", 1) } },
            })
            inventory.insert({ name = "copper-ore", count = 6 })
            data.circuit.enabled = true
            trading_silo.set_wire(data, "sell", "red")

            trading_silo.process()
            assert.equals(0, inventory.get_item_count("copper-ore"))
        end)
    end)

    it("stops the silo broadcasting its contents while under circuit control", function()
        -- A wired container adds its own stock to the network. Under the old
        -- semantics that was harmless; now the signal is a *price*, so 200 plates
        -- in the box would silently raise a cap of 150 to 350.
        local data, _, behavior = make_silo(trading_silo)
        assert.is_true(behavior.read_contents)

        trading_silo.set_circuit_enabled(data, true)
        assert.is_false(behavior.read_contents)

        trading_silo.set_circuit_enabled(data, false)
        assert.is_true(behavior.read_contents)
    end)

    describe("migration", function()
        it("splits the old single wire and keeps pre-limit orders trading", function()
            local data = make_silo(trading_silo)
            data.circuit = { enabled = true, wire = "red" }
            data.buy = { { item = "iron-ore", quantity = 5 } }
            trading_silo.normalise(data)

            assert.equals("red", data.circuit.buy_wire)
            assert.equals("green", data.circuit.sell_wire)
            assert.is_nil(data.circuit.wire)
            assert.is_nil(data.buy[1].limit)
        end)
    end)
end)
