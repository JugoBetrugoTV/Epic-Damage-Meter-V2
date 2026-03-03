------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Display.lua – Main UI frame and damage/healing bars
------------------------------------------------------------------------

local _, EDM = ...

local UPDATE_INTERVAL = 0.5   -- refresh every 0.5s during combat
local timeSinceLastUpdate = 0

------------------------------------------------------------------------
-- Main frame creation
------------------------------------------------------------------------

function EDM:CreateDisplay()
    if self.mainFrame then return end

    local db = self.db

    ----------------------------------------------------------------
    -- Main container (uses Compat.lua for BackdropTemplate)
    ----------------------------------------------------------------
    local frame = self:CreateBackdropFrame("Frame", "EpicDamageMeterFrame", UIParent)
    frame:SetSize(db.width, db.height)
    frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true,
            tileSize = 16,
            edgeSize = 16,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
        frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end
    frame:SetClampedToScreen(true)
    frame:SetMovable(not db.locked)
    frame:SetResizable(true)
    self:SetFrameResizeBounds(frame, 180, 80, 500, 800)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(5)

    if db.shown then
        frame:Show()
    else
        frame:Hide()
    end

    self.mainFrame = frame

    ----------------------------------------------------------------
    -- Title bar
    ----------------------------------------------------------------
    local titleBar = self:CreateBackdropFrame("Frame", nil, frame)
    titleBar:SetHeight(20)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    if titleBar.SetBackdrop then
        titleBar:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile   = true,
            tileSize = 16,
        })
        titleBar:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    end

    -- Make title bar the drag handle
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        if not db.locked then
            frame:StartMoving()
        end
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        db.point    = point
        db.relPoint = relPoint
        db.x        = x
        db.y        = y
    end)

    self.titleBar = titleBar

    ----------------------------------------------------------------
    -- Title text
    ----------------------------------------------------------------
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 4, 0)
    titleText:SetText("Epic Damage Meter")
    titleText:SetTextColor(0.9, 0.8, 0.0)
    self.titleText = titleText

    ----------------------------------------------------------------
    -- Close button
    ----------------------------------------------------------------
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButtonNoScripts")
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -2, 0)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
        db.shown = false
    end)

    ----------------------------------------------------------------
    -- View mode buttons
    ----------------------------------------------------------------
    local viewBtnWidth = 55
    local viewBtnHeight = 16

    self.viewButtons = {}
    local views = {
        { mode = EDM.VIEW_DAMAGE,  label = "Schaden" },
        { mode = EDM.VIEW_DPS,     label = "DPS" },
        { mode = EDM.VIEW_HEALING, label = "Heilung" },
        { mode = EDM.VIEW_HPS,     label = "HPS" },
    }

    local viewBar = CreateFrame("Frame", nil, frame)
    viewBar:SetHeight(viewBtnHeight)
    viewBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -1)
    viewBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -1)

    for i, v in ipairs(views) do
        local btn = self:CreateBackdropFrame("Button", nil, viewBar)
        btn:SetSize(viewBtnWidth, viewBtnHeight)
        if i == 1 then
            btn:SetPoint("LEFT", viewBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", self.viewButtons[i - 1], "RIGHT", 1, 0)
        end

        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                tile   = true, tileSize = 16,
            })
        end

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(v.label)
        text:SetTextColor(0.8, 0.8, 0.8)
        btn.text = text

        btn:SetScript("OnClick", function()
            db.currentView = v.mode
            EDM:UpdateViewButtons()
            EDM:UpdateDisplay()
        end)

        btn:SetScript("OnEnter", function(self)
            if self.SetBackdropColor then
                self:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.SetBackdropColor then
                if db.currentView == v.mode then
                    self:SetBackdropColor(0.2, 0.2, 0.6, 0.9)
                else
                    self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
                end
            end
        end)

        btn.mode = v.mode
        self.viewButtons[i] = btn
    end

    self:UpdateViewButtons()

    ----------------------------------------------------------------
    -- Scrollable bar area
    ----------------------------------------------------------------
    local barArea = CreateFrame("Frame", nil, frame)
    barArea:SetPoint("TOPLEFT", viewBar, "BOTTOMLEFT", 0, -2)
    barArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 18)
    barArea:SetClipsChildren(true)
    self.barArea = barArea

    ----------------------------------------------------------------
    -- Create bar pool
    ----------------------------------------------------------------
    self.bars = {}
    self:CreateBars()

    ----------------------------------------------------------------
    -- Resize grip
    ----------------------------------------------------------------
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeGrip:SetScript("OnMouseDown", function()
        if not db.locked then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        db.width  = frame:GetWidth()
        db.height = frame:GetHeight()
        EDM:CreateBars()
        EDM:UpdateDisplay()
    end)

    ----------------------------------------------------------------
    -- Bottom status bar
    ----------------------------------------------------------------
    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 4)
    statusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 4)
    statusText:SetJustifyH("LEFT")
    statusText:SetTextColor(0.6, 0.6, 0.6)
    statusText:SetText("")
    self.statusText = statusText

    ----------------------------------------------------------------
    -- Right-click menu
    ----------------------------------------------------------------
    self:CreateContextMenu()

    ----------------------------------------------------------------
    -- Update ticker
    ----------------------------------------------------------------
    frame:SetScript("OnUpdate", function(_, elapsed)
        timeSinceLastUpdate = timeSinceLastUpdate + elapsed
        if timeSinceLastUpdate >= UPDATE_INTERVAL then
            timeSinceLastUpdate = 0
            if EDM.displayDirty or EDM.inCombat then
                EDM.displayDirty = false
                EDM:UpdateDisplay()
            end
        end
    end)

    -- Scroll support
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        if not self.scrollOffset then self.scrollOffset = 0 end
        self.scrollOffset = math.max(0, self.scrollOffset - delta)
        self:UpdateDisplay()
    end)
end

------------------------------------------------------------------------
-- View button highlighting
------------------------------------------------------------------------

function EDM:UpdateViewButtons()
    for _, btn in ipairs(self.viewButtons) do
        if not btn.SetBackdropColor then break end
        if self.db.currentView == btn.mode then
            btn:SetBackdropColor(0.2, 0.2, 0.6, 0.9)
            btn.text:SetTextColor(1, 1, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            btn.text:SetTextColor(0.6, 0.6, 0.6)
        end
    end
end

------------------------------------------------------------------------
-- Bar creation
------------------------------------------------------------------------

function EDM:CreateBars()
    local db = self.db
    local barArea = self.barArea
    if not barArea then return end

    local areaHeight = barArea:GetHeight()
    local numBars = math.floor(areaHeight / (db.barHeight + db.barSpacing))
    numBars = math.max(numBars, 1)

    -- Reuse or create bars
    for i = 1, numBars do
        if not self.bars[i] then
            self.bars[i] = self:CreateSingleBar(barArea, i)
        end
        local bar = self.bars[i]
        bar:SetHeight(db.barHeight)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, -((i - 1) * (db.barHeight + db.barSpacing)))
        bar:SetPoint("RIGHT", barArea, "RIGHT", 0, 0)
        bar:Show()
    end

    -- Hide extra bars
    for i = numBars + 1, #self.bars do
        self.bars[i]:Hide()
    end

    self.numVisibleBars = numBars
end

function EDM:CreateSingleBar(parent, index)
    local db = self.db

    -- StatusBar with optional BackdropTemplate
    local bar = self:CreateBackdropFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(db.barTexture)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(db.barTexture)
    bg:SetAllPoints()
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)
    bar.bg = bg

    -- Rank / Name text (left side)
    local leftText = bar:CreateFontString(nil, "OVERLAY")
    leftText:SetFont(db.font, db.fontSize, "OUTLINE")
    leftText:SetPoint("LEFT", bar, "LEFT", 3, 0)
    leftText:SetJustifyH("LEFT")
    bar.leftText = leftText

    -- Value text (right side)
    local rightText = bar:CreateFontString(nil, "OVERLAY")
    rightText:SetFont(db.font, db.fontSize, "OUTLINE")
    rightText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    rightText:SetJustifyH("RIGHT")
    bar.rightText = rightText

    -- Tooltip on hover
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if self.playerData then
            EDM:ShowBarTooltip(self)
        end
    end)
    bar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return bar
end

------------------------------------------------------------------------
-- Display update
------------------------------------------------------------------------

function EDM:UpdateDisplay()
    if not self.mainFrame or not self.mainFrame:IsShown() then return end
    if not self.bars or not self.numVisibleBars then return end

    local segment = self:GetActiveSegment()
    local viewMode = self.db.currentView
    local data, total = self:GetSortedData(segment, viewMode)

    local scrollOffset = self.scrollOffset or 0
    -- Clamp scroll offset
    if scrollOffset > math.max(0, #data - self.numVisibleBars) then
        scrollOffset = math.max(0, #data - self.numVisibleBars)
        self.scrollOffset = scrollOffset
    end

    local maxValue = (data[1] and data[1].value) or 0

    for i = 1, self.numVisibleBars do
        local bar = self.bars[i]
        if not bar then break end

        local dataIdx = i + scrollOffset
        local entry = data[dataIdx]

        if entry and entry.value > 0 then
            bar:Show()

            -- Set bar value proportional to top player
            local pct = 0
            if maxValue > 0 then
                pct = (entry.value / maxValue) * 100
            end
            bar:SetValue(pct)

            -- Set class color
            local r, g, b = self:GetClassColor(entry.class)
            bar:SetStatusBarColor(r, g, b, 0.85)

            -- Left text: rank + name
            local leftStr
            if self.db.showRank then
                leftStr = dataIdx .. ". " .. entry.name
            else
                leftStr = entry.name
            end
            bar.leftText:SetText(leftStr)
            bar.leftText:SetTextColor(1, 1, 1)

            -- Right text: value (percentage of total)
            local valueStr = self:FormatNumber(entry.value)
            local pctOfTotal = 0
            if total > 0 then
                pctOfTotal = (entry.value / total) * 100
            end
            bar.rightText:SetText(valueStr .. " (" .. ("%.1f"):format(pctOfTotal) .. "%)")
            bar.rightText:SetTextColor(1, 1, 1)

            -- Store data reference for tooltip
            bar.playerData = entry
        else
            bar:Hide()
        end
    end

    -- Update status text
    local segmentName = segment and segment.name or ""
    local duration = segment and self:GetSegmentDuration(segment) or 0
    local viewLabel = EDM.VIEW_LABELS[viewMode] or ""
    local totalStr = self:FormatNumber(total)
    self.statusText:SetText(segmentName .. " | " .. viewLabel .. ": " .. totalStr .. " | " .. ("%.0f"):format(duration) .. "s")
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------

function EDM:ShowBarTooltip(bar)
    if not bar.playerData then return end

    local entry = bar.playerData
    local segment = self:GetActiveSegment()
    if not segment then return end

    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local r, g, b = self:GetClassColor(entry.class)
    GameTooltip:AddLine(entry.name, r, g, b)

    -- Find the player in the segment data
    local player = segment.players[entry.guid]
    if not player then
        GameTooltip:Show()
        return
    end

    local duration = self:GetSegmentDuration(segment)

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Schaden:", self:FormatNumber(player.damage), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("DPS:", self:FormatNumber(player.damage / duration), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Heilung:", self:FormatNumber(player.healing), 0.2, 1, 0.2, 1, 1, 1)
    GameTooltip:AddDoubleLine("HPS:", self:FormatNumber(player.healing / duration), 0.2, 1, 0.2, 1, 1, 1)

    -- Top abilities
    local abilities = {}
    for spellId, abilityData in pairs(player.abilities) do
        local value = 0
        if self.db.currentView == EDM.VIEW_DAMAGE or self.db.currentView == EDM.VIEW_DPS then
            value = abilityData.damage
        else
            value = abilityData.healing
        end
        if value > 0 then
            table.insert(abilities, {
                name  = abilityData.name,
                value = value,
                hits  = abilityData.hits,
                crits = abilityData.crits,
            })
        end
    end

    table.sort(abilities, function(a, b) return a.value > b.value end)

    if #abilities > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Top Faehigkeiten:", 1, 0.82, 0)

        local totalAbilityValue = 0
        for _, a in ipairs(abilities) do
            totalAbilityValue = totalAbilityValue + a.value
        end

        for i = 1, math.min(8, #abilities) do
            local a = abilities[i]
            local pct = totalAbilityValue > 0 and (a.value / totalAbilityValue * 100) or 0
            local critPct = a.hits > 0 and (a.crits / a.hits * 100) or 0
            GameTooltip:AddDoubleLine(
                ("  %s"):format(a.name),
                ("%s (%.0f%%) | Krit: %.0f%%"):format(self:FormatNumber(a.value), pct, critPct),
                1, 1, 1, 0.8, 0.8, 0.8
            )
        end
    end

    GameTooltip:Show()
end

------------------------------------------------------------------------
-- Live config refresh methods (called from Config.lua setters)
------------------------------------------------------------------------

--- Refresh only the data display (view mode, rank, pets, etc.)
function EDM:RefreshDisplay()
    self:UpdateDisplay()
end

--- Refresh bar appearance (texture, font, height, spacing).
-- Re-applies all visual settings from db to existing bars.
function EDM:RefreshBars()
    if not self.bars then return end
    local db = self.db

    for _, bar in ipairs(self.bars) do
        -- Update statusbar texture
        bar:SetStatusBarTexture(db.barTexture)
        if bar.bg then
            bar.bg:SetTexture(db.barTexture)
        end

        -- Update font
        if bar.leftText then
            bar.leftText:SetFont(db.font, db.fontSize, "OUTLINE")
        end
        if bar.rightText then
            bar.rightText:SetFont(db.font, db.fontSize, "OUTLINE")
        end
    end

    -- Rebuild bar layout (height/spacing may have changed)
    self:CreateBars()
    self:UpdateDisplay()
end

------------------------------------------------------------------------
-- Context menu (right-click)
-- Implementation is provided by the version module:
--   Retail  → Modules/Retail.lua       (MenuUtil)
--   Others  → Modules/DropdownMenu.lua (UIDropDownMenu)
------------------------------------------------------------------------

function EDM:CreateContextMenu()
    if not self.mainFrame then return end

    self.mainFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            EDM:ShowContextMenu()
        end
    end)
end
