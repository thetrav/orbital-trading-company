local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local trading_history = require("scripts.trading_history")

local M = {}

local HISTORY_LENGTH = 60
local TOTAL_KEY = "__total__"
local CHART_CHARS = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
local CHART_LEVELS = #CHART_CHARS

local INCOME_COLOR = { r = 0.2, g = 0.8, b = 0.2 }
local EXPENSE_COLOR = { r = 0.8, g = 0.2, b = 0.2 }
local PROFIT_COLOR = { r = 0.9, g = 0.9, b = 0.1 }

local function get_selected_force(player)
    local player_data = storage.players and storage.players[player.index]
    if player_data and player_data.trading_selected_force then
        return player_data.trading_selected_force
    end
    return player.force.name
end

local function set_selected_force(player, force_name)
    local player_data = storage.players and storage.players[player.index]
    if player_data then
        player_data.trading_selected_force = force_name
    end
end

local function build_sparkline(history, compute_fn)
    local parts = {}
    local max_val = 0
    local values = {}
    for age = HISTORY_LENGTH - 1, 0, -1 do
        local slot = history and history[(storage.trading_history_head - age) % HISTORY_LENGTH + 1]
        local v = slot and compute_fn(slot) or 0
        table.insert(values, v)
        if math.abs(v) > max_val then max_val = math.abs(v) end
    end
    if max_val <= 0 then
        return string.rep("▁", HISTORY_LENGTH), 0
    end
    for _, v in ipairs(values) do
        local level = math.floor((math.abs(v) / max_val) * CHART_LEVELS + 0.5)
        if level > CHART_LEVELS then level = CHART_LEVELS end
        if level < 1 then level = 1 end
        table.insert(parts, CHART_CHARS[level])
    end
    return table.concat(parts), max_val
end

local function update_chart()
    for _, player in pairs(game.connected_players) do
        local frame = player.gui.screen.otc_trading_frame
        if not frame then goto continue end
        local panels = frame.otc_trading_panels
        if not panels then goto continue end

        local force_name = get_selected_force(player)
        local total_history = trading_history.get_total_history(force_name)

        local series = {
            { key = "income", label = panels.otc_panel_income, color = INCOME_COLOR,
              compute = trading_history.income_from_slot },
            { key = "expense", label = panels.otc_panel_expense, color = EXPENSE_COLOR,
              compute = trading_history.expense_from_slot },
            { key = "profit", label = panels.otc_panel_profit, color = PROFIT_COLOR,
              compute = function(s)
                  return trading_history.income_from_slot(s) - trading_history.expense_from_slot(s)
              end },
        }

        local latest_slot = trading_history.get_slot(force_name, TOTAL_KEY, 1)

        for _, s in ipairs(series) do
            local sparkline, _ = build_sparkline(total_history, s.compute)
            local spark_label = s.label.otc_trading_spark
            if spark_label then
                spark_label.caption = sparkline
            end
            local rate_label = s.label.otc_trading_rate
            if rate_label then
                local rate = latest_slot and s.compute(latest_slot) or 0
                local prefix = rate >= 0 and "+" or ""
                rate_label.caption = prefix .. "₾" .. utils.format_number(math.floor(rate + 0.5)) .. "/s"
                if s.key == "profit" then
                    rate_label.style.font_color = rate >= 0 and PROFIT_COLOR or EXPENSE_COLOR
                end
            end
        end

        ::continue::
    end
end

local function rebuild_list(player)
    local frame = player.gui.screen.otc_trading_frame
    if not frame then return end
    local list_frame = frame.otc_trading_list
    if not list_frame then return end

    local old_scroll = list_frame.otc_trading_scroll
    if old_scroll then old_scroll.destroy() end
    local old_search = list_frame.otc_trading_search_flow
    if old_search then old_search.destroy() end

    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    local search_text = player_data.trading_search_text or ""
    local force_name = get_selected_force(player)

    local search_flow = list_frame.add {
        type = "flow",
        name = "otc_trading_search_flow",
        direction = "horizontal",
    }
    search_flow.style.horizontal_spacing = 2

    local search_field = search_flow.add {
        type = "textfield",
        name = "otc_trading_search",
    }
    search_field.style.width = 160
    if search_text ~= "" then search_field.text = search_text end

    local force_flow = search_flow.add {
        type = "flow",
        name = "otc_trading_force_flow",
        direction = "horizontal",
    }
    force_flow.style.horizontal_spacing = 4
    force_flow.style.left_margin = 8

    force_flow.add {
        type = "label",
        caption = "Force:",
    }

    local forces = trading_history.get_all_forces()
    local force_dropdown = force_flow.add {
        type = "drop-down",
        name = "otc_trading_force_dropdown",
        items = forces,
    }

    local selected_index = 1
    for i, f in ipairs(forces) do
        if f == force_name then
            selected_index = i
            break
        end
    end
    force_dropdown.selected_index = selected_index

    local scroll = list_frame.add {
        type = "scroll-pane",
        name = "otc_trading_scroll",
        direction = "vertical",
    }
    scroll.style.height = 250
    scroll.style.horizontally_stretchable = true

    local total_slot = trading_history.get_slot(force_name, TOTAL_KEY, 1)
    local total_income = total_slot and trading_history.income_from_slot(total_slot) or 0
    local total_expense = total_slot and trading_history.expense_from_slot(total_slot) or 0
    local total_net = total_income - total_expense

    local total_row = scroll.add {
        type = "flow",
        name = "otc_trading_row_" .. TOTAL_KEY,
        direction = "horizontal",
    }
    total_row.style.vertical_align = "center"

    total_row.add {
        type = "label",
        caption = "Total",
        style = "caption_label",
    }

    local ilbl = total_row.add {
        type = "label",
        caption = "  I:₾" .. utils.format_number(math.floor(total_income + 0.5)) .. "/s",
    }
    ilbl.style.font_color = INCOME_COLOR

    local elbl = total_row.add {
        type = "label",
        caption = "  E:₾" .. utils.format_number(math.floor(total_expense + 0.5)) .. "/s",
    }
    elbl.style.font_color = EXPENSE_COLOR

    local nlbl = total_row.add {
        type = "label",
        caption = "  N:₾" .. utils.format_number(math.floor(total_net + 0.5)) .. "/s",
    }
    nlbl.style.font_color = total_net >= 0 and PROFIT_COLOR or EXPENSE_COLOR

    local allowed = item_filter.get_allowed_items(game.forces[force_name] or player.force)

    for _, item in ipairs(allowed) do
        local matches = search_text == "" or string.find(string.lower(item.name),
            string.lower(search_text), 1, true)
        if not matches then goto continue end

        local slot = trading_history.get_slot(force_name, item.name, 1)
        local income = slot and trading_history.income_from_slot(slot) or 0
        local expense = slot and trading_history.expense_from_slot(slot) or 0
        local net = income - expense

        local row = scroll.add {
            type = "flow",
            name = "otc_trading_row_" .. item.name,
            direction = "horizontal",
        }
        row.style.vertical_align = "center"

        row.add {
            type = "sprite",
            sprite = "item/" .. item.name,
        }

        row.add {
            type = "label",
            caption = " " .. item.name,
        }

        local ri = row.add {
            type = "label",
            caption = "  I:₾" .. utils.format_number(math.floor(income + 0.5)) .. "/s",
        }
        ri.style.font_color = INCOME_COLOR

        local re = row.add {
            type = "label",
            caption = "  E:₾" .. utils.format_number(math.floor(expense + 0.5)) .. "/s",
        }
        re.style.font_color = EXPENSE_COLOR

        local rn = row.add {
            type = "label",
            caption = "  N:₾" .. utils.format_number(math.floor(net + 0.5)) .. "/s",
        }
        rn.style.font_color = net >= 0 and PROFIT_COLOR or EXPENSE_COLOR

        ::continue::
    end
end

function M.create_trading_gui(player)
    local frame = player.gui.screen.otc_trading_frame
    if frame then return end

    frame = player.gui.screen.add {
        type = "frame",
        name = "otc_trading_frame",
        direction = "vertical",
    }
    frame.style.size = {700, 520}
    frame.style.padding = 6
    frame.auto_center = true

    local title_flow = frame.add {
        type = "flow",
        direction = "horizontal",
    }
    title_flow.style.vertical_align = "center"

    local title = title_flow.add {
        type = "label",
        style = "frame_title",
        caption = "Trading Activity",
        ignored_by_interaction = true,
    }
    title.style.horizontally_stretchable = true

    local drag = title_flow.add {
        type = "empty-widget",
        style = "draggable_space",
        ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.horizontally_stretchable = true

    title_flow.add {
        type = "button",
        name = "otc_trading_close",
        caption = "✕",
        style = "frame_action_button",
    }

    local panels = frame.add {
        type = "flow",
        name = "otc_trading_panels",
        direction = "horizontal",
    }
    panels.style.horizontal_spacing = 4

    local panel_configs = {
        { key = "income", title = "Income", color = INCOME_COLOR },
        { key = "expense", title = "Expense", color = EXPENSE_COLOR },
        { key = "profit", title = "Profit", color = PROFIT_COLOR },
    }

    for _, cfg in ipairs(panel_configs) do
        local p = panels.add {
            type = "frame",
            name = "otc_panel_" .. cfg.key,
            direction = "vertical",
            style = "inside_deep_frame",
        }
        p.style.horizontally_stretchable = true
        p.style.padding = 6

        p.add {
            type = "label",
            caption = cfg.title,
            style = "caption_label",
        }
        p.add {
            type = "label",
            caption = "",
            style = "heading_2_label",
            name = "otc_trading_rate",
        }
        local spark = p.add {
            type = "label",
            name = "otc_trading_spark",
            caption = string.rep("▁", HISTORY_LENGTH),
        }
        spark.style.font = "default-small"
    end

    local list_frame = frame.add {
        type = "frame",
        name = "otc_trading_list",
        direction = "vertical",
        style = "inside_deep_frame",
    }
    list_frame.style.horizontally_stretchable = true
    list_frame.style.vertically_stretchable = true
    list_frame.style.padding = 2
    list_frame.style.margin = { 6, 0 }

    rebuild_list(player)
    update_chart()

    player.set_shortcut_toggled("otc-trading", true)
end

function M.refresh()
    update_chart()
    for _, player in pairs(game.connected_players) do
        if player.gui.screen.otc_trading_frame then
            rebuild_list(player)
        end
    end
end

function M.handle_search(player, text)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end
    player_data.trading_search_text = text
    rebuild_list(player)
end

function M.handle_force_change(player, force_name)
    set_selected_force(player, force_name)
    rebuild_list(player)
    update_chart()
end

function M.close(player)
    local frame = player.gui.screen.otc_trading_frame
    if frame then
        frame.destroy()
        player.set_shortcut_toggled("otc-trading", false)
    end
end

return M