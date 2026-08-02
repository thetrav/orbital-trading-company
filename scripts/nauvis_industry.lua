local supply_belts = require("scripts.supply_belts")
local nauvis = require("scripts.nauvis")
local platform = require("scripts.platform")

local M = {}

-- Geometry lives in the captured shape definitions; see README.md
-- "Capturing shapes" to change any of this from inside the game.
local MINE_BLOCKS = {
    { shape = "nauvis_mine_iron", x = -120, y = -4 },
    { shape = "nauvis_mine_copper", x = -105, y = -4 },
    { shape = "nauvis_mine_coal", x = -90, y = -4 },
    { shape = "stone_mine", x = -75, y = -4 },
}

local function place(surface, name, position, direction, extra)
    local args = {
        name = name,
        position = position,
        force = nauvis.FORCE_NAME,
        create_build_effect_smoke = false,
    }
    if direction then args.direction = direction end
    for key, value in pairs(extra or {}) do
        args[key] = value
    end
    local entity = surface.create_entity(args)
    if entity then
        entity.minable = false
        entity.destructible = false
    end
    return entity
end

local function tile_center(x, y)
    return { x + 0.5, y + 0.5 }
end

local function build_production_room(surface)
    platform.build_shape(surface, "nauvis_production_room", { x = 0, y = 0 }, nauvis.FORCE_NAME)
end

local function build_mine(surface)
    for _, block in ipairs(MINE_BLOCKS) do
        platform.build_shape(surface, block.shape, { x = block.x, y = block.y }, nauvis.FORCE_NAME)
    end
end

local function seal_top_airlock(surface)
    for _, pos in ipairs { { 0, -6 }, { 0, -7 }, { 1, -7 }, { -1, -7 } } do
        for _, entity in ipairs(surface.find_entities_filtered { area = {
            { pos[1], pos[2] }, { pos[1] + 1, pos[2] + 1 },
        } }) do
            if entity.valid and (entity.name == "gate" or entity.name == "otc-gate-computer") then
                if storage.gates_by_id then
                    storage.gates_by_id[entity.unit_number] = nil
                end
                entity.destroy()
            end
        end
    end
    if storage.gates then
        storage.gates[surface.name .. ":0,-6"] = nil
    end
    for _, pos in ipairs { { 0, -6 } } do
        if not surface.find_entity("otc-platform-wall", tile_center(pos[1], pos[2])) then
            place(surface, "otc-platform-wall", tile_center(pos[1], pos[2]))
        end
    end
end

local function chart(surface)
    local area = { { -130, -30 }, { 20, 10 } }
    for _, force in pairs(game.forces) do
        force.chart(surface, area)
    end
end

function M.init()
    storage.nauvis_industry = storage.nauvis_industry or { built = false }
end

function M.ensure_built()
    M.init()
    supply_belts.init()
    local surface = game.surfaces["nauvis"]
    if not surface then return end
    if storage.nauvis_industry.built then
        chart(surface)
        return
    end

    seal_top_airlock(surface)
    build_production_room(surface)
    build_mine(surface)
    chart(surface)

    storage.nauvis_industry.built = true
end

return M
