local addonName, ns = ...

local BAR_WIDTH = 200
local BAR_HEIGHT = 20
local BAR_SPACING = 2
local ICON_SIZE = BAR_HEIGHT
local UPDATE_INTERVAL = 0.05
local ANCHOR_SIZE = 8

local barPool = {}
local activeBars = {}
local timeSinceUpdate = 0

local function FormatTime(remaining)
    if remaining >= 60 then
        local m = math.floor(remaining / 60)
        local s = math.floor(remaining % 60)
        return string.format("%d:%02d", m, s)
    else
        return string.format("%.1f", remaining)
    end
end

local function GetBarColor(fraction)
    if fraction > 0.3 then
        return 0.2, 0.6, 1.0 -- blue
    elseif fraction > 0.1 then
        return 1.0, 0.8, 0.0 -- yellow
    else
        return 1.0, 0.2, 0.2 -- red
    end
end

local function CreateTimerBar(parent)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    bar:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bar:SetBackdropColor(0, 0, 0, 0.7)
    bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- Progress fill
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.fill:SetPoint("TOPLEFT", 2, -2)
    bar.fill:SetHeight(BAR_HEIGHT - 4)

    -- Icon
    bar.icon = bar:CreateTexture(nil, "OVERLAY")
    bar.icon:SetSize(ICON_SIZE, ICON_SIZE)
    bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
    bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Label text
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.label:SetPoint("LEFT", bar, "LEFT", 4, 0)
    bar.label:SetJustifyH("LEFT")
    bar.label:SetWidth(BAR_WIDTH - 50)

    -- Time text
    bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bar.time:SetJustifyH("RIGHT")

    bar:Hide()
    return bar
end

local function GetBar(index)
    if not barPool[index] then
        barPool[index] = CreateTimerBar(ns.anchorFrame)
    end
    return barPool[index]
end

function ns:InitDisplay()
    -- Anchor frame (draggable)
    local anchor = CreateFrame("Frame", "TerribleBuffTrackerAnchor", UIParent)
    anchor:SetSize(ICON_SIZE + BAR_WIDTH + 2, ANCHOR_SIZE)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:SetClampedToScreen(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.displayPoint = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Restore saved position
    if ns.db.displayPoint then
        local p = ns.db.displayPoint
        anchor:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end

    anchor:Show()
    ns.anchorFrame = anchor

    -- OnUpdate for timer ticking
    anchor:SetScript("OnUpdate", function(self, elapsed)
        timeSinceUpdate = timeSinceUpdate + elapsed
        if timeSinceUpdate < UPDATE_INTERVAL then return end
        timeSinceUpdate = 0
        ns:UpdateDisplay()
    end)
end

function ns:UpdateDisplay()
    local timers = ns:GetActiveTimers()
    local now = GetTime()

    -- Update/create bars for active timers
    for i, timer in ipairs(timers) do
        local bar = GetBar(i)
        local remaining = timer.expiresAt - now
        local fraction = remaining / timer.duration

        -- Position below anchor
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", ns.anchorFrame, "BOTTOMLEFT", ICON_SIZE + 2, -((i - 1) * (BAR_HEIGHT + BAR_SPACING)))

        -- Icon
        bar.icon:SetTexture(timer.icon)

        -- Label
        bar.label:SetText(timer.label)

        -- Fill width
        local fillWidth = math.max(1, (BAR_WIDTH - 4) * fraction)
        bar.fill:SetWidth(fillWidth)
        local r, g, b = GetBarColor(fraction)
        bar.fill:SetVertexColor(r, g, b, 0.8)

        -- Time text
        bar.time:SetText(FormatTime(remaining))

        bar:Show()
    end

    -- Hide unused bars
    for i = #timers + 1, #barPool do
        barPool[i]:Hide()
    end

    activeBars = timers
end
