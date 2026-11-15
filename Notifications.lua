local _, A = ...
local L = A.L
local Notifications = {}
A.Notifications = Notifications

local queue, queued = {}, {}
local current, toast, heading, title, note
local doneButton, laterButton, openButton
local attempted, advancing

local function createToast()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -105)
    frame:SetSize(382, 163)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
        insets = {left = 5, right = 5, top = 5, bottom = 5},
    })

    heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    heading:SetPoint("TOPLEFT", 15, -12)
    heading:SetText(L.REMINDER_DUE)

    title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 15, -29)
    title:SetSize(351, 38)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    title:SetMaxLines(2)

    note = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    note:SetPoint("TOPLEFT", 15, -70)
    note:SetSize(351, 52)
    note:SetJustifyH("LEFT")
    note:SetJustifyV("TOP")
    note:SetMaxLines(3)

    local function action(key, x, callback)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetPoint("BOTTOMLEFT", x, 12)
        button:SetSize(111, 24)
        button:SetText(L[key])
        button:SetScript("OnClick", function()
            A.playClickSound()
            callback()
        end)
        return button
    end

    doneButton = action("DONE", 15, function()
        if current and current.undo then
            A.Repository.undoCompletion(current.id)
            Notifications.refresh()
            return
        end
        local item = current and A.Repository.get(current.id)
        if not item then
            return
        end
        if item.repeatMode == "recurring" then
            Notifications.dismiss()
        else
            local entry = {id = item.id, undo = true}
            current = entry
            if not A.Repository.complete(item.id) then
                Notifications.dismiss()
                return
            end
            heading:SetText(L.DONE)
            note:SetText(L.COMPLETION_GRACE)
            doneButton:SetText(L.UNDO)
            laterButton:Hide()
            openButton:Hide()
            if C_Timer then
                A.safe(C_Timer.After, 5, function()
                    if current == entry then Notifications.dismiss() end
                end)
            end
        end
    end)
    laterButton = action("LATER", 135, Notifications.dismiss)
    openButton = action("OPEN", 255, function()
        if current then
            local id = current.id
            if A.UI.open(id) then Notifications.dismiss() end
        end
    end)
    return frame
end

function Notifications.init()
    if attempted or A.inCombat() then
        return
    end
    attempted = true
    toast = A.safe(createToast)
end

local function finish()
    if toast then
        toast:Hide()
    end
    current = nil
end

function Notifications.count()
    local total = current and not current.undo and 1 or 0
    for _, id in ipairs(queue) do
        if A.Engine.isDue(id) then
            total = total + 1
        end
    end
    return total
end

function Notifications.dismiss()
    if not current then
        return
    end
    local id = current.id
    finish()
    A.Engine.dismiss(id)
    Notifications.flush()
end

function Notifications.enqueue(id)
    if not id or queued[id] or not A.Engine.isDue(id) then
        return
    end
    if current and current.id == id then
        finish()
    end
    queue[#queue + 1] = id
    queued[id] = true
    Notifications.flush()
end

function Notifications.flush()
    if advancing then
        return
    end
    if A.inCombat() then
        if toast then
            toast:Hide()
        end
        return
    end
    if current then
        if toast then
            toast:Show()
        end
        return
    end
    if not A.Repository.settings().notifications then
        return
    end

    Notifications.init()
    advancing = true
    while #queue > 0 do
        local id = table.remove(queue, 1)
        queued[id] = nil
        local reminder = A.Repository.get(id)
        local delivered, leaving
        if reminder then delivered, leaving = A.Engine.delivered(id) end
        if delivered then
            local entry = {id = id}
            current = entry
            local label = leaving and L.REMINDER_OPEN_ON_EXIT or L.REMINDER_DUE
            local displayTitle = A.displayText(reminder.title)
            local displayNote = A.displayText(reminder.note ~= "" and reminder.note or A.Map.name(reminder.mapID) or "")
            if toast then
                heading:SetText(label)
                doneButton:SetText(L.DONE)
                laterButton:Show()
                openButton:Show()
                title:SetText(displayTitle)
                note:SetText(displayNote)
                toast:Show()
            else
                A.print(label .. "  " .. L.TOAST_CHAT:format(displayTitle, displayNote))
            end

            if A.Repository.settings().sound and SOUNDKIT and type(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) == "number" then
                A.safe(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end

            local after = C_Timer and C_Timer.After
            local scheduled = type(after) == "function" and pcall(after, 15, function()
                if current == entry then
                    Notifications.dismiss()
                end
            end)
            if not scheduled and not toast then
                finish()
                A.Engine.dismiss(id)
            end
            break
        end
    end
    advancing = false
end

function Notifications.refresh()
    local settings = A.Repository.settings()
    if not settings.notifications then
        for _, id in ipairs(queue) do
            A.Engine.dismiss(id)
        end
        queue, queued = {}, {}
        if current then
            local id = current.id
            finish()
            A.Engine.dismiss(id)
        end
        return
    end
    if current then
        local reminder = A.Repository.get(current.id)
        local validUndo = current.undo and reminder and reminder.deleteAfter
        if not validUndo and (not reminder or not reminder.enabled or reminder.status == "completed" or current.undo) then
            finish()
        end
    end
    Notifications.flush()
end
