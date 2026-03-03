------------------------------------------------------------------------
-- Epic Damage Meter V2
-- CombatLog.lua – Event registration + combat data collection
--
-- Midnight (12.0+):
--   Frame:RegisterEvent() at file scope works for events that exist.
--   COMBAT_LOG_EVENT_UNFILTERED and traditional combat events are gone.
--   → Register DAMAGE_METER_* events at FILE SCOPE (secure context)
--   → C_DamageMeter API for damage/healing data
--
-- Classic / TBC / MoP:
--   → Frame:RegisterEvent() + CLEU parsing (still works)
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- Event registration at FILE SCOPE
--
-- Frame:RegisterEvent() only works from secure (untainted) execution.
-- File scope at addon load time IS secure – just like Core.lua does
-- for ADDON_LOADED / PLAYER_LOGIN.
--
-- We register ALL events here, at file scope, before any library code
-- can taint our execution context.
------------------------------------------------------------------------

local isMidnight = (C_DamageMeter ~= nil)

local eventFrame = CreateFrame("Frame")

if isMidnight then
    -- Midnight 12.0+: DAMAGE_METER_* events + PLAYER_REGEN for combat end
    eventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    eventFrame:RegisterEvent("DAMAGE_METER_RESET")

    -- PLAYER_REGEN_ENABLED may or may not be registerable in Midnight.
    -- pcall so it doesn't break the addon if it's protected.
    pcall(function() eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end)

    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
            local meterType, sessionID = ...
            EDM:OnDamageMeterSessionUpdated(meterType, sessionID)
        elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
            EDM:OnDamageMeterCurrentSessionChanged()
        elseif event == "PLAYER_REGEN_ENABLED" then
            EDM:OnMidnightCombatEnd()
        elseif event == "DAMAGE_METER_RESET" then
            EDM:ResetData()
        end
    end)
else
    -- Classic/TBC/MoP: Traditional events + CLEU
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("UNIT_PET")

    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            EDM:OnCombatLogEvent()
        elseif event == "PLAYER_REGEN_DISABLED" then
            EDM:StartCombat()
        elseif event == "PLAYER_REGEN_ENABLED" then
            C_Timer.After(0.5, function()
                EDM:EndCombat()
            end)
        elseif event == "GROUP_ROSTER_UPDATE" then
            EDM:ScanGroupMembers()
        elseif event == "UNIT_PET" then
            EDM:ScanPets()
        else
            -- Delegate to version module (ENCOUNTER_START, ENCOUNTER_END)
            EDM:HandleVersionEvent(event, ...)
        end
    end)
end

-- RegisterSafeEvent for version modules to add more events (Classic only)
function EDM.RegisterSafeEvent(event, handler)
    if not isMidnight then
        -- Store handler mapping for the OnEvent dispatcher
        -- Version modules call this to add ENCOUNTER_START/END
        local origScript = eventFrame:GetScript("OnEvent")
        eventFrame:RegisterEvent(event)
        local prevHandler = eventFrame:GetScript("OnEvent")
        -- We just rely on HandleVersionEvent in the else-branch above
    end
    -- On Midnight: no-op (all events registered at file scope above)
end

------------------------------------------------------------------------
-- RegisterCombatLog – called from OnPlayerLogin
------------------------------------------------------------------------

function EDM:RegisterCombatLog()
    if not isMidnight then
        -- Version-specific events (encounter tracking on Classic/MoP)
        self:RegisterVersionEvents()

        -- Initial group scan
        self:ScanGroupMembers()
        self:ScanPets()
    end
end

------------------------------------------------------------------------
-- C_DamageMeter integration (Midnight 12.0+ only)
--
-- Secret Values: During combat, sourceGUID / name / totalAmount are
-- secret for addon (tainted) code. classFilename and isLocalPlayer
-- are NeverSecret.
--
-- Strategy:
--   1. During combat: try import on each update (silently skip secrets)
--   2. On combat end (PLAYER_REGEN_ENABLED / CURRENT_SESSION_UPDATED):
--      wait 0.5s for secrets to lift, then reimport via Expired session
--   3. Fallback: re-read by sessionID
------------------------------------------------------------------------

local lastSessionID = nil
local activeSessionID = nil
local pendingReimport = false

function EDM:ImportSessionSources(session, meterType, segment)
    local isDamage  = (meterType == Enum.DamageMeterType.DamageDone)
    local isHealing = (meterType == Enum.DamageMeterType.HealingDone)
    if not isDamage and not isHealing then return 0 end
    if not session or not session.combatSources then return 0 end
    if not segment then return 0 end

    local imported = 0

    for _, source in ipairs(session.combatSources) do
        pcall(function()
            local guid = source.sourceGUID
            local name = source.name or "Unbekannt"
            local class = source.classFilename or "UNKNOWN"

            -- Throws if guid is a secret value
            local _ = ({[guid] = true})[guid]

            local amount = 0
            pcall(function() amount = source.totalAmount + 0 end)

            local player = self:GetOrCreatePlayer(segment, guid, name, class)
            if player then
                if isDamage then
                    player.damage = amount
                elseif isHealing then
                    player.healing = amount
                end
            end
            imported = imported + 1
        end)
    end

    -- Duration
    pcall(function()
        local dur = session.durationSeconds + 0
        if dur > 0 then
            segment.startTime = GetTime() - dur
        end
    end)

    return imported
end

function EDM:TryImportByID(sessionID, meterType, segment)
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType)
    if ok and session then
        return self:ImportSessionSources(session, meterType, segment)
    end
    return 0
end

function EDM:TryImportByType(sessionType, meterType, segment)
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, meterType)
    if ok and session then
        return self:ImportSessionSources(session, meterType, segment)
    end
    return 0
end

function EDM:DoPostCombatImport()
    local segment = self.currentSegment
    if not segment then return end

    local totalImported = 0

    for _, meterType in ipairs({Enum.DamageMeterType.DamageDone, Enum.DamageMeterType.HealingDone}) do
        local n = 0

        -- Try 1: by stored sessionID
        if activeSessionID then
            n = self:TryImportByID(activeSessionID, meterType, segment)
        end

        -- Try 2: expired session (recently completed combat)
        if n == 0 then
            n = self:TryImportByType(Enum.DamageMeterSessionType.Expired, meterType, segment)
        end

        -- Try 3: current session (might still be accessible)
        if n == 0 then
            n = self:TryImportByType(Enum.DamageMeterSessionType.Current, meterType, segment)
        end

        totalImported = totalImported + n
    end

    if totalImported > 0 then
        self.displayDirty = true
    end
end

function EDM:OnDamageMeterSessionUpdated(meterType, sessionID)
    if not C_DamageMeter then return end

    local isDamage  = (meterType == Enum.DamageMeterType.DamageDone)
    local isHealing = (meterType == Enum.DamageMeterType.HealingDone)
    if not isDamage and not isHealing then return end

    -- New session → new combat segment
    if sessionID ~= lastSessionID then
        if self.inCombat then
            self:EndCombat()
        end

        lastSessionID = sessionID
        activeSessionID = sessionID
        self:StartCombat()

        -- Try to get the session name
        pcall(function()
            local sessions = C_DamageMeter.GetAvailableCombatSessions()
            if sessions then
                for _, s in ipairs(sessions) do
                    if s.sessionID == sessionID and s.name and s.name ~= "" then
                        if self.currentSegment then
                            self.currentSegment.name = s.name
                        end
                        break
                    end
                end
            end
        end)
    end

    -- Try to import (silently skips sources with secret fields)
    local segment = self.currentSegment
    if segment then
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType)
        if ok and session then
            self:ImportSessionSources(session, meterType, segment)
        end
    end
    self.displayDirty = true
end

function EDM:OnDamageMeterCurrentSessionChanged()
    if not self.inCombat then return end
    if pendingReimport then return end

    -- Delay reimport slightly to let secrets lift
    pendingReimport = true
    C_Timer.After(0.5, function()
        pendingReimport = false
        EDM:DoPostCombatImport()
        if EDM.inCombat then
            EDM:EndCombat()
        end
        lastSessionID = nil
        activeSessionID = nil
    end)
end

function EDM:OnMidnightCombatEnd()
    -- PLAYER_REGEN_ENABLED fired – combat definitely ended
    if not self.inCombat then return end
    if pendingReimport then return end

    pendingReimport = true
    C_Timer.After(0.5, function()
        pendingReimport = false
        EDM:DoPostCombatImport()
        if EDM.inCombat then
            EDM:EndCombat()
        end
        lastSessionID = nil
        activeSessionID = nil
    end)
end

------------------------------------------------------------------------
-- Group scanning (Classic/TBC/MoP only)
-- On Midnight, C_DamageMeter provides classFilename directly.
------------------------------------------------------------------------

function EDM:ScanGroupMembers()
    if isMidnight then return end
    if not self.classCache then self.classCache = {} end

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumGroupMembers() - 1
    else
        local guid = UnitGUID("player")
        local _, class = UnitClass("player")
        if guid and class then
            self.classCache[guid] = class
        end
        return
    end

    for i = 1, count do
        local unit = prefix .. i
        local guid = UnitGUID(unit)
        local _, class = UnitClass(unit)
        if guid and class then
            self.classCache[guid] = class
        end
    end

    local guid = UnitGUID("player")
    local _, class = UnitClass("player")
    if guid and class then
        self.classCache[guid] = class
    end
end

function EDM:ScanPets()
    if isMidnight then return end
    if not self.petOwners then self.petOwners = {} end

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumGroupMembers() - 1
    else
        prefix, count = nil, 0
    end

    local petGUID = UnitGUID("pet")
    local playerGUID = UnitGUID("player")
    if petGUID and playerGUID then
        self.petOwners[petGUID] = playerGUID
    end

    if prefix then
        for i = 1, count do
            local petUnit = prefix .. "pet" .. i
            local ownerUnit = prefix .. i
            local pGUID = UnitGUID(petUnit)
            local oGUID = UnitGUID(ownerUnit)
            if pGUID and oGUID then
                self.petOwners[pGUID] = oGUID
            end
        end
    end
end

------------------------------------------------------------------------
-- Class lookup (Classic/TBC/MoP CLEU path)
------------------------------------------------------------------------

function EDM:LookupClass(guid)
    if not guid then return "UNKNOWN" end
    if self.classCache and self.classCache[guid] then
        return self.classCache[guid]
    end

    local _, class = GetPlayerInfoByGUID(guid)
    if class and class ~= "" then
        if not self.classCache then self.classCache = {} end
        self.classCache[guid] = class
        return class
    end

    return "UNKNOWN"
end

------------------------------------------------------------------------
-- CLEU parsing (Classic / TBC / MoP only)
------------------------------------------------------------------------

local DAMAGE_EVENTS = {
    SWING_DAMAGE           = true,
    RANGE_DAMAGE           = true,
    SPELL_DAMAGE           = true,
    SPELL_PERIODIC_DAMAGE  = true,
    DAMAGE_SHIELD           = true,
    SPELL_BUILDING_DAMAGE  = true,
}

local HEALING_EVENTS = {
    SPELL_HEAL             = true,
    SPELL_PERIODIC_HEAL    = true,
}

function EDM:OnCombatLogEvent()
    local timestamp, subevent, hideCaster,
          sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

    if not self:IsFriendlyPlayer(sourceFlags) then return end

    if DAMAGE_EVENTS[subevent] then
        local spellId, spellName, spellSchool
        local amount, overkill, school, resisted, blocked, absorbed, critical

        if subevent == "SWING_DAMAGE" then
            spellId   = 0
            spellName = "Nahkampf"
            amount, overkill, school, resisted, blocked, absorbed, critical =
                select(12, CombatLogGetCurrentEventInfo())
        else
            spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical =
                select(12, CombatLogGetCurrentEventInfo())
        end

        if not amount or amount <= 0 then return end

        if not self.inCombat then
            self:StartCombat()
        end

        local resolvedClass = "UNKNOWN"
        local isPetOrGuardian = bit.band(sourceFlags, bit.bor(self.TYPE_PET, self.TYPE_GUARDIAN)) ~= 0
        if isPetOrGuardian then
            local ownerGUID = self:ResolvePetOwner(sourceGUID, sourceName, sourceFlags)
            if ownerGUID then
                self:SetPetOwner(sourceGUID, ownerGUID)
            end
            resolvedClass = self:LookupClass(sourceGUID)
        else
            resolvedClass = self:LookupClass(sourceGUID)
        end

        self:RecordDamage(sourceGUID, sourceName, resolvedClass, spellId, spellName, amount, critical, destName)

    elseif HEALING_EVENTS[subevent] then
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical =
            select(12, CombatLogGetCurrentEventInfo())

        if not amount or amount <= 0 then return end

        local effectiveHealing = amount - (overhealing or 0)
        if effectiveHealing <= 0 then return end

        local resolvedClass = "UNKNOWN"
        local isPetOrGuardian = bit.band(sourceFlags, bit.bor(self.TYPE_PET, self.TYPE_GUARDIAN)) ~= 0
        if isPetOrGuardian then
            local ownerGUID = self:ResolvePetOwner(sourceGUID, sourceName, sourceFlags)
            if ownerGUID then
                self:SetPetOwner(sourceGUID, ownerGUID)
            end
            resolvedClass = self:LookupClass(sourceGUID)
        else
            resolvedClass = self:LookupClass(sourceGUID)
        end

        self:RecordHealing(sourceGUID, sourceName, resolvedClass, spellId, spellName, effectiveHealing, overhealing, critical)
    end
end
