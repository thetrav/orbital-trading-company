-- Does a voted expansion actually land? Builds the first three slots and asks
-- the world the two questions the geometry has to get right: is there floor
-- under everything, and does the substation spine put the whole district on one
-- electric network so a science factory can run off a solar field.
local nauvis_expansion = require("scripts.nauvis_expansion")
local siting = require("scripts.nauvis_siting")
local shape_registry = require("scripts.shape_registry")
local shape_def = require("scripts.shape_def")

local M = {}

local function report_costs()
    for _, option in ipairs(nauvis_expansion.OPTIONS) do
        local parts = {}
        for _, entry in ipairs(nauvis_expansion.cost(option.key)) do
            parts[#parts + 1] = entry.name .. " x" .. entry.count
        end
        log("PROBE cost " .. option.key .. ": " .. table.concat(parts, ", "))
    end
end

local function describe(surface, key)
    local built = surface.find_entities_filtered { force = "Nauvis", name = "substation" }
    local networks = {}
    for _, entity in ipairs(built) do
        local id = entity.electric_network_id
        networks[id] = (networks[id] or 0) + 1
    end
    local ids = {}
    for id, count in pairs(networks) do ids[#ids + 1] = id .. "(" .. count .. ")" end
    table.sort(ids)
    log("PROBE after " .. key .. ": substations=" .. #built .. " networks=" .. table.concat(ids, " "))
end

--- Play mayor: walk west along the district's row until the siting rules accept
--- a footprint. A fixed origin is no good now that the world under it is real
--- terrain with lakes and the district's own ore in it.
local function find_site(surface, shape)
    local def = shape_registry.get(shape)
    for x = -70, -220, -6 do
        for _, y in ipairs { -30, -8, -52 } do
            local origin = { x = x, y = y }
            if siting.validate(surface, shape_def.clearance_box(def, origin, 0)) then
                return origin
            end
        end
    end
    return nil
end

function M.run()
    report_costs()

    local surface = game.surfaces["nauvis"]
    -- Expansions are sited by hand now, so the probe plays mayor: ask for a
    -- site, then hunt for ground west of the compound the rules will accept.
    for _, key in ipairs { "solar_field", "automation_science", "iron_mine" } do
        surface.request_to_generate_chunks({ x = -160, y = -40 }, 6)
        surface.force_generate_chunk_requests()
        local option = nauvis_expansion.get_option(key)
        siting.request { shape = option.shape, label = option.label, tag = key }
        local origin = find_site(surface, option.shape)
        local ok, reason = origin and siting.place(surface, origin)
        log(string.format("PROBE site %s at %s: %s%s", key,
            origin and (origin.x .. "," .. origin.y) or "nowhere legal",
            tostring(ok), reason and (" -- " .. reason) or ""))
        nauvis_expansion.set_target(key)
        nauvis_expansion.process()
        describe(surface, key)
    end

    -- Nauvis is out-of-map everywhere, so a missing pad shows up as tiles that
    -- were never replaced rather than as an error.
    local holes = surface.count_tiles_filtered {
        area = { { -170, -50 }, { -95, -27 } },
        name = "out-of-map",
    }
    log("PROBE out-of-map tiles left inside the district: " .. holes)

    local panels = surface.count_entities_filtered { force = "Nauvis", name = "solar-panel" }
    local assemblers = surface.find_entities_filtered { force = "Nauvis", name = "assembling-machine-1" }
    log("PROBE solar panels on nauvis: " .. panels .. ", assemblers: " .. #assemblers)
end

local function status_name(status)
    for name, value in pairs(defines.entity_status) do
        if value == status then return name end
    end
    return tostring(status)
end

-- on_init sees a world that has not ticked, so power and crafting only mean
-- anything later; see AGENTS.md.
script.on_nth_tick(600, function()
    if game.tick == 0 then return end
    local surface = game.surfaces["nauvis"]
    local assemblers = surface.find_entities_filtered {
        force = "Nauvis", name = "assembling-machine-1", area = { { -170, -50 }, { -95, -27 } },
    }
    log("PROBE district assemblers: " .. #assemblers)
    for i = 1, math.min(3, #assemblers) do
        local a = assemblers[i]
        log(string.format("PROBE assembler at %.0f,%.0f network=%s status=%s",
            a.position.x, a.position.y, tostring(a.electric_network_id), status_name(a.status)))
    end
    local panel = surface.find_entities_filtered {
        force = "Nauvis", name = "solar-panel", area = { { -145, -50 }, { -120, -27 } },
    }[1]
    if panel then
        log("PROBE solar field panel network=" .. tostring(panel.electric_network_id)
            .. " status=" .. status_name(panel.status))
    end
end)

return M
