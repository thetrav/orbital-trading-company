-- A new game: does the captured `nauvis_start` shape land whole, come out on one
-- electric network, mine into the warehouse through its intake belts, and leave
-- the stock empty at tick 0 rather than seeded?
local stock = require("scripts.stock")
local nauvis_expansion = require("scripts.nauvis_expansion")
local nauvis_siting = require("scripts.nauvis_siting")
local company_facilities = require("scripts.company_facilities")
local shape_registry = require("scripts.shape_registry")
local shape_def = require("scripts.shape_def")

local M = {}

local function box_at(shape, origin)
    return shape_def.clearance_box(shape_registry.get(shape), origin, 0)
end

local function find_site(surface, shape, sy)
    for d = 90, 200, 2 do
        local origin = { x = -d, y = sy * d }
        if nauvis_siting.validate(surface, box_at(shape, origin)) then return origin end
    end
    return nil
end

--- `status` is an enum, and the number alone says nothing.
local function status_name(entity)
    if not entity then return "MISSING" end
    for name, value in pairs(defines.entity_status) do
        if value == entity.status then return name end
    end
    return tostring(entity.status)
end

local function stock_summary()
    local lines = {}
    for item, count in pairs(stock.items()) do lines[#lines + 1] = item .. "=" .. count end
    table.sort(lines)
    return #lines == 0 and "(empty)" or table.concat(lines, " ")
end

-- `run()` is called at the end of on_init, so everything it sees is a world that
-- has not run a tick: every drill reads no_power and no assembler has started.
-- Anything about the industry actually *running* has to wait, so it goes in an
-- on_nth_tick registered here at require time.
script.on_nth_tick(590, function()
    if game.tick == 0 then return end
    local surface = game.surfaces["nauvis"]

    local lab = surface.find_entities_filtered { name = "lab" }[1]
    local drill = surface.find_entities_filtered { name = "electric-mining-drill" }[1]
    local assembler = surface.find_entities_filtered { name = "assembling-machine-1" }[1]
    log(string.format("PROBE @%d lab=%s drill=%s assembler=%s", game.tick,
        status_name(lab), status_name(drill), status_name(assembler)))

    local accumulator = surface.find_entities_filtered { name = "accumulator" }[1]
    if accumulator then
        log(string.format("PROBE @%d accumulator energy=%.0f J", game.tick, accumulator.energy))
    end

    log("PROBE @" .. game.tick .. " stock: " .. stock_summary())
end)

function M.run()
    local surface = game.surfaces["nauvis"]

    for _, name in ipairs { "electric-mining-drill", "lab", "solar-panel", "accumulator",
        "assembling-machine-1", "substation", "otc-supply-belt", "otc-intake-belt" } do
        log("PROBE " .. name .. ": " .. surface.count_entities_filtered { name = name })
    end
    for _, ore in ipairs { "iron-ore", "copper-ore", "coal", "stone" } do
        log("PROBE ore " .. ore .. ": "
            .. surface.count_entities_filtered { name = ore, type = "resource" })
    end

    -- Every drill has to have bound to a patch. A drill built before its ore
    -- reports no_minable_resources forever.
    local bound, unbound = 0, {}
    for _, drill in ipairs(surface.find_entities_filtered { name = "electric-mining-drill" }) do
        if drill.mining_target then
            bound = bound + 1
        else
            unbound[#unbound + 1] = string.format("%.0f,%.0f", drill.position.x, drill.position.y)
        end
    end
    log("PROBE drills bound to ore: " .. bound .. " unbound: "
        .. (#unbound == 0 and "none" or table.concat(unbound, " ")))

    local networks = {}
    for _, post in ipairs(surface.find_entities_filtered {
        name = { "substation", "big-electric-pole", "medium-electric-pole", "small-electric-pole" },
    }) do
        networks[post.electric_network_id] = (networks[post.electric_network_id] or 0) + 1
    end
    local ids = {}
    for id, n in pairs(networks) do ids[#ids + 1] = id .. "(" .. n .. ")" end
    table.sort(ids)
    log("PROBE electric networks: " .. table.concat(ids, " "))

    -- Supply belts with no per-lane item are registered but push nothing.
    local supplies = 0
    for _, data in pairs(storage.supply_belts or {}) do
        supplies = supplies + 1
        log(string.format("PROBE supply belt %s left=%s right=%s",
            data.entity and data.entity.valid and "ok" or "dead",
            tostring(data.left), tostring(data.right)))
    end
    local intakes = 0
    for _ in pairs(storage.intake_belts or {}) do intakes = intakes + 1 end
    log("PROBE registered supply belts: " .. supplies .. " intake belts: " .. intakes)

    log("PROBE stock now: " .. stock_summary())

    -- Nothing is fundable out of an empty warehouse, which is the point: the
    -- first expansion has to be mined or sold to Nauvis first.
    local rows = {}
    for _, entry in ipairs(nauvis_expansion.cost("solar_field")) do
        rows[#rows + 1] = string.format("%s %d/%d",
            entry.name, math.max(0, stock.get(entry.name) - stock.TARGET_STOCK), entry.count)
    end
    log("PROBE solar field affordable: " .. table.concat(rows, " "))

    -- Siting still works around the new starting industry.
    local field = nauvis_expansion.get_option("solar_field")
    nauvis_siting.request { shape = field.shape, label = field.label, tag = field.key }
    local origin = find_site(surface, field.shape, -1)
    local ok, why = false, "no legal site found"
    if origin then ok, why = nauvis_siting.place(surface, origin) end
    log("PROBE public work sited: " .. tostring(ok) .. " -- " .. tostring(why))

    game.create_force("ProbeCo")
    company_facilities.ensure_for("ProbeCo")
    local client = company_facilities.client("ProbeCo")
    local request = nauvis_siting.pending(client)
    local bay = request and find_site(surface, request.shape, 1)
    log("PROBE launch bay sited: "
        .. tostring(bay and nauvis_siting.place(surface, bay, client)))

    -- Does the starting industry overlap the compound or anything sited?
    local box = box_at("nauvis_start", { x = -14, y = -55 })
    log(string.format("PROBE start shape box: %d,%d .. %d,%d (compound is -6,-6 .. 6,6)",
        box[1][1], box[1][2], box[2][1], box[2][2]))
end

return M
