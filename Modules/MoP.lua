------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Modules/MoP.lua – MoP Classic (5.x) specific code
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- Classes: 11 classes in MoP (no Demon Hunter, no Evoker)
------------------------------------------------------------------------

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
    UNKNOWN     = { r = 0.60, g = 0.60, b = 0.60 },
}

------------------------------------------------------------------------
-- Context menu: UIDropDownMenu (provided by DropdownMenu.lua)
------------------------------------------------------------------------

-- ShowContextMenu is inherited from Modules/DropdownMenu.lua

------------------------------------------------------------------------
-- Version events: ENCOUNTER_START / ENCOUNTER_END
------------------------------------------------------------------------

function EDM:RegisterVersionEvents()
    EDM.RegisterSafeEventWithArgs("ENCOUNTER_START", function(...)
        EDM:HandleVersionEvent("ENCOUNTER_START", ...)
    end)
    EDM.RegisterSafeEventWithArgs("ENCOUNTER_END", function(...)
        EDM:HandleVersionEvent("ENCOUNTER_END", ...)
    end)
end

function EDM:HandleVersionEvent(event, ...)
    if event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        self:StartCombat()
        if self.currentSegment and encounterName then
            self.currentSegment.name = encounterName
        end
    elseif event == "ENCOUNTER_END" then
        self:EndCombat()
    end
end

------------------------------------------------------------------------
-- Pet resolution: C_PlayerInfo may be available on MoP Classic client
------------------------------------------------------------------------

function EDM:ResolvePetOwner(petGUID, petName, petFlags)
    local owner = self:GetPetOwner(petGUID)
    if owner then return owner end

    if petGUID and C_PlayerInfo and C_PlayerInfo.GetOwnerForPet then
        local ownerGUID = C_PlayerInfo.GetOwnerForPet(petGUID)
        if ownerGUID then
            self:SetPetOwner(petGUID, ownerGUID)
            return ownerGUID
        end
    end

    return nil
end
