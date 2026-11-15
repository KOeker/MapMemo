local _, A = ...
local unpack = unpack or table.unpack
local L = A.L
local ownerKey

function A.usable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function capture(...)
    return {n = select("#", ...), ...}
end

function A.safe(fn, ...)
    if not A.usable(fn) or type(fn) ~= "function" then return end
    local results = capture(pcall(fn, ...))
    if not results[1] then return end
    for index = 2, results.n do
        if not A.usable(results[index]) then results[index] = nil end
    end
    return unpack(results, 2, results.n)
end

function A.playClickSound()
    local sound = SOUNDKIT and (SOUNDKIT.IG_MAINMENU_OPTION or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if type(sound) == "number" then A.safe(PlaySound, sound) end
end

function A.inCombat()
    return type(InCombatLockdown) == "function" and A.safe(InCombatLockdown) == true
end

function A.finite(value)
    return A.usable(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

function A.mapID(value)
    return A.finite(value) and value > 0 and value <= 2147483647 and value % 1 == 0
end

function A.now()
    local timestamp = A.safe(GetServerTime) or A.safe(time) or A.safe(os and os.time)
    return A.finite(timestamp) and timestamp or 0
end

function A.displayText(value)
    return (value:gsub("|", "||"))
end

function A.print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(L.TITLE .. ": " .. message)
    elseif type(print) == "function" then
        print(L.TITLE .. ": " .. message)
    end
end

function A.characterKey()
    if ownerKey then return ownerKey end
    local region = A.safe(GetCurrentRegion)
    local name, realm = A.safe(UnitFullName, "player")
    if not realm or realm == "" then realm = A.safe(GetNormalizedRealmName) end
    if not A.mapID(region) or type(name) ~= "string" or name == "" or
        type(realm) ~= "string" or realm == "" then return end
    ownerKey = ("%d:%s:%s"):format(region, realm, name)
    return ownerKey
end

function A.reportCapabilities()
    local version, build, _, interface = A.safe(GetBuildInfo)
    local map = WorldMapFrame
    local current = A.Map.currentMap()
    local position = A.Map.position(current)
    local playerZone = A.Map.playerZone(current)
    local function describe(name, present, observed)
        local result = not present and L.UNAVAILABLE or observed == false and L.RESTRICTED or L.AVAILABLE
        A.print(name .. " — " .. result)
    end
    A.print(L.DIAGNOSTICS)
    A.print(L.BUILD:format(tostring(version or "?"), tostring(build or "?"),
        tostring(interface or "?"), tostring(A.safe(GetLocale) or "?")))
    describe("GetLocale", type(GetLocale) == "function", A.safe(GetLocale) ~= nil)
    describe("C_Map.GetBestMapForUnit", C_Map and type(C_Map.GetBestMapForUnit) == "function", current ~= nil)
    describe("C_Map.GetMapInfo", C_Map and type(C_Map.GetMapInfo) == "function", A.Map.info(current) ~= nil)
    describe("C_Map.GetMapChildrenInfo", C_Map and type(C_Map.GetMapChildrenInfo) == "function", #A.Map.choices() > 1)
    describe("C_Map.GetPlayerMapPosition", C_Map and type(C_Map.GetPlayerMapPosition) == "function", position ~= nil)
    describe("WorldMapFrame", map ~= nil)
    describe("WorldMapFrame.GetMapID", map and type(map.GetMapID) == "function", A.Map.displayed() ~= nil)
    describe("WorldMapFrame.SetMapID", map and type(map.SetMapID) == "function")
    describe("WorldMapFrame.ScrollContainer", map and map.ScrollContainer ~= nil)
    describe("WorldMapFrame.AddDataProvider", map and type(map.AddDataProvider) == "function", A.MapPins.available())
    describe("MapCanvasDataProviderMixin", type(MapCanvasDataProviderMixin) == "table")
    describe("MapCanvasPinMixin", type(MapCanvasPinMixin) == "table")
    describe("WorldMapFrame.AddCanvasClickHandler", map and type(map.AddCanvasClickHandler) == "function",
        A.MapIntegration.clickAvailable())
    describe(L.MAP_FIELD, A.MapIntegration.tabAvailable())
    describe("WorldMapFrame.IsProtected", map and type(map.IsProtected) == "function",
        map and A.safe(map.IsProtected, map) == false)
    describe("C_Timer.NewTicker", C_Timer and type(C_Timer.NewTicker) == "function")
    describe("C_Timer.After", C_Timer and type(C_Timer.After) == "function")
    describe("GameTooltip", GameTooltip ~= nil)
    describe("MenuUtil", type(MenuUtil) == "table")
    describe("PlaySound", type(PlaySound) == "function")
    describe("InCombatLockdown", type(InCombatLockdown) == "function", not A.inCombat())
    for _, event in ipairs(A.eventOrder or {}) do
        describe(event, A.registeredEvents[event])
    end
    if current then A.print("uiMapID: " .. current) end
    if playerZone then A.print(L.ZONE .. ": " .. playerZone) end
    if position then
        local x, y = A.Map.position(current)
        if x and y then A.print(L.PIN_COORDINATES:format(x * 100, y * 100)) end
    end
end
