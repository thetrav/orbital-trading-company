-- Mayor-chosen sites against the real API. The three things only the game can
-- answer: does the water filter actually see a lake, does a corner pole placed
-- next to the district land on the same electric network as the fixtures, and
-- does a shape built on raw terrain (no grass slab under it) come out whole.
local nauvis_siting = require("scripts.nauvis_siting")
local nauvis_expansion = require("scripts.nauvis_expansion")
local shape_registry = require("scripts.shape_registry")
local shape_def = require("scripts.shape_def")

local M = {}

local function box_at(shape, origin)
    return shape_def.clearance_box(shape_registry.get(shape), origin, 0)
end

local function report(surface, shape, origin, what)
    local ok, reason = nauvis_siting.validate(surface, box_at(shape, origin))
    log(string.format("PROBE validate %s at %d,%d (%s): %s%s",
        shape, origin.x, origin.y, what, tostring(ok), ok and "" or " -- " .. reason))
    return ok
end

local function networks(surface)
    local counts = {}
    for _, post in ipairs(surface.find_entities_filtered {
        name = { "substation", "big-electric-pole", "medium-electric-pole" },
    }) do
        counts[post.electric_network_id] = (counts[post.electric_network_id] or 0) + 1
    end
    local ids = {}
    for id, n in pairs(counts) do ids[#ids + 1] = id .. "(" .. n .. ")" end
    table.sort(ids)
    return table.concat(ids, " ")
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks({ 0, 0 }, 10)
    surface.force_generate_chunk_requests()

    log("PROBE networks before: " .. networks(surface))

    -- A site request has to exist before anything can be placed: the module is
    -- deliberately incapable of building something nobody asked for.
    log("PROBE place with no request: " .. tostring(select(2, nauvis_siting.place(surface, { x = 0, y = 0 }))))

    nauvis_siting.request { shape = "nauvis_mine_iron", label = "Iron mine", tag = "iron_mine" }
    log("PROBE pending: " .. tostring(nauvis_siting.pending().shape))

    -- On top of the compound: something is always built there.
    local wall = surface.find_entities_filtered { name = "otc-platform-wall", limit = 1 }[1]
    log("PROBE a compound wall sits at: " .. (wall
        and string.format("%.0f,%.0f", wall.position.x, wall.position.y) or "MISSING"))
    if wall then
        report(surface, "nauvis_mine_iron",
            { x = math.floor(wall.position.x) - 4, y = math.floor(wall.position.y) - 4 },
            "on the starting room")
    end
    -- Far out in the wild: dry and empty, but nowhere near a pole.
    surface.request_to_generate_chunks({ 400, 400 }, 3)
    surface.force_generate_chunk_requests()
    local dry = surface.find_tiles_filtered {
        area = { { 380, 380 }, { 420, 420 } }, name = { "grass-1", "grass-2", "grass-3", "grass-4" }, limit = 1,
    }[1]
    if dry then
        report(surface, "nauvis_mine_iron",
            { x = math.floor(dry.position.x), y = math.floor(dry.position.y) }, "off the grid")
    else
        log("PROBE no dry ground out at 400,400")
    end

    local water = surface.find_tiles_filtered {
        area = { { -300, -300 }, { 300, 300 } }, name = { "water", "deepwater" }, limit = 1,
    }[1]
    if water then
        report(surface, "nauvis_mine_iron",
            { x = math.floor(water.position.x) - 4, y = math.floor(water.position.y) - 4 }, "in a lake")
    else
        log("PROBE no water within 300 tiles to test")
    end

    -- Just off the west edge of the district's first row, which is where a
    -- mayor would realistically put one: clear ground, one pole away.
    local pole = surface.find_entities_filtered {
        name = "big-electric-pole", force = "Nauvis", limit = 1,
    }[1]
    if not pole then
        log("PROBE no district pole to build next to")
        return
    end
    log(string.format("PROBE nearest grid pole: %.0f,%.0f", pole.position.x, pole.position.y))

    local origin
    for distance = 4, 40, 2 do
        local candidate = { x = math.floor(pole.position.x) - 9 - distance, y = math.floor(pole.position.y) }
        if nauvis_siting.validate(surface, box_at("nauvis_mine_iron", candidate)) then
            origin = candidate
            break
        end
    end
    if not origin then
        log("PROBE found no legal site west of the district")
        return
    end
    report(surface, "nauvis_mine_iron", origin, "west of the district")

    local ok, reason = nauvis_siting.place(surface, origin)
    log("PROBE place: " .. tostring(ok) .. (reason and (" -- " .. reason) or ""))
    log("PROBE pending after place: " .. tostring(nauvis_siting.pending()))

    local drills = surface.count_entities_filtered {
        area = { { origin.x - 2, origin.y - 2 }, { origin.x + 14, origin.y + 14 } },
        name = "electric-mining-drill",
    }
    log("PROBE drills on the new site: " .. drills)
    log("PROBE networks after: " .. networks(surface))

    -- The expansion module picks the result up on its next second and books it.
    nauvis_expansion.set_target("iron_mine")
    local built_before = nauvis_expansion.built_count("iron_mine")
    nauvis_expansion.process()
    log(string.format("PROBE iron_mine built %d -> %d, target now %s",
        built_before, nauvis_expansion.built_count("iron_mine"),
        tostring(nauvis_expansion.target())))
end

return M
