local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")

local M = {}

local STARTING_CREDITS = 5000
local BUY_MULTIPLIER = 1.05

function M.create_credits_gui(player)
    if player.gui.screen.otc_credits_frame then
        player.gui.screen.otc_credits_frame.destroy()
    end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_credits_frame",
        direction = "vertical",
    }
    frame.style.size = {120, 70}
    frame.style.padding = 4
    frame.style.bottom_padding = 8

    local screen_width = player.display_resolution.width
    local scale = player.display_scale
    local frame_width = 120 * scale
    frame.location = {x = (screen_width - frame_width) / 2, y = 0}

    local title_flow = frame.add {
        type = "flow",
        name = "title_flow",
        direction = "horizontal",
    }
    title_flow.style.vertical_align = "center"
    title_flow.drag_target = frame

    title_flow.add {
        type = "label",
        style = "frame_title",
        caption = "Credits",
        ignored_by_interaction = true,
    }

    local drag = title_flow.add {
        type = "empty-widget",
        style = "draggable_space",
        ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.horizontally_stretchable = true

    local player_data = storage.players and storage.players[player.index]
    local credits = player_data and player_data.credits or STARTING_CREDITS
    local label = frame.add {
        type = "label",
        name = "otc_credits_label",
        caption = utils.format_number(credits),
    }
    label.style.font = "default-listbox"
    label.style.horizontal_align = "center"
    label.style.horizontally_stretchable = true

    return frame
end

function M.update_credits_gui(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    local frame = player.gui.screen.otc_credits_frame
    if not frame then return end
    local label = frame.otc_credits_label
    if not label then return end
    local player_data = storage.players and storage.players[player_index]
    local credits = player_data and player_data.credits or 0
    label.caption = utils.format_number(credits)
end

function M.rebuild_market_list(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    local frame = player.gui.screen.otc_market_frame
    if not frame then return end

    local search = ""
    local search_frame = frame.otc_market_search_frame
    if search_frame and search_frame.visible then
        local field = search_frame.otc_market_search
        if field and field.text then
            search = string.lower(field.text)
        end
    end

    local old_inner = frame.otc_market_inner
    if old_inner then old_inner.destroy() end

    local inner = frame.add {
        type = "frame",
        name = "otc_market_inner",
        style = "inside_deep_frame",
    }
    inner.style.horizontally_stretchable = true
    inner.style.vertically_stretchable = true
    inner.style.padding = 2

    local list = inner.add {
        type = "scroll-pane",
        name = "otc_market_list",
        direction = "vertical",
    }
    list.style.height = 420
    list.style.horizontally_stretchable = true

    for _, item in pairs(player_data.allowed_items) do
        if search == "" or string.find(string.lower(item.name), search, 1, true) then
            local row = list.add {
                type = "flow",
                direction = "horizontal",
            }
            row.style.vertical_align = "center"

            row.add {
                type = "sprite-button",
                style = "slot_button",
            }

            row.add {
                type = "sprite",
                sprite = "item/" .. item.name,
            }

            row.add {
                type = "label",
                caption = "₾" .. utils.format_number(math.floor(utils.get_price(item.name) * BUY_MULTIPLIER + 0.5)),
            }
        end
    end
end

function M.create_market_gui(player)
    if player.gui.screen.otc_market_frame then
        player.gui.screen.otc_market_frame.destroy()
    end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_market_frame",
        direction = "vertical",
        style = "frame",
    }
    frame.style.size = {180, 500}
    frame.style.padding = 4

    local title_flow = frame.add {
        type = "flow",
        name = "title_flow",
        direction = "horizontal",
    }
    title_flow.style.vertical_align = "center"
    title_flow.drag_target = frame

    title_flow.add {
        type = "label",
        style = "frame_title",
        caption = "Market",
        ignored_by_interaction = true,
    }

    local drag = title_flow.add {
        type = "empty-widget",
        style = "draggable_space",
        ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.horizontally_stretchable = true

    title_flow.add {
        type = "sprite-button",
        name = "otc_market_search_button",
        style = "tool_button",
        sprite = "utility/search",
    }

    local search_flow = frame.add {
        type = "flow",
        name = "otc_market_search_frame",
        direction = "horizontal",
    }
    search_flow.style.horizontally_stretchable = true
    search_flow.visible = false

    search_flow.add {
        type = "sprite",
        sprite = "utility/search",
    }

    local search_field = search_flow.add {
        type = "textfield",
        name = "otc_market_search",
    }
    search_field.style.horizontally_stretchable = true

    local player_data = storage.players and storage.players[player.index]
    if player_data then
        player_data.allowed_items = item_filter.get_allowed_items(player.force)
    end

    M.rebuild_market_list(player)

    return frame
end

function M.init_player(player)
    storage.players = storage.players or {}
    if not storage.players[player.index] then
        storage.players[player.index] = { credits = STARTING_CREDITS }
    end
    M.create_credits_gui(player)
    M.create_market_gui(player)
end

return M
