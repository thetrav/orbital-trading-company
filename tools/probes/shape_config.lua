-- Does the shape config tool tag per-lane items, label them by resolved screen
-- side, survive a capture, and feed only the lanes that were set?
local shape_config = require("scripts.shape_config")
local shape_capture = require("scripts.shape_capture")
local shape_io = require("scripts.shape_io")
local supply_belts = require("scripts.supply_belts")
local stock = require("scripts.stock")

local M = {}

local ORIGIN = { x = 600, y = 600 }

local function lay_tiles(surface)
    local tiles = {}
    for dx = -4, 8 do
        for dy = -4, 8 do
            tiles[#tiles + 1] = {
                name = "refined-concrete",
                position = { ORIGIN.x + dx, ORIGIN.y + dy },
            }
        end
    end
    surface.set_tiles(tiles, true)
end

local function label_of(entry)
    if not (entry and entry.label and entry.label.valid) then return "NO LABEL" end
    local ok, text = pcall(function() return entry.label.text end)
    return ok and tostring(text) or "READ FAILED"
end

local function lane_counts(entity)
    local out = {}
    for index = 1, 2 do
        local total = 0
        for _, item in pairs(entity.get_transport_line(index).get_contents()) do
            total = total + item.count
        end
        out[#out + 1] = "line" .. index .. "=" .. total
    end
    return table.concat(out, " ")
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks(ORIGIN, 3)
    surface.force_generate_chunk_requests()
    lay_tiles(surface)
    shape_config.init()

    -- East-facing: line 1 is the TOP lane. Copper on top only, bottom left
    -- clear for an assembler's gear output.
    local copper = surface.create_entity {
        name = "otc-supply-belt", position = { ORIGIN.x + 0.5, ORIGIN.y + 0.5 },
        direction = 4, type = "input", force = "player",
    }
    -- South-facing: iron on both lanes.
    local iron = surface.create_entity {
        name = "otc-supply-belt", position = { ORIGIN.x + 2.5, ORIGIN.y + 0.5 },
        direction = 8, type = "input", force = "player",
    }
    if not (copper and iron) then
        log("PROBE FAIL: could not create belts")
        return
    end

    shape_config.set(copper, "supply", { left = "copper-plate" })
    shape_config.set(iron, "supply", { left = "iron-plate", right = "iron-plate" })

    log("PROBE copper label: " .. label_of(shape_config.get(copper.unit_number)))
    log("PROBE iron   label: " .. label_of(shape_config.get(iron.unit_number)))

    local area = {
        left_top = { x = ORIGIN.x - 1, y = ORIGIN.y - 1 },
        right_bottom = { x = ORIGIN.x + 4, y = ORIGIN.y + 2 },
    }
    local ok, def = pcall(shape_capture.capture_area, surface, area, "probe_lanes",
        { entities_only = true })
    if not ok then
        log("PROBE FAIL capture: " .. tostring(def))
        return
    end
    for line in shape_io.serialize(def):gmatch("[^\n]+") do
        if line:find("otc%-supply%-belt") or line:find("item") then
            log("PROBE serialized:" .. line)
        end
    end

    -- Now drive the real supply loop and see which lanes actually get fed.
    supply_belts.init()
    stock.init()
    stock.add("copper-plate", 500)
    stock.add("iron-plate", 500)
    for _, e in ipairs { copper, iron } do
        local entry = shape_config.get(e.unit_number)
        supply_belts.register_from_def(e, {
            item_left = entry.item_left, item_right = entry.item_right,
        })
    end
    for _ = 1, 30 do supply_belts.process() end
    log("PROBE copper belt fed: " .. lane_counts(copper) .. "  (expect line2=0)")
    log("PROBE iron   belt fed: " .. lane_counts(iron) .. "  (expect both >0)")
end

return M
