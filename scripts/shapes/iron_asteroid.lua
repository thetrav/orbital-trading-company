-- Shape definition captured from the game.
-- Re-capture in game with: /otc-capture-shape iron_asteroid
-- Coordinates are shape-local; the canonical orientation is a gate on the
-- west edge with the room extending east. See README.md "Capturing shapes".
local runs = require("scripts.shape_runs")

return {
    format = 1,
    name = "iron_asteroid",
    hook = "room_gates",
    connection = { position = { x = 0, y = 0 }, side = "west", gap = 0, connector = false },
    clearance_box = { { 2, -6 }, { 15, 6 } },
    tile_layers = {
        {
            name = "dirt-7",
            correct = true,
            tiles = runs.expand {
                { -6, 6, 12 },
                { -5, 5, 13 },
                { -4, 4, 14 },
                { -3, 3, 15 },
                { -2, 3, 15 },
                { -1, 3, 15 },
                { 0, 3, 15 },
                { 1, 3, 15 },
                { 2, 3, 15 },
                { 3, 3, 15 },
                { 4, 4, 14 },
                { 5, 5, 13 },
                { 6, 6, 12 },
            },
        },
        {
            name = "otc-platform",
            correct = true,
            tiles = runs.expand {
                { -1, 2, 3 },
                { 0, 2, 3 },
                { 1, 2, 3 },
            },
        },
    },
    entities = {
        { name = "otc-platform-wall", position = { 3.5, 1.5 } },
        { name = "otc-platform-wall", position = { 2.5, 1.5 } },
        { name = "otc-platform-wall", position = { 3.5, -0.5 } },
        { name = "otc-platform-wall", position = { 2.5, -0.5 } },
        { name = "gate", position = { 3.5, 0.5 }, role = "gate", side = "east", skip_create = true },
    },
    resources = {
        { name = "iron-ore", position = { 7, -1 }, amount = 5000000 },
        { name = "iron-ore", position = { 7, 0 }, amount = 5000000 },
        { name = "iron-ore", position = { 7, 1 }, amount = 5000000 },
        { name = "iron-ore", position = { 8, -2 }, amount = 5000000 },
        { name = "iron-ore", position = { 8, -1 }, amount = 5000000 },
        { name = "iron-ore", position = { 8, 0 }, amount = 5000000 },
        { name = "iron-ore", position = { 8, 1 }, amount = 5000000 },
        { name = "iron-ore", position = { 8, 2 }, amount = 5000000 },
        { name = "iron-ore", position = { 9, -2 }, amount = 5000000 },
        { name = "iron-ore", position = { 9, -1 }, amount = 5000000 },
        { name = "iron-ore", position = { 9, 0 }, amount = 5000000 },
        { name = "iron-ore", position = { 9, 1 }, amount = 5000000 },
        { name = "iron-ore", position = { 9, 2 }, amount = 5000000 },
        { name = "iron-ore", position = { 10, -2 }, amount = 5000000 },
        { name = "iron-ore", position = { 10, -1 }, amount = 5000000 },
        { name = "iron-ore", position = { 10, 0 }, amount = 5000000 },
        { name = "iron-ore", position = { 10, 1 }, amount = 5000000 },
        { name = "iron-ore", position = { 10, 2 }, amount = 5000000 },
        { name = "iron-ore", position = { 11, -1 }, amount = 5000000 },
        { name = "iron-ore", position = { 11, 0 }, amount = 5000000 },
        { name = "iron-ore", position = { 11, 1 }, amount = 5000000 },
    },
}
