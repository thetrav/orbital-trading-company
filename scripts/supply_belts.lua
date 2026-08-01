local stock = require("scripts.stock")

local M = {}

M.SUPPLY_NAME = "otc-supply-belt"
M.INTAKE_NAME = "otc-intake-belt"

local function line_count(entity)
    return entity.get_max_transport_line_index()
end

function M.init()
    storage.supply_belts = storage.supply_belts or {}
    storage.intake_belts = storage.intake_belts or {}
end

function M.register_supply(entity, left_item, right_item)
    if not entity or not entity.valid then return end
    storage.supply_belts = storage.supply_belts or {}
    storage.supply_belts[entity.unit_number] = {
        entity = entity,
        left = left_item,
        right = right_item,
    }
end

function M.register_intake(entity)
    if not entity or not entity.valid then return end
    storage.intake_belts = storage.intake_belts or {}
    storage.intake_belts[entity.unit_number] = { entity = entity }
end

function M.process()
    for unit_number, data in pairs(storage.supply_belts or {}) do
        local entity = data.entity
        if not entity or not entity.valid then
            storage.supply_belts[unit_number] = nil
        else
            for index = 1, line_count(entity) do
                local item_name = (index % 2 == 1) and data.left or data.right
                local line = item_name and entity.get_transport_line(index)
                if line and line.can_insert_at_back() and stock.take(item_name, 1) > 0 then
                    line.insert_at_back({ name = item_name, count = 1 })
                end
            end
        end
    end

    for unit_number, data in pairs(storage.intake_belts or {}) do
        local entity = data.entity
        if not entity or not entity.valid then
            storage.intake_belts[unit_number] = nil
        else
            for index = 1, line_count(entity) do
                local line = entity.get_transport_line(index)
                if line then
                    for _, item in pairs(line.get_contents()) do
                        local removed = line.remove_item({ name = item.name, count = item.count })
                        if removed > 0 then
                            stock.add(item.name, removed)
                        end
                    end
                end
            end
        end
    end
end

return M
