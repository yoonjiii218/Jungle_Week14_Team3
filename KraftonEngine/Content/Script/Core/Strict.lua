-- Core/Strict.lua
-- Public boundary runtime checks for Lua gameplay modules.
-- Keep this small: it is not a full type system.

local Strict = {}

Strict.None = { __strict_none = true }

local function Fail(caller, message)
    error("[Strict] " .. tostring(caller or "unknown") .. ": " .. message, 3)
end

---@param value any
---@param name string
---@param caller string
---@return table
function Strict.AssertTable(value, name, caller)
    if type(value) ~= "table" then
        Fail(caller, tostring(name or "value") .. " must be table, got " .. type(value))
    end
    return value
end

---@param value any
---@param name string
---@param caller string
---@return number
function Strict.AssertNumber(value, name, caller)
    if type(value) ~= "number" then
        Fail(caller, tostring(name or "value") .. " must be number, got " .. type(value))
    end
    return value
end

---@param value any
---@param name string
---@param caller string
---@return string
function Strict.AssertString(value, name, caller)
    if type(value) ~= "string" then
        Fail(caller, tostring(name or "value") .. " must be string, got " .. type(value))
    end
    return value
end

---@param value any
---@param name string
---@param caller string
---@return boolean
function Strict.AssertBoolean(value, name, caller)
    if type(value) ~= "boolean" then
        Fail(caller, tostring(name or "value") .. " must be boolean, got " .. type(value))
    end
    return value
end

---@param value any
---@param name string
---@param caller string
---@return any
function Strict.AssertNotNil(value, name, caller)
    if value == nil then
        Fail(caller, tostring(name or "value") .. " must not be nil")
    end
    return value
end

---@param value any
---@param expectedKind string
---@param name string
---@param caller string
---@return table
function Strict.AssertKind(value, expectedKind, name, caller)
    Strict.AssertTable(value, name, caller)
    if value.Kind ~= expectedKind then
        Fail(caller, tostring(name or "value") .. ".Kind must be " .. expectedKind .. ", got " .. tostring(value.Kind))
    end
    return value
end

return Strict
