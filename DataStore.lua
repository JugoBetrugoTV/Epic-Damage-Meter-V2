------------------------------------------------------------------------
-- Epic Damage Meter V2
-- DataStore.lua – Data tracking, segments, and aggregation
------------------------------------------------------------------------

local _, EDM = ...

------------------------------------------------------------------------
-- Segment management
------------------------------------------------------------------------

-- A segment captures data for a single encounter or overall session.
-- Structure of a segment:
--   segment = {
--       name      = "Boss Name" or "Trash" or "Overall",
--       startTime = GetTime(),
--       endTime   = nil or GetTime(),
--       active    = true/false,
--       players   = {
--           [sourceGUID] = {
--               name     = "Player",
--               class    = "WARRIOR",
--               petOwner = nil or ownerGUID,  -- if this is a pet
--               damage   = 0,
--               healing  = 0,
--               overhealing = 0,
--               abilities = {
--                   [spellId] = {
--                       name   = "Spell Name",
--                       damage = 0,
--                       healing = 0,
--                       hits   = 0,
--                       crits  = 0,
--                       maxHit = 0,
--                   },
--               },
--           },
--       },
--   }

local MAX_HISTORY = 10

function EDM:InitDataStore()
    self.segments = {}
    self.overallSegment = self:CreateSegment("Gesamt")
    self.currentSegment = nil
    self.inCombat = false
end

function EDM:CreateSegment(name)
    return {
        name      = name or "Unbekannt",
        startTime = GetTime(),
        endTime   = nil,
        active    = true,
        players   = {},
    }
end

function EDM:StartCombat()
    if self.inCombat then return end
    self.inCombat = true
    self.currentSegment = self:CreateSegment("Aktueller Kampf")
    if self.mainFrame then
        self:UpdateDisplay()
    end
end

function EDM:EndCombat()
    if not self.inCombat then return end
    self.inCombat = false

    if self.currentSegment then
        self.currentSegment.active = false
        self.currentSegment.endTime = GetTime()

        -- Only save segments with actual data
        local hasData = false
        for _ in pairs(self.currentSegment.players) do
            hasData = true
            break
        end

        if hasData then
            -- Name the segment after the primary target if available
            local topDest = self:GetTopTarget(self.currentSegment)
            if topDest then
                self.currentSegment.name = topDest
            end

            -- Add to history
            table.insert(self.segments, 1, self.currentSegment)

            -- Trim history
            while #self.segments > MAX_HISTORY do
                table.remove(self.segments)
            end
        end
    end

    if self.mainFrame then
        self:UpdateDisplay()
    end
end

function EDM:GetTopTarget(segment)
    -- Returns the most‑damaged enemy name for labeling the segment
    if not segment or not segment._targets then return nil end
    local maxDmg, topName = 0, nil
    for name, dmg in pairs(segment._targets) do
        if dmg > maxDmg then
            maxDmg = dmg
            topName = name
        end
    end
    return topName
end

function EDM:TrackTarget(segment, destName, amount)
    if not segment or not destName then return end
    if not segment._targets then segment._targets = {} end
    segment._targets[destName] = (segment._targets[destName] or 0) + amount
end

------------------------------------------------------------------------
-- Player data management
------------------------------------------------------------------------

function EDM:GetOrCreatePlayer(segment, guid, name, class)
    if not segment then return nil end
    if not segment.players[guid] then
        segment.players[guid] = {
            name      = name or "Unbekannt",
            class     = class or "UNKNOWN",
            petOwner  = nil,
            damage    = 0,
            healing   = 0,
            overhealing = 0,
            abilities = {},
        }
    else
        -- Update name / class if we learn them later
        if name and segment.players[guid].name == "Unbekannt" then
            segment.players[guid].name = name
        end
        if class and class ~= "UNKNOWN" then
            segment.players[guid].class = class
        end
    end
    return segment.players[guid]
end

function EDM:RecordDamage(sourceGUID, sourceName, sourceClass, spellId, spellName, amount, critical, destName)
    if not self.overallSegment then return end

    -- Record in overall segment
    self:AddDamage(self.overallSegment, sourceGUID, sourceName, sourceClass, spellId, spellName, amount, critical)
    self:TrackTarget(self.overallSegment, destName, amount)

    -- Record in current segment
    if self.currentSegment then
        self:AddDamage(self.currentSegment, sourceGUID, sourceName, sourceClass, spellId, spellName, amount, critical)
        self:TrackTarget(self.currentSegment, destName, amount)
    end

    -- Refresh display (throttled in Display.lua)
    self.displayDirty = true
end

function EDM:RecordHealing(sourceGUID, sourceName, sourceClass, spellId, spellName, amount, overhealing, critical)
    if not self.overallSegment then return end

    -- Record in overall segment
    self:AddHealing(self.overallSegment, sourceGUID, sourceName, sourceClass, spellId, spellName, amount, overhealing, critical)

    -- Record in current segment
    if self.currentSegment then
        self:AddHealing(self.currentSegment, sourceGUID, sourceName, sourceClass, spellId, spellName, amount, overhealing, critical)
    end

    self.displayDirty = true
end

function EDM:AddDamage(segment, guid, name, class, spellId, spellName, amount, critical)
    local player = self:GetOrCreatePlayer(segment, guid, name, class)
    if not player then return end
    player.damage = player.damage + amount

    -- Track per-ability
    if not player.abilities[spellId] then
        player.abilities[spellId] = {
            name    = spellName,
            damage  = 0,
            healing = 0,
            hits    = 0,
            crits   = 0,
            maxHit  = 0,
        }
    end
    local ability = player.abilities[spellId]
    ability.damage = ability.damage + amount
    ability.hits   = ability.hits + 1
    if critical then
        ability.crits = ability.crits + 1
    end
    if amount > ability.maxHit then
        ability.maxHit = amount
    end
end

function EDM:AddHealing(segment, guid, name, class, spellId, spellName, amount, overhealing, critical)
    local player = self:GetOrCreatePlayer(segment, guid, name, class)
    if not player then return end
    player.healing     = player.healing + amount
    player.overhealing = player.overhealing + (overhealing or 0)

    -- Track per-ability
    if not player.abilities[spellId] then
        player.abilities[spellId] = {
            name    = spellName,
            damage  = 0,
            healing = 0,
            hits    = 0,
            crits   = 0,
            maxHit  = 0,
        }
    end
    local ability = player.abilities[spellId]
    ability.healing = ability.healing + amount
    ability.hits    = ability.hits + 1
    if critical then
        ability.crits = ability.crits + 1
    end
end

------------------------------------------------------------------------
-- Pet merging
------------------------------------------------------------------------

function EDM:SetPetOwner(petGUID, ownerGUID)
    if not self.petOwners then self.petOwners = {} end
    self.petOwners[petGUID] = ownerGUID
end

function EDM:GetPetOwner(petGUID)
    return self.petOwners and self.petOwners[petGUID] or nil
end

function EDM:ResolvePetOwner(petGUID, petName, petFlags)
    -- Try cached lookup first
    local owner = self:GetPetOwner(petGUID)
    if owner then return owner end

    -- Try tooltip scanning via GUID
    if petGUID then
        local ownerGUID = C_PlayerInfo and C_PlayerInfo.GetOwnerForPet and C_PlayerInfo.GetOwnerForPet(petGUID)
        if ownerGUID then
            self:SetPetOwner(petGUID, ownerGUID)
            return ownerGUID
        end
    end

    return nil
end

------------------------------------------------------------------------
-- Data retrieval for display
------------------------------------------------------------------------

function EDM:GetActiveSegment()
    if self.inCombat and self.currentSegment then
        return self.currentSegment
    elseif self.currentSegment and not self.currentSegment.active then
        return self.currentSegment
    elseif #self.segments > 0 then
        return self.segments[1]
    end
    return self.overallSegment
end

function EDM:GetSegmentDuration(segment)
    if not segment then return 1 end
    local endT = segment.endTime or GetTime()
    local duration = endT - segment.startTime
    return math.max(duration, 1)
end

function EDM:GetSortedData(segment, viewMode)
    if not segment then return {} end

    local data = {}
    local duration = self:GetSegmentDuration(segment)

    -- If pet merging is enabled, first accumulate pet damage into owners
    local merged = {}
    if self.db.mergePets then
        for guid, player in pairs(segment.players) do
            local ownerGUID = self:GetPetOwner(guid)
            if ownerGUID and segment.players[ownerGUID] then
                -- Merge pet data into owner
                if not merged[ownerGUID] then
                    merged[ownerGUID] = {
                        name    = segment.players[ownerGUID].name,
                        class   = segment.players[ownerGUID].class,
                        damage  = segment.players[ownerGUID].damage,
                        healing = segment.players[ownerGUID].healing,
                    }
                end
                merged[ownerGUID].damage  = merged[ownerGUID].damage + player.damage
                merged[ownerGUID].healing = merged[ownerGUID].healing + player.healing
            else
                if not merged[guid] then
                    merged[guid] = {
                        name    = player.name,
                        class   = player.class,
                        damage  = player.damage,
                        healing = player.healing,
                    }
                end
            end
        end
    else
        for guid, player in pairs(segment.players) do
            merged[guid] = {
                name    = player.name,
                class   = player.class,
                damage  = player.damage,
                healing = player.healing,
            }
        end
    end

    -- Build sorted list based on view mode
    local total = 0
    for guid, p in pairs(merged) do
        local value = 0
        if viewMode == EDM.VIEW_DAMAGE then
            value = p.damage
        elseif viewMode == EDM.VIEW_DPS then
            value = p.damage / duration
        elseif viewMode == EDM.VIEW_HEALING then
            value = p.healing
        elseif viewMode == EDM.VIEW_HPS then
            value = p.healing / duration
        end

        if value > 0 then
            table.insert(data, {
                guid   = guid,
                name   = p.name,
                class  = p.class,
                value  = value,
            })
            total = total + value
        end
    end

    -- Sort descending by value
    table.sort(data, function(a, b) return a.value > b.value end)

    return data, total
end

------------------------------------------------------------------------
-- Reset
------------------------------------------------------------------------

function EDM:ResetData()
    self:InitDataStore()
    if self.mainFrame then
        self:UpdateDisplay()
    end
    self:Print("Daten zurückgesetzt.")
end
