local _, A = ...
local Map = {}
A.Map = Map

local function mapType(name)
    return Enum and Enum.UIMapType and Enum.UIMapType[name]
end

function Map.coordinates(x, y)
    return A.finite(x) and A.finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

function Map.info(id)
    if not A.mapID(id) or not C_Map then return end
    local info = A.safe(C_Map.GetMapInfo, id)
    if type(info) ~= "table" then return end
    local kind, parent, name = info.mapType, info.parentMapID, info.name
    if not A.finite(kind) then return end
    return {
        mapID = id,
        mapType = kind,
        parentMapID = A.mapID(parent) and parent or nil,
        name = A.usable(name) and type(name) == "string" and name ~= "" and name or nil,
    }
end

function Map.name(id)
    local info = Map.info(id)
    return info and info.name or (A.mapID(id) and A.L.UNKNOWN_MAP:format(id) or A.L.MAP_UNAVAILABLE)
end

function Map.isZone(id)
    local info = Map.info(id)
    return info ~= nil and info.mapType == mapType("Zone")
end

function Map.isPointMap(id)
    return C_Map ~= nil and type(C_Map.GetPlayerMapPosition) == "function" and
        type(IsInInstance) == "function" and Map.isZone(id)
end

function Map.displayed()
    local map = WorldMapFrame
    if not map or A.safe(map.IsShown, map) ~= true then return end
    local id = A.safe(map.GetMapID, map)
    if A.mapID(id) then return id end
end

function Map.currentMap()
    local id = C_Map and A.safe(C_Map.GetBestMapForUnit, "player")
    if A.mapID(id) then return id end
end

function Map.playerZone(current)
    local id = current or Map.currentMap()
    local seen = {}
    while id and not seen[id] do
        seen[id] = true
        local info = Map.info(id)
        if not info then return end
        if info.mapType == mapType("Zone") then return id end
        if info.mapType ~= mapType("Micro") then return false end
        id = info.parentMapID
    end
end

function Map.position(id, current)
    if not Map.isPointMap(id) or (current or Map.currentMap()) ~= id or
        A.safe(IsInInstance) ~= false then return end
    local position = A.safe(C_Map.GetPlayerMapPosition, id, "player")
    if type(position) ~= "table" and type(position) ~= "userdata" then return end
    local x, y = A.safe(function()
        if A.usable(position.GetXY) and type(position.GetXY) == "function" then return position:GetXY() end
        return position.x, position.y
    end)
    if Map.coordinates(x, y) and (x ~= 0 or y ~= 0) then return x, y end
end

function Map.choices()
    local result, checked, roots = {}, {}, {}
    local zoneType = mapType("Zone")
    if zoneType == nil then return result end
    local function add(id)
        if not A.mapID(id) or checked[id] then return end
        checked[id] = true
        local info = Map.info(id)
        if info and info.mapType == zoneType and info.name then
            result[#result + 1] = {mapID = id, name = info.name}
        end
    end
    local function seed(id)
        add(id)
        while id and not roots[id] do
            roots[id] = true
            local info = Map.info(id)
            id = info and info.parentMapID
        end
    end
    seed(Map.displayed())
    seed(Map.currentMap())
    if C_Map then
        seed(A.safe(C_Map.GetFallbackWorldMapID))
        for root in pairs(roots) do
            local children = A.safe(C_Map.GetMapChildrenInfo, root, zoneType, true)
            if type(children) == "table" then
                for _, entry in ipairs(children) do
                    if A.usable(entry) and type(entry) == "table" then add(entry.mapID) end
                end
            end
        end
    end
    table.sort(result, function(left, right)
        if left.name == right.name then return left.mapID < right.mapID end
        return left.name < right.name
    end)
    return result
end
