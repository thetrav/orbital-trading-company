-- Rotating an otc-supply-belt must leave it an exit, keep feeding items, and
-- carry its shape_config tag and supply registration across the rebuild.
local shape_config = require("scripts.shape_config")
local supply_belts = require("scripts.supply_belts")
local stock = require("scripts.stock")

local M = {}

local ORIGIN = { x = 700, y = 700 }

local function describe(label, entity)
    if not (entity and entity.valid) then
        log("PROBE " .. label .. ": INVALID")
        return
    end
    log(string.format("PROBE %-20s belt_to_ground=%s unit=%s dir=%s",
        label, tostring(entity.belt_to_ground_type),
        tostring(entity.unit_number), tostring(entity.direction)))
end

local function registered(unit_number)
    local data = storage.supply_belts and storage.supply_belts[unit_number]
    if not data then return "NONE" end
    return tostring(data.left) .. "/" .. tostring(data.right)
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks(ORIGIN, 3)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for dx = -2, 6 do
        for dy = -2, 6 do
            tiles[#tiles + 1] = { name = "refined-concrete", position = { ORIGIN.x + dx, ORIGIN.y + dy } }
        end
    end
    surface.set_tiles(tiles, true)
    shape_config.init()
    supply_belts.init()
    stock.init()
    stock.add("copper-plate", 200)

    local belt = surface.create_entity {
        name = "otc-supply-belt", position = { ORIGIN.x + 0.5, ORIGIN.y + 0.5 },
        direction = 4, type = "output", force = "player",
    }
    shape_config.set(belt, "supply", { left = "copper-plate" })
    supply_belts.register_supply(belt, "copper-plate", nil)
    describe("created", belt)
    log("PROBE registered: " .. registered(belt.unit_number))

    -- What a player pressing R does.
    belt.rotate()
    describe("player rotated", belt)

    local old = belt.unit_number
    local rebuilt = supply_belts.enforce_exit(belt)
    if rebuilt then shape_config.migrate(old, rebuilt) end
    describe("after enforce", rebuilt)
    log("PROBE rebuilt: " .. tostring(rebuilt ~= nil)
        .. " unit_changed=" .. tostring(rebuilt and rebuilt.unit_number ~= old))
    log("PROBE registration carried: " .. registered(rebuilt and rebuilt.unit_number))
    local tag = rebuilt and shape_config.get(rebuilt.unit_number)
    log("PROBE tag carried: " .. tostring(tag and tag.role) .. " item=" .. tostring(tag and tag.item_left))
    log("PROBE old entry cleaned: " .. tostring(registered(old) == "NONE"))

    for _ = 1, 20 do supply_belts.process() end
    local total = 0
    for index = 1, 2 do
        for _, item in pairs(rebuilt.get_transport_line(index).get_contents()) do
            total = total + item.count
        end
    end
    log("PROBE still feeding after rotate: " .. tostring(total > 0) .. " items=" .. total)

    -- A second rotation should flip the exit back, never make an entrance.
    rebuilt.rotate()
    local again = supply_belts.enforce_exit(rebuilt)
    describe("second rotate", again or rebuilt)
end

return M
