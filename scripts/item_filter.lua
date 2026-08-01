local research = require("scripts.research")

local M = {}

local ALLOWED_SUBGROUPS = {
    ["raw-resource"] = true,
    ["raw-material"] = true,
    ["intermediate-product"] = true,
}

local RESEARCH_FREE_SUBGROUPS = {
    ["raw-resource"] = true,
}

function M.is_item_hidden(prototype)
    if not prototype.flags then return false end
    if type(prototype.flags) == "table" then
        if prototype.flags.hidden then return true end
        for _, flag in pairs(prototype.flags) do
            if flag == "hidden" then return true end
        end
    end
    return false
end

function M.is_item_allowed(item_name, force)
    local prototype = prototypes.item[item_name]
    if not prototype then return false end
    if M.is_item_hidden(prototype) then return false end
    if research.is_banned_item(item_name) then return false end
    local subgroup = prototype.subgroup
    if not subgroup or not ALLOWED_SUBGROUPS[subgroup.name] then return false end
    if RESEARCH_FREE_SUBGROUPS[subgroup.name] then return true end
    for _, recipe in pairs(force.recipes) do
        if recipe.enabled then
            for _, product in pairs(recipe.products) do
                if product.name == item_name then
                    return true
                end
            end
        end
    end
    return false
end

function M.get_allowed_items(force)
    local items = {}
    for name, prototype in pairs(prototypes.item) do
        if M.is_item_allowed(name, force) then
            table.insert(items, { name = name, prototype = prototype })
        end
    end
    table.sort(items, function(a, b) return a.prototype.order < b.prototype.order end)
    return items
end

return M
