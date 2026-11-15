local addonName, A = ...
local L = A.L
local frame = CreateFrame("Frame")
local initialized, loggedIn, pendingOpen

local function updateMap()
    if not loggedIn or A.inCombat() then return end
    A.MapIntegration.install()
    A.MapIntegration.refresh()
end

function A.changed()
    if not loggedIn then return end
    A.Engine.evaluate()
    A.Notifications.refresh()
    if not A.inCombat() then
        A.UI.refresh()
        A.MapPins.refresh()
        A.MapIntegration.refresh()
    end
end

A.eventOrder = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_MAP_CHANGED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
}
A.registeredEvents = {}

local function init()
    if initialized then return end
    initialized = true
    A.Storage.init()
    if A.Storage.issue then A.print(L[A.Storage.issue]) end
    SLASH_MAPMEMO1 = "/mmemo"
    SLASH_MAPMEMO2 = "/mapmemo"
    SlashCmdList.MAPMEMO = function(message)
        local command = message:match("^%s*(.-)%s*$"):lower()
        if command == "help" then
            A.print(L.HELP)
        elseif command == "debug" then
            if A.Repository.settings().developerMode then A.reportCapabilities() else A.print(L.HELP) end
        elseif command == "" then
            if A.inCombat() then
                pendingOpen = true
                A.print(L.COMBAT_WAIT)
            else
                A.UI.open()
            end
        else
            A.print(L.HELP)
        end
    end
end

local function login()
    init()
    if loggedIn then return end
    loggedIn = true
    A.Repository.expireCompleted()
    A.Notifications.init()
    updateMap()
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = A.safe(metadata, addonName, "Version") or "?"
    A.print(L.LOADED:format(version))
end

frame:SetScript("OnEvent", function(_, event, argument)
    if event == "ADDON_LOADED" then
        if argument == addonName then
            init()
            if A.safe(IsLoggedIn) == true then
                login()
                A.Engine.evaluate()
            end
        elseif argument == "Blizzard_WorldMap" then
            updateMap()
        end
    elseif event == "PLAYER_LOGIN" then
        login()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if not loggedIn then return end
        A.MapIntegration.refresh()
        A.MapPins.refresh()
        A.Notifications.flush()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not loggedIn then return end
        updateMap()
        A.changed()
        A.Notifications.flush()
        if pendingOpen then
            pendingOpen = nil
            A.UI.open()
        end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        updateMap()
    elseif loggedIn then
        A.Repository.expireCompleted()
        A.Engine.evaluate()
    end
end)

for _, event in ipairs(A.eventOrder) do
    A.registeredEvents[event] = pcall(frame.RegisterEvent, frame, event)
end
