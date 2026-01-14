------------------------------------------------------------------------
--
-- AbsorbsMonitor (TBC Update)
--
-- Copyright (C) 2010  Philipp Schmidt
-- Updated for Burning Crusade Classic
--
------------------------------------------------------------------------

local _, Precog = ...
local AM_Public = Precog
local AM_Core = {}
AM_Core.Events = {}
local floor = math.floor
local activeTimers = {}

---------------------
-- Install/Upgrade --
---------------------
local frame = CreateFrame("Frame", "AbsMon_Events");
frame:SetScript("OnEvent",
    function(self, event, ...)
        AM_Core.Events[event](...);
    end
);
AM_Core.Frame = frame;

---------------------
-- Local Variables --
---------------------

local AM_Events = AM_Core.Events;

local playerGUID;
local playerClass;
local lastCombatLogEvent = 0.0;
local activeEffectsBySpell;
local activeEffectsByPriority;
local activeCharges;
local Effects;
local CombatTriggersOnHeal;
local CombatTriggersOnHealCrit;
local CombatTriggersOnAuraApplied;
local CombatTriggersOnAuraRemoved;
local UnitStats;
local Scaling;
local privateScaling;
local playerScaling;

local OnEnableClass = {};
local ApplySingularEffect;
local HitUnit;
local RemoveActiveEffect;

local LOW_VALUE_TOLERANCE = 50;

----------------------
-- Helper functions --
----------------------

local function DeepTableCopy(src)
    local dest = {};
    for k, v in pairs(src) do
        if (type(k) == "table") then k = DeepTableCopy(k); end
        if (type(v) == "table") then v = DeepTableCopy(v); end
        dest[k] = v;
    end
    setmetatable(dest, getmetatable(src));
    return dest;
end

local function SortEffects(a, b)
    if (a[2] == b[2]) then
        return (a[3] < b[3]);
    else
        return (a[2] > b[2]);
    end
end

local GetUnitId = UnitTokenFromGUID
if not GetUnitId then
    GetUnitId = function(guid)
        if not guid then return end
        local unitIds = {
            { id = "player", max = false }, { id = "pet", max = false },
            { id = "party", max = 4 }, { id = "partypet", max = 4 },
            { id = "raid", max = 40 }, { id = "raidpet", max = 40 },
            { id = "nameplate", max = 40 }, { id = "target", max = false },
        }
        for _, unit in pairs(unitIds) do
            if unit.max then
                for i = 1, unit.max do
                    local unitId = unit.id .. i
                    if UnitGUID(unitId) == guid then return unitId end
                end
            else
                if UnitGUID(unit.id) == guid then return unit.id end
            end
        end
        return nil
    end
end

--------------------
-- Core functions --
--------------------

function AM_Core.PLAYER_LOGIN()
    _, playerClass = UnitClass("player");
    playerGUID = UnitGUID("player");

    AM_Core.activeEffects = { bySpell = {}, byPriority = {} };
    activeEffectsBySpell = AM_Core.activeEffects.bySpell;
    activeEffectsByPriority = AM_Core.activeEffects.byPriority;

    AM_Core.activeCharges = {};
    activeCharges = AM_Core.activeCharges;

    Effects = AM_Core.Effects;
    CombatTriggersOnHeal = AM_Core.CombatTriggers.OnHeal;
    CombatTriggersOnHealCrit = AM_Core.CombatTriggers.OnHealCrit;
    CombatTriggersOnAuraApplied = AM_Core.CombatTriggers.OnAuraApplied;
    CombatTriggersOnAuraRemoved = AM_Core.CombatTriggers.OnAuraRemoved;

    AM_Core.UnitStats = { [playerGUID] = { playerClass, 0, 0, 1.0 } };
    UnitStats = AM_Core.UnitStats;

    AM_Core.Scaling = { [-1] = {}, [playerGUID] = {} }
    Scaling = AM_Core.Scaling;

    playerScaling = Scaling[playerGUID];
    privateScaling = Scaling[-1];

    if (playerClass == "DRUID") then
        AM_Core.RegisterEvent("UNIT_ATTACK_POWER");
    elseif (playerClass == "MAGE" or playerClass == "PALADIN" or playerClass == "PRIEST" or playerClass == "WARLOCK") then
        AM_Core.RegisterEvent("PLAYER_DAMAGE_DONE_MODS");
    end

    AM_Events.STATS_CHANGED();
    if (OnEnableClass[playerClass]) then
        OnEnableClass[playerClass]();
    end

    if (AM_Events.PLAYER_LEVEL_UP) then AM_Core.RegisterEvent("PLAYER_LEVEL_UP"); end
    if (AM_Events.PLAYER_EQUIPMENT_CHANGED) then AM_Core.RegisterEvent("PLAYER_EQUIPMENT_CHANGED"); end

    AM_Core.RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
    AM_Public.Enabled = true;
end

function AM_Core.Disable()
    for guid, effects in pairs(activeEffectsBySpell) do
        EventRegistry:TriggerEvent("Precognito", guid)
    end
    wipe(AM_Core.activeEffects);
    wipe(AM_Core.activeCharges);
    wipe(AM_Core.Effects);
    wipe(AM_Core.CombatTriggers);
    wipe(AM_Core.UnitStats);
    wipe(AM_Core.Scaling);
    wipe(AM_Core.Events);
    AM_Core.Frame:UnregisterAllEvents();
    AM_Core:CancelAllTimers()
    AM_Public.Enabled = false;
end

function AM_Core.RegisterEvent(name) AM_Core.Frame:RegisterEvent(name); end
function AM_Core.UnregisterEvent(name) AM_Core.Frame:UnregisterEvent(name); end

function AM_Core.ApplySingularEffect(sourceGUID, sourceName, destGUID, destName, spellId)
    local destEffects = activeEffectsBySpell[destGUID];
    local effectInfo = Effects[spellId];
    local effectEntry;

    local timerId = destGUID .. "_" .. spellId

    local value, quality, extra = effectInfo[3](sourceGUID, sourceName, destGUID, destName, spellId, destEffects);
    if (value == nil) then return; end

    if (not destEffects) then
        effectEntry = { spellId, effectInfo[1], value, value, quality, timerId, extra };
        destEffects = { [-1] = 0, [-2] = 1.0, [spellId] = effectEntry };
        activeEffectsBySpell[destGUID] = destEffects
        activeEffectsByPriority[destGUID] = { effectEntry };
        EventRegistry:TriggerEvent("Precognito", destGUID, destGUID, destGUID, destGUID)

    elseif (not destEffects[spellId]) then
        effectEntry = { spellId, effectInfo[1], value, value, quality, timerId, extra };
        destEffects[spellId] = effectEntry;
        tinsert(activeEffectsByPriority[destGUID], effectEntry);
        sort(activeEffectsByPriority[destGUID], SortEffects);
        EventRegistry:TriggerEvent("Precognito", destGUID)
    else
        effectEntry = destEffects[spellId];
        local prevAmount = effectEntry[3];

        effectEntry[3] = value;
        effectEntry[4] = value;
        effectEntry[5] = quality;
        effectEntry[6] = timerId;
        effectEntry[7] = extra;

        sort(activeEffectsByPriority[destGUID], SortEffects);
        EventRegistry:TriggerEvent("Precognito", destGUID)

        value = value - prevAmount;
        AM_Core:CancelTimer(timerId);
    end

    if quality and (quality < destEffects[-2]) then
        destEffects[-2] = quality;
    end

    if effectInfo[1] and (effectInfo[1] < 2) then
        destEffects[-1] = destEffects[-1] + value;
        EventRegistry:TriggerEvent("Precognito", destGUID)
    end

    if (effectInfo[2]) then
        AM_Core:ScheduleUniqueTimer(effectEntry[6], AM_Events.OnSingularTimeout, effectInfo[2] + 5, { destGUID, spellId })
    else
        AM_Core:ScheduleRepeatingTimer(effectEntry[6], AM_Events.OnSingularActivityCheck, 8, { destGUID, spellId })
    end
end

function AM_Core.HitUnit(guid, absorbedTotal, overkill, spellSchool)
    local guidEffects = activeEffectsBySpell[guid];
    if (not guidEffects) then return; end

    local absorbedRemaining = absorbedTotal;
    local absorbed = 0;
    local keepEffect, visibleAbsorb = false, false;
    local i = 1;
    local effectEntry;

    while (absorbedRemaining > 0) do
        effectEntry = activeEffectsByPriority[guid][i];
        if (effectEntry == nil) then break; end

        if effectEntry[3] and (effectEntry[3] ~= 0) then
            absorbed, keepEffect = Effects[effectEntry[1]][4](effectEntry, absorbedRemaining, overkill, spellSchool);
            if absorbed and (absorbed > 0) then
                effectEntry[3] = effectEntry[3] - absorbed;
                absorbedRemaining = absorbedRemaining - absorbed;

                if effectEntry[2] and (effectEntry[2] < 2) then
                    guidEffects[-1] = guidEffects[-1] - absorbed;
                    visibleAbsorb = true;
                end
                EventRegistry:TriggerEvent("Precognito", guid)
            end

            if (not keepEffect) then
                effectEntry[3] = 0;
            end
        end
        i = i + 1;
    end

    if absorbedRemaining and (absorbedRemaining > LOW_VALUE_TOLERANCE) then
        guidEffects[-1] = guidEffects[-1] - absorbedRemaining;
        guidEffects[-2] = 0.0;
        visibleAbsorb = true;
    end

    if (visibleAbsorb) then
        EventRegistry:TriggerEvent("Precognito", guid)
    end
end

function AM_Core.RemoveActiveEffect(guid, spellId)
    if not activeEffectsBySpell or not activeEffectsBySpell[guid] then return end

    local guidEffects = activeEffectsBySpell[guid];
    local effectEntry = guidEffects[spellId];

    if not effectEntry then return end

    if (effectEntry[8]) then
        effectEntry[9] = effectEntry[9] - 1;
        if (guid ~= effectEntry[8]) then
            EventRegistry:TriggerEvent("Precognito", guid)
        end
    else
        if effectEntry[2] and (effectEntry[2] < 2) then
            guidEffects[-1] = guidEffects[-1] - effectEntry[3];
            EventRegistry:TriggerEvent("Precognito", guid)
        end

        if effectEntry[6] then
            AM_Core:CancelTimer(effectEntry[6])
        end

        EventRegistry:TriggerEvent("Precognito", guid)
    end

    if (#(activeEffectsByPriority[guid]) == 1) then
        activeEffectsBySpell[guid] = nil;
        activeEffectsByPriority[guid] = nil;
        EventRegistry:TriggerEvent("Precognito", guid)
    else
        guidEffects[spellId] = nil;
        for k, v in pairs(activeEffectsByPriority[guid]) do
            if (v[1] == spellId) then
                tremove(activeEffectsByPriority[guid], k);
                break ;
            end
        end
    end
end

function AM_Core.PushCharge(guid, spellId, amount, lifetime)
    local guidCharges = activeCharges[guid];
    if (not guidCharges) then
        activeCharges[guid] = { [spellId] = { lastCombatLogEvent + lifetime, amount } };
    elseif (not guidCharges[spellId]) then
        guidCharges[spellId] = { lastCombatLogEvent + lifetime, amount };
    else
        tinsert(guidCharges[spellId], lastCombatLogEvent + lifetime);
        tinsert(guidCharges[spellId], amount);
    end
end

function AM_Core.PopCharge(guid, spellId)
    local guidCharges = activeCharges[guid];
    if (guidCharges) then
        local queue = activeCharges[guid][spellId];
        if (queue and queue[2]) then
            local chargeAmount;
            local chargeExpire;
            while (true) do
                chargeAmount = tremove(queue, 2);
                if (not chargeAmount) then return 0; end
                chargeExpire = tremove(queue, 1);
                if chargeExpire and (chargeExpire > lastCombatLogEvent) then
                    return chargeAmount;
                end
            end
        end
    end
    return 0;
end

function AM_Core.AddCombatTrigger(target, event, func)
    local eventTriggers = AM_Core.CombatTriggers[event];
    local oldTrigger = eventTriggers[target];
    if (not oldTrigger) then
        eventTriggers[target] = func;
    else
        local listIndex = target .. "_list";
        local funcList = eventTriggers[listIndex];
        if (funcList) then
            for k, v in pairs(funcList) do
                if (v == func) then return; end
            end
            tinsert(funcList, func);
        else
            if (oldTrigger == func) then return; end
            funcList = { oldTrigger, func };
            eventTriggers[listIndex] = funcList;
            local handler = function(...)
                for k, v in pairs(funcList) do v(...); end
            end
            eventTriggers[target] = handler;
        end
    end
end

function AM_Core.RemoveCombatTrigger(target, event, func)
    local eventTriggers = AM_Core.CombatTriggers[event];
    local listIndex = target .. "_list";
    local funcList = eventTriggers[listIndex];
    if (funcList) then
        if (#funcList == 2) then
            eventTriggers[target] = (funcList[1] == func) and funcList[2] or funcList[1];
            eventTriggers[listIndex] = nil;
        else
            local old_funcList = DeepTableCopy(funcList);
            wipe(funcList);
            for k, v in pairs(old_funcList) do
                if (v ~= func) then tinsert(funcList, v); end
            end
        end
    else
        eventTriggers[target] = nil;
    end
end

function AM_Core:ScheduleUniqueTimer(id, callback, delay, arg)
    if activeTimers[id] then AM_Core:CancelTimer(id) end

    activeTimers[id] = C_Timer.NewTimer(delay, function()
        activeTimers[id] = nil
        callback(arg)
    end)
end

function AM_Core:ScheduleRepeatingTimer(id, callback, interval, arg)
    if activeTimers[id] then AM_Core:CancelTimer(id) end

    activeTimers[id] = C_Timer.NewTicker(interval, function()
        callback(arg)
    end)
end

function AM_Core:CancelTimer(id)
    local timer = activeTimers[id]
    if timer and timer.Cancel then
        timer:Cancel()
    end
    activeTimers[id] = nil
end

function AM_Core:CancelAllTimers()
    for id, _ in pairs(activeTimers) do
        AM_Core:CancelTimer(id)
    end
end

ApplySingularEffect = AM_Core.ApplySingularEffect;
HitUnit = AM_Core.HitUnit;
RemoveActiveEffect = AM_Core.RemoveActiveEffect;

---------------------
-- Event functions --
---------------------

function AM_Events.PLAYER_ENTERING_WORLD()
    if (not GetTalentInfo(1, 1)) then
        AM_Core.RegisterEvent("PLAYER_ALIVE");
    else
        AM_Core.Available = true;
        AM_Core.PLAYER_LOGIN();
    end
    AM_Core.UnregisterEvent("PLAYER_ENTERING_WORLD");
end

function AM_Events.PLAYER_ALIVE()
    AM_Core.Available = true;
    AM_Core.PLAYER_LOGIN();
    AM_Core.UnregisterEvent("PLAYER_ALIVE");
end

function AM_Events.COMBAT_LOG_EVENT_UNFILTERED()
    local timestamp, type, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellID, arg13, arg14, arg15, arg16, arg17, arg18, _, arg20 = CombatLogGetCurrentEventInfo()

    lastCombatLogEvent = timestamp;

    if (type == "SWING_DAMAGE") then
        local amount, absorbed = arg14, arg17

        if (not absorbed) then
            return ;
        end

        HitUnit(destGUID, absorbed, amount, SCHOOL_MASK_PHYSICAL);

    elseif (type == "RANGE_DAMAGE" or type == "SPELL_DAMAGE" or type == "SPELL_PERIODIC_DAMAGE") then
        local amount, absorbed, spellSchool = arg15, arg20, arg13

        if (not absorbed) then
            return ;
        end

        HitUnit(destGUID, absorbed, amount, spellSchool);

    elseif (type == "SWING_MISSED") then
        local missType, amountMissed = spellID, arg14

        if (missType ~= "ABSORB") then
            return ;
        end

        HitUnit(destGUID, amountMissed, 0, SCHOOL_MASK_PHYSICAL);

    elseif (type == "RANGE_MISSED" or type == "SPELL_MISSED" or type == "SPELL_PERIODIC_MISSED") then
        local missType, amountMissed, spellSchool = arg15, arg17, arg13

        if (missType ~= "ABSORB") then
            return ;
        end

        HitUnit(destGUID, amountMissed, 0, spellSchool);

    elseif (type == "SPELL_HEAL") then
        local spellId, amount, overhealing, critical = spellID, arg15, arg16, arg18

        if (CombatTriggersOnHeal[sourceGUID]) then
            CombatTriggersOnHeal[sourceGUID](sourceGUID, sourceName, destGUID, destName, spellId, amount, overhealing);
        end

        if (critical and CombatTriggersOnHealCrit[sourceGUID]) then
            CombatTriggersOnHealCrit[sourceGUID](sourceGUID, sourceName, destGUID, destName, spellId, amount, overhealing);
        end
    elseif (type == "SPELL_AURA_APPLIED") then
        local spellId = spellID

        if (Effects[spellId]) then
            if (Effects[spellId][1] > 0) then
                ApplySingularEffect(sourceGUID, sourceName, destGUID, destName, spellId);
            end
        end

        if (CombatTriggersOnAuraApplied[spellId]) then
            CombatTriggersOnAuraApplied[spellId](sourceGUID, sourceName, destGUID, destName, spellId);
        end

    elseif (type == "SPELL_AURA_REFRESH") then
        local spellId = spellID

        if (Effects[spellId]) then
            if (Effects[spellId][1] > 0) then
                ApplySingularEffect(sourceGUID, sourceName, destGUID, destName, spellId);
            end
        end

        if (CombatTriggersOnAuraApplied[spellId]) then
            CombatTriggersOnAuraApplied[spellId](sourceGUID, sourceName, destGUID, destName, spellId);
        end

    elseif (type == "SPELL_AURA_REMOVED") then
        local spellId = spellID

        if (Effects[spellId]) then
            if (activeEffectsBySpell[destGUID] and activeEffectsBySpell[destGUID][spellId]) then
                RemoveActiveEffect(destGUID, spellId);
            end
        end

        if (CombatTriggersOnAuraRemoved[spellId]) then
            CombatTriggersOnAuraRemoved[spellId](sourceGUID, sourceName, destGUID, destName, spellId);
        end
    end
end

function AM_Events.STATS_CHANGED()
    local baseAP, plusAP, minusAP = UnitAttackPower("player");
    UnitStats[playerGUID][2] = baseAP + plusAP + minusAP;

    if (playerClass == "MAGE") then
        local frost = GetSpellBonusDamage(5)
        local fire = GetSpellBonusDamage(3)
        local arcane = GetSpellBonusDamage(7)
        UnitStats[playerGUID][3] = math.max(frost, fire, arcane)
    elseif (playerClass == "WARLOCK") then
        UnitStats[playerGUID][3] = GetSpellBonusDamage(6); -- Shadow
    else
        UnitStats[playerGUID][3] = GetSpellBonusHealing();
    end
end

function AM_Events.OnSingularTimeout(args)
    local guid, spellId = args[1], args[2];
    if (activeEffectsBySpell[guid] and activeEffectsBySpell[guid][spellId]) then
        RemoveActiveEffect(guid, spellId);
    end
end

function AM_Events.OnSingularActivityCheck(args)
    local guid, spellId = args[1], args[2];
    if (activeEffectsBySpell[guid] and activeEffectsBySpell[guid][spellId]) then
        local _, _, _, _, _, name = GetPlayerInfoByGUID(guid);
        if (not name) then
            if activeEffectsBySpell[guid][spellId][6] then AM_Core:CancelTimer(activeEffectsBySpell[guid][spellId][6]) end
            RemoveActiveEffect(guid, spellId);
        end

        local stillActive = false;
        for i = 1, 40 do
            local _, _, _, _, _, _, _, _, _, buffId = UnitBuff(name, i);
            if (not buffId) then break; end
            if (buffId == spellId) then stillActive = true; break; end
        end

        if (not stillActive) then
            if activeEffectsBySpell[guid][spellId][6] then AM_Core:CancelTimer(activeEffectsBySpell[guid][spellId][6]) end
            RemoveActiveEffect(guid, spellId);
        end
    else
        if activeEffectsBySpell[guid][spellId][6] then AM_Core:CancelTimer(activeEffectsBySpell[guid][spellId][6]) end
    end
end

AM_Events.PLAYER_DAMAGE_DONE_MODS = AM_Events.STATS_CHANGED;
AM_Events.UNIT_ATTACK_POWER = AM_Events.STATS_CHANGED;

----------------------
-- Public functions --
----------------------

function AM_Public.Unit_Total(guid)
    local guidEffects = activeEffectsBySpell and activeEffectsBySpell[guid];
    return (guidEffects and guidEffects[-1] or 0);
end

function AM_Public.PrintActiveEffectsBySpell(guid)
    if not activeEffectsBySpell or not activeEffectsBySpell[guid] then return end
    for spellId, effect in pairs(activeEffectsBySpell[guid]) do
        if spellId and spellId > 0 then
            local name = GetSpellInfo(spellId)
            if name then print("Spell absorb active:", name, "val:", effect[3]) end
        else break end
    end
end

function AM_Public.Unit_Stats(guid, missingQuality)
    local guidStats = UnitStats[guid];
    if (guidStats) then return guidStats[2], guidStats[3], guidStats[4];
    else return 0, 0, missingQuality; end
end

function AM_Public.Unit_Scaling(guid, defaultScaling, defaultQuality)
    local guidScaling = Scaling[guid];
    if (guidScaling) then return guidScaling, 1.0;
    else return defaultScaling, defaultQuality; end
end

function AM_Public.Unit_StatsAndScaling(guid, missingQuality, defaultScaling, defaultQuality)
    local guidStats = UnitStats[guid];
    local guidScaling = Scaling[guid];
    if (guidStats) then
        if (guidScaling) then return guidStats[2], guidStats[3], guidStats[4], guidScaling, 1.0;
        else return guidStats[2], guidStats[3], guidStats[4], defaultScaling, defaultQuality; end
    else
        if (guidScaling) then return 0, 0, missingQuality, guidScaling, 1.0;
        else return 0, 0, missingQuality, defaultScaling, defaultQuality; end
    end
end

------------------------------
-- Generic Effect functions --
------------------------------

local PushCharge = AM_Core.PushCharge;
local PopCharge = AM_Core.PopCharge;
local Unit_Stats = AM_Public.Unit_Stats;
local Unit_Scaling = AM_Public.Unit_Scaling;
local Unit_StatsAndScaling = AM_Public.Unit_StatsAndScaling;

local function generic_ConstantByTable_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    return Effects[spellId][5][spellId], 1.0;
end

local function generic_SpellScalingByTable_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local effectInfo = Effects[spellId];
    local _, _, quality = Unit_Stats(sourceGUID, 0.1);
    return floor(effectInfo[5][spellId]), quality;
end

local function generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (absorbedRemaining > effectEntry[3]) then
        absorbedRemaining = effectEntry[3];
        overkill = 1;
    end
    return absorbedRemaining, (overkill == 0);
end

-------------------
-- Effects: Mage --
-------------------

local mage_Absorb_Spells = {
    -- Fire Ward (Ranks 1-6)
    [543] = 164,    [8457] = 289,   [8458] = 469,
    [10223] = 674,  [10225] = 874,  [27128] = 1124,
    -- Frost Ward (Ranks 1-6)
    [6143] = 164,   [8461] = 289,   [8462] = 469,
    [10177] = 674,  [28609] = 874,  [32796] = 1124,
    -- Ice Barrier (Ranks 1-6)
    [11426] = 437,  [13031] = 548,  [13032] = 677,
    [13033] = 817,  [27134] = 924,  [33405] = 1075,
    -- Mana Shield (Ranks 1-7)
    [1463] = 119,   [8494] = 209,   [8495] = 299,
    [10191] = 389,  [10192] = 479,  [10193] = 569,
    [27131] = 714,
};

local mage_defaultScaling = { [33405] = 0.3, [27134] = 0.3, [13033] = 0.1 };

local function mage_IceBarrier_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local _, sp, quality1, sourceScaling, quality2 = Unit_StatsAndScaling(sourceGUID, 0.1, mage_defaultScaling, 0.1);
    local coefficient = 0.3
    if sourceScaling and sourceScaling[spellId] then coefficient = sourceScaling[spellId] end
    local baseValue = mage_Absorb_Spells[spellId] or 0
    return floor(baseValue + (sp * coefficient)), math.min(quality1, quality2);
end

local function mage_ManaShield_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local _, sp, quality = Unit_Stats(sourceGUID, 0.1);
    local baseValue = mage_Absorb_Spells[spellId] or 0;
    return floor(baseValue + (sp * 0.50)), quality; -- 50% Coeff (TBC 2.4)
end

local function mage_Ward_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local _, sp, quality = Unit_Stats(sourceGUID, 0.1);
    local baseValue = mage_Absorb_Spells[spellId] or 0;
    return floor(baseValue + (sp * 0.10)), quality;
end

local function mage_FireWard_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_FIRE) then return 0, true; end
    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

local function mage_FrostWard_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_FROST) then return 0, true; end
    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

---------------------
-- Effects: Priest --
---------------------
-- [rank] = {spellId, LearnLevel, BaseValue, PointsPerLevel}
local priest_PWS_Ranks = {
    [1] = { 17, 6, 43, 0.8 },
    [2] = { 592, 12, 87, 1.2 },
    [3] = { 600, 18, 157, 1.6 },
    [4] = { 3747, 24, 233, 2.0 },
    [5] = { 6065, 30, 300, 2.3 },
    [6] = { 6066, 36, 380, 2.6 },
    [7] = { 10898, 42, 483, 3.0 },
    [8] = { 10899, 48, 604, 3.4 },
    [9] = { 10900, 54, 762, 3.9 },
    [10] = { 10901, 60, 941, 4.3 },
    [11] = { 25217, 65, 1124, 4.7 },
    [12] = { 25218, 70, 1264, 5.1 },
};

local function priest_ApplyScaling(guid, level, baseFactor, spFactor)
    local guidScaling = Scaling[guid] or {};
    Scaling[guid] = guidScaling;
    local rankValue, rankSP;

    for k, v in pairs(priest_PWS_Ranks) do
        if (v[2] <= level) then
            local ppl = v[4] or 0
            local learnLevel = v[2]
            local levelBonus = 0
            if level > learnLevel then
                levelBonus = (math.min(level, learnLevel + 5) - learnLevel) * ppl
                if levelBonus < 0 then levelBonus = 0 end
            end
            rankValue = v[3] + levelBonus

            if (v[2] + 6 < level) then
                local penalty = (v[2] + 6) / level
                rankSP = spFactor * penalty
            else
                rankSP = spFactor
            end

            guidScaling[v[1]] = { rankValue * baseFactor, rankSP };
        end
    end
end

local function priest_UpdatePlayerScaling()
    local healing = 1 + (privateScaling["SpiritualHealing"] or 0) * 0.02
    local pws = 1 + (privateScaling["ImpPWS"] or 0) * 0.05
    privateScaling.base = healing * pws

    -- Patch 2.3.0: Gains additional benefit from bonus healing (Set to 30%)
    privateScaling.sp = 0.3 * privateScaling.base

    priest_ApplyScaling(playerGUID, UnitLevel("player"), privateScaling.base, privateScaling.sp)
end


local function priest_ScanTalents()
    -- Improved Power Word: Shield
    local _, _, _, _, t = GetTalentInfo(1, 5);
    privateScaling["ImpPWS"] = t or 0;
    -- Spiritual Healing
    local _, _, _, _, t2 = GetTalentInfo(2, 16);
    privateScaling["SpiritualHealing"] = t2 or 0;
end

local function priest_OnLevelUp() priest_UpdatePlayerScaling(); end
local function priest_OnTalentUpdate() priest_ScanTalents(); priest_UpdatePlayerScaling(); end
local function priest_OnEquipmentChanged() priest_UpdatePlayerScaling(); end

function OnEnableClass.PRIEST()
    AM_Core.RegisterEvent("PLAYER_TALENT_UPDATE");
    priest_ScanTalents();
    priest_UpdatePlayerScaling();
    AM_Events.PLAYER_TALENT_UPDATE = priest_OnTalentUpdate
    AM_Events.PLAYER_LEVEL_UP = priest_OnLevelUp
    AM_Events.PLAYER_EQUIPMENT_CHANGED = priest_OnEquipmentChanged
end

local function priest_PowerWordShield_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local _, sp, quality1, sourceScaling, quality2 = Unit_StatsAndScaling(sourceGUID, 0.1, nil, 0.1);

    if not sourceScaling or not sourceScaling[spellId] then
        local base = 0
        for _, v in pairs(priest_PWS_Ranks) do
            if v[1] == spellId then base = v[3] break end
        end
        return floor(base + (sp * 0.30)), math.min(quality1, quality2)
    end

    local scalingData = sourceScaling[spellId]
    local baseValue = scalingData[1]
    local spCoefficient = scalingData[2]

    return floor(baseValue + (sp * spCoefficient)), math.min(quality1, quality2)
end

----------------------
-- Effects: Warlock --
----------------------

local warlock_Sacrifice_Spells = {
    [7812] = 304,   [19438] = 509,  [19440] = 769,
    [19441] = 1094, [19442] = 1469, [19443] = 1904,
    [27273] = 2854,
}
local warlock_ShadowWard_Spells = {
    [6229] = 289,   [11739] = 469,
    [11740] = 674,  [28610] = 874,
};
local warlock_defaultScaling = { 1.0 };

local function warlock_UpdatePlayerScaling()
    local multiplier = 1 + (privateScaling["ImpVoidwalker"] or 0) * 0.10
    wipe(playerScaling)
    playerScaling[1] = 1.0 * multiplier
end

local function warlock_ScanTalents()
    -- Improved Voidwalker (Demo 2, 5)
    local _, _, _, _, t = GetTalentInfo(2, 5);
    privateScaling["ImpVoidwalker"] = t or 0;
end

function OnEnableClass.WARLOCK()
    AM_Core.RegisterEvent("PLAYER_TALENT_UPDATE");
    warlock_ScanTalents();
    warlock_UpdatePlayerScaling();
    AM_Events.PLAYER_TALENT_UPDATE = function() warlock_ScanTalents(); warlock_UpdatePlayerScaling(); end
end

local function warlock_Sacrifice_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local scalingTable, quality = Unit_Scaling(sourceGUID, warlock_defaultScaling, 0.4);
    local multiplier = scalingTable[1] or 1.0
    return floor(warlock_Sacrifice_Spells[spellId] * multiplier), quality;
end

local function warlock_ShadowWard_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local _, sp, quality = Unit_Stats(sourceGUID, 0.1);
    local baseValue = warlock_ShadowWard_Spells[spellId] or 0;
    return floor(baseValue + (sp * 0.30)), quality;
end

local function warlock_ShadowWard_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_SHADOW) then return 0, true; end
    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

local function warlock_spellStone_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool == SCHOOL_MASK_PHYSICAL) or (spellSchool == SCHOOL_MASK_NONE) then return 0, true; end
    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

--------------------
-- Effects: Items --
--------------------

local function items_ScarabBrooch_OnHeal(sourceGUID, sourceName, destGUID, destName, spellId, amount)
    PushCharge(destGUID, 26470, floor(amount * 0.15), 5.0);
end

local function items_ScarabBrooch_OnAuraApplied(sourceGUID, sourceName, destGUID, destName, spellId)
    AM_Core.AddCombatTrigger(sourceGUID, "OnHeal", items_ScarabBrooch_OnHeal);
end

local function items_ScarabBrooch_OnAuraRemoved(sourceGUID, sourceName, destGUID, destName, spellId)
    AM_Core.RemoveCombatTrigger(sourceGUID, "OnHeal", items_ScarabBrooch_OnHeal);
end

local function items_ScarabBrooch_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local existing = 0;
    if (destEffects and destEffects[spellId]) then existing = destEffects[spellId][3]; end
    local charge = PopCharge(destGUID, spellId);
    if (charge == 0) then return existing, 0.0; end
    return (existing + charge), 1.0
end

local function CreateAbsorbHit(magicSchool)
    return function(effectEntry, absorbedRemaining, overkill, spellSchool)
        if (spellSchool ~= magicSchool) then
            return 0, true;
        end
        return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
    end
end


-----------------
-- Data Tables --
-----------------

local mage_FireWard_Entry = { 2.0, 30, mage_Ward_Create, mage_FireWard_Hit, mage_Absorb_Spells };
local mage_FrostWard_Entry = { 2.0, 30, mage_Ward_Create, mage_FrostWard_Hit, mage_Absorb_Spells };
local mage_IceBarrier_Entry = { 1.0, 60, mage_IceBarrier_Create, generic_Hit };
local mage_ManaShield_Entry = { 1.0, 60, mage_ManaShield_Create, generic_Hit, mage_Absorb_Spells };
local priest_PWS_Entry = { 1.0, 30, priest_PowerWordShield_Create, generic_Hit };
local warlock_Sacrifice_Entry = { 1.0, 30, warlock_Sacrifice_Create, generic_Hit, warlock_Sacrifice_Spells };
local warlock_ShadowWard_Entry = { 2.0, 30, warlock_ShadowWard_Create, warlock_ShadowWard_Hit, warlock_ShadowWard_Spells };

AM_Core.Effects = {
    [0] = { 1.0, 0, function() return 0, 0.0; end, nil };

    -- MAGE
    [543] = mage_FireWard_Entry,   [8457] = mage_FireWard_Entry,
    [8458] = mage_FireWard_Entry,  [10223] = mage_FireWard_Entry,
    [10225] = mage_FireWard_Entry, [27128] = mage_FireWard_Entry,
    [6143] = mage_FrostWard_Entry,  [8461] = mage_FrostWard_Entry,
    [8462] = mage_FrostWard_Entry,  [10177] = mage_FrostWard_Entry,
    [28609] = mage_FrostWard_Entry, [32796] = mage_FrostWard_Entry,
    [11426] = mage_IceBarrier_Entry, [13031] = mage_IceBarrier_Entry,
    [13032] = mage_IceBarrier_Entry, [13033] = mage_IceBarrier_Entry,
    [27134] = mage_IceBarrier_Entry, [33405] = mage_IceBarrier_Entry,
    [1463] = mage_ManaShield_Entry,  [8494] = mage_ManaShield_Entry,
    [8495] = mage_ManaShield_Entry,  [10191] = mage_ManaShield_Entry,
    [10192] = mage_ManaShield_Entry, [10193] = mage_ManaShield_Entry,
    [27131] = mage_ManaShield_Entry,

    -- PRIEST
    [17] = priest_PWS_Entry,    [592] = priest_PWS_Entry,
    [600] = priest_PWS_Entry,   [3747] = priest_PWS_Entry,
    [6065] = priest_PWS_Entry,  [6066] = priest_PWS_Entry,
    [10898] = priest_PWS_Entry, [10899] = priest_PWS_Entry,
    [10900] = priest_PWS_Entry, [10901] = priest_PWS_Entry,
    [25217] = priest_PWS_Entry, [25218] = priest_PWS_Entry,

    -- WARLOCK
    [7812] = warlock_Sacrifice_Entry,  [19438] = warlock_Sacrifice_Entry,
    [19440] = warlock_Sacrifice_Entry, [19441] = warlock_Sacrifice_Entry,
    [19442] = warlock_Sacrifice_Entry, [19443] = warlock_Sacrifice_Entry,
    [27273] = warlock_Sacrifice_Entry,
    [6229] = warlock_ShadowWard_Entry, [11739] = warlock_ShadowWard_Entry,
    [11740] = warlock_ShadowWard_Entry, [28610] = warlock_ShadowWard_Entry,

    -- ITEMS
    [26470] = { 1.0, 8, items_ScarabBrooch_Create, generic_Hit },
    [29506] = { 1.0, 20, function() return 900, 1.0; end, generic_Hit },
    [23506] = { 1.0, 20, function() return 1000, 0.5; end, generic_Hit },
    [27779] = { 1.0, 30, function() return 349, 1.0; end, generic_Hit },
    [28810] = { 1.0, 30, function() return 499, 1.0; end, generic_Hit },
    [27688] = { 1.0, 300, function() return 2499, 1.0; end, generic_Hit },
    
    -- Major Fire Protection Potion
    [28511] = { 1.0, 120, function() return 3400, 1.0; end, CreateAbsorbHit(SCHOOL_MASK_FIRE) },
    -- Major Frost Protection Potion
    [28512] = { 1.0, 120, function() return 3400, 1.0; end, CreateAbsorbHit(SCHOOL_MASK_FROST) },
    -- Major Nature Protection Potion
    [28513] = { 1.0, 120, function() return 3400, 1.0; end, CreateAbsorbHit(SCHOOL_MASK_NATURE) },
    -- Major Shadow Protection Potion
    [28537] = { 1.0, 120, function() return 3400, 1.0; end, CreateAbsorbHit(SCHOOL_MASK_SHADOW) },
    -- Major Arcane Protection Potion
    [28536] = { 1.0, 120, function() return 3400, 1.0; end, CreateAbsorbHit(SCHOOL_MASK_ARCANE) },
    -- Major Holy Protection Potion
    [28538] = { 1.0, 120, function() return 3400, 1.0; end, CreateAbsorbHit(SCHOOL_MASK_HOLY) },

    -- Nigh-Invulnerability Belt
    [30458] = { 1.0, 8, function() return 4000, 1.0; end, generic_Hit },

};

AM_Core.CombatTriggers = {
    OnAuraApplied = { [26470] = items_ScarabBrooch_OnAuraApplied },
    OnAuraRemoved = { [26470] = items_ScarabBrooch_OnAuraRemoved },
    OnHeal = {},
    OnHealCrit = {}
};

----------------
-- Initialize --
----------------

if (not AM_Core.Available) then
    AM_Core.RegisterEvent("PLAYER_ENTERING_WORLD");
else
    AM_Core.PLAYER_LOGIN();
end

_G["Precognito"] = Precog