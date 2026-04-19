local addonName, RaidNexus = ...

RaidNexus = RaidNexus or {}
RaidNexus.RosterExport = RaidNexus.RosterExport or {}

local RosterExport = RaidNexus.RosterExport

local function shortName(name)
    if not name or name == "" then
        return nil
    end

    if Ambiguate then
        return Ambiguate(name, "short")
    end

    return name:match("^[^-]+") or name
end

local function createBackdrop(frame)
    if not BackdropTemplateMixin then
        return
    end

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        tile = true,
        tileSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.06, 0.09, 0.96)
    frame:SetBackdropBorderColor(0.85, 0.65, 0.15, 0.95)
end

function RosterExport:GetRaidMembers()
    if not IsInRaid() then
        return nil, "You're not in a raid group."
    end

    local members = {}
    local groupSize = GetNumGroupMembers() or 0

    for index = 1, groupSize do
        local name, _, subgroup = GetRaidRosterInfo(index)
        name = shortName(name)

        if name then
            members[#members + 1] = {
                name = name,
                subgroup = subgroup or 0,
                index = index,
            }
        end
    end

    table.sort(members, function(a, b)
        if a.subgroup == b.subgroup then
            return a.index < b.index
        end

        return a.subgroup < b.subgroup
    end)

    return members
end

function RosterExport:BuildRosterText()
    local members, err = self:GetRaidMembers()
    if not members then
        return nil, err
    end

    local names = {}
    for _, member in ipairs(members) do
        names[#names + 1] = member.name
    end

    return table.concat(names, "\n"), #names
end

function RosterExport:BuildGroupsText()
    local members, err = self:GetRaidMembers()
    if not members then
        return nil, err
    end

    local grouped = {}
    for _, member in ipairs(members) do
        grouped[member.subgroup] = grouped[member.subgroup] or {}
        table.insert(grouped[member.subgroup], member.name)
    end

    local lines = {}
    for subgroup = 1, 8 do
        local names = grouped[subgroup]
        if names and #names > 0 then
            lines[#lines + 1] = string.format("Group %d: %s", subgroup, table.concat(names, ", "))
        end
    end

    return table.concat(lines, "\n"), #members
end

function RosterExport:EnsureCopyFrame()
    if self.copyFrame then
        return self.copyFrame
    end

    local frame = CreateFrame("Frame", "RaidNexusCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(620, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    createBackdrop(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RaidNexus Export")
    frame.title = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -48)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Press Ctrl+C to copy the selected text, then paste it into RaidNexus.")
    frame.subtitle = subtitle

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    local scrollFrame = CreateFrame("ScrollFrame", "RaidNexusCopyScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 18)

    local editBox = CreateFrame("EditBox", "RaidNexusCopyEditBox", scrollFrame)
    editBox:SetAutoFocus(false)
    editBox:SetMultiLine(true)
    editBox:EnableMouse(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(540)
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    editBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        self:HighlightText()
    end)
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    self.copyFrame = frame
    return frame
end

function RosterExport:ShowCopyFrame(title, text)
    local frame = self:EnsureCopyFrame()
    frame.title:SetText(title or "RaidNexus Export")
    frame.editBox:SetText(text or "")
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
    frame:Show()
end

function RosterExport:CopyRoster()
    local text, countOrError = self:BuildRosterText()
    if not text then
        RaidNexus:Print(countOrError)
        return
    end

    self:ShowCopyFrame("Raid Roster", text)
    RaidNexus:Print(string.format("Prepared %d raid members. Press Ctrl+C in the popup.", countOrError))
end

function RosterExport:CopyGroups()
    local text, countOrError = self:BuildGroupsText()
    if not text then
        RaidNexus:Print(countOrError)
        return
    end

    self:ShowCopyFrame("Raid Groups", text)
    RaidNexus:Print(string.format("Prepared %d raid members grouped by party. Press Ctrl+C in the popup.", countOrError))
end

function RosterExport:EnsureQuickPanel()
    if self.quickPanel then
        return self.quickPanel
    end

    local frame = CreateFrame("Frame", "RaidNexusQuickPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(220, 132)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    createBackdrop(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("RaidNexus")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -20)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Quick export tools for your current raid.")

    local rosterButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    rosterButton:SetSize(184, 24)
    rosterButton:SetPoint("TOP", frame, "TOP", 0, -52)
    rosterButton:SetText("Copy Roster")
    rosterButton:SetScript("OnClick", function()
        self:CopyRoster()
    end)

    local groupsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    groupsButton:SetSize(184, 24)
    groupsButton:SetPoint("TOP", rosterButton, "BOTTOM", 0, -8)
    groupsButton:SetText("Copy Groups")
    groupsButton:SetScript("OnClick", function()
        self:CopyGroups()
    end)

    self.quickPanel = frame
    return frame
end

function RosterExport:ToggleQuickPanel()
    local panel = self:EnsureQuickPanel()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end
