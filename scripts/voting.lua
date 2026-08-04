local nauvis = require("scripts.nauvis")
local research = require("scripts.research")
local nauvis_expansion = require("scripts.nauvis_expansion")

local M = {}

-- One day/night cycle per ballot. `ticks_per_day` is the surface's own figure so
-- a changed cycle length carries through; the constant is only the headless
-- fallback for a world with no nauvis surface.
local DAY_TICKS_FALLBACK = 25000
local WARNING_TICKS = 3600
-- The research frontier can be dozens of technologies wide. A ballot that long is
-- not a choice, it is a list, so only the cheapest few go on it.
local RESEARCH_CHOICES = 8

M.WARNING_TICKS = WARNING_TICKS
M.KINDS = { "mayor", "research", "expansion" }

local function tech_label(tech_name)
    local prototype = prototypes.technology[tech_name]
    return prototype and prototype.localised_name or tech_name
end

local KINDS = {
    mayor = {
        title = "Mayor",
        idle = "No election running. Any bondholder can call one.",
        options = function()
            local list = {}
            for _, player in pairs(game.players) do
                if nauvis.get_bonds(player.index) > 0 then
                    list[#list + 1] = { key = tostring(player.index), label = player.name }
                end
            end
            table.sort(list, function(a, b) return tonumber(a.key) < tonumber(b.key) end)
            return list
        end,
        resolve = function(key)
            nauvis.set_mayor(tonumber(key))
        end,
    },
    research = {
        title = "Next research",
        idle = "Nothing to elect -- Nauvis is already working on something.",
        options = function()
            local list = {}
            for index, name in ipairs(research.get_available_technologies()) do
                if index > RESEARCH_CHOICES then break end
                list[#list + 1] = {
                    key = name,
                    label = tech_label(name),
                    tooltip = not research.can_supply(name)
                        and "Nauvis cannot make the science packs this needs, so electing it "
                            .. "stalls research until it can."
                        or nil,
                }
            end
            return list
        end,
        resolve = function(key)
            research.set_next_research(key)
        end,
    },
    expansion = {
        title = "Next expansion",
        idle = "Nothing to elect -- Nauvis is already building something.",
        options = function()
            local list = {}
            for _, option in ipairs(nauvis_expansion.OPTIONS) do
                -- Built counts only move when an expansion finishes, which closes
                -- this ballot anyway, so baking them into the frozen label is safe.
                local built = nauvis_expansion.built_count(option.key)
                list[#list + 1] = {
                    key = option.key,
                    label = built > 0 and string.format("%s [%d built]", option.label, built) or option.label,
                    tooltip = option.tooltip,
                }
            end
            return list
        end,
        resolve = function(key)
            nauvis_expansion.set_target(key)
        end,
    },
}

function M.title(kind)
    local def = KINDS[kind]
    return def and def.title or kind
end

function M.idle_caption(kind)
    local def = KINDS[kind]
    return def and def.idle or ""
end

local function state()
    storage.voting = storage.voting or {}
    storage.voting.ballots = storage.voting.ballots or {}
    return storage.voting
end

function M.init()
    state()
end

function M.active(kind)
    return state().ballots[kind]
end

--- A bond is a vote. Nothing else carries weight here -- company shares govern
--- a company, bonds govern the state.
function M.weight(player_index)
    return nauvis.get_bonds(player_index)
end

function M.eligible_weight()
    return nauvis.total_bonds()
end

function M.duration()
    local surface = game.surfaces and game.surfaces["nauvis"]
    ---@diagnostic disable-next-line: undefined-field
    return surface and surface.ticks_per_day or DAY_TICKS_FALLBACK
end

function M.option_label(ballot, key)
    for _, option in ipairs(ballot.options) do
        if option.key == key then return option.label end
    end
    return key
end

function M.open(kind, caller_name)
    local def = KINDS[kind]
    if not def then return false, "Unknown vote." end
    if state().ballots[kind] then
        return false, def.title .. " is already on the ballot."
    end
    local options = def.options()
    if #options == 0 then return false, "There is nothing to vote on." end

    local ballot = {
        kind = kind,
        options = options,
        votes = {},
        start_tick = game.tick,
        end_tick = game.tick + M.duration(),
        warned = false,
    }
    state().ballots[kind] = ballot

    local minutes = math.max(math.floor(M.duration() / 3600 + 0.5), 1)
    game.print((caller_name and (caller_name .. " has called a vote: ") or "A vote is open: ")
        .. def.title
        .. string.format(" -- %d on the ballot, closing in about %d minutes. "
            .. "Cast your bonds at a Nauvis company monitor.", #options, minutes))
    return true
end

function M.cast(player_index, kind, key)
    local ballot = state().ballots[kind]
    if not ballot then return false, "That vote is not open." end
    if M.weight(player_index) <= 0 then
        return false, "You hold no Nauvis bonds, so you have no vote."
    end
    for _, option in ipairs(ballot.options) do
        if option.key == key then
            ballot.votes[player_index] = key
            return true
        end
    end
    return false, "That is not on the ballot."
end

function M.get_vote(player_index, kind)
    local ballot = state().ballots[kind]
    return ballot and ballot.votes[player_index] or nil
end

local function tally_ballot(ballot)
    local counts, cast = {}, 0
    for _, option in ipairs(ballot.options) do
        counts[option.key] = 0
    end
    for player_index, key in pairs(ballot.votes) do
        if counts[key] then
            local weight = M.weight(player_index)
            counts[key] = counts[key] + weight
            cast = cast + weight
        end
    end
    return counts, cast
end

--- Weight per option key, and the total weight cast.
function M.tally(kind)
    local ballot = state().ballots[kind]
    if not ballot then return {}, 0 end
    return tally_ballot(ballot)
end

--- True once no outstanding bond could still change the result: either every
--- bond has voted, or the leader's margin is bigger than what is left to cast.
--- A ballot nobody has voted in yet is never decided -- otherwise a world whose
--- players have not joined would resolve every ballot at random on tick one.
function M.decided_early(kind)
    local ballot = state().ballots[kind]
    if not ballot then return false end
    local counts, cast = M.tally(kind)
    if cast <= 0 then return false end

    local outstanding = math.max(M.eligible_weight() - cast, 0)
    if outstanding == 0 then return true end

    local best, second = 0, 0
    for _, option in ipairs(ballot.options) do
        local count = counts[option.key] or 0
        if count > best then
            best, second = count, best
        elseif count > second then
            second = count
        end
    end
    return best - second > outstanding
end

--- First past the post. Ties -- including the all-zero tie of a ballot nobody
--- voted in -- are drawn from the tied options with the game's own RNG, which is
--- deterministic across clients and so desync-safe.
local function decide(ballot)
    local counts, cast = tally_ballot(ballot)
    local best, leaders = 0, {}
    for _, option in ipairs(ballot.options) do
        local count = counts[option.key] or 0
        if count > best then
            best, leaders = count, { option.key }
        elseif count == best then
            leaders[#leaders + 1] = option.key
        end
    end
    return leaders[math.random(#leaders)], best, cast, #leaders > 1
end

function M.close(kind)
    local ballot = state().ballots[kind]
    if not ballot then return end
    state().ballots[kind] = nil

    local def = KINDS[kind]
    local winner, best, cast, tied = decide(ballot)
    local how
    if cast <= 0 then
        how = " No bonds were cast, so it was drawn at random."
    elseif tied then
        how = " The vote was tied, so it was drawn at random."
    else
        how = string.format(" (%d of %d bonds cast).", best, cast)
    end

    -- The winning label may be a technology's localised name, so this one stays a
    -- LocalisedString; the stub's element type does not admit plain strings.
    ---@diagnostic disable-next-line: assign-type-mismatch
    game.print({ "", "Vote closed -- ", def.title, ": ", M.option_label(ballot, winner), ".", how })
    def.resolve(winner)
end

--- Research and expansion ballots are standing business: whenever Nauvis has
--- nothing queued and nothing under construction, the next ballot opens itself.
--- That covers game start, a finished technology and a finished expansion in one
--- rule, rather than three call sites that each have to remember.
local function ensure_standing()
    -- game.players is a LuaCustomTable, so `next` is not an option here.
    if #game.players == 0 then return end
    if not state().ballots.research
        and not research.current_research_name()
        and not research.get_next_research() then
        M.open("research")
    end
    if not state().ballots.expansion and not nauvis_expansion.target() then
        M.open("expansion")
    end
end

function M.process()
    ensure_standing()
    for _, kind in ipairs(M.KINDS) do
        local ballot = state().ballots[kind]
        if ballot then
            if game.tick >= ballot.end_tick or M.decided_early(kind) then
                M.close(kind)
            elseif not ballot.warned and ballot.end_tick - game.tick <= WARNING_TICKS then
                ballot.warned = true
                game.print("One minute left to vote -- " .. KINDS[kind].title .. ".")
            end
        end
    end
end

return M
