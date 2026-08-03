local M = {}

M.TOOL_NAME = "otc-shape-config"

-- Roles a shape entity can carry. shape_def buckets any role string it is
-- given, so this list is only what the tool offers; adding one here is enough.
M.ROLES = {
    "supply",
    "intake",
    "drill",
    "lab",
    "gate",
    "computer",
    "pump",
    "silo",
    "teleporter",
    "company_monitor",
}

local NONE = "(none)"
local MAX_ROWS = 40

-- Transport line 1 is the lane 90 degrees counter-clockwise from the direction
-- of travel, so which screen side it lands on depends on the belt's facing.
-- Labelling the pickers by resolved side means "top" means top on every belt,
-- whichever way it points. tools/probes/belt_lane_sides.lua pins the mapping.
local LANE_SIDES = {
    [0] = { "left", "right" },
    [4] = { "top", "bottom" },
    [8] = { "right", "left" },
    [12] = { "bottom", "top" },
}

local function lane_sides(direction)
    return LANE_SIDES[direction or 0] or { "lane 1", "lane 2" }
end

local function state()
    storage.shape_config = storage.shape_config or {}
    storage.shape_config.entities = storage.shape_config.entities or {}
    storage.shape_config.selection = storage.shape_config.selection or {}
    return storage.shape_config
end

function M.init()
    state()
end

local function label_text(entity, role, items)
    local sides = lane_sides(entity.direction)
    local parts = {}
    if items.left and items.left == items.right then
        parts[#parts + 1] = items.left
    else
        if items.left then parts[#parts + 1] = sides[1] .. "=" .. items.left end
        if items.right then parts[#parts + 1] = sides[2] .. "=" .. items.right end
    end
    if #parts == 0 then return role end
    return role .. " " .. table.concat(parts, " ")
end

local function draw_label(entity, role, items)
    return rendering.draw_text {
        text = label_text(entity, role, items),
        surface = entity.surface,
        target = { entity = entity, offset = { 0, -0.9 } },
        color = { r = 0.35, g = 1, b = 0.5 },
        alignment = "center",
        scale = 0.5,
    }
end

local function destroy_label(entry)
    if entry and entry.label and entry.label.valid then
        entry.label.destroy()
    end
end

--- Entries key off unit_number but hold the entity, so a mined or destroyed
--- entity's tag can be swept rather than lingering as an orphan.
local function prune()
    local entities = state().entities
    for unit_number, entry in pairs(entities) do
        if not (entry.entity and entry.entity.valid) then
            destroy_label(entry)
            entities[unit_number] = nil
        end
    end
end

function M.get(unit_number)
    if not unit_number then return nil end
    local entry = state().entities[unit_number]
    if entry and entry.entity and entry.entity.valid then return entry end
    return nil
end

function M.set(entity, role, items)
    if not entity or not entity.valid or not entity.unit_number then return end
    local entities = state().entities
    local unit_number = entity.unit_number
    destroy_label(entities[unit_number])
    if not role then
        entities[unit_number] = nil
        return
    end
    items = items or {}
    entities[unit_number] = {
        entity = entity,
        role = role,
        item_left = items.left,
        item_right = items.right,
        label = draw_label(entity, role, items),
    }
end

local function items_of(entry)
    if not entry then return {} end
    return { left = entry.item_left, right = entry.item_right }
end

--- Carry a tag across a rebuild, which gives the entity a new unit_number and
--- would otherwise orphan it.
function M.migrate(old_unit_number, entity)
    local entities = state().entities
    local entry = entities[old_unit_number]
    if not entry then return end
    destroy_label(entry)
    entities[old_unit_number] = nil
    M.set(entity, entry.role, { left = entry.item_left, right = entry.item_right })
end

function M.clear_all()
    local entities = state().entities
    for unit_number, entry in pairs(entities) do
        destroy_label(entry)
        entities[unit_number] = nil
    end
end

local function selection_for(player)
    return state().selection[player.index] or {}
end

local function find_selected(player, unit_number)
    for _, entity in ipairs(selection_for(player)) do
        if entity.valid and entity.unit_number == unit_number then return entity end
    end
    return nil
end

local function role_index(role)
    if not role then return 1 end
    for index, name in ipairs(M.ROLES) do
        if name == role then return index + 1 end
    end
    return 1
end

function M.close(player)
    local frame = player.gui.screen.otc_shape_config_frame
    if frame then frame.destroy() end
end

local function add_row(list, entity)
    local entry = M.get(entity.unit_number)
    local row = list.add { type = "flow", direction = "horizontal" }
    row.style.vertical_align = "center"
    row.style.horizontally_stretchable = true

    local icon = row.add {
        type = "sprite",
        sprite = "entity/" .. entity.name,
        ignored_by_interaction = true,
    }
    icon.style.size = { 24, 24 }
    icon.style.stretch_image_to_widget_size = true

    local caption = row.add {
        type = "label",
        caption = string.format("%s  (%g, %g)", entity.name, entity.position.x, entity.position.y),
        ignored_by_interaction = true,
    }
    caption.style.minimal_width = 210

    local items = { NONE }
    for _, name in ipairs(M.ROLES) do items[#items + 1] = name end

    local dropdown = row.add {
        type = "drop-down",
        name = "otc_shape_config_role_" .. entity.unit_number,
        items = items,
        selected_index = role_index(entry and entry.role),
    }
    dropdown.style.minimal_width = 140

    -- Two pickers, one per transport lane, captioned with the screen side that
    -- lane actually occupies for this belt's facing. Leaving one empty keeps
    -- that lane clear, which is how you reserve it for an inserter's output.
    local sides = lane_sides(entity.direction)
    for lane, field in ipairs { "left", "right" } do
        local lane_label = row.add { type = "label", caption = sides[lane] }
        lane_label.style.left_padding = 6
        row.add {
            type = "choose-elem-button",
            name = "otc_shape_config_item_" .. entity.unit_number .. "_" .. field,
            elem_type = "item",
            item = entry and entry["item_" .. field] or nil,
            tooltip = "Item fed onto the " .. sides[lane]
                .. " lane. Only used by role=supply; leave empty to keep the lane clear.",
        }
    end
end

function M.open(player)
    M.close(player)
    local selection = selection_for(player)

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_shape_config_frame",
        direction = "vertical",
    }
    frame.auto_center = true
    frame.style.padding = 4

    local title_flow = frame.add { type = "flow", name = "title_flow", direction = "horizontal" }
    title_flow.style.vertical_align = "center"
    title_flow.drag_target = frame

    title_flow.add {
        type = "label",
        style = "frame_title",
        caption = "Shape roles",
        ignored_by_interaction = true,
    }

    local drag = title_flow.add {
        type = "empty-widget",
        style = "draggable_space",
        ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.minimal_width = 40
    drag.style.horizontally_stretchable = true

    title_flow.add {
        type = "sprite-button",
        name = "otc_shape_config_close",
        sprite = "utility/close",
        style = "frame_action_button",
        tooltip = { "gui.close" },
    }

    local inner = frame.add { type = "frame", style = "inside_deep_frame" }
    inner.style.padding = 4

    local list = inner.add {
        type = "scroll-pane",
        name = "otc_shape_config_list",
        direction = "vertical",
    }
    list.style.minimal_width = 720
    list.style.minimal_height = 640
    list.style.maximal_height = 1000
    list.style.horizontally_stretchable = true

    if #selection == 0 then
        list.add { type = "label", caption = "Nothing selected." }
        return
    end

    for _, entity in ipairs(selection) do
        if entity.valid then add_row(list, entity) end
    end
end

--- Position order, so the rows read the way the belts sit on screen rather
--- than in whatever order find_entities happened to return them.
local function sort_selection(entities)
    table.sort(entities, function(a, b)
        if a.position.y ~= b.position.y then return a.position.y < b.position.y end
        if a.position.x ~= b.position.x then return a.position.x < b.position.x end
        return a.unit_number < b.unit_number
    end)
end

function M.on_selected_area(event, clearing)
    if event.item ~= M.TOOL_NAME then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    prune()

    local selection = {}
    for _, entity in ipairs(event.entities) do
        if entity.valid and entity.unit_number and entity.name ~= "otc-shape-marker" then
            selection[#selection + 1] = entity
        end
    end
    sort_selection(selection)

    if clearing then
        local cleared = 0
        for _, entity in ipairs(selection) do
            if M.get(entity.unit_number) then
                M.set(entity, nil)
                cleared = cleared + 1
            end
        end
        player.print("Cleared " .. cleared .. " shape role tag(s).")
        M.close(player)
        state().selection[player.index] = nil
        return
    end

    local truncated = 0
    if #selection > MAX_ROWS then
        truncated = #selection - MAX_ROWS
        for _ = 1, truncated do table.remove(selection) end
    end

    state().selection[player.index] = selection
    M.open(player)
    -- Put the tool down once the window is up, so the cursor is free to click
    -- on things again.
    if player.cursor_stack and player.cursor_stack.valid_for_read
        and player.cursor_stack.name == M.TOOL_NAME then
        player.cursor_stack.clear()
    end

    if truncated > 0 then
        player.print("Showing the first " .. MAX_ROWS .. " entities; " .. truncated
            .. " more were dropped. Select a smaller area.")
    end
end

function M.handle_role_change(player, unit_number, selected_index)
    local entity = find_selected(player, unit_number)
    if not entity then return end
    local role = selected_index > 1 and M.ROLES[selected_index - 1] or nil
    M.set(entity, role, items_of(M.get(unit_number)))
end

function M.handle_item_change(player, unit_number, lane, item)
    local entity = find_selected(player, unit_number)
    if not entity then return end
    local entry = M.get(unit_number)
    if not entry then return end
    local items = items_of(entry)
    items[lane] = item
    M.set(entity, entry.role, items)
end

function M.give_tool(player)
    if player.cursor_stack and player.cursor_stack.can_set_stack { name = M.TOOL_NAME } then
        player.cursor_stack.set_stack { name = M.TOOL_NAME, count = 1 }
    end
end

function M.register_commands()
    commands.add_command("otc-config-shape",
        "Tag entities with a shape role: run the command, then drag the config tool over them.",
        function(event)
            local player = game.get_player(event.player_index)
            if not player then return end
            if not player.admin then
                player.print("Only admins can use the shape authoring tools.")
                return
            end
            M.give_tool(player)
            player.print("Drag the config tool over entities to tag them. Right-drag clears tags.")
        end)
end

return M
