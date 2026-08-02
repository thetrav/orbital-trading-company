-- Does the repaired capture apply on Nauvis, and do its belts land in the
-- supply/intake registries with the right per-lane items?
local platform = require("scripts.platform")
local stock = require("scripts.stock")
local supply_belts = require("scripts.supply_belts")

local M = {}

local AT = { x = -20, y = 15 }

function M.run()
    local surface = game.surfaces["nauvis"]
    local ok, err = pcall(platform.build_shape, surface, "red_flask_factory", AT, "Nauvis")
    log("PROBE build ok=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
    if not ok then return end

    for _, data in pairs(storage.supply_belts or {}) do
        local e = data.entity
        if e and e.valid then
            log(string.format("PROBE supply %s at %.1f,%.1f dir=%s left=%s right=%s",
                e.name, e.position.x, e.position.y, tostring(e.direction),
                tostring(data.left), tostring(data.right)))
        end
    end
    for _, data in pairs(storage.intake_belts or {}) do
        local e = data.entity
        if e and e.valid then
            log(string.format("PROBE intake %s at %.1f,%.1f", e.name, e.position.x, e.position.y))
        end
    end

    local assemblers = surface.find_entities_filtered {
        name = "assembling-machine-1",
        area = { left_top = { x = AT.x, y = AT.y }, right_bottom = { x = AT.x + 22, y = AT.y + 14 } },
    }
    local recipes = {}
    for _, a in ipairs(assemblers) do
        local recipe = a.get_recipe()
        local key = recipe and recipe.name or "NONE"
        recipes[key] = (recipes[key] or 0) + 1
    end
    for name, count in pairs(recipes) do
        log("PROBE recipe " .. name .. " x" .. count)
    end

    -- Drive the supply loop and confirm the reserved lane stays clear.
    stock.add("copper-plate", 200)
    stock.add("iron-plate", 200)
    for _ = 1, 40 do supply_belts.process() end
    for _, data in pairs(storage.supply_belts or {}) do
        local e = data.entity
        if e and e.valid then
            local lanes = {}
            for index = 1, 2 do
                local total = 0
                for _, item in pairs(e.get_transport_line(index).get_contents()) do
                    total = total + item.count
                end
                lanes[#lanes + 1] = "line" .. index .. "=" .. total
            end
            log(string.format("PROBE fed %.1f,%.1f %s", e.position.x, e.position.y,
                table.concat(lanes, " ")))
        end
    end
end

return M
