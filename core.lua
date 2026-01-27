local ADDON, STP = ...
STP.db     = STP.db     or {}
STP.config = STP.config or {}
STP.util   = STP.util   or {}

STP.config.defaults = {
    showItemLevel = true,
    showTarget = true,
    showMount = true,
}

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then
            db[k] = v
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON then return end

    -- Config
    SimpleTooltipPlus_Config = SimpleTooltipPlus_Config or {}
    -- apply defaults if not present in saved variables
    ApplyDefaults(SimpleTooltipPlus_Config, STP.config.defaults)
    STP.db.config = SimpleTooltipPlus_Config

    self:UnregisterEvent("ADDON_LOADED")
end)