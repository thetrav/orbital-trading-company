local M = {}

M.directions = {
    north = 0, northnortheast = 1, northeast = 2, eastnortheast = 3,
    east = 4, eastsoutheast = 5, southeast = 6, southsoutheast = 7,
    south = 8, southsouthwest = 9, southwest = 10, westsouthwest = 11,
    west = 12, westnorthwest = 13, northwest = 14, northnorthwest = 15,
}

--- Just `defines`, for specs that only need direction constants.
function M.setup_defines()
    _G.defines = _G.defines or {}
    _G.defines.direction = M.directions
    return _G.defines
end

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
        direction = M.directions,
    }

    return nauvis_force
end

-- A stand-in for LuaGuiElement, enough of one for a GUI module to build its
-- window and be driven through it: children are reachable by name, `children`
-- hands back a copy so destroying while iterating is safe, and anything the
-- real API lets you assign (style fields, state, text) is just a field here.
local element_methods = {}
local element_mt = {
    __index = function(self, key)
        local fields = rawget(self, "_fields")
        if fields[key] ~= nil then return fields[key] end
        if key == "children" then
            local copy = {}
            for index, child in ipairs(rawget(self, "_children")) do copy[index] = child end
            return copy
        end
        local named = rawget(self, "_by_name")[key]
        if named then return named end
        return element_methods[key]
    end,
    __newindex = function(self, key, value)
        rawget(self, "_fields")[key] = value
    end,
}

local function new_element(spec, parent)
    local element = setmetatable({
        _fields = { valid = true, style = {}, tabs = {} },
        _children = {},
        _by_name = {},
        _parent = parent,
    }, element_mt)
    for key, value in pairs(spec or {}) do
        rawget(element, "_fields")[key] = value
    end
    -- `style` names a prototype on the way in but reads back as a style object,
    -- so the string must not survive as the field.
    local fields = rawget(element, "_fields")
    if type(fields.style) == "string" then
        fields.style_name = fields.style
        fields.style = {}
    end
    return element
end

function element_methods.add(self, spec)
    local child = new_element(spec, self)
    local children = rawget(self, "_children")
    children[#children + 1] = child
    if spec.name then rawget(self, "_by_name")[spec.name] = child end
    return child
end

function element_methods.destroy(self)
    local parent = rawget(self, "_parent")
    if parent then
        local children = rawget(parent, "_children")
        for index, child in ipairs(children) do
            if child == self then
                table.remove(children, index)
                break
            end
        end
        local name = rawget(self, "_fields").name
        if name then rawget(parent, "_by_name")[name] = nil end
    end
    rawget(self, "_fields").valid = false
end

function element_methods.add_tab(self, tab, content)
    local tabs = rawget(self, "_fields").tabs
    tabs[#tabs + 1] = { tab = tab, content = content }
end

--- Factorio calls element methods with `:`; GUI code uses `element.add{...}`,
--- so bind self on the way out.
element_mt.__index = (function(inner)
    return function(self, key)
        local method = element_methods[key]
        if method then
            return function(...) return method(self, ...) end
        end
        return inner(self, key)
    end
end)(element_mt.__index)

function M.gui_root()
    return new_element({ name = "screen" }, nil)
end

function M.teardown()
    _G.game, _G.storage, _G.prototypes, _G.defines = nil, nil, nil, nil
end

return M
