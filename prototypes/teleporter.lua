local teleporter = table.deepcopy(data.raw["car"]["car"])
teleporter.name = "otc-teleporter"
teleporter.icon = "__core__/graphics/empty.png"
teleporter.icon_size = 1
teleporter.flags = {"placeable-neutral", "player-creation", "placeable-off-grid", "not-flammable"}
teleporter.minable = nil
teleporter.max_health = 1
teleporter.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
teleporter.selection_box = {{-0.3, -0.3}, {0.3, 0.3}}
teleporter.energy_per_hit_point = 1
teleporter.animation = {
    layers = {{
        filename = "__core__/graphics/empty.png",
        width = 1,
        height = 1,
        frame_count = 1,
        direction_count = 1,
    }},
}
teleporter.light_animation = {
    filename = "__core__/graphics/empty.png",
    width = 1,
    height = 1,
    frame_count = 1,
    direction_count = 1,
}
teleporter.inventory_size = 1
teleporter.energy_source = {type = "void"}
teleporter.consumption = "0kW"
teleporter.effectivity = 0

return {teleporter}
