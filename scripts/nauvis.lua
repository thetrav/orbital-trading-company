local M = {}

M.FORCE_NAME = "Nauvis"

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

return M
