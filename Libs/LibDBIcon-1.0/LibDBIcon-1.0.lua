--[[
LibDBIcon-1.0 – Minimap button management for LDB data objects.

Creates lightweight minimap buttons from LibDataBroker-1.1 launcher
objects. Buttons orbit the minimap and their position + visibility
is persisted via a supplied SavedVariables table.

API:
  :Register(name, obj, db)    – create a minimap button
  :Show(name)                 – show button
  :Hide(name)                 – hide button
  :IsRegistered(name)         – check if registered
  :GetMinimapButton(name)     – get the button frame
  :Lock(name)                 – prevent dragging
  :Unlock(name)               – allow dragging

License: Public Domain / MIT
]]

local MAJOR, MINOR = "LibDBIcon-1.0", 6
local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

-- ----------------------------------------------------------------
-- Internal storage
-- ----------------------------------------------------------------

lib.objects       = lib.objects       or {}   -- [name] = LDB dataobj
lib.buttons       = lib.buttons      or {}   -- [name] = minimap button frame
lib.savedVars     = lib.savedVars    or {}   -- [name] = db table ref
lib.locked        = lib.locked       or {}   -- [name] = bool

-- ----------------------------------------------------------------
-- Minimap geometry helpers
-- ----------------------------------------------------------------

local cos, sin, rad = math.cos, math.sin, math.rad

local function getMinimapShape()
    -- Returns the minimap mask shape. Most UIs use a round minimap.
    if GetMinimapShape then
        return GetMinimapShape()
    end
    return "ROUND"
end

local function updatePosition(button, db)
    local angle  = db.minimapPos or 225
    local radian = rad(angle)
    local shape  = getMinimapShape()

    -- Distance from minimap center
    local radius = 80

    local x, y
    if shape == "SQUARE" then
        -- Clamp to square minimap
        x = max(-radius, min(cos(radian) * radius, radius))
        y = max(-radius, min(sin(radian) * radius, radius))
    else
        -- Circle (default)
        x = cos(radian) * radius
        y = sin(radian) * radius
    end

    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ----------------------------------------------------------------
-- Button creation
-- ----------------------------------------------------------------

local function onDragStart(self)
    self.isMoving = true
    self:SetScript("OnUpdate", function(btn)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale  = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale

        local angle = math.deg(math.atan2(cy - my, cx - mx))
        if angle < 0 then angle = angle + 360 end

        local db = lib.savedVars[btn.dataName]
        if db then
            db.minimapPos = angle
            updatePosition(btn, db)
        end
    end)
end

local function onDragStop(self)
    self.isMoving = false
    self:SetScript("OnUpdate", nil)
end

local function onClick(self, button)
    local obj = lib.objects[self.dataName]
    if obj and obj.OnClick then
        obj.OnClick(self, button)
    end
end

local function onEnter(self)
    local obj = lib.objects[self.dataName]
    if obj and obj.OnTooltipShow then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        obj.OnTooltipShow(GameTooltip)
        GameTooltip:Show()
    end
end

local function onLeave(self)
    GameTooltip:Hide()
end

local function createButton(name, obj, db)
    local button = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetSize(32, 32)
    button:SetMovable(true)
    button:RegisterForClicks("anyUp")
    button:RegisterForDrag("LeftButton")

    -- Minimap border overlay
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(54, 54)
    overlay:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
    overlay:SetPoint("TOPLEFT")
    button.overlay = overlay

    -- Icon texture
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture(obj.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetPoint("CENTER")
    button.icon = icon

    -- Highlight
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
    highlight:SetSize(24, 24)
    highlight:SetPoint("CENTER")
    highlight:SetBlendMode("ADD")

    -- Store reference
    button.dataName = name

    -- Event handlers
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", onEnter)
    button:SetScript("OnLeave", onLeave)
    button:SetScript("OnDragStart", onDragStart)
    button:SetScript("OnDragStop", onDragStop)

    -- Position
    if not db.minimapPos then
        db.minimapPos = 225
    end
    updatePosition(button, db)

    -- Visibility
    if db.hide then
        button:Hide()
    else
        button:Show()
    end

    return button
end

-- ----------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------

--- Register a minimap button for a LibDataBroker data object.
-- @param name (string) unique name (usually addon name)
-- @param obj  (table)  LDB data object (from LDB:NewDataObject)
-- @param db   (table)  SavedVariables table with {hide, minimapPos}
function lib:Register(name, obj, db)
    if self.buttons[name] then return end -- already registered

    db = db or {}
    self.objects[name]   = obj
    self.savedVars[name] = db
    self.buttons[name]   = createButton(name, obj, db)
end

--- Show the minimap button.
function lib:Show(name)
    local btn = self.buttons[name]
    if btn then
        btn:Show()
        local db = self.savedVars[name]
        if db then db.hide = false end
    end
end

--- Hide the minimap button.
function lib:Hide(name)
    local btn = self.buttons[name]
    if btn then
        btn:Hide()
        local db = self.savedVars[name]
        if db then db.hide = true end
    end
end

--- Check if a button is registered.
function lib:IsRegistered(name)
    return self.buttons[name] ~= nil
end

--- Get the minimap button frame.
function lib:GetMinimapButton(name)
    return self.buttons[name]
end

--- Prevent a button from being dragged.
function lib:Lock(name)
    self.locked[name] = true
    local btn = self.buttons[name]
    if btn then
        btn:SetScript("OnDragStart", nil)
        btn:SetScript("OnDragStop", nil)
    end
end

--- Allow a button to be dragged.
function lib:Unlock(name)
    self.locked[name] = nil
    local btn = self.buttons[name]
    if btn then
        btn:SetScript("OnDragStart", onDragStart)
        btn:SetScript("OnDragStop", onDragStop)
    end
end

--- Refresh the icon texture from the data object.
function lib:Refresh(name, db)
    local btn = self.buttons[name]
    local obj = self.objects[name]
    if btn and obj then
        btn.icon:SetTexture(obj.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    if btn and db then
        self.savedVars[name] = db
        updatePosition(btn, db)
        if db.hide then
            btn:Hide()
        else
            btn:Show()
        end
    end
end
