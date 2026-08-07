-- Does the starting industry's supply config actually run? Seed the warehouse
-- with plates and flasks the way a player selling to Nauvis would, let it run,
-- and read back what is on each transport line, what the assemblers and labs are
-- doing, and whether science packs come back through the intake.
local stock = require("scripts.stock")
local supply_belts = require("scripts.supply_belts")

local M = {}

-- Shape-local -> world: the shape is built at -14,-55.
local OX, OY = -14, -55

local WATCH = {
    { label = "copper/gear bus (west)", x = 25.5, y = 23.5 },
    { label = "gear feed (north)", x = 26.5, y = 23.5 },
    { label = "lab feed (east)", x = 10.5, y = 37.5 },
}

local function status_name(entity)
    if not entity then return "MISSING" end
    for name, value in pairs(defines.entity_status) do
        if value == entity.status then return name end
    end
    return tostring(entity.status)
end

local function lines_of(entity)
    local out = {}
    for i = 1, entity.get_max_transport_line_index() do
        local contents = {}
        for name, count in pairs(entity.get_transport_line(i).get_contents
            and {} or {}) do contents[name] = count end
        -- get_contents is 2.0-shaped; fall back to iterating the line itself.
        local line = entity.get_transport_line(i)
        local seen = {}
        for _, item in ipairs(line.get_contents() or {}) do
            seen[#seen + 1] = item.name .. "x" .. item.count
        end
        out[#out + 1] = "line" .. i .. "=" .. (#seen == 0 and "-" or table.concat(seen, ","))
    end
    return table.concat(out, " ")
end

local function report(tick)
    local surface = game.surfaces["nauvis"]

    for _, watch in ipairs(WATCH) do
        local belt = surface.find_entity("otc-supply-belt", { watch.x + OX, watch.y + OY })
        if belt then
            local data
            for _, entry in pairs(storage.supply_belts or {}) do
                if entry.entity == belt then data = entry end
            end
            log(string.format("PROBE @%d %s cfg(left=%s right=%s) %s", tick, watch.label,
                tostring(data and data.left), tostring(data and data.right), lines_of(belt)))
        else
            log("PROBE @" .. tick .. " " .. watch.label .. " MISSING")
        end
    end

    -- The shared ingredient bus a few tiles west of the supply belt: this is
    -- where copper and gears have to be riding on separate lanes.
    local bus = surface.find_entity("transport-belt", { 22.5 + OX, 23.5 + OY })
    if bus then log("PROBE @" .. tick .. " bus at 22.5,23.5: " .. lines_of(bus)) end

    local gear = surface.find_entity("assembling-machine-1", { 26.5 + OX, 20.5 + OY })
    local science = surface.find_entity("assembling-machine-1", { 11.5 + OX, 20.5 + OY })
    local lab = surface.find_entity("lab", { 11.5 + OX, 34.5 + OY })
    log(string.format("PROBE @%d gear=%s science=%s lab=%s", tick,
        status_name(gear), status_name(science), status_name(lab)))

    local held = {}
    for _, item in ipairs { "iron-plate", "copper-plate", "iron-gear-wheel",
        "automation-science-pack", "iron-ore", "copper-ore" } do
        held[#held + 1] = item .. "=" .. stock.get(item)
    end
    log("PROBE @" .. tick .. " stock: " .. table.concat(held, " "))
end

script.on_nth_tick(1800, function()
    if game.tick == 0 then return end
    report(game.tick)
end)

function M.run()
    supply_belts.init()
    stock.init()
    -- Stand in for players selling Nauvis the things it cannot make itself.
    stock.set("iron-plate", 5000)
    stock.set("copper-plate", 5000)
    stock.set("automation-science-pack", 2000)
    stock.set("logistic-science-pack", 2000)

    local registered = 0
    for _, data in pairs(storage.supply_belts or {}) do
        registered = registered + 1
        log(string.format("PROBE registered supply left=%s right=%s",
            tostring(data.left), tostring(data.right)))
    end
    log("PROBE registered supply belts: " .. registered)
end

return M
