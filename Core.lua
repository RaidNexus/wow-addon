local addonName, RaidNexus = ...

RaidNexus = RaidNexus or {}
RaidNexus.name = addonName
RaidNexus.version = "0.1.0"
RaidNexus.minimapIconPath = "Interface\\AddOns\\RaidNexus\\RaidNexusIcon"

local defaultDb = {
    minimap = {
        angle = 225,
        hide = false,
    },
    combatLog = {
        enabled = true,
        autoEnableAdvanced = true,
        logRaids = true,
        logDungeons = true,
        logMythicPlus = true,
        stopDelaySecs = 30,
    },
}

local MINIMAP_BUTTON_RADIUS = 80

local function atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end

    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -(math.pi / 2)
    end

    return 0
end

function RaidNexus:Print(message)
    local prefix = "|cfff4b942RaidNexus|r"
    DEFAULT_CHAT_FRAME:AddMessage(string.format("%s %s", prefix, tostring(message)))
end

local function copyDefaults(target, defaults)
    if type(defaults) ~= "table" then
        return
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = target[key] or {}
            copyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function getMinimapPosition(angleDegrees)
    local angle = math.rad(angleDegrees or 225)
    local radius = MINIMAP_BUTTON_RADIUS
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    return x, y
end

function RaidNexus:UpdateMinimapButtonAngleFromCursor()
    if not self.minimapButton or not Minimap or not RaidNexusDB or not RaidNexusDB.minimap then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1
    local centerX, centerY = Minimap:GetCenter()

    if not centerX or not centerY then
        return
    end

    local angle = math.deg(atan2((cursorY / scale) - centerY, (cursorX / scale) - centerX))
    RaidNexusDB.minimap.angle = angle
    self:UpdateMinimapButtonPosition()
end

function RaidNexus:UpdateMinimapButtonPosition()
    if not self.minimapButton or not Minimap then
        return
    end

    local angle = RaidNexusDB and RaidNexusDB.minimap and RaidNexusDB.minimap.angle or 225
    local x, y = getMinimapPosition(angle)
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function RaidNexus:CreateMinimapButton()
    if self.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "RaidNexusMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture("Interface\\Minimap\\MiniMap-TrackingBackground")
    button.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER")
    icon:SetTexture(RaidNexus.minimapIconPath)
    icon:SetTexCoord(0, 1, 0, 1)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border = border

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button.highlight = highlight

    button:SetScript("OnClick", function(_, mouseButton)
        if button.wasDragged then
            button.wasDragged = nil
            return
        end

        if mouseButton == "RightButton" then
            RaidNexus.RosterExport:ToggleQuickPanel()
        else
            RaidNexus.RosterExport:CopyRoster()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self.dragStartX, self.dragStartY = GetCursorPosition()
        self.wasDragged = false
        self:SetScript("OnUpdate", function(dragButton)
            local currentX, currentY = GetCursorPosition()
            local deltaX = math.abs((currentX or 0) - (dragButton.dragStartX or 0))
            local deltaY = math.abs((currentY or 0) - (dragButton.dragStartY or 0))

            if deltaX > 4 or deltaY > 4 then
                dragButton.wasDragged = true
            end

            RaidNexus:UpdateMinimapButtonAngleFromCursor()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("RaidNexus", 1, 0.82, 0.2)
        GameTooltip:AddLine("Left-click: Copy raid roster", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move minimap button", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: Open quick actions", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.minimapButton = button
    self:UpdateMinimapButtonPosition()
end

function RaidNexus:HandleSlashCommand(message)
    local command, rest = (message or ""):match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")
    rest = rest or ""

    if command == "" then
        self.RosterExport:ToggleQuickPanel()
        return
    end

    if command == "roster" then
        self.RosterExport:CopyRoster()
        return
    end

    if command == "groups" then
        self.RosterExport:CopyGroups()
        return
    end

    if command == "help" then
        self:Print("/rnx roster - Copy all raid members, one per line.")
        self:Print("/rnx groups - Copy raid members grouped by raid group.")
        self:Print("/rnx combatlog - Show automatic combat logging status.")
        self:Print("/rnx - Open the quick action panel.")
        return
    end

    if command == "combatlog" then
        if self.CombatLog and self.CombatLog.HandleSlashCommand then
            self.CombatLog:HandleSlashCommand(rest)
        else
            self:Print("Combat logging module is unavailable.")
        end
        return
    end

    self:Print(string.format("Unknown command '%s'. Use /rnx help.", command))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        RaidNexusDB = RaidNexusDB or {}
        copyDefaults(RaidNexusDB, defaultDb)
        return
    end

    if event == "PLAYER_LOGIN" then
        RaidNexus:CreateMinimapButton()

        if RaidNexus.RosterExport and RaidNexus.RosterExport.EnsureQuickPanel then
            RaidNexus.RosterExport:EnsureQuickPanel()
        end

        SLASH_RAIDNEXUS1 = "/rnx"
        SlashCmdList.RAIDNEXUS = function(msg)
            RaidNexus:HandleSlashCommand(msg)
        end

        RaidNexus:Print("Loaded. Use /rnx roster or /rnx groups.")
    end
end)
