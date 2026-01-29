-- =========================================
-- WoW Addon: Tooltip Extension
--  - Target of Target
--  - Item level of players (Inspect)
-- WoW Retail 12.0.1+
-- =========================================

local _, STP = ...

local INSPECT_TTL = 3 -- seconds
local pendingInspect = {}     -- guid -> true (NotifyInspect already sent)
local itemLevelCache = {}     -- guid -> ilvl (optional cache)

-- -----------------------------
-- Determine item level
-- -----------------------------
local function GetUnitItemLevel(unit)
    if not unit or not UnitIsPlayer(unit) then return nil end

    local guid = UnitGUID(unit)
    if not guid then return nil end

    -- Cache
    if itemLevelCache[guid] then
        return itemLevelCache[guid]
    end

    -- Own character: Use simple API
    if UnitIsUnit(unit, "player") then
        local _, equipped = GetAverageItemLevel()
        local ilvl = math.floor((equipped or 0) + 0.0001)
        itemLevelCache[guid] = ilvl
        return ilvl
    end

    if pendingInspect[guid] then
        return nil;
    end

    -- Other players: Use Blizzard's inspect average item level (reliable)
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local inspectedIlvl = C_PaperDollInfo.GetInspectItemLevel(unit)
        if inspectedIlvl and inspectedIlvl > 0 then
            local ilvl = math.floor(inspectedIlvl + 0.0001)
            itemLevelCache[guid] = ilvl
            return ilvl
        end
    end

    -- Inspect data not ready yet
    return nil
end

-- -----------------------------
-- Determine current mount (best-effort via mount aura)
-- -----------------------------
local function GetUnitMountName(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    if not C_MountJournal or not C_MountJournal.GetMountFromSpell or not C_MountJournal.GetMountInfoByID then return nil end

    local foundName = nil
    local foundCollected = nil

    -- Scan helpful auras and map aura spellID -> mountID
    AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(auraData)
        local spellId = auraData and auraData.spellId
        if type(spellId) ~= "number" then
            return
        end

        local mountID = STP.util.Scrub(C_MountJournal.GetMountFromSpell(spellId))
        if not mountID or type(mountID) ~= "number" or mountID <= 0 then
            return
        end

        -- isCollected is the 11th return value
        local name, _, _, _, _, _, _, _, _, _, isCollected = STP.util.Scrub(C_MountJournal.GetMountInfoByID(mountID))
        if name and name ~= "" and isCollected ~= nil then
            foundName = name
            foundCollected = isCollected and true or false
            return true -- stop iteration
        end
    end, true) -- usePackedAura=true to receive auraData tables

    return foundName, foundCollected
end

-- -----------------------------
-- Tooltip hook (Unit)
-- -----------------------------
local function OnTooltipSetUnit(tooltip)
    local _, unit = STP.util.Scrub(tooltip:GetUnit())
    if not unit then
        unit = "mouseover"
    end

    if not unit then return end

    -- Item level
    if STP.db.config.showItemLevel then
        if UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            local ilvl = GetUnitItemLevel(unit)
    
            if ilvl then
                tooltip:AddLine("Item-Level: |cffffd100" .. ilvl .. "|r")
            else
                tooltip:AddLine("Item-Level: |cff808080Loading...|r")
    
                -- Trigger Inspect only once per GUID
                if guid and CanInspect(unit) then
                    local t = pendingInspect[guid]
                    if not t or (GetTime() - t) > INSPECT_TTL then
                        pendingInspect[guid] = GetTime()
                        NotifyInspect(unit)
                    end
                end
            end
        end
    end

    -- Mount
    if STP.db.config.showMount then
        if UnitIsPlayer(unit) then
            local mountName, isCollected = GetUnitMountName(unit)
            if mountName then
                -- Spacing
                tooltip:AddLine(" ")
    
                local collectedText
                if isCollected then
                    collectedText = " |cff00ff00[Collected]|r"
                else
                    collectedText = " |cffff4040[Not Collected]|r"
                end
    
                tooltip:AddLine("|cff66ccff" .. mountName .. "|r" .. collectedText)
            end
        end
    end

    -- Target of target
    if STP.db.config.showTarget then
        local targetUnit = unit .. "target"
        if UnitExists(targetUnit) then
            local name = UnitName(targetUnit)
            if name then
                local color
                local isPlayer = STP.util.Scrub(UnitIsPlayer(targetUnit))
                if isPlayer then
                    local _, class = STP.util.Scrub(UnitClass(targetUnit))
                    color = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
                else
                    color = { r = 0.5, g = 0.5, b = 0.5 }
                end
        
                -- Spacing
                tooltip:AddLine(" ")
        
                tooltip:AddDoubleLine(
                    "Target:",
                    string.format("|cff%02x%02x%02x%s|r",
                        (color.r or 1) * 255,
                        (color.g or 1) * 255,
                        (color.b or 1) * 255,
                        name
                    ),
                    1, 1, 1
                )
            end
        end
    end
end

-- -----------------------------
-- Events: INSPECT_READY
-- -----------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

eventFrame:SetScript("OnEvent", function(_, event, guid)
    if event == "INSPECT_READY" then
        if guid then pendingInspect[guid] = nil end

        -- Refresh if the tooltip is visible AND still refers to the same unit
        if not GameTooltip:IsVisible() then return end

        local _, tipUnit = STP.util.Scrub(GameTooltip:GetUnit())
        if not tipUnit then return end
        if UnitGUID(tipUnit) ~= guid then return end

        -- Only refresh if the mouse is still actually over the same unit
        if UnitExists("mouseover") and UnitGUID("mouseover") == guid then
            -- Populate cache if possible
            local ilvl = GetUnitItemLevel("mouseover")
            if ilvl then
                itemLevelCache[guid] = ilvl
            end

            if GameTooltip.RefreshData then
                GameTooltip:RefreshData()
            else
                GameTooltip:SetUnit("mouseover")
            end
        end

        if ClearInspectPlayer then
            ClearInspectPlayer()
        end

    elseif event == "PLAYER_LEAVING_WORLD" then
        wipe(pendingInspect)
        wipe(itemLevelCache)
    end
end)

local function PostUnitTooltip(tooltip, tooltipData)
    OnTooltipSetUnit(tooltip)
end

-- -----------------------------
-- Register tooltip hook
-- -----------------------------
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, PostUnitTooltip)
