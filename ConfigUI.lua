local addonName, ns = ...

local configFrame = nil
local scrollContent = nil
local ROW_HEIGHT = 24
local CONFIG_WIDTH = 420
local CONFIG_HEIGHT = 400

local function CreateConfigFrame()
    local frame = CreateFrame("Frame", "TerribleBuffTrackerConfig", UIParent, "BackdropTemplate")
    frame:SetSize(CONFIG_WIDTH, CONFIG_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("TerribleBuffTracker")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Make closeable with Escape
    table.insert(UISpecialFrames, "TerribleBuffTrackerConfig")

    -- Scroll area for tracked buff list
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 110)

    scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(CONFIG_WIDTH - 44, 1)
    scrollFrame:SetScrollChild(scrollContent)

    -- Add section: Spell ID
    local idLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    idLabel:SetPoint("BOTTOMLEFT", 12, 82)
    idLabel:SetText("Spell ID:")

    local idBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    idBox:SetSize(80, 20)
    idBox:SetPoint("BOTTOMLEFT", 100, 80)
    idBox:SetAutoFocus(false)
    idBox:SetNumeric(true)
    frame.idBox = idBox

    -- Duration
    local durLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durLabel:SetPoint("BOTTOMLEFT", 190, 82)
    durLabel:SetText("Duration (s):")

    local durBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    durBox:SetSize(60, 20)
    durBox:SetPoint("BOTTOMLEFT", 270, 80)
    durBox:SetAutoFocus(false)
    durBox:SetNumeric(true)
    frame.durBox = durBox

    -- Label
    local lblLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblLabel:SetPoint("BOTTOMLEFT", 12, 54)
    lblLabel:SetText("Label (optional):")

    local lblBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    lblBox:SetSize(200, 20)
    lblBox:SetPoint("BOTTOMLEFT", 100, 52)
    lblBox:SetAutoFocus(false)
    frame.lblBox = lblBox

    -- Add button
    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("BOTTOMLEFT", 310, 50)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local spellID = tonumber(idBox:GetText())
        local duration = tonumber(durBox:GetText())
        local label = strtrim(lblBox:GetText() or "")
        if label == "" then label = nil end

        if ns:AddTrackedBuff(spellID, duration, label) then
            idBox:SetText("")
            durBox:SetText("")
            lblBox:SetText("")
            ns:RefreshConfigList()
        end
    end)

    -- Enter key support on input boxes
    idBox:SetScript("OnEnterPressed", function() durBox:SetFocus() end)
    durBox:SetScript("OnEnterPressed", function() lblBox:SetFocus() end)
    lblBox:SetScript("OnEnterPressed", function() addBtn:Click() end)

    -- Help text
    local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("BOTTOM", 0, 14)
    helpText:SetText("|cff888888/tbt reset - Reset display position|r")

    frame:Hide()
    return frame
end

local function CreateListRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(CONFIG_WIDTH - 44, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))

    -- Alternating background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(1, 1, 1, 0.05)
    else
        bg:SetColorTexture(0, 0, 0, 0.05)
    end

    -- Checkbox (enable/disable)
    row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.checkbox:SetSize(20, 20)
    row.checkbox:SetPoint("LEFT", 2, 0)

    -- Icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", row.checkbox, "RIGHT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Label
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.label:SetWidth(110)
    row.label:SetJustifyH("LEFT")

    -- Spell ID
    row.spellIDText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.spellIDText:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
    row.spellIDText:SetWidth(60)
    row.spellIDText:SetJustifyH("LEFT")
    row.spellIDText:SetTextColor(0.7, 0.7, 0.7)

    -- Duration
    row.durText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.durText:SetPoint("LEFT", row.spellIDText, "RIGHT", 4, 0)
    row.durText:SetWidth(40)
    row.durText:SetJustifyH("LEFT")
    row.durText:SetTextColor(0.7, 0.7, 0.7)

    -- Bar/Buff toggle button
    row.modeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.modeBtn:SetSize(50, 20)
    row.modeBtn:SetPoint("LEFT", row.durText, "RIGHT", 4, 0)

    -- Remove button
    row.removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeBtn:SetSize(20, 20)
    row.removeBtn:SetPoint("RIGHT", -2, 0)
    row.removeBtn:SetText("X")

    return row
end

local listRows = {}

function ns:RefreshConfigList()
    if not configFrame or not configFrame:IsShown() then return end

    -- Hide all existing rows
    for _, row in ipairs(listRows) do
        row:Hide()
    end

    -- Build sorted list of tracked buffs
    local sorted = {}
    for spellID, entry in pairs(ns.db.trackedBuffs) do
        table.insert(sorted, entry)
    end
    table.sort(sorted, function(a, b) return a.spellID < b.spellID end)

    -- Create/update rows
    for i, entry in ipairs(sorted) do
        if not listRows[i] then
            listRows[i] = CreateListRow(scrollContent, i)
        end
        local row = listRows[i]

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))

        -- Checkbox
        row.checkbox:SetChecked(entry.enabled ~= false)
        row.checkbox:SetScript("OnClick", function(self)
            ns:SetBuffEnabled(entry.spellID, self:GetChecked())
            ns:RefreshConfigList()
        end)

        row.icon:SetTexture(ns:GetSpellIcon(entry.spellID))
        row.label:SetText(entry.label)
        row.spellIDText:SetText("ID: " .. entry.spellID)
        row.durText:SetText(entry.duration .. "s")

        -- Mode toggle button
        local mode = entry.displayMode or "bar"
        if mode == "buff" then
            row.modeBtn:SetText("Buff")
            row.modeBtn:GetFontString():SetTextColor(0.2, 1.0, 0.2)
        else
            row.modeBtn:SetText("Bar")
            row.modeBtn:GetFontString():SetTextColor(1.0, 1.0, 1.0)
        end
        row.modeBtn:SetScript("OnClick", function()
            local newMode = (entry.displayMode == "buff") and "bar" or "buff"
            ns:SetBuffDisplayMode(entry.spellID, newMode)
            ns:RefreshConfigList()
        end)

        row.removeBtn:SetScript("OnClick", function()
            ns:RemoveTrackedBuff(entry.spellID)
            ns:RefreshConfigList()
        end)

        -- Dim row if disabled
        local alpha = (entry.enabled ~= false) and 1.0 or 0.4
        row.icon:SetAlpha(alpha)
        row.label:SetAlpha(alpha)
        row.spellIDText:SetAlpha(alpha)
        row.durText:SetAlpha(alpha)
        row.modeBtn:SetAlpha(alpha)

        row:Show()
    end

    -- Update scroll content height
    scrollContent:SetHeight(math.max(1, #sorted * ROW_HEIGHT))
end

function ns:ToggleConfigUI()
    if not configFrame then
        configFrame = CreateConfigFrame()
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
        ns:RefreshConfigList()
    end
end
