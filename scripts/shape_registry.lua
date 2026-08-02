-- Every captured shape definition, required statically so Factorio loads them
-- at control-stage init. Add a line here after capturing a new shape.

local M = {}

M.defs = {
    hub = require("scripts.shapes.hub"),
    corridor = require("scripts.shapes.corridor"),
    factory = require("scripts.shapes.factory"),
    iron_asteroid = require("scripts.shapes.iron_asteroid"),
    copper_asteroid = require("scripts.shapes.copper_asteroid"),
    water_connection = require("scripts.shapes.water_connection"),
    orbital_station = require("scripts.shapes.orbital_station"),
    station_interior = require("scripts.shapes.station_interior"),
    nauvis_starting_room = require("scripts.shapes.nauvis_starting_room"),
    nauvis_production_room = require("scripts.shapes.nauvis_production_room"),
    nauvis_mine_iron = require("scripts.shapes.nauvis_mine_iron"),
    nauvis_mine_copper = require("scripts.shapes.nauvis_mine_copper"),
    nauvis_mine_coal = require("scripts.shapes.nauvis_mine_coal"),
    stone_mine = require("scripts.shapes.stone_mine"),
    red_flask_factory = require("scripts.shapes.red_flask_factory"),
}

function M.get(name)
    return M.defs[name]
end

function M.names()
    local names = {}
    for name in pairs(M.defs) do names[#names + 1] = name end
    table.sort(names)
    return names
end

return M
