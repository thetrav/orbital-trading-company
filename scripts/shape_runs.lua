local M = {}

--- Expand `{y, x1, x2}` horizontal runs into `{x, y}` tile positions.
function M.expand(runs)
    local tiles = {}
    for _, run in ipairs(runs) do
        local y, x1, x2 = run[1], run[2], run[3] or run[2]
        for x = x1, x2 do
            tiles[#tiles + 1] = { x, y }
        end
    end
    return tiles
end

--- Inverse of `expand`: pack `{x, y}` tile positions into sorted runs.
function M.compress(tiles)
    local rows = {}
    local ys = {}
    for _, t in ipairs(tiles) do
        local x, y = t[1], t[2]
        local row = rows[y]
        if not row then
            row = {}
            rows[y] = row
            ys[#ys + 1] = y
        end
        row[x] = true
    end
    table.sort(ys)

    local runs = {}
    for _, y in ipairs(ys) do
        local xs = {}
        for x in pairs(rows[y]) do xs[#xs + 1] = x end
        table.sort(xs)
        local i = 1
        while i <= #xs do
            local start = xs[i]
            local last = start
            while i < #xs and xs[i + 1] == last + 1 do
                i = i + 1
                last = xs[i]
            end
            runs[#runs + 1] = { y, start, last }
            i = i + 1
        end
    end
    return runs
end

return M
