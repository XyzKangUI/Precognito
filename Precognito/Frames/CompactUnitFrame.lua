local Precognito = LibStub("AceAddon-3.0"):GetAddon("Precognito")
local LibAbsorb = LibStub:GetLibrary("AbsorbsMonitor-1.0")

local UnitExists, UnitGUID = UnitExists, UnitGUID
local hooksecurefunc = hooksecurefunc
local UnitGetIncomingHeals = UnitGetIncomingHeals
local min, max, strfind = math.min, math.max, string.find
local storedFrames = {}

--WARNING: This function is very similar to the function UnitFrameHealPredictionBars_Update in UnitFrame.lua.
--If you are making changes here, it is possible you may want to make changes there as well.
local MAX_INCOMING_HEAL_OVERFLOW = 1.05
local function CompactUnitFrame_UpdateHealPrediction(frame)
    if not frame or not frame:IsVisible() then
        return
    end

    local _, maxHealth = frame.healthBar:GetMinMaxValues()
    local health = frame.healthBar:GetValue()
    local unit = frame.unit

    if (maxHealth <= 0) then
        return
    end

    local myIncomingHeal = UnitGetIncomingHeals(unit, "player") or 0
    local allIncomingHeal = UnitGetIncomingHeals(unit) or 0
    local totalAbsorb = UnitGetTotalAbsorbs(unit) or 0
    local myCurrentHealAbsorb = 0

    --We don't fill outside the health bar with healAbsorbs.  Instead, an overHealAbsorbGlow is shown.
    myCurrentHealAbsorb = 0
    --myCurrentHealAbsorb = fake.healAbsorb
    if (health < myCurrentHealAbsorb) then
        frame.overHealAbsorbGlowBar:Show()
        myCurrentHealAbsorb = health
    else
        frame.overHealAbsorbGlowBar:Hide()
    end

    --See how far we're going over the health bar and make sure we don't go too far out of the frame.
    if (health - myCurrentHealAbsorb + allIncomingHeal > maxHealth * MAX_INCOMING_HEAL_OVERFLOW) then
        allIncomingHeal = maxHealth * MAX_INCOMING_HEAL_OVERFLOW - health + myCurrentHealAbsorb
    end

    local otherIncomingHeal = 0

    --Split up incoming heals.
    if (allIncomingHeal >= myIncomingHeal) then
        otherIncomingHeal = allIncomingHeal - myIncomingHeal
    else
        myIncomingHeal = allIncomingHeal
    end

    local overAbsorb = false
    --We don't fill outside the the health bar with absorbs.  Instead, an overAbsorbGlow is shown.
    if ((health - myCurrentHealAbsorb + allIncomingHeal + totalAbsorb >= maxHealth and Precognito.db.profile.CUFPredict) or health + totalAbsorb >= maxHealth) then
        if (totalAbsorb > 0) then
            overAbsorb = true
        end

        if (allIncomingHeal > myCurrentHealAbsorb) and Precognito.db.profile.CUFPredict then
            totalAbsorb = max(0, maxHealth - (health - myCurrentHealAbsorb + allIncomingHeal))
        else
            totalAbsorb = max(0, maxHealth - health)
        end
    end
    if (overAbsorb) and Precognito.db.profile.CUFAbsorb then
        frame.overAbsorbGlowBar:Show()
    else
        frame.overAbsorbGlowBar:Hide()
    end

    local healthTexture = frame.healthBar:GetStatusBarTexture()

    local myCurrentHealAbsorbPercent = myCurrentHealAbsorb / maxHealth;

    local healAbsorbTexture = nil

    --If allIncomingHeal is greater than myCurrentHealAbsorb, then the current
    --heal absorb will be completely overlayed by the incoming heals so we don't show it.
    if (myCurrentHealAbsorb > allIncomingHeal) then
        local shownHealAbsorb = myCurrentHealAbsorb - allIncomingHeal
        local shownHealAbsorbPercent = shownHealAbsorb / maxHealth
        healAbsorbTexture = CompactUnitFrameUtil_UpdateFillBar(frame:GetParent(), healthTexture, frame.myHealAbsorbBar, shownHealAbsorb, -shownHealAbsorbPercent)

        --If there are incoming heals the left shadow would be overlayed by the incoming heals
        --so it isn't shown.
        if (allIncomingHeal > 0) then
            frame.myHealAbsorbBarLeftShadow:Hide()
        else
            frame.myHealAbsorbBarLeftShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPLEFT", 0, 0)
            frame.myHealAbsorbBarLeftShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMLEFT", 0, 0)
            frame.myHealAbsorbBarLeftShadow:Show()
        end

        -- The right shadow is only shown if there are absorbs on the health bar.
        if (totalAbsorb > 0) then
            frame.myHealAbsorbBarRightShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPRIGHT", -8, 0)
            frame.myHealAbsorbBarRightShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMRIGHT", -8, 0)
            frame.myHealAbsorbBarRightShadow:Show()
        else
            frame.myHealAbsorbBarRightShadow:Hide()
        end
    else
        frame.myHealAbsorbBar:Hide()
        frame.myHealAbsorbBarRightShadow:Hide()
        frame.myHealAbsorbBarLeftShadow:Hide()
    end

    --Show myIncomingHeal on the health bar.
    local incomingHealsTexture
    if Precognito.db.profile.CUFPredict then
        incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame:GetParent(), healthTexture, frame.myHealPredictionBar, myIncomingHeal, -myCurrentHealAbsorbPercent)
        --Append otherIncomingHeal on the health bar.
        if (myIncomingHeal > 0) then
            incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame:GetParent(), incomingHealsTexture, frame.otherHealPredictionBar, otherIncomingHeal)
        else
            incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame:GetParent(), healthTexture, frame.otherHealPredictionBar, otherIncomingHeal, -myCurrentHealAbsorbPercent)
        end
    else
        incomingHealsTexture = healthTexture
    end

    --Append absorbs to the correct section of the health bar.
    local appendTexture = nil
    if (healAbsorbTexture) then
        --If there is a healAbsorb part shown, append the absorb to the end of that.
        appendTexture = healAbsorbTexture
    else
        --Otherwise, append the absorb to the end of the the incomingHeals part
        appendTexture = incomingHealsTexture
    end
    if Precognito.db.profile.CUFAbsorb then
        CompactUnitFrameUtil_UpdateFillBar(frame:GetParent(), appendTexture, frame.totalAbsorbBar, totalAbsorb)
    end

    if Precognito.db.profile.CUFOvershield then
        local absorbBar = frame.totalAbsorbBar;
        if not absorbBar or absorbBar:IsForbidden() then
            return
        end

        local absorbOverlay = frame.totalAbsorbOverlayBar;
        if not absorbOverlay or absorbOverlay:IsForbidden() then
            return
        end

        local healthBar = frame.healthBar;
        if not healthBar or healthBar:IsForbidden() then
            return
        end

        local _, maxHealth = healthBar:GetMinMaxValues();
        if maxHealth <= 0 then
            return
        end

        local totalAbsorb = UnitGetTotalAbsorbs(unit or 0)
        if totalAbsorb > maxHealth then
            totalAbsorb = maxHealth;
        end

        if totalAbsorb > 0 then
            if absorbBar:IsShown() then
                absorbOverlay:SetPoint("TOPRIGHT", absorbBar, "TOPRIGHT", 0, 0);
                absorbOverlay:SetPoint("BOTTOMRIGHT", absorbBar, "BOTTOMRIGHT", 0, 0);
            else
                absorbOverlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0);
                absorbOverlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0);
            end

            local totalWidth, totalHeight = healthBar:GetSize();
            local barSize = totalAbsorb / maxHealth * totalWidth;

            absorbOverlay:SetWidth(barSize);
            absorbOverlay:SetTexCoord(0, min(max(barSize / absorbOverlay.tileSize, 0), 1), 0, min(max(totalHeight / absorbOverlay.tileSize, 0), 1));
            absorbOverlay:Show()
        end
    end
end

local function CompactUnitFrame_FireEvent(self, event)
    CompactUnitFrame_OnEvent(self, event, self.unit or self.displayedUnit)
end

local function LibEventCallback(self, event, ...)
    local arg1, _, arg3, _, arg5 = ...
    if (not UnitExists(self.unit)) then
        return
    end

    if (event == "EffectApplied" and arg3 == UnitGUID(self.unit)) then
        CompactUnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    else
        local unit = arg1 == UnitGUID(self.unit) or arg5 == UnitGUID(self.unit)
        if unit then
            if (event == "UnitUpdated") then
                CompactUnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            elseif (event == "EffectRemoved") then
                CompactUnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            elseif (event == "UnitCleared") then
                CompactUnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            elseif (event == "AreaCreated") then
                CompactUnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            elseif (event == "AreaCleared") then
                CompactUnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            elseif (event == "UnitAbsorbed") then
                CompactUnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            end
        end
    end
end

local function CompactUnitFrame_RegisterCallback(self)
    LibAbsorb.RegisterCallback(self, "EffectApplied", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "EffectUpdated", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "EffectRemoved", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "UnitUpdated", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "UnitCleared", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "AreaCreated", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "AreaCleared", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "UnitAbsorbed", LibEventCallback, self)
end

local function CompactUnitFrame_Initialize(frame, myHealPredictionBar, otherHealPredictionBar, totalAbsorbBar, totalAbsorbOverlayBar,
                                           overAbsorbGlowBar, overHealAbsorbGlowBar, myHealAbsorbBar, myHealAbsorbBarLeftShadow, myHealAbsorbBarRightShadow)

    frame.myHealPredictionBar = myHealPredictionBar
    frame.otherHealPredictionBar = otherHealPredictionBar
    frame.totalAbsorbBar = totalAbsorbBar
    frame.totalAbsorbOverlayBar = totalAbsorbOverlayBar
    frame.overAbsorbGlowBar = overAbsorbGlowBar
    frame.overHealAbsorbGlowBar = overHealAbsorbGlowBar
    frame.myHealAbsorbBar = myHealAbsorbBar
    frame.myHealAbsorbBarLeftShadow = myHealAbsorbBarLeftShadow
    frame.myHealAbsorbBarRightShadow = myHealAbsorbBarRightShadow

    if frame.myHealPredictionBar then
        frame.myHealPredictionBar:ClearAllPoints()
        frame.myHealPredictionBar:SetColorTexture(1, 1, 1)
        frame.myHealPredictionBar:SetGradient("VERTICAL", CreateColor(8 / 255, 93 / 255, 72 / 255, 1), CreateColor(11 / 255, 136 / 255, 105 / 255, 1))
    end

    if frame.myHealAbsorbBar then
        frame.myHealAbsorbBar:ClearAllPoints()
        frame.myHealAbsorbBar:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)
    end

    if frame.myHealAbsorbBarLeftShadow then
        frame.myHealAbsorbBarLeftShadow:ClearAllPoints()
        frame.myHealAbsorbBarLeftShadow:Hide()
    end
    if frame.myHealAbsorbBarRightShadow then
        frame.myHealAbsorbBarRightShadow:ClearAllPoints()
        frame.myHealAbsorbBarRightShadow:Hide()
    end

    if frame.otherHealPredictionBar then
        frame.otherHealPredictionBar:ClearAllPoints()
        frame.otherHealPredictionBar:SetColorTexture(1, 1, 1)
        frame.otherHealPredictionBar:SetGradient("VERTICAL", CreateColor(11 / 255, 53 / 255, 43 / 255, 1), CreateColor(21 / 255, 89 / 255, 72 / 255, 1))
    end

    if frame.totalAbsorbBar then
        frame.totalAbsorbBar:ClearAllPoints()
        frame.totalAbsorbBar:SetTexture("Interface\\RaidFrame\\Shield-Fill")
        frame.totalAbsorbBar:Hide()
    end

    if frame.totalAbsorbOverlayBar then
        frame.totalAbsorbBar.overlay = frame.totalAbsorbOverlayBar
        frame.totalAbsorbOverlayBar:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)    --Tile both vertically and horizontally
        frame.totalAbsorbOverlayBar:SetAllPoints(frame.totalAbsorbBar)
        frame.totalAbsorbOverlayBar.tileSize = 32
    end

    if frame.overAbsorbGlowBar then
        frame.overAbsorbGlowBar:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        frame.overAbsorbGlowBar:SetBlendMode("ADD")
        frame.overAbsorbGlowBar:ClearAllPoints()
        frame.overAbsorbGlowBar:SetPoint("BOTTOMLEFT", frame.healthBar, "BOTTOMRIGHT", -7, 0)
        frame.overAbsorbGlowBar:SetPoint("TOPLEFT", frame.healthBar, "TOPRIGHT", -7, 0)
        frame.overAbsorbGlowBar:SetWidth(16)
        frame.overAbsorbGlowBar:Hide()
    end

    if frame.overHealAbsorbGlowBar then
        frame.overHealAbsorbGlowBar:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
        frame.overHealAbsorbGlowBar:SetBlendMode("ADD")
        frame.overHealAbsorbGlowBar:ClearAllPoints()
        frame.overHealAbsorbGlowBar:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMLEFT", 7, 0)
        frame.overHealAbsorbGlowBar:SetPoint("TOPRIGHT", frame.healthBar, "TOPLEFT", 7, 0)
        frame.overHealAbsorbGlowBar:SetWidth(16)
        frame.overHealAbsorbGlowBar:Hide()
    end

    if Precognito.db.profile.CUFOvershield then
        local absorbBar = frame.totalAbsorbBar;
        if not absorbBar or absorbBar:IsForbidden() then
            return
        end

        local absorbOverlay = frame.totalAbsorbOverlayBar;
        if not absorbOverlay or absorbOverlay:IsForbidden() then
            return
        end

        local healthBar = frame.healthBar;
        if not healthBar or healthBar:IsForbidden() then
            return
        end

        absorbOverlay:SetParent(healthBar)
        absorbOverlay:ClearAllPoints()
        absorbOverlay:SetDrawLayer("OVERLAY")

        local absorbGlow = frame.overAbsorbGlowBar;
        if absorbGlow and not absorbGlow:IsForbidden() then
            absorbGlow:ClearAllPoints()
            absorbGlow:SetPoint("TOPLEFT", absorbOverlay, "TOPLEFT", -5, 0);
            absorbGlow:SetPoint("BOTTOMLEFT", absorbOverlay, "BOTTOMLEFT", -5, 0);
            absorbGlow:SetAlpha(0.6);
            absorbGlow:SetDrawLayer("OVERLAY")
        end
    end

    if Precognito.db.profile.CUFAbsorb then
        CompactUnitFrame_RegisterCallback(frame:GetParent())
    end

    CompactUnitFrame_UpdateHealPrediction(frame)
end

local function createPredictFrame(frame, unit)
    if (not storedFrames[frame] and UnitExists(unit)) then
        local name = frame:GetName()
        local predictFrame = CreateFrame("StatusBar", name .. "PredictFrame", frame, "CompactUnitFrameTemplate2")
        predictFrame:SetAllPoints(frame)
        predictFrame:SetFrameLevel(frame:GetFrameLevel())
        local prefix = predictFrame:GetName()
        local healthBar = frame.healthBar ~= nil and frame.healthBar or frame.healthbar
        storedFrames[frame] = predictFrame
        storedFrames[frame].healthBar = healthBar
        storedFrames[frame].unit = unit

        CompactUnitFrame_Initialize(storedFrames[frame], _G[prefix .. "MyHealPredictionBars"], _G[prefix .. "OtherHealPredictionBar"],
                _G[prefix .. "TotalAbsorbBar"], _G[prefix .. "TotalAbsorbOverlay"],
                _G[prefix .. "OverAbsorbGlow"], _G[prefix .. "OverHealAbsorbGlow"],
                _G[prefix .. "MyHealAbsorb"], _G[prefix .. "MyHealAbsorbLeftShadow"],
                _G[prefix .. "MyHealAbsorbRightShadow"])
    end
end

local function CUF_SetUnit(frame)
    if not frame or frame:IsForbidden() or not frame:GetName() or not frame.unit or strfind(frame.unit, "nameplate") then
        return
    end

    local unit = frame.displayedUnit ~= nil and frame.displayedUnit or frame.unit
    if storedFrames[frame] and storedFrames[frame].unit ~= unit then
        storedFrames[frame].unit = unit
    else
        createPredictFrame(frame, unit)
    end
end

local function CUF_UpdateEvent(frame)
    if not frame or frame:IsForbidden() or strfind(frame.displayedUnit, "nameplate") then
        return
    end

    local unit = frame.unit
    local displayedUnit
    if (unit ~= frame.displayedUnit) then
        displayedUnit = frame.displayedUnit
    end
    frame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit, displayedUnit)
end

local function CUF_Event(self, event, ...)
    if not self or self:IsForbidden() or not self:GetName() then
        return
    end

    local frame = storedFrames[self]

    if frame and not strfind(self.displayedUnit, "nameplate") then
        if (event == "UNIT_MAXHEALTH") then
            CompactUnitFrame_UpdateHealPrediction(frame)
        elseif (event == "UNIT_HEALTH") then
            CompactUnitFrame_UpdateHealPrediction(frame)
        elseif (event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED") then
            CompactUnitFrame_UpdateHealPrediction(frame)
        elseif (event == "UNIT_HEAL_PREDICTION") then
            CompactUnitFrame_UpdateHealPrediction(frame)
        elseif (event == "PLAYER_ENTERING_WORLD") then
            CompactUnitFrame_UpdateHealPrediction(frame)
        end
    end
end

function Precognito:CUFInit()
    hooksecurefunc("CompactUnitFrame_SetUnit", CUF_SetUnit)
    hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", CUF_UpdateEvent)
    hooksecurefunc("CompactUnitFrame_OnEvent", CUF_Event)
end