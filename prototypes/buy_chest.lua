return {
    {
        type = "item",
        name = "otc-buy-chest",
        icon = "__base__/graphics/icons/requester-chest.png",
        icon_size = 64,
        subgroup = "logistic-network",
        order = "b[storage]-b[buy-chest]",
        place_result = "otc-buy-chest",
        stack_size = 50,
    },
    {
        type = "recipe",
        name = "otc-buy-chest",
        enabled = true,
        ingredients = {
            { type = "item", name = "steel-plate", amount = 8 },
        },
        results = {
            { type = "item", name = "otc-buy-chest", amount = 1 },
        },
    },
    {
        type = "container",
        name = "otc-buy-chest",
        icon = "__base__/graphics/icons/requester-chest.png",
        icon_size = 64,
        flags = { "placeable-neutral", "player-creation" },
        minable = { mining_time = 0.5, result = "otc-buy-chest" },
        max_health = 200,
        corpse = "small-remnants",
        open_sound = { filename = "__base__/sound/metallic-chest-open.ogg", volume = 0.65 },
        close_sound = { filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.7 },
        resistances = {
            { type = "fire", percent = 90 },
        },
        collision_box = { { -0.35, -0.35 }, { 0.35, 0.35 } },
        selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
        inventory_size = 48,
        vehicle_impact_sound = { filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 },
        picture = {
            layers = {
                {
                    filename = "__base__/graphics/entity/logistic-chest/requester-chest.png",
                    priority = "extra-high",
                    width = 66,
                    height = 74,
                    shift = util.by_pixel(0, -0.25),
                    scale = 0.5,
                },
                {
                    filename = "__base__/graphics/entity/logistic-chest/logistic-chest-shadow.png",
                    priority = "extra-high",
                    width = 112,
                    height = 46,
                    shift = util.by_pixel(10, 6.5),
                    draw_as_shadow = true,
                    scale = 0.5,
                },
            },
        },
        circuit_wire_connection_point = {
            shadow = {
                red = { 0.734375, 0.5625 },
                green = { 0.734375, 0.65625 },
            },
            wire = {
                red = { 0.40625, 0.21875 },
                green = { 0.40625, 0.3125 },
            },
        },
        circuit_wire_max_distance = 9,
        draw_circuit_wires = true,
    },
}
