-- Nauvis as a normal world: does terrain generate, do ore and oil stay away,
-- and does the district still come out as one rectangle on one power network
-- once the fixtures, a company's facilities and a voted expansion have all
-- claimed slots from the same grid?
local district = require("scripts.district")
local company_facilities = require("scripts.company_facilities")
local nauvis_expansion = require("scripts.nauvis_expansion")
local nauvis_siting = require("scripts.nauvis_siting")
local shape_registry = require("scripts.shape_registry")
local shape_def = require("scripts.shape_def")

local M = {}

local function count(surface, filter)
    return surface.count_entities_filtered(filter)
end

function M.run()
    local surface = game.surfaces["nauvis"]
    surface.request_to_generate_chunks({ 0, -32 }, 6)
    surface.force_generate_chunk_requests()

    for _, n in ipairs { 0, 1, 2, 3, 4 } do
        local centre = district.module_centre(n)
        log(string.format("PROBE module %d -> %d,%d", n, centre.x, centre.y))
    end

    -- Well away from anything otc places, so whatever is here is worldgen.
    local wild = { { 200, -200 }, { 400, 0 } }
    log("PROBE wild resources: " .. count(surface, { area = wild, type = "resource" }))
    log("PROBE wild trees: " .. count(surface, { area = wild, type = "tree" }))
    log("PROBE wild rocks: " .. count(surface, { area = wild, type = "simple-entity" }))
    log("PROBE enemies anywhere: " .. count(surface, { force = "enemy" }))

    local room = surface.find_entities_filtered { name = "lab", force = "Nauvis" }[1]
    log("PROBE first lab at: " .. (room
        and string.format("%.0f,%.0f", room.position.x, room.position.y) or "MISSING"))

    local placed = {}
    for _, slot in ipairs(storage.district.slots) do
        placed[#placed + 1] = string.format("%s@%d,%d", slot.shape, slot.x, slot.y)
    end
    log("PROBE cells taken by fixtures: " .. table.concat(placed, " "))
    local poles = 0
    for _ in pairs(storage.district.poles) do poles = poles + 1 end
    local zones = {}
    for name, zone in pairs(storage.district.zones) do
        zones[#zones + 1] = name .. "=" .. zone.next
    end
    table.sort(zones)
    log("PROBE modules used: " .. table.concat(zones, " ") .. " poles: " .. poles)
    log("PROBE drills: " .. count(surface, { name = "electric-mining-drill" })
        .. " stone ore: " .. count(surface, { name = "stone", type = "resource" }))

    game.create_force("ProbeCo")
    local sites = company_facilities.ensure_for("ProbeCo")
    for _, site in ipairs(sites or {}) do
        log(string.format("PROBE company %s at %d,%d", site.shape, site.x, site.y))
    end
    local silo = surface.find_entities_filtered { name = "rocket-silo" }[1]
    log("PROBE silo force: " .. (silo and silo.force.name or "MISSING"))
    log("PROBE gate computers on nauvis: " .. count(surface, { name = "otc-gate-computer" }))

    -- A gate only joins up with walls on its own force, so the launch bay's
    -- gates and walls have to agree.
    local bay = sites and sites[1]
    if bay then
        local area = { { bay.x - 16, bay.y - 16 }, { bay.x + 16, bay.y + 16 } }
        local forces = {}
        for _, name in ipairs { "gate", "otc-platform-wall" } do
            for _, e in ipairs(surface.find_entities_filtered { area = area, name = name }) do
                forces[name .. "=" .. e.force.name] = (forces[name .. "=" .. e.force.name] or 0) + 1
            end
        end
        local parts = {}
        for k, v in pairs(forces) do parts[#parts + 1] = k .. "x" .. v end
        table.sort(parts)
        log("PROBE launch bay forces: " .. table.concat(parts, " "))
    end

    -- Orbit must be void, not grass.
    local station = game.surfaces["otc-station-1"]
    if station then
        station.request_to_generate_chunks({ 0, 0 }, 4)
        station.force_generate_chunk_requests()
        local void = station.count_tiles_filtered { area = { { -60, -60 }, { 60, 60 } }, name = "out-of-map" }
        local grass = station.count_tiles_filtered { area = { { -60, -60 }, { 60, 60 } }, name = "grass-1" }
        log("PROBE orbit tiles: out-of-map=" .. void .. " grass-1=" .. grass
            .. " at 50,50=" .. station.get_tile(50, 50).name)
    else
        log("PROBE no station surface")
    end

    -- An expansion is sited by hand now, so the probe plays mayor and hunts for
    -- ground west of the district that the rules accept.
    local field = nauvis_expansion.get_option("solar_field")
    nauvis_siting.request { shape = field.shape, label = field.label, tag = field.key }
    local def = shape_registry.get(field.shape)
    local sited, why = false, "no legal site found"
    for x = -70, -160, -6 do
        local origin = { x = x, y = -30 }
        if nauvis_siting.validate(surface, shape_def.clearance_box(def, origin, 0)) then
            sited, why = nauvis_siting.place(surface, origin)
            why = why or ("at " .. origin.x .. "," .. origin.y)
            break
        end
    end
    log("PROBE solar field sited: " .. tostring(sited) .. " -- " .. why)
    local panels = surface.find_entities_filtered { name = "solar-panel", force = "Nauvis" }
    log("PROBE nauvis solar panels: " .. #panels)

    -- A slot can land in a lake, and the pad is the only thing that would save
    -- it. Does set_tiles actually fill water?
    local water = surface.find_tiles_filtered { area = { { -300, -300 }, { 300, 300 } }, name = "water" }[1]
    if water then
        surface.set_tiles { { name = "refined-concrete", position = water.position } }
        log(string.format("PROBE water at %.0f,%.0f is now %s",
            water.position.x, water.position.y, surface.get_tile(water.position.x, water.position.y).name))
    else
        log("PROBE no water found to test")
    end

    local networks = {}
    for _, post in ipairs(surface.find_entities_filtered {
        name = { "substation", "big-electric-pole" },
    }) do
        local id = post.electric_network_id
        networks[id] = (networks[id] or 0) + 1
    end
    local ids = {}
    for id, n in pairs(networks) do ids[#ids + 1] = id .. "(" .. n .. ")" end
    table.sort(ids)
    log("PROBE pole networks: " .. table.concat(ids, " "))
end

return M
