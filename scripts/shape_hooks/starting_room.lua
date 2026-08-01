local platform_gates = require("scripts.platform_gates")

local M = {}

--- The 10x10 room every player starts in: airlocks and the company monitor.
function M.run(ctx)
    local surface = ctx.surface

    platform_gates.init_gates_for_surface(surface)
    platform_gates.place_gate_controls(surface, ctx.force_name)

    local monitor_entry = (ctx.roles.company_monitor or {})[1]
    if not monitor_entry then return end

    local monitor = surface.create_entity {
        name = monitor_entry.def.name,
        position = monitor_entry.def.position,
        force = "player",
        icon = { type = "space-location", name = "nauvis" },
    }
    if not monitor then return end
    monitor.minable = false
    monitor.destructible = false
    local behavior = monitor.get_or_create_control_behavior()
    behavior.set_message(-1, { text = "Company Management" })
    monitor_entry.entity = monitor
end

return M
