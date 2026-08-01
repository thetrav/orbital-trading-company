-- Are the Nauvis mining drills bound to ore, and are they powered?
local M = {}

local function status_name(status)
    for name, value in pairs(defines.entity_status) do
        if value == status then return name end
    end
    return "unknown(" .. tostring(status) .. ")"
end

local function report(label)
    local surface = game.surfaces["nauvis"]
    local drills = surface.find_entities_filtered { name = "electric-mining-drill" }
    for i, drill in ipairs(drills) do
        if i <= 2 then
            log(string.format("PROBE %s drill %.1f,%.1f status=%s target=%s",
                label, drill.position.x, drill.position.y, status_name(drill.status),
                drill.mining_target and drill.mining_target.name or "NONE"))
        end
    end
    local acc = surface.find_entities_filtered { name = "accumulator" }[1]
    if acc then
        log(string.format("PROBE %s accumulator energy=%.0f", label, acc.energy))
    end
end

function M.run()
    report("init")
end

-- on_nth_tick also fires at tick 0 when the save is loaded; skip that one or the
-- report measures a world that has not run for a single tick (everything reads
-- as no_power, and drills have not started mining yet).
script.on_nth_tick(600, function()
    if game.tick == 0 then return end
    report("tick" .. game.tick)
    script.on_nth_tick(600, nil)
end)

return M
