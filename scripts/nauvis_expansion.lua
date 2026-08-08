local stock = require("scripts.stock")
local item_filter = require("scripts.item_filter")
local district = require("scripts.district")
local shape_registry = require("scripts.shape_registry")
local siting = require("scripts.nauvis_siting")

local M = {}

-- What Nauvis can be told to build. Every option is an already-captured shape;
-- the cost is derived from that shape's entities, so recapturing a shape
-- retunes its price automatically.
M.OPTIONS = {
    {
        key = "solar_field",
        shape = "solar_field",
        label = "Solar field",
        tooltip = "Solar panels and accumulators. The expansion district shares one grid, "
            .. "so this is what powers everything built next to it.",
    },
    {
        key = "iron_mine",
        shape = "nauvis_mine_iron",
        label = "Iron mine",
        tooltip = "Four more drills on a fresh iron patch, feeding Nauvis's warehouse. "
            .. "Brings no generation of its own -- it runs off the district grid.",
    },
    {
        key = "copper_mine",
        shape = "nauvis_mine_copper",
        label = "Copper mine",
        tooltip = "Four more drills on a fresh copper patch, feeding Nauvis's warehouse. "
            .. "Brings no generation of its own -- it runs off the district grid.",
    },
    {
        key = "coal_mine",
        shape = "nauvis_mine_coal",
        label = "Coal mine",
        tooltip = "Four more drills on a fresh coal patch, feeding Nauvis's warehouse. "
            .. "Brings no generation of its own -- it runs off the district grid.",
    },
    {
        key = "stone_mine",
        shape = "stone_mine",
        label = "Stone mine",
        tooltip = "Four more drills on a fresh stone patch, feeding Nauvis's warehouse. "
            .. "Brings no generation of its own -- it runs off the district grid.",
    },
    {
        key = "automation_science",
        shape = "red_flask_factory",
        label = "Automation science",
        tooltip = "Another automation science line, turning plates out of the warehouse "
            .. "into flasks. Brings no power of its own -- build a solar field first or "
            .. "it sits idle.",
    },
    {
        key = "lab_district",
        shape = "nauvis_lab",
        label = "Lab district",
        tooltip = "Twelve more labs to spend the flasks in, so research runs faster. "
            .. "Brings no power of its own -- build a solar field first or it sits idle.",
    },
}

-- Nauvis only builds out of genuine surplus. Below this it is competing with
-- the players for its own warehouse, which would drain the market to fund a
-- vote most of them did not cast.
--
-- Buildings are the exception, and have to be: `TARGET_STOCK` is the depth the
-- *market* is priced around, and no one is ever going to sell Nauvis a thousand
-- spare drills so it can spend thirty-two of them. Holding a reserve of machines
-- it cannot make and nobody stocks would make every expansion unfundable, which
-- is the whole reason a ballot elects one.
local RESERVE = stock.TARGET_STOCK

local function reserve_for(item_name)
    if item_filter.is_building(item_name) then return 0 end
    return RESERVE
end

local cost_cache = {}

function M.init()
    district.init()
    local state = storage.nauvis_expansion or {}
    -- The rolling share-weighted tally this module used to keep is gone; the
    -- ballot lives in scripts/voting.lua and only ever hands back a target.
    state.votes = nil
    state.progress = state.progress or {}
    state.built = state.built or {}
    storage.nauvis_expansion = state
    return state
end

local function state()
    return storage.nauvis_expansion or M.init()
end

function M.get_option(key)
    for _, option in ipairs(M.OPTIONS) do
        if option.key == key then return option end
    end
    return nil
end

--- The items needed to place every entity in an option's shape, as a list
--- sorted by item name so the order is stable in the GUI and across saves.
function M.cost(key)
    local cached = cost_cache[key]
    if cached then return cached end

    local option = M.get_option(key)
    local def = option and shape_registry.get(option.shape)
    local totals = {}
    for _, entity in ipairs(def and def.entities or {}) do
        if not entity.skip_create then
            local prototype = prototypes.entity[entity.name]
            local items = prototype and prototype.items_to_place_this
            local item = items and items[1]
            if item then
                totals[item.name] = (totals[item.name] or 0) + (item.count or 1)
            end
        end
    end

    local list = {}
    for name, count in pairs(totals) do
        list[#list + 1] = { name = name, count = count }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    cost_cache[key] = list
    return list
end

function M.target()
    return state().target
end

--- Per-item `have` against `need` for an option, for display and for deciding
--- when a build can go ahead.
function M.remaining(key)
    local progress = state().progress
    local rows = {}
    for _, entry in ipairs(M.cost(key)) do
        rows[#rows + 1] = {
            name = entry.name,
            need = entry.count,
            have = math.min(progress[entry.name] or 0, entry.count),
        }
    end
    return rows
end

function M.built_count(key)
    return state().built[key] or 0
end

--- What the ballot elected. Goods already set aside are kept where the new
--- target also needs them and refunded where it does not, so a change of
--- direction costs the market nothing beyond the delay.
function M.set_target(key)
    local st = state()
    if key == st.target then return end
    st.target = key
    st.awaiting_site = nil

    local needed = {}
    for _, entry in ipairs(key and M.cost(key) or {}) do
        needed[entry.name] = entry.count
    end
    for item, held in pairs(st.progress) do
        local keep = math.min(held, needed[item] or 0)
        if keep < held then
            stock.add(item, held - keep)
            st.progress[item] = keep > 0 and keep or nil
        end
    end
end

--- Draw whatever surplus exists towards the target. Returns true once every
--- line item is covered.
local function accumulate(key)
    local progress = state().progress
    local complete = true
    for _, entry in ipairs(M.cost(key)) do
        local held = progress[entry.name] or 0
        local need = entry.count - held
        if need > 0 then
            local take = math.min(need, stock.get(entry.name) - reserve_for(entry.name))
            if take > 0 then
                take = stock.take(entry.name, take)
                progress[entry.name] = held + take
                need = need - take
            end
            if need > 0 then complete = false end
        end
    end
    return complete
end

--- Book a finished build. The world was built by `nauvis_siting` the moment the
--- mayor clicked; this is only the accounting, which clears the target and so
--- reopens the ballot.
function M.finish(key)
    local st = state()
    st.built[key] = (st.built[key] or 0) + 1
    st.progress = {}
    st.target = nil
    st.awaiting_site = nil
    return true
end

--- Called once a second: spend the surplus on the elected target, then ask for
--- a site once the bill of materials is covered. Returns the option built, if
--- any -- a cleared target is what tells `voting` to open the next ballot.
function M.process()
    local done = siting.take_completed()
    if done and done.tag then
        local option = M.get_option(done.tag)
        if option then
            M.finish(done.tag)
            game.print("Nauvis has finished a new " .. option.label
                .. ". The expansion ballot is open again.")
            return option
        end
    end

    local st = state()
    local key = st.target
    local option = key and M.get_option(key)
    if not option then return nil end
    if st.awaiting_site then return nil end
    if not accumulate(key) then return nil end

    -- Where it goes is the mayor's call, so the goods sit set aside until one is
    -- pointed at a piece of ground.
    if siting.request { shape = option.shape, label = option.label, tag = key } then
        st.awaiting_site = true
    end
    return nil
end

--- True while the goods are paid for and Nauvis is only waiting to be told
--- where to put them.
function M.awaiting_site()
    return state().awaiting_site == true and siting.pending() ~= nil
end

--- New forces see the district only if it is charted for them; a company
--- founded after a build would otherwise stare at black tiles.
function M.chart_force(force)
    local surface = game.surfaces["nauvis"]
    if surface then district.chart_all(surface, force) end
end

return M
