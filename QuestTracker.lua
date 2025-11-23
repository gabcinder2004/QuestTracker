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

-- Check if a quest is available for the player
local function IsQuestForPlayer(questData)
    if not questData then return false end
    if not questData["race"] then return true end

    local raceMask = questData["race"]
    if raceMask == 0 or raceMask == 255 then return true end

    local faction = UnitFactionGroup("player")
    if faction == "Alliance" then
        return bit.band(raceMask, 77) > 0
    else
        return bit.band(raceMask, 178) > 0
    end
end

-- Get quest zones from quest data
local function GetQuestZones(questID, questData)
    local zones = {}

    local function AddZonesFromCoords(entityType, entityID)
        if pfDB and pfDB[entityType] and pfDB[entityType]["data"] and pfDB[entityType]["data"][entityID] then
            local data = pfDB[entityType]["data"][entityID]
            if data["coords"] then
                for _, coord in pairs(data["coords"]) do
                    if coord[3] then
                        zones[coord[3]] = true
                    end
                end
            end
        end
    end

    -- Check start locations
    if questData["start"] then
        if questData["start"]["U"] then
            for _, unitID in ipairs(questData["start"]["U"]) do
                AddZonesFromCoords("units", unitID)
            end
        end
        if questData["start"]["O"] then
            for _, objID in ipairs(questData["start"]["O"]) do
                AddZonesFromCoords("objects", objID)
            end
        end
    end

    -- Check end locations
    if questData["end"] and questData["end"]["U"] then
        for _, unitID in ipairs(questData["end"]["U"]) do
            AddZonesFromCoords("units", unitID)
        end
    end

    -- Check objectives
    if questData["obj"] then
        if questData["obj"]["U"] then
            for _, unitID in ipairs(questData["obj"]["U"]) do
                AddZonesFromCoords("units", unitID)
            end
        end
        if questData["obj"]["O"] then
            for _, objID in ipairs(questData["obj"]["O"]) do
                AddZonesFromCoords("objects", objID)
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
-- Progress Display
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

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00QuestTracker:|r /qt debug | rebuild | zone | audit | export")
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
