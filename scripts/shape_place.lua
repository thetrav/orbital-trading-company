local shape_registry = require("scripts.shape_registry")
local shape_def = require("scripts.shape_def")
local room_builder = require("scripts.room_builder")
local platform = require("scripts.platform")

local M = {}

M.MARKER_PREFIX = "otc-place-marker-"
M.ITEM_PREFIX = "otc-place-"

-- Hyphens are Lua pattern quantifiers, so the prefix has to be escaped rather
-- than concatenated raw into a pattern.
local MARKER_PATTERN = "^" .. M.MARKER_PREFIX:gsub("%-", "%%-") .. "(.+)$"

-- Fixed Nauvis builds belong to Nauvis; nothing here goes to a company force.
local FORCE_NAME = "Nauvis"

-- Placing from the cursor is limited by build reach, which makes a 22-tile
-- room impossible to land from where you are standing. The bonus is lifted
-- while the tool is held and put back the moment it is put down.
local REACH_BONUS = 1000

local function state()
    storage.shape_place = storage.shape_place or {}
    storage.shape_place.selected = storage.shape_place.selected or {}
    storage.shape_place.clear = storage.shape_place.clear or {}
    storage.shape_place.reach = storage.shape_place.reach or {}
    return storage.shape_place
end

local function grant_reach(player)
    local reach = state().reach
    local force = player.force
    if reach[force.name] == nil then
        reach[force.name] = force.character_build_distance_bonus
    end
    force.character_build_distance_bonus = REACH_BONUS
end

local function revoke_reach(player)
    local reach = state().reach
    local force = player.force
    local previous = reach[force.name]
    if previous ~= nil then
        force.character_build_distance_bonus = previous
        reach[force.name] = nil
    end
end

function M.init()
    state()
end

function M.selected(player)
    return state().selected[player.index]
end

local function clear_enabled(player)
    local value = state().clear[player.index]
    if value == nil then return true end
    return value
end

local function footprint(def)
    local box = def.clearance_box or shape_def.tile_bounds(def)
    if not box then return 1, 1 end
    return box[2][1] - box[1][1] + 1, box[2][2] - box[1][2] + 1
end

function M.close(player)
    local frame = player.gui.screen.otc_place_frame
    if frame then frame.destroy() end
    M.clear_cursor(player)
end

--- Put the tool down: empty the cursor and hand back the normal build reach.
function M.clear_cursor(player)
    local stack = player.cursor_stack
    if stack and stack.valid_for_read
        and string.sub(stack.name, 1, #M.ITEM_PREFIX) == M.ITEM_PREFIX then
        stack.clear()
    end
    revoke_reach(player)
end

local function list_of(frame)
    local inner = frame and frame.otc_place_inner
    return inner and inner.otc_place_list
end

function M.refresh(player)
    local list = list_of(player.gui.screen.otc_place_frame)
    if not list then return end
    local selected = M.selected(player)
    for _, row in ipairs(list.children) do
        local button = row.children and row.children[1]
        if button and button.type == "button" then
            button.toggled = (button.name == "otc_place_shape_" .. tostring(selected))
        end
    end
end

function M.open(player)
    M.close(player)

    local frame = player.gui.screen.add {
        type = "frame", name = "otc_place_frame", direction = "vertical",
    }
    -- Down the left edge, not centred: the middle of the screen is exactly
    -- where you want to be clicking.
    frame.auto_center = false
    frame.location = { x = math.floor(16 * player.display_scale), y = math.floor(120 * player.display_scale) }
    frame.style.padding = 4

    local title_flow = frame.add { type = "flow", name = "title_flow", direction = "horizontal" }
    title_flow.style.vertical_align = "center"
    title_flow.drag_target = frame

    title_flow.add {
        type = "label", style = "frame_title", caption = "Place shape",
        ignored_by_interaction = true,
    }
    local drag = title_flow.add {
        type = "empty-widget", style = "draggable_space", ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.minimal_width = 40
    drag.style.horizontally_stretchable = true
    title_flow.add {
        type = "sprite-button", name = "otc_place_close", sprite = "utility/close",
        style = "frame_action_button", tooltip = { "gui.close" },
    }

    local inner = frame.add { type = "frame", name = "otc_place_inner", style = "inside_deep_frame" }
    inner.style.padding = 4

    local list = inner.add { type = "scroll-pane", name = "otc_place_list", direction = "vertical" }
    list.style.maximal_height = 400
    list.style.minimal_width = 260

    for _, name in ipairs(shape_registry.names()) do
        local width, height = footprint(shape_registry.get(name))
        local row = list.add { type = "flow", direction = "horizontal" }
        row.style.vertical_align = "center"
        row.style.horizontally_stretchable = true

        local button = row.add {
            type = "button",
            name = "otc_place_shape_" .. name,
            caption = name,
            style = "list_box_item",
            mouse_button_filter = { "left" },
        }
        button.style.horizontally_stretchable = true

        local size = row.add {
            type = "label",
            caption = width .. "x" .. height,
            ignored_by_interaction = true,
        }
        size.style.minimal_width = 50
        size.style.horizontal_align = "right"
    end

    frame.add {
        type = "checkbox",
        name = "otc_place_clear",
        caption = "Clear the area first",
        tooltip = "Destroy whatever already stands inside the shape's footprint."
            .. " Off means overlapping entities simply fail to appear.",
        state = clear_enabled(player),
    }

    frame.add {
        type = "label",
        caption = "Pick a shape, then left-click the map. One placement per pick;"
            .. "\nclick the shape again to place another. Build reach is lifted"
            .. "\nwhile the tool is in your cursor.",
    }

    M.refresh(player)
end

--- Selecting a shape puts its placement item in the cursor, which is what makes
--- Factorio draw the footprint preview under the mouse.
function M.handle_selection(player, name)
    if not shape_registry.get(name) then return end
    state().selected[player.index] = name
    M.refresh(player)
    M.give_item(player, name)
end

function M.handle_clear_toggle(player, enabled)
    state().clear[player.index] = enabled
end

function M.give_item(player, name)
    name = name or M.selected(player)
    if not name then return end
    local item = M.ITEM_PREFIX .. name
    if player.cursor_stack and player.cursor_stack.can_set_stack { name = item } then
        player.cursor_stack.set_stack { name = item, count = 1 }
        grant_reach(player)
    end
end

--- Safety net for the force-wide reach bonus: if the tool leaves the cursor by
--- any route other than placing -- Q, another item, clearing by hand -- the
--- bonus has to come back off.
function M.handle_cursor_changed(player)
    local stack = player.cursor_stack
    local holding = stack and stack.valid_for_read
        and string.sub(stack.name, 1, #M.ITEM_PREFIX) == M.ITEM_PREFIX
    if not holding then revoke_reach(player) end
end

--- Entities already standing where the shape would go. Reported either way:
--- with clearing on they are about to be destroyed, with it off they are what
--- will stop parts of the shape appearing.
local function occupants(surface, box)
    local area = { { box[1][1], box[1][2] }, { box[2][1] + 1, box[2][2] + 1 } }
    local found, total = {}, 0
    for _, entity in ipairs(surface.find_entities_filtered { area = area }) do
        if entity.valid and entity.type ~= "character" then
            found[entity.name] = (found[entity.name] or 0) + 1
            total = total + 1
        end
    end
    local names = {}
    for name, count in pairs(found) do names[#names + 1] = name .. " x" .. count end
    table.sort(names)
    return total, names
end

--- The marker is centred on its footprint; a shape's own origin is the top-left
--- of its clearance box, so shift by half the footprint to get there.
function M.origin_from_marker(def, position)
    local width, height = footprint(def)
    return {
        x = math.floor(position.x - width / 2 + 0.5),
        y = math.floor(position.y - height / 2 + 0.5),
    }
end

--- Called when the dummy marker entity is built. Swaps it for the real shape.
function M.on_marker_built(entity, player_index)
    local name = string.match(entity.name, MARKER_PATTERN)
    if not name then return false end

    local surface = entity.surface
    local position = entity.position
    entity.destroy()

    local player = player_index and game.get_player(player_index)
    local def = shape_registry.get(name)
    if not def then
        if player then player.print("Unknown shape: " .. name) end
        return true
    end

    local origin = M.origin_from_marker(def, position)
    local box = shape_def.clearance_box(def, origin, 0)
    local clear = player and clear_enabled(player) or true

    if box and player then
        local total, names = occupants(surface, box)
        if total > 0 then
            player.print(string.format("%s %d entities in the footprint: %s",
                clear and "Clearing" or "Warning,", total,
                table.concat(names, ", ", 1, math.min(#names, 6))
                    .. (#names > 6 and ", ..." or "")))
        end
    end
    if box and clear then room_builder.clear_area(surface, box) end

    local ctx = platform.build_shape(surface, name, origin, FORCE_NAME)
    if player then
        if ctx then
            player.print(string.format("Placed %q at %d,%d.", name, origin.x, origin.y))
        else
            player.print("Failed to place " .. name .. ".")
        end
        -- One stamp per pick. Holding the tool after a placement made it far
        -- too easy to drop several copies on top of each other.
        M.clear_cursor(player)
    end
    return true
end

function M.register_commands()
    commands.add_command("otc-place-shape",
        "Open the shape placement list, then left-click the map to place the picked shape.",
        function(event)
            local player = game.get_player(event.player_index)
            if not player then return end
            if not player.admin then
                player.print("Only admins can use the shape authoring tools.")
                return
            end
            M.open(player)
            M.give_item(player)
        end)
end

return M
