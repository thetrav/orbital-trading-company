-- Authoring tools: a selection tool that dumps a region of the world into a
-- shape definition, and a marker entity that labels anchors inside it.

local marker = table.deepcopy(data.raw["display-panel"]["display-panel"])
marker.name = "otc-shape-marker"
marker.icon = "__base__/graphics/icons/display-panel.png"
marker.icon_size = 64
marker.flags = { "placeable-neutral", "player-creation", "not-on-map", "get-by-unit-number" }
marker.minable = { mining_time = 0.1, result = nil }
marker.collision_mask = { layers = {} }
marker.collision_box = { { -0.3, -0.3 }, { 0.3, 0.3 } }
marker.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
marker.dying_explosion = nil

local tool = {
    type = "selection-tool",
    name = "otc-shape-capture",
    icon = "__base__/graphics/icons/blueprint.png",
    icon_size = 64,
    flags = { "only-in-cursor", "spawnable", "not-stackable" },
    subgroup = "tool",
    order = "z[otc]-a[shape-capture]",
    stack_size = 1,
    draw_label_for_cursor_render = true,
    select = {
        border_color = { r = 0.2, g = 0.8, b = 0.35 },
        cursor_box_type = "copy",
        mode = { "any-entity", "any-tile" },
    },
    alt_select = {
        border_color = { r = 0.9, g = 0.6, b = 0.2 },
        cursor_box_type = "copy",
        mode = { "any-entity" },
    },
}

return { marker, tool }
