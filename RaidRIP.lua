local ADDON_NAME = ...
local PREFIX = "RAIDRIP"
local DEFAULT_SOUND = "Sound\\Interface\\RaidWarning.ogg"

local frame = CreateFrame("Frame")
local roster = {}
local guidToName = {}
local recentDeaths = {}

local function now()
    return GetTime()
end

local function shortName(name)
    if not name then
        return nil
    end

    if Ambiguate then
        return Ambiguate(name, "short")
    end

    local base = name:match("([^%-]+)")
    return base or name
end

local function normalizePath(path)
    if not path or path == "" then
        return path
    end

    return (path:gsub("\\\\", "\\"))
end

local function printMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00d1ffRaidRIP|r: " .. msg)
end

local function debugMsg(msg)
    if RaidRIPDB and RaidRIPDB.debug then
        printMsg("|cffffd200DEBUG|r " .. msg)
    end
end

local function ensureDB()
    RaidRIPDB = RaidRIPDB or {}

    if RaidRIPDB.enabled == nil then
        RaidRIPDB.enabled = true
    end

    if RaidRIPDB.sync == nil then
        RaidRIPDB.sync = true
    end

    if RaidRIPDB.debug == nil then
        RaidRIPDB.debug = false
    end

    if not RaidRIPDB.defaultSound or RaidRIPDB.defaultSound == "" then
        RaidRIPDB.defaultSound = DEFAULT_SOUND
    else
        RaidRIPDB.defaultSound = normalizePath(RaidRIPDB.defaultSound)
    end

    if type(RaidRIPDB.sounds) ~= "table" then
        RaidRIPDB.sounds = {}
    else
        for name, path in pairs(RaidRIPDB.sounds) do
            RaidRIPDB.sounds[name] = normalizePath(path)
        end
    end

    return RaidRIPDB
end

local function cleanupRecentDeaths()
    local cutoff = now() - 15

    for key, stamp in pairs(recentDeaths) do
        if stamp < cutoff then
            recentDeaths[key] = nil
        end
    end
end

local function rebuildRoster()
    wipe(roster)
    wipe(guidToName)

    local player = shortName(UnitName("player"))
    if player then
        roster[player] = true
        local playerGuid = UnitGUID("player")
        if playerGuid then
            guidToName[playerGuid] = player
        end
    end

    if IsInRaid and IsInRaid() then
        local count = GetNumRaidMembers and GetNumRaidMembers() or 0
        for i = 1, count do
            local name = GetRaidRosterInfo(i)
            if name then
                local key = shortName(name)
                if key then
                    roster[key] = true
                end

                local unit = "raid" .. i
                local guid = UnitGUID(unit)
                if guid and key then
                    guidToName[guid] = key
                end
            end
        end
        return
    end

    if IsInGroup and IsInGroup() then
        local count = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, count do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local guid = UnitGUID(unit)
                if name then
                    local key = shortName(name)
                    if key then
                        roster[key] = true
                        if guid then
                            guidToName[guid] = key
                        end
                    end
                end
            end
        end
    end
end

local function registerPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        return
    end

    if RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
end

local function sendAddonMessage(message, channel)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, message, channel)
        return
    end

    if SendAddonMessage then
        SendAddonMessage(PREFIX, message, channel)
    end
end

local function getSoundForName(name)
    local db = RaidRIPDB
    local key = shortName(name)
    if not db or not key then
        return DEFAULT_SOUND
    end

    return normalizePath(db.sounds[key] or db.defaultSound or DEFAULT_SOUND)
end

local function playSoundForName(name)
    local sound = getSoundForName(name)
    if sound and sound ~= "" then
        debugMsg("play sound name=" .. tostring(shortName(name)) .. " file=" .. tostring(sound))
        local played = PlaySoundFile(sound)
        debugMsg("PlaySoundFile returned " .. tostring(played))
    else
        debugMsg("no sound found for name=" .. tostring(shortName(name)))
    end
end

local function trackedName(name)
    local key = shortName(name)
    return key and roster[key] or false
end

local function resolveNameFromGUID(guid, fallbackName)
    if guid and guidToName[guid] then
        return guidToName[guid]
    end

    if guid and UnitGUID("player") == guid then
        return shortName(UnitName("player"))
    end

    return shortName(fallbackName)
end

local function syncDeath(name, guid)
    local db = RaidRIPDB
    if not db or not db.sync then
        return
    end

    if not IsInGroup or not IsInGroup() then
        return
    end

    local channel = IsInRaid and IsInRaid() and "RAID" or "PARTY"
    local key = shortName(name)
    local payloadGuid = guid or key
    if not key or not payloadGuid then
        return
    end

    sendAddonMessage("D|" .. payloadGuid .. "|" .. key, channel)
end

local function handleDeath(name, guid, localEvent)
    local key = resolveNameFromGUID(guid, name)

    debugMsg(
        "resolve guid=" .. tostring(guid)
        .. " cached=" .. tostring(guid and guidToName[guid] or nil)
        .. " fallback=" .. tostring(shortName(name))
        .. " resolved=" .. tostring(key)
        .. " roster=" .. tostring(key and roster[key] or nil)
    )

    if not key or not roster[key] then
        return
    end

    local stamp = recentDeaths[key]
    local t = now()
    if stamp and (t - stamp) < 8 then
        return
    end

    recentDeaths[key] = t
    cleanupRecentDeaths()
    playSoundForName(key)

    if localEvent then
        syncDeath(key, guid)
    end
end

local function getCombatLogData(...)
    if CombatLogGetCurrentEventInfo then
        return CombatLogGetCurrentEventInfo()
    end

    return ...
end

local function handleCombatLog(...)
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName = getCombatLogData(...)

    if subevent == "UNIT_DIED" or subevent == "PARTY_KILL" then
        debugMsg(
            "subevent=" .. tostring(subevent)
            .. " source=" .. tostring(sourceName)
            .. " dest=" .. tostring(destName)
            .. " sourceGUID=" .. tostring(sourceGUID)
            .. " destGUID=" .. tostring(destGUID)
        )
        handleDeath(destName, destGUID, true)
    end
end

local function listSounds()
    printMsg("Mappings:")
    for name, path in pairs(RaidRIPDB.sounds) do
        printMsg(name .. " -> " .. path)
    end
    printMsg("Default -> " .. RaidRIPDB.defaultSound)
end

local function setSound(name, path)
    local key = shortName(name)
    if not key or not path or path == "" then
        return false
    end

    RaidRIPDB.sounds[key] = normalizePath(path)
    return true
end

local function clearSound(name)
    local key = shortName(name)
    if not key then
        return false
    end

    RaidRIPDB.sounds[key] = nil
    return true
end

local function syncMapping(targetName, path)
    if not RaidRIPDB.sync then
        return
    end

    if not IsInGroup or not IsInGroup() then
        return
    end

    local channel = IsInRaid and IsInRaid() and "RAID" or "PARTY"
    local key = shortName(targetName)
    if not key then
        return
    end

    sendAddonMessage("M|" .. key .. "|" .. (path or ""), channel)
end

local function handleAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or not message or message == "" then
        return
    end

    if not RaidRIPDB or not RaidRIPDB.enabled then
        return
    end

    local kind, a, b = strsplit("|", message)
    if kind == "D" then
        local guid = a
        local name = b
        if name and guid then
            handleDeath(name, guid, false)
        end
        return
    end

    if kind == "M" then
        local name = a
        local path = b
        if name and path and path ~= "" then
            RaidRIPDB.sounds[name] = path
        elseif name then
            RaidRIPDB.sounds[name] = nil
        end
    end
end

local function showHelp()
    printMsg("Commands:")
    printMsg("/rds help")
    printMsg("/rds test [name]")
    printMsg("/rds set <name> <sound path>")
    printMsg("/rds clear <name>")
    printMsg("/rds default <sound path>")
    printMsg("/rds enable | disable")
    printMsg("/rds sync on | off")
    printMsg("/rds debug on | off")
    printMsg("/rds list")
end

local function handleSlash(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""

    if cmd == "" or cmd == "help" then
        showHelp()
        return
    end

    if cmd == "enable" then
        RaidRIPDB.enabled = true
        printMsg("Enabled.")
        return
    end

    if cmd == "disable" then
        RaidRIPDB.enabled = false
        printMsg("Disabled.")
        return
    end

    if cmd == "sync" then
        local mode = rest:lower()
        if mode == "on" then
            RaidRIPDB.sync = true
            printMsg("Sync enabled.")
        elseif mode == "off" then
            RaidRIPDB.sync = false
            printMsg("Sync disabled.")
        else
            printMsg("Usage: /rds sync on|off")
        end
        return
    end

    if cmd == "debug" then
        local mode = rest:lower()
        if mode == "on" then
            RaidRIPDB.debug = true
            printMsg("Debug enabled.")
        elseif mode == "off" then
            RaidRIPDB.debug = false
            printMsg("Debug disabled.")
        else
            printMsg("Usage: /rds debug on|off")
            printMsg("Current: " .. (RaidRIPDB.debug and "on" or "off"))
        end
        return
    end

    if cmd == "default" then
        if rest == "" then
            printMsg("Usage: /rds default <sound path>")
            return
        end

        RaidRIPDB.defaultSound = rest
        RaidRIPDB.defaultSound = normalizePath(RaidRIPDB.defaultSound)
        printMsg("Default sound set.")
        return
    end

    if cmd == "set" then
        local name, path = rest:match("^(%S+)%s+(.+)$")
        if not name or not path then
            printMsg("Usage: /rds set <name> <sound path>")
            return
        end

        if setSound(name, path) then
            local normalized = normalizePath(path)
            syncMapping(name, normalized)
            printMsg("Mapped " .. shortName(name) .. " to " .. normalized)
        end
        return
    end

    if cmd == "clear" then
        if rest == "" then
            printMsg("Usage: /rds clear <name>")
            return
        end

        if clearSound(rest) then
            syncMapping(rest, nil)
            printMsg("Cleared mapping for " .. shortName(rest))
        end
        return
    end

    if cmd == "list" then
        listSounds()
        return
    end

    if cmd == "test" then
        local target = rest
        if target == "" then
            target = UnitName("player")
        end

        playSoundForName(target)
        return
    end

    printMsg("Unknown command. Use /rds help")
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        ensureDB()
        rebuildRoster()
        registerPrefix()

        if not SlashCmdList.RAIDRIP then
            SlashCmdList.RAIDRIP = handleSlash
            SLASH_RAIDRIP1 = "/rds"
        end

        printMsg("Loaded. Use /rds help.")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        rebuildRoster()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if RaidRIPDB and RaidRIPDB.enabled then
            handleCombatLog(...)
        end
        return
    end

    if event == "CHAT_MSG_ADDON" then
        handleAddonMessage(...)
    end
end)
