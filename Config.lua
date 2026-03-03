------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Config.lua – AceConfig options panel, slash commands, and reporting
--
-- Loaded by ALL WoW versions. AceConfigDialog automatically handles
-- Retail Settings API (10.0+) vs legacy InterfaceOptions.
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- LSM helpers – populate dropdowns from LibSharedMedia
------------------------------------------------------------------------

local function LSM_StatusBarValues()
    local t = {}
    if EDM.LSM then
        local list = EDM.LSM:HashTable("statusbar")
        for k in pairs(list) do t[k] = k end
    else
        t["Blizzard"] = "Blizzard"
    end
    return t
end

local function LSM_FontValues()
    local t = {}
    if EDM.LSM then
        local list = EDM.LSM:HashTable("font")
        for k in pairs(list) do t[k] = k end
    else
        t["Friz Quadrata TT"] = "Friz Quadrata TT"
    end
    return t
end

------------------------------------------------------------------------
-- AceConfig options table
------------------------------------------------------------------------

function EDM:GetOptionsTable()
    local options = {
        type = "group",
        name = "Epic Damage Meter V2",
        childGroups = "tab",
        args = {
            ----------------------------------------------------------------
            -- Tab 1: General
            ----------------------------------------------------------------
            general = {
                type = "group",
                name = "Allgemein",
                order = 1,
                args = {
                    headerDisplay = {
                        type = "header",
                        name = "Anzeige",
                        order = 1,
                    },
                    shown = {
                        type = "toggle",
                        name = "Fenster anzeigen",
                        desc = "Hauptfenster ein-/ausblenden.",
                        order = 2,
                        width = "full",
                        get = function() return self.db.shown end,
                        set = function(_, val)
                            self.db.shown = val
                            if val then self:ShowWindow() else self:HideWindow() end
                        end,
                    },
                    locked = {
                        type = "toggle",
                        name = "Fenster sperren",
                        desc = "Verhindert Verschieben und Groesseaendern.",
                        order = 3,
                        get = function() return self.db.locked end,
                        set = function(_, val)
                            self.db.locked = val
                            if self.mainFrame then
                                self.mainFrame:SetMovable(not val)
                            end
                        end,
                    },
                    showRank = {
                        type = "toggle",
                        name = "Rang anzeigen",
                        desc = "Zeigt die Platznummer vor dem Namen.",
                        order = 4,
                        get = function() return self.db.showRank end,
                        set = function(_, val)
                            self.db.showRank = val
                            self:RefreshDisplay()
                        end,
                    },

                    headerData = {
                        type = "header",
                        name = "Daten",
                        order = 10,
                    },
                    mergePets = {
                        type = "toggle",
                        name = "Pets zusammenfuehren",
                        desc = "Pet-Schaden/-Heilung wird dem Besitzer zugerechnet.",
                        order = 11,
                        get = function() return self.db.mergePets end,
                        set = function(_, val)
                            self.db.mergePets = val
                            self:RefreshDisplay()
                        end,
                    },
                    classColors = {
                        type = "toggle",
                        name = "Klassenfarben",
                        desc = "Balken in Klassenfarben statt einheitlicher Farbe.",
                        order = 12,
                        get = function() return self.db.classColors end,
                        set = function(_, val)
                            self.db.classColors = val
                            self:RefreshDisplay()
                        end,
                    },
                    currentView = {
                        type = "select",
                        name = "Standard-Ansicht",
                        desc = "Welche Ansicht beim Start aktiv ist.",
                        order = 13,
                        values = EDM.VIEW_LABELS,
                        get = function() return self.db.currentView end,
                        set = function(_, val)
                            self.db.currentView = val
                            self:UpdateViewButtons()
                            self:RefreshDisplay()
                        end,
                    },

                    headerReset = {
                        type = "header",
                        name = "",
                        order = 20,
                    },
                    resetData = {
                        type = "execute",
                        name = "Daten zuruecksetzen",
                        desc = "Setzt alle Kampfdaten zurueck.",
                        order = 21,
                        confirm = true,
                        confirmText = "Wirklich alle Kampfdaten zuruecksetzen?",
                        func = function() self:ResetData() end,
                    },
                },
            },

            ----------------------------------------------------------------
            -- Tab 2: Appearance
            ----------------------------------------------------------------
            appearance = {
                type = "group",
                name = "Aussehen",
                order = 2,
                args = {
                    headerTexture = {
                        type = "header",
                        name = "Balken",
                        order = 1,
                    },
                    barTexture = {
                        type = "select",
                        name = "Balkentextur",
                        desc = "Textur fuer die Schadensbalken (via LibSharedMedia).",
                        order = 2,
                        dialogControl = EDM.LSM and "LSM30_Statusbar" or nil,
                        values = LSM_StatusBarValues,
                        get = function()
                            return self.db.barTextureName or "Blizzard"
                        end,
                        set = function(_, val)
                            self.db.barTextureName = val
                            if EDM.LSM then
                                self.db.barTexture = EDM.LSM:Fetch("statusbar", val)
                            end
                            self:RefreshBars()
                        end,
                    },
                    barHeight = {
                        type = "range",
                        name = "Balkenhoehe",
                        desc = "Hoehe jedes einzelnen Balkens in Pixeln.",
                        order = 3,
                        min = 10, max = 32, step = 1,
                        get = function() return self.db.barHeight end,
                        set = function(_, val)
                            self.db.barHeight = val
                            self:RefreshBars()
                        end,
                    },
                    barSpacing = {
                        type = "range",
                        name = "Balkenabstand",
                        desc = "Abstand zwischen den Balken in Pixeln.",
                        order = 4,
                        min = 0, max = 5, step = 1,
                        get = function() return self.db.barSpacing end,
                        set = function(_, val)
                            self.db.barSpacing = val
                            self:RefreshBars()
                        end,
                    },

                    headerFont = {
                        type = "header",
                        name = "Schrift",
                        order = 10,
                    },
                    font = {
                        type = "select",
                        name = "Schriftart",
                        desc = "Schriftart fuer Balkentexte (via LibSharedMedia).",
                        order = 11,
                        dialogControl = EDM.LSM and "LSM30_Font" or nil,
                        values = LSM_FontValues,
                        get = function()
                            return self.db.fontName or "Friz Quadrata TT"
                        end,
                        set = function(_, val)
                            self.db.fontName = val
                            if EDM.LSM then
                                self.db.font = EDM.LSM:Fetch("font", val)
                            end
                            self:RefreshBars()
                        end,
                    },
                    fontSize = {
                        type = "range",
                        name = "Schriftgroesse",
                        desc = "Groesse der Schrift auf den Balken.",
                        order = 12,
                        min = 6, max = 24, step = 1,
                        get = function() return self.db.fontSize end,
                        set = function(_, val)
                            self.db.fontSize = val
                            self:RefreshBars()
                        end,
                    },

                    headerWindow = {
                        type = "header",
                        name = "Fenster",
                        order = 20,
                    },
                    width = {
                        type = "range",
                        name = "Breite",
                        desc = "Breite des Hauptfensters.",
                        order = 21,
                        min = 180, max = 500, step = 5,
                        get = function() return self.db.width end,
                        set = function(_, val)
                            self.db.width = val
                            if self.mainFrame then
                                self.mainFrame:SetWidth(val)
                                self:CreateBars()
                                self:RefreshDisplay()
                            end
                        end,
                    },
                    height = {
                        type = "range",
                        name = "Hoehe",
                        desc = "Hoehe des Hauptfensters.",
                        order = 22,
                        min = 80, max = 800, step = 5,
                        get = function() return self.db.height end,
                        set = function(_, val)
                            self.db.height = val
                            if self.mainFrame then
                                self.mainFrame:SetHeight(val)
                                self:CreateBars()
                                self:RefreshDisplay()
                            end
                        end,
                    },
                    resetPosition = {
                        type = "execute",
                        name = "Position zuruecksetzen",
                        desc = "Setzt Fensterposition auf Standardwerte zurueck.",
                        order = 23,
                        func = function()
                            self.db.point    = "RIGHT"
                            self.db.relPoint = "RIGHT"
                            self.db.x        = -20
                            self.db.y        = 0
                            self.db.width    = 260
                            self.db.height   = 300
                            if self.mainFrame then
                                self.mainFrame:ClearAllPoints()
                                self.mainFrame:SetSize(260, 300)
                                self.mainFrame:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
                                self:CreateBars()
                                self:RefreshDisplay()
                            end
                        end,
                    },
                },
            },

            ----------------------------------------------------------------
            -- Tab 3: Minimap
            ----------------------------------------------------------------
            minimap = {
                type = "group",
                name = "Minimap",
                order = 3,
                args = {
                    showMinimap = {
                        type = "toggle",
                        name = "Minimap-Button anzeigen",
                        desc = "Zeigt/versteckt den Button an der Minimap.",
                        order = 1,
                        width = "full",
                        get = function()
                            return not self.db.minimap.hide
                        end,
                        set = function(_, val)
                            self.db.minimap.hide = not val
                            if self.LDBIcon then
                                if val then
                                    self.LDBIcon:Show("EpicDamageMeter")
                                else
                                    self.LDBIcon:Hide("EpicDamageMeter")
                                end
                            end
                        end,
                    },
                },
            },
        },
    }

    -- Profile tab (only when AceDB + AceDBOptions are loaded)
    local AceDBOptions = self:GetLib("AceDBOptions-3.0")
    if AceDBOptions and self.acedb then
        options.args.profiles = AceDBOptions:GetOptionsTable(self.acedb)
        options.args.profiles.order = 99
    end

    return options
end

------------------------------------------------------------------------
-- Config initialization (called from Core.lua after libs are ready)
------------------------------------------------------------------------

function EDM:InitConfig()
    local AceConfig = self:GetLib("AceConfig-3.0")
    local AceConfigDialog = self:GetLib("AceConfigDialog-3.0")

    if not AceConfig or not AceConfigDialog then
        -- Fallback: no GUI, slash commands only
        return
    end

    -- Register options table
    AceConfig:RegisterOptionsTable("EpicDamageMeter", function()
        return self:GetOptionsTable()
    end)

    -- Add to Blizzard Interface Options (works on all WoW versions)
    -- AceConfigDialog handles Retail Settings API vs legacy InterfaceOptions
    self.configPanel = AceConfigDialog:AddToBlizOptions(
        "EpicDamageMeter",
        "Epic Damage Meter"
    )

    -- Store reference for OpenConfig
    self.AceConfigDialog = AceConfigDialog
end

function EDM:OpenConfig()
    if self.AceConfigDialog then
        -- Open standalone config window (not embedded in Blizzard UI)
        self.AceConfigDialog:Open("EpicDamageMeter")
    elseif Settings and Settings.OpenToCategory then
        -- Retail 10.0+ fallback
        Settings.OpenToCategory("Epic Damage Meter")
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Legacy fallback
        InterfaceOptionsFrame_OpenToCategory(self.configPanel)
        InterfaceOptionsFrame_OpenToCategory(self.configPanel) -- called twice intentionally (Blizzard bug)
    else
        self:Print("Optionen konnten nicht geoeffnet werden.")
    end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

function EDM:RegisterSlashCommands()
    SLASH_EPICDAMAGEMETER1 = "/edm"
    SLASH_EPICDAMAGEMETER2 = "/epicdm"
    SLASH_EPICDAMAGEMETER3 = "/epicdamagemeter"

    SlashCmdList["EPICDAMAGEMETER"] = function(msg)
        msg = strtrim(msg or ""):lower()
        local cmd, arg = strsplit(" ", msg, 2)

        if cmd == "" or cmd == "show" or cmd == "toggle" then
            self:ToggleWindow()
        elseif cmd == "hide" then
            self:HideWindow()
        elseif cmd == "reset" or cmd == "clear" then
            self:ResetData()
        elseif cmd == "lock" then
            self:ToggleLock()
        elseif cmd == "damage" or cmd == "dmg" then
            self:SetView(EDM.VIEW_DAMAGE)
        elseif cmd == "dps" then
            self:SetView(EDM.VIEW_DPS)
        elseif cmd == "healing" or cmd == "heal" then
            self:SetView(EDM.VIEW_HEALING)
        elseif cmd == "hps" then
            self:SetView(EDM.VIEW_HPS)
        elseif cmd == "report" then
            local channel = arg or "say"
            self:ReportToChat(channel)
        elseif cmd == "config" or cmd == "options" or cmd == "opt" then
            self:OpenConfig()
        elseif cmd == "help" then
            self:PrintHelp()
        else
            self:PrintHelp()
        end
    end
end

------------------------------------------------------------------------
-- Window control
------------------------------------------------------------------------

function EDM:ToggleWindow()
    if not self.mainFrame then return end
    if self.mainFrame:IsShown() then
        self:HideWindow()
    else
        self:ShowWindow()
    end
end

function EDM:ShowWindow()
    if not self.mainFrame then return end
    self.mainFrame:Show()
    self.db.shown = true
    self:UpdateDisplay()
end

function EDM:HideWindow()
    if not self.mainFrame then return end
    self.mainFrame:Hide()
    self.db.shown = false
end

function EDM:ToggleLock()
    self.db.locked = not self.db.locked
    if self.mainFrame then
        self.mainFrame:SetMovable(not self.db.locked)
    end
    if self.db.locked then
        self:Print("Fenster gesperrt.")
    else
        self:Print("Fenster entsperrt.")
    end
end

function EDM:SetView(viewMode)
    self.db.currentView = viewMode
    self:UpdateViewButtons()
    self:UpdateDisplay()
    self:Print("Ansicht: " .. (EDM.VIEW_LABELS[viewMode] or "?"))
end

------------------------------------------------------------------------
-- Report to chat
------------------------------------------------------------------------

function EDM:ReportToChat(channel)
    channel = channel or "say"

    local segment = self:GetActiveSegment()
    if not segment then
        self:Print("Keine Daten zum Berichten.")
        return
    end

    local viewMode = self.db.currentView
    local data, total = self:GetSortedData(segment, viewMode)
    local viewLabel = EDM.VIEW_LABELS[viewMode] or "Schaden"
    local duration = self:GetSegmentDuration(segment)

    if #data == 0 then
        self:Print("Keine Daten zum Berichten.")
        return
    end

    local sendFunc

    if channel == "say" then
        sendFunc = function(msg) SendChatMessage(msg, "SAY") end
    elseif channel == "party" then
        sendFunc = function(msg) SendChatMessage(msg, "PARTY") end
    elseif channel == "raid" then
        sendFunc = function(msg) SendChatMessage(msg, "RAID") end
    elseif channel == "guild" then
        sendFunc = function(msg) SendChatMessage(msg, "GUILD") end
    elseif channel == "instance" then
        sendFunc = function(msg) SendChatMessage(msg, "INSTANCE_CHAT") end
    elseif channel == "whisper" or channel == "w" then
        self:Print("Bitte Ziel angeben: /edm report whisper <Name>")
        return
    elseif channel == "print" then
        sendFunc = function(msg) self:Print(msg) end
    else
        sendFunc = function(msg) SendChatMessage(msg, "SAY") end
    end

    sendFunc(("--- Epic Damage Meter: %s (%s, %.0fs) ---"):format(viewLabel, segment.name, duration))

    local numToReport = math.min(10, #data)
    for i = 1, numToReport do
        local entry = data[i]
        local pct = total > 0 and (entry.value / total * 100) or 0
        sendFunc(("%d. %s - %s (%.1f%%)"):format(i, entry.name, self:FormatNumber(entry.value), pct))
    end
end

------------------------------------------------------------------------
-- Help
------------------------------------------------------------------------

function EDM:PrintHelp()
    self:Print("--- Befehle ---")
    self:Print("/edm - Fenster ein/ausblenden")
    self:Print("/edm show - Fenster anzeigen")
    self:Print("/edm hide - Fenster verstecken")
    self:Print("/edm reset - Daten zuruecksetzen")
    self:Print("/edm lock - Fenster sperren/entsperren")
    self:Print("/edm damage - Schadensansicht")
    self:Print("/edm dps - DPS-Ansicht")
    self:Print("/edm healing - Heilungsansicht")
    self:Print("/edm hps - HPS-Ansicht")
    self:Print("/edm report <say|party|raid|guild> - Report im Chat")
    self:Print("/edm config - Optionspanel oeffnen")
    self:Print("/edm help - Diese Hilfe anzeigen")
end
