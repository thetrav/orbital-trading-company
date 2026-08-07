local nauvis = require("scripts.nauvis")
local shape_def = require("scripts.shape_def")
local shape_registry = require("scripts.shape_registry")
local shape_place = require("scripts.shape_place")
local platform = require("scripts.platform")

local M = {}

-- Where a building goes is a human's decision, not the packer's. A build whose
-- bill of materials is covered waits here for someone to point at a piece of
-- ground; the caller polls `take_completed` for the result, which is what keeps
-- this module ignorant of what it is siting.
--
-- Requests are keyed by **client**, so the state's public works and each
-- company's own facilities queue independently and one waiting on a mayor never
-- blocks the other. `sited_by` is the force allowed to place it; with it nil the
-- request is the state's and the mayor sites it.

local FORCE_NAME = nauvis.FORCE_NAME

M.NAUVIS_CLIENT = "nauvis"

-- A border laid round a finished building is two tiles wide.
local BORDER_WIDTH = 2

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

-- Overlap is judged on the footprint alone and nothing else is asked of a site.
-- Buildings may stand shoulder to shoulder or half a map apart -- where the
-- planet gets built up is the players' business, and a rule that pulled every
-- new build back towards the last one is what made it look like a grid.

local function state()
    local st = storage.nauvis_siting or {}
    -- Siting used to serve exactly one client, so the request, its holder and
    -- the finished site were single fields. A save from before companies sited
    -- their own buildings folds whatever it was carrying onto the nauvis client.
    -- `requests` is what says the table has already been converted: the legacy
    -- fields are all optional, so their absence proves nothing.
    if not st.requests and (st.request or st.holder or st.completed) then
        local migrated = { requests = {}, holders = {}, completed = {} }
        if st.request then
            st.request.client = M.NAUVIS_CLIENT
            migrated.requests[M.NAUVIS_CLIENT] = st.request
        end
        if st.holder then migrated.holders[st.holder] = M.NAUVIS_CLIENT end
        if st.completed then migrated.completed[M.NAUVIS_CLIENT] = st.completed end
        st = migrated
    end
    st.requests = st.requests or {}
    st.holders = st.holders or {}
    st.completed = st.completed or {}
    storage.nauvis_siting = st
    return st
end

function M.init()
    state()
end

function M.pending(client)
    return state().requests[client or M.NAUVIS_CLIENT]
end

--- Every open request, in a stable order so a GUI listing them does not shuffle
--- between refreshes.
function M.list()
    local out = {}
    for _, request in pairs(state().requests) do out[#out + 1] = request end
    table.sort(out, function(a, b) return a.client < b.client end)
    return out
end

local function announce(request)
    if request.sited_by then
        local force = game.forces[request.sited_by]
        if force then
            force.print(string.format(
                "Your %s is ready to build. Open a company monitor on Nauvis, Company "
                .. "tab, and choose a site.", request.label))
        end
        return
    end

    local mayor_index = nauvis.get_mayor()
    local mayor = mayor_index and game.get_player(mayor_index)
    game.print(string.format(
        "Nauvis has the materials for a %s. %s Open a company monitor on Nauvis, "
        .. "Nauvis tab, and choose a site.",
        request.label,
        mayor and ("Mayor " .. mayor.name .. " must say where it goes.")
            or "With no mayor in office, anyone may say where it goes."))
end

--- Ask for a site. `req` is `{ shape, label, tag }` plus, for anything that is
--- not the state's own, `client`, the `force_name` / `owned_by_force` the shape
--- is built under, the `sited_by` force allowed to place it and the `border`
--- tile laid round it. `tag` is whatever the caller needs handed back.
function M.request(req)
    local st = state()
    local client = req.client or M.NAUVIS_CLIENT
    if st.requests[client] then return false end

    local request = {
        client = client,
        shape = req.shape,
        label = req.label,
        tag = req.tag,
        force_name = req.force_name,
        owned_by_force = req.owned_by_force,
        sited_by = req.sited_by,
        border = req.border,
    }
    st.requests[client] = request
    announce(request)
    return true
end

--- The mayor sites public works. With the office vacant anyone can, because a
--- world that never held an election would otherwise never build anything. A
--- company's own facilities are its own business, so `sited_by` names the force
--- and the mayor has no say.
function M.can_site(player, request)
    request = request or M.pending()
    if not request then return false end
    if request.sited_by then return player.force.name == request.sited_by end
    local mayor = nauvis.get_mayor()
    if not mayor then return true end
    if mayor == player.index then return true end
    return false
end

function M.reason_denied(player, client)
    local request = M.pending(client)
    if not request then return "Nothing is waiting for a site." end
    if not M.can_site(player, request) then
        if request.sited_by then
            return "Only " .. request.sited_by .. " can site that."
        end
        local mayor = game.get_player(nauvis.get_mayor())
        return "Only the mayor" .. (mayor and (" (" .. mayor.name .. ")") or "") .. " picks the site."
    end
    if player.surface.name ~= "nauvis" then return "You have to be on Nauvis to site a building." end
    return nil
end

--- Put the footprint in the player's cursor. It is the same placement item the
--- shape authoring tool uses, so Factorio draws its own build preview and the
--- build-reach bonus is handled in one place.
function M.begin(player, client)
    local request = M.pending(client)
    if not request then return false, "Nothing is waiting for a site." end
    local denied = M.reason_denied(player, client)
    if denied then return false, denied end

    state().holders[player.index] = request.client
    shape_place.give_item(player, request.shape)
    player.print("Left-click where the " .. request.label .. " should go. Anywhere on dry, empty "
        .. "ground will do; trees, rocks and cliffs are cleared for you.")
    return true
end

function M.cancel(player)
    state().holders[player.index] = nil
    shape_place.clear_cursor(player)
end

--- Dropping the tool by any route gives the site request back to whoever asks
--- for it next.
function M.handle_cursor_changed(player)
    local st = state()
    if not st.holders[player.index] then return end
    local stack = player.cursor_stack
    local holding = stack and stack.valid_for_read
        and string.sub(stack.name, 1, #shape_place.ITEM_PREFIX) == shape_place.ITEM_PREFIX
    if not holding then st.holders[player.index] = nil end
end

--- Is this footprint a legal site? There are exactly two rules: don't build in
--- the water, and don't build on top of something already there. Scenery is not
--- something already there -- Nauvis clears its own ground -- and how far the
--- site is from anything else is nobody's business.
function M.validate(surface, box)
    local area = { { box[1][1], box[1][2] }, { box[2][1] + 1, box[2][2] + 1 } }

    if surface.count_tiles_filtered { area = area, collision_mask = "water_tile", limit = 1 } > 0 then
        return false, "That site is in the water. Pick dry land."
    end

    for _, entity in ipairs(surface.find_entities_filtered { area = area }) do
        if entity.valid and not SCENERY[entity.type] then
            if entity.type == "character" then
                return false, "Someone is standing on that site. Clear the ground and try again."
            end
            return false, "That site is taken -- " .. entity.name .. " is in the way."
        end
    end

    return true
end

--- A ring of floor round a finished building, so a company's ground reads as its
--- own rather than as whatever it happened to land on. It lies wholly outside
--- the clearance box, so a shape's own `tile_layers` never fight it, and it is
--- laid before the build for the same reason the district lays grass first: it
--- fills a lakeside edge that would otherwise leave the wall standing in water.
local function lay_border(surface, box, tile_name)
    local tiles = {}
    for x = box[1][1] - BORDER_WIDTH, box[2][1] + BORDER_WIDTH do
        for y = box[1][2] - BORDER_WIDTH, box[2][2] + BORDER_WIDTH do
            local inside = x >= box[1][1] and x <= box[2][1]
                and y >= box[1][2] and y <= box[2][2]
            if not inside then
                tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
            end
        end
    end
    if #tiles > 0 then surface.set_tiles(tiles) end
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
function M.place(surface, origin, client)
    local request = M.pending(client)
    if not request then return false, "Nothing is waiting for a site." end

    local def = shape_registry.get(request.shape)
    local box = def and shape_def.clearance_box(def, origin, 0)
    if not box then return false, "That shape has no footprint to place." end

    local ok, reason = M.validate(surface, box)
    if not ok then return false, reason or "That is not a legal site." end

    if request.border then lay_border(surface, box, request.border) end
    platform.build_shape(surface, request.shape, origin, request.force_name or FORCE_NAME,
        { owned_by_force = request.owned_by_force })
    chart(surface, box)

    local st = state()
    st.requests[request.client] = nil
    for index, held in pairs(st.holders) do
        if held == request.client then st.holders[index] = nil end
    end
    st.completed[request.client] = { shape = request.shape, label = request.label,
        tag = request.tag, x = origin.x, y = origin.y }
    return true
end

--- Handles the placement marker the site tool puts down. Returns true when this
--- module owned the marker, so the dev placer never sees it.
function M.on_marker_built(entity, player_index)
    if not player_index then return false end
    local client = state().holders[player_index]
    if not client then return false end
    local request = M.pending(client)
    if not request then return false end
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
        ok, reason = M.place(surface, origin, client)
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
function M.take_completed(client)
    local st = state()
    client = client or M.NAUVIS_CLIENT
    local done = st.completed[client]
    st.completed[client] = nil
    return done
end

return M
