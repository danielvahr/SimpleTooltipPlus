local _, STP = ...
STP.util = STP.util or {}

-- Util functions declaration
local function Scrub(...)
    if scrubsecretvalues then
        return scrubsecretvalues(...)
    end
    return ...
end

-- Export util functions
STP.util.Scrub = Scrub