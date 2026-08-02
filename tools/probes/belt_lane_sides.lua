-- Which transport line index is the screen-TOP (-y) lane, for each belt facing?
--
-- An inserter drops onto the FAR lane of its target belt. Dropping from a chest
-- above the belt (-y) therefore lands every item on the BOTTOM (+y) lane, so
-- whichever line gains items is the bottom one and the other is the top.
local M = {}

local ORIGIN = { x = 500, y = 500 }
local ROW_GAP = 6

local CASES = {
    { label = "belt-faces-east", direction = 4 },
    { label = "belt-faces-west", direction = 12 },
    { label = "belt-faces-north", direction = 0 },
    { label = "belt-faces-south", direction = 8 },
}

local function spots(row)
    local y = ORIGIN.y + row * ROW_GAP
    local x = ORIGIN.x
    return {
        belt = { x + 0.5, y + 0.5 },
        inserter = { x + 0.5, y - 0.5 },
        chest = { x + 0.5, y - 1.5 },
        pole = { x + 2.5, y - 0.5 },
        power = { x + 3.5, y - 1.5 },
    }
end

local function lay_tiles(surface)
    local tiles = {}
    for dx = -4, 8 do
        for dy = -4, ROW_GAP * #CASES do
            tiles[#tiles + 1] = {
                name = "refined-concrete",
                position = { ORIGIN.x + dx, ORIGIN.y + dy },
            }
        end
    end
    surface.set_tiles(tiles, true)
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks(ORIGIN, 3)
    surface.force_generate_chunk_requests()
    lay_tiles(surface)

    log(string.format("PROBE defines left_line=%s right_line=%s",
        tostring(defines.transport_line.left_line),
        tostring(defines.transport_line.right_line)))

    for row, case in ipairs(CASES) do
        local at = spots(row)
        surface.create_entity {
            name = "transport-belt", position = at.belt,
            direction = case.direction, force = "player",
        }
        -- Inserter direction points at the pickup: north picks from the chest
        -- above it and drops south onto the belt.
        surface.create_entity {
            name = "inserter", position = at.inserter, direction = 0, force = "player",
        }
        local chest = surface.create_entity {
            name = "steel-chest", position = at.chest, force = "player",
        }
        if chest then
            chest.get_inventory(defines.inventory.chest).insert { name = "iron-plate", count = 50 }
        end
        surface.create_entity { name = "small-electric-pole", position = at.pole, force = "player" }
        local power = surface.create_entity {
            name = "electric-energy-interface", position = at.power, force = "player",
        }
        if power then
            power.power_production = 100000
            power.electric_buffer_size = 1000000
            power.energy = 1000000
        end
    end
end

script.on_nth_tick(180, function()
    if game.tick == 0 then return end
    local surface = game.surfaces["nauvis"]
    for row, case in ipairs(CASES) do
        local belt = surface.find_entity("transport-belt", spots(row).belt)
        if belt then
            local counts, bottom = {}, nil
            for index = 1, belt.get_max_transport_line_index() do
                local total = 0
                for _, item in pairs(belt.get_transport_line(index).get_contents()) do
                    total = total + item.count
                end
                counts[#counts + 1] = "line" .. index .. "=" .. total
                if total > 0 then bottom = index end
            end
            log(string.format("PROBE %-18s %s -> BOTTOM lane is line%s, TOP lane is line%s",
                case.label, table.concat(counts, " "),
                tostring(bottom), bottom and tostring(3 - bottom) or "?"))
        end
    end
    script.on_nth_tick(180, nil)
end)

return M
