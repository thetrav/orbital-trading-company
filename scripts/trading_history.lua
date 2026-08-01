local M = {}

local HISTORY_LENGTH = 60
local SCALE_10S_LENGTH = 60
local SCALE_10M_LENGTH = 6
local TOTAL_KEY = "__total__"

local SCALES = {
    second = { length = HISTORY_LENGTH, interval = 1, name = "1s / 1m" },
    five_second = { length = 2, interval = 5, name = "5s" },
    ten_second = { length = SCALE_10S_LENGTH, interval = 10, name = "10s / 10m" },
    ten_minute = { length = SCALE_10M_LENGTH, interval = 600, name = "10m / 1h" },
}

function M.init()
    storage.trading_history_head = storage.trading_history_head or 0
    storage.trading_chart = storage.trading_chart or {}
    storage.trading_scale_tensecond_head = storage.trading_scale_tensecond_head or 0
    storage.trading_scale_tenminute_head = storage.trading_scale_tenminute_head or 0
    storage.trading_scale_elapsed = storage.trading_scale_elapsed or {}
end

local function new_chart_slot()
    return {
        income = { [TOTAL_KEY] = 0 },
        expense = { [TOTAL_KEY] = 0 },
        profit = { [TOTAL_KEY] = 0 },
    }
end

local CHART_KIND_KEYS = { "income", "expense", "profit" }

local function ensure_series_in_all_slots(chart, name)
    for i = 1, chart.length do
        local slot = chart.data[i]
        for _, kind in ipairs(CHART_KIND_KEYS) do
            if slot[kind][name] == nil then
                slot[kind][name] = 0
            end
        end
    end
end

local function reset_chart_slot(old, sum)
    local slot = new_chart_slot()
    for _, kind in ipairs(CHART_KIND_KEYS) do
        local target = slot[kind]
        for name in pairs(sum[kind]) do
            target[name] = 0
        end
        if old then
            for name in pairs(old[kind]) do
                if target[name] == nil then
                    target[name] = 0
                end
            end
        end
    end
    return slot
end

local function new_chart(length)
    local chart = {
        data = {},
        head = 0,
        index = 1,
        length = length,
        sum = {
            income = {},
            expense = {},
            profit = {},
        },
    }
    for i = 1, length do
        chart.data[i] = new_chart_slot()
    end
    return chart
end

local function get_chart(force_name, scale_key)
    local scale = SCALES[scale_key]
    storage.trading_chart[scale_key] = storage.trading_chart[scale_key] or {}
    if not storage.trading_chart[scale_key][force_name] then
        storage.trading_chart[scale_key][force_name] = new_chart(scale.length)
    end
    return storage.trading_chart[scale_key][force_name]
end

local function add_series_value(slot_map, sum_map, name, value)
    if value == 0 then return end
    slot_map[name] = (slot_map[name] or 0) + value
    sum_map[name] = (sum_map[name] or 0) + value
end

local function add_chart_value(force_name, scale_key, item_name, income, expense)
    local chart = get_chart(force_name, scale_key)
    if chart.sum.income[item_name] == nil
        and chart.sum.expense[item_name] == nil
        and chart.sum.profit[item_name] == nil then
        ensure_series_in_all_slots(chart, item_name)
    end
    local slot = chart.data[chart.head + 1]
    local profit = income - expense
    add_series_value(slot.income, chart.sum.income, item_name, income)
    add_series_value(slot.expense, chart.sum.expense, item_name, expense)
    add_series_value(slot.profit, chart.sum.profit, item_name, profit)
    add_series_value(slot.income, chart.sum.income, TOTAL_KEY, income)
    add_series_value(slot.expense, chart.sum.expense, TOTAL_KEY, expense)
    add_series_value(slot.profit, chart.sum.profit, TOTAL_KEY, profit)
end

function M.record_buy(force_name, item_name, count, price_per_unit)
    for scale_key in pairs(SCALES) do
        add_chart_value(force_name, scale_key, item_name, 0, count * price_per_unit * 1.01)
    end
end

function M.record_sell(force_name, item_name, count, price_per_unit)
    for scale_key in pairs(SCALES) do
        add_chart_value(force_name, scale_key, item_name, count * price_per_unit * 0.99, 0)
    end
end

local function advance_scale(scale_key)
    local scale = SCALES[scale_key]
    local head_var = "trading_scale_" .. scale_key:gsub("_", "") .. "_head"
    if storage[head_var] == nil then
        storage[head_var] = 0
    end
    storage[head_var] = (storage[head_var] + 1) % scale.length
    local head_idx = storage[head_var] + 1

    for _, chart in pairs(storage.trading_chart[scale_key] or {}) do
        chart.head = storage[head_var]
        chart.index = head_idx % scale.length
        local old = chart.data[head_idx]
        if old then
            for kind, sum in pairs(chart.sum) do
                for name, value in pairs(old[kind]) do
                    if value ~= 0 then
                        local remaining = (sum[name] or 0) - value
                        if math.abs(remaining) < 0.5 then
                            sum[name] = nil
                        else
                            sum[name] = remaining
                        end
                    end
                end
            end
        end
        chart.data[head_idx] = reset_chart_slot(old, chart.sum)
    end
end

local function tick_scale(scale_key)
    local scale = SCALES[scale_key]
    storage.trading_scale_elapsed = storage.trading_scale_elapsed or {}
    local elapsed = (storage.trading_scale_elapsed[scale_key] or 0) + 1
    if elapsed >= scale.interval then
        elapsed = 0
        advance_scale(scale_key)
    end
    storage.trading_scale_elapsed[scale_key] = elapsed
end

function M.advance_second()
    storage.trading_history_head = (storage.trading_history_head + 1) % HISTORY_LENGTH
    local head_idx = storage.trading_history_head + 1

    for _, chart in pairs(storage.trading_chart.second or {}) do
        chart.head = storage.trading_history_head
        chart.index = head_idx % HISTORY_LENGTH
        local old = chart.data[head_idx]
        if old then
            for kind, sum in pairs(chart.sum) do
                for name, value in pairs(old[kind]) do
                    if value ~= 0 then
                        local remaining = (sum[name] or 0) - value
                        if math.abs(remaining) < 0.5 then
                            sum[name] = nil
                        else
                            sum[name] = remaining
                        end
                    end
                end
            end
        end
        chart.data[head_idx] = reset_chart_slot(old, chart.sum)
    end

    tick_scale("five_second")
    tick_scale("ten_second")
    tick_scale("ten_minute")
end

function M.get_chart_data(force_name, scale_key)
    scale_key = scale_key or "second"
    return get_chart(force_name, scale_key)
end

---Get the totals for the last fully-completed period of a scale (i.e. not the
---still-accumulating current period), for rate displays that shouldn't flicker
---with partial data.
---@param force_name string
---@param scale_key string
---@return table slot {income = {...}, expense = {...}, profit = {...}}
function M.get_previous_period(force_name, scale_key)
    local chart = get_chart(force_name, scale_key)
    local prev_idx = ((chart.head - 1) % chart.length) + 1
    return chart.data[prev_idx]
end

function M.get_all_forces()
    if not game then return {} end
    local forces = {}
    local seen = {}
    local function add(name)
        if not name or seen[name] then return end
        if not game.forces[name] then return end
        seen[name] = true
        forces[#forces + 1] = name
    end
    for force_name in pairs(storage.trading_chart.second or {}) do
        add(force_name)
    end
    for name in pairs(storage.companies or {}) do
        add(name)
    end
    table.sort(forces)
    return forces
end

function M.get_scales()
    return SCALES
end

return M