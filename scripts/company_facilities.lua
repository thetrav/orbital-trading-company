local district = require("scripts.district")

local M = {}

-- What a company is given the moment it is founded, rather than made to shop
-- for. Just the launch bay: it is the only way off the planet, so picking it
-- was never a decision, only a delay. A company's ground presence stops there
-- -- everything it actually chooses is built in space, off its own station's
-- airlocks.
local FACILITIES = {
    { shape = "orbital_station", label = "launch bay" },
}

function M.init()
    storage.company_facilities = storage.company_facilities or {}
    return storage.company_facilities
end

function M.get(force_name)
    return M.init()[force_name]
end

--- Claim a district slot per facility and build it owned by the company.
--- Idempotent, so a migration can call it for companies founded before this
--- existed.
function M.ensure_for(force_name)
    local all = M.init()
    if all[force_name] then return all[force_name] end

    local surface = game.surfaces["nauvis"]
    if not surface then return nil end

    local sites = {}
    for _, facility in ipairs(FACILITIES) do
        local centre = district.claim()
        district.build(surface, facility.shape, centre, force_name, { owned_by_force = true })
        sites[#sites + 1] = {
            shape = facility.shape,
            label = facility.label,
            x = centre.x,
            y = centre.y,
        }
    end

    all[force_name] = sites
    return sites
end

return M
