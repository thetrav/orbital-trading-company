local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local stock = require("scripts.stock")

local M = {}

local BUY_MULTIPLIER = 1.01

local function get_company_credits(player_index)
    local player_data = storage.players and storage.players[player_index]
    if not player_data then return 0 end
    local company_name = player_data.company
    if not company_name then return 0 end
    local company = storage.companies and storage.companies[company_name]
    return company and company.credits or 0
end

local function update_credits_gui(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    local frame = player.gui.screen.otc_credits_frame
    if not frame then return end

    local player_data = storage.players and storage.players[player_index]
    local company_name = player_data and player_data.company

    local company_row = frame.otc_credits_company_row
    if company_row then
        local company_name_label = company_row.otc_credits_company_name
        if company_name_label then
            company_name_label.caption = company_name or "No Company"
        end
        local label = company_row.otc_credits_label
        if label then
            label.caption = utils.format_number(get_company_credits(player_index))
        end
    end

    local personal_row = frame.otc_credits_personal_row
    if personal_row then
        local personal_name_label = personal_row.otc_credits_personal_name
        if personal_name_label then
            personal_name_label.caption = player.name
        end
        local personal_label = personal_row.otc_personal_credits_label
        if personal_label then
            personal_label.caption = utils.format_number(player_data and player_data.personal_credits or 0)
        end
    end
end

function M.update_credits_gui(player_index)
    update_credits_gui(player_index)
end

function M.update_all_forces_credits()
    for _, player in pairs(game.connected_players) do
        update_credits_gui(player.index)
    end
end

function M.create_credits_gui(player)
    if player.gui.screen.otc_credits_frame then
        player.gui.screen.otc_credits_frame.destroy()
    end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_credits_frame",
        direction = "vertical",
    }
    frame.style.size = {120, 96}
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
    local company_name = player_data and player_data.company

    local company_row = frame.add { type = "flow", name = "otc_credits_company_row", direction = "horizontal" }
    company_row.style.vertical_align = "center"
    company_row.add {
        type = "label",
        name = "otc_credits_company_name",
        caption = company_name or "No Company",
        style = "bold_label",
    }
    local credits = get_company_credits(player.index)
    local label = company_row.add {
        type = "label",
        name = "otc_credits_label",
        caption = utils.format_number(credits),
    }
    label.style.font = "default-listbox"
    label.style.horizontal_align = "center"
    label.style.horizontally_stretchable = true

    local personal_row = frame.add { type = "flow", name = "otc_credits_personal_row", direction = "horizontal" }
    personal_row.style.vertical_align = "center"
    personal_row.add {
        type = "label",
        name = "otc_credits_personal_name",
        caption = player.name,
        style = "bold_label",
    }
    local personal_credits = player_data and player_data.personal_credits or 0
    local personal_label = personal_row.add {
        type = "label",
        name = "otc_personal_credits_label",
        caption = utils.format_number(personal_credits),
    }
    personal_label.style.font = "default-listbox"
    personal_label.style.horizontal_align = "center"
    personal_label.style.horizontally_stretchable = true

    return frame
end

local function get_player_filter(player_index)
    local player_data = storage.players and storage.players[player_index]
    return player_data and player_data.market_filter or "all"
end

local function is_item_visible(item_name, player_index)
    local mode = get_player_filter(player_index)
    if mode == "none" then return false end
    if mode == "all" then return true end
    local player_data = storage.players and storage.players[player_index]
    return player_data and player_data.pinned_items and player_data.pinned_items[item_name] or false
end

function M.apply_stock_label(label, item_name)
    local count = utils.get_stock(item_name)
    if count <= 0 then
        label.caption = "sold out"
        label.style.font_color = {r = 0.9, g = 0.25, b = 0.25}
    elseif count < stock.TARGET_STOCK / 4 then
        label.caption = utils.format_number(count)
        label.style.font_color = {r = 0.95, g = 0.7, b = 0.2}
    else
        label.caption = utils.format_number(count)
        label.style.font_color = {r = 0.6, g = 0.6, b = 0.6}
    end
end

function M.rebuild_market_list(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    if not player_data.allowed_items then
        player_data.allowed_items = item_filter.get_allowed_items(player.force)
    end

    local frame = player.gui.screen.otc_market_frame
    if not frame then return end

    local search = ""
    local search_frame = frame.title_flow.otc_market_search_frame
    if search_frame and search_frame.visible then
        local field = search_frame.otc_market_search
        if field and field.text then
            search = string.lower(field.text)
        end
    end

    local old_filter = frame.otc_market_filter_flow
    if old_filter then old_filter.destroy() end

    local old_inner = frame.otc_market_inner
    if old_inner then old_inner.destroy() end

    local mode = get_player_filter(player.index)
    local modes = {"all", "pinned", "none"}
    local labels = {"All", "Pinned", "None"}

    local filter_flow = frame.add {
        type = "flow",
        name = "otc_market_filter_flow",
        direction = "horizontal",
    }
    filter_flow.style.horizontal_spacing = 2
    filter_flow.style.bottom_margin = 4

    for i, m in ipairs(modes) do
        local btn = filter_flow.add {
            type = "sprite-button",
            name = "otc_market_filter_" .. m,
            caption = labels[i],
            style = mode == m and "button" or "tool_button",
        }
        btn.style.width = 62
    end

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
    list.style.height = 400
    list.style.horizontally_stretchable = true

    player_data.pinned_items = player_data.pinned_items or {}

    local rendered = 0
    for _, item in pairs(player_data.allowed_items or {}) do
        local matches_search = search == "" or string.find(string.lower(item.name), search, 1, true)
        local matches_filter = is_item_visible(item.name, player.index)
        if matches_search and matches_filter then
            local row = list.add {
                type = "flow",
                name = "otc_market_row_" .. item.name,
                direction = "horizontal",
            }
            row.style.vertical_align = "center"

            local pinned = player_data.pinned_items[item.name] or false
            row.add {
                type = "checkbox",
                name = "otc_pin_" .. item.name,
                state = pinned,
            }

            row.add {
                type = "sprite",
                sprite = "item/" .. item.name,
            }

            local effective_price = math.floor(utils.get_price(item.name) * BUY_MULTIPLIER + 0.5)
            row.add {
                type = "label",
                name = "otc_price_" .. item.name,
                caption = "₾" .. utils.format_number(effective_price),
            }

            local offset = utils.get_price_offset(item.name)
            local trend_text = ""
            local trend_color = {r = 0.6, g = 0.6, b = 0.6}
            if offset > 0.5 then
                trend_text = "▲"
                trend_color = {r = 0.2, g = 0.8, b = 0.2}
            elseif offset < -0.5 then
                trend_text = "▼"
                trend_color = {r = 0.8, g = 0.2, b = 0.2}
            end
            local trend = row.add {
                type = "label",
                name = "otc_trend_" .. item.name,
                caption = trend_text,
            }
            trend.style.font_color = trend_color

            local stock_label = row.add {
                type = "label",
                name = "otc_stock_" .. item.name,
            }
            stock_label.style.horizontal_align = "right"
            stock_label.style.horizontally_stretchable = true
            M.apply_stock_label(stock_label, item.name)
            rendered = rendered + 1
        end
    end
end

function M.refresh_market_prices(player)
    local frame = player.gui.screen.otc_market_frame
    if not frame then return end
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end
    local list = frame.otc_market_inner and frame.otc_market_inner.otc_market_list
    if not list then return end

    for _, item in pairs(player_data.allowed_items or {}) do
        local row = list["otc_market_row_" .. item.name]
        if not row or not row.valid then goto continue end

        local price_label = row["otc_price_" .. item.name]
        if price_label and price_label.valid then
            local effective_price = math.floor(utils.get_price(item.name) * BUY_MULTIPLIER + 0.5)
            price_label.caption = "₾" .. utils.format_number(effective_price)
        end

        local stock_label = row["otc_stock_" .. item.name]
        if stock_label and stock_label.valid then
            M.apply_stock_label(stock_label, item.name)
        end

        local trend_label = row["otc_trend_" .. item.name]
        if trend_label and trend_label.valid then
            local offset = utils.get_price_offset(item.name)
            local trend_text = ""
            local trend_color = {r = 0.6, g = 0.6, b = 0.6}
            if offset > 0.5 then
                trend_text = "▲"
                trend_color = {r = 0.2, g = 0.8, b = 0.2}
            elseif offset < -0.5 then
                trend_text = "▼"
                trend_color = {r = 0.8, g = 0.2, b = 0.2}
            end
            trend_label.caption = trend_text
            trend_label.style.font_color = trend_color
        end
        ::continue::
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
    frame.style.size = {210, 500}
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
        name = "otc_market_drag",
        style = "draggable_space",
        ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.horizontally_stretchable = true

    local search_flow = title_flow.add {
        type = "flow",
        name = "otc_market_search_frame",
        direction = "horizontal",
    }
    search_flow.visible = false

    local search_field = search_flow.add {
        type = "textfield",
        name = "otc_market_search",
    }
    search_field.style.width = 80

    title_flow.add {
        type = "sprite-button",
        name = "otc_market_search_button",
        style = "tool_button",
        sprite = "utility/search",
    }

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
        storage.players[player.index] = {}
    end
    M.create_credits_gui(player)
    M.create_market_gui(player)
end

return M
