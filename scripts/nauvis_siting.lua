local nauvis = require("scripts.nauvis")
local shape_def = require("scripts.shape_def")
local shape_registry = require("scripts.shape_registry")
local shape_place = require("scripts.shape_place")
local district = require("scripts.district")
local platform = require("scripts.platform")

local M = {}

-- Where a public work goes is the mayor's decision, not the packer's. A build
-- whose bill of materials is covered waits here for a human to point at a piece
-- of ground; `nauvis_expansion` polls `take_completed` for the result, which is
-- what keeps this module ignorant of what it is siting.

local FORCE_NAME = nauvis.FORCE_NAME
local POLE = "big-electric-pole"
local DEFAULT_WIRE_REACH = 30

-- The site has to be clear, but Nauvis is a real world: a forest, a boulder
-- field or a cliff is fair game and gets levelled. Anything else standing in the
-- footprint means the site is taken.
local SCENERY = {
    tree = true,
    ["simple-entity"] = true,
    cliff = true,
    fish = true,
    ["item-entity"] = true,
    corpse = true,
    ["character-corpse"] = true,
}

-- Overlap is judged on the footprint alone, so a new building can sit right up
-- against the district's gutter and share its poles. Enemies get a wider berth:
-- a nest this close would be attacking the site before it finished.
local ENEMY_MARGIN = 8

local function state()
    storage.nauvis_siting = storage.nauvis_siting or {}
    return storage.nauvis_siting
end

function M.init()
    state()
end

function M.pending()
    return state().request
end

--- Ask for a site. `req` is `{ shape, label, tag }`; `tag` is whatever the
--- caller needs handed back when the site is built.
function M.request(req)
    local st = state()
    if st.request then return false end
    st.request = { shape = req.shape, label = req.label, tag = req.tag }

    local mayor_index = nauvis.get_mayor()
    local mayor = mayor_index and game.get_player(mayor_index)
    game.print(string.format(
        "Nauvis has the materials for a %s. %s Open a company monitor on Nauvis, "
        .. "Nauvis tab, and choose a site.",
        req.label,
        mayor and ("Mayor " .. mayor.name .. " must say where it goes.")
            or "With no mayor in office, anyone may say where it goes."))
    return true
end

--- The mayor sites public works. With the office vacant anyone can, because a
--- world that never held an election would otherwise never build anything.
function M.can_site(player)
    local mayor = nauvis.get_mayor()
    if not mayor then return true end
    if mayor == player.index then return true end
    return false
end

function M.reason_denied(player)
    if not M.pending() then return "Nothing is waiting for a site." end
    if not M.can_site(player) then
        local mayor = game.get_player(nauvis.get_mayor())
        return "Only the mayor" .. (mayor and (" (" .. mayor.name .. ")") or "") .. " picks the site."
    end
    if player.surface.name ~= "nauvis" then return "You have to be on Nauvis to site a building." end
    return nil
end

--- Put the footprint in the player's cursor. It is the same placement item the
--- shape authoring tool uses, so Factorio draws its own build preview and the
--- build-reach bonus is handled in one place.
function M.begin(player)
    local request = M.pending()
    if not request then return false, "Nothing is waiting for a site." end
    local denied = M.reason_denied(player)
    if denied then return false, denied end

    state().holder = player.index
    shape_place.give_item(player, request.shape)
    player.print("Left-click where the " .. request.label .. " should go. It needs dry, empty "
        .. "ground within reach of Nauvis's power grid; trees, rocks and cliffs are cleared for you.")
    return true
end

function M.cancel(player)
    local st = state()
    if st.holder == player.index then st.holder = nil end
    shape_place.clear_cursor(player)
end

--- Dropping the tool by any route gives the site request back to whoever asks
--- for it next.
function M.handle_cursor_changed(player)
    local st = state()
    if st.holder ~= player.index then return end
    local stack = player.cursor_stack
    local holding = stack and stack.valid_for_read
        and string.sub(stack.name, 1, #shape_place.ITEM_PREFIX) == shape_place.ITEM_PREFIX
    if not holding then st.holder = nil end
end

--- Wire reach is quality-dependent in 2.0, so it is a getter rather than a
--- field: reading `max_wire_distance` off a prototype is a hard error.
local function wire_reach(prototype)
    if type(prototype) == "string" then prototype = prototypes.entity[prototype] end
    if not prototype or not prototype.get_max_wire_distance then return DEFAULT_WIRE_REACH end
    return prototype.get_max_wire_distance() or DEFAULT_WIRE_REACH
end

--- The four tiles a corner pole stands on: just outside the footprint, one on
--- each corner, exactly as the district lays them round a module. A 2x2 pole
--- covers the tile it is named after and the one before it, so these sit clear
--- of the shape without leaving a gap.
function M.pole_positions(box)
    local x1, y1, x2, y2 = box[1][1], box[1][2], box[2][1], box[2][2]
    return {
        { x = x1 - 1, y = y1 - 1 },
        { x = x2 + 2, y = y1 - 1 },
        { x = x1 - 1, y = y2 + 2 },
        { x = x2 + 2, y = y2 + 2 },
    }
end

--- The corner that can reach an existing Nauvis pole, if any. Connection
--- distance is the shorter of the two poles' wire reach, so a substation on the
--- edge of a built district pulls the site in closer than a big pole would.
function M.grid_link(surface, box)
    local reach = wire_reach(POLE)
    for _, position in ipairs(M.pole_positions(box)) do
        local found = surface.find_entities_filtered {
            position = position, radius = reach, type = "electric-pole", force = FORCE_NAME,
        }
        for _, pole in ipairs(found) do
            local limit = math.min(reach, wire_reach(pole.prototype))
            local dx = pole.position.x - position.x
            local dy = pole.position.y - position.y
            if dx * dx + dy * dy <= limit * limit then return position, pole end
        end
    end
    return nil
end

--- Is this footprint a legal site? Water and anything built are hard stops;
--- scenery is not, because Nauvis clears its own ground.
function M.validate(surface, box)
    local area = { { box[1][1], box[1][2] }, { box[2][1] + 1, box[2][2] + 1 } }

    if surface.count_tiles_filtered { area = area, collision_mask = "water_tile", limit = 1 } > 0 then
        return false, "That site is in the water. Pick dry land."
    end

    local wide = {
        { area[1][1] - ENEMY_MARGIN, area[1][2] - ENEMY_MARGIN },
        { area[2][1] + ENEMY_MARGIN, area[2][2] + ENEMY_MARGIN },
    }
    for _, entity in ipairs(surface.find_entities_filtered { area = wide, force = "enemy" }) do
        if entity.valid then
            return false, "Too close to the enemy -- there is a " .. entity.name
                .. " within " .. ENEMY_MARGIN .. " tiles."
        end
    end

    for _, entity in ipairs(surface.find_entities_filtered { area = area }) do
        if entity.valid and not SCENERY[entity.type] then
            if entity.type == "character" then
                return false, "Someone is standing on that site. Clear the ground and try again."
            end
            return false, "That site is taken -- " .. entity.name .. " is in the way."
        end
    end

    if not M.grid_link(surface, box) then
        return false, "That site is out of reach of Nauvis's power grid. Build within "
            .. wire_reach(POLE) .. " tiles of an existing pole."
    end

    return true
end

--- Run the line to a freshly sited building: a big pole on each corner of the
--- footprint, which auto-connects to the grid it was validated against and to
--- the shape's own substation.
local function connect(surface, box)
    for _, position in ipairs(M.pole_positions(box)) do
        if surface.can_place_entity { name = POLE, position = position, force = FORCE_NAME } then
            district.ensure_pole(surface, position.x, position.y)
        end
    end
end

local function chart(surface, box)
    local area = {
        { box[1][1] - 4, box[1][2] - 4 },
        { box[2][1] + 4, box[2][2] + 4 },
    }
    for _, force in pairs(game.forces) do
        force.chart(surface, area)
    end
end

--- Settle the pending request on a piece of ground: validate, build, run the
--- power in and chart it. Player-free, so a probe can drive the whole thing.
function M.place(surface, origin)
    local request = M.pending()
    if not request then return false, "Nothing is waiting for a site." end

    local def = shape_registry.get(request.shape)
    local box = def and shape_def.clearance_box(def, origin, 0)
    if not box then return false, "That shape has no footprint to place." end

    local ok, reason = M.validate(surface, box)
    if not ok then return false, reason or "That is not a legal site." end

    platform.build_shape(surface, request.shape, origin, FORCE_NAME)
    connect(surface, box)
    chart(surface, box)

    local st = state()
    st.request = nil
    st.holder = nil
    st.completed = { shape = request.shape, label = request.label, tag = request.tag,
        x = origin.x, y = origin.y }
    return true
end

--- Handles the placement marker the site tool puts down. Returns true when this
--- module owned the marker, so the dev placer never sees it.
function M.on_marker_built(entity, player_index)
    local request = M.pending()
    if not request or not player_index then return false end
    if state().holder ~= player_index then return false end
    if entity.name ~= shape_place.MARKER_PREFIX .. request.shape then return false end

    local surface = entity.surface
    local position = entity.position
    entity.destroy()

    local player = game.get_player(player_index)
    if not player then return true end

    local def = shape_registry.get(request.shape)
    local origin = def and shape_place.origin_from_marker(def, position)
    local ok, reason
    if origin then
        ok, reason = M.place(surface, origin)
    else
        reason = "That shape has no footprint to place."
    end
    if not ok then
        player.print(reason or "That is not a legal site.")
        -- The stack is consumed by the placement, so hand it back: a rejected
        -- site should cost a click, not the whole trip to the computer.
        shape_place.give_item(player, request.shape)
        return true
    end

    shape_place.clear_cursor(player)
    game.print(string.format("%s sited the new %s at %d,%d.",
        player.name, request.label, origin.x, origin.y))
    return true
end

--- The finished site, handed over once. Polled by whoever made the request so
--- this module never has to know what it was building.
function M.take_completed()
    local st = state()
    local done = st.completed
    st.completed = nil
    return done
end

return M
