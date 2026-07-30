return {
    {
        type = "planet",
        name = "orbit",
        order = "z[orbit]",
        distance = 100,
        orientation = 0.5,
        draw_orbit = false,
        hidden = true,
        icon = "__base__/graphics/icons/iron-plate.png",
        icon_size = 64,
        starting_surface = false,
        map_gen_settings = {
            width = 0,
            height = 0,
            starting_area = 0,
            terrain_segmentation = 0,
            water = 0,
            peaceful_mode = true,
            no_enemies_mode = true,
            autoplace_settings = {
                tile = {
                    settings = {
                        ["out-of-map"] = {
                            frequency = "normal",
                            size = "normal",
                            richness = "normal",
                        },
                    },
                },
            },
        },
        surface_properties = {
            ["day-night-cycle"] = 0,
        },
    },
}
