local _, A = ...
local L = A.L
local pins = {}
local pinMixin = {}
local template = "MapMemoPinTemplate"
local provider
local failed = false

A.MapPins = pins

function pins.drawBell(frame, scale)
    local pieces = {
        {4, 2, 0, 7},
        {8, 2, 0, 5},
        {10, 4, 0, 2},
        {12, 3, 0, -1},
        {14, 2, 0, -3},
        {4, 2, 0, -6},
    }
    for _, piece in ipairs(pieces) do
        local texture = frame:CreateTexture(nil, "ARTWORK")
        texture:SetSize(piece[1] * scale, piece[2] * scale)
        texture:SetPoint("CENTER", frame, "CENTER", piece[3] * scale, piece[4] * scale)
        texture:SetColorTexture(1, 0.82, 0.31, 1)
    end
end

local function hideTooltip(pin)
    if GameTooltip and GameTooltip:IsOwned(pin) then
        GameTooltip:Hide()
    end
end

function MapMemoInitializePin(frame)
    Mixin(frame, MapCanvasPinMixin, pinMixin)
end

function pinMixin:OnLoad()
    self:SetScalingLimits(1, 1, 1)
    self:SetIgnoreGlobalPinScale(true)
    pins.drawBell(self, 0.85)
end

function pinMixin:OnAcquired(reminder)
    self.reminder = reminder
    self:SetPosition(reminder.x, reminder.y)
    self:ApplyCurrentScale()
end

function pinMixin:OnReleased()
    hideTooltip(self)
    self.reminder = nil
end

function pinMixin:GetDisplayName()
    return self.reminder and A.displayText(self.reminder.title) or L.TITLE
end

function pinMixin:OnMouseEnter()
    local reminder = self.reminder
    if not GameTooltip or not reminder or A.inCombat() then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self:GetDisplayName())
    if reminder.note ~= "" then
        GameTooltip:AddLine(A.displayText(reminder.note), 1, 1, 1, true)
    end
    GameTooltip:AddLine(L.PIN_COORDINATES:format(reminder.x * 100, reminder.y * 100))
    GameTooltip:Show()
end

function pinMixin:OnMouseLeave()
    hideTooltip(self)
end

function pinMixin:OnMouseClickAction(button)
    if button == "LeftButton" and self.reminder and not A.inCombat() then
        if A.UI.edit(self.reminder) then A.playClickSound() end
    end
end

local function hideOwnedPins(self)
    for _, pin in ipairs(self.activePins) do
        hideTooltip(pin)
        pcall(pin.Hide, pin)
    end
end

local function removeOwnedPins(self)
    self:GetMap():RemoveAllPinsByTemplate(template)
    self.activePins = {}
end

local function refreshOwnedPins(self)
    if A.inCombat() then
        hideOwnedPins(self)
        return
    end

    local map = self:GetMap()
    local success = pcall(function()
        removeOwnedPins(self)
        local mapID = A.Map.displayed()
        if not map:IsShown() or not mapID or not A.Map.isPointMap(mapID) then
            return
        end
        for _, reminder in ipairs(A.Repository.list()) do
            if reminder.type == "point" and reminder.mapID == mapID and reminder.enabled
                and reminder.status ~= "completed" and A.Map.coordinates(reminder.x, reminder.y) then
                self.activePins[#self.activePins + 1] = map:AcquirePin(template, reminder)
            end
        end
    end)
    if not success then
        failed = true
        hideOwnedPins(self)
        pcall(map.RemoveDataProvider, map, self)
    end
end

function pins.install(map)
    if not map or failed or A.inCombat() then
        return false
    end
    if provider then
        return provider:GetMap() == map
    end
    if type(MapCanvasDataProviderMixin) ~= "table" or type(MapCanvasPinMixin) ~= "table"
        or type(Mixin) ~= "function" or type(CreateFromMixins) ~= "function"
        or type(map.AddDataProvider) ~= "function"
        or type(map.RemoveDataProvider) ~= "function" or type(map.AcquirePin) ~= "function"
        or type(map.RemoveAllPinsByTemplate) ~= "function" or not C_XMLUtil
        or type(A.safe(C_XMLUtil.GetTemplateInfo, template)) ~= "table" then
        return false
    end

    local candidate = CreateFromMixins(MapCanvasDataProviderMixin)
    candidate.activePins = {}
    candidate.RefreshAllData = refreshOwnedPins
    candidate.RemoveAllData = removeOwnedPins
    if not pcall(map.AddDataProvider, map, candidate) then
        pcall(map.RemoveDataProvider, map, candidate)
        return false
    end
    provider = candidate
    provider:RefreshAllData()
    return not failed
end

function pins.refresh()
    if provider and not failed then
        provider:RefreshAllData()
    end
end

function pins.available()
    return provider ~= nil and not failed
end
