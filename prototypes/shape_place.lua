-- Placement markers for the dev shape-placer. One item + one dummy entity per
-- registered shape, sized to that shape's footprint, so Factorio draws its own
-- build preview under the cursor: there is no API for polling the mouse
-- position, so a hand-drawn preview cannot follow it.
--
-- The dummy collides with nothing, which keeps placement legal on top of
-- whatever is already there; the placer clears the area itself when asked.
local shape_registry = require("scripts.shape_registry")

local ICON = "__base__/graphics/icons/blueprint.png"

local function footprint(def)
    local box = def.clearance_box
    if not box then return 1, 1 end
    return box[2][1] - box[1][1] + 1, box[2][2] - box[1][2] + 1
end

-- A layer of its own, which no other prototype uses. The marker therefore
-- collides with nothing real -- placement is never blocked, so shapes can be
-- stamped over whatever is already there -- while still having a non-empty
-- mask, which is what makes the engine draw its footprint highlight.
local COLLISION_LAYER = "otc-placement"

-- A single sprite scales uniformly, so a square source can never draw a 22x14
-- rectangle, and an invisible picture leaves the cursor showing nothing at all.
-- The footprint is therefore built out of one-tile squares laid along its
-- border, which is the only way to express an arbitrary rectangle here.
local TILE_SQUARE = "__core__/graphics/white-square.png"
local TINT = { r = 0.35, g = 0.8, b = 1, a = 0.45 }
local MAX_OUTLINE_TILES = 240

local function square_at(shift_x, shift_y)
    return {
        filename = TILE_SQUARE,
        width = 1,
        height = 1,
        scale = 32,
        shift = { shift_x, shift_y },
        tint = TINT,
        priority = "extra-high",
    }
end

local function outline(width, height)
    local half_w, half_h = width / 2, height / 2
    local layers = {}
    local perimeter = 2 * width + 2 * height - 4

    if perimeter > MAX_OUTLINE_TILES then
        -- Very large shapes get corner pips instead of a full border, so the
        -- sprite count stays sane.
        for _, corner in ipairs {
            { 0, 0 }, { width - 1, 0 }, { 0, height - 1 }, { width - 1, height - 1 },
        } do
            layers[#layers + 1] = square_at(corner[1] - half_w + 0.5, corner[2] - half_h + 0.5)
        end
        return layers
    end

    for x = 0, width - 1 do
        for y = 0, height - 1 do
            if x == 0 or y == 0 or x == width - 1 or y == height - 1 then
                layers[#layers + 1] = square_at(x - half_w + 0.5, y - half_h + 0.5)
            end
        end
    end
    return layers
end

local prototypes = {
    { type = "collision-layer", name = COLLISION_LAYER },
}

for _, name in ipairs(shape_registry.names()) do
    local def = shape_registry.get(name)
    local width, height = footprint(def)
    local half_w, half_h = width / 2, height / 2
    local entity_name = "otc-place-marker-" .. name

    prototypes[#prototypes + 1] = {
        type = "simple-entity-with-owner",
        name = entity_name,
        icon = ICON,
        icon_size = 64,
        flags = {
            "placeable-neutral", "player-creation", "not-on-map",
            "not-blueprintable", "not-deconstructable", "not-flammable",
        },
        hidden = true,
        minable = nil,
        selectable_in_game = false,
        collision_mask = { layers = { [COLLISION_LAYER] = true } },
        collision_box = { { -half_w + 0.1, -half_h + 0.1 }, { half_w - 0.1, half_h - 0.1 } },
        selection_box = { { -half_w, -half_h }, { half_w, half_h } },
        tile_width = width,
        tile_height = height,
        picture = { layers = outline(width, height) },
    }

    prototypes[#prototypes + 1] = {
        type = "item",
        name = "otc-place-" .. name,
        icon = ICON,
        icon_size = 64,
        hidden = true,
        flags = { "only-in-cursor", "spawnable", "not-stackable" },
        subgroup = "tool",
        order = "z[otc]-c[shape-place]-" .. name,
        stack_size = 1,
        place_result = entity_name,
    }
end

return prototypes
