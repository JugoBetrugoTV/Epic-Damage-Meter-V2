------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Modules/Retail.lua – Retail (Midnight 12.0.1+) specific code
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- Classes: All 13 classes available in Retail
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
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
    UNKNOWN     = { r = 0.60, g = 0.60, b = 0.60 },
}

------------------------------------------------------------------------
-- Context menu: MenuUtil (available since 11.0)
------------------------------------------------------------------------

function EDM:ShowContextMenu()
    MenuUtil.CreateContextMenu(self.mainFrame, function(ownerRegion, rootDescription)
        rootDescription:CreateTitle("Epic Damage Meter V2")

        for mode, label in pairs(EDM.VIEW_LABELS) do
            rootDescription:CreateRadio(label,
                function() return self.db.currentView == mode end,
                function()
                    self.db.currentView = mode
                    self:UpdateViewButtons()
                    self:UpdateDisplay()
                end
            )
        end

        rootDescription:CreateDivider()

        rootDescription:CreateCheckbox(
            "Fenster sperren",
            function() return self.db.locked end,
            function()
                self.db.locked = not self.db.locked
                self.mainFrame:SetMovable(not self.db.locked)
            end
        )

        rootDescription:CreateCheckbox(
            "Pets zusammenfuehren",
            function() return self.db.mergePets end,
            function()
                self.db.mergePets = not self.db.mergePets
                self:UpdateDisplay()
            end
        )

        rootDescription:CreateCheckbox(
            "Rang anzeigen",
            function() return self.db.showRank end,
            function()
                self.db.showRank = not self.db.showRank
                self:UpdateDisplay()
            end
        )

        rootDescription:CreateDivider()

        rootDescription:CreateButton("Daten zuruecksetzen", function()
            EDM:ResetData()
        end)

        rootDescription:CreateButton("Chat-Report", function()
            EDM:ReportToChat("say")
        end)
    end)
end

------------------------------------------------------------------------
-- Version events: ENCOUNTER_START / ENCOUNTER_END
------------------------------------------------------------------------

function EDM:RegisterVersionEvents(frame)
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
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
-- Pet resolution: C_PlayerInfo.GetOwnerForPet (Retail API)
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
