local silo = data.raw["rocket-silo"]["rocket-silo"]

local function sprite(field)
    return util.table.deepcopy(silo[field])
end

return {
    {
        -- A plain container, not a logistic one: as a logistic chest outside any
        -- roboport coverage it flashes a "not connected to network" alert. Bots
        -- are meant to come back later -- switching the type back and restoring
        -- logistic_mode/max_logistic_slots is the whole change.
        type = "container",
        name = "otc-trading-silo",
        icon = "__base__/graphics/icons/rocket-silo.png",
        icon_size = 64,
        icon_draw_specification = { shift = { 0, 2 } },
        flags = { "placeable-player", "player-creation" },
        max_health = 5000,
        corpse = "rocket-silo-remnants",
        dying_explosion = "rocket-silo-explosion",
        collision_box = { { -4.20, -4.20 }, { 4.20, 4.20 } },
        selection_box = { { -4.5, -4.5 }, { 4.5, 4.5 } },
        impact_category = "metal-large",
        resistances = {
            { type = "fire",   percent = 60 },
            { type = "impact", percent = 60 },
        },
        inventory_size = 100,
        -- Slot filters are how a buy order says *what* and *how much*: a filtered
        -- slot is a reservation, and one slot holds one stack. The limiter bar
        -- comes with it and is what blocks slots off entirely.
        --
        -- This forecloses `with_custom_stack_size`: `inventory_type` is a single
        -- value, so a container can have filters+bar or a custom stack size, not
        -- both. Reservation granularity is therefore one vanilla stack.
        inventory_type = "with_filters_and_bar",
        open_sound = { filename = "__base__/sound/metallic-chest-open.ogg", volume = 0.65 },
        close_sound = { filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.7 },
        picture = {
            layers = {
                sprite("shadow_sprite"),
                sprite("hole_sprite"),
                sprite("door_back_sprite"),
                sprite("door_front_sprite"),
                sprite("base_day_sprite"),
            },
        },
        circuit_wire_max_distance = 9,
        draw_circuit_wires = true,
    },
}
