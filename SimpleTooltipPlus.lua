-- =========================================
-- WoW Addon: Tooltip Extension
--  - Target of Target
--  - Item level of players (Inspect)
-- WoW Retail 12.0.1+
-- =========================================

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
-- Tooltip hook (Unit)
-- -----------------------------
local function OnTooltipSetUnit(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit then return end

    -- Target of target
    -- Use stable unit tokens first (mouseover is reliable for tooltip units).
    local baseUnit = UnitExists("mouseover") and "mouseover" or unit
    local targetUnit = baseUnit .. "target"

    if UnitExists(targetUnit) then
        local name = UnitName(targetUnit)
        if name then
            local color
            if UnitIsPlayer(targetUnit) then
                local _, class = UnitClass(targetUnit)
                color = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
            else
                color = { r = 0.5, g = 0.5, b = 0.5 }
            end

            tooltip:AddLine(
                "Ziel: " ..
                string.format("|cff%02x%02x%02x%s|r",
                    (color.r or 1) * 255,
                    (color.g or 1) * 255,
                    (color.b or 1) * 255,
                    name
                )
            )
        end
    end

    -- Item level
    if UnitIsPlayer(unit) then
        local guid = UnitGUID(unit)
        local ilvl = GetUnitItemLevel(unit)

        if ilvl then
            tooltip:AddLine("Item-Level: |cffffd100" .. ilvl .. "|r")
        else
            tooltip:AddLine("Item-Level: |cff808080Loading...|r")

            -- Trigger Inspect only once per GUID
            if guid and CanInspect(unit) and not pendingInspect[guid] then
                pendingInspect[guid] = true
                NotifyInspect(unit)
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

        -- Important: DO NOT use SetUnit() -> causes “sticky” tooltips
        -- Only refresh if the tooltip is visible AND still refers to the same unit
        if not GameTooltip:IsVisible() then return end

        local _, tipUnit = GameTooltip:GetUnit()
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

-- -----------------------------
-- Register tooltip hook
-- -----------------------------
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)
