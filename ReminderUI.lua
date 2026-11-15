local _, A = ...
local L = A.L
local UI = {}
local panelWidth, panelHeight = 320, 465
A.UI = UI

local pane, panel, screens, search, filterButton, listPage, listEmpty, listRows
local selected, selectedTitle, pauseButton, doneButton, mapButton, newButton, settingsButton
local editor, mapLabel, editorError, coordinateControls
local pickerQuery, pickerPage, pickerRows, pickerEmpty, pickerChoices
local confirmText, settingsButtons
local filterIndex, page, mapPage = 1, 1, 1
local filters = {"ALL_ZONES", "THIS_ZONE", "ACTIVE", "COMPLETED"}
local draft, editingID, deleteID
local listTop, rowHeight, footerHeight, footerInset = 93, 54, 90, 10
local rowCount, pickerCount = 5, 9
local createListRow
local countdownScheduled

local function place(region, x, y, width, height)
    region:SetPoint("TOPLEFT", x, -y)
    region:SetSize(width, height)
    return region
end

local function text(parent, x, y, width, height, font)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    label:SetJustifyH("LEFT")
    return place(label, x, y, width, height)
end

local function button(parent, key, x, y, width, action)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetText(L[key])
    control:SetScript("OnClick", function(self)
        A.playClickSound()
        action(self)
    end)
    return place(control, x, y, width, 24)
end

local function tooltip(control, label)
    control:SetScript("OnEnter", function(self)
        if GameTooltip and not A.inCombat() then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L[label])
            GameTooltip:Show()
        end
    end)
    control:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
end

local function editBox(parent, x, y, width, limit)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetMaxBytes(limit)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    return place(box, x, y, width, 24)
end

local function editPlainText(box, limit)
    box:SetMaxBytes(limit * 2)
    if type(box.SetVisibleTextByteLimit) == "function" then
        box:SetVisibleTextByteLimit(limit)
    end
    local function escapeRun(pipes)
        return #pipes % 2 == 0 and pipes or pipes .. "|"
    end
    box:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end
        local value = self:GetText()
        local escaped = value:gsub("|+", escapeRun)
        if escaped ~= value then
            local position = self:GetCursorPosition()
            local prefix = value:sub(1, position):gsub("|+", escapeRun)
            self:SetText(escaped)
            self:SetCursorPosition(#prefix)
        end
    end)
end

local function readPlainText(box)
    return (box:GetText():gsub("||", "|"))
end

local function screen(name)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetAllPoints()
    frame:Hide()
    screens[name] = frame
    return frame
end

local function show(name)
    for key, frame in pairs(screens) do
        frame:SetShown(key == name)
    end
end

local function mapName(id)
    return (id and A.Map.name(id)) or L.MAP_UNAVAILABLE
end

local function stateKey(reminder)
    if reminder.status == "completed" then
        return "COMPLETED"
    end
    return reminder.enabled and "ACTIVE" or "PAUSED"
end

local uppercaseGerman = {["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü", ["ẞ"] = "ß"}

local function searchText(value)
    local lower = (value or ""):gsub("[A-Z]", function(letter)
        return string.char(letter:byte() + 32)
    end)
    return (lower:gsub("[\194-\244][\128-\191]+", uppercaseGerman))
end

local function matches(value, query)
    return searchText(value):find(query, 1, true) ~= nil
end

local function setOption(control, label, value)
    control:SetText(L.SETTINGS_STATE:format(L[label], L[value]))
end

local function refreshCountdowns()
    local now, counting = A.now(), false
    for _, row in ipairs(listRows) do
        local seconds = row.deleteAfter and math.ceil(row.deleteAfter - now)
        local pending = seconds and seconds > 0
        row.countdown:SetShown(not not pending)
        if pending then
            row.countdown:SetText(L.AUTO_DELETE_COUNTDOWN:format(seconds))
            counting = true
        end
    end
    if counting and screens.list:IsVisible() and not countdownScheduled and C_Timer
        and type(C_Timer.After) == "function" then
        countdownScheduled = pcall(C_Timer.After, 1, function()
            countdownScheduled = false
            if screens.list:IsVisible() then refreshCountdowns() end
        end)
    end
end

local function renderList()
    local rows = {}
    local query = searchText(search:GetText())
    local current = A.Map.displayed() or A.Map.playerZone()
    for _, reminder in ipairs(A.Repository.list()) do
        local validFilter = filterIndex == 1
            or (filterIndex == 2 and current == reminder.mapID)
            or (filterIndex == 3 and stateKey(reminder) == "ACTIVE")
            or (filterIndex == 4 and stateKey(reminder) == "COMPLETED")
        if validFilter and (matches(reminder.title, query) or matches(reminder.note, query)
            or matches(mapName(reminder.mapID), query)) then
            rows[#rows + 1] = reminder
        end
    end

    local pages = math.max(1, math.ceil(#rows / rowCount))
    page = math.min(math.max(1, page), pages)
    filterButton:SetText(L[filters[filterIndex]])
    listPage:SetText(L.PAGE:format(page, pages))
    listEmpty:SetText(A.Repository.readOnly() and L.ERROR_STORAGE
        or (query == "" and filterIndex == 1 and L.NO_REMINDERS or L.NO_RESULTS))
    listEmpty:SetShown(#rows == 0)
    local writable = not A.Repository.readOnly()
    newButton:SetEnabled(writable)
    settingsButton:SetEnabled(writable)
    local slots = math.min(#rows - (page - 1) * rowCount, rowCount)
    for index = #listRows + 1, slots do
        listRows[index] = createListRow(screens.list, index)
    end
    for index, row in ipairs(listRows) do
        local reminder = index <= rowCount and rows[(page - 1) * rowCount + index]
        row.id = reminder and reminder.id
        row.deleteAfter = reminder and reminder.deleteAfter or false
        row:SetShown(not not reminder)
        if reminder then
            local state = stateKey(reminder)
            local meta = L[state] .. "  ·  " .. L[reminder.type == "point" and "LOCATION" or "ZONE"]
                .. "  ·  " .. L[reminder.repeatMode == "recurring" and "RECURRING" or "ONE_TIME"]
            row.title:SetText(A.displayText(reminder.title))
            row.map:SetText(A.displayText(mapName(reminder.mapID)))
            row.details:SetWidth(reminder.deleteAfter and 173 or 286)
            row.details:SetText(meta)
            row.edit:SetEnabled(writable and not reminder.deleteAfter)
            row.delete:SetEnabled(writable)
        end
    end

    local reminder = selected and A.Repository.get(selected)
    selectedTitle:SetText(reminder and A.displayText(reminder.title) or "")
    local state = reminder and stateKey(reminder)
    local canUndo = reminder and reminder.deleteAfter ~= nil
    pauseButton:SetText(L[canUndo and "UNDO" or state == "ACTIVE" and "PAUSE" or "RESUME"])
    pauseButton:SetEnabled(writable and state ~= nil and (state ~= "COMPLETED" or canUndo))
    doneButton:SetEnabled(writable and state ~= nil and state ~= "COMPLETED")
    mapButton:SetEnabled(reminder ~= nil)
    refreshCountdowns()
end

local function activateList()
    draft, editingID, deleteID = nil, nil, nil
    show("list")
    renderList()
end

local function setPositionFields(x, y)
    draft.x, draft.y = x, y
    editor.x:SetText(x and string.format("%.6f", x * 100):gsub("0+$", ""):gsub("%.$", "") or "")
    editor.y:SetText(y and string.format("%.6f", y * 100):gsub("0+$", ""):gsub("%.$", "") or "")
    draft.originalX, draft.originalY = editor.x:GetText(), editor.y:GetText()
end

local function supportedMap(mapID)
    if draft.type == "point" then
        return A.Map.isPointMap(mapID)
    end
    return A.Map.isZone(mapID)
end

local function renderEditor()
    mapLabel:SetText(A.displayText(mapName(draft.mapID)))
    editor.kind:SetText(L[draft.type == "point" and "LOCATION" or "ZONE"])
    editor.radius:SetText(L[draft.radiusNormalized == 0.03 and "RADIUS_WIDE" or "RADIUS_NEAR"])
    editor.repeatMode:SetText(L[draft.repeatMode == "recurring" and "RECURRING" or "ONE_TIME"])
    editor.scope:SetText(L[draft.scope == "account" and "ACCOUNT_WIDE" or "THIS_CHARACTER"])
    editor.enabled:SetText(L[draft.enabled and "ACTIVE" or "PAUSED"])
    coordinateControls:SetShown(draft.type == "point")
end

local function chooseMap(id)
    if not id or not supportedMap(id) then
        editorError:SetText(L[draft.type == "point" and "UNSUPPORTED_LOCATION" or "MAP_UNAVAILABLE"])
        return false
    end
    if draft.mapID ~= id then
        draft.mapID = id
        setPositionFields()
    end
    editorError:SetText("")
    renderEditor()
    return true
end

local function renderPicker()
    if not draft then
        return
    end
    local options = {}
    local query = searchText(pickerQuery:GetText())
    for _, entry in ipairs(pickerChoices) do
        if supportedMap(entry.mapID) and matches(entry.name, query) then
            options[#options + 1] = entry
        end
    end
    local pages = math.max(1, math.ceil(#options / pickerCount))
    mapPage = math.min(math.max(1, mapPage), pages)
    pickerPage:SetText(L.PAGE:format(mapPage, pages))
    pickerEmpty:SetShown(#options == 0)
    for index, row in ipairs(pickerRows) do
        local option = options[(mapPage - 1) * pickerCount + index]
        row.mapID = option and option.mapID
        row:SetShown(option ~= nil)
        if option then
            row:SetText(A.displayText(option.name))
        end
    end
end

local function percent(box)
    local value = tonumber((box:GetText():gsub(",", ".")))
    return value and value / 100
end

local function save()
    if draft.type == "point" then
        local x = draft.x
        local y = draft.y
        if editor.x:GetText() ~= draft.originalX then x = percent(editor.x) end
        if editor.y:GetText() ~= draft.originalY then y = percent(editor.y) end
        if not x or not y then
            editorError:SetText(L.POSITION_REQUIRED)
            return
        end
        draft.x, draft.y = x, y
        draft.originalX, draft.originalY = editor.x:GetText(), editor.y:GetText()
    end
    draft.title = readPlainText(editor.title)
    draft.note = readPlainText(editor.note)
    local reminder, errorKey = A.Repository.save(draft, editingID)
    if reminder then
        selected = reminder.id
        activateList()
    else
        editorError:SetText(L[errorKey or "ERROR_STORAGE"])
    end
end

createListRow = function(frame, index)
    local row = place(CreateFrame("Button", nil, frame), 15, listTop + (index - 1) * rowHeight, 289, 51)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnClick", function(self)
        A.playClickSound()
        selected = self.id
        renderList()
    end)
    row.title = text(row, 2, 4, 154, 20, "GameFontNormal")
    row.map = text(row, 2, 23, 286, 14, "GameFontHighlightSmall")
    row.details = text(row, 2, 37, 286, 14, "GameFontHighlightSmall")
    row.countdown = text(row, 177, 37, 110, 14, "GameFontHighlightSmall")
    row.countdown:SetJustifyH("RIGHT")
    row.countdown:SetTextColor(1, 0.25, 0.25)
    row.title:SetWordWrap(false)
    row.map:SetWordWrap(false)
    row.details:SetWordWrap(false)
    row.edit = button(row, "EDIT", 155, 0, 71, function()
        local reminder = row.id and A.Repository.get(row.id)
        if reminder then
            selected = reminder.id
            UI.edit(reminder)
        end
    end)
    row.delete = button(row, "DELETE", 228, 0, 61, function()
        local reminder = row.id and A.Repository.get(row.id)
        if reminder then
            deleteID = reminder.id
            confirmText:SetText(L.DELETE_CONFIRM:format(A.displayText(reminder.title)))
            show("confirm")
        end
    end)
    return row
end

local function createList()
    local frame = screen("list")
    text(frame, 16, 44, 288, 18):SetText(L.SEARCH)
    search = editBox(frame, 19, 64, 154, 120)
    search:SetScript("OnTextChanged", function()
        page = 1
        renderList()
    end)
    filterButton = button(frame, filters[filterIndex], 180, 64, 124, function()
        filterIndex = filterIndex % #filters + 1
        page = 1
        renderList()
    end)
    newButton = button(frame, "ADD_BUTTON", 181, 13, 35, function() UI.edit() end)
    tooltip(newButton, "NEW_REMINDER")
    settingsButton = button(frame, "SETTINGS", 221, 13, 83, function()
        show("settings")
        UI.refresh()
    end)
    listRows = {}
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        page = page - delta
        renderList()
    end)
    listEmpty = text(frame, 19, 115, 282, 110)
    listEmpty:SetJustifyV("TOP")
    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 0, footerInset)
    footer:SetPoint("BOTTOMRIGHT", 0, footerInset)
    footer:SetHeight(footerHeight)
    tooltip(button(footer, "PREVIOUS_ARROW", 17, 0, 41, function()
        page = page - 1
        renderList()
    end), "PREVIOUS_PAGE")
    tooltip(button(footer, "NEXT_ARROW", 264, 0, 41, function()
        page = page + 1
        renderList()
    end), "NEXT_PAGE")
    listPage = text(footer, 65, 0, 190, 24)
    listPage:SetJustifyH("CENTER")
    selectedTitle = text(footer, 17, 28, 286, 20, "GameFontNormal")
    selectedTitle:SetWordWrap(false)
    pauseButton = button(footer, "PAUSE", 15, 50, 91, function()
        local reminder = selected and A.Repository.get(selected)
        if reminder and reminder.deleteAfter then
            A.Repository.undoCompletion(reminder.id)
        elseif reminder then
            A.Repository.setEnabled(reminder.id, not reminder.enabled)
        end
    end)
    doneButton = button(footer, "DONE", 109, 50, 85, function()
        if selected then
            A.Repository.complete(selected)
        end
    end)
    mapButton = button(footer, "SHOW_ON_MAP", 197, 50, 108, function()
        local reminder = selected and A.Repository.get(selected)
        if reminder then
            if A.inCombat() then
                A.print(L.COMBAT_WAIT)
            elseif not A.MapIntegration.showOnMap(reminder) then
                A.print(L.MAP_UNAVAILABLE)
            end
        end
    end)
end

local function createNoteBox(parent)
    local scroll = place(CreateFrame("ScrollFrame", nil, parent, "BackdropTemplate"), 17, 148, 286, 78)
    scroll:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1},
    })
    scroll:SetBackdropColor(0.15, 0.12, 0.09, 1)
    scroll:SetBackdropBorderColor(0.65, 0.52, 0.34, 1)
    local note = CreateFrame("EditBox", nil, scroll)
    note:SetMultiLine(true)
    note:SetAutoFocus(false)
    note:EnableMouse(true)
    note:SetFontObject(GameFontHighlight)
    editPlainText(note, 1000)
    note:SetSize(286, 78)
    note:SetTextInsets(7, 7, 5, 5)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then note:SetFocus() end
    end)
    note:SetScript("OnEscapePressed", note.ClearFocus)
    note:SetScript("OnCursorChanged", function(self, _, y, _, height)
        local top = scroll:GetVerticalScroll()
        local bottom = -y + height + 8
        if bottom > self:GetHeight() then
            self:SetHeight(bottom)
            scroll:UpdateScrollChildRect()
        end
        if -y < top then
            scroll:SetVerticalScroll(math.max(0, -y))
        elseif bottom > top + scroll:GetHeight() then
            scroll:SetVerticalScroll(bottom - scroll:GetHeight())
        end
    end)
    scroll:SetScrollChild(note)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local position = self:GetVerticalScroll() - delta * 20
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), position)))
    end)
    return note, scroll
end

local function createEditor()
    local frame = screen("editor")
    editor = {}
    editor.heading = text(frame, 16, 43, 161, 24, "GameFontNormal")
    editor.kind = button(frame, "ZONE", 184, 43, 120, function()
        draft.type = draft.type == "point" and "zone" or "point"
        editorError:SetText("")
        renderEditor()
    end)
    text(frame, 16, 75, 288, 17):SetText(L.TITLE_FIELD)
    editor.title = editBox(frame, 20, 96, 279, 120)
    editPlainText(editor.title, 120)
    text(frame, 16, 127, 288, 17):SetText(L.NOTE_FIELD)
    editor.note, editor.noteScroll = createNoteBox(frame)
    mapLabel = text(frame, 16, 232, 288, 22, "GameFontNormal")
    mapLabel:SetWordWrap(false)
    button(frame, "PICK_MAP", 16, 258, 90, function()
        pickerChoices = A.Map.choices()
        mapPage = 1
        pickerQuery:SetText("")
        show("picker")
        renderPicker()
    end)
    button(frame, "CURRENT_MAP", 109, 258, 95, function() chooseMap(A.Map.playerZone()) end)
    button(frame, "DISPLAYED_MAP", 207, 258, 97, function() chooseMap(A.Map.displayed()) end)

    coordinateControls = CreateFrame("Frame", nil, frame)
    coordinateControls:SetAllPoints()
    text(coordinateControls, 16, 290, 43, 22):SetText(L.X_PERCENT)
    editor.x = editBox(coordinateControls, 58, 289, 51, 16)
    text(coordinateControls, 117, 290, 42, 22):SetText(L.Y_PERCENT)
    editor.y = editBox(coordinateControls, 158, 289, 51, 16)
    button(coordinateControls, "PLAYER_POSITION", 16, 321, 171, function()
        local mapID = A.Map.currentMap()
        if not mapID or not A.Map.isPointMap(mapID) then
            editorError:SetText(L.UNSUPPORTED_LOCATION)
            return
        end
        local x, y = A.Map.position(mapID)
        if x and y and chooseMap(mapID) then
            setPositionFields(x, y)
        else
            editorError:SetText(L.UNSUPPORTED_LOCATION)
        end
    end)
    editor.radius = button(coordinateControls, "RADIUS_NEAR", 192, 321, 112, function()
        draft.radiusNormalized = draft.radiusNormalized == 0.03 and 0.01 or 0.03
        renderEditor()
    end)
    tooltip(editor.radius, "RADIUS")
    editor.repeatMode = button(frame, "ONE_TIME", 16, 354, 89, function()
        draft.repeatMode = draft.repeatMode == "recurring" and "once" or "recurring"
        renderEditor()
    end)
    editor.scope = button(frame, "THIS_CHARACTER", 107, 354, 122, function()
        draft.scope = draft.scope == "account" and "character" or "account"
        renderEditor()
    end)
    editor.enabled = button(frame, "ACTIVE", 231, 354, 73, function()
        draft.enabled = not draft.enabled
        renderEditor()
    end)
    editor.title:SetScript("OnTabPressed", function() editor.note:SetFocus() end)
    editor.note:SetScript("OnTabPressed", function()
        (draft.type == "point" and editor.x or editor.title):SetFocus()
    end)
    editor.x:SetScript("OnTabPressed", function() editor.y:SetFocus() end)
    editor.y:SetScript("OnTabPressed", function() editor.title:SetFocus() end)

    editorError = text(frame, 16, 383, 288, 39, "GameFontRed")
    button(frame, "CANCEL", 16, 425, 113, activateList)
    button(frame, "SAVE", 191, 425, 113, save)
end

local function createPicker()
    local frame = screen("picker")
    text(frame, 16, 49, 287, 20, "GameFontNormal"):SetText(L.PICK_MAP)
    text(frame, 16, 76, 288, 20):SetText(L.SEARCH)
    pickerQuery = editBox(frame, 19, 98, 281, 120)
    pickerQuery:SetScript("OnTextChanged", function()
        mapPage = 1
        renderPicker()
    end)
    pickerRows = {}
    for index = 1, pickerCount do
        local row = button(frame, "PICK_MAP", 16, 128 + (index - 1) * 28, 288, function(self)
            if chooseMap(self.mapID) then
                show("editor")
            end
        end)
        pickerRows[index] = row
    end
    pickerEmpty = text(frame, 16, 131, 288, 44)
    pickerEmpty:SetText(L.NO_MAPS)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        mapPage = mapPage - delta
        renderPicker()
    end)
    tooltip(button(frame, "PREVIOUS_ARROW", 16, 385, 41, function()
        mapPage = mapPage - 1
        renderPicker()
    end), "PREVIOUS_PAGE")
    tooltip(button(frame, "NEXT_ARROW", 263, 385, 41, function()
        mapPage = mapPage + 1
        renderPicker()
    end), "NEXT_PAGE")
    pickerPage = text(frame, 64, 385, 192, 24)
    pickerPage:SetJustifyH("CENTER")
    button(frame, "BACK", 16, 425, 113, function() show("editor") end)
end

local function createOptions()
    local frame = screen("settings")
    text(frame, 16, 50, 286, 25, "GameFontNormal"):SetText(L.SETTINGS)
    settingsButtons = {}
    local function setting(key, label, y)
        settingsButtons[key] = {label = label, control = button(frame, label, 16, y, 288, function()
            A.Repository.setSetting(key, not A.Repository.settings()[key])
            UI.refresh()
        end)}
    end
    setting("notifications", "NOTIFICATIONS", 90)
    setting("sound", "SOUND", 124)
    setting("developerMode", "DEVELOPER_MODE", 158)
    button(frame, "BACK", 16, 425, 113, activateList)
end

local function createConfirm()
    local frame = screen("confirm")
    confirmText = text(frame, 16, 110, 288, 150, "GameFontNormal")
    button(frame, "CANCEL", 16, 287, 113, activateList)
    button(frame, "DELETE", 191, 287, 113, function()
        if deleteID then
            A.Repository.delete(deleteID)
        end
        activateList()
    end)
end

function UI.attach(host)
    if pane then return pane end
    pane = CreateFrame("Frame", "MapMemoQuestPanel", host)
    pane:Hide()
    local questBody = host.QuestsFrame and host.QuestsFrame.ScrollFrame
    if questBody then
        pane:SetAllPoints(questBody)
    else
        pane:SetPoint("TOPLEFT", host.ContentsAnchor, "TOPLEFT", 0, -29)
        pane:SetPoint("BOTTOMRIGHT", host.ContentsAnchor, "BOTTOMRIGHT", -22, 0)
    end
    pane:SetFrameLevel(host:GetFrameLevel() + 20)
    pane:EnableMouse(true)

    local background = pane:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.055, 0.045, 0.03, 1)

    panel = CreateFrame("Frame", nil, pane)
    panel:SetSize(panelWidth, panelHeight)
    panel:SetPoint("TOP", pane, "TOP")

    text(panel, 16, 13, 154, 24, "GameFontNormalLarge"):SetText(L.TITLE)
    screens = {}
    createList()
    createEditor()
    createPicker()
    createOptions()
    createConfirm()
    activateList()

    local function fit(_, width, height)
        if type(width) ~= "number" or width <= 0 or type(height) ~= "number" or height <= 0 then return end
        local scale = math.min(1, width / panelWidth, height / panelHeight)
        local contentHeight = height / scale
        panel:SetScale(scale)
        panel:SetHeight(contentHeight)
        local visibleRows = math.max(1, math.floor((contentHeight - listTop - footerHeight - footerInset) / rowHeight))
        if visibleRows ~= rowCount then
            page = math.floor((page - 1) * rowCount / visibleRows) + 1
            rowCount = visibleRows
            UI.refresh()
        end
    end
    pane:SetScript("OnSizeChanged", fit)
    fit(pane, pane:GetSize())
    return pane
end

function UI.open(id)
    if not A.MapIntegration.open() or not pane then
        A.print(L.MAP_TAB_UNAVAILABLE)
        return false
    end
    selected = id or selected
    activateList()
    return true
end

function UI.edit(reminder, defaults)
    if A.Repository.readOnly() or A.inCombat() then
        return false
    end
    if (not pane or not pane:IsVisible()) and not UI.open() then return false end
    local source = reminder or defaults or {}
    local mapID = source.mapID
    if not mapID then
        local displayed = A.Map.displayed()
        mapID = displayed and A.Map.isZone(displayed) and displayed or A.Map.playerZone()
    end
    draft = {
        type = source.type or "zone",
        mapID = mapID,
        radiusNormalized = source.radiusNormalized or 0.01,
        repeatMode = source.repeatMode or "once",
        scope = source.scope or "character",
        enabled = source.enabled ~= false,
    }
    editingID = reminder and reminder.id
    editor.heading:SetText(L[editingID and "EDIT" or "NEW_REMINDER"])
    editor.title:SetText(A.displayText(source.title or ""))
    editor.note:SetText("")
    editor.note:SetHeight(78)
    editor.note:SetText(A.displayText(source.note or ""))
    editor.noteScroll:UpdateScrollChildRect()
    editor.noteScroll:SetVerticalScroll(0)
    setPositionFields(source.x, source.y)
    editorError:SetText("")
    show("editor")
    renderEditor()
    return true
end

function UI.refresh()
    if not pane or not pane:IsVisible() then return end
    if screens.list:IsShown() then
        renderList()
    elseif screens.settings:IsShown() then
        local settings = A.Repository.settings()
        for key, entry in pairs(settingsButtons) do
            setOption(entry.control, entry.label, settings[key] and "ON" or "OFF")
        end
    end
end
