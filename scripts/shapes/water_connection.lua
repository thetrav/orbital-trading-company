-- Shape definition captured from the game.
-- Re-capture in game with: /otc-capture-shape water_connection
-- Coordinates are shape-local; the canonical orientation is a gate on the
-- west edge with the room extending east. See README.md "Capturing shapes".
local runs = require("scripts.shape_runs")

return {
    format = 1,
    name = "water_connection",
    clear_area = true,
    connection = { position = { x = -3, y = 0 }, side = "west", gap = 2, connector = true },
    clearance_box = { { -4, -4 }, { 4, 4 } },
    tile_layers = {
        {
            name = "otc-platform",
            correct = false,
            tiles = runs.expand {
                { -3, -3, 3 },
                { -2, -3, 3 },
                { -1, -3, 3 },
                { 0, -3, 3 },
                { 1, -3, 3 },
                { 2, -3, 3 },
                { 3, -3, 3 },
            },
        },
    },
    entities = {
        { name = "otc-platform-wall", position = { -2.5, -2.5 } },
        { name = "otc-platform-wall", position = { 3.5, -2.5 } },
        { name = "otc-platform-wall", position = { -2.5, -1.5 } },
        { name = "otc-platform-wall", position = { 3.5, -1.5 } },
        { name = "otc-platform-wall", position = { -2.5, -0.5 } },
        { name = "otc-platform-wall", position = { 3.5, -0.5 } },
        { name = "otc-platform-wall", position = { 3.5, 0.5 } },
        { name = "otc-platform-wall", position = { -2.5, 1.5 } },
        { name = "otc-platform-wall", position = { 3.5, 1.5 } },
        { name = "otc-platform-wall", position = { -2.5, 2.5 } },
        { name = "otc-platform-wall", position = { 3.5, 2.5 } },
        { name = "otc-platform-wall", position = { -2.5, 3.5 } },
        { name = "otc-platform-wall", position = { 3.5, 3.5 } },
        { name = "otc-platform-wall", position = { -1.5, -2.5 } },
        { name = "otc-platform-wall", position = { -1.5, 3.5 } },
        { name = "otc-platform-wall", position = { -0.5, -2.5 } },
        { name = "otc-platform-wall", position = { -0.5, 3.5 } },
        { name = "otc-platform-wall", position = { 0.5, -2.5 } },
        { name = "otc-platform-wall", position = { 0.5, 3.5 } },
        { name = "otc-platform-wall", position = { 1.5, -2.5 } },
        { name = "otc-platform-wall", position = { 1.5, 3.5 } },
        { name = "otc-platform-wall", position = { 2.5, -2.5 } },
        { name = "otc-platform-wall", position = { 2.5, 3.5 } },
        { name = "otc-water-pump", position = { 0.5, 0.5 }, direction = 4, role = "pump" },
    },
}
