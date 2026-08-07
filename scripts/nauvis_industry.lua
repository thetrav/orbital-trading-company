local supply_belts = require("scripts.supply_belts")
local nauvis = require("scripts.nauvis")
local district = require("scripts.district")
local platform = require("scripts.platform")
local shape_registry = require("scripts.shape_registry")
local shape_def = require("scripts.shape_def")

local M = {}

-- What Nauvis starts the game owning, beyond the compound the players spawn in:
-- one hand-built shape, captured in game rather than packed by code. It holds
-- the four ore patches with their drills, the red flask line, the lab block and
-- a solar field with accumulators, all on one electric network of its own.
--
-- It runs a day/night deficit on purpose -- the accumulators do not carry the
-- labs through the night -- and it has the essentials for red science only as
-- far as players keep it supplied. The warehouse starts **empty** again: what
-- Nauvis has to spend on its first expansion is what these drills dig and what
-- players sell it, not a seeded stockpile.
local START_SHAPE = "nauvis_start"

-- The origin the shape was captured at, so it lands exactly where it was built.
-- Its clearance box runs 39x45 from here, which puts it clear north of the
-- compound with no overlap.
local START_ORIGIN = { x = -14, y = -55 }

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

--- Lay the starting industry down where it was captured. The `stock_belts` hook
--- on the definition is what wires its intake belts into the warehouse, so a
--- re-capture that loses the `hook` line leaves the whole thing mining into
--- nothing.
local function build_start_shape(surface)
    platform.build_shape(surface, START_SHAPE, START_ORIGIN, nauvis.FORCE_NAME)
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

--- The compound plus the starting industry's own footprint, with a margin. The
--- box is derived rather than written down so moving `START_ORIGIN` or
--- recapturing a bigger shape cannot leave half of it in the dark.
local function chart_area()
    local def = shape_registry.get(START_SHAPE)
    local box = def and shape_def.clearance_box(def, START_ORIGIN, 0)
    if not box then return { { -40, -40 }, { 40, 12 } } end
    return {
        { math.min(-40, box[1][1] - 8), math.min(-40, box[1][2] - 8) },
        { math.max(40, box[2][1] + 8), math.max(12, box[2][2] + 8) },
    }
end

local function chart(surface)
    local area = chart_area()
    for _, force in pairs(game.forces) do
        force.chart(surface, area)
        district.chart_all(surface, force)
    end
end

function M.init()
    storage.nauvis_industry = storage.nauvis_industry or { built = false }
end

function M.ensure_built()
    M.init()
    district.init()
    supply_belts.init()
    local surface = game.surfaces["nauvis"]
    if not surface then return end
    if storage.nauvis_industry.built then
        chart(surface)
        return
    end

    seal_top_airlock(surface)
    build_start_shape(surface)
    chart(surface)

    storage.nauvis_industry.built = true
end

return M
