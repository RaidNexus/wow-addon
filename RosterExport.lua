local addonName, RaidNexus = ...

RaidNexus = RaidNexus or {}
RaidNexus.RosterExport = RaidNexus.RosterExport or {}

local RosterExport = RaidNexus.RosterExport

local FRONTLINE_GROUP_MIN = 1
local FRONTLINE_GROUP_MAX = 4
local BENCH_GROUP_MIN = 5
local BENCH_GROUP_MAX = 8
local MAX_MEMBERS_PER_GROUP = 5
local MAX_FRONTLINE_MEMBERS = 20
local MAX_SIMULATED_MOVES = 40

local function shortName(name)
    if not name or name == "" then
        return nil
    end

    if Ambiguate then
        return Ambiguate(name, "short")
    end

    return name:match("^[^-]+") or name
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeLookupName(name)
    local cleaned = trim(name)
    cleaned = cleaned:gsub("%s*%-%s*", "-")
    return string.lower(cleaned)
end

local function buildFullName(name, realm)
    local baseName = trim(name)
    local realmName = trim(realm)

    if baseName == "" then
        return nil
    end

    if realmName == "" then
        return baseName
    end

    return string.format("%s-%s", baseName, realmName)
end

local function stripRealm(name)
    local cleaned = trim(name)
    return cleaned:match("^[^-]+") or cleaned
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

local function isFrontlineGroup(subgroup)
    return subgroup and subgroup >= FRONTLINE_GROUP_MIN and subgroup <= FRONTLINE_GROUP_MAX
end

local function isBenchGroup(subgroup)
    return subgroup and subgroup >= BENCH_GROUP_MIN and subgroup <= BENCH_GROUP_MAX
end

local function sortMembersByGroupAndIndex(members)
    table.sort(members, function(a, b)
        if (a.subgroup or 0) == (b.subgroup or 0) then
            return (a.index or 0) < (b.index or 0)
        end

        return (a.subgroup or 0) < (b.subgroup or 0)
    end)
end

local function copyMember(member)
    return {
        name = member.name,
        shortName = member.shortName,
        fullName = member.fullName,
        subgroup = member.subgroup,
        index = member.index,
    }
end

local function describeMember(member)
    local label = member.name or member.shortName or member.fullName or "Unknown"
    local subgroup = member.subgroup or 0
    return string.format("%s (Group %d)", label, subgroup)
end

local function estimateEditBoxHeight(editBox, minHeight)
    local _, lineHeight = editBox:GetFont()
    local text = tostring(editBox:GetText() or "")
    local lineCount = 1

    for _ in string.gmatch(text, "\n") do
        lineCount = lineCount + 1
    end

    return math.max(minHeight, math.ceil((lineHeight or 14) * lineCount + 20))
end

function RosterExport:GetRaidMembers()
    if not IsInRaid() then
        return nil, "You're not in a raid group."
    end

    local members = {}
    local groupSize = GetNumGroupMembers() or 0

    for index = 1, groupSize do
        local unit = "raid" .. index
        local rawName, _, subgroup = GetRaidRosterInfo(index)
        local unitName, unitRealm

        if UnitFullName then
            unitName, unitRealm = UnitFullName(unit)
        end

        local fullName = buildFullName(unitName, unitRealm) or rawName
        local displayName = shortName(fullName or rawName)

        if displayName then
            members[#members + 1] = {
                name = displayName,
                shortName = displayName,
                fullName = fullName or rawName or displayName,
                subgroup = subgroup or 0,
                index = index,
            }
        end
    end

    sortMembersByGroupAndIndex(members)
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

function RosterExport:ParseFrontlineImportText(text)
    local tokens = {}
    local source = tostring(text or "")

    for line in string.gmatch(source .. "\n", "(.-)\n") do
        local cleanedLine = trim(line)
        if cleanedLine ~= "" then
            local groupContent = cleanedLine:match("^[Gg]roup%s+[1-8]%s*:%s*(.+)$")
            local tokenSource = groupContent or cleanedLine
            local foundSplit = false

            for piece in string.gmatch(tokenSource, "[^,;]+") do
                foundSplit = true
                local token = trim(piece)
                token = token:gsub("^%d+[%.)]%s*", "")
                token = token:gsub("^[-*]%s*", "")
                token = token:gsub("^%[[ xX]?%]%s*", "")
                token = token:gsub("%s*%-%s*", "-")
                token = trim(token)
                if token ~= "" then
                    tokens[#tokens + 1] = token
                end
            end

            if not foundSplit and tokenSource ~= "" then
                tokens[#tokens + 1] = tokenSource
            end
        end
    end

    return tokens
end

function RosterExport:ResolveDesiredFrontlineMembers(text, members)
    local requested = self:ParseFrontlineImportText(text)
    if #requested == 0 then
        return nil, "Paste the boss roster first."
    end

    local byFullName = {}
    local byShortName = {}
    local ambiguousShortNames = {}

    for _, member in ipairs(members) do
        local fullKey = normalizeLookupName(member.fullName)
        local shortKey = normalizeLookupName(member.shortName or member.name)

        if fullKey ~= "" then
            byFullName[fullKey] = member
        end

        if shortKey ~= "" then
            if byShortName[shortKey] and byShortName[shortKey].fullName ~= member.fullName then
                ambiguousShortNames[shortKey] = true
                byShortName[shortKey] = nil
            elseif not ambiguousShortNames[shortKey] then
                byShortName[shortKey] = member
            end
        end
    end

    local desiredFullNames = {}
    local desiredSet = {}
    local missing = {}
    local ambiguous = {}

    for _, requestedName in ipairs(requested) do
        local key = normalizeLookupName(requestedName)
        if key ~= "" then
            local member = byFullName[key]
            local shortKey = normalizeLookupName(stripRealm(requestedName))

            if not member then
                if ambiguousShortNames[key] then
                    ambiguous[#ambiguous + 1] = requestedName
                else
                    member = byShortName[key]
                end
            end

            if not member and shortKey ~= "" and shortKey ~= key then
                if ambiguousShortNames[shortKey] then
                    ambiguous[#ambiguous + 1] = requestedName
                else
                    member = byShortName[shortKey]
                end
            end

            if member then
                local resolvedKey = normalizeLookupName(member.fullName)
                if not desiredSet[resolvedKey] then
                    desiredSet[resolvedKey] = true
                    desiredFullNames[#desiredFullNames + 1] = member.fullName
                end
            elseif not ambiguousShortNames[key] then
                missing[#missing + 1] = requestedName
            end
        end
    end

    if #desiredFullNames == 0 then
        return nil, "None of the pasted names matched the current raid roster."
    end

    return {
        requested = requested,
        desiredFullNames = desiredFullNames,
        desiredSet = desiredSet,
        missing = missing,
        ambiguous = ambiguous,
    }
end

function RosterExport:BuildFrontlineStatus(members, desiredFullNames, desiredSet)
    local status = {
        desiredInFront = {},
        undesiredInFront = {},
        desiredInBack = {},
        desiredMissing = {},
        countsByGroup = {},
    }

    local liveByFullName = {}

    for subgroup = 1, 8 do
        status.countsByGroup[subgroup] = 0
    end

    for _, member in ipairs(members) do
        local fullKey = normalizeLookupName(member.fullName)
        liveByFullName[fullKey] = member

        if member.subgroup and status.countsByGroup[member.subgroup] ~= nil then
            status.countsByGroup[member.subgroup] = status.countsByGroup[member.subgroup] + 1
        end

        if desiredSet[fullKey] then
            if isFrontlineGroup(member.subgroup) then
                status.desiredInFront[#status.desiredInFront + 1] = member
            elseif isBenchGroup(member.subgroup) then
                status.desiredInBack[#status.desiredInBack + 1] = member
            end
        elseif isFrontlineGroup(member.subgroup) then
            status.undesiredInFront[#status.undesiredInFront + 1] = member
        end
    end

    for _, fullName in ipairs(desiredFullNames) do
        local key = normalizeLookupName(fullName)
        if not liveByFullName[key] then
            status.desiredMissing[#status.desiredMissing + 1] = fullName
        end
    end

    sortMembersByGroupAndIndex(status.desiredInFront)
    sortMembersByGroupAndIndex(status.undesiredInFront)
    sortMembersByGroupAndIndex(status.desiredInBack)

    return status
end

function RosterExport:FindAvailableGroup(members, minGroup, maxGroup)
    local counts = {}

    for subgroup = minGroup, maxGroup do
        counts[subgroup] = 0
    end

    for _, member in ipairs(members) do
        if member.subgroup and counts[member.subgroup] ~= nil then
            counts[member.subgroup] = counts[member.subgroup] + 1
        end
    end

    for subgroup = minGroup, maxGroup do
        if counts[subgroup] < MAX_MEMBERS_PER_GROUP then
            return subgroup
        end
    end

    return nil
end

function RosterExport:BuildNextFrontlineMove(members, desiredFullNames, desiredSet)
    local status = self:BuildFrontlineStatus(members, desiredFullNames, desiredSet)

    if #status.desiredMissing > 0 then
        return {
            kind = "blocked",
            reason = string.format(
                "Missing from raid: %s",
                table.concat(status.desiredMissing, ", ")
            ),
        }
    end

    if #status.undesiredInFront == 0 and #status.desiredInBack == 0 then
        return {
            kind = "done",
            status = status,
        }
    end

    if #status.undesiredInFront > 0 and #status.desiredInBack > 0 then
        local source = status.undesiredInFront[1]
        local target = status.desiredInBack[1]
        return {
            kind = "swap",
            source = source,
            target = target,
            description = string.format(
                "Swap %s with %s",
                describeMember(source),
                describeMember(target)
            ),
            status = status,
        }
    end

    if #status.desiredInBack > 0 then
        local targetGroup = self:FindAvailableGroup(members, FRONTLINE_GROUP_MIN, FRONTLINE_GROUP_MAX)
        if targetGroup then
            local member = status.desiredInBack[1]
            return {
                kind = "set",
                member = member,
                targetGroup = targetGroup,
                description = string.format(
                    "Move %s to Group %d",
                    describeMember(member),
                    targetGroup
                ),
                status = status,
            }
        end
    end

    if #status.undesiredInFront > 0 then
        local targetGroup = self:FindAvailableGroup(members, BENCH_GROUP_MIN, BENCH_GROUP_MAX)
        if targetGroup then
            local member = status.undesiredInFront[1]
            return {
                kind = "set",
                member = member,
                targetGroup = targetGroup,
                description = string.format(
                    "Move %s to Group %d",
                    describeMember(member),
                    targetGroup
                ),
                status = status,
            }
        end
    end

    return {
        kind = "blocked",
        reason = "No legal subgroup move is available. Check that groups 5-8 have space.",
        status = status,
    }
end

function RosterExport:SimulateFrontlinePlan(members, desiredFullNames, desiredSet)
    local simulatedMembers = {}
    for index, member in ipairs(members) do
        simulatedMembers[index] = copyMember(member)
    end

    local steps = {}

    for _ = 1, MAX_SIMULATED_MOVES do
        local move = self:BuildNextFrontlineMove(simulatedMembers, desiredFullNames, desiredSet)
        if move.kind == "done" or move.kind == "blocked" then
            return {
                finalMove = move,
                steps = steps,
            }
        end

        steps[#steps + 1] = move.description

        if move.kind == "swap" then
            local sourceKey = normalizeLookupName(move.source.fullName)
            local targetKey = normalizeLookupName(move.target.fullName)
            local sourceMember
            local targetMember

            for _, member in ipairs(simulatedMembers) do
                local memberKey = normalizeLookupName(member.fullName)
                if memberKey == sourceKey then
                    sourceMember = member
                elseif memberKey == targetKey then
                    targetMember = member
                end
            end

            if sourceMember and targetMember then
                local subgroup = sourceMember.subgroup
                sourceMember.subgroup = targetMember.subgroup
                targetMember.subgroup = subgroup
            end
        elseif move.kind == "set" then
            local memberKey = normalizeLookupName(move.member.fullName)
            for _, member in ipairs(simulatedMembers) do
                if normalizeLookupName(member.fullName) == memberKey then
                    member.subgroup = move.targetGroup
                    break
                end
            end
        end

        sortMembersByGroupAndIndex(simulatedMembers)
    end

    return {
        finalMove = {
            kind = "blocked",
            reason = "Preview exceeded the maximum move count. Trim the imported roster and try again.",
        },
        steps = steps,
    }
end

function RosterExport:AnalyzeFrontlineText(text)
    local members, err = self:GetRaidMembers()
    if not members then
        return {
            ok = false,
            previewText = err,
        }
    end

    local resolved, resolveErr = self:ResolveDesiredFrontlineMembers(text, members)
    if not resolved then
        return {
            ok = false,
            previewText = resolveErr,
        }
    end

    local lines = {}
    lines[#lines + 1] = string.format("Desired frontline roster: %d player(s)", #resolved.desiredFullNames)

    if #resolved.desiredFullNames > MAX_FRONTLINE_MEMBERS then
        lines[#lines + 1] = string.format(
            "Too many players selected for groups 1-4. Mythic frontline max is %d.",
            MAX_FRONTLINE_MEMBERS
        )
    end

    if #resolved.missing > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Not found in the current raid:"
        for _, name in ipairs(resolved.missing) do
            lines[#lines + 1] = string.format("- %s", name)
        end
    end

    if #resolved.ambiguous > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Ambiguous short names. Paste full Name-Realm for:"
        for _, name in ipairs(resolved.ambiguous) do
            lines[#lines + 1] = string.format("- %s", name)
        end
    end

    local status = self:BuildFrontlineStatus(
        members,
        resolved.desiredFullNames,
        resolved.desiredSet
    )

    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(
        "Already correct in groups 1-4: %d",
        #status.desiredInFront
    )
    lines[#lines + 1] = string.format(
        "Need to move up from groups 5-8: %d",
        #status.desiredInBack
    )
    lines[#lines + 1] = string.format(
        "Need to move out of groups 1-4: %d",
        #status.undesiredInFront
    )

    if #status.desiredInBack > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Desired players currently in groups 5-8:"
        for _, member in ipairs(status.desiredInBack) do
            lines[#lines + 1] = string.format("- %s", describeMember(member))
        end
    end

    if #status.undesiredInFront > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Players currently in groups 1-4 who should move out:"
        for _, member in ipairs(status.undesiredInFront) do
            lines[#lines + 1] = string.format("- %s", describeMember(member))
        end
    end

    local simulation = self:SimulateFrontlinePlan(
        members,
        resolved.desiredFullNames,
        resolved.desiredSet
    )

    if #simulation.steps > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("Planned moves: %d", #simulation.steps)
        for index, description in ipairs(simulation.steps) do
            lines[#lines + 1] = string.format("%d. %s", index, description)
        end
    else
        lines[#lines + 1] = ""
        lines[#lines + 1] = "No subgroup moves needed."
    end

    if simulation.finalMove.kind == "blocked" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("Blocked: %s", simulation.finalMove.reason or "Unknown reason.")
    end

    local canApply =
        #resolved.desiredFullNames > 0
        and #resolved.desiredFullNames <= MAX_FRONTLINE_MEMBERS
        and #resolved.missing == 0
        and #resolved.ambiguous == 0
        and simulation.finalMove.kind ~= "blocked"

    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "You must be the raid leader or an assistant to apply subgroup moves."
    end

    if InCombatLockdown and InCombatLockdown() then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Leave combat before applying subgroup moves."
    end

    return {
        ok = canApply,
        previewText = table.concat(lines, "\n"),
        desiredFullNames = resolved.desiredFullNames,
        desiredSet = resolved.desiredSet,
    }
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

function RosterExport:EnsureFrontlineFrame()
    if self.frontlineFrame then
        return self.frontlineFrame
    end

    local frame = CreateFrame("Frame", "RaidNexusFrontlineFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(760, 560)
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
    title:SetText("RaidNexus Frontline Groups")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -48)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Paste the boss roster from RaidNexus. Preview who belongs in groups 1-4, then apply subgroup moves.")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    local inputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    inputLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    inputLabel:SetText("Imported boss roster")

    local inputScrollFrame = CreateFrame("ScrollFrame", "RaidNexusFrontlineInputScrollFrame", frame, "UIPanelScrollFrameTemplate")
    inputScrollFrame:SetPoint("TOPLEFT", inputLabel, "BOTTOMLEFT", 0, -8)
    inputScrollFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -88)
    inputScrollFrame:SetHeight(150)

    local inputContent = CreateFrame("Frame", nil, inputScrollFrame)
    inputContent:SetSize(690, 150)
    inputContent:EnableMouse(true)
    inputScrollFrame:SetScrollChild(inputContent)

    local inputEditBox = CreateFrame("EditBox", "RaidNexusFrontlineInputEditBox", inputContent)
    inputEditBox:SetPoint("TOPLEFT", inputContent, "TOPLEFT", 4, -4)
    inputEditBox:SetWidth(672)
    inputEditBox:SetHeight(150)
    inputEditBox:SetAutoFocus(false)
    inputEditBox:SetMultiLine(true)
    inputEditBox:EnableMouse(true)
    inputEditBox:SetFontObject(ChatFontNormal)
    inputEditBox:SetTextInsets(0, 0, 0, 0)
    inputContent:SetScript("OnMouseDown", function()
        inputEditBox:SetFocus()
    end)
    inputEditBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
    end)
    inputEditBox:SetScript("OnTextChanged", function(self)
        local contentHeight = estimateEditBoxHeight(self, 150)
        self:SetHeight(contentHeight)
        inputContent:SetHeight(contentHeight)
    end)
    inputEditBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    inputEditBox:SetText("")
    frame.inputEditBox = inputEditBox

    local previewLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewLabel:SetPoint("TOPLEFT", inputScrollFrame, "BOTTOMLEFT", 0, -16)
    previewLabel:SetText("Preview")

    local previewScrollFrame = CreateFrame("ScrollFrame", "RaidNexusFrontlinePreviewScrollFrame", frame, "UIPanelScrollFrameTemplate")
    previewScrollFrame:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 0, -8)
    previewScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 54)

    local previewContent = CreateFrame("Frame", nil, previewScrollFrame)
    previewContent:SetSize(690, 240)
    previewContent:EnableMouse(true)
    previewScrollFrame:SetScrollChild(previewContent)

    local previewEditBox = CreateFrame("EditBox", "RaidNexusFrontlinePreviewEditBox", previewContent)
    previewEditBox:SetPoint("TOPLEFT", previewContent, "TOPLEFT", 4, -4)
    previewEditBox:SetWidth(672)
    previewEditBox:SetHeight(240)
    previewEditBox:SetAutoFocus(false)
    previewEditBox:SetMultiLine(true)
    previewEditBox:EnableMouse(true)
    previewEditBox:SetFontObject(ChatFontNormal)
    previewEditBox:SetTextInsets(0, 0, 0, 0)
    previewContent:SetScript("OnMouseDown", function()
        previewEditBox:SetFocus()
    end)
    previewEditBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
    end)
    previewEditBox:SetScript("OnTextChanged", function(self)
        local contentHeight = estimateEditBoxHeight(self, 240)
        self:SetHeight(contentHeight)
        previewContent:SetHeight(contentHeight)
    end)
    previewEditBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    previewEditBox:SetText("")
    frame.previewEditBox = previewEditBox

    local previewButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    previewButton:SetSize(110, 24)
    previewButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    previewButton:SetText("Preview")
    previewButton:SetScript("OnClick", function()
        self:PreviewFrontlinePlan()
    end)

    local applyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyButton:SetSize(154, 24)
    applyButton:SetPoint("LEFT", previewButton, "RIGHT", 10, 0)
    applyButton:SetText("Apply to Groups 1-4")
    applyButton:SetScript("OnClick", function()
        self:StartFrontlineApply(frame.inputEditBox:GetText())
    end)
    frame.applyButton = applyButton

    local stopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopButton:SetSize(90, 24)
    stopButton:SetPoint("LEFT", applyButton, "RIGHT", 10, 0)
    stopButton:SetText("Stop")
    stopButton:SetScript("OnClick", function()
        self:CancelFrontlineApply("Stopped the pending subgroup sort.")
    end)
    stopButton:SetEnabled(false)
    frame.stopButton = stopButton

    self.frontlineFrame = frame
    return frame
end

function RosterExport:ShowFrontlineSorter()
    local frame = self:EnsureFrontlineFrame()
    frame:Show()
    frame.inputEditBox:SetFocus()
    self:PreviewFrontlinePlan()
end

function RosterExport:PreviewFrontlinePlan()
    local frame = self:EnsureFrontlineFrame()
    local analysis = self:AnalyzeFrontlineText(frame.inputEditBox:GetText())
    frame.previewEditBox:SetText(analysis.previewText or "")

    local canApply =
        analysis.ok
        and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
        and not (InCombatLockdown and InCombatLockdown())

    frame.applyButton:SetEnabled(canApply)
    if frame.stopButton then
        frame.stopButton:SetEnabled(self.frontlineApplyState ~= nil)
    end
end

function RosterExport:CancelFrontlineApply(message)
    self.frontlineApplyState = nil

    if message then
        RaidNexus:Print(message)
    end

    if self.frontlineFrame and self.frontlineFrame:IsShown() then
        self:PreviewFrontlinePlan()
    elseif self.frontlineFrame and self.frontlineFrame.stopButton then
        self.frontlineFrame.stopButton:SetEnabled(false)
    end
end

function RosterExport:ContinueFrontlineApply()
    local state = self.frontlineApplyState
    if not state or state.moveInFlight then
        return
    end

    if not IsInRaid() then
        self:CancelFrontlineApply("Raid group lost before subgroup sorting could finish.")
        return
    end

    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        self:CancelFrontlineApply("You need raid lead or assist to keep moving groups.")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        self:CancelFrontlineApply("Leave combat before applying subgroup moves.")
        return
    end

    local members, err = self:GetRaidMembers()
    if not members then
        self:CancelFrontlineApply(err)
        return
    end

    local move = self:BuildNextFrontlineMove(members, state.desiredFullNames, state.desiredSet)
    if move.kind == "done" then
        self:CancelFrontlineApply(string.format(
            "Frontline groups sorted. Applied %d move(s).",
            state.movesApplied or 0
        ))
        return
    end

    if move.kind == "blocked" then
        self:CancelFrontlineApply(string.format(
            "Couldn't finish subgroup sorting: %s",
            move.reason or "Unknown reason."
        ))
        return
    end

    state.movesApplied = (state.movesApplied or 0) + 1
    state.moveInFlight = true

    if move.kind == "swap" then
        SwapRaidSubgroup(move.source.index, move.target.index)
    elseif move.kind == "set" then
        SetRaidSubgroup(move.member.index, move.targetGroup)
    end

    if self.frontlineFrame and self.frontlineFrame:IsShown() then
        self.frontlineFrame.previewEditBox:SetText(string.format(
            "Applying move %d...\n%s",
            state.movesApplied,
            move.description or "Updating raid groups."
        ))
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            if self.frontlineApplyState == state and state.moveInFlight then
                state.moveInFlight = false
                self:ContinueFrontlineApply()
            end
        end)
    end
end

function RosterExport:StartFrontlineApply(text)
    local analysis = self:AnalyzeFrontlineText(text)
    if not analysis.ok then
        if self.frontlineFrame and self.frontlineFrame:IsShown() then
            self.frontlineFrame.previewEditBox:SetText(analysis.previewText or "")
            self.frontlineFrame.applyButton:SetEnabled(false)
        end
        RaidNexus:Print("Fix the import preview before applying subgroup moves.")
        return
    end

    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        RaidNexus:Print("You must be the raid leader or an assistant to move players between groups.")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        RaidNexus:Print("Leave combat before applying subgroup moves.")
        return
    end

    self.frontlineApplyState = {
        desiredFullNames = analysis.desiredFullNames,
        desiredSet = analysis.desiredSet,
        movesApplied = 0,
        moveInFlight = false,
    }

    if self.frontlineFrame and self.frontlineFrame.stopButton then
        self.frontlineFrame.stopButton:SetEnabled(true)
    end

    RaidNexus:Print("Applying frontline roster to groups 1-4...")
    self:ContinueFrontlineApply()
end

function RosterExport:EnsureQuickPanel()
    if self.quickPanel then
        return self.quickPanel
    end

    local frame = CreateFrame("Frame", "RaidNexusQuickPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(220, 256)
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
    subtitle:SetText("Quick export and raid sorting tools.")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local simSection = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    simSection:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    simSection:SetText("Sim")

    local simcButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    simcButton:SetSize(184, 24)
    simcButton:SetPoint("TOP", frame, "TOP", 0, -90)
    simcButton:SetText("Copy SimC")
    simcButton:SetScript("OnClick", function()
        frame:Hide()
        if RaidNexus.SimCExport and RaidNexus.SimCExport.PrintSimcProfile then
            RaidNexus.SimCExport:PrintSimcProfile(false, false, false)
        else
            RaidNexus:Print("SimC export module is unavailable.")
        end
    end)

    local rosterSection = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterSection:SetPoint("TOPLEFT", simcButton, "BOTTOMLEFT", 0, -14)
    rosterSection:SetText("Raid Roster")

    local rosterButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    rosterButton:SetSize(184, 24)
    rosterButton:SetPoint("TOP", frame, "TOP", 0, -150)
    rosterButton:SetText("Copy Roster")
    rosterButton:SetScript("OnClick", function()
        frame:Hide()
        self:CopyRoster()
    end)

    local groupsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    groupsButton:SetSize(184, 24)
    groupsButton:SetPoint("TOP", rosterButton, "BOTTOM", 0, -8)
    groupsButton:SetText("Copy Groups")
    groupsButton:SetScript("OnClick", function()
        frame:Hide()
        self:CopyGroups()
    end)

    local frontlineButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frontlineButton:SetSize(184, 24)
    frontlineButton:SetPoint("TOP", groupsButton, "BOTTOM", 0, -8)
    frontlineButton:SetText("Apply Groups 1-4")
    frontlineButton:SetScript("OnClick", function()
        frame:Hide()
        self:ShowFrontlineSorter()
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        local state = RosterExport.frontlineApplyState
        if state then
            state.moveInFlight = false
            RosterExport:ContinueFrontlineApply()
        end
    end
end)
