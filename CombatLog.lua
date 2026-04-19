local addonName, RaidNexus = ...

RaidNexus = RaidNexus or {}
RaidNexus.CombatLog = RaidNexus.CombatLog or {}

local CombatLog = RaidNexus.CombatLog
local loggingActive = false

local defaults = {
    enabled = true,
    autoEnableAdvanced = true,
    logRaids = true,
    logDungeons = true,
    logMythicPlus = true,
    stopDelaySecs = 30,
}

local function shortName(name)
    if not name or name == "" then
        return nil
    end

    if Ambiguate then
        return Ambiguate(name, "short")
    end

    return name:match("^[^-]+") or name
end

local function getSettings()
    RaidNexusDB = RaidNexusDB or {}
    RaidNexusDB.combatLog = RaidNexusDB.combatLog or {}

    for key, value in pairs(defaults) do
        if RaidNexusDB.combatLog[key] == nil then
            RaidNexusDB.combatLog[key] = value
        end
    end

    return RaidNexusDB.combatLog
end

local function isAdvancedCombatLoggingEnabled()
    return tonumber(GetCVar("advancedCombatLogging") or "0") == 1
end

local function isChallengeModeActive()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
end

function CombatLog:CancelStopTimer()
    if self.stopTimer and self.stopTimer.Cancel then
        self.stopTimer:Cancel()
    end
    self.stopTimer = nil
end

function CombatLog:GetContext()
    local _, instanceType, difficultyID, difficultyName, _, _, _, _, groupSize = GetInstanceInfo()
    local settings = getSettings()
    local challengeMode = isChallengeModeActive()
    local shouldLog = false
    local reason = "unsupported"

    if not settings.enabled then
        reason = "disabled"
    elseif instanceType == "raid" and settings.logRaids then
        shouldLog = true
        reason = "raid"
    elseif instanceType == "party" and challengeMode and settings.logMythicPlus then
        shouldLog = true
        reason = "mythic_plus"
    elseif instanceType == "party" and settings.logDungeons then
        shouldLog = true
        reason = "dungeon"
    end

    return {
        shouldLog = shouldLog,
        reason = reason,
        instanceType = instanceType or "",
        difficultyID = difficultyID,
        difficultyName = difficultyName or "Unknown",
        challengeMode = challengeMode,
        groupSize = groupSize or 0,
    }
end

function CombatLog:ApplyAdvancedCombatLogging()
    local settings = getSettings()
    if not settings.autoEnableAdvanced or isAdvancedCombatLoggingEnabled() then
        return
    end

    SetCVar("advancedCombatLogging", "1")
    if RaidNexus and RaidNexus.Print then
        RaidNexus:Print("Enabled Advanced Combat Logging automatically.")
    end
end

function CombatLog:StartLogging(context)
    self:CancelStopTimer()
    self:ApplyAdvancedCombatLogging()

    if loggingActive then
        self.autoStarted = true
        return
    end

    LoggingCombat(true)
    loggingActive = true
    self.autoStarted = true

    if RaidNexus and RaidNexus.Print then
        local difficulty = context and context.difficultyName or "encounter"
        RaidNexus:Print(string.format("Combat logging enabled for %s.", difficulty))
    end
end

function CombatLog:StopLogging(reason)
    self:CancelStopTimer()

    if not self.autoStarted then
        return
    end

    if loggingActive then
        LoggingCombat(false)
        loggingActive = false
    end

    self.autoStarted = false

    if RaidNexus and RaidNexus.Print then
        RaidNexus:Print(string.format("Combat logging stopped (%s).", reason or "left supported content"))
    end
end

function CombatLog:ScheduleStop(context)
    self:CancelStopTimer()

    if not self.autoStarted then
        return
    end

    local settings = getSettings()
    local delay = tonumber(settings.stopDelaySecs or defaults.stopDelaySecs) or defaults.stopDelaySecs
    if delay <= 0 or not C_Timer or not C_Timer.NewTimer then
        self:StopLogging(context and context.reason or "unsupported")
        return
    end

    self.stopTimer = C_Timer.NewTimer(delay, function()
        self.stopTimer = nil
        local nextContext = self:GetContext()
        if not nextContext.shouldLog then
            self:StopLogging(nextContext.reason)
        end
    end)
end

function CombatLog:RefreshLoggingState(reason)
    local context = self:GetContext()

    if context.shouldLog then
        self:StartLogging(context)
    else
        self:ScheduleStop(context)
    end
end

function CombatLog:GetStatusLines()
    local context = self:GetContext()
    local lines = {
        string.format("Logging: %s", loggingActive and "On" or "Off"),
        string.format("Mode: %s", self.autoStarted and "Managed by RaidNexus" or "Manual / inactive"),
        string.format("Advanced Combat Logging: %s", isAdvancedCombatLoggingEnabled() and "Enabled" or "Disabled"),
        string.format(
            "Detected content: %s (%s)",
            context.instanceType ~= "" and context.instanceType or "world",
            context.difficultyName
        ),
    }

    if context.challengeMode then
        lines[#lines + 1] = "Mythic+: active"
    end

    lines[#lines + 1] = string.format("Auto logging target: %s", context.shouldLog and context.reason or "off")
    return lines
end

function CombatLog:HandleSlashCommand(message)
    local command = string.lower((message or ""):match("^(%S+)") or "")
    local settings = getSettings()

    if command == "" or command == "status" then
        for _, line in ipairs(self:GetStatusLines()) do
            RaidNexus:Print(line)
        end
        return
    end

    if command == "on" then
        settings.enabled = true
        self:RefreshLoggingState("slash_on")
        RaidNexus:Print("Automatic combat logging is enabled.")
        return
    end

    if command == "off" then
        settings.enabled = false
        self:StopLogging("disabled")
        RaidNexus:Print("Automatic combat logging is disabled.")
        return
    end

    if command == "toggle" then
        settings.enabled = not settings.enabled
        if settings.enabled then
            self:RefreshLoggingState("slash_toggle")
        else
            self:StopLogging("disabled")
        end
        RaidNexus:Print(string.format(
            "Automatic combat logging is %s.",
            settings.enabled and "enabled" or "disabled"
        ))
        return
    end

    RaidNexus:Print("/rnx combatlog - Show combat logging status.")
    RaidNexus:Print("/rnx combatlog on - Enable automatic combat logging.")
    RaidNexus:Print("/rnx combatlog off - Disable automatic combat logging.")
end

if hooksecurefunc then
    hooksecurefunc("LoggingCombat", function(state)
        if state == nil then
            return
        end

        loggingActive = state == true or state == 1
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        CombatLog:ApplyAdvancedCombatLogging()
    end

    CombatLog:RefreshLoggingState(event)
end)
