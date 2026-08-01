-- Minimal line-chart renderer for the trading GUI, replacing the factorio-charts dependency.
-- Only implements what trading_gui.lua actually needs: a hidden render surface with
-- reusable chunks, camera framing that accounts for player.display_scale, and a
-- time-series line graph draw.
local M = {}

local TILE_SIZE = 32
local VIEWPORT_WIDTH = 300
local VIEWPORT_HEIGHT = 233
local TILES_WIDTH = math.ceil(VIEWPORT_WIDTH / TILE_SIZE) + 2
local TILES_HEIGHT = math.ceil(VIEWPORT_HEIGHT / TILE_SIZE) + 2
local CHUNK_SPACING = math.max(TILES_WIDTH, TILES_HEIGHT, 32)

local SERIES_COLORS = {
    { r = 1.0, g = 1.0, b = 0.0 }, -- Yellow
    { r = 0.0, g = 1.0, b = 1.0 }, -- Cyan
    { r = 1.0, g = 1.0, b = 1.0 }, -- White
    { r = 1.0, g = 0.0, b = 0.0 }, -- Red
    { r = 0.0, g = 1.0, b = 0.0 }, -- Green
    { r = 1.0, g = 0.5, b = 0.0 }, -- Orange
    { r = 1.0, g = 0.0, b = 1.0 }, -- Magenta
    { r = 0.5, g = 0.5, b = 1.0 }, -- Light blue
    { r = 1.0, g = 0.5, b = 0.5 }, -- Light red
    { r = 0.5, g = 1.0, b = 0.5 }, -- Light green
    { r = 1.0, g = 1.0, b = 0.5 }, -- Light yellow
    { r = 1.0, g = 0.5, b = 1.0 }, -- Pink
}

local GRID_COLOR = { r = 0.3, g = 0.3, b = 0.3, a = 0.4 }
local LABEL_COLOR = { r = 0.8, g = 0.8, b = 0.8 }

function M.get_series_colors()
    return SERIES_COLORS
end

---Create (or fetch) the hidden surface used to render charts
---@param name string Unique surface name
---@return table surface_data {surface, chunk_freelist, next_chunk_x, next_chunk_y}
function M.create_surface(name)
    local surface = game.get_surface(name)
    if not surface then
        surface = game.create_surface(name, { width = 1, height = 1 })
    end
    surface.daytime = 0.5
    surface.freeze_daytime = true
    for _, force in pairs(game.forces) do
        force.set_surface_hidden(surface, true)
    end

    return {
        surface = surface,
        chunk_freelist = {},
        next_chunk_x = 0,
        next_chunk_y = 0,
    }
end

---Allocate a fixed-size (VIEWPORT_WIDTH x VIEWPORT_HEIGHT) chunk for a chart
---@param surface_data table The surface data from create_surface
---@return table chunk {coord, light_ids}
function M.allocate_chunk(surface_data)
    local chunk_coord
    local freelist = surface_data.chunk_freelist
    local length = #freelist
    if length > 0 then
        chunk_coord = freelist[length]
        freelist[length] = nil
    else
        chunk_coord = {
            x = surface_data.next_chunk_x * CHUNK_SPACING,
            y = surface_data.next_chunk_y * CHUNK_SPACING,
        }
        if surface_data.next_chunk_x == 0 then
            surface_data.next_chunk_x = surface_data.next_chunk_y + 1
            surface_data.next_chunk_y = 0
        else
            surface_data.next_chunk_x = surface_data.next_chunk_x - 1
            surface_data.next_chunk_y = surface_data.next_chunk_y + 1
        end

        local tiles = {}
        local i = 1
        for x = chunk_coord.x, chunk_coord.x + TILES_WIDTH - 1 do
            for y = chunk_coord.y, chunk_coord.y + TILES_HEIGHT - 1 do
                tiles[i] = { name = "lab-dark-1", position = { x = x, y = y } }
                i = i + 1
            end
        end
        surface_data.surface.set_tiles(tiles)
    end

    local light_ids = {}
    local light_spacing_x = TILES_WIDTH / 3
    local light_spacing_y = TILES_HEIGHT / 3
    for lx = 0, 2 do
        for ly = 0, 2 do
            light_ids[#light_ids + 1] = rendering.draw_light {
                sprite = "utility/light_medium",
                scale = 50,
                intensity = 10,
                minimum_darkness = 0,
                target = { chunk_coord.x + light_spacing_x * (lx + 0.5), chunk_coord.y + light_spacing_y * (ly + 0.5) },
                surface = surface_data.surface,
            }
        end
    end

    return { coord = chunk_coord, light_ids = light_ids }
end

---Free a chunk back to the pool
---@param surface_data table The surface data from create_surface
---@param chunk table The chunk to free
function M.free_chunk(surface_data, chunk)
    if chunk.light_ids then
        for _, light_id in ipairs(chunk.light_ids) do
            if light_id.valid then
                light_id.destroy()
            end
        end
    end
    table.insert(surface_data.chunk_freelist, chunk.coord)
end

---Compute camera position/zoom to frame a chunk, accounting for the player's display scale.
---This mod always shows a chunk's chart at exactly VIEWPORT_WIDTH x VIEWPORT_HEIGHT, so the
---widget is always the same size as the viewport and zoom reduces to display_scale directly:
---the GUI widget's on-screen pixel size scales with display_scale, but camera zoom is a raw
---framebuffer value that doesn't, so display_scale IS the zoom needed to keep them in sync.
---@param chunk table The chunk from allocate_chunk()
---@param display_scale number The viewing player's LuaPlayer.display_scale
---@return table camera_params {position, zoom}
function M.get_camera_params(chunk, display_scale)
    return {
        position = {
            x = chunk.coord.x + (VIEWPORT_WIDTH / TILE_SIZE) / 2,
            y = chunk.coord.y + (VIEWPORT_HEIGHT / TILE_SIZE) / 2,
        },
        zoom = display_scale,
    }
end

---Render a time-series line graph onto a chunk
---@param surface LuaSurface The rendering surface
---@param chunk table The chunk with coord from allocate_chunk()
---@param options table
---  - data: table[] Ring buffer of {[series_name]: value}
---  - index: number Current position in the ring buffer
---  - length: number Buffer capacity
---  - counts: table {[series_name]: sample_count}
---  - sum: table {[series_name]: total}
---  - selected_series: table? {[name]: bool} Filter (nil/empty = show all)
---  - label_format: function(value) -> string Y-axis label formatter
---  - ttl: number? Time to live in ticks (default 360)
---@return LuaRenderObject[]? line_ids
function M.line_graph(surface, chunk, options)
    if not chunk or not chunk.coord then return nil end

    local data = options.data
    local index = options.index
    local length = options.length
    local counts = options.counts
    local sum = options.sum
    local label_format = options.label_format
    local selected_series = options.selected_series
    local ttl = options.ttl or 360

    -- Collect and sort ALL series by sum first (for consistent color assignment)
    local all_series = {}
    local all_count = 0
    for name in pairs(counts) do
        all_count = all_count + 1
        all_series[all_count] = { name = name, sum = sum[name] or 0 }
    end

    if all_count == 0 then return nil end

    table.sort(all_series, function(a, b)
        if a.sum ~= b.sum then
            return a.sum > b.sum
        end
        return a.name < b.name
    end)

    local color_indices = {}
    for i, entry in ipairs(all_series) do
        color_indices[entry.name] = ((i - 1) % #SERIES_COLORS) + 1
    end

    -- Filter to selected series only, preserving sort order
    local show_all = not selected_series or not next(selected_series)
    local ordered = {}
    local datasets = 0
    for _, entry in ipairs(all_series) do
        if show_all or selected_series[entry.name] ~= false then
            datasets = datasets + 1
            ordered[datasets] = { name = entry.name, color_index = color_indices[entry.name] }
        end
    end

    if datasets == 0 then return nil end

    local to_draw = math.min(datasets, #SERIES_COLORS)

    -- Compute Y-axis range from actual data
    local min_y = math.huge
    local max_y = -math.huge
    local has_data = false
    for i = 1, length do
        local datum = data[i]
        if datum then
            for j = 1, to_draw do
                local val = datum[ordered[j].name]
                if val then
                    has_data = true
                    if val < min_y then min_y = val end
                    if val > max_y then max_y = val end
                end
            end
        end
    end

    if not has_data then return nil end

    if min_y == max_y then
        min_y = min_y - 1
        max_y = max_y + 1
    end

    -- graph_left leaves room for y-axis labels
    local graph_left = 2.0
    local graph_right = VIEWPORT_WIDTH / TILE_SIZE - 0.5
    local graph_top = 1
    local graph_bottom = VIEWPORT_HEIGHT / TILE_SIZE - 0.5

    local graph_width = graph_right - graph_left
    local graph_height = graph_bottom - graph_top

    local y_range = max_y - min_y
    if y_range == 0 then y_range = 1 end

    local dx = graph_width / (length - 1)
    local dy = graph_height / y_range

    local entity_pos = chunk.coord
    local line_ids = {}

    -- Horizontal grid lines with Y-axis labels
    local num_grid_lines = 5
    for i = 0, num_grid_lines - 1 do
        local grid_value = min_y + (y_range * i / (num_grid_lines - 1))
        local grid_y = graph_bottom - ((grid_value - min_y) * dy)

        line_ids[#line_ids + 1] = rendering.draw_line {
            surface = surface,
            color = GRID_COLOR,
            width = 1,
            from = { entity_pos.x + graph_left, entity_pos.y + grid_y },
            to = { entity_pos.x + graph_right, entity_pos.y + grid_y },
            time_to_live = ttl,
        }

        line_ids[#line_ids + 1] = rendering.draw_text {
            text = label_format(grid_value),
            surface = surface,
            target = { entity_pos.x + graph_left - 0.2, entity_pos.y + grid_y },
            color = LABEL_COLOR,
            scale = 1.0,
            alignment = "right",
            vertical_alignment = "middle",
            time_to_live = ttl,
        }
    end

    -- Draw lines for each series, iterating the ring buffer in chronological order
    local prev = {}
    local x = graph_left

    local first = data[index + 1]
    if first then
        for j = 1, to_draw do
            local name = ordered[j].name
            local n = first[name]
            if n then
                prev[name] = { x, graph_bottom - ((n - min_y) * dy) }
            end
        end
    end

    local ranges = {
        { start = index + 2, stop = length },
        { start = 1, stop = index },
    }

    for _, range in ipairs(ranges) do
        for i = range.start, range.stop do
            x = x + dx
            local datum = data[i]
            local next_points = {}

            for j = to_draw, 1, -1 do
                local entry = ordered[j]
                local name = entry.name
                local point = prev[name]
                local n = datum and datum[name]

                if n then
                    local y = graph_bottom - ((n - min_y) * dy)
                    next_points[name] = { x, y }

                    if point then
                        line_ids[#line_ids + 1] = rendering.draw_line {
                            surface = surface,
                            color = SERIES_COLORS[entry.color_index],
                            width = 1,
                            from = { entity_pos.x + point[1], entity_pos.y + point[2] },
                            to = { entity_pos.x + x, entity_pos.y + y },
                            time_to_live = ttl,
                        }
                    end
                end
            end
            prev = next_points
        end
    end

    return line_ids
end

return M
