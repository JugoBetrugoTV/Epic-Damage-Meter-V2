------------------------------------------------------------------------
-- Epic Damage Meter V2
-- CombatLog.lua – Event registration + combat data collection
--
-- Midnight (12.0+):
--   Frame:RegisterEvent() is a protected function – addons can't use it.
--   COMBAT_LOG_EVENT_UNFILTERED has been removed.
--   → Frame:RegisterEventCallback(event, cb)  for traditional events
--   → RegisterEventCallback(event, cb)         for new Midnight events
--   → C_DamageMeter API for damage/healing data
--
-- Classic / TBC / MoP:
--   → Use Frame:RegisterEvent() + CLEU parsing (still works)
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- Event registration abstraction
------------------------------------------------------------------------

-- C_DamageMeter only exists in Midnight 12.0+
local isMidnight = (C_DamageMeter ~= nil)

-- Event frame (used on all versions; Midnight uses RegisterEventCallback method)
local eventFrame = CreateFrame("Frame")

if isMidnight then
    -- Midnight 12.0+: Frame:RegisterEventCallback(event, cb)
    -- New frame method that replaces Frame:RegisterEvent() for addon code.
    -- Global RegisterEventCallback() is only for NEW Midnight events.
    local function RegisterSafeEvent(event, handler)
        -- Try frame method first (works for traditional events)
        if eventFrame.RegisterEventCallback then
            eventFrame:RegisterEventCallback(event, handler)
        else
            -- Fallback: global function (only works for new events)
            RegisterEventCallback(event, handler)
        end
    end
    EDM.RegisterSafeEvent = RegisterSafeEvent
else
    -- Classic/TBC/MoP: Frame:RegisterEvent + OnEvent dispatch
    local eventHandlers = {}
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        local handler = eventHandlers[event]
        if handler then handler(...) end
    end)
    local function RegisterSafeEvent(event, handler)
        eventHandlers[event] = handler
        eventFrame:RegisterEvent(event)
    end
    EDM.RegisterSafeEvent = RegisterSafeEvent
end

------------------------------------------------------------------------
-- Combat log event registration
------------------------------------------------------------------------

function EDM:RegisterCombatLog()
    -- Combat state events (all versions)
    RegisterSafeEvent("PLAYER_REGEN_DISABLED", function()
        EDM:StartCombat()
    end)

    RegisterSafeEvent("PLAYER_REGEN_ENABLED", function()
        C_Timer.After(0.5, function()
            EDM:EndCombat()
        end)
    end)

    RegisterSafeEvent("GROUP_ROSTER_UPDATE", function()
        EDM:ScanGroupMembers()
    end)

    RegisterSafeEvent("UNIT_PET", function()
        EDM:ScanPets()
    end)

    -- Version-specific events (encounter tracking)
    self:RegisterVersionEvents()

    if isMidnight then
        -- ============================================================
        -- Midnight 12.0+: C_DamageMeter replaces CLEU
        -- ============================================================
        RegisterSafeEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", function(meterType, sessionID)
            EDM:OnDamageMeterSessionUpdated(meterType, sessionID)
        end)
    else
        -- ============================================================
        -- Classic / TBC / MoP: traditional CLEU parsing
        -- ============================================================
        RegisterSafeEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
            EDM:OnCombatLogEvent()
        end)
    end

    -- Initial group scan
    self:ScanGroupMembers()
    self:ScanPets()
end

------------------------------------------------------------------------
-- C_DamageMeter integration (Midnight 12.0+ only)
--
-- Blizzard's server-side damage meter provides aggregated session data.
-- We query it on each update event and import into our segment format.
-- Secret Values: During boss encounters / M+, numeric values may be
-- secret (can't do math). We use pcall to handle this gracefully.
------------------------------------------------------------------------

function EDM:OnDamageMeterSessionUpdated(meterType, sessionID)
    if not C_DamageMeter then return end

    -- Only process damage and healing types
    local isDamage  = (meterType == Enum.DamageMeterType.DamageDone)
    local isHealing = (meterType == Enum.DamageMeterType.HealingDone)
    if not isDamage and not isHealing then return end

    -- Query the session
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType)
    if not ok or not session then return end

    -- Ensure we have a segment
    if not self.currentSegment then
        self:StartCombat()
    end
    local segment = self.currentSegment
    if not segment then return end

    -- Import source data into our segment
    if session.combatSources then
        for _, source in ipairs(session.combatSources) do
            local guid = source.sourceGUID or ("creature:" .. tostring(source.sourceCreatureID or 0))
            local name = source.name or "Unbekannt"
            local class = source.classFilename or "UNKNOWN"

            -- pcall: totalAmount may be a secret value during restricted combat
            local amount
            local amtOk, amtVal = pcall(function() return source.totalAmount + 0 end)
            if amtOk then
                amount = amtVal
            else
                amount = 0
            end

            local player = self:GetOrCreatePlayer(segment, guid, name, class)
            if player then
                if isDamage then
                    player.damage = amount
                elseif isHealing then
                    player.healing = amount
                end
            end
        end
    end

    -- Update segment duration from server data
    local durOk, dur = pcall(function() return session.durationSeconds + 0 end)
    if durOk and dur and dur > 0 then
        segment.startTime = GetTime() - dur
    end

    self.displayDirty = true
end

------------------------------------------------------------------------
-- Group scanning for class information
------------------------------------------------------------------------

function EDM:ScanGroupMembers()
    if not self.classCache then self.classCache = {} end

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumGroupMembers() - 1
    else
        -- Solo – cache the player
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

    -- Always add player
    local guid = UnitGUID("player")
    local _, class = UnitClass("player")
    if guid and class then
        self.classCache[guid] = class
    end
end

function EDM:ScanPets()
    if not self.petOwners then self.petOwners = {} end

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumGroupMembers() - 1
    else
        prefix, count = nil, 0
    end

    -- Player pet
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
-- Class lookup (used by CLEU path on Classic/TBC/MoP)
------------------------------------------------------------------------

function EDM:LookupClass(guid)
    if not guid then return "UNKNOWN" end
    if self.classCache and self.classCache[guid] then
        return self.classCache[guid]
    end

    -- Try to extract from GUID (Player-Server-ID format)
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
--
-- Not used on Midnight 12.0+ where CLEU has been removed.
------------------------------------------------------------------------

-- Sub-events that represent damage
local DAMAGE_EVENTS = {
    SWING_DAMAGE           = true,
    RANGE_DAMAGE           = true,
    SPELL_DAMAGE           = true,
    SPELL_PERIODIC_DAMAGE  = true,
    DAMAGE_SHIELD           = true,
    SPELL_BUILDING_DAMAGE  = true,
}

-- Sub-events that represent healing
local HEALING_EVENTS = {
    SPELL_HEAL             = true,
    SPELL_PERIODIC_HEAL    = true,
}

function EDM:OnCombatLogEvent()
    local timestamp, subevent, hideCaster,
          sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

    -- Only process events from friendly players/pets
    if not self:IsFriendlyPlayer(sourceFlags) then return end

    ---------------------------------------------------------------
    -- Damage events
    ---------------------------------------------------------------
    if DAMAGE_EVENTS[subevent] then
        local spellId, spellName, spellSchool
        local amount, overkill, school, resisted, blocked, absorbed, critical

        if subevent == "SWING_DAMAGE" then
            -- Swing damage: params start at position 12
            spellId   = 0
            spellName = "Nahkampf"
            amount, overkill, school, resisted, blocked, absorbed, critical =
                select(12, CombatLogGetCurrentEventInfo())
        else
            -- Spell/Range/Shield damage: spellId, spellName, spellSchool, then damage params
            spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical =
                select(12, CombatLogGetCurrentEventInfo())
        end

        if not amount or amount <= 0 then return end

        -- Auto-start combat if not yet in combat
        if not self.inCombat then
            self:StartCombat()
        end

        -- Resolve source for pets
        local resolvedGUID = sourceGUID
        local resolvedName = sourceName
        local resolvedClass = "UNKNOWN"

        local isPetOrGuardian = bit.band(sourceFlags, bit.bor(self.TYPE_PET, self.TYPE_GUARDIAN)) ~= 0
        if isPetOrGuardian then
            local ownerGUID = self:ResolvePetOwner(sourceGUID, sourceName, sourceFlags)
            if ownerGUID then
                self:SetPetOwner(sourceGUID, ownerGUID)
            end
            -- Record under the actual pet GUID; merging happens at display time
            resolvedClass = self:LookupClass(sourceGUID)
        else
            resolvedClass = self:LookupClass(sourceGUID)
        end

        self:RecordDamage(sourceGUID, sourceName, resolvedClass, spellId, spellName, amount, critical, destName)

    ---------------------------------------------------------------
    -- Healing events
    ---------------------------------------------------------------
    elseif HEALING_EVENTS[subevent] then
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical =
            select(12, CombatLogGetCurrentEventInfo())

        if not amount or amount <= 0 then return end

        -- Subtract overhealing from effective healing
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
