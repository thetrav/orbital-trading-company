-- Does the auto-built stone mine bind its drills to stone, draw power off the
-- district grid, and land stone in Nauvis's stock?
--
-- It brings no generation of its own. It used to sit at fixed coordinates next
-- to the coal block and share its poles; now it takes a district slot, and what
-- powers it is the substation lattice. Both slots are ring 1, so the areas below
-- are the two slot pads rather than hand-measured boxes.
local district = require("scripts.district")

local M = {}

local function slot_area(col, row)
    local box = district.pad_box(district.centre(col, row))
    return {
        left_top = { x = box[1][1], y = box[1][2] },
        right_bottom = { x = box[2][1], y = box[2][2] },
    }
end

local AREA = slot_area(1, 0)
local COAL_AREA = slot_area(-1, 0)

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
