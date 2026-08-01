local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local trading_history = require("scripts.trading_history")

local chart_render = require("scripts.chart_render")

local M = {}

local TOTAL_KEY = "__total__"

local INCOME_COLOR = { r = 0.2, g = 0.8, b = 0.2 }
local EXPENSE_COLOR = { r = 0.8, g = 0.2, b = 0.2 }
local PROFIT_COLOR = { r = 0.9, g = 0.9, b = 0.1 }

local CHART_KINDS = { "income", "expense", "profit" }
local SCALES = { "second", "ten_second", "ten_minute" }

-- The item list's rates are intentionally decoupled from the chart's selected time
-- scale: always show a smoothed, non-flickering rate averaged over the last fully
-- completed 5-second window.
local LIST_RATE_SCALE = "five_second"

local CHECKBOX_SIZE = 18
local NAME_COLUMN_WIDTH = 200
local VALUE_COLUMN_WIDTH = 95
local VALUE_CELL_WIDTH = CHECKBOX_SIZE + 2 + VALUE_COLUMN_WIDTH
local GRAY_COLOR = { r = 0.6, g = 0.6, b = 0.6 }

local function credits_label(value)
    return utils.format_number(math.floor(value + 0.5))
end

local function default_selection()
    return {
        income = { [TOTAL_KEY] = true },
        expense = { [TOTAL_KEY] = true },
        profit = { [TOTAL_KEY] = true },
    }
end

local function get_chart_selection(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return default_selection() end
    local selection = player_data.trading_chart_selection
    if not selection or type(selection.income) ~= "table" then
        selection = default_selection()
        player_data.trading_chart_selection = selection
    end
    return selection
end

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

local function init_chart_surface()
    if not storage.chart_surface then
        local surface_data = chart_render.create_surface("otc-trading-charts")
        storage.chart_surface = surface_data
    end
    return storage.chart_surface
end

local function get_chart_state(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return nil end
    if not player_data.trading_chart_state then
        player_data.trading_chart_state = {}
    end
    local chart_state = player_data.trading_chart_state
    for _, scale in ipairs(SCALES) do
        if not chart_state[scale] then
            chart_state[scale] = {}
        end
    end
    return chart_state
end

local function get_selected_scale(player)
    local player_data = storage.players and storage.players[player.index]
    if player_data and player_data.trading_selected_scale then
        return player_data.trading_selected_scale
    end
    return "second"
end

local function set_selected_scale(player, scale_key)
    local player_data = storage.players and storage.players[player.index]
    if player_data then
        player_data.trading_selected_scale = scale_key
    end
end

-- The label above each chart shows the total across the whole charted window, so the
-- suffix is the window duration (matching the scale buttons: 1m / 10m / 1h), not the
-- per-bucket duration.
local function get_period_label(scale_key)
    if scale_key == "second" then
        return "/m"
    elseif scale_key == "ten_second" then
        return "/10m"
    elseif scale_key == "ten_minute" then
        return "/h"
    end
    return "/m"
end

local function destroy_render_objects(line_ids)
    if not line_ids then return end
    for _, id in ipairs(line_ids) do
        if id and id.valid then
            id.destroy()
        end
    end
end

local function get_series_color_map(chart, kind, selection)
    local ordered = {}
    for name in pairs(selection[kind]) do
        table.insert(ordered, { name = name, sum = chart.sum[kind][name] or 0 })
    end
    table.sort(ordered, function(a, b)
        if a.sum ~= b.sum then
            return a.sum > b.sum
        end
        return a.name < b.name
    end)
    local palette = chart_render.get_series_colors()
    local colors = {}
    for i, entry in ipairs(ordered) do
        colors[entry.name] = palette[((i - 1) % #palette) + 1]
    end
    return colors
end

local function build_chart_view(chart, kind, selection)
    local data = {}
    for i = 1, chart.length do
        data[i] = chart.data[i][kind]
    end
    local counts = {}
    local sum = {}
    local kind_sum = chart.sum[kind]
    for name in pairs(selection[kind]) do
        counts[name] = chart.length
        sum[name] = kind_sum[name] or 0
    end
    return data, counts, sum
end

local function render_series_on_chunk(state, chart, kind, selection)
    destroy_render_objects(state.line_ids)

    local data, counts, sum = build_chart_view(chart, kind, selection)

    local options = {
        data = data,
        index = chart.index,
        length = chart.length,
        counts = counts,
        sum = sum,
        selected_series = selection[kind],
        label_format = credits_label,
        ttl = 360,
    }

    local line_ids = chart_render.line_graph(state.surface, state.chunk, options)
    state.line_ids = line_ids or {}
end

-- Each panel's rate label is shared by all of that panel's scale states, so it must
-- only ever be written for the scale currently on screen.
local function update_rate_label(state, chart, kind, selection, scale_key)
    local total = chart.sum[kind][TOTAL_KEY] or 0
    local caption = "₾" .. utils.format_number(math.floor(total + 0.5)) .. get_period_label(scale_key)
    if kind == "profit" then
        caption = (total >= 0 and "+" or "") .. caption
    end
    state.rate_label.caption = caption
    local color_map = get_series_color_map(chart, kind, selection)
    state.rate_label.style.font_color = color_map[TOTAL_KEY] or GRAY_COLOR
end

local function render_all_charts(player)
    local frame = player.gui.screen.otc_trading_frame
    if not frame then return end

    local chart_state = get_chart_state(player)
    if not chart_state then return end

    local force_name = get_selected_force(player)
    local selection = get_chart_selection(player)
    local selected_scale = get_selected_scale(player)

    for _, scale_key in ipairs(SCALES) do
        local chart = trading_history.get_chart_data(force_name, scale_key)
        local scale_state = chart_state[scale_key]
        if scale_state then
            for _, cfg_key in ipairs(CHART_KINDS) do
                local state = scale_state[cfg_key]
                if state then
                    render_series_on_chunk(state, chart, cfg_key, selection)
                    if scale_key == selected_scale then
                        update_rate_label(state, chart, cfg_key, selection, scale_key)
                    end
                end
            end
        end
    end
end

local function create_chart_panels(panels, player, surface_data)
    local chart_state = get_chart_state(player)
    if not chart_state then return end
    local selected_scale = get_selected_scale(player)
    chart_state.cameras = chart_state.cameras or {}
    local panel_configs = {
        { key = "income", title = "Income", color = INCOME_COLOR },
        { key = "expense", title = "Expense", color = EXPENSE_COLOR },
        { key = "profit", title = "Profit", color = PROFIT_COLOR },
    }

    for _, cfg in ipairs(panel_configs) do
        local panel = panels.add {
            type = "frame",
            name = "otc_panel_" .. cfg.key,
            direction = "vertical",
            style = "inside_shallow_frame",
        }
        panel.style.width = 300
        panel.style.padding = 0
        panel.style.margin = 0

        local header = panel.add {
            type = "flow",
            name = "otc_panel_header_" .. cfg.key,
            direction = "horizontal",
        }
        header.style.width = 295
        header.style.vertical_align = "center"
        header.style.horizontal_spacing = 2
        header.style.left_margin = 2
        header.style.bottom_margin = 2

        header.add {
            type = "label",
            caption = cfg.title,
            style = "caption_label",
        }

        local rate = header.add {
            type = "label",
            caption = "",
            style = "heading_2_label",
            name = "otc_trading_rate",
        }
        rate.style.font_color = cfg.color

        for _, scale in ipairs(SCALES) do
            local scale_chunk = chart_render.allocate_chunk(surface_data)
            if not scale_chunk then
                chart_state[scale][cfg.key] = nil
            else
                local scale_camera_params = chart_render.get_camera_params(scale_chunk, player.display_scale)

                chart_state[scale][cfg.key] = {
                    chunk = scale_chunk,
                    surface = surface_data.surface,
                    camera_params = scale_camera_params,
                    series_key = cfg.key,
                    panel = panel,
                    rate_label = rate,
                    line_ids = {},
                }
            end
        end

        local initial_state = chart_state[selected_scale][cfg.key]
        if not initial_state then
            panel.add { type = "label", caption = "Error: no chunk available" }
        else
            local camera = panel.add {
                type = "camera",
                name = "otc_camera_" .. cfg.key,
                position = initial_state.camera_params.position,
                surface_index = initial_state.surface.index,
                zoom = initial_state.camera_params.zoom,
            }
            camera.style.width = 300
            camera.style.height = 233
            chart_state.cameras[cfg.key] = camera
        end
    end
end

local function switch_chart_scale(player, scale_key)
    local frame = player.gui.screen.otc_trading_frame
    if not frame then return end

    local chart_state = get_chart_state(player)
    if not chart_state then return end

    local scale_state = chart_state[scale_key]
    if not scale_state then return end

    local force_name = get_selected_force(player)
    local chart = trading_history.get_chart_data(force_name, scale_key)
    local selection = get_chart_selection(player)

    for _, series_key in ipairs(CHART_KINDS) do
        local state = scale_state[series_key]
        local camera = chart_state.cameras and chart_state.cameras[series_key]
        if state and camera and camera.valid then
            camera.position = state.camera_params.position
            camera.zoom = state.camera_params.zoom
            camera.surface_index = state.surface.index
            render_series_on_chunk(state, chart, series_key, selection)
            update_rate_label(state, chart, series_key, selection, scale_key)
        end
    end
end

local function profit_caption(net)
    return (net < 0 and "-" or "") .. "₾" .. utils.format_number(math.floor(math.abs(net) + 0.5)) .. "/s"
end

local function value_cell(parent, checkbox_name, checked, color)
    local checkbox = parent.add {
        type = "checkbox",
        name = checkbox_name,
        state = checked,
    }
    checkbox.style.width = CHECKBOX_SIZE
    checkbox.style.height = CHECKBOX_SIZE
    local lbl = parent.add { type = "label", caption = "" }
    lbl.style.width = VALUE_COLUMN_WIDTH
    lbl.style.font_color = color
    return { checkbox = checkbox, value = lbl }
end

local function add_list_header(scroll)
    local header = scroll.add {
        type = "flow",
        name = "otc_trading_header",
        direction = "horizontal",
    }
    header.style.horizontal_spacing = 2
    header.style.left_margin = 32 + 2
    header.style.bottom_margin = 2

    local header_name = header.add {
        type = "label",
        caption = "Name",
        style = "caption_label",
    }
    header_name.style.width = NAME_COLUMN_WIDTH

    local header_cols = {
        { caption = "Income", color = INCOME_COLOR },
        { caption = "Expense", color = EXPENSE_COLOR },
        { caption = "Profit", color = PROFIT_COLOR },
    }
    for _, col in ipairs(header_cols) do
        local hlbl = header.add {
            type = "label",
            caption = col.caption,
            style = "caption_label",
        }
        hlbl.style.width = VALUE_CELL_WIDTH
        hlbl.style.font_color = col.color
    end
    return header
end

local function add_total_row(scroll, selection)
    local total_row = scroll.add {
        type = "flow",
        name = "otc_trading_row_" .. TOTAL_KEY,
        direction = "horizontal",
    }
    total_row.style.vertical_align = "center"
    total_row.style.horizontal_spacing = 2

    local spacer = total_row.add { type = "empty-widget" }
    spacer.style.width = 32
    spacer.style.height = 1

    local name = total_row.add {
        type = "label",
        caption = "Total",
        style = "caption_label",
    }
    name.style.width = NAME_COLUMN_WIDTH

    return {
        flow = total_row,
        income = value_cell(total_row, "otc_series_income_" .. TOTAL_KEY, selection.income[TOTAL_KEY] or false, GRAY_COLOR),
        expense = value_cell(total_row, "otc_series_expense_" .. TOTAL_KEY, selection.expense[TOTAL_KEY] or false, GRAY_COLOR),
        profit = value_cell(total_row, "otc_series_profit_" .. TOTAL_KEY, selection.profit[TOTAL_KEY] or false, GRAY_COLOR),
    }
end

local function get_list_state(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return nil end
    return player_data.trading_list_state
end

local function populate_rows(player, state)
    local scroll = state.scroll
    local force_name = get_selected_force(player)
    local selection = get_chart_selection(player)
    local allowed = item_filter.get_allowed_items(game.forces[force_name] or player.force)
    state.order = {}
    for _, item in ipairs(allowed) do
        local row = scroll.add {
            type = "flow",
            name = "otc_trading_row_" .. item.name,
            direction = "horizontal",
        }
        row.style.vertical_align = "center"
        row.style.horizontal_spacing = 2

        row.add {
            type = "sprite",
            sprite = "item/" .. item.name,
        }

        local name = row.add {
            type = "label",
            caption = item.name,
        }
        name.style.width = NAME_COLUMN_WIDTH

        state.rows[item.name] = {
            flow = row,
            income = value_cell(row, "otc_series_income_" .. item.name, selection.income[item.name] or false, GRAY_COLOR),
            expense = value_cell(row, "otc_series_expense_" .. item.name, selection.expense[item.name] or false, GRAY_COLOR),
            profit = value_cell(row, "otc_series_profit_" .. item.name, selection.profit[item.name] or false, GRAY_COLOR),
        }
        state.order[#state.order + 1] = item.name
    end
    state.force_name = force_name
end

local function update_total_row(state, selection, color_maps, list_period, list_interval)
    local total_income = (list_period.income[TOTAL_KEY] or 0) / list_interval
    local total_expense = (list_period.expense[TOTAL_KEY] or 0) / list_interval
    local total_net = total_income - total_expense
    local total = state.total
    total.income.value.caption = "₾" .. utils.format_number(math.floor(total_income + 0.5)) .. "/s"
    total.income.value.style.font_color = selection.income[TOTAL_KEY] and color_maps.income[TOTAL_KEY] or GRAY_COLOR
    total.expense.value.caption = "₾" .. utils.format_number(math.floor(total_expense + 0.5)) .. "/s"
    total.expense.value.style.font_color = selection.expense[TOTAL_KEY] and color_maps.expense[TOTAL_KEY] or GRAY_COLOR
    total.profit.value.caption = profit_caption(total_net)
    total.profit.value.style.font_color = selection.profit[TOTAL_KEY] and color_maps.profit[TOTAL_KEY] or GRAY_COLOR
end

local function update_list(player)
    local state = get_list_state(player)
    if not state or not state.scroll or not state.scroll.valid then return end

    local force_name = get_selected_force(player)
    local player_data = storage.players and storage.players[player.index]

    local forces = trading_history.get_all_forces()
    local dropdown_items = state.force_dropdown.items
    local needs_update = #dropdown_items ~= #forces
    if not needs_update then
        for i = 1, #forces do
            if dropdown_items[i] ~= forces[i] then
                needs_update = true
                break
            end
        end
    end
    if needs_update then
        state.force_dropdown.items = forces
    end
    if #forces > 0 then
        local selected_index = 1
        for i, f in ipairs(forces) do
            if f == force_name then
                selected_index = i
                break
            end
        end
        state.force_dropdown.selected_index = selected_index
    end

    local company = storage.companies and storage.companies[force_name]
    local credits = company and company.credits or 0
    if state.balance_label and state.balance_label.valid then
        state.balance_label.caption = "₾" .. utils.format_number(credits)
    end

    local search_text = player_data and player_data.trading_search_text or ""
    local chart = trading_history.get_chart_data(force_name)
    local selection = get_chart_selection(player)

    local color_maps = {}
    for _, kind in ipairs(CHART_KINDS) do
        color_maps[kind] = get_series_color_map(chart, kind, selection)
    end

    local list_period = trading_history.get_previous_period(force_name, LIST_RATE_SCALE)
    local list_interval = trading_history.get_scales()[LIST_RATE_SCALE].interval

    update_total_row(state, selection, color_maps, list_period, list_interval)

    for _, item_name in ipairs(state.order) do
        local row = state.rows[item_name]
        local matches = search_text == "" or string.find(string.lower(item_name),
            string.lower(search_text), 1, true) ~= nil
        row.flow.visible = matches
        if matches then
            local income = (list_period.income[item_name] or 0) / list_interval
            local expense = (list_period.expense[item_name] or 0) / list_interval
            local net = income - expense
            row.income.value.caption = "₾" .. utils.format_number(math.floor(income + 0.5)) .. "/s"
            row.income.value.style.font_color = selection.income[item_name] and color_maps.income[item_name] or GRAY_COLOR
            row.expense.value.caption = "₾" .. utils.format_number(math.floor(expense + 0.5)) .. "/s"
            row.expense.value.style.font_color = selection.expense[item_name] and color_maps.expense[item_name] or GRAY_COLOR
            row.profit.value.caption = profit_caption(net)
            row.profit.value.style.font_color = selection.profit[item_name] and color_maps.profit[item_name] or GRAY_COLOR
        end
    end
end

local function build_list(player, frame)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end
    local list_frame = frame.otc_trading_list
    if not list_frame then return end

    local state = player_data.trading_list_state
    if not state then state = {} end
    state.rows = {}
    state.order = {}
    player_data.trading_list_state = state

    local search_flow = frame.otc_trading_search_flow
    if search_flow then state.search_flow = search_flow end

    local scroll = list_frame.add {
        type = "scroll-pane",
        name = "otc_trading_scroll",
        direction = "vertical",
    }
    scroll.style.horizontally_stretchable = true
    scroll.style.vertically_stretchable = true

    state.search_flow = search_flow
    state.scroll = scroll
    state.header = add_list_header(scroll)
    state.total = add_total_row(scroll, get_chart_selection(player))

    populate_rows(player, state)
    update_list(player)
end

local function rebuild_rows(player)
    local state = get_list_state(player)
    if not state or not state.scroll or not state.scroll.valid then return end
    local scroll_position = state.scroll.scroll_position or nil
    for _, row in pairs(state.rows) do
        if row.flow.valid then row.flow.destroy() end
    end
    state.rows = {}
    populate_rows(player, state)
    update_list(player)
    if scroll_position then
        state.scroll.scroll_position = scroll_position
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
    frame.style.size = {950, 720}
    frame.style.padding = 2
    frame.auto_center = true

    local title_flow = frame.add{
        type = "flow",
        direction = "horizontal"
    }
    title_flow.style.vertical_align = "center"

    title_flow.add{
        type = "label",
        style = "frame_title",
        caption = "Profit And Loss",
        ignored_by_interaction = true
    }

    local filler = title_flow.add{
        type = "empty-widget"
    }
    filler.style.horizontally_stretchable = true
    filler.style.height = 24

    title_flow.add{
        type = "sprite-button",
        name = "otc_trading_close",
        sprite = "utility/close",
        style = "frame_action_button",
        tooltip = {"gui.close"},
    }

    local company_flow = frame.add {
        type = "flow",
        name = "otc_trading_company_flow",
        direction = "horizontal",
    }
    company_flow.style.vertical_align = "center"
    company_flow.style.horizontal_spacing = 4
    company_flow.style.left_margin = 2
    company_flow.style.bottom_margin = 4

    company_flow.add {
        type = "label",
        caption = "Company:",
        style = "caption_label",
    }

    local force_dropdown = company_flow.add {
        type = "drop-down",
        name = "otc_trading_force_dropdown",
        items = {},
    }

    local company_spacer = company_flow.add { type = "empty-widget" }
    company_spacer.style.horizontally_stretchable = true

    company_flow.add {
        type = "label",
        caption = "Balance:",
        style = "caption_label",
    }

    local balance_label = company_flow.add {
        type = "label",
        name = "otc_trading_balance",
        caption = "₾0",
    }

    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end
    player_data.trading_list_state = {
        force_dropdown = force_dropdown,
        balance_label = balance_label,
    }

    local panels = frame.add {
        type = "table",
        name = "otc_trading_panels",
        column_count = 3,
    }
    panels.style.horizontal_spacing = 4

    local surface_data = init_chart_surface()
    create_chart_panels(panels, player, surface_data)
    render_all_charts(player)

    local search_flow = frame.add {
        type = "flow",
        name = "otc_trading_search_flow",
        direction = "horizontal",
    }
    search_flow.style.vertical_align = "center"
    search_flow.style.horizontal_spacing = 2
    search_flow.style.left_margin = 6
    search_flow.style.bottom_margin = 4

    local search_field = search_flow.add {
        type = "textfield",
        name = "otc_trading_search",
    }
    search_field.style.width = 160
    local search_text = player_data.trading_search_text or ""
    if search_text ~= "" then search_field.text = search_text end

    search_flow.add {
        type = "sprite",
        sprite = "utility/search",
        ignored_by_interaction = true,
    }

    local scale_filler = search_flow.add { type = "empty-widget" }
    scale_filler.style.horizontally_stretchable = true

    local scale_button_1m = search_flow.add {
        type = "button",
        name = "otc_trading_scale_second",
        caption = "1m",
        style = "button",
        toggled = false,
    }
    local scale_button_10m = search_flow.add {
        type = "button",
        name = "otc_trading_scale_ten_second",
        caption = "10m",
        style = "button",
        toggled = false,
    }
    local scale_button_1h = search_flow.add {
        type = "button",
        name = "otc_trading_scale_ten_minute",
        caption = "1h",
        style = "button",
        toggled = false,
    }

    local selected_scale = get_selected_scale(player)
    local scale_buttons = {
        second = scale_button_1m,
        ten_second = scale_button_10m,
        ten_minute = scale_button_1h,
    }
    for key, btn in pairs(scale_buttons) do
        btn.toggled = (key == selected_scale)
    end
    player_data.trading_list_state.scale_buttons = scale_buttons

    local list_frame = frame.add {
        type = "frame",
        name = "otc_trading_list",
        direction = "vertical",
        style = "inside_deep_frame",
    }
    list_frame.style.horizontally_stretchable = true
    list_frame.style.vertically_stretchable = true
    list_frame.style.padding = 2
    list_frame.style.margin = { top = 6, right = 0, bottom = 6, left = 0 }

    build_list(player, frame)

    player.set_shortcut_toggled("otc-trading", true)
end

function M.refresh()
    for _, player in pairs(game.connected_players) do
        if player.gui.screen.otc_trading_frame then
            render_all_charts(player)
            update_list(player)
        end
    end
end

function M.handle_search(player, text)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end
    player_data.trading_search_text = text
    update_list(player)
end

function M.handle_force_change(player, force_name)
    set_selected_force(player, force_name)
    render_all_charts(player)
    rebuild_rows(player)
end

function M.handle_series_toggle(player, kind, item_name, state)
    local selection = get_chart_selection(player)
    if state then
        selection[kind][item_name] = true
    else
        selection[kind][item_name] = nil
    end
    render_all_charts(player)
    update_list(player)
end

local function update_scale_buttons(player, selected_scale)
    local state = get_list_state(player)
    if not state or not state.scale_buttons then return end
    for key, btn in pairs(state.scale_buttons) do
        if btn and btn.valid then
            btn.toggled = (key == selected_scale)
        end
    end
end

function M.handle_scale_button(player, scale_key)
    set_selected_scale(player, scale_key)
    update_scale_buttons(player, scale_key)
    switch_chart_scale(player, scale_key)
    update_list(player)
end

function M.handle_display_scale_changed(player)
    local frame = player.gui.screen.otc_trading_frame
    if not frame then return end

    local chart_state = get_chart_state(player)
    if not chart_state then return end

    local selected_scale = get_selected_scale(player)

    for _, scale in ipairs(SCALES) do
        local scale_state = chart_state[scale]
        if scale_state then
            for _, series_key in ipairs(CHART_KINDS) do
                local state = scale_state[series_key]
                if state then
                    state.camera_params = chart_render.get_camera_params(state.chunk, player.display_scale)
                    if scale == selected_scale then
                        local camera = chart_state.cameras and chart_state.cameras[series_key]
                        if camera and camera.valid then
                            camera.position = state.camera_params.position
                            camera.zoom = state.camera_params.zoom
                            camera.surface_index = state.surface.index
                        end
                    end
                end
            end
        end
    end
end

function M.close(player)
    local frame = player.gui.screen.otc_trading_frame
    if frame then
        local chart_state = get_chart_state(player)
        if chart_state then
            local surface_data = storage.chart_surface
            if surface_data then
                for _, scale in ipairs(SCALES) do
                    local scale_state = chart_state[scale]
                    if scale_state then
                        for _, state in pairs(scale_state) do
                            destroy_render_objects(state.line_ids)
                            if state.chunk then
                                chart_render.free_chunk(surface_data, state.chunk)
                            end
                        end
                    end
                end
            end
        end
        frame.destroy()
        player.set_shortcut_toggled("otc-trading", false)
    end
    local player_data = storage.players and storage.players[player.index]
    if player_data then player_data.trading_list_state = nil end
end

return M
