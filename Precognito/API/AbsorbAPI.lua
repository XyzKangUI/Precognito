local _, Precog = ...
local activeAuras = {}
local UnitGUID, blockGUID = UnitGUID, blockGUID
local pairs, next = pairs, next
local C_UnitAuras, C_Timer = C_UnitAuras, C_Timer
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local specificAbsorbs = {
    [77535] = true, -- Blood Shield
    [17545] = true, -- Greater Holy Protection
    [28538] = true, -- Major Holy Protection Potion
    [7245] = true, -- Holy Protection
    [6051] = true, -- Greater Holy Protection Potion
    [7233] = true, -- Fire Protection
    [17543] = true, -- Greater Fire Protection
    [53911] = true, -- Major Fire Protection
    [28511] = true, -- Major Fire Protection
    [7239] = true, -- Frost Protection
    [17544] = true, -- Greater Frost Protection Potion
    [28512] = true, -- Major Frost Protection
    [53913] = true, -- Mighty Frost Protection
    [17548] = true, -- Greater Shadow Protection
    [53915] = true, -- Mighty Shadow Protection
    [28537] = true, -- Major Shadow Protection
    [7242] = true, -- Shadow Protection
    [53910] = true, -- Mighty Arcane Protection
    [28536] = true, -- Major Arcane Protection
    [17549] = true, -- Greater Arcane Protection
    [17546] = true, -- Greater Nature Protection
    [28513] = true, -- Major Nature Protection
    [53914] = true, -- Mighty Nature Protection
    [7254] = true, -- Nature Protection
    [6229] = true, -- Shadow Ward
    [62606] = true, -- Savage Defense
    [17] = true, -- Power Word: Shield
    [86273] = true, -- Illuminated healing
    [11426] = true, -- Ice Barrier
    [98864] = true, -- Ice Barrier
    [47753] = true, -- Divine Aegis
    [88063] = true, -- Guarded by the Light
    [97129] = true, -- Loom of Fate
    [91711] = true, -- Nether Ward
    [543] = true, -- Mage Ward
    [1463] = true, -- Mana Shield
}

local scValues = {
    [58] = 337,
    [59] = 346,
    [60] = 346,
    [61] = 505,
    [62] = 514,
    [63] = 524,
    [64] = 533,
    [65] = 552,
    [66] = 561,
    [67] = 571,
    [68] = 589,
    [69] = 636,
    [70] = 655,
    [71] = 832,
    [72] = 870,
    [73] = 869,
    [74] = 935,
    [75] = 973,
    [76] = 1001,
    [77] = 1048,
    [78] = 1085,
    [79] = 1122,
    [80] = 1169,
    [81] = 2853,
    [82] = 3161,
    [83] = 3507,
    [84] = 3807,
    [85] = 4143,
}

local function resetBlockedGUID()
    blockGUID = nil
end

local function UnitAuras(unit, info)
    if info.isFullUpdate then
        return
    end

    local guid = UnitGUID(unit)
    if not guid then return end

    -- We can prevent firing multiple times for same unit--[[:]] "target" = "focus" = "nameplate1" = "arena1"
    if blockGUID == guid then
        return
    else
        blockGUID = guid
    end

    C_Timer.After(0, resetBlockedGUID)

    if not activeAuras[guid] then
        activeAuras[guid] = {}
    end

    local triggerEvent = false

    if info.addedAuras then
        for _, aura in pairs(info.addedAuras) do
            if aura and aura.isHelpful and specificAbsorbs[aura.spellId] and aura.points and aura.points[1] then
                local value = aura.points[1] or 0
                activeAuras[guid][aura.auraInstanceID] = { spellId = aura.spellId, amount = value }
                triggerEvent = true
            elseif aura and aura.spellId == 55277 then
                local absorbValue = UnitCreatureType(unit) == "Totem" and scValues[UnitLevel(unit)] or scValues[UnitLevel(unit)] * 4
                activeAuras[guid][aura.auraInstanceID] = { spellId = aura.spellId, amount = absorbValue or 0 }
                triggerEvent = true
            end
        end
    end

    if info.updatedAuraInstanceIDs then
        for _, auraInstanceID in pairs(info.updatedAuraInstanceIDs) do
            local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
            if aura and aura.isHelpful and specificAbsorbs[aura.spellId] and aura.points and aura.points[1] then
                local value = aura.points[1] or 0
                activeAuras[guid][aura.auraInstanceID] = { spellId = aura.spellId, amount = value }
                triggerEvent = true
            end
        end
    end

    if info.removedAuraInstanceIDs then
        for _, auraInstanceID in pairs(info.removedAuraInstanceIDs) do
            if auraInstanceID and activeAuras[guid][auraInstanceID] then
                activeAuras[guid][auraInstanceID] = nil
                triggerEvent = true
            end
        end
    end

    if triggerEvent then
        EventRegistry:TriggerEvent("Precognito", unit)
    end
end

local function SCTTracker(...)
    local _, eventType, _, _, _, _, _, destGUID, _, _, _, spellID, _, _, _, amount, _, _, arg19, _, _, arg22 = ...

    if eventType == "SPELL_ABSORBED" and activeAuras[destGUID] then
        local value = arg19
        spellID = amount
        if arg22 then
            spellID = arg19
            value = arg22
        end

        if spellID == 55277 then
            for auraInstanceID, aura in pairs(activeAuras[destGUID]) do
                if aura.spellId == spellID then
                    aura.amount = aura.amount - value
                    if aura.amount <= 0 then
                        activeAuras[destGUID][auraInstanceID] = nil
                    end
                end
            end

            if next(activeAuras[destGUID]) == nil then
                activeAuras[destGUID] = nil
            end

            EventRegistry:TriggerEvent("Precognito", destGUID)
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_AURA" then
        UnitAuras(...)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        SCTTracker(CombatLogGetCurrentEventInfo())
    else
        activeAuras = {}
    end
end)

function Precog.UnitGetTotalAbsorbs(unit)
    local guid = unit and UnitGUID(unit)
    if not guid or not activeAuras[guid] then
        return 0
    end

    local totalAbsorb = 0
    local validAuras = {}

    for auraInstanceID, auraData in pairs(activeAuras[guid]) do
        local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
        if aura or auraData.spellId == 55277 then
            totalAbsorb = totalAbsorb + auraData.amount
            validAuras[auraInstanceID] = auraData
        else
            activeAuras[guid][auraInstanceID] = nil
        end
    end

    activeAuras[guid] = validAuras
    return totalAbsorb
end

-- Who needs libs
_G["Precognito"] = Precog