local M = {}

local function make_technology(name, spec)
    return {
        name = name,
        enabled = spec.enabled ~= false,
        researched = spec.researched or false,
        prerequisites = {},
        research_unit_count = spec.unit_count or 100,
        research_unit_energy = spec.unit_energy or 30,
        research_unit_ingredients = spec.ingredients or { { name = "automation-science-pack", amount = 1 } },
    }
end

-- Builds a minimal stand-in for the Factorio runtime globals that scripts/research.lua
-- reads. `specs` maps technology name -> { researched, enabled, prerequisites,
-- ingredients, unit_count, unit_energy }; prerequisites are wired up by name afterwards
-- so specs can reference each other in any order.
function M.setup(specs)
    local technologies = {}
    for name, spec in pairs(specs or {}) do
        technologies[name] = make_technology(name, spec)
    end
    for name, spec in pairs(specs or {}) do
        for _, prerequisite in ipairs(spec.prerequisites or {}) do
            technologies[name].prerequisites[prerequisite] = technologies[prerequisite]
        end
    end

    local nauvis_force = {
        name = "Nauvis",
        valid = true,
        technologies = technologies,
        current_research = nil,
        research_progress = 0,
        research_queue = {},
        recipes = {},
        add_research = function(self, tech_name)
            local tech = self.technologies[tech_name]
            if not tech or tech.researched then return false end
            self.current_research = tech
            return true
        end,
    }
    -- Factorio calls these with `:` syntax internally; scripts use force.add_research(x)
    -- so bind self explicitly.
    local raw_add = nauvis_force.add_research
    nauvis_force.add_research = function(tech_name) return raw_add(nauvis_force, tech_name) end

    _G.game = {
        forces = { Nauvis = nauvis_force },
        players = {},
        permissions = {
            groups = {},
            get_group = function(name) return _G.game.permissions.groups[name] end,
            create_group = function(name)
                local group = {
                    name = name,
                    disallowed = {},
                    set_allows_action = function(action, allow)
                        _G.game.permissions.groups[name].disallowed[action] = not allow
                    end,
                }
                _G.game.permissions.groups[name] = group
                return group
            end,
        },
    }
    _G.storage = {}
    _G.prototypes = { item = {}, technology = technologies }
    _G.defines = {
        input_action = { start_research = 1, cancel_research = 2, move_research = 3 },
    }

    return nauvis_force
end

function M.teardown()
    _G.game, _G.storage, _G.prototypes, _G.defines = nil, nil, nil, nil
end

return M
