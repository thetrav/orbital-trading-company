local nauvis = require("scripts.nauvis")
local research = require("scripts.research")

local M = {}

local SHARE_PAR = 100
local LEAVE_FLOOR = 0.9
local FOUNDING_MIN = 5000
local TAKEOVER_DISCOUNT = 0.5
local LEDGER_CAPACITY = 60

M.SHARE_PAR = SHARE_PAR
M.FOUNDING_MIN = FOUNDING_MIN

function M.is_state(name)
    return nauvis.is_state(name)
end

function M.get(name)
    return name and storage.companies[name] or nil
end

function M.player_company_name(player_index)
    local player_data = storage.players and storage.players[player_index]
    return player_data and player_data.company or nil
end

function M.holder_count(company)
    local count = 0
    for _ in pairs(company.holders) do
        count = count + 1
    end
    return count
end

function M.sorted_holders(company)
    local rows = {}
    for player_index, holding in pairs(company.holders) do
        table.insert(rows, { player_index = player_index, shares = holding.shares, role = holding.role })
    end
    table.sort(rows, function(a, b) return a.shares > b.shares end)
    return rows
end

function M.per_share(company)
    -- Cash-only stand-in until scripts/valuation.lua (plan phase 5) lands.
    local issued = company.shares_issued or 0
    if issued <= 0 then return SHARE_PAR end
    return math.max(company.credits / issued, SHARE_PAR / 10)
end

function M.available_shares(name, company)
    return (company.treasury_shares or 0) + nauvis.get_holding(name)
end

function M.percent(company, player_index)
    local holder = company.holders[player_index]
    if not holder or (company.shares_issued or 0) <= 0 then return 0 end
    return holder.shares / company.shares_issued * 100
end

local function ledger_add(company, kind, amount, player_index)
    company.ledger = company.ledger or {}
    table.insert(company.ledger, {
        tick = game.tick,
        kind = kind,
        amount = amount,
        player_index = player_index,
    })
    while #company.ledger > LEDGER_CAPACITY do
        table.remove(company.ledger, 1)
    end
end

local function ensure_manager(company)
    for _, holder in pairs(company.holders) do
        if holder.role == "manager" then return end
    end
    local best_index, best_shares = nil, -1
    for player_index, holder in pairs(company.holders) do
        if holder.shares > best_shares then
            best_index, best_shares = player_index, holder.shares
        end
    end
    if best_index then
        company.holders[best_index].role = "manager"
    end
end

function M.validate_name(name)
    if not name or name == "" then
        return false, "Enter a valid company name!"
    end
    if name == "Nauvis" or name == "player" or name == "enemy" or name == "neutral" then
        return false, "That name is reserved!"
    end
    if game.forces[name] then
        return false, "A company named '" .. name .. "' already exists!"
    end
    return true
end

-- SEAM: admissions vote goes here. Return "pending" and park the request in
-- company.pending; the vote resolves it later and calls the admit step directly.
-- Callers must already handle a non-"approved" result without moving credits.
function M.resolve_application(_company_name, _player_index)
    return "approved"
end

-- SEAM: share auction goes here. This is the reserve price, not the clearing price --
-- list the block in company.auctions, let players bid above it, and fall back to this
-- value with Nauvis as buyer of last resort when the auction closes unsold.
function M.settlement_price(_company_name, company)
    return M.per_share(company) * LEAVE_FLOOR
end

function M.create(player, name, capital)
    local player_data = storage.players[player.index]
    if M.player_company_name(player.index) then
        return false, "You already hold shares in a company!"
    end
    local ok, err = M.validate_name(name)
    if not ok then return false, err end
    if not capital or capital < FOUNDING_MIN then
        return false, "Founding capital must be at least " .. FOUNDING_MIN .. "!"
    end
    if (player_data.personal_credits or 0) < capital then
        return false, "Not enough personal credits!"
    end

    game.create_force(name)
    for _, force in pairs(game.forces) do
        force.set_cease_fire(game.forces[name], true)
        force.set_friend(game.forces[name], true)
    end
    research.sync_force(game.forces[name])

    local shares = math.floor(capital / SHARE_PAR)
    storage.companies[name] = {
        credits = capital,
        founded_tick = game.tick,
        holders = {
            [player.index] = { shares = shares, role = "manager", joined_tick = game.tick },
        },
        treasury_shares = 0,
        shares_issued = shares,
        pending = {},
        auctions = {},
        receivership = false,
        valuation = { tick = 0, cash = 0, assets = 0, inventory = 0, earnings = 0, total = 0, per_share = 0 },
        ledger = {},
    }

    player_data.personal_credits = player_data.personal_credits - capital
    player_data.company = name
    player.force = game.forces[name]

    ledger_add(storage.companies[name], "found", capital, player.index)
    return true
end

function M.join(player, name)
    local player_data = storage.players[player.index]
    if M.player_company_name(player.index) then
        return false, "You already hold shares in a company!"
    end
    local company = M.get(name)
    if not company or not game.forces[name] then
        return false, "Company no longer exists!"
    end
    if M.is_state(name) then
        return false, "Nauvis cannot be joined!"
    end
    if company.receivership then
        return false, "That company is in receivership!"
    end

    local available = M.available_shares(name, company)
    if available <= 0 then
        return false, "No shares available to buy!"
    end

    local resolution = M.resolve_application(name, player.index)
    if resolution ~= "approved" then
        return false, "Your application is pending approval."
    end

    local price = M.per_share(company)
    local treasury_take = math.min(available, company.treasury_shares or 0)
    local nauvis_take = available - treasury_take
    local cost = math.floor(price * available + 0.5)
    local cost_treasury = math.floor(cost * treasury_take / available + 0.5)
    local cost_nauvis = cost - cost_treasury

    if (player_data.personal_credits or 0) < cost then
        return false, "Not enough personal credits!"
    end

    player_data.personal_credits = player_data.personal_credits - cost
    company.credits = company.credits + cost_treasury
    company.treasury_shares = (company.treasury_shares or 0) - treasury_take
    if nauvis_take > 0 then
        nauvis.remove_holding(name, nauvis_take)
        nauvis.burn(cost_nauvis, "join:" .. name)
    end

    company.holders[player.index] = {
        shares = available,
        role = "member",
        joined_tick = game.tick,
    }

    player_data.company = name
    player.force = game.forces[name]

    ledger_add(company, "join", cost, player.index)
    return true
end

function M.takeover_price(company)
    -- Receivership sale: Nauvis discounts its whole block to get the company staffed
    -- again rather than left idle, hence a flat discount instead of the leave floor.
    return M.per_share(company) * TAKEOVER_DISCOUNT
end

function M.takeover(player, name)
    local player_data = storage.players[player.index]
    if M.player_company_name(player.index) then
        return false, "You already hold shares in a company!"
    end
    local company = M.get(name)
    if not company or not game.forces[name] then
        return false, "Company no longer exists!"
    end
    if not company.receivership then
        return false, "That company is not in receivership!"
    end

    local shares = nauvis.get_holding(name)
    local price = M.takeover_price(company)
    local cost = math.floor(price * shares + 0.5)

    if (player_data.personal_credits or 0) < cost then
        return false, "Not enough personal credits!"
    end

    player_data.personal_credits = player_data.personal_credits - cost
    nauvis.remove_holding(name, shares)
    nauvis.burn(cost, "takeover:" .. name)

    company.holders[player.index] = { shares = shares, role = "manager", joined_tick = game.tick }
    company.receivership = false

    player_data.company = name
    player.force = game.forces[name]

    ledger_add(company, "takeover", cost, player.index)
    return true
end

function M.leave(player)
    local player_data = storage.players[player.index]
    local name = M.player_company_name(player.index)
    if not name then
        return false, "You don't hold shares in a company!"
    end
    local company = M.get(name)
    if not company then
        player_data.company = nil
        return false, "Company no longer exists!"
    end

    local holder = company.holders[player.index]
    if not holder then
        player_data.company = nil
        return false, "You don't hold shares in that company!"
    end

    local shares = holder.shares
    local price = M.settlement_price(name, company)
    local payout = math.floor(price * shares + 0.5)

    nauvis.mint(payout, "leave:" .. name)
    player_data.personal_credits = (player_data.personal_credits or 0) + payout
    company.holders[player.index] = nil
    nauvis.add_holding(name, shares)

    if next(company.holders) == nil then
        company.receivership = true
    else
        ensure_manager(company)
    end

    ledger_add(company, "leave", payout, player.index)

    player_data.company = nil
    if game.forces[nauvis.FORCE_NAME] then
        player.force = game.forces[nauvis.FORCE_NAME]
    end
    return true
end

return M
