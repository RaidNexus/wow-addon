local addonName, RaidNexus = ...

RaidNexus = RaidNexus or {}
RaidNexus.name = addonName
RaidNexus.version = "0.2.31"
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

local MINIMAP_BUTTON_RADIUS = 5
local MINIMAP_BUTTON_SIZE = 31
local MINIMAP_ICON_SIZE = 23
local MINIMAP_BACKGROUND_SIZE = 24
local MINIMAP_RING_SIZE = 50
local MINIMAP_SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

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
    local x, y, quadrant = math.cos(angle), math.sin(angle), 1

    if x < 0 then
        quadrant = quadrant + 1
    end

    if y > 0 then
        quadrant = quadrant + 2
    end

    local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local shapeQuadrants = MINIMAP_SHAPES[minimapShape] or MINIMAP_SHAPES["ROUND"]
    local widthRadius = (Minimap:GetWidth() / 2) + MINIMAP_BUTTON_RADIUS
    local heightRadius = (Minimap:GetHeight() / 2) + MINIMAP_BUTTON_RADIUS

    if shapeQuadrants[quadrant] then
        x = x * widthRadius
        y = y * heightRadius
    else
        local diagonalWidth = math.sqrt(2 * (widthRadius ^ 2)) - 10
        local diagonalHeight = math.sqrt(2 * (heightRadius ^ 2)) - 10
        x = math.max(-widthRadius, math.min(x * diagonalWidth, widthRadius))
        y = math.max(-heightRadius, math.min(y * diagonalHeight, heightRadius))
    end

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

function RaidNexus:UpdateMinimapButtonVisibility()
    if not self.minimapButton then
        return
    end

    local hidden = RaidNexusDB and RaidNexusDB.minimap and RaidNexusDB.minimap.hide
    if hidden then
        self.minimapButton:Hide()
    else
        self.minimapButton:Show()
        self:UpdateMinimapButtonPosition()
    end
end

function RaidNexus:CreateMinimapButton()
    if self.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "RaidNexusMinimapButton", Minimap)
    button:SetSize(MINIMAP_BUTTON_SIZE, MINIMAP_BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(MINIMAP_BACKGROUND_SIZE, MINIMAP_BACKGROUND_SIZE)
    background:SetPoint("CENTER", button, "CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(MINIMAP_ICON_SIZE, MINIMAP_ICON_SIZE)
    icon:SetPoint("CENTER", button, "CENTER")
    icon:SetTexture(RaidNexus.minimapIconPath)
    icon:SetTexCoord(0, 1, 0, 1)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(MINIMAP_RING_SIZE, MINIMAP_RING_SIZE)
    border:SetPoint("TOPLEFT", button, "TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border = border

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button.highlight = highlight

    button:SetScript("OnClick", function(_, _)
        if button.wasDragged then
            button.wasDragged = nil
            return
        end

        RaidNexus.RosterExport:ToggleQuickPanel()
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
        GameTooltip:AddLine("Click: Open quick actions", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move minimap button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.minimapButton = button
    self:UpdateMinimapButtonVisibility()
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
        self:Print("/rnx simc - Open a SimulationCraft export for your character.")
        self:Print("/rnx combatlog - Show automatic combat logging status.")
        self:Print("/rnx - Open the quick action panel.")
        return
    end

    if command == "simc" then
        if self.SimCExport and self.SimCExport.HandleChatCommand then
            self.SimCExport:HandleChatCommand(rest)
        else
            self:Print("SimC export module is unavailable.")
        end
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

        if not (IsAddOnLoaded and IsAddOnLoaded("Simulationcraft"))
            and not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Simulationcraft")) then
            SLASH_RAIDNEXUSSIMC1 = "/simc"
            SlashCmdList.RAIDNEXUSSIMC = function(msg)
                if RaidNexus.SimCExport and RaidNexus.SimCExport.HandleChatCommand then
                    RaidNexus.SimCExport:HandleChatCommand(msg)
                else
                    RaidNexus:Print("SimC export module is unavailable.")
                end
            end
        end

        RaidNexus:Print("Loaded. Use /rnx roster or /rnx groups.")
    end
end)
