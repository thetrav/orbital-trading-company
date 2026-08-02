-- Does the auto-built stone mine bind its drills to stone, draw power off the
-- coal block's grid, and land stone in Nauvis's stock?
local M = {}

local AREA = { left_top = { x = -78, y = -8 }, right_bottom = { x = -64, y = 8 } }
local COAL_AREA = { left_top = { x = -95, y = -8 }, right_bottom = { x = -79, y = 16 } }

local function status_name(status)
    for name, value in pairs(defines.entity_status) do
        if value == status then return name end
    end
    return "unknown(" .. tostring(status) .. ")"
end

local function report(label)
    local surface = game.surfaces["nauvis"]
    for _, drill in ipairs(surface.find_entities_filtered {
        name = "electric-mining-drill", area = AREA,
    }) do
        log(string.format("PROBE %s drill %.1f,%.1f status=%s target=%s",
            label, drill.position.x, drill.position.y, status_name(drill.status),
            drill.mining_target and drill.mining_target.name or "NONE"))
    end
    for _, area in ipairs { AREA, COAL_AREA } do
        for _, sub in ipairs(surface.find_entities_filtered { name = "substation", area = area }) do
            log(string.format("PROBE %s substation %.1f,%.1f network=%s",
                label, sub.position.x, sub.position.y, tostring(sub.electric_network_id)))
        end
    end
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
