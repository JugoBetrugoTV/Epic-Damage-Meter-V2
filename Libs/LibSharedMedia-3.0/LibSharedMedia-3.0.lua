--[[
LibSharedMedia-3.0 – Shared media registry for WoW addons.

Provides a central registry for statusbar textures, fonts, sounds,
backgrounds, and borders so that addons can share media resources.

API:
  :Register(mediatype, key, data)     – register a media entry
  :Fetch(mediatype, key)              – retrieve path for a media entry
  :HashTable(mediatype)               – get full key→path table for a type
  :List(mediatype)                    – get sorted list of keys
  :IsValid(mediatype, key)            – check if a key exists
  :SetGlobal(mediatype, key)          – set the global default for a type

Media types: "statusbar", "font", "sound", "background", "border"
Callbacks:   "LibSharedMedia_Registered", "LibSharedMedia_SetGlobal"

License: Public Domain / MIT
]]

local MAJOR, MINOR = "LibSharedMedia-3.0", 8
local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then return end

-- ----------------------------------------------------------------
-- Media type constants
-- ----------------------------------------------------------------

lib.MediaType          = lib.MediaType or {}
lib.MediaType.STATUSBAR   = "statusbar"
lib.MediaType.FONT        = "font"
lib.MediaType.SOUND       = "sound"
lib.MediaType.BACKGROUND  = "background"
lib.MediaType.BORDER      = "border"

-- Backwards-compat short names
lib.STATUSBAR   = "statusbar"
lib.FONT        = "font"
lib.SOUND       = "sound"
lib.BACKGROUND  = "background"
lib.BORDER      = "border"

-- ----------------------------------------------------------------
-- Internal storage
-- ----------------------------------------------------------------

lib.mediaTable   = lib.mediaTable   or {}   -- [type][key] = data
lib.sortedList   = lib.sortedList   or {}   -- [type] = { sorted keys }
lib.globalMedia  = lib.globalMedia  or {}   -- [type] = key

-- Callback handler (reuse existing if upgrading)
if not lib.callbacks then
    lib.callbacks = LibStub("CallbackHandler-1.0"):New(lib)
end

-- ----------------------------------------------------------------
-- Default media (Blizzard built-in)
-- ----------------------------------------------------------------

local defaultMedia = {
    statusbar = {
        ["Blizzard"]            = "Interface\\TargetingFrame\\UI-StatusBar",
        ["Blizzard Character Skills Bar"] = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
        ["Blizzard Raid Bar"]   = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    },
    font = {
        ["Friz Quadrata TT"]   = "Fonts\\FRIZQT__.TTF",
        ["Arial Narrow"]       = "Fonts\\ARIALN.TTF",
        ["Morpheus"]           = "Fonts\\MORPHEUS.TTF",
        ["Skurri"]             = "Fonts\\skurri.TTF",
    },
    sound = {},
    background = {
        ["Blizzard Dialog Background"]       = "Interface\\DialogFrame\\UI-DialogBox-Background",
        ["Blizzard Dialog Background Dark"]  = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        ["Blizzard Dialog Background Gold"]  = "Interface\\DialogFrame\\UI-DialogBox-Gold-Background",
    },
    border = {
        ["Blizzard Dialog"]     = "Interface\\DialogFrame\\UI-DialogBox-Border",
        ["Blizzard Dialog Gold"] = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        ["Blizzard Tooltip"]    = "Interface\\Tooltips\\UI-Tooltip-Border",
    },
}

-- Defaults for Fetch when a key is not found
local defaultFallback = {
    statusbar  = "Interface\\TargetingFrame\\UI-StatusBar",
    font       = "Fonts\\FRIZQT__.TTF",
    sound      = "",
    background = "Interface\\DialogFrame\\UI-DialogBox-Background",
    border     = "Interface\\DialogFrame\\UI-DialogBox-Border",
}

-- Register built-in defaults
for mediatype, entries in pairs(defaultMedia) do
    if not lib.mediaTable[mediatype] then
        lib.mediaTable[mediatype] = {}
    end
    for key, data in pairs(entries) do
        lib.mediaTable[mediatype][key] = data
    end
end

-- ----------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------

local function rebuildSortedList(mediatype)
    local sorted = {}
    for key in pairs(lib.mediaTable[mediatype] or {}) do
        sorted[#sorted + 1] = key
    end
    table.sort(sorted)
    lib.sortedList[mediatype] = sorted
end

-- ----------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------

--- Register a new media entry.
-- @param mediatype (string) one of the MediaType constants
-- @param key       (string) display name
-- @param data      (string) file path or sound ID
-- @return true if the entry was registered, false if it was a duplicate
function lib:Register(mediatype, key, data)
    if not mediatype or not key or not data then return false end

    if not self.mediaTable[mediatype] then
        self.mediaTable[mediatype] = {}
    end

    local isNew = (self.mediaTable[mediatype][key] == nil)
    self.mediaTable[mediatype][key] = data

    if isNew then
        rebuildSortedList(mediatype)
        self.callbacks:Fire("LibSharedMedia_Registered", mediatype, key)
    end

    return true
end

--- Retrieve the path/data for a given media entry.
-- If the key is not found, returns the default for that media type.
-- @param mediatype (string) one of the MediaType constants
-- @param key       (string) display name
-- @return (string) the media path
function lib:Fetch(mediatype, key)
    local bucket = self.mediaTable[mediatype]
    if bucket and key and bucket[key] then
        return bucket[key]
    end
    return defaultFallback[mediatype] or ""
end

--- Get the full key→path table for a media type.
-- @param mediatype (string)
-- @return (table) the hash table {key = path, ...}
function lib:HashTable(mediatype)
    return self.mediaTable[mediatype] or {}
end

--- Get a sorted list of registered keys for a media type.
-- @param mediatype (string)
-- @return (table) numerically-indexed sorted table of keys
function lib:List(mediatype)
    if not self.sortedList[mediatype] then
        rebuildSortedList(mediatype)
    end
    return self.sortedList[mediatype]
end

--- Check if a key exists for a media type.
-- @param mediatype (string)
-- @param key       (string)
-- @return (boolean)
function lib:IsValid(mediatype, key)
    return self.mediaTable[mediatype] and self.mediaTable[mediatype][key] and true or false
end

--- Set the global default for a media type.
-- @param mediatype (string)
-- @param key       (string)
function lib:SetGlobal(mediatype, key)
    if self:IsValid(mediatype, key) then
        self.globalMedia[mediatype] = key
        self.callbacks:Fire("LibSharedMedia_SetGlobal", mediatype, key)
    end
end

--- Get the global default for a media type.
-- @param mediatype (string)
-- @return (string) key or nil
function lib:GetGlobal(mediatype)
    return self.globalMedia[mediatype]
end

--- Get the default path for a media type.
-- @param mediatype (string)
-- @return (string) default path
function lib:GetDefault(mediatype)
    return defaultFallback[mediatype]
end
