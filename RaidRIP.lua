local ADDON_NAME = ...
local PREFIX = "RAIDRIP"
local DEFAULT_SOUND = "Sound\\Interface\\RaidWarning.ogg"

local frame = CreateFrame("Frame")
local roster = {}
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

local function printMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00d1ffRaidRIP|r: " .. msg)
end

local function ensureDB()
    RaidRIPDB = RaidRIPDB or {}

    if RaidRIPDB.enabled == nil then
        RaidRIPDB.enabled = true
    end

    if RaidRIPDB.sync == nil then
        RaidRIPDB.sync = true
    end

    if not RaidRIPDB.defaultSound or RaidRIPDB.defaultSound == "" then
        RaidRIPDB.defaultSound = DEFAULT_SOUND
    end

    if type(RaidRIPDB.sounds) ~= "table" then
        RaidRIPDB.sounds = {}
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

    local player = shortName(UnitName("player"))
    if player then
        roster[player] = true
    end

    if IsInRaid and IsInRaid() then
        local count = GetNumRaidMembers and GetNumRaidMembers() or 0
        for i = 1, count do
            local name = GetRaidRosterInfo(i)
            if name then
                roster[shortName(name)] = true
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
                if name then
                    roster[shortName(name)] = true
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

    return db.sounds[key] or db.defaultSound or DEFAULT_SOUND
end

local function playSoundForName(name)
    local sound = getSoundForName(name)
    if sound and sound ~= "" then
        PlaySoundFile(sound)
    end
end

local function trackedName(name)
    local key = shortName(name)
    return key and roster[key] or false
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
    if not trackedName(name) then
        return
    end

    local key = guid or shortName(name)
    if not key then
        return
    end

    local stamp = recentDeaths[key]
    local t = now()
    if stamp and (t - stamp) < 8 then
        return
    end

    recentDeaths[key] = t
    cleanupRecentDeaths()
    playSoundForName(name)

    if localEvent then
        syncDeath(name, guid)
    end
end

local function handleCombatLog(...)
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName = ...

    if subevent == "UNIT_DIED" or subevent == "PARTY_KILL" then
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

    RaidRIPDB.sounds[key] = path
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

    if cmd == "default" then
        if rest == "" then
            printMsg("Usage: /rds default <sound path>")
            return
        end

        RaidRIPDB.defaultSound = rest
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
            syncMapping(name, path)
            printMsg("Mapped " .. shortName(name) .. " to " .. path)
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
