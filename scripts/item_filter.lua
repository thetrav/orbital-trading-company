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

--- Anything that puts an entity on the ground. Nauvis pays for its expansions in
--- buildings and cannot make a single one of them, so the machines have to be
--- tradeable or the ballot elects works that can never be funded. It cuts both
--- ways on purpose: a company can buy a drill off Nauvis instead of crafting it,
--- and can go into business manufacturing them for the state.
---
--- Tile items -- landfill, concrete -- carry `place_as_tile_result` rather than
--- `place_result` and are deliberately not covered: nothing Nauvis builds is
--- costed in them.
local function places_an_entity(prototype)
    return prototype.place_result ~= nil
end

--- Exposed because `nauvis_expansion` reserves stock differently for buildings:
--- `TARGET_STOCK` is a market depth, and nobody is ever going to sell Nauvis a
--- thousand spare drills.
function M.is_building(item_name)
    local prototype = prototypes.item[item_name]
    return prototype ~= nil and places_an_entity(prototype)
end

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
    local in_subgroup = subgroup ~= nil and ALLOWED_SUBGROUPS[subgroup.name] == true
    if not in_subgroup and not places_an_entity(prototype) then return false end
    if in_subgroup and RESEARCH_FREE_SUBGROUPS[subgroup.name] then return true end
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
