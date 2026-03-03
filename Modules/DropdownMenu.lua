------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Modules/DropdownMenu.lua – UIDropDownMenu context menu
--
-- Shared by: MoP Classic, TBC Anniversary, Classic Era
-- NOT loaded by Retail (uses MenuUtil instead)
------------------------------------------------------------------------

local _, EDM = ...

function EDM:ShowContextMenu()
    if not self.dropdownMenu then
        self.dropdownMenu = CreateFrame("Frame", "EpicDamageMeterDropdown", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(self.dropdownMenu, function(_, level)
        level = level or 1
        local info

        if level == 1 then
            info = UIDropDownMenu_CreateInfo()
            info.text = "Epic Damage Meter V2"
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)

            -- View modes
            for mode, label in pairs(EDM.VIEW_LABELS) do
                info = UIDropDownMenu_CreateInfo()
                info.text = label
                info.checked = (self.db.currentView == mode)
                info.func = function()
                    self.db.currentView = mode
                    self:UpdateViewButtons()
                    self:UpdateDisplay()
                end
                UIDropDownMenu_AddButton(info, level)
            end

            -- Separator
            info = UIDropDownMenu_CreateInfo()
            info.text = ""
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)

            -- Lock
            info = UIDropDownMenu_CreateInfo()
            info.text = "Fenster sperren"
            info.checked = self.db.locked
            info.func = function()
                self.db.locked = not self.db.locked
                self.mainFrame:SetMovable(not self.db.locked)
            end
            UIDropDownMenu_AddButton(info, level)

            -- Merge pets
            info = UIDropDownMenu_CreateInfo()
            info.text = "Pets zusammenfuehren"
            info.checked = self.db.mergePets
            info.func = function()
                self.db.mergePets = not self.db.mergePets
                self:UpdateDisplay()
            end
            UIDropDownMenu_AddButton(info, level)

            -- Show rank
            info = UIDropDownMenu_CreateInfo()
            info.text = "Rang anzeigen"
            info.checked = self.db.showRank
            info.func = function()
                self.db.showRank = not self.db.showRank
                self:UpdateDisplay()
            end
            UIDropDownMenu_AddButton(info, level)

            -- Separator
            info = UIDropDownMenu_CreateInfo()
            info.text = ""
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)

            -- Reset
            info = UIDropDownMenu_CreateInfo()
            info.text = "Daten zuruecksetzen"
            info.notCheckable = true
            info.func = function() EDM:ResetData() end
            UIDropDownMenu_AddButton(info, level)

            -- Report
            info = UIDropDownMenu_CreateInfo()
            info.text = "Chat-Report"
            info.notCheckable = true
            info.func = function() EDM:ReportToChat("say") end
            UIDropDownMenu_AddButton(info, level)

            -- Options
            info = UIDropDownMenu_CreateInfo()
            info.text = "Optionen"
            info.notCheckable = true
            info.func = function() EDM:OpenConfig() end
            UIDropDownMenu_AddButton(info, level)

            -- Close
            info = UIDropDownMenu_CreateInfo()
            info.text = "Schliessen"
            info.notCheckable = true
            info.func = function() CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, self.dropdownMenu, "cursor", 0, 0)
end
