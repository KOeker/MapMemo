local _, A = ...
local L = A.L
local integration = {}
local key = "mapmemo"
local activeMap, questLog, panel, tab, sharedTabs, questTab
local clickRegistered, restorePending
local canvasClickPriority = -10

A.MapIntegration = integration

local function updatePanel()
    if not A.inCombat() then A.UI.refresh() end
    A.Engine.evaluate()
end

local function scheduleUpdate()
    if C_Timer and type(C_Timer.After) == "function" then
        A.safe(C_Timer.After, 0, updatePanel)
    else
        updatePanel()
    end
end

local function restoreQuestContent()
    if A.inCombat() then
        restorePending = true
        return
    end
    restorePending = nil
    if panel:IsShown() then
        panel:Hide()
        tab:SetChecked(false)
        for _, frame in ipairs(questLog.ContentFrames) do
            frame:SetShown(frame.displayMode == questLog.displayMode)
        end
        for _, button in ipairs(questLog.TabButtons) do
            button:SetChecked(button.displayMode == questLog.displayMode)
        end
    end
    if questTab then questTab:SetChecked(questLog.displayMode == QuestLogDisplayMode.Quests) end
end

local function selectTab()
    if A.inCombat() or not tab then return false end
    if sharedTabs then
        A.safe(sharedTabs.Select, key)
    else
        panel:Show()
        for _, frame in ipairs(questLog.ContentFrames) do frame:Hide() end
        for _, button in ipairs(questLog.TabButtons) do button:SetChecked(false) end
        if questTab then questTab:SetChecked(false) end
        tab:SetChecked(true)
    end
    A.UI.refresh()
    return panel:IsShown()
end

local function onTabClick(_, button, inside)
    if button == "LeftButton" and inside then selectTab() end
end

local function createNativeTab(name)
    return CreateFrame("Button", name, questLog, "LargeSideTabButtonTemplate")
end

local function installNativeTab()
    if type(hooksecurefunc) ~= "function" or type(questLog.SetDisplayMode) ~= "function"
        or type(questLog.ContentFrames) ~= "table" or type(questLog.TabButtons) ~= "table"
        or not questLog.QuestsTab then return end

    local button = createNativeTab("MapMemoWorldMapTab")
    button:Hide()
    if QuestMapFrameOverrides and QuestMapFrameOverrides.questTabHidden and QuestLogDisplayMode then
        local quests = createNativeTab("MapMemoQuestsTab")
        local _, offset = A.safe(QuestMapFrameOverrides.GetQuestsTabAnchorOffset)
        quests:SetPoint("TOPLEFT", questLog, "TOPRIGHT", 0, A.finite(offset) and offset or 0)
        quests.tooltipText = QUESTS_LABEL or L.ZONE
        quests.activeAtlas = "questlog-tab-icon-quest"
        quests.inactiveAtlas = "questlog-tab-icon-quest-inactive"
        quests:SetCustomOnMouseUpHandler(function(_, mouseButton, inside)
            if mouseButton == "LeftButton" and inside and not A.inCombat() then
                questLog:SetDisplayMode(QuestLogDisplayMode.Quests)
                restoreQuestContent()
            end
        end)
        quests:SetChecked(questLog.displayMode == QuestLogDisplayMode.Quests)
        questTab = quests
    end

    local above = questTab or questLog.QuestsTab
    for _, native in ipairs(questLog.TabButtons) do
        if native:IsShown() then above = native end
    end
    button:SetPoint("TOP", above, "BOTTOM", 0, -3)
    hooksecurefunc(questLog, "SetDisplayMode", restoreQuestContent)
    if type(QuestMapFrame_ShowQuestDetails) == "function" then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", restoreQuestContent)
    end
    button:SetChecked(false)
    button:Show()
    return button
end

local function setTabIcon(button)
    local icon = button.Icon
    if not icon then return end
    local atlas = "Waypoint-MapPin-Tracked"
    local info = C_Texture and A.safe(C_Texture.GetAtlasInfo, atlas)
    if type(info) == "table" and A.finite(info.width) and info.width > 0
        and A.finite(info.height) and info.height > 0 then
        icon:SetAtlas(atlas)
        local scale = 32 / math.max(info.width, info.height)
        icon:SetSize(info.width * scale, info.height * scale)
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        icon:SetSize(28, 28)
    end
end

local function attachTab(map)
    local host = QuestMapFrame
    if not host or host ~= map.QuestLog or not host.ContentsAnchor then return end
    questLog = host
    panel = panel or A.UI.attach(host)
    if not panel then return end

    local registry = ForeverCore and ForeverCore.QuestLogTabs
    if registry and type(registry.Register) == "function" and type(registry.Select) == "function" then
        tab = A.safe(registry.Register, key, {
            name = "MapMemoWorldMapTab",
            tooltip = L.TITLE,
            panel = panel,
            order = 30,
            shown = function(visible)
                if visible and not A.inCombat() then A.UI.refresh() end
            end,
        })
        if tab then sharedTabs = registry end
    elseif type(QuestLogMixin) == "table" or type(host.SetDisplayMode) == "function" then
        tab = A.safe(installNativeTab)
    end
    if not tab then return end
    tab:SetCustomOnMouseUpHandler(onTabClick)
    setTabIcon(tab)
end

function integration.refresh()
    if not tab or A.inCombat() then return end
    if restorePending then restoreQuestContent() end
    tab.tooltipText = L.TITLE .. "\n" .. L.MAP_TAB_TOOLTIP:format(A.Notifications.count())
    if clickRegistered then tab.tooltipText = tab.tooltipText .. "\n" .. L.MAP_CLICK_HINT end
end

local function handleCanvasClick(map, button, x, y)
    if map ~= activeMap or not tab or button ~= "RightButton" or A.inCombat()
        or not A.safe(IsShiftKeyDown) or A.safe(IsControlKeyDown) or A.safe(IsAltKeyDown)
        or not A.Map.coordinates(x, y) or x == 0 or x == 1 or y == 0 or y == 1 then
        return false
    end
    local scroll = map.ScrollContainer
    local focus = A.safe(GetMouseFoci)
    if type(focus) ~= "table" or not A.usable(focus[1]) or focus[1] ~= scroll
        or not A.safe(scroll.IsMouseMotionFocus, scroll) then return false end
    local mapID = A.Map.displayed()
    if not mapID or not A.Map.isPointMap(mapID) then return false end
    return A.UI.edit(nil, {type = "point", mapID = mapID, x = x, y = y}) == true
end

function integration.install()
    local map = WorldMapFrame
    if not map or type(map.GetMapID) ~= "function" or A.inCombat() then return end
    if activeMap and map ~= activeMap then return end
    if not activeMap then
        activeMap = map
        if map.ScrollContainer and type(map.AddCanvasClickHandler) == "function"
            and type(map.RemoveCanvasClickHandler) == "function" and type(GetMouseFoci) == "function"
            and type(IsShiftKeyDown) == "function" then
            clickRegistered = pcall(map.AddCanvasClickHandler, map, handleCanvasClick, canvasClickPriority)
            if not clickRegistered then
                pcall(map.RemoveCanvasClickHandler, map, handleCanvasClick, canvasClickPriority)
            end
        end
        if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
            local function mapVisibilityChanged(_, frame)
                if frame == map then scheduleUpdate() end
            end
            for _, event in ipairs({"ShowUIPanel", "HideUIPanel", "ForcePanelHide"}) do
                A.safe(EventRegistry.RegisterCallback, EventRegistry,
                    "UIParentPanelManager." .. event, mapVisibilityChanged, integration)
            end
        end
        if type(hooksecurefunc) == "function" then
            if type(map.SetQuestLogPanelShown) == "function" then
                pcall(hooksecurefunc, map, "SetQuestLogPanelShown", scheduleUpdate)
            end
            if type(map.SetMapID) == "function" then
                pcall(hooksecurefunc, map, "SetMapID", scheduleUpdate)
            end
        end
    end
    A.MapPins.install(map)
    if not tab then A.safe(attachTab, map) end
    integration.refresh()
end

local function openWorldMap(id)
    if type(OpenWorldMap) == "function" and pcall(OpenWorldMap, id) then return true end
    return C_Map and type(C_Map.OpenWorldMap) == "function" and pcall(C_Map.OpenWorldMap, id)
end

function integration.open()
    if A.inCombat() then return false end
    local map = WorldMapFrame
    if not map or A.safe(map.IsShown, map) ~= true then openWorldMap() end
    integration.install()
    if not tab or WorldMapFrame ~= activeMap then return false end
    if not questLog:IsShown() then
        A.safe(activeMap.HandleUserActionOpenQuestLog, activeMap)
    end
    return activeMap:IsShown() and questLog:IsShown() and selectTab()
end

function integration.showOnMap(reminder)
    if A.inCombat() or not reminder or not A.Map.info(reminder.mapID) then return false end
    return openWorldMap(reminder.mapID) and A.Map.displayed() == reminder.mapID
end

function integration.tabAvailable()
    return tab ~= nil and WorldMapFrame == activeMap
end

function integration.clickAvailable()
    return clickRegistered == true and integration.tabAvailable()
end
