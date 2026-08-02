local supply_belts = require("scripts.supply_belts")

local M = {}

M.NAUVIS_FORCE = "Nauvis"

-- Everything otc places on Nauvis belongs to the Nauvis force (see
-- room_builder.get_surface_force), including the fixtures players are meant to
-- use. Those stay interactive; the guard is about Nauvis's own industry.
local ALWAYS_ALLOWED = {
    ["otc-gate-computer"] = true,
    ["otc-company-monitor"] = true,
    ["otc-teleporter"] = true,
    ["otc-shape-marker"] = true,
}

local function state()
    storage.nauvis_guard = storage.nauvis_guard or {}
    storage.nauvis_guard.snapshots = storage.nauvis_guard.snapshots or {}
    storage.nauvis_guard.mined = storage.nauvis_guard.mined or {}
    storage.nauvis_guard.pasted = storage.nauvis_guard.pasted or {}
    return storage.nauvis_guard
end

local function is_nauvis(surface)
    return surface and surface.valid and surface.name == "nauvis"
end

local function is_outsider(player)
    return player and player.valid and player.force.name ~= M.NAUVIS_FORCE
end

function M.init()
    state()
end

--- Nauvis's own property, being touched by somebody who does not work here.
function M.is_protected(entity, player)
    if not entity or not entity.valid or not player or not player.valid then return false end
    if ALWAYS_ALLOWED[entity.name] then return false end
    if entity.force.name ~= M.NAUVIS_FORCE then return false end
    return player.force.name ~= M.NAUVIS_FORCE
end

local function refuse(player, what)
    player.print("That belongs to Nauvis. You cannot " .. what .. " it.")
end

--- Closing the machine GUI is what stops recipes being changed and contents
--- being taken by hand; both need the window open.
function M.on_gui_opened(player, entity)
    if not M.is_protected(entity, player) then return false end
    player.opened = nil
    refuse(player, "open")
    return true
end

function M.on_rotated(event)
    local player = game.get_player(event.player_index)
    local entity = event.entity
    if not player or not entity then return false end
    if not M.is_protected(entity, player) then return false end
    entity.direction = event.previous_direction
    -- Restoring direction can flip an underground belt's end; supply belts have
    -- to come back as exits.
    supply_belts.enforce_exit(entity)
    refuse(player, "rotate")
    return true
end

local function inventories(entity)
    local seen, list = {}, {}
    for _, index in pairs(defines.inventory) do
        local ok, inventory = pcall(entity.get_inventory, index)
        if ok and inventory and inventory.valid then
            local key = inventory.index or #list + 1
            if not seen[key] then
                seen[key] = true
                list[#list + 1] = inventory
            end
        end
    end
    return list
end

local function contents_of(entity)
    local totals = {}
    for _, inventory in ipairs(inventories(entity)) do
        for _, item in pairs(inventory.get_contents()) do
            totals[item.name] = (totals[item.name] or 0) + item.count
        end
    end
    return totals
end

--- A fast transfer cannot be vetoed, only undone, and the event does not say
--- what moved. Snapshotting while the entity is merely hovered gives us the
--- before-picture to diff against.
function M.on_hover(player)
    local snapshots = state().snapshots
    local entity = player.selected
    if not M.is_protected(entity, player) or not entity.unit_number then
        snapshots[player.index] = nil
        return
    end
    snapshots[player.index] = { unit = entity.unit_number, contents = contents_of(entity) }
end

function M.on_fast_transferred(event)
    local player = game.get_player(event.player_index)
    local entity = event.entity
    if not player then return false end
    if not M.is_protected(entity, player) then return false end

    local snapshot = state().snapshots[player.index]
    if not snapshot or snapshot.unit ~= entity.unit_number then
        refuse(player, "take from")
        return true
    end

    local now = contents_of(entity)
    for name, before in pairs(snapshot.contents) do
        local after = now[name] or 0
        if after < before then
            local returned = player.remove_item { name = name, count = before - after }
            if returned > 0 then entity.insert { name = name, count = returned } end
        end
    end
    for name, after in pairs(now) do
        local before = snapshot.contents[name] or 0
        if after > before then
            local taken = entity.remove_item { name = name, count = after - before }
            if taken > 0 then player.insert { name = name, count = taken } end
        end
    end

    state().snapshots[player.index] = { unit = entity.unit_number, contents = contents_of(entity) }
    refuse(player, "take from")
    return true
end

--- Engine-level hardening, applied to everything Nauvis owns. Events can undo a
--- mine or a paste after the fact, but nothing can undo a super-force build --
--- Ctrl+Shift placing a blueprint destroys whatever is in the way outright --
--- so Nauvis's property is made indestructible and unminable instead. That also
--- takes deconstruction planners out of play, since only minable entities can
--- be marked.
function M.harden(entity)
    if not entity or not entity.valid then return false end
    if entity.force.name ~= M.NAUVIS_FORCE then return false end
    if ALWAYS_ALLOWED[entity.name] then return false end
    entity.minable = false
    entity.destructible = false
    return true
end

--- Harden a whole applied shape.
function M.harden_shape(ctx)
    if not ctx or not ctx.entities then return end
    if not is_nauvis(ctx.surface) then return end
    for _, built in ipairs(ctx.entities) do
        M.harden(built.entity)
    end
end

--- A settings paste (shift+right-click to copy, shift+left-click to paste)
--- cannot be vetoed, so the destination's settings are snapshotted first and
--- put back afterwards.
local function settings_snapshot(entity)
    local snapshot = {}
    local ok, recipe = pcall(entity.get_recipe)
    if ok and recipe then snapshot.recipe = recipe.name end

    local counted, count = pcall(function() return entity.filter_slot_count end)
    if counted and count and count > 0 then
        snapshot.filters = {}
        for index = 1, count do
            local got, filter = pcall(entity.get_filter, index)
            if got then snapshot.filters[index] = filter or false end
        end
    end
    return snapshot
end

local function settings_restore(entity, snapshot)
    if not entity.valid then return end
    pcall(function() entity.set_recipe(snapshot.recipe) end)
    for index, filter in pairs(snapshot.filters or {}) do
        pcall(entity.set_filter, index, filter or nil)
    end
end

function M.on_pre_settings_pasted(event)
    local player = game.get_player(event.player_index)
    local destination = event.destination
    if not player or not destination then return end
    if not M.is_protected(destination, player) then
        state().pasted[event.player_index] = nil
        return
    end
    state().pasted[event.player_index] = {
        unit = destination.unit_number,
        settings = settings_snapshot(destination),
    }
end

function M.on_settings_pasted(event)
    local pending = state().pasted[event.player_index]
    state().pasted[event.player_index] = nil
    if not pending then return false end

    local destination = event.destination
    if destination and destination.valid and destination.unit_number == pending.unit then
        settings_restore(destination, pending.settings)
    end
    local player = game.get_player(event.player_index)
    if player then refuse(player, "reconfigure") end
    return true
end

--- Deconstruction and upgrade planners mark entities for robots; the marks are
--- cancellable, unlike the actions they would cause.
function M.on_marked_for_deconstruction(event)
    local player = event.player_index and game.get_player(event.player_index)
    local entity = event.entity
    if not player or not entity then return false end
    if not M.is_protected(entity, player) then return false end
    entity.cancel_deconstruction(player.force, player)
    refuse(player, "deconstruct")
    return true
end

function M.on_marked_for_upgrade(event)
    local player = event.player_index and game.get_player(event.player_index)
    local entity = event.entity
    if not player or not entity then return false end
    if not M.is_protected(entity, player) then return false end
    entity.cancel_upgrade(player.force, player)
    refuse(player, "upgrade")
    return true
end

--- Nauvis is Nauvis's planet: an outsider builds nothing on its surface. The
--- entity is mined back into the player's inventory rather than destroyed, so
--- the attempt costs them nothing.
function M.on_built(entity, player_index)
    if not entity or not entity.valid then return false end
    local player = player_index and game.get_player(player_index)
    if not is_nauvis(entity.surface) then return false end
    if entity.force.name == M.NAUVIS_FORCE then return false end
    if player and not is_outsider(player) then return false end

    if player then
        if not player.mine_entity(entity, true) and entity.valid then
            entity.destroy()
        end
        refuse(player, "build on")
    elseif entity.valid then
        entity.destroy()
    end
    return true
end

--- Mining is undone rather than prevented: nothing can veto it, but the loot
--- buffer can be emptied and the entity put back exactly as it was.
local function mining_blocked(entity, player)
    if not entity or not entity.valid then return false end
    if not is_nauvis(entity.surface) then return false end
    return is_outsider(player)
end

function M.on_pre_mined(event)
    local player = game.get_player(event.player_index)
    local entity = event.entity
    if not entity or not entity.valid or not mining_blocked(entity, player) then
        state().mined[event.player_index] = nil
        return
    end
    state().mined[event.player_index] = {
        name = entity.name,
        position = entity.position,
        surface = entity.surface.name,
        force = entity.force.name,
        direction = entity.direction,
        amount = entity.type == "resource" and entity.amount or nil,
        belt_type = entity.type == "underground-belt" and entity.belt_to_ground_type or nil,
    }
end

function M.on_mined(event)
    local snapshot = state().mined[event.player_index]
    state().mined[event.player_index] = nil
    if not snapshot then return false end

    if event.buffer and event.buffer.valid then event.buffer.clear() end

    local surface = game.surfaces[snapshot.surface]
    if surface then
        local args = {
            name = snapshot.name,
            position = snapshot.position,
            force = snapshot.force,
            direction = snapshot.direction,
            create_build_effect_smoke = false,
        }
        if snapshot.amount then args.amount = snapshot.amount end
        if snapshot.belt_type then args.type = snapshot.belt_type end
        pcall(surface.create_entity, args)
    end

    local player = game.get_player(event.player_index)
    if player then refuse(player, "mine") end
    return true
end

--- Items on the ground belong to Nauvis too. Nothing can veto the pickup, so
--- take it back off the player and drop it where they stood.
function M.on_picked_up(event)
    local player = game.get_player(event.player_index)
    if not player or not is_outsider(player) then return false end
    if not is_nauvis(player.surface) then return false end

    local stack = event.item_stack
    if not stack or not stack.name then return false end
    local removed = player.remove_item { name = stack.name, count = stack.count }
    if removed > 0 then
        player.surface.spill_item_stack {
            position = player.position,
            stack = { name = stack.name, count = removed },
            enable_looted = false,
            allow_belts = false,
        }
    end
    refuse(player, "pick up things on")
    return true
end

return M
