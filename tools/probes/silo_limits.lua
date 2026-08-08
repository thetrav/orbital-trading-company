-- Do the price limits hold, and do real slot filters plus the limiter bar decide
-- how much a circuit-driven buy order takes?
--
-- Setup happens in run() (end of on_init) but every assertion waits for a tick:
-- a circuit network built this tick carries no signals yet, exactly like a drill
-- having no mining target at tick 0.
local trading_silo = require("scripts.trading_silo")
local stock = require("scripts.stock")
local pricing = require("scripts.pricing")

local M = {}

local GREEN = defines.wire_connector_id.circuit_green

-- Setup runs in on_init during --create and the checks run after a load, so the
-- handles have to live in `storage`: a module-local table does not survive the
-- save.
local function built()
    storage.otc_probe = storage.otc_probe or {}
    return storage.otc_probe
end

local function silo_of(unit)
    local data = unit and trading_silo.get(unit)
    if not data or not data.entity.valid then return nil end
    return data
end

local COMBINATOR_POS = { 336, 296 }

--- `find_entity` wants the entity's exact centre, and a 1x1 built at {336,296}
--- snaps to {336.5,296.5}, so an area search is what actually finds it.
local function section_of()
    local found = game.surfaces["nauvis"].find_entities_filtered {
        name = "constant-combinator",
        area = { { COMBINATOR_POS[1] - 2, COMBINATOR_POS[2] - 2 },
            { COMBINATOR_POS[1] + 2, COMBINATOR_POS[2] + 2 } },
    }
    local entity = found[1]
    if not entity or not entity.valid then return nil end
    return entity.get_control_behavior().get_section(1)
end

local function make_silo(position, force_name)
    local entity = game.surfaces["nauvis"].create_entity {
        name = trading_silo.NAME, position = position, force = force_name,
    }
    return entity, trading_silo.register(entity)
end

local function held(inventory, item)
    return inventory.get_item_count(item)
end

local function checks()
    local manual, circuit = silo_of(built().manual), silo_of(built().circuit)
    if not manual or not circuit then
        log("PROBE silos missing after load")
        return
    end
    local inv1 = manual.entity.get_inventory(defines.inventory.chest)
    local inv2 = circuit.entity.get_inventory(defines.inventory.chest)

    -- control.lua runs process() every tick, so anything already in the box was
    -- bought by the background pass before this check ran. Each sub-test starts
    -- from empty, and no game tick passes inside this function.
    --
    -- Stock has to be reset *before* the price is read: price is the anchor times
    -- a scarcity multiple, so the background pass draining the warehouse moves it
    -- and a limit compared against a stale price proves nothing.
    local function reset()
        inv1.clear()
        stock.set("iron-plate", stock.TARGET_STOCK)
        stock.set("copper-plate", stock.TARGET_STOCK)
    end

    reset()
    local buy_price = trading_silo.buy_price("iron-plate")
    local sell_price = trading_silo.sell_price("copper-plate")
    log(string.format("PROBE prices at target stock: iron-plate buy=%d, copper-plate sell=%d",
        buy_price, sell_price))

    -- 1. Manual: a max below market blocks the buy, at market allows it.
    trading_silo.set_limit(manual, "buy", 1, buy_price - 1)
    trading_silo.process()
    log("PROBE manual max=" .. (buy_price - 1) .. " (below) -> bought " .. held(inv1, "iron-plate"))

    reset()
    trading_silo.set_limit(manual, "buy", 1, buy_price)
    trading_silo.process()
    log("PROBE manual max=" .. buy_price .. " (at market) -> bought " .. held(inv1, "iron-plate"))

    -- 2. Manual: a min above market blocks the sale.
    reset()
    inv1.insert { name = "copper-plate", count = 40 }
    trading_silo.set_limit(manual, "sell", 1, sell_price + 1)
    trading_silo.process()
    log("PROBE manual min=" .. (sell_price + 1) .. " (above) -> still holding "
        .. held(inv1, "copper-plate"))

    trading_silo.set_limit(manual, "sell", 1, sell_price)
    trading_silo.process()
    log("PROBE manual min=" .. sell_price .. " (at market) -> still holding "
        .. held(inv1, "copper-plate"))
    -- Stop the background pass from refilling it and confusing what follows.
    trading_silo.set_limit(manual, "buy", 1, 1)

    -- 3. Circuit: the signal is the cap, filters and the bar are the quantity.
    local network = circuit.entity.get_circuit_network(GREEN)
    local seen = {}
    for _, sig in pairs(network and network.signals or {}) do
        seen[#seen + 1] = tostring(sig.signal.name) .. "=" .. tostring(sig.count)
    end
    log("PROBE green signals on the silo: " .. (#seen == 0 and "(none)" or table.concat(seen, " ")))

    local buy, sell = trading_silo.resolve(circuit)
    log("PROBE resolved buy=" .. #buy .. " sell=" .. #sell
        .. " item=" .. tostring(buy[1] and buy[1].item)
        .. " limit=" .. tostring(buy[1] and buy[1].limit)
        .. " quantity=" .. tostring(buy[1] and buy[1].quantity))

    inv2.clear()
    -- Enough that stock never becomes the binding constraint, but the price is
    -- read back below so the cap comparison stays honest.
    stock.set("iron-plate", stock.TARGET_STOCK * 4)
    log("PROBE bar=" .. inv2.get_bar() .. ", 2 filtered slots, stack="
        .. prototypes.item["iron-plate"].stack_size
        .. ", insertable=" .. inv2.get_insertable_count("iron-plate"))
    trading_silo.process()
    log("PROBE circuit buy took: " .. held(inv2, "iron-plate")
        .. " (expect 2 slots x 100 = 200, not the silo's 100 slots)")

    -- A third filtered slot, bar still at 4: filters and the bar are the dial.
    inv2.set_bar(4)
    inv2.set_filter(3, "iron-plate")
    trading_silo.process()
    log("PROBE after a third filtered slot: " .. held(inv2, "iron-plate") .. " (expect 300)")

    -- 4. An unsignalled item on the stored list is not traded under circuit control.
    log("PROBE unsignalled copper-plate bought: " .. held(inv2, "copper-plate"))

    -- 5. Drop the cap under market; the next pass must stop dead despite room.
    -- The wire only carries the new value from the next tick, which is why this
    -- is checked in a later firing rather than here.
    local section = section_of()
    log("PROBE combinator section found: " .. tostring(section ~= nil))
    if section then
        section.set_slot(1, {
            value = { type = "item", name = "iron-plate", quality = "normal" }, min = 1,
        })
    end
end

local function recheck()
    local circuit = silo_of(built().circuit)
    if not circuit then return end
    local inv2 = circuit.entity.get_inventory(defines.inventory.chest)
    -- Plenty of room and plenty of stock: only the cap can stop it now. Stock
    -- stays near target so the price does not collapse to the floor of 1, which
    -- a cap of 1 would then satisfy and prove nothing.
    inv2.set_bar(101)
    stock.set("iron-plate", stock.TARGET_STOCK)
    local before = held(inv2, "iron-plate")
    log("PROBE cap now " .. tostring((trading_silo.resolve(circuit)[1] or {}).limit)
        .. ", market " .. trading_silo.buy_price("iron-plate")
        .. ", insertable " .. inv2.get_insertable_count("iron-plate"))
    trading_silo.process()
    log("PROBE cap below market with room and stock: " .. before
        .. " -> " .. held(inv2, "iron-plate"))
end

-- Not 60, and not 1: control.lua registers both, and a later on_nth_tick for the
-- same period silently replaces this handler.
script.on_nth_tick(90, function()
    if game.tick == 0 or not built().circuit then return end
    if not built().done then
        built().done = true
        checks()
        return
    end
    if not built().rechecked then
        built().rechecked = true
        recheck()
    end
end)

function M.run()
    game.create_force("SiloCo")
    storage.companies = storage.companies or {}
    storage.companies.SiloCo = { credits = 100000000 }

    -- control.lua computes prices after this point, so without it every price
    -- reads as the floor of 1.
    storage.prices = pricing.calculate()
    stock.init()
    -- At TARGET_STOCK the scarcity multiple is 1, so prices are the plain
    -- anchor. Flooding stock instead drives them to the floor and every limit
    -- comparison becomes meaningless.
    stock.set("iron-plate", stock.TARGET_STOCK)
    stock.set("copper-plate", stock.TARGET_STOCK)

    local entity1, data1 = make_silo({ 300, 300 }, "SiloCo")
    trading_silo.add_buy(data1, "iron-plate", 10)
    trading_silo.add_sell(data1, "copper-plate")
    built().manual = entity1.unit_number

    local entity2, data2 = make_silo({ 340, 300 }, "SiloCo")
    local inv2 = entity2.get_inventory(defines.inventory.chest)
    inv2.set_filter(1, "iron-plate")
    inv2.set_filter(2, "iron-plate")
    inv2.set_bar(3)
    -- On the stored list but never signalled, so it must not be traded.
    trading_silo.add_buy(data2, "copper-plate", 50)
    data2.circuit.enabled = true
    trading_silo.set_wire(data2, "buy", "green")

    -- A wired container broadcasts its own contents onto the network, which would
    -- add the silo's stock to the price signal. Can that be switched off?
    local behavior = entity2.get_or_create_control_behavior()
    log("PROBE container control behavior: " .. tostring(behavior and behavior.object_name))
    if behavior then
        log("PROBE read_contents default: " .. tostring(behavior.read_contents))
        local ok, err = pcall(function() behavior.read_contents = false end)
        log("PROBE read_contents := false ok=" .. tostring(ok)
            .. " now=" .. tostring(behavior.read_contents) .. " err=" .. tostring(err))
    end

    local combinator = game.surfaces["nauvis"].create_entity {
        name = "constant-combinator", position = COMBINATOR_POS, force = "SiloCo",
    }
    local section = combinator.get_control_behavior().get_section(1)
    section.set_slot(1, {
        value = { type = "item", name = "iron-plate", quality = "normal" }, min = 100000,
    })
    combinator.get_wire_connector(GREEN, true)
        .connect_to(entity2.get_wire_connector(GREEN, true))

    built().circuit = entity2.unit_number
    log("PROBE combinator unit_number: " .. tostring(combinator.unit_number))
end

return M
