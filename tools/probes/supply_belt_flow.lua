-- Can items placed on an unpaired otc-supply-belt actually move off it, and can
-- an inserter pick them up? Compares our prototype against a vanilla unpaired
-- underground belt and a plain transport belt.
--
-- Entities are looked up by position rather than kept in a local, because
-- on_init does not run on --load-game and the tick report has to work there.
local M = {}

local ORIGIN = { x = 300, y = 300 }
local ROW_GAP = 4

local CASES = {
    { label = "otc-supply(output)", name = "otc-supply-belt", belt_type = "output", row = 0 },
    { label = "vanilla-ug(output)", name = "underground-belt", belt_type = "output", row = 1 },
    { label = "otc-supply(input)", name = "otc-supply-belt", belt_type = "input", row = 2 },
    { label = "plain-transport", name = "transport-belt", row = 3 },
}

local function status_name(status)
    for name, value in pairs(defines.entity_status) do
        if value == status then return name end
    end
    return "unknown(" .. tostring(status) .. ")"
end

local function spots(case)
    local y = ORIGIN.y + case.row * ROW_GAP
    local x = ORIGIN.x
    return {
        belt = { x + 0.5, y + 0.5 },
        downstream = { x + 1.5, y + 0.5 },
        inserter = { x + 0.5, y - 0.5 },
        chest = { x + 0.5, y - 1.5 },
        pole = { x + 2.5, y - 0.5 },
        power = { x + 3.5, y - 1.5 },
    }
end

local function lay_tiles(surface)
    local tiles = {}
    for dx = -4, 12 do
        for dy = -4, ROW_GAP * #CASES do
            tiles[#tiles + 1] = {
                name = "refined-concrete",
                position = { ORIGIN.x + dx, ORIGIN.y + dy },
            }
        end
    end
    surface.set_tiles(tiles, true)
end

--- One test row: the belt under test, a transport belt downstream of it, and an
--- inserter above it feeding a chest. Whichever of those two gains an item
--- tells us the belt is behaving like a real belt exit.
local function build_case(surface, case)
    local at = spots(case)
    local args = { name = case.name, position = at.belt, direction = 4, force = "player" }
    if case.belt_type then args.type = case.belt_type end
    local ok, belt = pcall(surface.create_entity, args)
    if not ok or not belt then
        log("PROBE " .. case.label .. ": create FAILED " .. tostring(belt))
        return
    end

    surface.create_entity {
        name = "transport-belt", position = at.downstream, direction = 4, force = "player",
    }
    -- Inserter direction points at the pickup, so south picks off the belt below it.
    surface.create_entity {
        name = "inserter", position = at.inserter, direction = 8, force = "player",
    }
    surface.create_entity { name = "steel-chest", position = at.chest, force = "player" }
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

local function report(surface, case, label)
    local at = spots(case)
    local belt = surface.find_entity(case.name, at.belt)
    local downstream = surface.find_entity("transport-belt", at.downstream)
    local inserter = surface.find_entity("inserter", at.inserter)
    local chest = surface.find_entity("steel-chest", at.chest)

    local chest_count = 0
    if chest then
        chest_count = chest.get_inventory(defines.inventory.chest).get_item_count("iron-plate")
    end
    log(string.format("PROBE %-20s %-8s on_belt=%2d downstream=%2d chest=%2d inserter=%s",
        case.label, label, count_lines(belt), count_lines(downstream), chest_count,
        inserter and status_name(inserter.status) or "GONE"))
end

local function seed(surface, case)
    local belt = surface.find_entity(case.name, spots(case).belt)
    if not belt then
        log("PROBE " .. case.label .. " seed: belt missing")
        return
    end
    local lines = belt.get_max_transport_line_index()
    local inserted = 0
    for index = 1, lines do
        local line = belt.get_transport_line(index)
        for _ = 1, 4 do
            if line.can_insert_at_back() and line.insert_at_back { name = "iron-plate", count = 1 } then
                inserted = inserted + 1
            end
        end
    end
    log(string.format("PROBE %-20s seeded=%d lines=%d", case.label, inserted, lines))
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks(ORIGIN, 3)
    surface.force_generate_chunk_requests()
    lay_tiles(surface)

    log("PROBE linked-belt prototype exists: " .. tostring(prototypes.entity["linked-belt"] ~= nil))

    for _, case in ipairs(CASES) do
        build_case(surface, case)
        seed(surface, case)
        report(surface, case, "t0")
    end
end

script.on_nth_tick(120, function()
    if game.tick == 0 then return end
    local surface = game.surfaces["nauvis"]
    -- Re-seed on the first load tick: --load-game starts from the created map,
    -- where the init seeding already happened, but a fresh run needs items.
    for _, case in ipairs(CASES) do
        report(surface, case, "tick" .. game.tick)
    end
    if game.tick >= 360 then script.on_nth_tick(120, nil) end
end)

return M
