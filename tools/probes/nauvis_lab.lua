-- Does the lab district actually run? Every entity the shape describes has to
-- exist (a collision drops one silently), the labs have to be powered off the
-- district lattice, and a pack put into stock has to reach a lab and come back
-- to stock if nothing wanted it.
local stock = require("scripts.stock")

local M = {}

local PACK = "automation-science-pack"

local function report(surface)
    local labs = surface.find_entities_filtered { name = "lab", force = "Nauvis" }
    local statuses = {}
    local packs = 0
    for _, lab in ipairs(labs) do
        local status = lab.status or -1
        statuses[status] = (statuses[status] or 0) + 1
        local inv = lab.get_inventory(defines.inventory.lab_input)
        packs = packs + (inv and inv.get_item_count(PACK) or 0)
    end
    local names = {}
    for status, n in pairs(statuses) do
        names[#names + 1] = tostring(status) .. "x" .. n
    end
    table.sort(names)
    log("PROBE labs: " .. #labs .. " statuses: " .. table.concat(names, " ")
        .. " packs held: " .. packs)
    local first = labs[1]
    if first then
        local x, y = first.position.x, first.position.y
        log("PROBE lab inserters: " .. surface.count_entities_filtered {
            name = "inserter", area = { { x - 2, y }, { x + 26, y + 6 } },
        })
    end
    log("PROBE stock packs: " .. stock.get(PACK))
end

-- Registered at require time, so it survives the save/load the harness does
-- between building the world and running ticks.
script.on_nth_tick(590, function()
    if game.tick == 0 then return end
    local surface = game.surfaces["nauvis"]
    report(surface)
    local force = game.forces["Nauvis"]
    log("PROBE research: " .. tostring(force.current_research and force.current_research.name)
        .. " progress " .. string.format("%.3f", force.research_progress))
end)

function M.run()
    log("PROBE working: " .. tostring(defines.entity_status.working)
        .. " no_power: " .. tostring(defines.entity_status.no_power)
        .. " low_power: " .. tostring(defines.entity_status.low_power)
        .. " no_research: " .. tostring(defines.entity_status.no_research_in_progress))
    stock.add(PACK, 400)
    game.forces["Nauvis"].add_research("logistics")
    report(game.surfaces["nauvis"])
end

return M
