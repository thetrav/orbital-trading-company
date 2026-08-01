local M = {}

local TARGET_STOCK = 1000
local SCARCITY_CAP = 20
local SCARCITY_EXPONENT_SCARCE = 0.7
local SCARCITY_EXPONENT_GLUT = 2

M.TARGET_STOCK = TARGET_STOCK
M.SCARCITY_CAP = SCARCITY_CAP

-- Nauvis mines its own ore but has no furnaces: plates are supplied entirely by
-- players, so they must not seed with a free starting stockpile.
local ZERO_SEED_ITEMS = {
    ["iron-plate"] = true,
    ["copper-plate"] = true,
}

function M.init()
    storage.stock = storage.stock or {}
    storage.stock.items = storage.stock.items or {}
end

function M.get(item_name)
    if not storage.stock then return 0 end
    local count = storage.stock.items[item_name]
    if count == nil then
        count = ZERO_SEED_ITEMS[item_name] and 0 or TARGET_STOCK
        storage.stock.items[item_name] = count
    end
    return count
end

function M.set(item_name, count)
    if not storage.stock then return end
    storage.stock.items[item_name] = math.max(0, math.floor(count))
end

function M.add(item_name, count)
    if count <= 0 then return 0 end
    M.set(item_name, M.get(item_name) + count)
    return count
end

function M.take(item_name, count)
    if count <= 0 then return 0 end
    local available = M.get(item_name)
    local taken = math.min(available, count)
    if taken <= 0 then return 0 end
    M.set(item_name, available - taken)
    return taken
end

function M.is_available(item_name)
    return M.get(item_name) > 0
end

function M.scarcity(item_name)
    local count = M.get(item_name)
    if count <= 0 then return SCARCITY_CAP end
    if count < TARGET_STOCK then
        return math.min(SCARCITY_CAP, (TARGET_STOCK / count) ^ SCARCITY_EXPONENT_SCARCE)
    end
    return (TARGET_STOCK / count) ^ SCARCITY_EXPONENT_GLUT
end

return M
