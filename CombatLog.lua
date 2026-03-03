------------------------------------------------------------------------
-- Epic Damage Meter V2
-- CombatLog.lua – COMBAT_LOG_EVENT_UNFILTERED parsing
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- Event registration abstraction
--
-- Midnight (12.0+): Frame:RegisterEvent() is a protected function.
--   Use EventRegistry:RegisterFrameEventAndCallback() instead.
-- Classic/TBC/MoP: EventRegistry doesn't exist, use legacy frame events.
------------------------------------------------------------------------

local useEventRegistry = EventRegistry
    and EventRegistry.RegisterFrameEventAndCallback
    and true or false

-- Legacy event frame (only created when EventRegistry is unavailable)
local combatFrame
local eventHandlers = {}

if not useEventRegistry then
    combatFrame = CreateFrame("Frame")
    combatFrame:SetScript("OnEvent", function(_, event, ...)
        local handler = eventHandlers[event]
        if handler then handler(...) end
    end)
end

--- Register for a Blizzard event with a callback.
-- Automatically picks the right API for the WoW version.
local function RegisterSafeEvent(event, handler)
    if useEventRegistry then
        EventRegistry:RegisterFrameEventAndCallback(event, function()
            handler()
        end, "EDM_" .. event)
    else
        eventHandlers[event] = handler
        combatFrame:RegisterEvent(event)
    end
end

--- Register for a Blizzard event that passes arguments to the callback.
local function RegisterSafeEventWithArgs(event, handler)
    if useEventRegistry then
        EventRegistry:RegisterFrameEventAndCallback(event, function(_, ...)
            handler(...)
        end, "EDM_" .. event)
    else
        eventHandlers[event] = handler
        combatFrame:RegisterEvent(event)
    end
end

-- Expose for version modules (Retail.lua, MoP.lua, etc.)
EDM.RegisterSafeEvent = RegisterSafeEvent
EDM.RegisterSafeEventWithArgs = RegisterSafeEventWithArgs

------------------------------------------------------------------------
-- Combat log event registration
------------------------------------------------------------------------

function EDM:RegisterCombatLog()
    -- Core events
    RegisterSafeEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
        EDM:OnCombatLogEvent()
    end)

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

    -- Version-specific events (ENCOUNTER_START/END in Retail & MoP)
    self:RegisterVersionEvents()

    -- Initial group scan
    self:ScanGroupMembers()
    self:ScanPets()
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
-- Class lookup
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
-- CLEU parsing
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

-- Sub-events that indicate combat start (for auto-detection)
local COMBAT_START_EVENTS = {
    SWING_DAMAGE          = true,
    RANGE_DAMAGE          = true,
    SPELL_DAMAGE          = true,
    SPELL_PERIODIC_DAMAGE = true,
    SPELL_CAST_SUCCESS    = true,
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
