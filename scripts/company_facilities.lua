local siting = require("scripts.nauvis_siting")

local M = {}

-- What a company is given the moment it is founded, rather than made to shop
-- for. Just the launch bay: it is the only way off the planet, so picking it
-- was never a decision, only a delay. A company's ground presence stops there
-- -- everything it actually chooses is built in space, off its own station's
-- airlocks.
--
-- It is given, but not sited: the company picks its own ground under exactly
-- the rules a public work is held to (dry, empty, within reach of the grid),
-- via `nauvis_siting`. One request is open at a time, so the queue drains a
-- facility per placement.
local FACILITIES = {
    { shape = "orbital_station", label = "launch bay" },
}

-- A company's ground is paved so it reads as the company's rather than as
-- whatever grass the launch bay landed on.
local BORDER_TILE = "stone-path"

--- Each company has its own siting queue, so a request waiting on one company
--- never blocks Nauvis's own works or another company's.
function M.client(force_name)
    return "company:" .. force_name
end

function M.init()
    local all = storage.company_facilities or {}
    -- Facilities used to be packed into the district the moment a company was
    -- founded, so the entry was just the list of what went up.
    for force_name, record in pairs(all) do
        if not record.sites then
            all[force_name] = { queue = {}, sites = record }
        end
    end
    storage.company_facilities = all
    return all
end

function M.get(force_name)
    local record = M.init()[force_name]
    return record and record.sites
end

local function request_next(force_name, record)
    local facility = record.queue[1]
    if not facility then return end
    if siting.pending(M.client(force_name)) then return end
    if siting.request {
        client = M.client(force_name),
        shape = facility.shape,
        label = facility.label,
        force_name = force_name,
        owned_by_force = true,
        sited_by = force_name,
        border = BORDER_TILE,
    } then
        table.remove(record.queue, 1)
    end
end

--- Queue a new company's facilities and open the first site request. Idempotent,
--- so a migration can call it for companies founded before this existed.
function M.ensure_for(force_name)
    local all = M.init()
    local record = all[force_name]
    if record then return record.sites end

    record = { queue = {}, sites = {} }
    for i, facility in ipairs(FACILITIES) do record.queue[i] = facility end
    all[force_name] = record
    request_next(force_name, record)
    return record.sites
end

--- Called once a second: book whatever a company just sited and put the next
--- facility in the queue up for placement.
function M.process()
    for force_name, record in pairs(M.init()) do
        local done = siting.take_completed(M.client(force_name))
        if done then
            record.sites[#record.sites + 1] = {
                shape = done.shape, label = done.label, x = done.x, y = done.y,
            }
            local force = game.forces[force_name]
            if force then
                force.print(string.format("Your %s is built at %d,%d.", done.label, done.x, done.y))
            end
        end
        request_next(force_name, record)
    end
end

return M
