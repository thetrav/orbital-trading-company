local nauvis = require("scripts.nauvis")
local stock = require("scripts.stock")
local company = require("scripts.company")
local district = require("scripts.district")
local shape_registry = require("scripts.shape_registry")

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
local RESERVE = stock.TARGET_STOCK

local cost_cache = {}

function M.init()
    district.init()
    local state = storage.nauvis_expansion or {}
    state.votes = state.votes or {}
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

--- A player votes the shares they hold. No shares, no vote -- governance
--- follows ownership, the same way the share market already does.
function M.vote_weight(player_index)
    local company_name = company.player_company_name(player_index)
    local record = company.get(company_name)
    local holder = record and record.holders and record.holders[player_index]
    return holder and holder.shares or 0
end

function M.get_vote(player_index)
    return state().votes[player_index]
end

function M.set_vote(player_index, key)
    if key and not M.get_option(key) then return false, "Unknown expansion." end
    if M.vote_weight(player_index) <= 0 then
        return false, "Only shareholders vote on Nauvis expansions. Join or found a company first."
    end
    state().votes[player_index] = key
    return true
end

--- Weight per option key, and the total cast.
function M.tally()
    local counts, total = {}, 0
    for _, option in ipairs(M.OPTIONS) do
        counts[option.key] = 0
    end
    for player_index, key in pairs(state().votes) do
        if counts[key] then
            local weight = M.vote_weight(player_index)
            counts[key] = counts[key] + weight
            total = total + weight
        end
    end
    return counts, total
end

--- Highest tally wins; ties break towards the earlier option so the result
--- never depends on table iteration order.
function M.leader()
    local counts = M.tally()
    local best, best_weight = nil, 0
    for _, option in ipairs(M.OPTIONS) do
        if counts[option.key] > best_weight then
            best, best_weight = option.key, counts[option.key]
        end
    end
    return best
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

--- Follow the vote. Goods already set aside are kept where the new target also
--- needs them and refunded where it does not, so switching a vote costs the
--- market nothing beyond the delay.
local function retarget()
    local st = state()
    local leader = M.leader()
    if leader == st.target then return end
    st.target = leader

    local needed = {}
    for _, entry in ipairs(leader and M.cost(leader) or {}) do
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
            local take = math.min(need, stock.get(entry.name) - RESERVE)
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

function M.build(key)
    local option = M.get_option(key)
    local surface = game.surfaces["nauvis"]
    if not option or not surface then return false end

    district.build(surface, option.shape, nauvis.FORCE_NAME)

    local st = state()
    st.built[key] = (st.built[key] or 0) + 1
    st.progress = {}
    st.target = nil
    st.votes = {}
    return true
end

--- Called once a second: follow the vote, spend the surplus, build when the
--- bill of materials is covered.
function M.process()
    local st = state()
    retarget()
    local key = st.target
    local option = key and M.get_option(key)
    if not option then return end
    if not accumulate(key) then return end

    if M.build(key) then
        game.print("Nauvis has finished a new " .. option.label
            .. ". The expansion ballot is open again.")
    end
end

--- New forces see the district only if it is charted for them; a company
--- founded after a build would otherwise stare at black tiles.
function M.chart_force(force)
    local surface = game.surfaces["nauvis"]
    if surface then district.chart_all(surface, force) end
end

return M
