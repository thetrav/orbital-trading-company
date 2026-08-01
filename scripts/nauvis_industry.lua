local supply_belts = require("scripts.supply_belts")
local nauvis = require("scripts.nauvis")

local M = {}

local ROOM = { left = -12, right = 12, top = -26, bottom = -10 }
local MINE_BLOCKS = {
    { ore = "iron-ore", x = -120, y = -4 },
    { ore = "copper-ore", x = -105, y = -4 },
    { ore = "coal", x = -90, y = -4 },
}
local MINE_ORE_AMOUNT = 2000000000
local MINE_BLOCK_SIZE = 8

local function ground_tile()
    if prototypes.tile["grass-1"] then return "grass-1" end
    return "otc-platform"
end

local function set_tiles(surface, name, left, top, right, bottom)
    local tiles = {}
    for x = left, right do
        for y = top, bottom do
            table.insert(tiles, { name = name, position = { x, y } })
        end
    end
    surface.set_tiles(tiles, true)
end

local function fixed(entity)
    if entity then
        entity.minable = false
        entity.destructible = false
    end
    return entity
end

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
    return fixed(surface.create_entity(args))
end

local function tile_center(x, y)
    return { x + 0.5, y + 0.5 }
end

local function build_production_room(surface)
    set_tiles(surface, "otc-platform", ROOM.left - 1, ROOM.top - 1, ROOM.right + 1, ROOM.bottom + 1)
    surface.destroy_decoratives {
        area = { { ROOM.left - 1, ROOM.top - 1 }, { ROOM.right + 1, ROOM.bottom + 1 } },
    }

    for x = ROOM.left - 1, ROOM.right + 1 do
        for y = ROOM.top - 1, ROOM.bottom + 1 do
            local on_edge = x == ROOM.left - 1 or x == ROOM.right + 1
                or y == ROOM.top - 1 or y == ROOM.bottom + 1
            if on_edge and not surface.find_entity("otc-platform-wall", tile_center(x, y)) then
                place(surface, "otc-platform-wall", tile_center(x, y))
            end
        end
    end

    for _, x in ipairs { -11, -7, -3, 1, 5, 9 } do
        place(surface, "solar-panel", tile_center(x, -25))
    end
    for _, x in ipairs { -11, -7 } do
        place(surface, "solar-panel", tile_center(x, -22))
    end
    for _, x in ipairs { -4, -2, 0, 2, 4, 6, 8 } do
        place(surface, "accumulator", { x + 1, -22 })
    end
    for _, x in ipairs { -9, 0, 9 } do
        place(surface, "substation", { x, -18 })
    end

    local gear_assembler = place(surface, "assembling-machine-1", { -3.5, -14.5 })
    if gear_assembler then gear_assembler.set_recipe("iron-gear-wheel") end
    local science_assembler = place(surface, "assembling-machine-1", { 0.5, -14.5 })
    if science_assembler then science_assembler.set_recipe("automation-science-pack") end
    local lab = place(surface, "lab", { 0.5, -10.5 })

    place(surface, supply_belts.SUPPLY_NAME, tile_center(-8, -15),
        defines.direction.east, { type = "output" })
    local iron_feed = place(surface, "transport-belt", tile_center(-7, -15), defines.direction.east)
    supply_belts.register_supply(iron_feed, "iron-plate", "iron-plate")

    place(surface, supply_belts.SUPPLY_NAME, tile_center(4, -15),
        defines.direction.west, { type = "output" })
    local copper_feed = place(surface, "transport-belt", tile_center(3, -15), defines.direction.west)
    supply_belts.register_supply(copper_feed, "copper-plate", "copper-plate")

    place(surface, "inserter", tile_center(-6, -15), defines.direction.west)
    place(surface, "inserter", tile_center(-2, -15), defines.direction.west)
    place(surface, "inserter", tile_center(2, -15), defines.direction.east)
    place(surface, "inserter", tile_center(0, -13), defines.direction.north)

    return lab ~= nil
end

local function build_mine_block(surface, block)
    local left, top = block.x, block.y
    local right, bottom = left + MINE_BLOCK_SIZE - 1, top + MINE_BLOCK_SIZE - 1
    set_tiles(surface, ground_tile(), left - 2, top - 2, right + 2, bottom + 10)
    surface.destroy_decoratives { area = { { left - 2, top - 2 }, { right + 2, bottom + 10 } } }

    for x = left, right do
        for y = top, bottom do
            surface.create_entity {
                name = block.ore,
                position = tile_center(x, y),
                amount = MINE_ORE_AMOUNT,
            }
        end
    end

    for _, offset in ipairs { 1, 5 } do
        local drill = place(surface, "electric-mining-drill",
            tile_center(left + offset, top + 1), defines.direction.south)
        if drill then
            local drop = drill.drop_position
            local intake = place(surface, supply_belts.INTAKE_NAME, drop,
                defines.direction.south, { type = "input" })
            supply_belts.register_intake(intake)
        end
    end

    place(surface, "substation", { right + 2, top + 1 })
    place(surface, "substation", { left - 1, bottom + 6 })
    for _, row in ipairs { bottom + 3, bottom + 7 } do
        for _, offset in ipairs { 0, 3, 6 } do
            place(surface, "solar-panel", tile_center(left + offset, row))
        end
    end
    for _, offset in ipairs { -1, 1, 3, 5, 7 } do
        place(surface, "accumulator", { left + offset + 1, bottom + 10 })
    end
end

local function build_mine(surface)
    for _, block in ipairs(MINE_BLOCKS) do
        build_mine_block(surface, block)
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
