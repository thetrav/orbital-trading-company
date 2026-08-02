-- An unpaired output otc-supply-belt has 4 transport lines but only some of
-- them are the visible, moving side. Seed exactly one line per row and see
-- which ones actually deliver.
local M = {}

local ORIGIN = { x = 400, y = 400 }
local ROW_GAP = 4
local LINES = { 1, 2, 3, 4 }

local function spots(row)
    local y = ORIGIN.y + row * ROW_GAP
    local x = ORIGIN.x
    return {
        belt = { x + 0.5, y + 0.5 },
        downstream = { x + 1.5, y + 0.5 },
        sink = { x + 2.5, y + 0.5 },
    }
end

local function lay_tiles(surface)
    local tiles = {}
    for dx = -4, 12 do
        for dy = -4, ROW_GAP * #LINES do
            tiles[#tiles + 1] = {
                name = "refined-concrete",
                position = { ORIGIN.x + dx, ORIGIN.y + dy },
            }
        end
    end
    surface.set_tiles(tiles, true)
end

local function count_lines(entity)
    if not (entity and entity.valid) then return -1 end
    local total = 0
    for index = 1, entity.get_max_transport_line_index() do
        for _, item in pairs(entity.get_transport_line(index).get_contents()) do
            total = total + item.count
        end
    end
    return total
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks(ORIGIN, 3)
    surface.force_generate_chunk_requests()
    lay_tiles(surface)

    for row, line_index in ipairs(LINES) do
        local at = spots(row)
        local belt = surface.create_entity {
            name = "otc-supply-belt", position = at.belt, direction = 4,
            type = "output", force = "player",
        }
        surface.create_entity {
            name = "transport-belt", position = at.downstream, direction = 4, force = "player",
        }
        surface.create_entity {
            name = "transport-belt", position = at.sink, direction = 4, force = "player",
        }
        if belt then
            local line = belt.get_transport_line(line_index)
            local inserted = 0
            for _ = 1, 3 do
                if line.can_insert_at_back() and line.insert_at_back { name = "iron-plate", count = 1 } then
                    inserted = inserted + 1
                end
            end
            log(string.format("PROBE line%d seeded=%d", line_index, inserted))
        end
    end
end

script.on_nth_tick(180, function()
    if game.tick == 0 then return end
    local surface = game.surfaces["nauvis"]
    for row, line_index in ipairs(LINES) do
        local at = spots(row)
        local belt = surface.find_entity("otc-supply-belt", at.belt)
        local downstream = surface.find_entity("transport-belt", at.downstream)
        local sink = surface.find_entity("transport-belt", at.sink)
        log(string.format("PROBE line%d tick%d stuck_on_belt=%d moved_downstream=%d",
            line_index, game.tick, count_lines(belt),
            count_lines(downstream) + count_lines(sink)))
    end
    script.on_nth_tick(180, nil)
end)

return M
