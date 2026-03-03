------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Core.lua – Addon namespace, utilities, and initialization
------------------------------------------------------------------------

local ADDON_NAME, EDM = ...

-- Make the namespace globally accessible for debugging
EpicDamageMeter = EDM

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------

EDM.VERSION = "2.0.0"
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

-- Class colors fallback (in case RAID_CLASS_COLORS is not loaded yet)
EDM.CLASS_COLORS = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
    MONK        = { r = 0.00, g = 1.00, b = 0.60 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
    UNKNOWN     = { r = 0.60, g = 0.60, b = 0.60 },
}

------------------------------------------------------------------------
-- Default saved‑variable settings
------------------------------------------------------------------------

EDM.DEFAULTS = {
    point         = "RIGHT",
    relPoint      = "RIGHT",
    x             = -20,
    y             = 0,
    width         = 260,
    height        = 300,
    numBars       = 15,
    barHeight     = 18,
    barSpacing    = 1,
    barTexture    = "Interface\\TargetingFrame\\UI-StatusBar",
    font          = "Fonts\\FRIZQT__.TTF",
    fontSize      = 10,
    locked        = false,
    shown         = true,
    currentView   = 1,     -- VIEW_DAMAGE
    showRank      = true,
    mergePets     = true,
    minimap       = true,
    classColors   = true,
}

------------------------------------------------------------------------
-- Utility functions
------------------------------------------------------------------------

function EDM:GetClassColor(class)
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    local c = self.CLASS_COLORS[class] or self.CLASS_COLORS.UNKNOWN
    return c.r, c.g, c.b
end

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
-- Initialization
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            EDM:OnAddonLoaded()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        EDM:OnPlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        EDM:OnPlayerLogout()
    end
end)

function EDM:OnAddonLoaded()
    -- Initialize saved variables
    if not EpicDamageMeterDB then
        EpicDamageMeterDB = {}
    end
    -- Merge defaults into saved variables
    for k, v in pairs(self.DEFAULTS) do
        if EpicDamageMeterDB[k] == nil then
            EpicDamageMeterDB[k] = v
        end
    end
    self.db = EpicDamageMeterDB
end

function EDM:OnPlayerLogin()
    self:InitDataStore()
    self:CreateDisplay()
    self:RegisterCombatLog()
    self:RegisterSlashCommands()
    self:Print("v" .. self.VERSION .. " geladen. /edm für Hilfe.")
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
