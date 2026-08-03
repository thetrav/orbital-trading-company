-- A fallback for `busted`, used by validate.sh when the real runner is not
-- installed. It implements just enough of busted's API for the specs in this
-- directory -- describe/it/before_each/after_each and the handful of assertions
-- they use -- so the suite still runs on a plain `lua`. Install busted and it
-- takes over again; nothing here is used when it is present.
--
--   lua test/minimal_runner.lua test/foo_spec.lua [test/bar_spec.lua ...]

package.path = "./?.lua;" .. package.path

local befores, afters = {}, {}
local passed, failed = 0, 0
local depth = 0
local failures = {}

local function indent() return string.rep("  ", depth) end

function describe(name, body)
    print(indent() .. name)
    depth = depth + 1
    local n_before, n_after = #befores, #afters
    body()
    for i = #befores, n_before + 1, -1 do befores[i] = nil end
    for i = #afters, n_after + 1, -1 do afters[i] = nil end
    depth = depth - 1
end

function before_each(fn) befores[#befores + 1] = fn end
function after_each(fn) afters[#afters + 1] = fn end

function it(name, body)
    for _, fn in ipairs(befores) do fn() end
    local ok, err = pcall(body)
    for _, fn in ipairs(afters) do pcall(fn) end
    if ok then
        passed = passed + 1
        print(indent() .. "PASS " .. name)
    else
        failed = failed + 1
        failures[#failures + 1] = name
        print(indent() .. "FAIL " .. name)
        print(indent() .. "     " .. tostring(err))
    end
end

local function fail(message, note)
    error(message .. (note and (" -- " .. tostring(note)) or ""), 3)
end

local function describe_value(value, seen)
    if type(value) ~= "table" then return tostring(value) end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local parts = {}
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key) .. "=" .. describe_value(value[key], seen)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function deep_equal(expected, actual)
    if expected == actual then return true end
    if type(expected) ~= "table" or type(actual) ~= "table" then return false end
    for key, value in pairs(expected) do
        if not deep_equal(value, actual[key]) then return false end
    end
    for key in pairs(actual) do
        if expected[key] == nil then return false end
    end
    return true
end

local assertions = {
    equals = function(expected, actual, note)
        if expected ~= actual then
            fail("expected " .. tostring(expected) .. ", got " .. tostring(actual), note)
        end
    end,
    same = function(expected, actual, note)
        if not deep_equal(expected, actual) then
            fail("expected " .. describe_value(expected) .. ", got " .. describe_value(actual), note)
        end
    end,
    is_true = function(value, note)
        if value ~= true then fail("expected true, got " .. tostring(value), note) end
    end,
    is_false = function(value, note)
        if value ~= false then fail("expected false, got " .. tostring(value), note) end
    end,
    is_nil = function(value, note)
        if value ~= nil then fail("expected nil, got " .. tostring(value), note) end
    end,
    is_truthy = function(value, note)
        if not value then fail("expected a truthy value, got " .. tostring(value), note) end
    end,
    is_falsy = function(value, note)
        if value then fail("expected a falsy value, got " .. tostring(value), note) end
    end,
    is_string = function(value, note)
        if type(value) ~= "string" then fail("expected a string, got " .. type(value), note) end
    end,
    is_number = function(value, note)
        if type(value) ~= "number" then fail("expected a number, got " .. type(value), note) end
    end,
    is_table = function(value, note)
        if type(value) ~= "table" then fail("expected a table, got " .. type(value), note) end
    end,
}
assertions.equal = assertions.equals
assertions.are = assertions
assertions.is_not = {
    equals = function(expected, actual, note)
        if expected == actual then fail("expected anything but " .. tostring(expected), note) end
    end,
    same = function(expected, actual, note)
        if deep_equal(expected, actual) then
            fail("expected anything but " .. describe_value(expected), note)
        end
    end,
    is_nil = function(value, note)
        if value == nil then fail("expected a value, got nil", note) end
    end,
}
assertions.is_not.equal = assertions.is_not.equals

_G.assert = setmetatable(assertions, {
    __call = function(_, value, note)
        if not value then fail("assertion failed", note) end
        return value
    end,
})

for index = 1, #arg do
    dofile(arg[index])
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
