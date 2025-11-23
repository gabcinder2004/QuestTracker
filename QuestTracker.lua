-- QuestTracker: Zone Quest Progress Addon
-- Displays quest completion progress per zone when hovering on the world map

QuestTracker = CreateFrame("Frame")
QuestTracker.zoneQuestCache = {}
QuestTracker.cacheBuilt = false
QuestTracker.debug = false  -- Use /qt debug to enable

-- Saved variable for caching
QuestTracker_Cache = QuestTracker_Cache or {}

-- Debug print function
local function DebugPrint(msg)
    if QuestTracker.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff00ffQT Debug:|r " .. tostring(msg))
    end
end

----------------------------------------------
-- Utility Functions
----------------------------------------------

local function GetAllZoneIDs(mainZoneID)
    local zones = {mainZoneID}
    if QuestTracker_ZoneData and QuestTracker_ZoneData.SubZones and QuestTracker_ZoneData.SubZones[mainZoneID] then
        for _, subZoneID in ipairs(QuestTracker_ZoneData.SubZones[mainZoneID]) do
            table.insert(zones, subZoneID)
        end
    end
    return zones
end

-- Class name to bitmask mapping
local classMasks = {
    ["WARRIOR"] = 1,
    ["PALADIN"] = 2,
    ["HUNTER"] = 4,
    ["ROGUE"] = 8,
    ["PRIEST"] = 16,
    ["SHAMAN"] = 32,
    ["MAGE"] = 64,
    ["WARLOCK"] = 128,
    ["DRUID"] = 1024,
}

-- Check if a quest is available for the player
local function IsQuestForPlayer(questData)
    if not questData then return false end

    -- Check race restriction
    if questData["race"] then
        local raceMask = questData["race"]
        if raceMask ~= 0 and raceMask ~= 255 then
            local faction = UnitFactionGroup("player")
            if faction == "Alliance" then
                if bit.band(raceMask, 77) == 0 then return false end
            else
                if bit.band(raceMask, 178) == 0 then return false end
            end
        end
    end

    -- Check class restriction
    if questData["class"] then
        local classMask = questData["class"]
        local _, playerClass = UnitClass("player")
        local playerMask = classMasks[playerClass] or 0
        if playerMask > 0 and bit.band(classMask, playerMask) == 0 then
            return false
        end
    end

    return true
end

-- Get quest zones from quest data (only counts where quest STARTS, primary location only)
local function GetQuestZones(questID, questData)
    local zones = {}

    -- Get PRIMARY zone from an entity (first coordinate only)
    local function GetPrimaryZone(entityType, entityID)
        if pfDB and pfDB[entityType] and pfDB[entityType]["data"] and pfDB[entityType]["data"][entityID] then
            local data = pfDB[entityType]["data"][entityID]
            if data["coords"] and data["coords"][1] and data["coords"][1][3] then
                return data["coords"][1][3]
            end
        end
        return nil
    end

    -- Only check START locations - quest belongs to the zone where you pick it up
    -- Use only the FIRST quest giver's PRIMARY location to avoid duplicates
    if questData["start"] then
        -- Check NPCs first (most common)
        if questData["start"]["U"] and questData["start"]["U"][1] then
            local zone = GetPrimaryZone("units", questData["start"]["U"][1])
            if zone then
                zones[zone] = true
                return zones -- Found primary zone, done
            end
        end
        -- Check objects
        if questData["start"]["O"] and questData["start"]["O"][1] then
            local zone = GetPrimaryZone("objects", questData["start"]["O"][1])
            if zone then
                zones[zone] = true
                return zones
            end
        end
        -- Item-start quests: check where the item drops (first source only)
        if questData["start"]["I"] and questData["start"]["I"][1] then
            local itemID = questData["start"]["I"][1]
            if pfDB and pfDB["items"] and pfDB["items"]["data"] and pfDB["items"]["data"][itemID] then
                local itemData = pfDB["items"]["data"][itemID]
                -- Check first unit that drops this item
                if itemData["U"] then
                    for unitID, _ in pairs(itemData["U"]) do
                        local zone = GetPrimaryZone("units", unitID)
                        if zone then
                            zones[zone] = true
                            return zones
                        end
                    end
                end
                -- Check first object
                if itemData["O"] then
                    for objID, _ in pairs(itemData["O"]) do
                        local zone = GetPrimaryZone("objects", objID)
                        if zone then
                            zones[zone] = true
                            return zones
                        end
                    end
                end
            end
        end
    end

    return zones
end

----------------------------------------------
-- Cache Building
----------------------------------------------

function QuestTracker:BuildQuestCache()
    if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
        DebugPrint("pfDB not available")
        return false
    end

    self.zoneQuestCache = {}
    local questCount = 0

    for questID, questData in pairs(pfDB["quests"]["data"]) do
        if IsQuestForPlayer(questData) then
            local questZones = GetQuestZones(questID, questData)
            for zoneID, _ in pairs(questZones) do
                if not self.zoneQuestCache[zoneID] then
                    self.zoneQuestCache[zoneID] = {}
                end
                self.zoneQuestCache[zoneID][questID] = true
            end
            questCount = questCount + 1
        end
    end

    self.cacheBuilt = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker:|r Cached " .. questCount .. " quests.")
    return true
end

-- Look up zone ID by name
local function GetZoneIDByName(zoneName)
    if QuestTracker_ZoneData and QuestTracker_ZoneData.ZoneNameToID and QuestTracker_ZoneData.ZoneNameToID[zoneName] then
        return QuestTracker_ZoneData.ZoneNameToID[zoneName]
    end

    if pfDB and pfDB["zones"] and pfDB["zones"]["loc"] then
        for id, name in pairs(pfDB["zones"]["loc"]) do
            if name == zoneName then
                return id
            end
        end
    end
    return nil
end

-- Get quest progress for a zone
function QuestTracker:GetZoneProgress(zoneName)
    local mainZoneID = GetZoneIDByName(zoneName)
    if not mainZoneID then return nil, nil end

    local allZoneIDs = GetAllZoneIDs(mainZoneID)
    local allQuests = {}

    for _, zoneID in ipairs(allZoneIDs) do
        if self.zoneQuestCache[zoneID] then
            for questID, _ in pairs(self.zoneQuestCache[zoneID]) do
                allQuests[questID] = true
            end
        end
    end

    local total = 0
    local completed = 0

    for questID, _ in pairs(allQuests) do
        total = total + 1
        if pfQuest_history and pfQuest_history[questID] then
            completed = completed + 1
        end
    end

    return completed, total
end

-- Audit zone quest counting
function QuestTracker:AuditZone(zoneName)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Auditing: " .. zoneName .. " ===|r")

    local mainZoneID = GetZoneIDByName(zoneName)
    if not mainZoneID then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Zone not found in data|r")
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage("Main Zone ID: " .. mainZoneID)

    -- Get zone name from pfDB
    if pfDB and pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][mainZoneID] then
        DEFAULT_CHAT_FRAME:AddMessage("pfDB zone name: " .. pfDB["zones"]["loc"][mainZoneID])
    end

    local allZoneIDs = GetAllZoneIDs(mainZoneID)
    DEFAULT_CHAT_FRAME:AddMessage("Total zone IDs (main + sub): " .. table.getn(allZoneIDs))

    -- Count quests per zone ID
    local questsByZone = {}
    local allQuests = {}

    for _, zoneID in ipairs(allZoneIDs) do
        local count = 0
        if self.zoneQuestCache[zoneID] then
            for questID, _ in pairs(self.zoneQuestCache[zoneID]) do
                allQuests[questID] = true
                count = count + 1
            end
        end
        if count > 0 then
            local zName = "Unknown"
            if pfDB and pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneID] then
                zName = pfDB["zones"]["loc"][zoneID]
            end
            questsByZone[zoneID] = {name = zName, count = count}
        end
    end

    -- Show breakdown
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Quest breakdown by sub-zone:|r")
    for zoneID, data in pairs(questsByZone) do
        DEFAULT_CHAT_FRAME:AddMessage("  [" .. zoneID .. "] " .. data.name .. ": " .. data.count .. " quests")
    end

    -- Total unique quests
    local total = 0
    for _ in pairs(allQuests) do
        total = total + 1
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Total unique quests: " .. total .. "|r")

    -- Sample some quest names
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Sample quests (first 5):|r")
    local count = 0
    for questID, _ in pairs(allQuests) do
        if count >= 5 then break end
        local questName = "Unknown"
        if pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questID] then
            local locData = pfDB["quests"]["loc"][questID]
            -- Handle both string and table formats
            if type(locData) == "string" then
                questName = locData
            elseif type(locData) == "table" then
                -- Try common keys: first element, or named keys
                questName = locData[1] or locData["T"] or locData["title"] or tostring(locData)
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("  [" .. questID .. "] " .. tostring(questName))
        count = count + 1
    end
end

----------------------------------------------
-- Progress Display Helpers
----------------------------------------------

local function GetProgressColor(percent)
    if percent >= 100 then return 0, 1, 0
    elseif percent >= 75 then return 0.5, 1, 0
    elseif percent >= 50 then return 1, 1, 0
    elseif percent >= 25 then return 1, 0.5, 0
    else return 1, 0.2, 0.2 end
end

local function CreateProgressBar(percent)
    local width = 20
    local filled = math.floor(percent / 100 * width)
    local empty = width - filled
    return "|cff00ff00" .. string.rep("I", filled) .. "|r|cff555555" .. string.rep("I", empty) .. "|r"
end

-- Helper to get quest name from pfDB
local function GetQuestName(questID)
    if pfDB and pfDB["quests"] and pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questID] then
        local locData = pfDB["quests"]["loc"][questID]
        if type(locData) == "string" then
            return locData
        elseif type(locData) == "table" then
            return locData[1] or locData["T"] or locData["title"] or ("Quest #" .. questID)
        end
    end
    return "Quest #" .. questID
end

-- Helper to get quest level from pfDB
local function GetQuestLevel(questID)
    if pfDB and pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questID] then
        return pfDB["quests"]["data"][questID]["lvl"] or 0
    end
    return 0
end

-- Helper to get quest min level from pfDB
local function GetQuestMinLevel(questID)
    if pfDB and pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questID] then
        return pfDB["quests"]["data"][questID]["min"] or 0
    end
    return 0
end

-- Helper to get quest prerequisites from pfDB
local function GetQuestPrereqs(questID)
    if pfDB and pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questID] then
        return pfDB["quests"]["data"][questID]["pre"]
    end
    return nil
end

-- Check if a quest is available to start right now
local function IsQuestAvailable(questID)
    local playerLevel = UnitLevel("player")

    -- Check minimum level
    local minLevel = GetQuestMinLevel(questID)
    if minLevel > 0 and playerLevel < minLevel then
        return false, "Requires level " .. minLevel
    end

    -- Check prerequisites
    local prereqs = GetQuestPrereqs(questID)
    if prereqs then
        for _, preQuestID in ipairs(prereqs) do
            if not (pfQuest_history and pfQuest_history[preQuestID]) then
                local preName = GetQuestName(preQuestID)
                return false, "Requires: " .. preName
            end
        end
    end

    return true, nil
end

----------------------------------------------
-- Quest Tracker Window (Zone Statistics UI)
----------------------------------------------

local trackerWindow = nil
local selectedZone = nil
local zoneButtons = {}
local questButtons = {}
local questHeaders = {}
local zoneSortMode = "name" -- "name", "progress", "percent"
local zoneSortAsc = true
local questTypeFilter = "all" -- "all", "kill", "gather", "interact", "other"

local function CreateTrackerWindow()
    if trackerWindow then return trackerWindow end

    -- Main frame
    trackerWindow = CreateFrame("Frame", "QuestTrackerWindow", UIParent)
    trackerWindow:SetWidth(800)
    trackerWindow:SetHeight(500)
    trackerWindow:SetPoint("CENTER", 0, 0)
    trackerWindow:SetFrameStrata("HIGH")
    trackerWindow:SetMovable(true)
    trackerWindow:EnableMouse(true)
    trackerWindow:RegisterForDrag("LeftButton")
    trackerWindow:SetScript("OnDragStart", function() this:StartMoving() end)
    trackerWindow:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    trackerWindow:SetClampedToScreen(true)

    -- Background
    trackerWindow:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    trackerWindow:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    trackerWindow:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)

    -- Title
    trackerWindow.title = trackerWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    trackerWindow.title:SetPoint("TOP", 0, -12)
    trackerWindow.title:SetText("Quest Tracker")
    trackerWindow.title:SetTextColor(1, 0.82, 0)

    -- Close button
    trackerWindow.closeBtn = CreateFrame("Button", nil, trackerWindow, "UIPanelCloseButton")
    trackerWindow.closeBtn:SetPoint("TOPRIGHT", -5, -5)
    trackerWindow.closeBtn:SetScript("OnClick", function() trackerWindow:Hide() end)

    -- Divider line (positioned to give ~340px to left panel)
    trackerWindow.divider = trackerWindow:CreateTexture(nil, "ARTWORK")
    trackerWindow.divider:SetTexture(1, 1, 1, 0.3)
    trackerWindow.divider:SetWidth(1)
    trackerWindow.divider:SetPoint("TOP", trackerWindow, "TOP", -55, -40)
    trackerWindow.divider:SetPoint("BOTTOM", trackerWindow, "BOTTOM", -55, 15)

    -- ============ LEFT PANEL (Zone List) ============
    trackerWindow.leftPanel = CreateFrame("Frame", nil, trackerWindow)
    trackerWindow.leftPanel:SetPoint("TOPLEFT", 10, -40)
    trackerWindow.leftPanel:SetPoint("BOTTOMRIGHT", trackerWindow.divider, "BOTTOMLEFT", -10, 5)

    -- Column headers (clickable for sorting)
    trackerWindow.headerName = CreateFrame("Button", nil, trackerWindow.leftPanel)
    trackerWindow.headerName:SetPoint("TOPLEFT", 5, 0)
    trackerWindow.headerName:SetWidth(160)
    trackerWindow.headerName:SetHeight(18)
    trackerWindow.headerName.text = trackerWindow.headerName:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackerWindow.headerName.text:SetPoint("LEFT", 0, 0)
    trackerWindow.headerName.text:SetText("Zone")
    trackerWindow.headerName.text:SetTextColor(1, 0.82, 0)
    trackerWindow.headerName:SetScript("OnClick", function()
        if zoneSortMode == "name" then
            zoneSortAsc = not zoneSortAsc
        else
            zoneSortMode = "name"
            zoneSortAsc = true
        end
        QuestTracker:PopulateZoneList()
    end)

    trackerWindow.headerProgress = CreateFrame("Button", nil, trackerWindow.leftPanel)
    trackerWindow.headerProgress:SetPoint("TOPLEFT", 170, 0)
    trackerWindow.headerProgress:SetWidth(115)
    trackerWindow.headerProgress:SetHeight(18)
    trackerWindow.headerProgress.text = trackerWindow.headerProgress:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackerWindow.headerProgress.text:SetPoint("LEFT", 0, 0)
    trackerWindow.headerProgress.text:SetText("Progress")
    trackerWindow.headerProgress.text:SetTextColor(1, 0.82, 0)
    trackerWindow.headerProgress:SetScript("OnClick", function()
        if zoneSortMode == "percent" then
            zoneSortAsc = not zoneSortAsc
        else
            zoneSortMode = "percent"
            zoneSortAsc = false -- default descending for progress
        end
        QuestTracker:PopulateZoneList()
    end)

    -- Zone scroll frame
    trackerWindow.zoneScroll = CreateFrame("ScrollFrame", "QuestTrackerZoneScroll", trackerWindow.leftPanel, "UIPanelScrollFrameTemplate")
    trackerWindow.zoneScroll:SetPoint("TOPLEFT", 0, -20)
    trackerWindow.zoneScroll:SetPoint("BOTTOMRIGHT", -25, 0)

    trackerWindow.zoneContent = CreateFrame("Frame", "QuestTrackerZoneContent", trackerWindow.zoneScroll)
    trackerWindow.zoneContent:SetWidth(290)
    trackerWindow.zoneContent:SetHeight(1)
    trackerWindow.zoneScroll:SetScrollChild(trackerWindow.zoneContent)

    -- Enable mouse wheel scrolling for zone panel
    trackerWindow.zoneScroll:EnableMouseWheel(true)
    trackerWindow.zoneScroll:SetScript("OnMouseWheel", function()
        local scrollBar = getglobal("QuestTrackerZoneScrollScrollBar")
        if scrollBar then
            local current = scrollBar:GetValue()
            local min, max = scrollBar:GetMinMaxValues()
            local step = 40
            if arg1 > 0 then
                scrollBar:SetValue(math.max(current - step, min))
            else
                scrollBar:SetValue(math.min(current + step, max))
            end
        end
    end)

    -- ============ RIGHT PANEL (Quest Details) ============
    trackerWindow.rightPanel = CreateFrame("Frame", nil, trackerWindow)
    trackerWindow.rightPanel:SetPoint("TOPLEFT", trackerWindow.divider, "TOPRIGHT", 10, 0)
    trackerWindow.rightPanel:SetPoint("BOTTOMRIGHT", -10, 15)

    -- Right panel title (zone name)
    trackerWindow.rightTitle = trackerWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    trackerWindow.rightTitle:SetPoint("TOPLEFT", trackerWindow.rightPanel, "TOPLEFT", 5, 0)
    trackerWindow.rightTitle:SetText("Select a zone")
    trackerWindow.rightTitle:SetTextColor(1, 0.82, 0)

    -- Progress info
    trackerWindow.progressText = trackerWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackerWindow.progressText:SetPoint("TOPLEFT", trackerWindow.rightTitle, "BOTTOMLEFT", 0, -5)
    trackerWindow.progressText:SetTextColor(0.7, 0.7, 0.7)

    -- Quest type filter buttons
    local function CreateFilterButton(name, label, xOffset)
        local btn = CreateFrame("Button", "QuestTrackerFilter"..name, trackerWindow.rightPanel)
        btn:SetWidth(55)
        btn:SetHeight(18)
        btn:SetPoint("TOPLEFT", trackerWindow.progressText, "BOTTOMLEFT", xOffset, -5)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER", 0, 0)
        btn.text:SetText(label)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetTexture(0.2, 0.2, 0.2, 0.8)

        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetTexture(1, 1, 1, 0.1)

        btn.filterType = string.lower(name)
        btn:SetScript("OnClick", function()
            questTypeFilter = this.filterType
            QuestTracker:UpdateFilterButtons()
            if selectedZone then
                QuestTracker:PopulateQuestList(selectedZone)
            end
        end)

        return btn
    end

    trackerWindow.filterAll = CreateFilterButton("All", "All", 0)
    trackerWindow.filterKill = CreateFilterButton("Kill", "Kill", 60)
    trackerWindow.filterGather = CreateFilterButton("Gather", "Gather", 120)
    trackerWindow.filterOther = CreateFilterButton("Other", "Other", 180)

    -- Quest scroll frame
    trackerWindow.questScroll = CreateFrame("ScrollFrame", "QuestTrackerQuestScroll", trackerWindow.rightPanel, "UIPanelScrollFrameTemplate")
    trackerWindow.questScroll:SetPoint("TOPLEFT", 0, -68)
    trackerWindow.questScroll:SetPoint("BOTTOMRIGHT", -25, 0)

    trackerWindow.questContent = CreateFrame("Frame", "QuestTrackerQuestContent", trackerWindow.questScroll)
    trackerWindow.questContent:SetWidth(460)
    trackerWindow.questContent:SetHeight(1)
    trackerWindow.questScroll:SetScrollChild(trackerWindow.questContent)

    -- Enable mouse wheel scrolling for quest panel
    trackerWindow.questScroll:EnableMouseWheel(true)
    trackerWindow.questScroll:SetScript("OnMouseWheel", function()
        local scrollBar = getglobal("QuestTrackerQuestScrollScrollBar")
        if scrollBar then
            local current = scrollBar:GetValue()
            local min, max = scrollBar:GetMinMaxValues()
            local step = 40
            if arg1 > 0 then
                scrollBar:SetValue(math.max(current - step, min))
            else
                scrollBar:SetValue(math.min(current + step, max))
            end
        end
    end)

    -- ESC to close
    tinsert(UISpecialFrames, "QuestTrackerWindow")

    trackerWindow:Hide()
    return trackerWindow
end

-- Create a zone button
local function CreateZoneButton(parent, index)
    local btn = CreateFrame("Button", "QuestTrackerZoneBtn"..index, parent)
    btn:SetWidth(290)
    btn:SetHeight(20)

    -- Zone name on left (truncates if too long)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", 5, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetWidth(160)

    -- Progress on right with fixed position
    btn.progress = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.progress:SetPoint("LEFT", 170, 0)
    btn.progress:SetJustifyH("LEFT")
    btn.progress:SetWidth(115)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetTexture(1, 1, 1, 0.1)

    btn.selected = btn:CreateTexture(nil, "BACKGROUND")
    btn.selected:SetAllPoints()
    btn.selected:SetTexture(1, 0.82, 0, 0.2)
    btn.selected:Hide()

    btn:SetScript("OnClick", function()
        QuestTracker:SelectZone(this.zoneName)
    end)

    return btn
end

-- Create a quest button
local function CreateQuestButton(parent, index)
    local btn = CreateFrame("Button", "QuestTrackerQuestBtn"..index, parent)
    btn:SetWidth(460)
    btn:SetHeight(18)

    -- Level indicator
    btn.level = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.level:SetPoint("LEFT", 5, 0)
    btn.level:SetWidth(25)
    btn.level:SetJustifyH("CENTER")

    -- Quest type indicator (K=Kill, G=Gather, ?=Other)
    btn.qtype = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.qtype:SetPoint("LEFT", 28, 0)
    btn.qtype:SetWidth(12)
    btn.qtype:SetJustifyH("CENTER")

    -- Completion check
    btn.check = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.check:SetPoint("LEFT", 40, 0)
    btn.check:SetWidth(15)

    -- Quest name
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.text:SetPoint("LEFT", 55, 0)
    btn.text:SetPoint("RIGHT", -55, 0)
    btn.text:SetJustifyH("LEFT")

    -- Quest ID
    btn.id = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.id:SetPoint("RIGHT", -5, 0)
    btn.id:SetWidth(50)
    btn.id:SetJustifyH("RIGHT")
    btn.id:SetTextColor(0.5, 0.5, 0.5)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetTexture(1, 1, 1, 0.05)

    -- Right-click to inspect
    btn:RegisterForClicks("RightButtonUp")
    btn:SetScript("OnClick", function()
        if this.questID then
            QuestTracker:InspectQuest(this.questID)
        end
    end)

    return btn
end

-- Create a section header
local function CreateSectionHeader(parent, index)
    local header = CreateFrame("Frame", "QuestTrackerHeader"..index, parent)
    header:SetWidth(460)
    header:SetHeight(20)

    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetPoint("LEFT", 5, 0)
    header.text:SetTextColor(1, 0.82, 0)

    header.count = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.count:SetPoint("LEFT", header.text, "RIGHT", 5, 0)
    header.count:SetTextColor(0.7, 0.7, 0.7)

    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetTexture(1, 1, 1, 0.3)
    header.line:SetHeight(1)
    header.line:SetPoint("LEFT", header.count, "RIGHT", 10, 0)
    header.line:SetPoint("RIGHT", header, "RIGHT", -5, 0)

    return header
end

-- Select a zone and show its quests
function QuestTracker:SelectZone(zoneName)
    selectedZone = zoneName

    -- Update zone button selection visuals
    for _, btn in pairs(zoneButtons) do
        if btn.zoneName == zoneName then
            btn.selected:Show()
        else
            btn.selected:Hide()
        end
    end

    -- Update right panel
    local window = trackerWindow
    window.rightTitle:SetText(zoneName)

    local completed, total = self:GetZoneProgress(zoneName)
    if completed and total and total > 0 then
        local percent = math.floor((completed / total) * 100)
        local r, g, b = GetProgressColor(percent)
        window.progressText:SetText(string.format("|cff%02x%02x%02x%d/%d (%d%%)|r completed", r*255, g*255, b*255, completed, total, percent))
    else
        window.progressText:SetText("No quest data")
    end

    -- Get quests for this zone
    self:PopulateQuestList(zoneName)
end

-- Update filter button visual states
function QuestTracker:UpdateFilterButtons()
    if not trackerWindow then return end
    local buttons = {
        trackerWindow.filterAll,
        trackerWindow.filterKill,
        trackerWindow.filterGather,
        trackerWindow.filterOther
    }
    for _, btn in ipairs(buttons) do
        if btn.filterType == questTypeFilter then
            btn.bg:SetTexture(0.4, 0.3, 0.1, 0.9)
            btn.text:SetTextColor(1, 0.82, 0)
        else
            btn.bg:SetTexture(0.2, 0.2, 0.2, 0.8)
            btn.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end
end

-- Get quest type based on objectives
local function GetQuestType(questID)
    if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
        return "other"
    end
    local data = pfDB["quests"]["data"][questID]
    if not data or not data["obj"] then
        return "other"
    end

    local hasKill = data["obj"]["U"] and table.getn(data["obj"]["U"]) > 0
    local hasGather = data["obj"]["I"] and table.getn(data["obj"]["I"]) > 0
    local hasInteract = data["obj"]["O"] and table.getn(data["obj"]["O"]) > 0

    -- Prioritize: kill > gather > other
    if hasKill then
        return "kill"
    elseif hasGather then
        return "gather"
    elseif hasInteract then
        return "other"
    else
        return "other"
    end
end

-- Check if quest matches current filter
local function QuestMatchesFilter(questID)
    if questTypeFilter == "all" then
        return true
    end
    return GetQuestType(questID) == questTypeFilter
end

-- Populate the quest list for a zone
function QuestTracker:PopulateQuestList(zoneName)
    -- Hide existing elements
    for _, btn in pairs(questButtons) do
        btn:Hide()
    end
    for _, header in pairs(questHeaders) do
        header:Hide()
    end

    -- Update filter button states
    self:UpdateFilterButtons()

    local mainZoneID = GetZoneIDByName(zoneName)
    if not mainZoneID then return end

    local allZoneIDs = GetAllZoneIDs(mainZoneID)
    local allQuests = {}

    for _, zoneID in ipairs(allZoneIDs) do
        if self.zoneQuestCache[zoneID] then
            for questID, _ in pairs(self.zoneQuestCache[zoneID]) do
                allQuests[questID] = true
            end
        end
    end

    -- Categorize quests
    local completed = {}
    local available = {}
    local locked = {}

    for questID, _ in pairs(allQuests) do
        -- Apply quest type filter
        if QuestMatchesFilter(questID) then
            local name = GetQuestName(questID)
            local done = pfQuest_history and pfQuest_history[questID]
            local level = GetQuestLevel(questID)
            local isAvailable, reason = IsQuestAvailable(questID)
            local qType = GetQuestType(questID)

            local questData = {id = questID, name = name, completed = done, level = level, reason = reason, questType = qType}

            if done then
                table.insert(completed, questData)
            elseif isAvailable then
                table.insert(available, questData)
            else
                table.insert(locked, questData)
            end
        end
    end

    -- Sort each category by level then name
    local function sortQuests(a, b)
        if a.level ~= b.level then
            return a.level < b.level
        end
        return a.name < b.name
    end
    table.sort(completed, sortQuests)
    table.sort(available, sortQuests)
    table.sort(locked, sortQuests)

    -- Get player level for color coding
    local playerLevel = UnitLevel("player")

    local yOffset = 0
    local btnIndex = 0
    local headerIndex = 0

    -- Helper to render a section
    local function RenderSection(title, quests, dimmed)
        if table.getn(quests) == 0 then return end

        -- Section header
        headerIndex = headerIndex + 1
        local header = questHeaders[headerIndex]
        if not header then
            header = CreateSectionHeader(trackerWindow.questContent, headerIndex)
            questHeaders[headerIndex] = header
        end
        header:SetPoint("TOPLEFT", 0, -yOffset)
        header.text:SetText(title)
        header.count:SetText("(" .. table.getn(quests) .. ")")
        header:Show()
        yOffset = yOffset + 22

        -- Quest buttons
        for _, quest in ipairs(quests) do
            btnIndex = btnIndex + 1
            local btn = questButtons[btnIndex]
            if not btn then
                btn = CreateQuestButton(trackerWindow.questContent, btnIndex)
                questButtons[btnIndex] = btn
            end

            btn:SetPoint("TOPLEFT", 0, -yOffset)

            -- Level with difficulty color
            local levelColor
            local diff = quest.level - playerLevel
            if dimmed then
                levelColor = "808080"
            elseif diff >= 5 then
                levelColor = "ff0000"
            elseif diff >= 3 then
                levelColor = "ff6600"
            elseif diff >= -2 then
                levelColor = "ffff00"
            elseif diff >= -8 then
                levelColor = "00ff00"
            else
                levelColor = "808080"
            end
            btn.level:SetText("|cff" .. levelColor .. quest.level .. "|r")

            -- Quest type indicator
            local typeChar, typeColor
            if quest.questType == "kill" then
                typeChar = "K"
                typeColor = "ff6666" -- red
            elseif quest.questType == "gather" then
                typeChar = "G"
                typeColor = "66ff66" -- green
            else
                typeChar = "?"
                typeColor = "aaaaaa" -- gray
            end
            if dimmed then typeColor = "666666" end
            btn.qtype:SetText("|cff" .. typeColor .. typeChar .. "|r")

            if quest.completed then
                btn.check:SetText("|cff00ff00+|r")
                btn.text:SetTextColor(0.5, 0.5, 0.5)
                btn.id:SetTextColor(0.4, 0.4, 0.4)
            elseif dimmed then
                btn.check:SetText("|cff666666-|r")
                btn.text:SetTextColor(0.4, 0.4, 0.4)
                btn.id:SetTextColor(0.3, 0.3, 0.3)
            else
                btn.check:SetText("|cffff6600-|r")
                btn.text:SetTextColor(1, 1, 1)
                btn.id:SetTextColor(0.5, 0.5, 0.5)
            end

            btn.questID = quest.id
            btn.text:SetText(quest.name)
            btn.id:SetText("#" .. quest.id)
            btn:Show()

            yOffset = yOffset + 18
        end

        yOffset = yOffset + 5 -- spacing between sections
    end

    -- Render sections
    RenderSection("Available", available, false)
    RenderSection("Locked", locked, true)
    RenderSection("Completed", completed, true)

    -- Set content height and update scroll bar
    local contentHeight = math.max(yOffset, 1)
    trackerWindow.questContent:SetHeight(contentHeight)

    -- Update scroll bar range
    local scrollFrame = trackerWindow.questScroll
    local scrollBar = getglobal("QuestTrackerQuestScrollScrollBar")
    if scrollBar then
        local visibleHeight = scrollFrame:GetHeight()
        local maxScroll = math.max(0, contentHeight - visibleHeight)
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(0)
        if maxScroll > 0 then
            scrollBar:Show()
        else
            scrollBar:Hide()
        end
    end
end

-- Populate the zone list
function QuestTracker:PopulateZoneList()
    -- Hide existing buttons
    for _, btn in pairs(zoneButtons) do
        btn:Hide()
    end

    if not self.cacheBuilt then
        self:BuildQuestCache()
    end

    -- Get all zones from ZoneData
    local zones = {}
    if QuestTracker_ZoneData and QuestTracker_ZoneData.ZoneNameToID then
        for zoneName, zoneID in pairs(QuestTracker_ZoneData.ZoneNameToID) do
            local completed, total = self:GetZoneProgress(zoneName)
            if total and total > 0 then
                local percent = math.floor((completed / total) * 100)
                table.insert(zones, {
                    name = zoneName,
                    completed = completed,
                    total = total,
                    percent = percent
                })
            end
        end
    end

    -- Sort based on current mode
    table.sort(zones, function(a, b)
        if zoneSortMode == "name" then
            if zoneSortAsc then
                return a.name < b.name
            else
                return a.name > b.name
            end
        elseif zoneSortMode == "percent" then
            if zoneSortAsc then
                return a.percent < b.percent
            else
                return a.percent > b.percent
            end
        end
        return a.name < b.name
    end)

    -- Update header text to show sort indicator
    local nameArrow = ""
    local progressArrow = ""
    if zoneSortMode == "name" then
        nameArrow = zoneSortAsc and " v" or " ^"
    elseif zoneSortMode == "percent" then
        progressArrow = zoneSortAsc and " v" or " ^"
    end
    trackerWindow.headerName.text:SetText("Zone" .. nameArrow)
    trackerWindow.headerProgress.text:SetText("Progress" .. progressArrow)

    -- Create/update buttons
    local yOffset = 0
    for i, zone in ipairs(zones) do
        local btn = zoneButtons[i]
        if not btn then
            btn = CreateZoneButton(trackerWindow.zoneContent, i)
            zoneButtons[i] = btn
        end

        btn:SetPoint("TOPLEFT", 0, -yOffset)
        btn.zoneName = zone.name
        btn.text:SetText(zone.name)

        local r, g, b = GetProgressColor(zone.percent)
        btn.progress:SetText(string.format("|cff%02x%02x%02x%d/%d (%d%%)|r", r*255, g*255, b*255, zone.completed, zone.total, zone.percent))

        if selectedZone == zone.name then
            btn.selected:Show()
        else
            btn.selected:Hide()
        end

        btn:Show()
        yOffset = yOffset + 20
    end

    trackerWindow.zoneContent:SetHeight(math.max(yOffset, 1))
end

-- Toggle tracker window
function QuestTracker:ToggleWindow()
    local window = CreateTrackerWindow()
    if window:IsVisible() then
        window:Hide()
    else
        self:PopulateZoneList()
        window:Show()
    end
end

----------------------------------------------
-- Quest Detail Popup Window
----------------------------------------------

local questDetailFrame = nil

local function CreateQuestDetailFrame()
    if questDetailFrame then return questDetailFrame end

    questDetailFrame = CreateFrame("Frame", "QuestTrackerDetailFrame", UIParent)
    questDetailFrame:SetWidth(500)
    questDetailFrame:SetHeight(550)
    questDetailFrame:SetPoint("CENTER", 200, 0)
    questDetailFrame:SetFrameStrata("DIALOG")
    questDetailFrame:SetMovable(true)
    questDetailFrame:EnableMouse(true)
    questDetailFrame:RegisterForDrag("LeftButton")
    questDetailFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    questDetailFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    questDetailFrame:SetClampedToScreen(true)

    questDetailFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    questDetailFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    questDetailFrame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)

    -- Close button (create first so title can account for it)
    questDetailFrame.closeBtn = CreateFrame("Button", nil, questDetailFrame, "UIPanelCloseButton")
    questDetailFrame.closeBtn:SetPoint("TOPRIGHT", -5, -5)
    questDetailFrame.closeBtn:SetScript("OnClick", function() questDetailFrame:Hide() end)

    -- Title (quest name) - leave room for close button
    questDetailFrame.title = questDetailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    questDetailFrame.title:SetPoint("TOPLEFT", 15, -15)
    questDetailFrame.title:SetPoint("TOPRIGHT", -35, -15)
    questDetailFrame.title:SetJustifyH("LEFT")
    questDetailFrame.title:SetTextColor(1, 0.82, 0)

    -- Quest ID subtitle
    questDetailFrame.questID = questDetailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    questDetailFrame.questID:SetPoint("TOPLEFT", questDetailFrame.title, "BOTTOMLEFT", 0, -2)
    questDetailFrame.questID:SetTextColor(0.6, 0.6, 0.6)

    -- Scroll frame for content
    questDetailFrame.scrollFrame = CreateFrame("ScrollFrame", "QuestTrackerDetailScroll", questDetailFrame, "UIPanelScrollFrameTemplate")
    questDetailFrame.scrollFrame:SetPoint("TOPLEFT", 15, -55)
    questDetailFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)

    questDetailFrame.content = CreateFrame("Frame", "QuestTrackerDetailContent", questDetailFrame.scrollFrame)
    questDetailFrame.content:SetWidth(435)
    questDetailFrame.content:SetHeight(1)
    questDetailFrame.scrollFrame:SetScrollChild(questDetailFrame.content)

    -- Enable mouse wheel scrolling
    questDetailFrame.scrollFrame:EnableMouseWheel(true)
    questDetailFrame.scrollFrame:SetScript("OnMouseWheel", function()
        local scrollBar = getglobal("QuestTrackerDetailScrollScrollBar")
        if scrollBar then
            local current = scrollBar:GetValue()
            local min, max = scrollBar:GetMinMaxValues()
            local step = 40
            if arg1 > 0 then
                scrollBar:SetValue(math.max(current - step, min))
            else
                scrollBar:SetValue(math.min(current + step, max))
            end
        end
    end)

    -- Pool of text lines for reuse
    questDetailFrame.lines = {}

    -- ESC to close
    tinsert(UISpecialFrames, "QuestTrackerDetailFrame")

    questDetailFrame:Hide()
    return questDetailFrame
end

-- Get or create a text line in the detail frame
local function GetDetailLine(frame, index)
    if not frame.lines[index] then
        local line = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line:SetWidth(420)
        line:SetJustifyH("LEFT")
        frame.lines[index] = line
    end
    return frame.lines[index]
end

-- Helper to split text into lines of max length
local function SplitTextIntoLines(text, maxLen)
    local lines = {}
    if not text or text == "" then return lines end

    while string.len(text) > maxLen do
        -- Find a good break point (space)
        local breakPoint = maxLen
        for i = maxLen, 1, -1 do
            if string.sub(text, i, i) == " " then
                breakPoint = i
                break
            end
        end
        table.insert(lines, string.sub(text, 1, breakPoint))
        text = string.sub(text, breakPoint + 1)
        -- Trim leading space
        text = string.gsub(text, "^%s+", "")
    end
    if string.len(text) > 0 then
        table.insert(lines, text)
    end
    return lines
end

-- Show quest details in popup
function QuestTracker:ShowQuestDetail(questID)
    local frame = CreateQuestDetailFrame()

    -- Hide all existing lines
    for _, line in pairs(frame.lines) do
        line:Hide()
    end

    local lineIndex = 0
    local yOffset = 0

    -- Helper to add a line
    local function AddLine(text, r, g, b, size, indent)
        lineIndex = lineIndex + 1
        local line = GetDetailLine(frame, lineIndex)
        line:SetText(text)
        line:SetTextColor(r or 1, g or 1, b or 1)
        local lineHeight = 14
        if size == "small" then
            line:SetFontObject(GameFontNormalSmall)
            lineHeight = 12
        elseif size == "header" then
            line:SetFontObject(GameFontNormal)
            lineHeight = 14
        else
            line:SetFontObject(GameFontHighlight)
            lineHeight = 14
        end
        line:SetPoint("TOPLEFT", frame.content, "TOPLEFT", indent or 0, -yOffset)
        line:Show()
        yOffset = yOffset + lineHeight + 2
    end

    -- Helper to add a section header
    local function AddHeader(text)
        yOffset = yOffset + 8 -- extra space before header
        AddLine(text, 1, 0.82, 0, "header", 0)
        yOffset = yOffset + 2
    end

    -- Helper to add an indented item
    local function AddItem(text, r, g, b)
        AddLine("  " .. text, r or 0.9, g or 0.9, b or 0.9, "normal", 10)
    end

    -- Helper to get entity name
    local function GetEntityName(entityType, entityID)
        if pfDB and pfDB[entityType] and pfDB[entityType]["loc"] and pfDB[entityType]["loc"][entityID] then
            local locData = pfDB[entityType]["loc"][entityID]
            if type(locData) == "string" then return locData
            elseif type(locData) == "table" then return locData[1] or ("ID:" .. entityID)
            end
        end
        return "ID:" .. entityID
    end

    -- Helper to get zone name
    local function GetZoneName(zoneID)
        if pfDB and pfDB["zones"] and pfDB["zones"]["loc"] and pfDB["zones"]["loc"][zoneID] then
            return pfDB["zones"]["loc"][zoneID]
        end
        return "Zone " .. zoneID
    end

    -- Helper to get entity coordinates
    local function GetEntityCoords(entityType, entityID)
        if pfDB and pfDB[entityType] and pfDB[entityType]["data"] and pfDB[entityType]["data"][entityID] then
            local data = pfDB[entityType]["data"][entityID]
            if data["coords"] and data["coords"][1] then
                local c = data["coords"][1]
                local zoneName = GetZoneName(c[3])
                return string.format("%.1f, %.1f (%s)", c[1], c[2], zoneName)
            end
        end
        return nil
    end

    -- Helper to get item drop info
    local function GetItemDropInfo(itemID)
        local dropInfo = {}
        if pfDB and pfDB["items"] and pfDB["items"]["data"] and pfDB["items"]["data"][itemID] then
            local itemData = pfDB["items"]["data"][itemID]
            -- Dropped by units
            if itemData["U"] then
                for unitID, dropRate in pairs(itemData["U"]) do
                    local unitName = GetEntityName("units", unitID)
                    table.insert(dropInfo, string.format("%s (%.1f%%)", unitName, dropRate))
                end
            end
            -- Dropped by objects
            if itemData["O"] then
                for objID, dropRate in pairs(itemData["O"]) do
                    local objName = GetEntityName("objects", objID)
                    table.insert(dropInfo, string.format("%s (%.1f%%)", objName, dropRate))
                end
            end
            -- Sold by vendors
            if itemData["V"] then
                for vendorID, _ in pairs(itemData["V"]) do
                    local vendorName = GetEntityName("units", vendorID)
                    table.insert(dropInfo, vendorName .. " |cff00ff00(Vendor)|r")
                end
            end
        end
        return dropInfo
    end

    -- Quest name and ID
    local name = GetQuestName(questID)
    frame.title:SetText(name)
    frame.questID:SetText("Quest ID: " .. questID)

    -- Check if completed
    local completed = pfQuest_history and pfQuest_history[questID]
    if completed then
        AddLine("Status: Completed", 0, 1, 0)
    else
        local isAvailable, reason = IsQuestAvailable(questID)
        if isAvailable then
            AddLine("Status: Available", 0.5, 1, 0.5)
        else
            AddLine("Status: Locked - " .. (reason or "Unknown"), 1, 0.5, 0.5)
        end
    end

    -- Helper to clean WoW text formatting codes
    local function CleanQuestText(text)
        if not text then return "" end
        -- Replace $B with newline/space
        text = string.gsub(text, "%$[Bb]", " ")
        -- Replace $N with "player"
        text = string.gsub(text, "%$[Nn]", UnitName("player") or "player")
        -- Replace $C with class
        text = string.gsub(text, "%$[Cc]", UnitClass("player") or "adventurer")
        -- Replace $R with race
        text = string.gsub(text, "%$[Rr]", UnitRace("player") or "hero")
        -- Replace $G male;female; with appropriate gender
        text = string.gsub(text, "%$[Gg]([^;]+);([^;]+);", "%1")
        -- Remove any remaining $ codes
        text = string.gsub(text, "%$%w", "")
        -- Clean up multiple spaces
        text = string.gsub(text, "%s+", " ")
        -- Trim
        text = string.gsub(text, "^%s+", "")
        text = string.gsub(text, "%s+$", "")
        return text
    end

    -- Get localized quest text (description, objectives)
    local questLoc = nil
    if pfDB and pfDB["quests"] then
        -- Try turtle-specific locale first, then standard
        questLoc = pfDB["quests"]["loc"] and pfDB["quests"]["loc"][questID]
        if not questLoc and pfDB["quests"]["enUS"] then
            questLoc = pfDB["quests"]["enUS"][questID]
        end
        if not questLoc and pfDB["quests"]["enUS-turtle"] then
            questLoc = pfDB["quests"]["enUS-turtle"][questID]
        end
    end

    -- Show quest objectives if available
    if questLoc and type(questLoc) == "table" then
        if questLoc["O"] and questLoc["O"] ~= "" then
            AddHeader("Objectives")
            local objText = CleanQuestText(questLoc["O"])
            -- Split into multiple lines if too long
            local objLines = SplitTextIntoLines(objText, 60)
            for i, line in ipairs(objLines) do
                if i <= 4 then -- Max 4 lines
                    AddItem(line, 0.9, 0.9, 0.8)
                end
            end
        end
    end

    -- Get quest data
    if pfDB and pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questID] then
        local data = pfDB["quests"]["data"][questID]

        -- Basic info section
        AddHeader("Quest Info")
        if data["lvl"] then
            local playerLevel = UnitLevel("player")
            local diff = data["lvl"] - playerLevel
            local levelColor
            if diff >= 5 then levelColor = "|cffff0000"
            elseif diff >= 3 then levelColor = "|cffff6600"
            elseif diff >= -2 then levelColor = "|cffffff00"
            elseif diff >= -8 then levelColor = "|cff00ff00"
            else levelColor = "|cff808080" end
            AddItem("Quest Level: " .. levelColor .. data["lvl"] .. "|r")
        end
        if data["min"] then
            local playerLevel = UnitLevel("player")
            local minColor = playerLevel >= data["min"] and "|cff00ff00" or "|cffff0000"
            AddItem("Minimum Level: " .. minColor .. data["min"] .. "|r")
        end

        -- Race restrictions
        if data["race"] and data["race"] ~= 0 and data["race"] ~= 255 then
            local races = {}
            local raceBits = {
                [1] = "Human", [2] = "Orc", [4] = "Dwarf", [8] = "Night Elf",
                [16] = "Undead", [32] = "Tauren", [64] = "Gnome", [128] = "Troll",
                [512] = "High Elf"
            }
            for bitVal, raceName in pairs(raceBits) do
                if bit.band(data["race"], bitVal) > 0 then
                    table.insert(races, raceName)
                end
            end
            AddItem("Races: " .. table.concat(races, ", "))
        end

        -- Class restrictions
        if data["class"] then
            local classNames = {
                [1] = "Warrior", [2] = "Paladin", [4] = "Hunter", [8] = "Rogue",
                [16] = "Priest", [32] = "Shaman", [64] = "Mage", [128] = "Warlock", [1024] = "Druid"
            }
            local className = classNames[data["class"]] or ("Class Mask: " .. data["class"])
            AddItem("Class: " .. className)
        end

        -- Prerequisites
        if data["pre"] and table.getn(data["pre"]) > 0 then
            AddHeader("Prerequisites")
            for _, preID in ipairs(data["pre"]) do
                local preName = GetQuestName(preID)
                local preDone = pfQuest_history and pfQuest_history[preID]
                if preDone then
                    AddItem("|cff00ff00[Done]|r " .. preName .. " |cff666666(#" .. preID .. ")|r")
                else
                    AddItem("|cffff0000[Needed]|r " .. preName .. " |cff666666(#" .. preID .. ")|r")
                end
            end
        end

        -- Quest start with coordinates
        if data["start"] then
            AddHeader("Quest Start")
            if data["start"]["U"] then
                for _, unitID in ipairs(data["start"]["U"]) do
                    local unitName = GetEntityName("units", unitID)
                    local coords = GetEntityCoords("units", unitID)
                    AddItem("|cff88ccffNPC:|r " .. unitName .. " |cff666666(#" .. unitID .. ")|r")
                    if coords then
                        AddItem("    |cff888888" .. coords .. "|r", 0.6, 0.6, 0.6)
                    end
                end
            end
            if data["start"]["O"] then
                for _, objID in ipairs(data["start"]["O"]) do
                    local objName = GetEntityName("objects", objID)
                    local coords = GetEntityCoords("objects", objID)
                    AddItem("|cffffcc88Object:|r " .. objName .. " |cff666666(#" .. objID .. ")|r")
                    if coords then
                        AddItem("    |cff888888" .. coords .. "|r", 0.6, 0.6, 0.6)
                    end
                end
            end
            if data["start"]["I"] then
                for _, itemID in ipairs(data["start"]["I"]) do
                    local itemName = GetEntityName("items", itemID)
                    AddItem("|cffa335eeItem:|r " .. itemName .. " |cff666666(#" .. itemID .. ")|r")
                    -- Show where to get the item
                    local dropInfo = GetItemDropInfo(itemID)
                    for _, info in ipairs(dropInfo) do
                        AddItem("    |cff888888Drops: " .. info .. "|r", 0.6, 0.6, 0.6)
                    end
                end
            end
        end

        -- Quest turn-in with coordinates
        if data["end"] then
            AddHeader("Quest Turn-in")
            if data["end"]["U"] then
                for _, unitID in ipairs(data["end"]["U"]) do
                    local unitName = GetEntityName("units", unitID)
                    local coords = GetEntityCoords("units", unitID)
                    AddItem("|cff88ccffNPC:|r " .. unitName .. " |cff666666(#" .. unitID .. ")|r")
                    if coords then
                        AddItem("    |cff888888" .. coords .. "|r", 0.6, 0.6, 0.6)
                    end
                end
            end
            if data["end"]["O"] then
                for _, objID in ipairs(data["end"]["O"]) do
                    local objName = GetEntityName("objects", objID)
                    local coords = GetEntityCoords("objects", objID)
                    AddItem("|cffffcc88Object:|r " .. objName .. " |cff666666(#" .. objID .. ")|r")
                    if coords then
                        AddItem("    |cff888888" .. coords .. "|r", 0.6, 0.6, 0.6)
                    end
                end
            end
        end

        -- Objectives with coordinates and drop rates
        if data["obj"] then
            AddHeader("Objective Targets")
            if data["obj"]["U"] then
                for _, unitID in ipairs(data["obj"]["U"]) do
                    local unitName = GetEntityName("units", unitID)
                    local coords = GetEntityCoords("units", unitID)
                    -- Get level info
                    local levelStr = ""
                    if pfDB["units"]["data"] and pfDB["units"]["data"][unitID] and pfDB["units"]["data"][unitID]["lvl"] then
                        levelStr = " |cffaaaaaa[" .. pfDB["units"]["data"][unitID]["lvl"] .. "]|r"
                    end
                    AddItem("|cffff6666Kill:|r " .. unitName .. levelStr .. " |cff666666(#" .. unitID .. ")|r")
                    if coords then
                        AddItem("    |cff888888" .. coords .. "|r", 0.6, 0.6, 0.6)
                    end
                end
            end
            if data["obj"]["O"] then
                for _, objID in ipairs(data["obj"]["O"]) do
                    local objName = GetEntityName("objects", objID)
                    local coords = GetEntityCoords("objects", objID)
                    AddItem("|cffffcc88Interact:|r " .. objName .. " |cff666666(#" .. objID .. ")|r")
                    if coords then
                        AddItem("    |cff888888" .. coords .. "|r", 0.6, 0.6, 0.6)
                    end
                end
            end
            if data["obj"]["I"] then
                for _, itemID in ipairs(data["obj"]["I"]) do
                    local itemName = GetEntityName("items", itemID)
                    AddItem("|cffa335eeCollect:|r " .. itemName .. " |cff666666(#" .. itemID .. ")|r")
                    -- Show drop info
                    local dropInfo = GetItemDropInfo(itemID)
                    local shown = 0
                    for _, info in ipairs(dropInfo) do
                        if shown < 5 then -- Limit to 5 sources
                            AddItem("    |cff888888" .. info .. "|r", 0.6, 0.6, 0.6)
                            shown = shown + 1
                        end
                    end
                    if table.getn(dropInfo) > 5 then
                        AddItem("    |cff888888... and " .. (table.getn(dropInfo) - 5) .. " more sources|r", 0.5, 0.5, 0.5)
                    end
                end
            end
        end

        -- Raw data section at the end
        AddHeader("Raw Data")
        for key, value in pairs(data) do
            if type(value) == "table" then
                local parts = {}
                for k, v in pairs(value) do
                    if type(v) == "table" then
                        local items = {}
                        for _, item in ipairs(v) do
                            table.insert(items, tostring(item))
                        end
                        table.insert(parts, tostring(k) .. "={" .. table.concat(items, ",") .. "}")
                    else
                        table.insert(parts, tostring(k) .. "=" .. tostring(v))
                    end
                end
                AddItem("|cff88ff88" .. key .. "|r: {" .. table.concat(parts, ", ") .. "}", 0.7, 0.7, 0.7)
            else
                AddItem("|cff88ff88" .. key .. "|r: " .. tostring(value), 0.7, 0.7, 0.7)
            end
        end
    else
        AddLine("Quest data not found in pfDB", 1, 0.5, 0.5)
    end

    -- Set content height
    frame.content:SetHeight(math.max(yOffset + 10, 1))

    -- Update scroll bar
    local scrollBar = getglobal("QuestTrackerDetailScrollScrollBar")
    if scrollBar then
        local visibleHeight = frame.scrollFrame:GetHeight()
        local maxScroll = math.max(0, yOffset - visibleHeight + 20)
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(0)
    end

    frame:Show()
end

----------------------------------------------
-- Export Frame (copyable text window)
----------------------------------------------

local exportFrame = nil

local function CreateExportFrame()
    if exportFrame then return exportFrame end

    exportFrame = CreateFrame("Frame", "QuestTrackerExportFrame", UIParent)
    exportFrame:SetWidth(500)
    exportFrame:SetHeight(400)
    exportFrame:SetPoint("CENTER", 0, 0)
    exportFrame:SetFrameStrata("DIALOG")
    exportFrame:SetMovable(true)
    exportFrame:EnableMouse(true)
    exportFrame:RegisterForDrag("LeftButton")
    exportFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    exportFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    exportFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    exportFrame:SetBackdropColor(0, 0, 0, 0.9)
    exportFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Title
    exportFrame.title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    exportFrame.title:SetPoint("TOP", 0, -10)
    exportFrame.title:SetText("Quest Export")

    -- Close button
    exportFrame.closeBtn = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
    exportFrame.closeBtn:SetPoint("TOPRIGHT", -5, -5)
    exportFrame.closeBtn:SetScript("OnClick", function() exportFrame:Hide() end)

    -- Scroll frame
    exportFrame.scrollFrame = CreateFrame("ScrollFrame", "QuestTrackerExportScrollFrame", exportFrame, "UIPanelScrollFrameTemplate")
    exportFrame.scrollFrame:SetPoint("TOPLEFT", 10, -35)
    exportFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    -- Edit box for copyable text
    exportFrame.editBox = CreateFrame("EditBox", "QuestTrackerExportEditBox", exportFrame.scrollFrame)
    exportFrame.editBox:SetMultiLine(true)
    exportFrame.editBox:SetFontObject(GameFontHighlightSmall)
    exportFrame.editBox:SetWidth(450)
    exportFrame.editBox:SetAutoFocus(false)
    exportFrame.editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    exportFrame.scrollFrame:SetScrollChild(exportFrame.editBox)

    -- Instructions
    exportFrame.instructions = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exportFrame.instructions:SetPoint("BOTTOM", 0, 15)
    exportFrame.instructions:SetText("Press Ctrl+A to select all, then Ctrl+C to copy")

    exportFrame:Hide()
    return exportFrame
end

function QuestTracker:ShowExport(title, text)
    local frame = CreateExportFrame()
    frame.title:SetText(title)
    frame.editBox:SetText(text)
    frame.editBox:HighlightText()
    frame:Show()
end

-- Inspect a quest's raw data (now shows in popup window)
function QuestTracker:InspectQuest(questID)
    self:ShowQuestDetail(questID)
end

-- Export all quests for a zone
function QuestTracker:ExportZoneQuests(zoneName)
    if not self.cacheBuilt then
        self:BuildQuestCache()
    end

    local mainZoneID = GetZoneIDByName(zoneName)
    if not mainZoneID then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000QuestTracker:|r Zone not found: " .. zoneName)
        return
    end

    local allZoneIDs = GetAllZoneIDs(mainZoneID)
    local allQuests = {}

    for _, zoneID in ipairs(allZoneIDs) do
        if self.zoneQuestCache[zoneID] then
            for questID, _ in pairs(self.zoneQuestCache[zoneID]) do
                allQuests[questID] = true
            end
        end
    end

    -- Build sorted list
    local questList = {}
    for questID, _ in pairs(allQuests) do
        local name = GetQuestName(questID)
        local completed = (pfQuest_history and pfQuest_history[questID]) and "[DONE] " or ""
        table.insert(questList, completed .. name .. " (ID: " .. questID .. ")")
    end
    table.sort(questList)

    -- Build export text
    local exportText = zoneName .. " - " .. table.getn(questList) .. " quests\n"
    exportText = exportText .. "========================================\n\n"
    for _, questLine in ipairs(questList) do
        exportText = exportText .. questLine .. "\n"
    end

    self:ShowExport(zoneName .. " Quests (" .. table.getn(questList) .. ")", exportText)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker:|r Exported " .. table.getn(questList) .. " quests for " .. zoneName)
end

----------------------------------------------
-- Custom Progress Frame (TurtleWoW uses custom tooltips)
----------------------------------------------

local progressFrame = nil

local function CreateProgressFrame()
    if progressFrame then return progressFrame end
    if not WorldMapFrame then return nil end

    -- Create frame with subtle background
    progressFrame = CreateFrame("Frame", "QuestTrackerProgressFrame", WorldMapFrame)
    progressFrame:SetWidth(160)
    progressFrame:SetHeight(38)
    progressFrame:SetFrameStrata("TOOLTIP")
    progressFrame:SetFrameLevel(100)

    -- Add subtle background
    progressFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    progressFrame:SetBackdropColor(0, 0, 0, 0.7)
    progressFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    -- Progress text (centered)
    progressFrame.progress = progressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progressFrame.progress:SetPoint("TOP", progressFrame, "TOP", 0, -8)

    -- Progress bar (centered below text)
    progressFrame.bar = progressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressFrame.bar:SetPoint("TOP", progressFrame.progress, "BOTTOM", 0, -2)

    progressFrame:Hide()
    return progressFrame
end

function QuestTracker:ShowProgress(zoneName)
    local frame = CreateProgressFrame()
    if not frame then return end

    if not zoneName or zoneName == "" then
        frame:Hide()
        return
    end

    -- Check if this is a city/town that should use parent zone
    local displayName = zoneName
    if QuestTracker_ZoneData and QuestTracker_ZoneData.CityToZone and QuestTracker_ZoneData.CityToZone[zoneName] then
        zoneName = QuestTracker_ZoneData.CityToZone[zoneName]
    end

    local zoneID = GetZoneIDByName(zoneName)
    if not zoneID then
        frame:Hide()
        return
    end

    if not self.cacheBuilt then
        self:BuildQuestCache()
    end

    local completed, total = self:GetZoneProgress(zoneName)
    if not completed or not total or total == 0 then
        frame:Hide()
        return
    end

    local percent = math.floor((completed / total) * 100)
    local r, g, b = GetProgressColor(percent)
    local colorCode = string.format("|cff%02x%02x%02x", r*255, g*255, b*255)

    -- Format: "Quests: 15/42 (36%)" with color
    frame.progress:SetText("|cffffcc00Quests:|r " .. colorCode .. completed .. "/" .. total .. " (" .. percent .. "%)|r")
    frame.bar:SetText(CreateProgressBar(percent))

    -- Position relative to zone labels
    self:UpdateProgressPosition()

    frame:Show()
end

function QuestTracker:HideProgress()
    if progressFrame then
        progressFrame:Hide()
    end
end

----------------------------------------------
-- Zone Label Hook
----------------------------------------------

local function HookZoneLabel()
    if not WorldMapFrameAreaLabel then
        DebugPrint("WorldMapFrameAreaLabel not found")
        return false
    end

    -- Store original SetText function
    local originalSetText = WorldMapFrameAreaLabel.SetText

    -- Hook SetText to intercept zone changes
    WorldMapFrameAreaLabel.SetText = function(self, text)
        -- Call original function first
        originalSetText(self, text)

        -- Now handle our progress display
        if text and text ~= "" then
            DebugPrint("Zone label set: " .. text)
            QuestTracker:ShowProgress(text)
        else
            QuestTracker:HideProgress()
        end
    end

    DebugPrint("Hooked WorldMapFrameAreaLabel:SetText()")
    return true
end

-- Also hook the area description label to position our frame better
local function HookAreaDescription()
    if not WorldMapFrameAreaDescription then
        return false
    end

    local originalSetText = WorldMapFrameAreaDescription.SetText

    WorldMapFrameAreaDescription.SetText = function(self, text)
        originalSetText(self, text)
        -- Update position when description changes (adjusts for level range text)
        if progressFrame and progressFrame:IsVisible() then
            QuestTracker:UpdateProgressPosition()
        end
    end

    return true
end

-- Update progress frame position relative to zone labels
function QuestTracker:UpdateProgressPosition()
    if not progressFrame then return end

    -- Position below the zone info area
    progressFrame:ClearAllPoints()

    -- Try to position relative to zone description if visible
    if WorldMapFrameAreaDescription and WorldMapFrameAreaDescription:IsVisible()
       and WorldMapFrameAreaDescription:GetText() and WorldMapFrameAreaDescription:GetText() ~= "" then
        progressFrame:SetPoint("TOP", WorldMapFrameAreaDescription, "BOTTOM", 0, -5)
    elseif WorldMapFrameAreaLabel and WorldMapFrameAreaLabel:IsVisible() then
        progressFrame:SetPoint("TOP", WorldMapFrameAreaLabel, "BOTTOM", 0, -5)
    else
        progressFrame:SetPoint("BOTTOM", WorldMapFrame, "BOTTOM", 0, 20)
    end
end

-- Hide progress when map closes
local mapHideMonitor = CreateFrame("Frame")
mapHideMonitor:SetScript("OnUpdate", function()
    if not WorldMapFrame or not WorldMapFrame:IsVisible() then
        QuestTracker:HideProgress()
    end
end)

----------------------------------------------
-- Slash Commands
----------------------------------------------

SLASH_QUESTTRACKER1 = "/questtracker"
SLASH_QUESTTRACKER2 = "/qt"
SlashCmdList["QUESTTRACKER"] = function(msg)
    msg = string.lower(msg or "")

    -- No argument or "show" opens the window
    if msg == "" or msg == "show" or msg == "window" then
        QuestTracker:ToggleWindow()
        return
    end

    if msg == "debug" then
        QuestTracker.debug = not QuestTracker.debug
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker:|r Debug " .. (QuestTracker.debug and "ON" or "OFF"))
        return
    end

    if msg == "rebuild" then
        QuestTracker.cacheBuilt = false
        QuestTracker:BuildQuestCache()
        return
    end

    if msg == "zone" then
        local zone = GetRealZoneText()
        if not QuestTracker.cacheBuilt then QuestTracker:BuildQuestCache() end
        local c, t = QuestTracker:GetZoneProgress(zone)
        if c and t and t > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker:|r " .. zone .. ": " .. c .. "/" .. t)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker:|r No data for " .. zone)
        end
        return
    end

    if string.find(msg, "^audit") then
        local zoneName = string.gsub(msg, "^audit%s*", "")
        if zoneName == "" then
            -- Try to get hovered zone from map first
            if WorldMapFrameAreaLabel and WorldMapFrameAreaLabel:GetText() and WorldMapFrameAreaLabel:GetText() ~= "" then
                zoneName = WorldMapFrameAreaLabel:GetText()
            else
                zoneName = GetRealZoneText()
            end
        end
        QuestTracker:AuditZone(zoneName)
        return
    end

    if string.find(msg, "^export") then
        local zoneName = string.gsub(msg, "^export%s*", "")
        if zoneName == "" then
            if WorldMapFrameAreaLabel and WorldMapFrameAreaLabel:GetText() and WorldMapFrameAreaLabel:GetText() ~= "" then
                zoneName = WorldMapFrameAreaLabel:GetText()
            else
                zoneName = GetRealZoneText()
            end
        end
        QuestTracker:ExportZoneQuests(zoneName)
        return
    end

    if string.find(msg, "^inspect") then
        local questID = tonumber(string.gsub(msg, "^inspect%s*", ""))
        if questID then
            QuestTracker:InspectQuest(questID)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Usage: /qt inspect <questID>|r")
        end
        return
    end

    if msg == "test" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker Test:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  pfDB: " .. tostring(pfDB ~= nil))
        DEFAULT_CHAT_FRAME:AddMessage("  pfQuest_history: " .. tostring(pfQuest_history ~= nil))
        DEFAULT_CHAT_FRAME:AddMessage("  WorldMapFrame: " .. tostring(WorldMapFrame ~= nil))
        DEFAULT_CHAT_FRAME:AddMessage("  WorldMapFrameAreaLabel: " .. tostring(WorldMapFrameAreaLabel ~= nil))
        DEFAULT_CHAT_FRAME:AddMessage("  Cache built: " .. tostring(QuestTracker.cacheBuilt))
        if WorldMapFrameAreaLabel and WorldMapFrameAreaLabel.GetText then
            DEFAULT_CHAT_FRAME:AddMessage("  Label text: " .. tostring(WorldMapFrameAreaLabel:GetText()))
        end

        -- Check tooltip visibility
        DEFAULT_CHAT_FRAME:AddMessage("  -- Tooltips --")
        local tooltips = {"WorldMapTooltip", "GameTooltip", "pfaborMapTooltip", "WorldMapCompareTooltip", "ShoppingTooltip1"}
        for _, name in ipairs(tooltips) do
            local tt = getglobal(name)
            if tt then
                local vis = tt:IsVisible() and "VISIBLE" or "hidden"
                DEFAULT_CHAT_FRAME:AddMessage("  " .. name .. ": " .. vis)
            end
        end
        return
    end

    if msg == "scan" then
        -- Scan for visible frames that might be tooltips
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Scanning for visible tooltip frames...|r")
        local found = 0
        local framesToCheck = {
            "WorldMapTooltip", "GameTooltip", "ItemRefTooltip",
            "ShoppingTooltip1", "ShoppingTooltip2", "WorldMapCompareTooltip",
            "pfQuestTooltip", "pfaborMapTooltip", "AtlasLootTooltip",
        }
        for _, name in ipairs(framesToCheck) do
            local frame = getglobal(name)
            if frame and frame:IsVisible() then
                DEFAULT_CHAT_FRAME:AddMessage("  VISIBLE: " .. name)
                found = found + 1
            end
        end
        if found == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("  No known tooltip frames visible")
        end
        DEFAULT_CHAT_FRAME:AddMessage("Run this while hovering over a zone on the map!")
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker:|r /qt [show] | debug | rebuild | audit | export | inspect <id>")
end

----------------------------------------------
-- Event Handling
----------------------------------------------

QuestTracker:RegisterEvent("PLAYER_ENTERING_WORLD")
QuestTracker:RegisterEvent("VARIABLES_LOADED")

QuestTracker:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker|r loaded. Use /qt for help.")

        -- Hook zone labels (WorldMapFrame should exist by now)
        if WorldMapFrameAreaLabel then
            HookZoneLabel()
            HookAreaDescription()
        end
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if not QuestTracker.cacheBuilt and pfDB then
            QuestTracker:BuildQuestCache()
        end

        -- Try hooking again if it wasn't ready before
        if WorldMapFrameAreaLabel and not QuestTracker.hooked then
            if HookZoneLabel() then
                QuestTracker.hooked = true
                HookAreaDescription()
            end
        end
    end
end)

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker|r file loaded.")
