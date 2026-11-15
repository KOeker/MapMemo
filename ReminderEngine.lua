local _, A = ...
local E, R, M = {}, A.Repository, A.Map
A.Engine = E

local states, zones, points
local indexed, indexedOwner, previousZone, previousPointMap
local ticker
local lastMap, lastX, lastY

local function cancel(timer)
    if timer then A.safe(function() timer:Cancel() end) end
end

function E.reset()
    cancel(ticker)
    ticker = nil
    states, zones, points = {}, {}, {}
    indexed, indexedOwner, previousZone, previousPointMap = false, nil, nil, nil
    lastMap, lastX, lastY = nil, nil, nil
end

E.reset()

function E.invalidate(id, reset)
    indexed, lastMap = false, nil
    if not id or not reset then return end
    states[id] = nil
    local item = R.get(id)
    if not item or not item.enabled or not previousZone then return end
    local inside
    if item.type == "zone" then
        inside = M.playerZone() == item.mapID
    else
        local x, y = M.position(item.mapID)
        if x then
            local dx, dy = x - item.x, y - item.y
            inside = dx * dx + dy * dy <= item.radiusNormalized * item.radiusNormalized
        end
    end
    if inside then states[id] = {inside = true} end
end

local function active(item)
    return item and item.enabled and item.status ~= "completed"
end

local function index()
    local owner = A.characterKey()
    if indexed and indexedOwner == owner then return end
    zones, points = {}, {}
    if not R.readOnly() and R.settings().notifications then
        for _, item in ipairs(R.list()) do
            if active(item) then
                local destination = item.type == "point" and points or zones
                local bucket = destination[item.mapID] or {}
                bucket[#bucket + 1] = item
                destination[item.mapID] = bucket
            end
        end
    end
    indexed, indexedOwner = true, owner
end

local function state(id)
    if not states[id] then states[id] = {} end
    return states[id]
end

function E.isDue(id)
    return not R.readOnly() and R.settings().notifications and active(R.get(id)) and
        states[id] ~= nil and states[id].due ~= nil
end

function E.delivered(id)
    if not E.isDue(id) then return false end
    local item = R.get(id)
    local runtime = state(id)
    local leaving = runtime.due == "leave"
    runtime.due = nil
    if not leaving then
        item.lastTriggeredAt = A.now()
    end
    item.status = "pending"
    return true, leaving
end

function E.clearDue()
    for _, runtime in pairs(states) do
        runtime.due, runtime.inside = nil, nil
    end
end

function E.dismiss(id)
    if states[id] then states[id].due = nil end
end

local function observe(item, distanceSquared, now, due)
    local runtime = state(item.id)
    if item.type == "point" then
        local radius = item.radiusNormalized
        local exitRadius = radius * 1.3
        if distanceSquared >= exitRadius * exitRadius then
            runtime.inside = false
            return
        end
        if distanceSquared > radius * radius then return end
    end
    local entered = not runtime.inside
    local returning = runtime.inside == false and item.type == "zone" and item.repeatMode == "once"
    runtime.inside = true
    if runtime.due or not entered then return end
    if not returning and item.lastTriggeredAt and now - item.lastTriggeredAt < R.settings().cooldownSeconds then return end
    runtime.due = "arrival"
    due[#due + 1] = item.id
end

local function leave(bucket)
    for _, item in ipairs(bucket or {}) do state(item.id).inside = false end
end

local function leaveZone(bucket, due)
    for _, item in ipairs(bucket or {}) do
        local runtime = state(item.id)
        if runtime.inside then
            if item.repeatMode == "once" then
                if not runtime.due then due[#due + 1] = item.id end
                runtime.due = "leave"
            end
            runtime.inside = false
        end
    end
end

local function updateTicker(needed)
    if needed and not ticker and C_Timer then
        ticker = A.safe(C_Timer.NewTicker, 1.5, function() E.evaluate() end)
    elseif not needed and ticker then
        cancel(ticker)
        ticker = nil
    end
end

function E.evaluate()
    if not R.settings() then return end
    index()
    local current = M.currentMap()
    local zone = current and M.playerZone(current)
    local now = A.now()
    local due = {}
    if zone then
        if previousZone ~= zone then leaveZone(zones[previousZone], due) end
        previousZone = zone
        for _, item in ipairs(zones[zone] or {}) do observe(item, nil, now, due) end
    end
    local outdoors = A.safe(IsInInstance) == false
    if current and zone == current and outdoors and current ~= previousPointMap then
        leave(points[previousPointMap])
        previousPointMap, lastMap = current, nil
    end
    local pointBucket = points[current]
    if pointBucket then
        local x, y = M.position(current, current)
        if x and (lastMap ~= current or lastX ~= x or lastY ~= y) then
            lastMap, lastX, lastY = current, x, y
            for _, item in ipairs(pointBucket) do
                local dx, dy = x - item.x, y - item.y
                observe(item, dx * dx + dy * dy, now, due)
            end
        elseif not x then
            lastMap = nil
        end
    end
    updateTicker(outdoors and (pointBucket ~= nil or (not current and points[previousPointMap] ~= nil))
        and not M.displayed())
    if A.Notifications then
        for _, id in ipairs(due) do A.Notifications.enqueue(id) end
    end
end
