------------------------------------------------------------------------
--
-- AbsorbsMonitor
--
-- Copyright (C) 2010  Philipp Schmidt
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to:
--
-- Free Software Foundation, Inc.,
-- 51 Franklin Street, Fifth Floor,
-- Boston, MA  02110-1301, USA.
--
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

-- Specifies the channel any AddOn message should be
-- sent to, nil if silent
-- Can also be used to get the last known party state
local curChatChannel = nil;

-- Always hold the timestamp from the last COMBAT_LOG_EVENT_UNFILTERED fired
local lastCombatLogEvent = 0.0;

-- Table of all active absorb effects indexed by GUID and then spellId
-- at spellId == -1 there is a numeric entry with the total remaining value,
-- at spellId == -2 there is a numeric entry with the total quality (that is, the minimal quality)
-- The priority is also in this table for performance reasons during sort
-- [GUID] = { [spellId] = {spellId, priority, remainingValue, maxValue, quality, durationTimerHandle, extra} }
-- Shortcut to AM_Core.activeEffects.bySpell
local activeEffectsBySpell;

-- Table of all active absorb effects indexed by GUID and then a list in the order in which
-- they will be used
-- Shortcut to AM_Core.activeEffects.byPriority
local activeEffectsByPriority;

-- Table of current unit charges
-- A charge is a variant value a custom trigger can put on any unit with a limited lifetime
-- It is organized as a (very simple) queue (FIFO) for use with Divine Aegis e.g. to save the
-- critical heal value and then apply it on the aura gain or with Val'anyr.
-- [GUID] = { [spellId] = { charge1, charge2, ... } }
-- Shortcut to AM_Core.activeCharges
local activeCharges;

-- Table of known spells that cause an absorb effects
-- priority: active effects above 2 are neither used in total value nor displayed (e.g. Anti-Magic Shell)
-- [spellId] = {priority, duration, createFunc, hitFunc}
-- Shortcut to AM_Core.EffectInfo
local Effects;

-- Table of additional callbacks on combat log events for proc-based and other non-generic absorb effects.
-- Shortcuts to entries of AM_Core.CombatTriggers
local CombatTriggersOnHeal;
local CombatTriggersOnHealCrit;
local CombatTriggersOnAuraApplied;
local CombatTriggersOnAuraRemoved;

-- Table of all unit stats relevant to absorb effects like attack power and spell power
-- (mastery rating later on)
-- [GUID] = { class, AttackPower, SpellPower, quality }
-- Shortcut to AM_Core.UnitStats
local UnitStats;

-- Table of all scaling factors to absorb effects like talents, items, set boni, buffs
-- If there is no mechanism in Cataclysm to obtain the correct absorb amount by any effect
-- this entries are meant to be distributed among a group, raid, etc
-- [GUID] = { [scaling_Name] = scaling_Value }
-- A numerical scaling_name above 10 should ONLY be used if it is the spellId of the affected effect,
-- since it is sometimes used as a very quick way to check for a unit's class
-- Scaling factors that are only relevant to the local user like priest talents and do not
-- need to be distributed but are needed for calculation of the public one's are private ones,
-- found at index -1
-- Shortcuts to AM_Core.Scaling and its entries
local Scaling;
local privateScaling;
local playerScaling;

-- Class-specific callbacks
local OnEnableClass = {};
-- Shortcut to the most important core functions
local ApplySingularEffect;
local HitUnit;
local RemoveActiveEffect;

-- Constants
local LOW_VALUE_TOLERANCE = 50;

----------------------
-- Helper functions --
----------------------

local function DeepTableCopy(src)
    local dest = {};

    for k, v in pairs(src) do
        if (type(k) == "table") then
            k = DeepTableCopy(k);
        end

        if (type(v) == "table") then
            v = DeepTableCopy(v);
        end

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

-- Tries to get a working unitId
local GetUnitId = UnitTokenFromGUID

if not GetUnitId then
    GetUnitId = function(guid)
        if not guid then
            return
        end

        local unitIds = {
            { id = "player", max = false },
            { id = "pet", max = false },
            { id = "party", max = 4 },
            { id = "partypet", max = 4 },
            { id = "raid", max = 40 },
            { id = "raidpet", max = 40 },
            { id = "nameplate", max = 40 },
            { id = "target", max = false },
        }

        for _, unit in pairs(unitIds) do
            if unit.max then
                for i = 1, unit.max do
                    local unitId = unit.id .. i
                    if UnitGUID(unitId) == guid then
                        return unitId
                    end
                end
            else
                if UnitGUID(unit.id) == guid then
                    return unit.id
                end
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

    elseif (playerClass == "MAGE") then
        AM_Core.RegisterEvent("PLAYER_DAMAGE_DONE_MODS");

    elseif (playerClass == "PALADIN") then
        AM_Core.RegisterEvent("PLAYER_DAMAGE_DONE_MODS");

    elseif (playerClass == "PRIEST") then
        AM_Core.RegisterEvent("PLAYER_DAMAGE_DONE_MODS");

    elseif (playerClass == "WARLOCK") then
        AM_Core.RegisterEvent("PLAYER_DAMAGE_DONE_MODS");
    end

    AM_Events.STATS_CHANGED();

    if (OnEnableClass[playerClass]) then
        OnEnableClass[playerClass]();
    end

    if (AM_Events.PLAYER_LEVEL_UP) then
        AM_Core.RegisterEvent("PLAYER_LEVEL_UP");
    end

    if (AM_Events.PLAYER_TALENT_UPDATE) then
        AM_Core.RegisterEvent("PLAYER_TALENT_UPDATE");
    end

    if (AM_Events.PLAYER_EQUIPMENT_CHANGED) then
        AM_Core.RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
    end

    AM_Core.RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");

    AM_Public.Enabled = true;
end

-- These function has to clear any memory this version of the library may
-- have accumulated. It will be called in case this library version gets
-- replaced by a new one
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

    collectgarbage("collect");
end

function AM_Core.RegisterEvent(name)
    AM_Core.Frame:RegisterEvent(name);
end

function AM_Core.UnregisterEvent(name)
    AM_Core.Frame:UnregisterEvent(name);
end

function AM_Core.ApplySingularEffect(sourceGUID, sourceName, destGUID, destName, spellId)
    local destEffects = activeEffectsBySpell[destGUID];
    local effectInfo = Effects[spellId];
    local effectEntry;
    
    local timerId = destGUID .. "_" .. spellId 

    local value, quality, extra = effectInfo[3](sourceGUID, sourceName, destGUID, destName, spellId, destEffects);

    if (value == nil) then
        return ;
    end

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

    if (not guidEffects) then
        return ;
    end

    local absorbedRemaining = absorbedTotal;

    local absorbed = 0;
    local keepEffect, visibleAbsorb = false, false;
    local i = 1;
    local effectEntry;

    -- This loop lasts as long as there is still an absorb value that
    -- no effect could account for, but it will break once the list of
    -- available effects got used completely.
    while (absorbedRemaining > 0) do
        effectEntry = activeEffectsByPriority[guid][i];

        -- Sometimes there can be holes in this list since we don't re-sort
        -- after removing an effect
        if (effectEntry == nil) then
            break ;
        end

        -- Only absorb effects with exactly zero are ignored, negative ones
        -- are treated as infinite (that is, no addon should display their value)
        if effectEntry[3] and (effectEntry[3] ~= 0) then
            -- Hit the abosrb effect
            absorbed, keepEffect = Effects[effectEntry[1]][4](effectEntry, absorbedRemaining, overkill, spellSchool);

            if absorbed and (absorbed > 0) then
                -- Reduce the value of this effect and the remaining absorb value
                -- to be accounted for
                effectEntry[3] = effectEntry[3] - absorbed;
                absorbedRemaining = absorbedRemaining - absorbed;

                -- If it should be visible (priority < 2), correct the total value
                if effectEntry[2] and (effectEntry[2] < 2) then
                    guidEffects[-1] = guidEffects[-1] - absorbed;

                    -- Shows us that at least one visible effect got hit
                    visibleAbsorb = true;
                end

                EventRegistry:TriggerEvent("Precognito", guid)
            end

            -- If the hit-function told us to remove the effect, do so
            -- Note that only RemoveActiveEffect is allowed to remove it from the
            -- list, we just set the value to zero, so it gets ignored on any hit.
            -- This is do not come into any desync issues with the events, and to
            -- keep the proper clean-up code in one place
            if (not keepEffect) then
                effectEntry[3] = 0;
            end
        end

        i = i + 1;
    end

    -- There are two possibilities when things are going wrong
    --
    --	a)	we guessed an absorb value too high, in that case it will
    --		automatically be corrected when it breaks
    --
    --	b)	we guessed an absorb value too low, so we end up with an
    --		amount to absorb when all effects seem to be gone
    --		(absorbedRemaining > 0)
    --		Note that we cannot rely on SPELL_AURA_REMOVED to check this,
    --		since it may happen completely out of order, but it will
    --		clear this unit soon or did so already.
    --		we reduce the quality to zero, since any absorb now happening
    --		cannot be accounted for.
    --		Since we may have rounding --errors from scanning the spellbook
    --		and calculating the value thereafter (does Blizzard round on
    --		EVERY step?!?), we accept a small threshold
    if absorbedRemaining and (absorbedRemaining > LOW_VALUE_TOLERANCE) then
        guidEffects[-1] = guidEffects[-1] - absorbedRemaining;
        guidEffects[-2] = 0.0;
        visibleAbsorb = true;
    end

    if (visibleAbsorb) then
        EventRegistry:TriggerEvent("Precognito", guid)
    end
end

-- Note that this method should NOT be called on non-existing effects or units
-- There are no exist checks within it.
function AM_Core.RemoveActiveEffect(guid, spellId)
    local guidEffects = activeEffectsBySpell[guid];
    local effectEntry = guidEffects[spellId];

    -- This is a shared effect with a triggerGUID
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

-- This is uses a _very_ simple queue implementation with tinsert and tremove.
-- It will not scale very well for large values, but we're talking of a maximum
-- of ~3 entries per GUID at any given time. A proper implementation
-- with linked list would probably not be any faster.
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

        -- For some weird reason, it will fail (true even on empty array)
        -- if checked for queue[1] ?!?
        if (queue and queue[2]) then
            local chargeAmount;
            local chargeExpire;

            -- This loop will not be able to run infinitely
            while (true) do
                -- In this order we might save one table reshuffle
                chargeAmount = tremove(queue, 2);

                if (not chargeAmount) then
                    return 0;
                end

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

        -- There is already a list of callbacks, so we just add this one
        if (funcList) then
            for k, v in pairs(funcList) do
                if (v == func) then
                    return ;
                end
            end

            tinsert(funcList, func);

            -- We used a direct call so far, create a list and set up a handler
        else
            if (oldTrigger == func) then
                return ;
            end

            funcList = { oldTrigger, func };
            eventTriggers[listIndex] = funcList;

            local handler = function(...)
                for k, v in pairs(funcList) do
                    v(...);
                end
            end

            eventTriggers[target] = handler;
        end
    end
end

function AM_Core.RemoveCombatTrigger(target, event, func)
    local eventTriggers = AM_Core.CombatTriggers[event];

    local listIndex = target .. "_list";
    local funcList = eventTriggers[listIndex];

    -- We have a list of callbacks, reduce if possible
    if (funcList) then
        if (#funcList == 2) then
            eventTriggers[target] = (funcList[1] == func) and funcList[2] or funcList[1];
            eventTriggers[listIndex] = nil;
        else
            -- ATTENTION: We have to keep the table in place
            -- because the handler references this table

            local old_funcList = DeepTableCopy(funcList);
            wipe(funcList);

            for k, v in pairs(old_funcList) do
                if (v ~= func) then
                    tinsert(funcList, v);
                end
            end
        end

        -- It was a direct call anyway
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
-- Due to be removed in 4.

function AM_Events.STATS_CHANGED()
    local baseAP, plusAP, minusAP = UnitAttackPower("player");

    UnitStats[playerGUID][2] = baseAP + plusAP + minusAP;
    UnitStats[playerGUID][3] = GetSpellBonusHealing();
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

        -- We cannot track whether it's still on, remove it
        if (not name) then
            if activeEffectsBySpell[guid][spellId][6] then
                AM_Core:CancelTimer(activeEffectsBySpell[guid][spellId][6])
            end
            RemoveActiveEffect(guid, spellId);
        end

        local stillActive = false;

        for i = 1, 40 do
            local _, _, _, _, _, _, _, _, _, buffId = UnitBuff(name, i);

            if (not buffId) then
                break ;
            end

            if (buffId == spellId) then
                stillActive = true;

                break ;
            end
        end

        if (not stillActive) then
            if activeEffectsBySpell[guid][spellId][6] then
                AM_Core:CancelTimer(activeEffectsBySpell[guid][spellId][6])
            end

            RemoveActiveEffect(guid, spellId);
        end
    else
        -- Make sure to remove the timer
        if activeEffectsBySpell[guid][spellId][6] then
            AM_Core:CancelTimer(activeEffectsBySpell[guid][spellId][6])
        end
    end
end

-- Map client events to our callbacks
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
    if not activeEffectsBySpell or not activeEffectsBySpell[guid] then
        return
    end

    for spellId, effect in pairs(activeEffectsBySpell[guid]) do
        if spellId and spellId > 0 then
            local name = GetSpellInfo(spellId)
            if name then
                print("Spell absorb active:", name, "val:", effect[3])
            end
        else
            break
        end
    end
end

function AM_Public.Unit_Stats(guid, missingQuality)
    local guidStats = UnitStats[guid];

    if (guidStats) then
        return guidStats[2], guidStats[3], guidStats[4];
    else
        return 0, 0, missingQuality;
    end
end

function AM_Public.Unit_Scaling(guid, defaultScaling, defaultQuality)
    local guidScaling = Scaling[guid];

    if (guidScaling) then
        return guidScaling, 1.0;
    else
        return defaultScaling, defaultQuality;
    end
end

-- Optimized method to save one function call on creation, since a lot of spells
-- actually require stats and scaling
function AM_Public.Unit_StatsAndScaling(guid, missingQuality, defaultScaling, defaultQuality)
    local guidStats = UnitStats[guid];
    local guidScaling = Scaling[guid];

    if (guidStats) then
        if (guidScaling) then
            return guidStats[2], guidStats[3], guidStats[4], guidScaling, 1.0;
        else
            return guidStats[2], guidStats[3], guidStats[4], defaultScaling, defaultQuality;
        end
    else
        if (guidScaling) then
            return 0, 0, missingQuality, guidScaling, 1.0;
        else
            return 0, 0, missingQuality, defaultScaling, defaultQuality;
        end
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

--- Generic Hit function suitable for most absorb effects
-- Note that this function is only responsible for determining the amount this
-- particular absorb effect will take, NOT to handle its consequences like updating
-- the data structures
-- @param	effectEntry			activeEffectsBySpell[guid][spellId]
-- @param	absorbedRemaining	absorb value left to be accounted for on this unit
-- @param	overkill			amount of damage done on top of the absorb
-- @param	spellSchool			spell school for this hit
-- @return	absorb value this effect can account fors
-- @return	whether this absorb was broken by this hit
local function generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (absorbedRemaining > effectEntry[3]) then
        -- dirty but efficient
        absorbedRemaining = effectEntry[3];
        overkill = 1;
    end

    return absorbedRemaining, (overkill == 0);
end


-------------------
-- Effects: Mage --
-------------------

-- Table for base values of
-- Fire Ward, Frost Ward, Ice Barrier, Mana Shield
-- TODO: base leveling increase
local mage_Absorb_Spells = {
    -- Fire Ward
    [543] = 165,
    [8457] = 290,
    [8458] = 470,
    [10223] = 675,
    [10225] = 920,
    [412214] = 330,
    [412218] = 580,
    [412230] = 940,
    [412231] = 1350,
    [412232] = 1840,

    -- Frost Ward
    [6143] = 165,
    [8461] = 290,
    [8462] = 470,
    [10177] = 675,
    [28609] = 920,
    [412202] = 330,
    [412205] = 580,
    [412207] = 940,
    [412209] = 1350,
    [412210] = 1840,

    -- Ice Barrier
    [11426] = 455,
    [13031] = 569,
    [13032] = 700,
    [13033] = 826,

    [1463] = 120,
    [8494] = 210,
    [8495] = 300,
    [10191] = 390,
    [10192] = 480,
    [10193] = 570,
    [412116] = 240,
    [412118] = 420,
    [412120] = 600,
    [412121] = 780,
    [412122] = 960,
    [412123] = 1140,
};

local mage_defaultScaling = { 1.0 };

-- No Downranking support here
local function mage_IceBarrier_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local _, sp, quality1, sourceScaling, quality2 = Unit_StatsAndScaling(sourceGUID, 0.3, mage_defaultScaling, 0.4);

    local scaleFactor = sourceScaling[1] or 1.0

    return floor((mage_Absorb_Spells[spellId] + (sp * 0.1)) * scaleFactor), math.min(quality1, quality2);
end

local function mage_FireWard_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_FIRE) then
        return 0, true;
    end

    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

local function mage_FrostWard_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_FROST) then
        return 0, true;
    end

    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

----------------------
-- Effects: Paladin --
----------------------

local function paladin_SacredShield_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local unit = GetUnitId(sourceGUID)
    if not unit then
        return 242, 1.0
    end

    local level = UnitLevel(unit) or 60
    local shieldAmount = floor((36 * (38.258376 + 0.904195 * level + 0.161311 * level * level) / 100))

    return shieldAmount or 0, 1.0
end

local function DirectValue_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local unitId = GetUnitId(destGUID)
    if not unitId then
        return 0, 0.3
    end

    for i = 1, 32 do
        local aura = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex(unitId, i, "HELPFUL")
        if not aura then
            break
        end

        if aura and (aura.spellId == spellId) and (aura.points and aura.points[1]) and (aura.sourceUnit and UnitGUID(aura.sourceUnit) == sourceGUID) then
            return aura.points[1], 1.0
        end
    end

    return 0, 0.5
end

---------------------
-- Effects: Priest --
---------------------

-- [rank] = {spellId, level, baseValue, incValue}
local priest_PWS_Ranks = {
    [1] = { 17, 6, 44, 4 },
    [2] = { 592, 12, 88, 6 },
    [3] = { 600, 18, 158, 8 },
    [4] = { 3747, 24, 234, 10 },
    [5] = { 6065, 30, 301, 12 },
    [6] = { 6066, 36, 381, 13 },
    [7] = { 10898, 42, 484, 15 },
    [8] = { 10899, 48, 605, 17 },
    [9] = { 10900, 54, 763, 20 },
    [10] = { 10901, 60, 942, 0 },
};

local priest_defaultScaling = {};

do
    for k, v in pairs(priest_PWS_Ranks) do
        priest_defaultScaling[v[1]] = { v[3], 0.1 };
    end
end

local function priest_PowerWordShield_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    local _, sp, quality1, sourceScaling, quality2 = Unit_StatsAndScaling(sourceGUID, 0.1, priest_defaultScaling, 0.1);

    local baseValue = sourceScaling[spellId][1]
    local spScaling = sourceScaling[spellId][2]

    -- Soul Warding rune is equipped
    if C_Engraving and C_Engraving.IsRuneEquipped(48265) then
        baseValue = baseValue * 1.10
        spScaling = 0.20
    end

    local finalAbsorb = floor(baseValue + (sp * spScaling))

    return finalAbsorb, math.min(quality1, quality2)
end

local function priest_ApplyScaling(guid, level, baseFactor, spFactor)
    local guidScaling;

    if (not Scaling[guid]) then
        guidScaling = {};
        Scaling[guid] = guidScaling;
    else
        guidScaling = Scaling[guid];
    end

    local rankValue, rankSP;

    for k, v in pairs(priest_PWS_Ranks) do
        if (v[2] <= level) then
            if (level == 60) then
                rankValue = v[3] + v[4];
            else
                -- TODO
                rankValue = v[3];
            end

            if (v[2] < (level - 5)) then
                if (level == 60) then
                    rankSP = math.max(spFactor * ((v[2] * 0.0430000019073) - 2.381389768), 0);
                else
                    rankSP = 0;
                end
            else
                rankSP = spFactor;
            end

            guidScaling[v[1]] = { rankValue * baseFactor, rankSP };
        end
    end
end

local function priest_UpdatePlayerScaling()
    local healing = 1 + privateScaling["SpiritualHealing"] * 0.02
    local pws = 1 + privateScaling["ImpPWS"] * 0.05

    privateScaling.base = healing * pws
    privateScaling.sp = 0.1 * privateScaling.base

    priest_ApplyScaling(playerGUID, UnitLevel("player"), privateScaling.base, privateScaling.sp)
end

local function priest_ScanTalents()
    -- Improved Power Word: Shield
    local _, _, _, _, t = GetTalentInfo(1, 5);
    privateScaling["ImpPWS"] = t;

    -- Spiritual Healing
    local _, _, _, _, t = GetTalentInfo(2, 15);
    privateScaling["SpiritualHealing"] = t;
end

local function priest_OnLevelUp()
    priest_UpdatePlayerScaling();
end

local function priest_OnTalentUpdate()
    priest_ScanTalents();
    priest_UpdatePlayerScaling();
end

local function priest_OnEquipmentChangedDelayed()
    priest_UpdatePlayerScaling();
end

local function priest_OnEquipmentChanged()
    AM_Core:ScheduleUniqueTimer("priest_equip", priest_OnEquipmentChangedDelayed, 0.7);
end

function OnEnableClass.PRIEST()
    AM_Events.PLAYER_LEVEL_UP = priest_OnLevelUp;
    AM_Events.PLAYER_TALENT_UPDATE = priest_OnTalentUpdate;
    AM_Events.PLAYER_EQUIPMENT_CHANGED = priest_OnEquipmentChanged;

    priest_ScanTalents();

    priest_UpdatePlayerScaling();
end

----------------------
-- Effects: Warlock --
----------------------

-- TODO: base leveling increase
local warlock_Sacrifice_Spells = {
    [7812] = 305,
    [19438] = 510,
    [19440] = 770,
    [19441] = 1095,
    [19442] = 1470,
    [19443] = 1905,
}

local warlock_ShadowWard_Spells = {
    [6229] = 290,
    [11739] = 470,
    [11740] = 675,
    [28610] = 920,
};

-- Public Scaling: { [DemonicBrutality] }
local warlock_defaultScaling = { 1.0 };

-- No downranking support here
local function warlock_Sacrifice_Create(sourceGUID, sourceName, destGUID, destName, spellId, destEffects)
    -- Note that the source is the voidwalker, so dest is the warlock!
    local sourceScaling, quality = Unit_Scaling(destGUID, warlock_defaultScaling, 0.4);

    return floor(warlock_Sacrifice_Spells[spellId] * sourceScaling[1]), quality;
end

local function warlock_ShadowWard_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_SHADOW) then
        return 0, true;
    end

    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

local function warlock_spellStone_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool == SCHOOL_MASK_PHYSICAL) or (spellSchool == SCHOOL_MASK_NONE) then
        return 0, true;
    end

    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

local function warlock_OnTalentUpdate()
    -- Demonic Brutality
    local _, _, _, _, t = GetTalentInfo(2, 5);

    playerScaling[1] = 1 + (t * 0.1);

end

function OnEnableClass.WARLOCK()
    AM_Events.PLAYER_TALENT_UPDATE = warlock_OnTalentUpdate;

    warlock_OnTalentUpdate();
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

    if (destEffects and destEffects[spellId]) then
        existing = destEffects[spellId][3];
    end

    local charge = PopCharge(destGUID, spellId);

    if (charge == 0) then
        return existing, 0.0;
    end

    return (existing + charge), 1.0
end

local function potion_Nature_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_NATURE) then
        return 0, true;
    end

    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

local function potion_Holy_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_HOLY) then
        return 0, true;
    end

    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

local function potion_Arcane_Hit(effectEntry, absorbedRemaining, overkill, spellSchool)
    if (spellSchool ~= SCHOOL_MASK_ARCANE) then
        return 0, true;
    end

    return generic_Hit(effectEntry, absorbedRemaining, overkill, spellSchool);
end

-----------------
-- Data Tables --
-----------------

local mage_FireWard_Entry = { 2.0, 30, generic_SpellScalingByTable_Create, mage_FireWard_Hit, mage_Absorb_Spells };
local mage_FrostWard_Entry = { 2.0, 30, generic_SpellScalingByTable_Create, mage_FrostWard_Hit, mage_Absorb_Spells };
local mage_IceBarrier_Entry = { 1.0, 60, mage_IceBarrier_Create, generic_Hit };
local mage_ManaShield_Entry = { 1.0, 60, generic_SpellScalingByTable_Create, generic_Hit, mage_Absorb_Spells };
local priest_PWS_Entry = { 1.0, 30, priest_PowerWordShield_Create, generic_Hit };
local warlock_Sacrifice_Entry = { 1.0, 30, generic_ConstantByTable_Create, generic_Hit, warlock_Sacrifice_Spells };
local warlock_ShadowWard_Entry = { 2.0, 30, generic_SpellScalingByTable_Create, warlock_ShadowWard_Hit, warlock_ShadowWard_Spells };


-- INCOMPLETE
AM_Core.Effects = {
    -- Unknown Effect
    [0] = { 1.0, 0, function()
        return 0, 0.0;
    end, nil };

    -- MAGE
    -- Fire Ward
    [543] = mage_FireWard_Entry,
    [8457] = mage_FireWard_Entry,
    [8458] = mage_FireWard_Entry,
    [10223] = mage_FireWard_Entry,
    [10225] = mage_FireWard_Entry,
    [412214] = mage_FireWard_Entry,
    [412218] = mage_FireWard_Entry,
    [412230] = mage_FireWard_Entry,
    [412231] = mage_FireWard_Entry,
    [412232] = mage_FireWard_Entry,

    -- Frost Ward
    [6143] = mage_FrostWard_Entry,
    [8461] = mage_FrostWard_Entry,
    [8462] = mage_FrostWard_Entry,
    [10177] = mage_FrostWard_Entry,
    [28609] = mage_FrostWard_Entry,
    [412202] = mage_FrostWard_Entry,
    [412205] = mage_FrostWard_Entry,
    [412207] = mage_FrostWard_Entry,
    [412209] = mage_FrostWard_Entry,
    [412210] = mage_FrostWard_Entry,

    -- Ice Barrier
    [11426] = mage_IceBarrier_Entry,
    [13031] = mage_IceBarrier_Entry,
    [13032] = mage_IceBarrier_Entry,
    [13033] = mage_IceBarrier_Entry,
    [1213278] = mage_IceBarrier_Entry,

    -- Mana Shield
    [1463] = mage_ManaShield_Entry,
    [8494] = mage_ManaShield_Entry,
    [8495] = mage_ManaShield_Entry,
    [10191] = mage_ManaShield_Entry,
    [10192] = mage_ManaShield_Entry,
    [10193] = mage_ManaShield_Entry,
    [412116] = mage_ManaShield_Entry,
    [412118] = mage_ManaShield_Entry,
    [412120] = mage_ManaShield_Entry,
    [412121] = mage_ManaShield_Entry,
    [412122] = mage_ManaShield_Entry,
    [412123] = mage_ManaShield_Entry,

    -- Temporal anomaly
    [428895] = { 1.0, 15, DirectValue_Create, generic_Hit },

    -- PALADIN
    -- Sacred Shield
    [412018] = { 1.0, 6, paladin_SacredShield_Create, generic_Hit },
    -- Divine Heal
    [458857] = { 1.0, 15, DirectValue_Create, generic_Hit },

    -- PRIEST
    -- Power Word: Shield
    [17] = priest_PWS_Entry,
    [592] = priest_PWS_Entry,
    [600] = priest_PWS_Entry,
    [3747] = priest_PWS_Entry,
    [6065] = priest_PWS_Entry,
    [6066] = priest_PWS_Entry,
    [10898] = priest_PWS_Entry,
    [10899] = priest_PWS_Entry,
    [10900] = priest_PWS_Entry,
    [10901] = priest_PWS_Entry,

    -- Divine Aegis
    [431624] = { 1.0, 12, DirectValue_Create, generic_Hit },

    -- WARLOCK
    -- Sacrifice
    [7812] = warlock_Sacrifice_Entry,
    [19438] = warlock_Sacrifice_Entry,
    [19440] = warlock_Sacrifice_Entry,
    [19441] = warlock_Sacrifice_Entry,
    [19442] = warlock_Sacrifice_Entry,
    [19443] = warlock_Sacrifice_Entry,
    -- Shadow Ward
    [6229] = warlock_ShadowWard_Entry,
    [11739] = warlock_ShadowWard_Entry,
    [11740] = warlock_ShadowWard_Entry,
    [28610] = warlock_ShadowWard_Entry,

    -- ITEMS
    -- Scarab Brooch
    [26470] = { 1.0, 8, items_ScarabBrooch_Create, generic_Hit },
    -- The Burrower's Shell
    [29506] = { 1.0, 20, function()
        return 900, 1.0;
    end, generic_Hit },
    -- Arena Grand Master (mean value of 1000)
    [23506] = { 1.0, 20, function()
        return 1000, 0.5;
    end, generic_Hit },
    -- Divine Protection (Priest Dungeon Set 0/0.5 4pc bonus)
    [27779] = { 1.0, 30, function()
        return 350, 1.0;
    end, generic_Hit },
    -- Armor of Faith (Priest Raid Set 3 4pc bonus)
    [28810] = { 1.0, 30, function()
        return 500, 1.0;
    end, generic_Hit },
    -- Bone Shield
    [27688] = { 1.0, 300, function()
        return 2500, 1.0;
    end, generic_Hit },
    -- Spellstone
    [128] = { 2.0, 60, function()
        return 400, 1.0;
    end, warlock_spellStone_Hit },
    -- Greater Spellstone
    [17729] = { 2.0, 60, function()
        return 650, 1.0;
    end, warlock_spellStone_Hit },
    -- Major Spellstone
    [17730] = { 2.0, 60, function()
        return 900, 1.0;
    end, warlock_spellStone_Hit },

    --[17549] = { 2.0, 3600, function()
    --    return 1950, 1.0;
    --end, potion_Arcane_Hit }, -- Arcane Protection
    --
    --[7245] = { 2.0, 3600, function()
    --    return 300, 1.0;
    --end, potion_Holy_Hit }, -- Holy Protection (Rank 1)
    --
    --[16892] = { 2.0, 3600, function()
    --    return 300, 1.0;
    --end, potion_Holy_Hit }, -- Holy Protection (Rank 1)
    --
    --[7246] = { 2.0, 3600, function()
    --    return 525, 1.0;
    --end, potion_Holy_Hit }, -- Holy Protection (Rank 2)
    --
    --[7247] = { 2.0, 3600, function()
    --    return 675, 1.0;
    --end, potion_Holy_Hit }, -- Holy Protection (Rank 3)
    --
    --[7248] = { 2.0, 3600, function()
    --    return 975, 1.0;
    --end, potion_Holy_Hit }, -- Holy Protection (Rank 4)
    --
    --[7249] = { 2.0, 3600, function()
    --    return 1350, 1.0;
    --end, potion_Holy_Hit }, -- Holy Protection (Rank 5)
    --
    --[17545] = { 2.0, 3600, function()
    --    return 1950, 1.0;
    --end, potion_Holy_Hit }, -- Holy Protection (Rank 6)
    --
    --[17548] = { 2.0, 3600, function()
    --    return 1950, 1.0;
    --end, warlock_ShadowWard_Hit }, -- Shadow Protection
    --
    --[7235] = { 2.0, 3600, function()
    --    return 300, 1.0;
    --end, warlock_ShadowWard_Hit }, -- Shadow Protection (Rank 1)
    --
    --[7241] = { 2.0, 3600, function()
    --    return 525, 1.0;
    --end, warlock_ShadowWard_Hit }, -- Shadow Protection (Rank 2)
    --
    --[7242] = { 2.0, 3600, function()
    --    return 675, 1.0;
    --end, warlock_ShadowWard_Hit }, -- Shadow Protection (Rank 3)
    --
    --[16891] = { 2.0, 3600, function()
    --    return 675, 1.0;
    --end, warlock_ShadowWard_Hit }, -- Shadow Protection (Rank 3)
    --
    --[7243] = { 2.0, 3600, function()
    --    return 975, 1.0;
    --end, warlock_ShadowWard_Hit }, -- Shadow Protection (Rank 4)
    --
    --[7244] = { 2.0, 3600, function()
    --    return 1350, 1.0;
    --end, warlock_ShadowWard_Hit }, -- Shadow Protection (Rank 5)
    --
    --[17544] = { 2.0, 3600, function()
    --    return 1950, 1.0;
    --end, potion_Nature_Hit }, -- Frost Protection
    --
    --[7240] = { 2.0, 3600, function()
    --    return 300, 1.0;
    --end, potion_Nature_Hit }, -- Frost Protection (Rank 1)
    --
    --[7236] = { 2.0, 3600, function()
    --    return 525, 1.0;
    --end, potion_Nature_Hit }, -- Frost Protection (Rank 2)
    --
    --[7238] = { 2.0, 3600, function()
    --    return 675, 1.0;
    --end, potion_Nature_Hit }, -- Frost Protection (Rank 3)
    --
    --[7237] = { 2.0, 3600, function()
    --    return 975, 1.0;
    --end, potion_Nature_Hit }, -- Frost Protection (Rank 4)
    --
    --[7239] = { 2.0, 3600, function()
    --    return 1350, 1.0;
    --end, potion_Nature_Hit }, -- Frost Protection (Rank 5)
    --
    --[16895] = { 2.0, 3600, function()
    --    return 1350, 1.0;
    --end, potion_Nature_Hit }, -- Frost Protection (Rank 5)
    --
    --[17546] = { 2.0, 3600, function()
    --    return 1950, 1.0;
    --end, potion_Nature_Hit }, -- Nature Protection
    --
    --[7250] = { 2.0, 3600, function()
    --    return 300, 1.0;
    --end, potion_Nature_Hit }, -- Nature Protection (Rank 1)
    --
    --[7251] = { 2.0, 3600, function()
    --    return 525, 1.0;
    --end, potion_Nature_Hit }, -- Nature Protection (Rank 2)
    --
    --[7252] = { 2.0, 3600, function()
    --    return 675, 1.0;
    --end, potion_Nature_Hit }, -- Nature Protection (Rank 3)
    --
    --[7253] = { 2.0, 3600, function()
    --    return 975, 1.0;
    --end, potion_Nature_Hit }, -- Nature Protection (Rank 4)
    --
    --[7254] = { 2.0, 3600, function()
    --    return 1350, 1.0;
    --end, potion_Nature_Hit }, -- Nature Protection (Rank 5)
    --
    --[16893] = { 2.0, 3600, function()
    --    return 1350, 1.0;
    --end, potion_Nature_Hit }, -- Nature Protection (Rank 5)
    --
    --[29432] = { 2.0, 3600, function()
    --    return 1500, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection
    --
    --[17543] = { 2.0, 3600, function()
    --    return 1950, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection
    --
    --[18942] = { 2.0, 3600, function()
    --    return 1950, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection
    --
    --[7230] = { 2.0, 3600, function()
    --    return 300, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection (Rank 1)
    --
    --[12561] = { 2.0, 3600, function()
    --    return 300, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection (Rank 1)
    --
    --[7231] = { 2.0, 3600, function()
    --    return 525, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection (Rank 2)
    --
    --[7232] = { 2.0, 3600, function()
    --    return 675, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection (Rank 3)
    --
    --[7233] = { 2.0, 3600, function()
    --    return 975, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection (Rank 4)
    --
    --[16894] = { 2.0, 3600, function()
    --    return 975, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection (Rank 4)
    --
    --[7234] = { 2.0, 3600, function()
    --    return 1350, 1.0;
    --end, mage_FireWard_Hit }, -- Fire Protection (Rank 5)
};

AM_Core.CombatTriggers = {
    OnAuraApplied = {
        [26470] = items_ScarabBrooch_OnAuraApplied,
    },

    OnAuraRemoved = {
        [26470] = items_ScarabBrooch_OnAuraRemoved,
    },

    OnHeal = {
    },

    OnHealCrit = {
    }
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