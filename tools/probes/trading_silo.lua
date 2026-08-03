-- Does otc-trading-silo really behave as a 100-slot container that inserters and
-- logistic bots can load and unload, and does a registered silo trade?
local trading_silo = require("scripts.trading_silo")
local stock = require("scripts.stock")

local M = {}

local ORIGIN = { x = 700, y = 700 }

local function at(dx, dy)
    return { x = ORIGIN.x + dx, y = ORIGIN.y + dy }
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks(ORIGIN, 3)
    surface.force_generate_chunk_requests()

    local tiles = {}
    for dx = -12, 12 do
        for dy = -12, 12 do
            tiles[#tiles + 1] = { name = "refined-concrete", position = { ORIGIN.x + dx, ORIGIN.y + dy } }
        end
    end
    surface.set_tiles(tiles, true)

    local force = game.forces["player"]
    local silo = surface.create_entity {
        name = "otc-trading-silo", position = at(0, 0), force = force,
    }
    log("PROBE silo placed: " .. tostring(silo ~= nil))
    if not silo then return end

    local inventory = silo.get_inventory(defines.inventory.chest)
    log("PROBE slots: " .. tostring(#inventory) .. " want=100")

    -- An inserter has to be able to put arbitrary goods in, which is the whole
    -- reason this is a container and not a real rocket silo.
    local source = surface.create_entity {
        name = "steel-chest", position = at(-6, 0), force = force,
    }
    source.insert { name = "iron-plate", count = 100 }
    -- An inserter's direction points at its pickup, so west picks up from the
    -- chest and drops east onto the silo's edge tile.
    local inserter = surface.create_entity {
        name = "fast-inserter", position = at(-5, 0), force = force, direction = defines.direction.west,
    }
    log("PROBE inserter built: " .. tostring(inserter ~= nil))

    surface.create_entity { name = "substation", position = at(-6, -3), force = force }
    local accumulator = surface.create_entity { name = "electric-energy-interface", position = at(-8, -3), force = force }
    if accumulator then accumulator.power_production = 10000000 end

    -- Bots are deliberately out for now: as a logistic chest with no roboport
    -- coverage the silo flashed a "not connected" alert. It must therefore be
    -- invisible to a logistic network even when one reaches it.
    local roboport = surface.create_entity { name = "roboport", position = at(-9, 3), force = force }
    if roboport then
        roboport.insert { name = "construction-robot", count = 5 }
        roboport.insert { name = "logistic-robot", count = 5 }
        roboport.energy = roboport.prototype.get_max_energy_usage() * 1000
    end

    local member = defines.logistic_member_index and defines.logistic_member_index.logistic_container
    local point = member and silo.get_logistic_point(member) or nil
    log("PROBE silo is a logistic member: " .. tostring(point ~= nil) .. " want=false")

    local requester = surface.create_entity {
        name = "requester-chest", position = at(-9, 6), force = force,
    }
    if requester then
        local request = requester.get_requester_point()
        if request then
            request.add_section().set_slot(1, { value = "iron-plate", min = 20 })
        end
    end

    -- Seed the silo so a bot has something to withdraw, and register it so the
    -- trading loop runs against a real entity.
    inventory.insert { name = "iron-plate", count = 50 }
    storage.companies = storage.companies or {}
    storage.companies[force.name] = storage.companies[force.name] or { credits = 100000 }
    trading_silo.init()
    local data = trading_silo.register(silo)
    if data then
        data.force_name = force.name
        trading_silo.add_buy(data, "iron-ore", 25)
        trading_silo.add_sell(data, "copper-ore")
        stock.set("iron-ore", 5000)
        inventory.insert { name = "copper-ore", count = 30 }
    end

    storage.probe = { silo = silo, requester = requester, force_name = force.name }
end

-- Registered at require time so it survives the save/load that --ticks does.
script.on_nth_tick(300, function()
    if game.tick == 0 then return end
    local state = storage.probe
    if not state or not state.silo.valid then return end
    local inventory = state.silo.get_inventory(defines.inventory.chest)
    log("PROBE t=" .. game.tick
        .. " silo iron-plate=" .. inventory.get_item_count("iron-plate")
        .. " iron-ore=" .. inventory.get_item_count("iron-ore")
        .. " copper-ore=" .. inventory.get_item_count("copper-ore")
        .. " requester iron-plate=" .. (state.requester and state.requester.valid
            and state.requester.get_item_count("iron-plate") or -1)
        .. " credits=" .. math.floor(storage.companies[state.force_name].credits))
end)

return M
