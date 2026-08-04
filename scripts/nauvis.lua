local stock = require("scripts.stock")
local utils = require("scripts.utils")

local M = {}

M.FORCE_NAME = "Nauvis"

-- A bond costs a slice of everything the world is worth, multiplied by the bonds
-- the buyer already holds. See M.total_value and M.bond_price for why each half is
-- shaped the way it is. The floor exists only so a zero or negative valuation
-- cannot give votes away; it is not meant to be a meaningful price.
local BOND_RATE = 0.03
local BOND_FLOOR = 100

M.BOND_RATE = BOND_RATE
M.STARTING_BONDS = 1

function M.init()
    storage.nauvis = storage.nauvis or {}
    storage.nauvis.minted = storage.nauvis.minted or 0
    storage.nauvis.burned = storage.nauvis.burned or 0
    storage.nauvis.holdings = storage.nauvis.holdings or {}
    storage.nauvis.bonds = storage.nauvis.bonds or {}
end

function M.is_state(name)
    return name == M.FORCE_NAME
end

function M.mint(amount, _reason)
    if amount <= 0 then return end
    storage.nauvis.minted = storage.nauvis.minted + amount
end

function M.burn(amount, _reason)
    if amount <= 0 then return end
    storage.nauvis.burned = storage.nauvis.burned + amount
end

function M.net()
    return storage.nauvis.minted - storage.nauvis.burned
end

function M.get_holding(company_name)
    return storage.nauvis.holdings[company_name] or 0
end

function M.add_holding(company_name, shares)
    storage.nauvis.holdings[company_name] = M.get_holding(company_name) + shares
end

function M.remove_holding(company_name, shares)
    local remaining = M.get_holding(company_name) - shares
    if remaining <= 0 then
        storage.nauvis.holdings[company_name] = nil
    else
        storage.nauvis.holdings[company_name] = remaining
    end
end

function M.get_bonds(player_index)
    return storage.nauvis.bonds[player_index] or 0
end

function M.add_bonds(player_index, count)
    storage.nauvis.bonds[player_index] = M.get_bonds(player_index) + count
end

function M.total_bonds()
    local total = 0
    for _, count in pairs(storage.nauvis.bonds) do
        total = total + count
    end
    return total
end

function M.ensure_bonds(player_index)
    if storage.nauvis.bonds[player_index] == nil then
        storage.nauvis.bonds[player_index] = M.STARTING_BONDS
    end
end

--- Everything the world is worth: the money supply plus Nauvis's warehouse at
--- *base* prices. Base, not market, because market price moves with scarcity and
--- demand -- anchoring governance to it would let someone corner a thin item to
--- crash the bond price and buy influence cheaply. Company assets belong in this
--- sum too and join it when scripts/valuation.lua lands.
function M.total_value()
    local value = M.net()
    for item_name, count in pairs(stock.items()) do
        if count > 0 then
            value = value + count * utils.get_base_price(item_name)
        end
    end
    return value
end

--- Progressive: the price is multiplied by the bonds the buyer already holds, so
--- reaching h bonds costs about `RATE * value * h^2 / 2` -- doubling your influence
--- costs four times as much. That multiplier climbing is also what stops a
--- purchase cheapening the next one: it outruns the value the burn removes, so
--- each bond is dearer than the last rather than a step down a geometric curve.
function M.bond_price(player_index)
    local held = math.max(M.get_bonds(player_index), 1)
    return math.max(math.floor(M.total_value() * BOND_RATE * held + 0.5), BOND_FLOOR)
end

function M.buy_bond(player_index)
    local player_data = storage.players and storage.players[player_index]
    if not player_data then return false, "No player record." end
    local price = M.bond_price(player_index)
    if (player_data.personal_credits or 0) < price then
        return false, "Not enough personal credits for a bond."
    end
    player_data.personal_credits = player_data.personal_credits - price
    M.burn(price, "bond")
    M.add_bonds(player_index, 1)
    return true, price
end

function M.get_mayor()
    return storage.nauvis.mayor
end

function M.set_mayor(player_index)
    storage.nauvis.mayor = player_index
end

return M
