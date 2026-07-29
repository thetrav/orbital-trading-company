local kiosk = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-1"])

kiosk.name = "otc-gate-control"
kiosk.icon = "__base__/graphics/icons/gate.png"
kiosk.icon_size = 64
kiosk.flags = {"placeable-neutral", "player-creation", "not-on-map"}
kiosk.minable = nil
kiosk.max_health = 100
kiosk.corpse = nil
kiosk.dying_explosion = nil
kiosk.icon_draw_specification = nil
kiosk.resistances = nil
kiosk.collision_box = {{-0.35, -0.35}, {0.35, 0.35}}
kiosk.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
kiosk.damaged_trigger_effect = nil
kiosk.fast_replaceable_group = nil
kiosk.next_upgrade = nil
kiosk.circuit_wire_max_distance = nil
kiosk.circuit_connector = nil
kiosk.alert_icon_shift = nil
kiosk.graphics_set = nil
kiosk.crafting_categories = {"otc-gate-crafting"}
kiosk.crafting_speed = 1
kiosk.energy_usage = "1W"
kiosk.energy_source = {type = "void"}
kiosk.open_sound = nil
kiosk.close_sound = nil
kiosk.allowed_effects = nil
kiosk.effect_receiver = nil
kiosk.impact_category = nil
kiosk.working_sound = nil
kiosk.picture = {
    filename = "__base__/graphics/entity/steel-chest/steel-chest.png",
    priority = "extra-high",
    width = 64,
    height = 80,
    shift = {0, -0.25},
    scale = 0.5,
}

return {
    {
        type = "recipe-category",
        name = "otc-gate-crafting",
    },
    kiosk,
}
