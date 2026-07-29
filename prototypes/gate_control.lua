local k = table.deepcopy(data.raw["display-panel"]["display-panel"])
k.name = "otc-gate-computer"
k.icon = "__base__/graphics/icons/display-panel.png"
k.icon_size = 64
k.flags = {"placeable-neutral", "player-creation", "not-on-map", "get-by-unit-number"}
k.minable = nil
k.max_health = 200
k.collision_box = {{-0.35, -0.35}, {0.35, 0.35}}
k.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
k.dying_explosion = nil

return {k}