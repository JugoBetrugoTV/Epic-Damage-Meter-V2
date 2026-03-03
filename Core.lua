------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Core.lua – Addon namespace, library integration, and initialization
------------------------------------------------------------------------

local ADDON_NAME, EDM = ...

-- Make the namespace globally accessible for debugging
EpicDamageMeter = EDM

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

EDM.VERSION    = "2.0.0"
EDM.ADDON_NAME = ADDON_NAME

-- View modes
EDM.VIEW_DAMAGE   = 1
EDM.VIEW_DPS      = 2
EDM.VIEW_HEALING  = 3
EDM.VIEW_HPS      = 4

EDM.VIEW_LABELS = {
    [EDM.VIEW_DAMAGE]  = "Schaden",
    [EDM.VIEW_DPS]     = "DPS",
    [EDM.VIEW_HEALING] = "Heilung",
    [EDM.VIEW_HPS]     = "HPS",
}

-- Affiliation flags for combat log filtering
EDM.AFFILIATION_MINE  = COMBATLOG_OBJECT_AFFILIATION_MINE  or 0x00000001
EDM.AFFILIATION_PARTY = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002
EDM.AFFILIATION_RAID  = COMBATLOG_OBJECT_AFFILIATION_RAID  or 0x00000004
EDM.AFFILIATION_MASK  = bit.bor(EDM.AFFILIATION_MINE, EDM.AFFILIATION_PARTY, EDM.AFFILIATION_RAID)

-- Type flags
EDM.TYPE_PLAYER   = COMBATLOG_OBJECT_TYPE_PLAYER   or 0x00000400
EDM.TYPE_PET      = COMBATLOG_OBJECT_TYPE_PET      or 0x00001000
EDM.TYPE_GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000

-- Class colors: Populated by version module (Modules/Retail.lua, MoP.lua, etc.)
-- with only the classes available on that platform.
-- Minimal fallback so GetClassColor never errors.
EDM.CLASS_COLORS = {
    UNKNOWN = { r = 0.60, g = 0.60, b = 0.60 },
}

------------------------------------------------------------------------
-- Library references (populated on ADDON_LOADED)
------------------------------------------------------------------------

EDM.AceDB      = nil   -- AceDB-3.0
EDM.LSM        = nil   -- LibSharedMedia-3.0
EDM.LDB        = nil   -- LibDataBroker-1.1
EDM.LDBIcon    = nil   -- LibDBIcon-1.0

------------------------------------------------------------------------
-- Default saved-variable settings
------------------------------------------------------------------------

EDM.DEFAULTS = {
    profile = {
        point           = "RIGHT",
        relPoint        = "RIGHT",
        x               = -20,
        y               = 0,
        width           = 260,
        height          = 300,
        numBars         = 15,
        barHeight       = 18,
        barSpacing      = 1,
        barTexture      = "Interface\\TargetingFrame\\UI-StatusBar",
        barTextureName  = "Blizzard",
        font            = "Fonts\\FRIZQT__.TTF",
        fontName        = "Friz Quadrata TT",
        fontSize        = 10,
        locked          = false,
        shown           = true,
        currentView     = 1,     -- VIEW_DAMAGE
        showRank        = true,
        mergePets       = true,
        minimap         = { hide = false },
        classColors     = true,
    },
}

-- Flat defaults fallback (when AceDB is not available)
EDM.DEFAULTS_FLAT = {
    point           = "RIGHT",
    relPoint        = "RIGHT",
    x               = -20,
    y               = 0,
    width           = 260,
    height          = 300,
    numBars         = 15,
    barHeight       = 18,
    barSpacing      = 1,
    barTexture      = "Interface\\TargetingFrame\\UI-StatusBar",
    barTextureName  = "Blizzard",
    font            = "Fonts\\FRIZQT__.TTF",
    fontName        = "Friz Quadrata TT",
    fontSize        = 10,
    locked          = false,
    shown           = true,
    currentView     = 1,
    showRank        = true,
    mergePets       = true,
    minimap         = { hide = false },
    classColors     = true,
}

------------------------------------------------------------------------
-- Utility functions
------------------------------------------------------------------------

-- GetClassColor is defined in Compat.lua

function EDM:FormatNumber(num)
    if num >= 1e9 then
        return ("%.2fB"):format(num / 1e9)
    elseif num >= 1e6 then
        return ("%.2fM"):format(num / 1e6)
    elseif num >= 1e3 then
        return ("%.1fK"):format(num / 1e3)
    end
    return tostring(math.floor(num))
end

function EDM:IsFriendlyPlayer(flags)
    if not flags then return false end
    if bit.band(flags, self.AFFILIATION_MASK) == 0 then return false end
    if bit.band(flags, self.TYPE_PLAYER) ~= 0 then return true end
    if bit.band(flags, self.TYPE_PET) ~= 0 then return true end
    if bit.band(flags, self.TYPE_GUARDIAN) ~= 0 then return true end
    return false
end

function EDM:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffEpic Damage Meter|r: " .. tostring(msg))
end

------------------------------------------------------------------------
-- Library initialization
------------------------------------------------------------------------

local function InitLibraries()
    -- AceDB-3.0 for profile-based saved variables
    EDM.AceDB = EDM:GetLib("AceDB-3.0")

    -- LibSharedMedia-3.0 for bar textures and fonts
    EDM.LSM = EDM:GetLib("LibSharedMedia-3.0")
    if EDM.LSM then
        EDM.LSM:Register("statusbar", "EDM Default", "Interface\\TargetingFrame\\UI-StatusBar")
    end

    -- LibDataBroker-1.1 for data display
    EDM.LDB = EDM:GetLib("LibDataBroker-1.1")

    -- LibDBIcon-1.0 for minimap button
    EDM.LDBIcon = EDM:GetLib("LibDBIcon-1.0")
end

local function InitSavedVariables()
    if EDM.AceDB then
        -- AceDB: full profile support (per-spec, per-char, defaults, etc.)
        EDM.acedb = EDM.AceDB:New("EpicDamageMeterDB", EDM.DEFAULTS, true)
        EDM.db = EDM.acedb.profile
    else
        -- Fallback: simple global table
        if not EpicDamageMeterDB then
            EpicDamageMeterDB = {}
        end
        for k, v in pairs(EDM.DEFAULTS_FLAT) do
            if EpicDamageMeterDB[k] == nil then
                if type(v) == "table" then
                    EpicDamageMeterDB[k] = {}
                    for kk, vv in pairs(v) do
                        EpicDamageMeterDB[k][kk] = vv
                    end
                else
                    EpicDamageMeterDB[k] = v
                end
            end
        end
        EDM.db = EpicDamageMeterDB
    end
end

local function InitMinimapButton()
    if not EDM.LDB or not EDM.LDBIcon then return end

    local dataObj = EDM.LDB:NewDataObject("EpicDamageMeter", {
        type  = "launcher",
        icon  = "Interface\\Icons\\Ability_Warrior_Bladestorm",
        label = "Epic Damage Meter",
        OnClick = function(_, button)
            if button == "LeftButton" then
                EDM:ToggleWindow()
            elseif button == "RightButton" then
                EDM:ResetData()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Epic Damage Meter V2")
            tooltip:AddLine("|cff00ff00Linksklick|r: Fenster ein/ausblenden")
            tooltip:AddLine("|cffff0000Rechtsklick|r: Daten zuruecksetzen")
        end,
    })

    EDM.LDBIcon:Register("EpicDamageMeter", dataObj, EDM.db.minimap)
end

------------------------------------------------------------------------
-- Initialization
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            InitLibraries()
            InitSavedVariables()
            eventFrame:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        EDM:OnPlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        EDM:OnPlayerLogout()
    end
end)

function EDM:OnPlayerLogin()
    self:InitDataStore()
    self:RegisterCombatLog()      -- Before CreateDisplay: avoid taint from UI code
    self:CreateDisplay()
    self:RegisterSlashCommands()
    self:InitConfig()
    InitMinimapButton()
    self:InitConfig()             -- Last: AceConfig may taint the execution context

    local versionInfo
    if self.isRetail then
        versionInfo = "Retail"
    elseif self.isMoP then
        versionInfo = "MoP Classic"
    elseif self.isTBC then
        versionInfo = "TBC Anniversary"
    elseif self.isClassic then
        versionInfo = "Classic"
    else
        versionInfo = "Unbekannt"
    end
    self:Print("v" .. self.VERSION .. " (" .. versionInfo .. ") geladen. /edm fuer Hilfe.")
end

function EDM:OnPlayerLogout()
    -- Save window position
    if self.mainFrame then
        local point, _, relPoint, x, y = self.mainFrame:GetPoint()
        self.db.point    = point
        self.db.relPoint = relPoint
        self.db.x        = x
        self.db.y        = y
        self.db.width    = self.mainFrame:GetWidth()
        self.db.height   = self.mainFrame:GetHeight()
    end
end
