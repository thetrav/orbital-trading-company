local supply_belts = require("scripts.supply_belts")
local nauvis = require("scripts.nauvis")
local district = require("scripts.district")

local M = {}

-- What Nauvis starts the game owning, placed in named slots of the expansion
-- district rather than at hand-picked coordinates -- the fixtures and the
-- voted expansions share one geography. These fill ring 1 exactly, the
-- rectangle immediately around spawn: the production room takes the slot due
-- north so players can watch it work, the four mine blocks take the rest, and
-- everything anyone builds afterwards grows outward from there.
--
-- `stone_mine` brings no generation of its own -- it used to sit next to the
-- coal block and draw off its grid. The district's substation lattice is one
-- network, so it is still powered wherever its slot lands.
local FIXTURES = {
    { shape = "nauvis_production_room", col = 0, row = -1 },
    { shape = "nauvis_mine_iron", col = -1, row = -1 },
    { shape = "nauvis_mine_copper", col = 1, row = -1 },
    { shape = "nauvis_mine_coal", col = -1, row = 0 },
    { shape = "stone_mine", col = 1, row = 0 },
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

local function build_fixtures(surface)
    for _, fixture in ipairs(FIXTURES) do
        district.build(surface, fixture.shape,
            district.claim_at(fixture.col, fixture.row), nauvis.FORCE_NAME)
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
    for _, force in pairs(game.forces) do
        force.chart(surface, { { -40, -40 }, { 40, 12 } })
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
    build_fixtures(surface)
    chart(surface)

    storage.nauvis_industry.built = true
end

return M
