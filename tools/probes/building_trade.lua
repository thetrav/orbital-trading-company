-- Can a company trade buildings with Nauvis, and does selling it a realistic
-- number of machines actually fund an expansion? Also: which lines of each
-- option's bill of materials can a company force supply at all?
local item_filter = require("scripts.item_filter")
local nauvis_expansion = require("scripts.nauvis_expansion")
local nauvis_siting = require("scripts.nauvis_siting")
local research = require("scripts.research")
local stock = require("scripts.stock")
local utils = require("scripts.utils")

local M = {}

local function can_craft(force, item_name)
    for _, recipe in pairs(force.recipes) do
        if recipe.enabled then
            for _, product in pairs(recipe.products) do
                if product.name == item_name then return true end
            end
        end
    end
    return false
end

function M.run()
    game.create_force("TradeCo")
    local force = game.forces.TradeCo
    research.sync_force(force)

    -- The filter is the single gate: trading_silo checks it at execution time
    -- too, so what it says here is what a silo will actually move.
    for _, item in ipairs { "iron-plate", "electric-mining-drill", "solar-panel",
        "accumulator", "substation", "transport-belt", "inserter", "fast-inserter",
        "long-handed-inserter", "assembling-machine-1", "lab", "automation-science-pack" } do
        log(string.format("PROBE allowed %-24s tradeable=%s craftable=%s price=%s",
            item, tostring(item_filter.is_item_allowed(item, force)),
            tostring(can_craft(force, item)),
            tostring(utils.get_base_price and utils.get_base_price(item) or "?")))
    end

    -- Why is a plain drill not craftable? Compare the force's recipe against the
    -- prototype default and against Nauvis's own copy.
    for _, name in ipairs { "electric-mining-drill", "solar-panel", "substation",
        "assembling-machine-1", "transport-belt" } do
        local proto = prototypes.recipe[name]
        local mine = force.recipes[name]
        local theirs = game.forces.Nauvis.recipes[name]
        log(string.format("PROBE recipe %-22s prototype.enabled=%s TradeCo.enabled=%s Nauvis.enabled=%s",
            name, tostring(proto and proto.enabled),
            tostring(mine and mine.enabled), tostring(theirs and theirs.enabled)))
    end
    for _, tech in ipairs { "automation", "electronics", "steam-power", "solar-energy",
        "electric-energy-distribution-1", "electric-energy-accumulators" } do
        local t = game.forces.Nauvis.technologies[tech]
        log("PROBE nauvis tech " .. tech .. " researched=" .. tostring(t and t.researched))
    end

    local allowed = item_filter.get_allowed_items(force)
    local buildings = 0
    for _, entry in ipairs(allowed) do
        if item_filter.is_building(entry.name) then buildings = buildings + 1 end
    end
    log("PROBE tradeable items: " .. #allowed .. " of which buildings: " .. buildings)

    -- Every option's bill, and whether a company force could ever supply it.
    for _, option in ipairs(nauvis_expansion.OPTIONS) do
        local blocked = {}
        for _, entry in ipairs(nauvis_expansion.cost(option.key)) do
            if not item_filter.is_item_allowed(entry.name, force) then
                blocked[#blocked + 1] = entry.name
            end
        end
        log("PROBE bill " .. option.key .. ": "
            .. (#blocked == 0 and "all supplyable" or ("BLOCKED " .. table.concat(blocked, " "))))
    end

    -- Sell Nauvis exactly what a solar field costs -- nothing like TARGET_STOCK --
    -- and see whether the expansion funds and asks for a site.
    nauvis_expansion.init()
    nauvis_expansion.set_target("solar_field")
    for _, entry in ipairs(nauvis_expansion.cost("solar_field")) do
        stock.set(entry.name, entry.count)
        log(string.format("PROBE sold Nauvis %d %s", entry.count, entry.name))
    end

    nauvis_expansion.process()
    local rows = {}
    for _, row in ipairs(nauvis_expansion.remaining("solar_field")) do
        rows[#rows + 1] = string.format("%s %d/%d", row.name, row.have, row.need)
    end
    log("PROBE after one pass: " .. table.concat(rows, " "))
    log("PROBE awaiting site: " .. tostring(nauvis_expansion.awaiting_site())
        .. " request=" .. tostring((nauvis_siting.pending() or {}).shape))

    -- Labs: craftable and tradeable so Nauvis can buy a lab district, but still
    -- unusable -- block_lab destroys and refunds one the moment a company builds
    -- it, which is where the research monopoly actually lives.
    local lab_recipe = force.recipes["lab"]
    log("PROBE lab recipe enabled=" .. tostring(lab_recipe and lab_recipe.enabled)
        .. " tradeable=" .. tostring(item_filter.is_item_allowed("lab", force))
        .. " science pack tradeable=" .. tostring(item_filter.is_item_allowed("automation-science-pack", force)))
    local surface = game.surfaces["nauvis"]
    local planted = surface.create_entity { name = "lab", position = { 60, 60 }, force = force }
    local blocked = planted and research.block_lab(planted, nil)
    log("PROBE company lab blocked=" .. tostring(blocked)
        .. " survives=" .. tostring(planted and planted.valid))

    -- Clear the site request the solar field just opened, or the next one cannot
    -- be filed and the result reads as "unfunded" when it is only "queued".
    storage.nauvis_siting.requests = {}
    nauvis_expansion.finish("solar_field")

    nauvis_expansion.set_target("automation_science")
    for _, entry in ipairs(nauvis_expansion.cost("automation_science")) do
        stock.set(entry.name, entry.count)
    end
    nauvis_expansion.process()
    log("PROBE automation_science funded from bare cost: "
        .. tostring(nauvis_expansion.awaiting_site()))

    -- And a non-building line still has to clear the full reserve, so the
    -- exemption really is scoped to machines.
    storage.nauvis_siting.requests = {}
    nauvis_expansion.finish("automation_science")
    stock.set("iron-plate", 50)
    log("PROBE reserve iron-plate=" .. tostring(not item_filter.is_building("iron-plate"))
        .. " (spendable at 50 held: "
        .. math.max(0, 50 - stock.TARGET_STOCK) .. ")")
end

return M
