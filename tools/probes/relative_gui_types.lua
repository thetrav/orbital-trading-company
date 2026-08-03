-- Which relative_gui_type does a logistic container's window use? The enum name
-- decides what an anchored frame attaches to, and guessing it fails silently.
local M = {}

function M.run()
    local names = {}
    for name in pairs(defines.relative_gui_type) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        if name:find("container") or name:find("chest") or name:find("logistic") then
            log("PROBE relative_gui_type: " .. name)
        end
    end
    log("PROBE total relative_gui_type entries: " .. #names)

    local positions = {}
    for name in pairs(defines.relative_gui_position) do positions[#positions + 1] = name end
    table.sort(positions)
    log("PROBE relative_gui_position: " .. table.concat(positions, ", "))
end

return M
