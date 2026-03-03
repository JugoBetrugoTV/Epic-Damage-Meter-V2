------------------------------------------------------------------------
-- Epic Damage Meter V2
-- Config.lua – Slash commands, reporting, and configuration
------------------------------------------------------------------------

local _, EDM = ...

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
        elseif cmd == "config" or cmd == "options" then
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

    -- Determine the chat function
    local sendFunc
    local target

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
        -- Default to say
        sendFunc = function(msg) SendChatMessage(msg, "SAY") end
    end

    -- Header line
    sendFunc(("--- Epic Damage Meter: %s (%s, %.0fs) ---"):format(viewLabel, segment.name, duration))

    -- Top entries (max 10)
    local numToReport = math.min(10, #data)
    for i = 1, numToReport do
        local entry = data[i]
        local pct = total > 0 and (entry.value / total * 100) or 0
        sendFunc(("%d. %s - %s (%.1f%%)"):format(i, entry.name, self:FormatNumber(entry.value), pct))
    end
end

------------------------------------------------------------------------
-- Configuration (Interface Options)
------------------------------------------------------------------------

function EDM:OpenConfig()
    self:Print("Rechtsklick auf das Fenster für Optionen.")
end

------------------------------------------------------------------------
-- Help
------------------------------------------------------------------------

function EDM:PrintHelp()
    self:Print("--- Befehle ---")
    self:Print("/edm - Fenster ein/ausblenden")
    self:Print("/edm show - Fenster anzeigen")
    self:Print("/edm hide - Fenster verstecken")
    self:Print("/edm reset - Daten zurücksetzen")
    self:Print("/edm lock - Fenster sperren/entsperren")
    self:Print("/edm damage - Schadensansicht")
    self:Print("/edm dps - DPS-Ansicht")
    self:Print("/edm healing - Heilungsansicht")
    self:Print("/edm hps - HPS-Ansicht")
    self:Print("/edm report <say|party|raid|guild> - Report im Chat")
    self:Print("/edm help - Diese Hilfe anzeigen")
end
