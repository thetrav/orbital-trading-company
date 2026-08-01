---@diagnostic disable: inject-field
local function make(name, icon)
    local belt = table.deepcopy(data.raw["underground-belt"]["underground-belt"])
    belt.name = name
    belt.icon = icon
    belt.icon_size = 64
    belt.minable = nil
    belt.next_upgrade = nil
    belt.fast_replaceable_group = nil
    belt.flags = {"placeable-neutral", "player-creation", "not-on-map", "not-flammable", "not-deconstructable"}
    belt.max_distance = 0
    return belt
end

local supply = make("otc-supply-belt", "__base__/graphics/icons/underground-belt.png")
local intake = make("otc-intake-belt", "__base__/graphics/icons/underground-belt.png")
---@diagnostic enable: inject-field

return {supply, intake}
