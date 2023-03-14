local Precognito = LibStub("AceAddon-3.0"):GetAddon("Precognito")
local LibAbsorb = LibStub:GetLibrary("AbsorbsMonitor-1.0")
local UnitIsUnit, UnitGUID = UnitIsUnit, UnitGUID
local UnitHealth, UnitPower, UnitPowerType = UnitHealth, UnitPower, UnitPowerType
local UnitGetIncomingHeals = UnitGetIncomingHeals
local max, pairs = math.max, pairs
local hooksecurefunc = hooksecurefunc

local whitelist = {
    ["PlayerFrame"] = "true",
    ["TargetFrame"] = "true",
    ["FocusFrame"] = "true",
    -- ["PartyMemberFrame1"] = "true",
    -- ["PartyMemberFrame2"] = "true",
    -- ["PartyMemberFrame3"] = "true",
    -- ["PartyMemberFrame4"] = "true",
}

function UnitGetTotalAbsorbs(unit)
    if not (unit and LibAbsorb) then
        return
    end

    return LibAbsorb.Unit_Total(UnitGUID(unit))
end

local MAX_INCOMING_HEAL_OVERFLOW = 1.0
local function UnitFrameHealPredictionBars_Update(frame)
    if (not frame.myHealPredictionBars) then
        return
    end
    local _, maxHealth = frame.healthbar:GetMinMaxValues()
    local health = frame.healthbar:GetValue()
    if (maxHealth <= 0) then
        return
    end
    local myIncomingHeal = UnitGetIncomingHeals(frame.unit, "player") or 0
    local allIncomingHeal = UnitGetIncomingHeals(frame.unit) or 0
    local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0
    local myCurrentHealAbsorb = 0

    if (frame.healAbsorbBar) then
        myCurrentHealAbsorb = 0;
        --We don't fill outside the health bar with healAbsorbs.  Instead, an overHealAbsorbGlow is shown.
        if (health < myCurrentHealAbsorb) then
            frame.overHealAbsorbGlow:Show()
            myCurrentHealAbsorb = health
        else
            frame.overHealAbsorbGlow:Hide()
        end
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
    --We don't fill outside the the health bar with absorbs.  Instead, an overAbsorbGlow is shown.
    local overAbsorb = false
    if ((health - myCurrentHealAbsorb + allIncomingHeal + totalAbsorb >= maxHealth and Precognito.db.profile.healPredict) or health + totalAbsorb >= maxHealth) then
        if (totalAbsorb > 0) then
            overAbsorb = true
        end
        if (allIncomingHeal > myCurrentHealAbsorb) and Precognito.db.profile.healPredict then
            totalAbsorb = max(0, maxHealth - (health - myCurrentHealAbsorb + allIncomingHeal))
        else
            totalAbsorb = max(0, maxHealth - health)
        end
    end

    if (overAbsorb) and Precognito.db.profile.absorbTrack then
        frame.overAbsorbGlow:Show()
    else
        frame.overAbsorbGlow:Hide()
    end

    local healthTexture = frame.healthbar:GetStatusBarTexture()

    local myCurrentHealAbsorbPercent = 0
    local healAbsorbTexture = nil
    if (frame.healAbsorbBar) then
        myCurrentHealAbsorbPercent = myCurrentHealAbsorb / maxHealth

        --If allIncomingHeal is greater than myCurrentHealAbsorb, then the current
        --heal absorb will be completely overlayed by the incoming heals so we don't show it.
        if (myCurrentHealAbsorb > allIncomingHeal) then
            local shownHealAbsorb = myCurrentHealAbsorb - allIncomingHeal
            local shownHealAbsorbPercent = shownHealAbsorb / maxHealth

            healAbsorbTexture = UnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.healAbsorbBar, shownHealAbsorb, -shownHealAbsorbPercent)

            --If there are incoming heals the left shadow would be overlayed by the incoming heals
            --so it isn't shown.
            if (allIncomingHeal > 0) then
                frame.healAbsorbBarLeftShadow:Hide()
            else
                frame.healAbsorbBarLeftShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPLEFT", 0, 0)
                frame.healAbsorbBarLeftShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMLEFT", 0, 0)
                frame.healAbsorbBarLeftShadow:Show()
            end
            -- The right shadow is only shown if there are absorbs on the health bar.
            if (totalAbsorb > 0) then
                frame.healAbsorbBarRightShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPRIGHT", -8, 0)
                frame.healAbsorbBarRightShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMRIGHT", -8, 0)
                frame.healAbsorbBarRightShadow:Show()
            else
                frame.healAbsorbBarRightShadow:Hide()
            end
        else
            frame.healAbsorbBar:Hide()
            frame.healAbsorbBarLeftShadow:Hide()
            frame.healAbsorbBarRightShadow:Hide()
        end
    end
    --Show myIncomingHeal on the health bar.
    local incomingHealTexture
    if Precognito.db.profile.healPredict then
        incomingHealTexture = UnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.myHealPredictionBars, myIncomingHeal, -myCurrentHealAbsorbPercent)
        --Append otherIncomingHeal on the health bar
        if (myIncomingHeal > 0) then
            incomingHealTexture = UnitFrameUtil_UpdateFillBar(frame, incomingHealTexture, frame.otherHealPredictionBar, otherIncomingHeal)
        else
            incomingHealTexture = UnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.otherHealPredictionBar, otherIncomingHeal, -myCurrentHealAbsorbPercent)
        end
    else
        incomingHealTexture = healthTexture
    end
    --Append absorbs to the correct section of the health bar.
    local appendTexture = nil
    if (healAbsorbTexture) then
        --If there is a healAbsorb part shown, append the absorb to the end of that.
        appendTexture = healAbsorbTexture
    else
        --Otherwise, append the absorb to the end of the the incomingHeals part
        appendTexture = incomingHealTexture
    end
    if Precognito.db.profile.absorbTrack then
        UnitFrameUtil_UpdateFillBar(frame, appendTexture, frame.totalAbsorbBar, totalAbsorb)
    end
end

local function UnitFrame_FireEvent(self, event)
    UnitFrame_OnEvent(self, event, self.unit)
end

local function LibEventCallback(self, event, ...)
    local arg1, _, arg3 = ...
    if (not self.unit) then
        return
    end

    if (event == "EffectApplied" and arg3 == UnitGUID(self.unit)) then
        UnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    elseif (arg1 == UnitGUID(self.unit)) then
        if (event == "UnitUpdated") then
            UnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
        elseif (event == "EffectRemoved") then
            UnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
        elseif (event == "UnitCleared") then
            UnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
        elseif (event == "AreaCreated") then
            UnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
        elseif (event == "AreaCleared") then
            UnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
        elseif (event == "UnitAbsorbed") then
            UnitFrame_FireEvent(self, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
        end
    end
end

local function UnitFrame_RegisterCallback(self)
    LibAbsorb.RegisterCallback(self, "EffectApplied", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "EffectUpdated", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "EffectRemoved", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "UnitUpdated", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "UnitCleared", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "AreaCreated", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "AreaCleared", LibEventCallback, self)
    LibAbsorb.RegisterCallback(self, "UnitAbsorbed", LibEventCallback, self)
end

local function UnitFrameHealthBar_OnUpdate_New(self)
    if (not self.disconnected and not self.lockValues) then
        local currValue = UnitHealth(self.unit);
        local animatedLossBar = self.AnimatedLossBar;
        if (currValue ~= self.currValue) then
            if (not self.ignoreNoUnit or UnitGUID(self.unit)) then
                if animatedLossBar then
                    animatedLossBar:UpdateHealth(currValue, self.currValue);
                end
                self:SetValue(currValue);
                self.currValue = currValue;
                TextStatusBar_UpdateTextString(self);
                UnitFrameHealPredictionBars_Update(self:GetParent());
            end
        end
        if animatedLossBar then
            animatedLossBar:UpdateLossAnimation(currValue);
        end
    end
end

local function UnitFrame_Initialize(self, myHealPredictionBars, otherHealPredictionBar, totalAbsorbBar, totalAbsorbBarOverlay,
                                    overAbsorbGlow, overHealAbsorbGlow, healAbsorbBar, healAbsorbBarLeftShadow, healAbsorbBarRightShadow, myManaCostPredictionBars)

    self.myHealPredictionBars = myHealPredictionBars
    self.otherHealPredictionBar = otherHealPredictionBar
    self.totalAbsorbBar = totalAbsorbBar
    self.totalAbsorbBarOverlay = totalAbsorbBarOverlay
    self.overAbsorbGlow = overAbsorbGlow
    self.overHealAbsorbGlow = overHealAbsorbGlow
    self.healAbsorbBar = healAbsorbBar
    self.healAbsorbBarLeftShadow = healAbsorbBarLeftShadow
    self.healAbsorbBarRightShadow = healAbsorbBarRightShadow
    self.myManaCostPredictionBars = myManaCostPredictionBars

    self.myHealPredictionBars:ClearAllPoints();
    self.otherHealPredictionBar:ClearAllPoints();
    self.totalAbsorbBar:ClearAllPoints();
    self.totalAbsorbBar.overlay = self.totalAbsorbBarOverlay;
    self.totalAbsorbBarOverlay:SetAllPoints(self.totalAbsorbBar);
    self.totalAbsorbBarOverlay.tileSize = 32;
    self.overAbsorbGlow:ClearAllPoints();
    self.overAbsorbGlow:SetPoint("TOPLEFT", self.healthbar, "TOPRIGHT", -7, 0);
    self.overAbsorbGlow:SetPoint("BOTTOMLEFT", self.healthbar, "BOTTOMRIGHT", -7, 0);
    self.healAbsorbBar:ClearAllPoints();
    self.healAbsorbBar:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true);
    self.overHealAbsorbGlow:ClearAllPoints();
    self.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", self.healthbar, "BOTTOMLEFT", 7, 0);
    self.overHealAbsorbGlow:SetPoint("TOPRIGHT", self.healthbar, "TOPLEFT", 7, 0);
    self.healAbsorbBarLeftShadow:ClearAllPoints();
    self.healAbsorbBarRightShadow:ClearAllPoints();

    self:RegisterUnitEvent("UNIT_MAXHEALTH", self.unit);
    self:RegisterUnitEvent("UNIT_HEAL_PREDICTION", self.unit)

    if Precognito.db.profile.absorbTrack then
        UnitFrame_RegisterCallback(self)
    end

    if (self.unit == "player") and Precognito.db.profile.animMana then
        self.myManaCostPredictionBars:ClearAllPoints()

        self:RegisterUnitEvent("UNIT_SPELLCAST_START", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", self.unit)
    else
        self.myManaCostPredictionBars:Hide()
    end

    if (self.unit == "player") then
        if Precognito.db.profile.animHealth then
            self.healthbar:SetScript("OnUpdate", UnitFrameHealthBar_OnUpdate_New);
            self.PlayerFrameHealthBarAnimatedHealth = Mixin(CreateFrame("StatusBar", nil, self), AnimatedHealthLossMixin)
            self.PlayerFrameHealthBarAnimatedHealth:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            self.PlayerFrameHealthBarAnimatedHealth:SetFrameLevel(self.healthbar:GetFrameLevel() - 1)
            self.PlayerFrameHealthBarAnimatedHealth:OnLoad()
            self.PlayerFrameHealthBarAnimatedHealth:SetUnitHealthBar("player", self.healthbar)
            self.PlayerFrameHealthBarAnimatedHealth:Hide()
        end

        if self.manabar then
            if Precognito.db.profile.animMana then
                self.manabar.FeedbackFrame = CreateFrame("Frame", nil, self.manabar, "BuilderSpenderFrame")
                self.manabar.FeedbackFrame:SetAllPoints()
                self.manabar.FeedbackFrame:SetFrameLevel(self:GetParent():GetFrameLevel() + 2)
                self.manabar:SetScript("OnUpdate", UnitFrameManaBar_OnUpdate)
            end

            if Precognito.db.profile.FeedBack then
                self.manabar.FullPowerFrame = CreateFrame("Frame", nil, self.manabar, "FullResourcePulseFrame")
                self.manabar.FullPowerFrame:SetPoint("TOPRIGHT", 0, 0)
                self.manabar.FullPowerFrame:SetSize(119, 12)
            end
        end
    end

    UnitFrame_Update(self)
end

local function UnitFrameManaBar_UpdateType(manaBar)
    local prefix = manaBar:GetParent():GetName()
    if (not manaBar) or not whitelist[prefix] then
        return ;
    end

    local unitFrame = manaBar:GetParent();
    local powerType, powerToken = UnitPowerType(manaBar.unit);
    local info = PowerBarColor[powerToken];
    if ( info ) then
        if ( not manaBar.lockColor ) then
            if ( manaBar.FullPowerFrame ) and Precognito.db.profile.FeedBack then
                manaBar.FullPowerFrame:Initialize(true);
            end
        end
    end

    if (manaBar.powerType ~= powerType or manaBar.powerType ~= powerType) then
        manaBar.powerType = powerType;
        manaBar.powerToken = powerToken;
        if (manaBar.FullPowerFrame) then
            manaBar.FullPowerFrame:RemoveAnims();
        end
        if manaBar.FeedbackFrame then
            manaBar.FeedbackFrame:StopFeedbackAnim();
        end
        manaBar.currValue = UnitPower("player", powerType);
        if unitFrame.myManaCostPredictionBars then
            unitFrame.myManaCostPredictionBars:Hide();
        end
        unitFrame.predictedPowerCost = 0;
    end
end

function UnitFrameManaCostPredictionBars_Update(frame, isStarting, startTime, endTime, spellID)
    if (not frame.manabar or not frame.myManaCostPredictionBars) then
        return
    end

    local cost = 0

    if not isStarting or startTime == endTime then
        local _, _, _, _, _, _, _, _, currentSpellID = CastingInfo()

        if currentSpellID and frame.predictedPowerCost then
            cost = frame.predictedPowerCost
        else
            frame.predictedPowerCost = nil
        end
    else
        local costTable = GetSpellPowerCost(spellID)

        for _, costInfo in pairs(costTable) do
            if costInfo.type == frame.manabar.powerType then
                cost = costInfo.cost
                break
            end
        end

        frame.predictedPowerCost = cost
    end
    local manaBarTexture = frame.manabar:GetStatusBarTexture()
    UnitFrameManaBar_Update(frame.manabar, frame.unit)
    UnitFrameUtil_UpdateManaFillBar(frame, manaBarTexture, frame.myManaCostPredictionBars, cost)
end

local function UnitFrameHealPredictionBars_UpdateMax(self)
    if (not self.myHealPredictionBars) then
        return
    end

    UnitFrameHealPredictionBars_Update(self)
end

local function UF_Event(self, event, ...)
    local prefix = self:GetName()

    if not whitelist[prefix] then
        return
    end

    if (not self.myHealPredictionBars) then
        CreateFrame("Frame", nil, self, "HealPredictionTemplate")

        UnitFrame_Initialize(self, _G[prefix .. "MyHealPredictionBars"], _G[prefix .. "OtherHealPredictionBar"],
                _G[prefix .. "TotalAbsorbBar"], _G[prefix .. "TotalAbsorbBarOverlay"],
                _G[prefix .. "FrameOverAbsorbGlow"], _G[prefix .. "OverHealAbsorbGlow"],
                _G[prefix .. "HealAbsorbBar"], _G[prefix .. "HealAbsorbBarLeftShadow"],
                _G[prefix .. "HealAbsorbBarRightShadow"], _G[prefix .. "ManaCostPredictionBars"])
    end

    if (event == "UNIT_MAXHEALTH") then
        UnitFrameHealPredictionBars_UpdateMax(self)
        UnitFrameHealPredictionBars_Update(self)
    elseif event == "UNIT_HEALTH" then
        UnitFrameHealPredictionBars_Update(self)
    elseif (event == "UNIT_HEAL_PREDICTION") or (event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED") then
        UnitFrameHealPredictionBars_Update(self)
    elseif (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_SUCCEEDED") then
        local unit = ...
        if (UnitIsUnit(unit, "player")) then
            local _, _, _, startTime, endTime, _, _, _, spellID = CastingInfo()
            UnitFrameManaCostPredictionBars_Update(self, event == "UNIT_SPELLCAST_START", startTime, endTime, spellID)
        end
    elseif event == "VARIABLES_LOADED" then
        if GetCVar("predictedHealth") ~= "1" then
            SetCVar("predictedHealth", 1)
        end
    end
end

function Precognito:UFInit()
    hooksecurefunc("UnitFrame_OnEvent", UF_Event)
    hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar, unit)
        if not statusbar then
            return
        end

        if (unit == statusbar.unit) then
            if statusbar.AnimatedLossBar then
                statusbar.AnimatedLossBar:UpdateHealthMinMax()
            end
        end
        UnitFrameHealPredictionBars_Update(statusbar:GetParent())
    end)

    hooksecurefunc("UnitFrame_Update", function(self)
        local prefix = self:GetName()
        if not whitelist[prefix] then
            return
        end
        UnitFrameHealPredictionBars_UpdateMax(self)
        UnitFrameHealPredictionBars_Update(self)
        if Precognito.db.profile.animMana then
            UnitFrameManaCostPredictionBars_Update(self)
        end
    end)

    if Precognito.db.profile.animMana or Precognito.db.profile.FeedBack then
        hooksecurefunc("UnitFrameManaBar_UpdateType", UnitFrameManaBar_UpdateType)
    end
end

