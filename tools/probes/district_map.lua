-- An ASCII picture of the district, so packing and the power line can be read
-- without a screenshot (headless cannot render one).
--   # pole   = concrete path   o other tile laid by a shape
--   M drill  L lab  A assembler  S solar/accumulator  * any other entity
local company_facilities = require("scripts.company_facilities")

local M = {}

local LEFT, RIGHT = -60, 60
local TOP, BOTTOM = -60, 44
local STEP = 2

local function glyph(surface, x, y)
    local area = { { x, y }, { x + STEP, y + STEP } }
    local by_name = {
        ["big-electric-pole"] = "#",
        ["electric-mining-drill"] = "M",
        lab = "L",
        ["solar-panel"] = "S",
        accumulator = "S",
        substation = "+",
    }
    for _, entity in ipairs(surface.find_entities_filtered { area = area }) do
        local mark = by_name[entity.name]
        if mark then return mark end
    end
    if surface.count_entities_filtered { area = area, type = "assembling-machine" } > 0 then
        return "A"
    end
    if surface.count_entities_filtered { area = area, type = { "transport-belt", "inserter" } } > 0 then
        return "*"
    end
    local tile = surface.get_tile(x, y).name
    if tile == "concrete" then return "=" end
    if tile == "refined-concrete" or tile == "refined-hazard-concrete-left" then return "o" end
    if tile:match("^otc") then return "o" end
    local grass = tile:match("^grass%-(%d)$")
    if grass then return grass end
    return "."
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks({ 0, 0 }, 4)
    surface.force_generate_chunk_requests()

    -- A company so the picture shows the south zone as well as the state's own.
    game.create_force("MapCo")
    company_facilities.ensure_for("MapCo")
    for y = TOP, BOTTOM, STEP do
        local row = {}
        for x = LEFT, RIGHT, STEP do
            row[#row + 1] = glyph(surface, x, y)
        end
        log(string.format("PROBE %4d %s", y, table.concat(row)))
    end
end

return M
