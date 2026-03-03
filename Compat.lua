------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Compat.lua – WoW version detection and API compatibility layer
--
-- This file MUST be loaded before all other addon files.
-- It detects the WoW version and provides unified API wrappers
-- so the rest of the addon does not need version checks.
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- Version detection
------------------------------------------------------------------------

local _, _, _, tocVersion = GetBuildInfo()

EDM.tocVersion = tocVersion
EDM.isRetail   = (tocVersion >= 100000)                         -- 10.0+
EDM.isMoP      = (tocVersion >= 50000 and tocVersion < 60000)   -- 5.x
EDM.isCata     = (tocVersion >= 40000 and tocVersion < 50000)   -- 4.x
EDM.isWrath    = (tocVersion >= 30000 and tocVersion < 40000)   -- 3.x
EDM.isTBC      = (tocVersion >= 20000 and tocVersion < 30000)   -- 2.x
EDM.isVanilla  = (tocVersion < 20000)                           -- 1.x
EDM.isClassic  = not EDM.isRetail

------------------------------------------------------------------------
-- Frame compatibility
------------------------------------------------------------------------

-- BackdropTemplate (required on all modern clients since 9.0 engine)
EDM.backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

--- Create a frame with BackdropTemplate support.
-- Works on all WoW versions – uses BackdropTemplate mixin when available,
-- falls back to native SetBackdrop on legacy clients.
function EDM:CreateBackdropFrame(frameType, name, parent, extraTemplate)
    local templates = {}
    if self.backdropTemplate then
        templates[#templates + 1] = self.backdropTemplate
    end
    if extraTemplate then
        templates[#templates + 1] = extraTemplate
    end
    local tplStr = #templates > 0 and table.concat(templates, ",") or nil
    return CreateFrame(frameType, name, parent, tplStr)
end

--- SetResizeBounds compat (SetMinResize/SetMaxResize before 10.0)
function EDM:SetFrameResizeBounds(frame, minW, minH, maxW, maxH)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then
            frame:SetMinResize(minW, minH)
        end
        if frame.SetMaxResize and maxW and maxH then
            frame:SetMaxResize(maxW, maxH)
        end
    end
end

------------------------------------------------------------------------
-- Menu compatibility
------------------------------------------------------------------------

-- MenuUtil.CreateContextMenu is available since retail 11.0
EDM.hasMenuUtil = (MenuUtil ~= nil and MenuUtil.CreateContextMenu ~= nil)

------------------------------------------------------------------------
-- Group API compatibility
------------------------------------------------------------------------

-- All current Classic clients have GetNumGroupMembers, but provide
-- a fallback for very old builds just in case.
if not GetNumGroupMembers then
    GetNumGroupMembers = function()
        if IsInRaid() then
            return GetNumRaidMembers()
        end
        return (GetNumPartyMembers() or 0) + 1
    end
end

------------------------------------------------------------------------
-- Combat log compatibility
------------------------------------------------------------------------

-- CombatLogGetCurrentEventInfo was introduced in 8.0. All current
-- Classic clients (1.15.x, 2.5.x, 5.x …) run on the modern engine
-- and have this function.
EDM.hasCLEUInfo = (CombatLogGetCurrentEventInfo ~= nil)

------------------------------------------------------------------------
-- Class color compatibility
------------------------------------------------------------------------

--- Safely retrieve class color for a given class token.
-- Prefers C_ClassColor (8.1.5+) > CUSTOM_CLASS_COLORS > RAID_CLASS_COLORS > fallback table.
function EDM:GetClassColor(classToken)
    if C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(classToken)
        if color then
            return color.r, color.g, color.b
        end
    end

    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    if colors and colors[classToken] then
        local c = colors[classToken]
        return c.r, c.g, c.b
    end

    local c = self.CLASS_COLORS[classToken] or self.CLASS_COLORS.UNKNOWN
    return c.r, c.g, c.b
end

------------------------------------------------------------------------
-- Library helpers
------------------------------------------------------------------------

--- Safely get a library via LibStub. Returns nil if not available.
function EDM:GetLib(name)
    if LibStub then
        return LibStub(name, true)  -- true = silentFail
    end
    return nil
end
