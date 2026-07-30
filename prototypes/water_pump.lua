---@diagnostic disable: inject-field
local pump = table.deepcopy(data.raw["offshore-pump"]["offshore-pump"])
pump.name = "otc-water-pump"
pump.icon = "__base__/graphics/icons/offshore-pump.png"
pump.icon_size = 64
pump.minable = nil
pump.flags = {"placeable-neutral", "player-creation", "not-on-map", "not-flammable"}
pump.tile_filter = {"otc-platform"}
pump.adjacent_tile_filter = {"otc-platform"}
---@diagnostic enable: inject-field

return {pump}
