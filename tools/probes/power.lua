-- Why does the Nauvis mine have no power?
local M = {}

local function status_name(status)
    for name, value in pairs(defines.entity_status) do
        if value == status then return name end
    end
    return "unknown(" .. tostring(status) .. ")"
end

local function report(label)
    local surface = game.surfaces["nauvis"]
    log(string.format("PROBE %s tick=%d daytime=%.4f solar_mult=%.2f",
        label, game.tick, surface.daytime, surface.solar_power_multiplier))

    local drill = surface.find_entities_filtered { name = "electric-mining-drill" }[1]
    local solar = surface.find_entities_filtered { name = "solar-panel" }[1]
    local acc = surface.find_entities_filtered { name = "accumulator" }[1]
    local lab = surface.find_entities_filtered { name = "lab" }[1]

    for name, entity in pairs { drill = drill, solar = solar, accumulator = acc, lab = lab } do
        if entity then
            log(string.format("PROBE %s %s: status=%s energy=%.0f buffer=%.0f net=%s",
                label, name, status_name(entity.status), entity.energy,
                entity.electric_buffer_size or 0, tostring(entity.electric_network_id)))
        end
    end

    if drill then
        local ok, counts = pcall(function() return drill.electric_network_statistics.output_counts end)
        if ok and counts then
            for name, count in pairs(counts) do
                log(string.format("PROBE %s network produced %s = %s", label, name, tostring(count)))
            end
        else
            log("PROBE " .. label .. " output_counts unavailable: " .. tostring(counts))
        end
    end
end

function M.run()
    report("init")
end

-- on_nth_tick also fires at tick 0 when the save is loaded; skip that one or the
-- report measures a world that has not run for a single tick.
script.on_nth_tick(600, function()
    if game.tick == 0 then return end
    report("tick" .. game.tick)
    script.on_nth_tick(600, nil)
end)

return M
