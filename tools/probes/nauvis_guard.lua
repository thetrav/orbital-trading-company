-- Does the guard tell Nauvis's property apart from the fixtures players are
-- meant to use, and does it undo a mine?
local nauvis_guard = require("scripts.nauvis_guard")
local platform = require("scripts.platform")

local M = {}

local ORIGIN = { x = 800, y = 800 }

local function fake_player(force_name)
    return { valid = true, force = { name = force_name } }
end

local function fake_entity(name, force_name, surface)
    return {
        valid = true, name = name, force = { name = force_name },
        surface = surface, unit_number = 1,
    }
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks(ORIGIN, 3)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for dx = -2, 8 do
        for dy = -2, 8 do
            tiles[#tiles + 1] = { name = "refined-concrete", position = { ORIGIN.x + dx, ORIGIN.y + dy } }
        end
    end
    surface.set_tiles(tiles, true)
    nauvis_guard.init()

    local outsider = fake_player("Default")
    local insider = fake_player("Nauvis")

    local cases = {
        { "assembling-machine-1", "Nauvis", outsider, true, "outsider vs nauvis machine" },
        { "assembling-machine-1", "Nauvis", insider, false, "nauvis player vs nauvis machine" },
        { "assembling-machine-1", "Default", outsider, false, "outsider vs own machine" },
        { "otc-gate-computer", "Nauvis", outsider, false, "gate computer stays usable" },
        { "otc-company-monitor", "Nauvis", outsider, false, "company monitor stays usable" },
    }
    for _, case in ipairs(cases) do
        local got = nauvis_guard.is_protected(fake_entity(case[1], case[2], surface), case[3])
        log(string.format("PROBE %-34s protected=%s want=%s %s",
            case[5], tostring(got), tostring(case[4]), got == case[4] and "OK" or "MISMATCH"))
    end

    -- A real mine, undone: the ore must come back and the loot must vanish.
    local ore = surface.create_entity {
        name = "iron-ore", position = { ORIGIN.x + 2.5, ORIGIN.y + 2.5 }, amount = 500,
    }
    log("PROBE ore created: " .. tostring(ore ~= nil))

    local buffer = game.create_inventory(4)
    buffer.insert { name = "iron-ore", count = 7 }
    storage.nauvis_guard.mined[99] = {
        name = "iron-ore", position = { x = ORIGIN.x + 2.5, y = ORIGIN.y + 2.5 },
        surface = "nauvis", force = "neutral", amount = 500,
    }
    if ore then ore.destroy() end
    log("PROBE ore gone before restore: "
        .. tostring(surface.find_entity("iron-ore", { ORIGIN.x + 2.5, ORIGIN.y + 2.5 }) == nil))

    nauvis_guard.on_mined { player_index = 99, buffer = buffer }
    local restored = surface.find_entity("iron-ore", { ORIGIN.x + 2.5, ORIGIN.y + 2.5 })
    log("PROBE ore restored: " .. tostring(restored ~= nil)
        .. " amount=" .. tostring(restored and restored.amount))
    log("PROBE loot buffer emptied: " .. tostring(buffer.is_empty()))
    buffer.destroy()

    -- Hardening is what stops a super-force build, which nothing can undo.
    local at = { x = 900, y = 900 }
    surface.request_to_generate_chunks(at, 4)
    surface.force_generate_chunk_requests()
    local placed, place_err = pcall(platform.build_shape, surface, "red_flask_factory", at, "Nauvis")
    log("PROBE build_shape ok=" .. tostring(placed) .. (placed and "" or (" err=" .. tostring(place_err))))
    if not placed then return end

    local built = surface.find_entities_filtered {
        area = {
            left_top = { x = at.x, y = at.y },
            right_bottom = { x = at.x + 22, y = at.y + 14 },
        },
        force = "Nauvis",
    }
    local soft, total = 0, 0
    local exempt = 0
    for _, entity in ipairs(built) do
        if entity.valid and entity.unit_number then
            if entity.name == "otc-gate-computer" or entity.name == "otc-company-monitor" then
                exempt = exempt + 1
            else
                total = total + 1
                if entity.minable or entity.destructible then soft = soft + 1 end
            end
        end
    end
    log(string.format("PROBE hardened %d/%d nauvis entities (%d still soft, %d exempt)",
        total - soft, total, soft, exempt))
end

return M
