------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Modules/TBC.lua – TBC Anniversary Edition (2.x) specific code
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- Classes: 9 classes in TBC (no Death Knight, Monk, Demon Hunter, Evoker)
------------------------------------------------------------------------

EDM.CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE    = { r = 0.25, g = 0.78, b = 0.92 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
    UNKNOWN = { r = 0.60, g = 0.60, b = 0.60 },
}

------------------------------------------------------------------------
-- Context menu: UIDropDownMenu (provided by DropdownMenu.lua)
------------------------------------------------------------------------

-- ShowContextMenu is inherited from Modules/DropdownMenu.lua

------------------------------------------------------------------------
-- Version events: No ENCOUNTER events in TBC
------------------------------------------------------------------------

function EDM:RegisterVersionEvents()
    -- TBC does not have reliable ENCOUNTER_START / ENCOUNTER_END
end

function EDM:HandleVersionEvent(event, ...)
    -- No version-specific events
end

------------------------------------------------------------------------
-- Pet resolution: Cache-only (no C_PlayerInfo in TBC)
------------------------------------------------------------------------

function EDM:ResolvePetOwner(petGUID, petName, petFlags)
    return self:GetPetOwner(petGUID)
end
