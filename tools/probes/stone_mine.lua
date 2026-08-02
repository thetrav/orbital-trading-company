-- Does the auto-built stone mine bind its drills to stone, draw power off the
-- district line, and land stone in Nauvis's stock?
--
-- No mine block brings generation of its own any more, and there is no
-- substation lattice either: what powers it is the big-pole line running round
-- its module, reaching the mine's own substation. So the interesting numbers
-- are the drill's status and whether that substation shares a network with the
-- poles.
local M = {}

local function status_name(status)
    for name, value in pairs(defines.entity_status) do
        if value == status then return name end
    end
    return "unknown(" .. tostring(status) .. ")"
end

local function report(label)
    local surface = game.surfaces["nauvis"]
    for _, drill in ipairs(surface.find_entities_filtered { name = "electric-mining-drill" }) do
        local target = drill.mining_target and drill.mining_target.name or "NONE"
        if target == "stone" or target == "NONE" then
            log(string.format("PROBE %s drill %.1f,%.1f status=%s target=%s",
                label, drill.position.x, drill.position.y, status_name(drill.status), target))
        end
    end

    local networks = {}
    for _, name in ipairs { "substation", "big-electric-pole" } do
        for _, pole in ipairs(surface.find_entities_filtered { name = name }) do
            local id = pole.electric_network_id
            networks[name .. "=" .. tostring(id)] = (networks[name .. "=" .. tostring(id)] or 0) + 1
        end
    end
    local parts = {}
    for key, n in pairs(networks) do parts[#parts + 1] = key .. "x" .. n end
    table.sort(parts)
    log("PROBE " .. label .. " networks: " .. table.concat(parts, " "))
    log("PROBE " .. label .. " stone stock=" .. tostring((storage.stock.items or {})["stone"] or 0))
end

script.on_nth_tick(600, function()
    if game.tick == 0 then return end
    report("tick" .. game.tick)
end)

function M.run()
    report("init")
end

return M
