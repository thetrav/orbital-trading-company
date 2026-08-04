-- The enlarged orbital station and the launch bay that turns to face spawn.
-- Does every wall get an airlock that expands outwards, and does each company's
-- bay open on the side its players walk in from?
local company_facilities = require("scripts.company_facilities")
local platform = require("scripts.platform")

local M = {}

function M.run()
    local surface = game.surfaces["nauvis"]

    for i = 1, 5 do
        local name = "ProbeCo" .. i
        game.create_force(name)
        local sites = company_facilities.ensure_for(name)
        local bay = sites and sites[1]
        if not bay then
            log("PROBE " .. name .. " got no bay")
            goto continue
        end

        local gate = surface.find_entities_filtered {
            area = { { bay.x - 16, bay.y - 16 }, { bay.x + 16, bay.y + 16 } },
            name = "gate",
            force = name,
        }[1]
        local dx = gate and (gate.position.x - bay.x) or 0
        local dy = gate and (gate.position.y - bay.y) or 0
        local side = (math.abs(dx) > math.abs(dy))
            and (dx > 0 and "+x" or "-x")
            or (dy > 0 and "+y" or "-y")
        log(string.format("PROBE bay %s at %d,%d gate offset %.0f,%.0f side %s (spawn is %s)",
            name, bay.x, bay.y, dx, dy, side,
            (math.abs(bay.x) > math.abs(bay.y)) and (bay.x > 0 and "-x" or "+x")
                or (bay.y > 0 and "-y" or "+y")))

        -- The gate is only worth facing spawn if what a player walks in for is
        -- on the same side: the teleporter should sit just inside it, and the
        -- silo should not be between the two.
        local pad = surface.find_entities_filtered {
            area = { { bay.x - 16, bay.y - 16 }, { bay.x + 16, bay.y + 16 } },
            name = "otc-teleporter",
            force = name,
        }[1]
        local silo = surface.find_entities_filtered {
            area = { { bay.x - 16, bay.y - 16 }, { bay.x + 16, bay.y + 16 } },
            name = "rocket-silo",
        }[1]
        if pad and gate then
            log(string.format("PROBE   teleporter offset %.0f,%.0f - %.1f tiles from the gate; silo offset %.0f,%.0f",
                pad.position.x - bay.x, pad.position.y - bay.y,
                math.abs(pad.position.x - gate.position.x) + math.abs(pad.position.y - gate.position.y),
                silo and (silo.position.x - bay.x) or 0, silo and (silo.position.y - bay.y) or 0))
        end
        ::continue::
    end

    local station = game.surfaces["otc-station-1"]
    if not station then
        log("PROBE no station surface")
        return
    end
    station.request_to_generate_chunks({ 0, 0 }, 4)
    station.force_generate_chunk_requests()

    local platform_tiles = station.count_tiles_filtered {
        area = { { -60, -60 }, { 60, 60 } }, name = "otc-platform",
    }
    log("PROBE station platform tiles: " .. platform_tiles
        .. " walls: " .. station.count_entities_filtered { name = "otc-platform-wall" }
        .. " gates: " .. station.count_entities_filtered { name = "gate" }
        .. " computers: " .. station.count_entities_filtered { name = "otc-gate-computer" }
        .. " silos: " .. station.count_entities_filtered { name = "otc-trading-silo" })

    local gates = {}
    for _, gate in pairs(storage.gates) do
        if gate.surface_name == station.name then
            gates[#gates + 1] = gate
            log(string.format("PROBE station gate %d,%d dir=%s computer=%s",
                gate.pos.x, gate.pos.y, gate.dir, tostring(gate.computer_unit_number)))
        end
    end

    -- Every airlock has to be able to sell a room, and the room has to land
    -- clear of the station rather than inside it.
    for _, gate in ipairs(gates) do
        local ok, err = platform.expand_from_gate(station, gate.pos, "hub", "ProbeCo1")
        log(string.format("PROBE expand %s from %d,%d -> %s %s",
            gate.dir, gate.pos.x, gate.pos.y, tostring(ok), tostring(err)))
    end
    log("PROBE station silos after expansion: "
        .. station.count_entities_filtered { name = "otc-trading-silo" }
        .. " hub gates: " .. station.count_entities_filtered { name = "gate" })
end

return M
