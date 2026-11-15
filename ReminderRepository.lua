local _, A = ...
local R, S = {}, A.Storage
A.Repository = R

local expiryDeadline

local function visible(reminder, owner)
    return reminder.scope == "account" or (owner ~= nil and reminder.ownerKey == owner)
end

local function changed(id, reset)
    if A.Engine then A.Engine.invalidate(id, reset) end
    if A.changed then A.changed() end
end

function R.readOnly()
    return S.locked
end

function R.list()
    local result = {}
    local owner = A.characterKey()
    for _, reminder in pairs(S.records) do
        if visible(reminder, owner) then result[#result + 1] = reminder end
    end
    table.sort(result, function(left, right) return tonumber(left.id) > tonumber(right.id) end)
    return result
end

function R.get(id)
    local reminder = S.records[id]
    if reminder and visible(reminder, A.characterKey()) then return reminder end
end

function R.settings()
    return S.settings
end

function R.setSetting(key, value)
    if S.locked then return nil, "ERROR_STORAGE" end
    if not S.validSetting(key, value) then return nil, "INVALID_REMINDER" end
    if S.settings[key] == value then return true end
    S.settings[key] = value
    if key == "notifications" and not value and A.Engine then A.Engine.clearDue() end
    changed()
    return true
end

function R.save(draft, id)
    if S.locked then return nil, "ERROR_STORAGE" end
    if type(draft) ~= "table" then return nil, "INVALID_REMINDER" end
    local old = id and R.get(id)
    if id and not old then return nil, "NOT_FOUND" end
    if old and old.deleteAfter then return nil, "UNDO_TO_EDIT" end
    local item = {}
    if old then
        for key, value in pairs(old) do item[key] = value end
    end
    item.title = draft.title
    item.note = draft.note == nil and "" or draft.note
    item.mapID = draft.mapID
    item.type = draft.type
    item.scope = draft.scope
    item.repeatMode = draft.repeatMode
    item.enabled = draft.enabled
    item.x, item.y, item.radiusNormalized, item.ownerKey = nil, nil, nil, nil
    if item.type == "point" then
        item.x, item.y, item.radiusNormalized = draft.x, draft.y, draft.radiusNormalized
    end
    local invalid = S.validate(item)
    if invalid then return nil, invalid end
    item.title = item.title:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if not A.Map.isZone(item.mapID) then
        if not old or old.mapID ~= item.mapID or old.type ~= item.type then return nil, "MAP_UNAVAILABLE" end
    end
    if item.type == "point" and not A.Map.isPointMap(item.mapID) and
        (not old or old.type ~= "point" or old.mapID ~= item.mapID or
        old.x ~= item.x or old.y ~= item.y or old.radiusNormalized ~= item.radiusNormalized) then
        return nil, "UNSUPPORTED_LOCATION"
    end
    if item.scope == "character" then
        item.ownerKey = A.characterKey()
        if not item.ownerKey then return nil, "ERROR_CHARACTER" end
    end
    if not id then
        if not A.mapID(S.database.nextId) then return nil, "ERROR_STORAGE" end
        id = tostring(S.database.nextId)
        S.database.nextId = S.database.nextId + 1
    end
    local reset = not old or item.type ~= old.type or item.mapID ~= old.mapID or
        item.x ~= old.x or item.y ~= old.y or item.radiusNormalized ~= old.radiusNormalized or
        item.scope ~= old.scope or item.enabled ~= old.enabled
    item.id = id
    item.createdAt = old and old.createdAt or A.now()
    item.updatedAt = A.now()
    item.status = old and old.status or "pending"
    if item.status == "completed" then item.enabled = false end
    if reset then
        if item.status ~= "completed" then item.status = "pending" end
    end
    item.lastTriggeredAt = old and old.lastTriggeredAt
    S.records[id] = item
    changed(id, reset)
    return item
end

local function writable(id)
    if S.locked then return nil, "ERROR_STORAGE" end
    local item = R.get(id)
    if not item then return nil, "NOT_FOUND" end
    return item
end

function R.setEnabled(id, enabled)
    local item, err = writable(id)
    if not item then return nil, err end
    if type(enabled) ~= "boolean" then return nil, "INVALID_REMINDER" end
    if item.deleteAfter then return nil, "UNDO_TO_EDIT" end
    if enabled == item.enabled and (not enabled or item.status ~= "completed") then return true end
    item.enabled = enabled
    item.updatedAt = A.now()
    if enabled or item.status ~= "completed" then item.status = "pending" end
    changed(id, true)
    return true
end

function R.expireCompleted()
    if S.locked then return end
    local now, owner = A.now(), A.characterKey()
    local nextDeadline, removed
    for id, item in pairs(S.records) do
        if item.deleteAfter and visible(item, owner) then
            if item.deleteAfter <= now then
                S.records[id] = nil
                if A.Engine then A.Engine.invalidate(id, true) end
                removed = true
            elseif not nextDeadline or item.deleteAfter < nextDeadline then
                nextDeadline = item.deleteAfter
            end
        end
    end
    if removed and A.changed then A.changed() end
    if not nextDeadline then
        expiryDeadline = nil
    elseif nextDeadline ~= expiryDeadline and C_Timer and type(C_Timer.After) == "function" then
        expiryDeadline = nextDeadline
        local scheduled = pcall(C_Timer.After, math.max(1, nextDeadline - now), function()
            if expiryDeadline ~= nextDeadline then return end
            expiryDeadline = nil
            R.expireCompleted()
        end)
        if not scheduled then expiryDeadline = nil end
    end
end

function R.complete(id)
    local item, err = writable(id)
    if not item then return nil, err end
    if item.status == "completed" then return true end
    local now = A.now()
    if item.repeatMode == "once" then
        item.deleteAfter = now + 60
        item.enabledBeforeCompletion = item.enabled
    end
    item.enabled, item.status = false, "completed"
    item.updatedAt = now
    changed(id, true)
    if item.deleteAfter then R.expireCompleted() end
    return true
end

function R.undoCompletion(id)
    local item, err = writable(id)
    if not item then return nil, err end
    local now = A.now()
    if not item.deleteAfter or item.deleteAfter <= now then
        R.expireCompleted()
        return nil, "NOT_FOUND"
    end
    item.enabled, item.status = item.enabledBeforeCompletion, "pending"
    item.deleteAfter, item.enabledBeforeCompletion = nil, nil
    item.updatedAt = now
    changed(id, true)
    return true
end

function R.delete(id)
    local item, err = writable(id)
    if not item then return nil, err end
    S.records[id] = nil
    changed(id, true)
    return true
end
