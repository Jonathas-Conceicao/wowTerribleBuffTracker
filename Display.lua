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
        barPool[index] = CreateTimerBar(ns.anchorFrame or UIParent)
    end
    return barPool[index]
end

-- Find the bottommost active bar in BuffBarCooldownViewer
local function GetCDMBottomBar(viewer)
    local bottomBar = nil
    local bottomY = math.huge

    for frame in viewer.itemFramePool:EnumerateActive() do
        if frame:IsShown() then
            local _, _, _, _, y = frame:GetPoint()
            -- GetPoint y is relative; use GetBottom() for screen coords
            local screenBottom = frame:GetBottom()
            if screenBottom and screenBottom < bottomY then
                bottomY = screenBottom
                bottomBar = frame
            end
        end
    end

    return bottomBar, bottomY
end

-- Get the width of CDM bars by checking an active bar frame
local function GetCDMBarWidth(viewer)
    for frame in viewer.itemFramePool:EnumerateActive() do
        if frame:IsShown() then
            return frame:GetWidth()
        end
    end
    return nil
end

function ns:RepositionBars()
    if not ns.cdmMode or not ns.cdmViewer then return end

    local viewer = ns.cdmViewer
    local bottomBar = GetCDMBottomBar(viewer)

    -- Match bar width to CDM bars if possible
    local cdmWidth = GetCDMBarWidth(viewer)
    if cdmWidth then
        BAR_WIDTH = cdmWidth
    end

    -- Determine anchor point for our first bar
    local anchorFrame, anchorPoint, yOffset
    if bottomBar then
        anchorFrame = bottomBar
        anchorPoint = "BOTTOMLEFT"
        yOffset = -(BAR_SPACING)
    else
        anchorFrame = viewer
        anchorPoint = "BOTTOMLEFT"
        yOffset = -(BAR_SPACING)
    end

    -- Reposition all active TBT bars
    local timers = ns:GetActiveTimers()
    for i, timer in ipairs(timers) do
        local bar = GetBar(i)
        bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
        bar.label:SetWidth(BAR_WIDTH - 50)
        bar:ClearAllPoints()

        if i == 1 then
            bar:SetPoint("TOPLEFT", anchorFrame, anchorPoint, ICON_SIZE + 2, yOffset)
        else
            local prevBar = GetBar(i - 1)
            bar:SetPoint("TOPLEFT", prevBar, "BOTTOMLEFT", 0, -(BAR_SPACING))
        end
    end
end

function ns:InitDisplay()
    -- Check for CDM viewer
    local viewer = BuffBarCooldownViewer
    if viewer and viewer.itemFramePool then
        ns.cdmMode = true
        ns.cdmViewer = viewer

        -- Hook layout methods to reposition our bars when CDM relayouts
        hooksecurefunc(viewer, "Layout", function()
            ns:RepositionBars()
        end)
        if viewer.UpdateLayout then
            hooksecurefunc(viewer, "UpdateLayout", function()
                ns:RepositionBars()
            end)
        end
        if viewer.RefreshLayout then
            hooksecurefunc(viewer, "RefreshLayout", function()
                ns:RepositionBars()
            end)
        end

        -- Parent bars to UIParent (same as Blizzard), no draggable anchor needed
        -- Create a hidden update driver frame
        local updateFrame = CreateFrame("Frame", nil, UIParent)
        updateFrame:SetScript("OnUpdate", function(self, elapsed)
            timeSinceUpdate = timeSinceUpdate + elapsed
            if timeSinceUpdate < UPDATE_INTERVAL then return end
            timeSinceUpdate = 0
            ns:UpdateDisplay()
        end)

        -- No anchor frame in CDM mode — bars position relative to CDM
        ns.anchorFrame = nil

        print("|cff00ccffTerribleBuffTracker|r: Attached to Cooldown Manager.")
    else
        -- Standalone mode: draggable anchor (original behavior)
        ns.cdmMode = false
        ns:InitStandaloneDisplay()
    end
end

function ns:InitStandaloneDisplay()
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

    if ns.cdmMode then
        -- CDM mode: position relative to CDM viewer
        local viewer = ns.cdmViewer
        local bottomBar = GetCDMBottomBar(viewer)
        local cdmWidth = GetCDMBarWidth(viewer)
        if cdmWidth then
            BAR_WIDTH = cdmWidth
        end

        for i, timer in ipairs(timers) do
            local bar = GetBar(i)
            local remaining = timer.expiresAt - now
            local fraction = remaining / timer.duration

            bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
            bar.label:SetWidth(BAR_WIDTH - 50)
            bar:ClearAllPoints()

            if i == 1 then
                local anchorFrame = bottomBar or viewer
                bar:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", ICON_SIZE + 2, -(BAR_SPACING))
            else
                local prevBar = GetBar(i - 1)
                bar:SetPoint("TOPLEFT", prevBar, "BOTTOMLEFT", 0, -(BAR_SPACING))
            end

            bar.icon:SetTexture(timer.icon)
            bar.label:SetText(timer.label)

            local fillWidth = math.max(1, (BAR_WIDTH - 4) * fraction)
            bar.fill:SetWidth(fillWidth)
            local r, g, b = GetBarColor(fraction)
            bar.fill:SetVertexColor(r, g, b, 0.8)

            bar.time:SetText(FormatTime(remaining))
            bar:Show()
        end
    else
        -- Standalone mode: position below anchor
        for i, timer in ipairs(timers) do
            local bar = GetBar(i)
            local remaining = timer.expiresAt - now
            local fraction = remaining / timer.duration

            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", ns.anchorFrame, "BOTTOMLEFT", ICON_SIZE + 2, -((i - 1) * (BAR_HEIGHT + BAR_SPACING)))

            bar.icon:SetTexture(timer.icon)
            bar.label:SetText(timer.label)

            local fillWidth = math.max(1, (BAR_WIDTH - 4) * fraction)
            bar.fill:SetWidth(fillWidth)
            local r, g, b = GetBarColor(fraction)
            bar.fill:SetVertexColor(r, g, b, 0.8)

            bar.time:SetText(FormatTime(remaining))
            bar:Show()
        end
    end

    -- Hide unused bars
    for i = #timers + 1, #barPool do
        barPool[i]:Hide()
    end

    activeBars = timers
end
