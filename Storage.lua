local _, A = ...
local Storage = {}
A.Storage = Storage

local defaults = {
    notifications = true,
    sound = true,
    developerMode = false,
    cooldownSeconds = 300,
}

local function validUTF8(text, limit)
    if type(text) ~= "string" or #text > limit then return false end
    local index = 1
    while index <= #text do
        local byte = text:byte(index)
        if byte < 128 then
            if (byte < 32 and byte ~= 9 and byte ~= 10 and byte ~= 13) or byte == 127 then return false end
            index = index + 1
        else
            local length
            if byte >= 194 and byte <= 223 then length = 2
            elseif byte >= 224 and byte <= 239 then length = 3
            elseif byte >= 240 and byte <= 244 then length = 4
            else return false end
            local second = text:byte(index + 1)
            if not second or second < 128 or second > 191 or
                (byte == 224 and second < 160) or (byte == 237 and second > 159) or
                (byte == 240 and second < 144) or (byte == 244 and second > 143) then return false end
            for offset = 2, length - 1 do
                local continuation = text:byte(index + offset)
                if not continuation or continuation < 128 or continuation > 191 then return false end
            end
            index = index + length
        end
    end
    return true
end

function Storage.validate(item)
    if type(item) ~= "table" then return "INVALID_REMINDER" end
    if not validUTF8(item.title, 120) or not validUTF8(item.note, 1000) then return "INVALID_TEXT" end
    if not item.title:find("%S") then return "TITLE_REQUIRED" end
    if not A.mapID(item.mapID) then return "MAP_UNAVAILABLE" end
    if (item.type ~= "zone" and item.type ~= "point") or
        (item.scope ~= "account" and item.scope ~= "character") or
        (item.repeatMode ~= "once" and item.repeatMode ~= "recurring") or
        type(item.enabled) ~= "boolean" then return "INVALID_REMINDER" end
    if item.type == "point" and (not A.Map.coordinates(item.x, item.y) or
        not A.finite(item.radiusNormalized) or item.radiusNormalized <= 0 or
        item.radiusNormalized > 0.1) then return "INVALID_COORDINATES" end
end

local function validTime(value)
    return value == nil or (A.finite(value) and value >= 0)
end

local function validRecord(id, reminder)
    return not Storage.validate(reminder) and type(id) == "string" and A.mapID(tonumber(id)) and
        tostring(tonumber(id)) == id and reminder.id == id and
        (reminder.scope == "account" or (type(reminder.ownerKey) == "string" and reminder.ownerKey ~= "")) and
        (reminder.status == "pending" or reminder.status == "completed" or reminder.status == "snoozed") and
        (reminder.status ~= "snoozed" or reminder.snoozedUntil ~= nil) and
        validTime(reminder.createdAt) and validTime(reminder.updatedAt) and
        validTime(reminder.lastTriggeredAt) and validTime(reminder.snoozedUntil) and
        (reminder.deleteAfter == nil or (validTime(reminder.deleteAfter) and reminder.deleteAfter > 0 and
            reminder.status == "completed" and reminder.repeatMode == "once" and not reminder.enabled and
            type(reminder.enabledBeforeCompletion) == "boolean"))
end

function Storage.validSetting(key, value)
    if key == "cooldownSeconds" then
        return A.finite(value) and value >= 300 and value <= 86400 and value % 1 == 0
    end
    return type(defaults[key]) == "boolean" and type(value) == "boolean"
end

function Storage.init()
    local source = MapMemoDB
    if source == nil then source = {schemaVersion = 1, reminders = {}, settings = {}, nextId = 1} end
    local recognized = type(source) == "table" and type(source.reminders) == "table"
    local supported = recognized and
        (source.schemaVersion == 1 or source.schemaVersion == 0 or source.schemaVersion == nil)
    Storage.locked = not supported
    Storage.issue = Storage.locked and "ERROR_STORAGE" or nil
    Storage.settings = {}
    Storage.records = {}
    Storage.database = nil
    local sourceSettings = recognized and source.settings
    for key, default in pairs(defaults) do
        local value
        if type(sourceSettings) == "table" then value = sourceSettings[key] end
        if Storage.validSetting(key, value) then
            Storage.settings[key] = value
        else
            Storage.settings[key] = default
        end
    end
    if not recognized then return end
    if not supported then
        for id, reminder in pairs(source.reminders) do
            if validRecord(id, reminder) then Storage.records[id] = reminder end
        end
        return
    end
    Storage.database = source
    if type(source.quarantine) ~= "table" then
        if source.quarantine ~= nil then
            source.quarantine = {previousQuarantine = source.quarantine}
            Storage.issue = "ERROR_STORAGE_RECOVERED"
        else
            source.quarantine = {}
        end
    end
    local function isolate(key, value)
        local slot = key
        while source.quarantine[slot] ~= nil do slot = tostring(slot) .. ":recovered" end
        source.quarantine[slot] = value
        Storage.issue = "ERROR_STORAGE_RECOVERED"
    end
    local highest = 0
    for id, reminder in pairs(source.reminders) do
        if A.mapID(tonumber(id)) then highest = math.max(highest, tonumber(id)) end
        if (source.schemaVersion == nil or source.schemaVersion == 0) and type(reminder) == "table" then
            if reminder.status == nil then reminder.status = "pending" end
            if reminder.note == nil then reminder.note = "" end
        end
        if validRecord(id, reminder) then
            if reminder.status == "snoozed" then reminder.status = "pending" end
            reminder.snoozedUntil = nil
            Storage.records[id] = reminder
        else
            isolate(id, reminder)
        end
    end
    if sourceSettings ~= nil and type(sourceSettings) ~= "table" then isolate("settings", sourceSettings) end
    if type(sourceSettings) == "table" then
        for key, value in pairs(sourceSettings) do
            if defaults[key] ~= nil and not Storage.validSetting(key, value) then
                isolate("settings." .. key, value)
            elseif defaults[key] == nil then
                Storage.settings[key] = value
            end
        end
    end
    for id in pairs(source.quarantine) do
        if A.mapID(tonumber(id)) then highest = math.max(highest, tonumber(id)) end
    end
    local nextId = A.mapID(source.nextId) and source.nextId or 1
    source.nextId = math.max(nextId, highest + 1)
    source.schemaVersion = 1
    source.settings = Storage.settings
    source.reminders = Storage.records
    MapMemoDB = source
end
