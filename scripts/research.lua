local nauvis = require("scripts.nauvis")

local M = {}

local TRIGGER_TECHS = { "steam-power", "electronics", "automation-science-pack" }
local NON_COMPANY_FORCES = { enemy = true, neutral = true, captured = true }
local NAUVIS_PACKS = { ["automation-science-pack"] = true }
local PERMISSION_GROUP_NAME = "Nauvis Research Lockout"
local RESTRICTED_ACTIONS = {
    defines.input_action.start_research,
    defines.input_action.cancel_research,
    defines.input_action.move_research,
}

-- Research is Nauvis's alone; the research screen is read-only for everyone else.
-- Blocking these input actions keeps the vanilla tech tree from inviting clicks that
-- would just get reverted by sync_all_progress() a tick later.
function M.ensure_permission_group()
    local group = game.permissions.get_group(PERMISSION_GROUP_NAME)
    if not group then
        group = game.permissions.create_group(PERMISSION_GROUP_NAME)
    end
    if not group then return nil end
    for _, action in ipairs(RESTRICTED_ACTIONS) do
        group.set_allows_action(action, false)
    end
    return group
end

function M.lock_player_research(player)
    if not player or not player.valid then return end
    local group = M.ensure_permission_group()
    if not group then return end
    if player.permission_group ~= group then
        player.permission_group = group
    end
end

function M.lock_all_players()
    for _, player in pairs(game.players) do
        M.lock_player_research(player)
    end
end

--- Science packs, and only science packs. The monopoly is about who may *run*
--- research, not who may build the box: a lab a company puts down is destroyed
--- and refunded by `M.block_lab` the moment it appears, so letting companies
--- craft and sell labs costs the state nothing and is the only way Nauvis can
--- ever buy a lab district -- it cannot make one itself, and no other force was
--- allowed to.
function M.is_banned_item(item_name)
    local prototype = prototypes.item[item_name]
    if not prototype then return false end
    return prototype.type == "tool"
end

local function is_banned_recipe(recipe)
    for _, product in pairs(recipe.products) do
        if product.type == "item" and M.is_banned_item(product.name) then
            return true
        end
    end
    return false
end

function M.is_restricted_force(force)
    if not force or not force.valid then return false end
    if nauvis.is_state(force.name) then return false end
    return not NON_COMPANY_FORCES[force.name]
end

--- Ban only ever *disables*, so a recipe that stops being banned stays off for
--- the rest of the save unless something puts it back. `reset_recipes` is that
--- something: it restores every recipe to what the force's researched
--- technologies say it should be, and the bans go on top. Without it, a save
--- written while labs were banned would keep the lab recipe disabled forever --
--- `sync_force` cannot re-run a technology's unlock effects, because it skips
--- any technology the force already has researched.
function M.apply_bans(force)
    if not M.is_restricted_force(force) then return end
    force.reset_recipes()
    for _, recipe in pairs(force.recipes) do
        if recipe.enabled and is_banned_recipe(recipe) then
            recipe.enabled = false
        end
    end
end

-- Mirrors Nauvis's current research and progress onto a company force so its
-- vanilla research GUI shows the same tech and fill level, purely for visibility --
-- company forces cannot queue research themselves (see M.block_lab / recipe bans).
--
-- The whole queue is written rather than appended to: add_research() only pushes onto
-- the back, so anything a player managed to queue themselves would survive. Writing
-- research_queue outright makes Nauvis's choice the only entry, which is what makes
-- this a real revert rather than a suggestion.
local function queue_matches(force, tech_name)
    local queue = force.research_queue
    if not tech_name then return #queue == 0 end
    return #queue == 1 and queue[1].name == tech_name
end

local function sync_current_research(force)
    local state = game.forces[nauvis.FORCE_NAME]
    if not state then return end

    local target = state.current_research
    local target_name = target and target.name or nil
    if target_name then
        local mirrored = force.technologies[target_name]
        if not mirrored or mirrored.researched then target_name = nil end
    end

    if not queue_matches(force, target_name) then
        force.research_queue = target_name and { target_name } or nil
    end
    if target_name then
        force.research_progress = state.research_progress
    end
end

function M.sync_force(force)
    if not M.is_restricted_force(force) then return end
    local state = game.forces[nauvis.FORCE_NAME]
    if not state then return end
    for name, tech in pairs(state.technologies) do
        if tech.researched then
            local target = force.technologies[name]
            if target and not target.researched then
                target.researched = true
            end
        end
    end
    M.apply_bans(force)
    sync_current_research(force)
end

function M.sync_all()
    for _, force in pairs(game.forces) do
        M.sync_force(force)
    end
end

-- Cheap per-tick heartbeat: just mirrors current research + progress, without
-- rescanning every technology on every force.
function M.sync_all_progress()
    for _, force in pairs(game.forces) do
        if M.is_restricted_force(force) then
            sync_current_research(force)
        end
    end
end

local function prerequisites_met(tech)
    for _, prerequisite in pairs(tech.prerequisites) do
        if not prerequisite.researched then return false end
    end
    return true
end

-- A technology a lab can actually work on. Trigger technologies (craft N of an item)
-- have no research units, complete outside the lab entirely, and cannot be queued --
-- listing them would offer choices that silently do nothing.
local function is_lab_researchable(tech)
    local ingredients = tech.research_unit_ingredients
    return ingredients ~= nil and #ingredients > 0
end

-- Every not-yet-researched technology whose prerequisites are met, cheapest first --
-- the frontier Nauvis could pick from next, regardless of whether it currently has
-- the packs to actually fund it (see can_supply).
function M.get_available_technologies()
    local state = game.forces[nauvis.FORCE_NAME]
    if not state then return {} end
    local list = {}
    for _, tech in pairs(state.technologies) do
        if tech.enabled and not tech.researched and is_lab_researchable(tech) and prerequisites_met(tech) then
            table.insert(list, tech.name)
        end
    end
    table.sort(list, function(a, b)
        local ta, tb = state.technologies[a], state.technologies[b]
        local cost_a = ta.research_unit_count * ta.research_unit_energy
        local cost_b = tb.research_unit_count * tb.research_unit_energy
        if cost_a == cost_b then return a < b end
        return cost_a < cost_b
    end)
    return list
end

-- Whether Nauvis's own assemblers can actually produce this technology's packs.
-- Not a hard gate -- a player may queue anything on the frontier -- but it drives the
-- warning shown next to the choice.
function M.can_supply(tech_name)
    local state = game.forces[nauvis.FORCE_NAME]
    local tech = state and state.technologies[tech_name]
    if not tech then return false end
    local ingredients = tech.research_unit_ingredients
    if not ingredients or #ingredients == 0 then return false end
    for _, ingredient in pairs(ingredients) do
        if not NAUVIS_PACKS[ingredient.name] then return false end
    end
    return true
end

function M.get_next_research()
    return storage.nauvis_research and storage.nauvis_research.next or nil
end

-- Nauvis never picks its own research; it only ever works on what a player has applied
-- via the company monitor. Starting idle is deliberate -- research begins when someone
-- decides it should.
function M.start_pending_research()
    local state = game.forces[nauvis.FORCE_NAME]
    if not state or state.current_research then return end
    local pending = M.get_next_research()
    if not pending then return end

    local tech = state.technologies[pending]
    if not tech or tech.researched or not tech.enabled or not prerequisites_met(tech) then
        storage.nauvis_research.next = nil
        return
    end
    if state.add_research(pending) then
        storage.nauvis_research.next = nil
    end
end

function M.set_next_research(tech_name)
    storage.nauvis_research = storage.nauvis_research or {}
    if not tech_name then
        storage.nauvis_research.next = nil
        return true
    end

    local state = game.forces[nauvis.FORCE_NAME]
    local tech = state and state.technologies[tech_name]
    if not tech then return false, "Unknown technology." end
    if tech.researched then return false, "Nauvis has already researched that." end
    if not tech.enabled or not prerequisites_met(tech) then
        return false, "Prerequisites for that technology are not met."
    end

    storage.nauvis_research.next = tech_name
    M.start_pending_research()
    return true
end

function M.current_research_name()
    local state = game.forces[nauvis.FORCE_NAME]
    if not state or not state.current_research then return nil end
    return state.current_research.name
end

function M.init()
    storage.nauvis_research = storage.nauvis_research or {}

    local state = game.forces[nauvis.FORCE_NAME]
    if state then
        for _, name in ipairs(TRIGGER_TECHS) do
            local tech = state.technologies[name]
            if tech and not tech.researched then
                tech.researched = true
            end
        end
    end
    M.start_pending_research()
    M.sync_all()
    M.ensure_permission_group()
    M.lock_all_players()
end

function M.handle_research_finished(force)
    if not force or not force.valid then return end
    if not nauvis.is_state(force.name) then return end
    M.start_pending_research()
    M.sync_all()
end

function M.block_lab(entity, player_index)
    if not entity or not entity.valid then return false end
    if entity.type ~= "lab" then return false end
    if not M.is_restricted_force(entity.force) then return false end

    local item_name = entity.prototype.items_to_place_this
        and entity.prototype.items_to_place_this[1]
        and entity.prototype.items_to_place_this[1].name
    entity.destroy()

    local player = player_index and game.get_player(player_index)
    if player then
        if item_name then
            player.insert({ name = item_name, count = 1 })
        end
        player.print("Labs are Nauvis property. Research is not available to companies.")
    end
    return true
end

return M
