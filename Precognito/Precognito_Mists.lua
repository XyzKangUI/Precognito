local addonName, Precog = ...
local min, max = math.min, math.max
local UnitGetTotalAbsorbs, UnitGetIncomingHeals, UnitGetTotalHealAbsorbs = UnitGetTotalAbsorbs, UnitGetIncomingHeals, UnitGetTotalHealAbsorbs

--- Raid Frames
local MAX_INCOMING_HEAL_OVERFLOW = 1.05
local function CompactUnitFrame_UpdateHealPredictions(frame)
    if ( not frame.myHealPrediction and not frame.otherHealPrediction and not frame.healAbsorb and not frame.totalAbsorb ) then
        return;
    end

    if not frame or frame:IsForbidden() or not frame:IsVisible() then
        return
    end

    local _, maxHealth = frame.healthBar:GetMinMaxValues();
    local health = frame.healthBar:GetValue();

    if ( maxHealth <= 0 ) then
        return;
    end

    local myIncomingHeal = UnitGetIncomingHeals(frame.displayedUnit, "player") or 0;
    local allIncomingHeal = UnitGetIncomingHeals(frame.displayedUnit) or 0;
    local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0;
    local myCurrentHealAbsorb = UnitGetTotalHealAbsorbs(frame.unit) or 0;

    --We don't fill outside the health bar with healAbsorbs.  Instead, an overHealAbsorbGlow is shown.
    if ( health < myCurrentHealAbsorb ) then
        if frame.overHealAbsorbGlow then
            frame.overHealAbsorbGlow:Show();
        end
        myCurrentHealAbsorb = health;
    else
        if frame.overHealAbsorbGlow then
            frame.overHealAbsorbGlow:Hide();
        end
    end

    --We don't fill outside the health bar with healAbsorbs.  Instead, an overHealAbsorbGlow is shown.
    myCurrentHealAbsorb = UnitGetTotalHealAbsorbs(frame.displayedUnit) or 0;
    if ( health < myCurrentHealAbsorb ) then
        frame.overHealAbsorbGlow:Show();
        myCurrentHealAbsorb = health;
    else
        frame.overHealAbsorbGlow:Hide();
    end

    --See how far we're going over the health bar and make sure we don't go too far out of the frame.
    if ( health - myCurrentHealAbsorb + allIncomingHeal > maxHealth * MAX_INCOMING_HEAL_OVERFLOW ) then
        allIncomingHeal = maxHealth * MAX_INCOMING_HEAL_OVERFLOW - health + myCurrentHealAbsorb;
    end

    local otherIncomingHeal = 0

    --Split up incoming heals.
    if ( allIncomingHeal >= myIncomingHeal ) then
        otherIncomingHeal = allIncomingHeal - myIncomingHeal;
    else
        myIncomingHeal = allIncomingHeal;
    end

    local overAbsorb = false
    --We don't fill outside the the health bar with absorbs.  Instead, an overAbsorbGlow is shown.
    if (((health + allIncomingHeal + totalAbsorb) >= maxHealth and Precog.db.CUFPredicts) or health + totalAbsorb >= maxHealth) then
        if (totalAbsorb > 0) then
            overAbsorb = true
        end

        if (allIncomingHeal > myCurrentHealAbsorb) and Precog.db.CUFPredicts then
            totalAbsorb = max(0, maxHealth - (health - myCurrentHealAbsorb + allIncomingHeal))
        else
            totalAbsorb = max(0, maxHealth - health)
        end
    end

    if (frame.overAbsorbGlow) then
        if ( overAbsorb ) then
            frame.overAbsorbGlow:Show();
        else
            frame.overAbsorbGlow:Hide();
        end
    end

    local healthTexture = frame.healthBar:GetStatusBarTexture()
    local myCurrentHealAbsorbPercent = myCurrentHealAbsorb / maxHealth;
    local healAbsorbTexture = nil;

    --If allIncomingHeal is greater than myCurrentHealAbsorb, then the current
    --heal absorb will be completely overlayed by the incoming heals so we don't show it.
    if ( myCurrentHealAbsorb > allIncomingHeal ) then
        local shownHealAbsorb = myCurrentHealAbsorb - allIncomingHeal;
        local shownHealAbsorbPercent = shownHealAbsorb / maxHealth;
        healAbsorbTexture = CompactUnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.myHealAbsorb, shownHealAbsorb, -shownHealAbsorbPercent);

        --If there are incoming heals the left shadow would be overlayed by the incoming heals
        --so it isn't shown.
        if ( allIncomingHeal > 0 ) then
            frame.myHealAbsorbLeftShadow:Hide();
        else
            frame.myHealAbsorbLeftShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPLEFT", 0, 0);
            frame.myHealAbsorbLeftShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMLEFT", 0, 0);
            frame.myHealAbsorbLeftShadow:Show();
        end

        -- The right shadow is only shown if there are absorbs on the health bar.
        if ( totalAbsorb > 0 ) then
            frame.myHealAbsorbRightShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPRIGHT", -8, 0);
            frame.myHealAbsorbRightShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMRIGHT", -8, 0);
            frame.myHealAbsorbRightShadow:Show();
        else
            frame.myHealAbsorbRightShadow:Hide();
        end
    else
        frame.myHealAbsorb:Hide();
        frame.myHealAbsorbRightShadow:Hide();
        frame.myHealAbsorbLeftShadow:Hide();
    end

    --Show myIncomingHeal on the health bar.
    local incomingHealsTexture
    if Precog.db.CUFPredicts then
        incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame, healthTexture, frame.myHealPrediction, myIncomingHeal, -myCurrentHealAbsorbPercent);
        --Append otherIncomingHeal on the health bar.
        incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame, incomingHealsTexture, frame.otherHealPrediction, otherIncomingHeal);
    else
        incomingHealsTexture = healthTexture
    end

    --Append absorbs to the correct section of the health bar.
    local appendTexture = nil;
    if ( healAbsorbTexture ) then
        --If there is a healAbsorb part shown, append the absorb to the end of that.
        appendTexture = healAbsorbTexture;
    else
        --Otherwise, append the absorb to the end of the the incomingHeals part;
        appendTexture = incomingHealsTexture;
    end

    CompactUnitFrameUtil_UpdateFillBar(frame, appendTexture, frame.totalAbsorb, totalAbsorb)

    if Precog.db.CUFOvershield then
        local absorbBar = frame.totalAbsorb
        if not absorbBar or absorbBar:IsForbidden() then
            return
        end

        local absorbOverlay = frame.totalAbsorbOverlay
        if not absorbOverlay or absorbOverlay:IsForbidden() then
            return
        end

        local healthBar = frame.healthBar
        if not healthBar or healthBar:IsForbidden() then
            return
        end

        local _, maxHealth = healthBar:GetMinMaxValues()
        if maxHealth <= 0 then
            return
        end

        absorbOverlay:SetParent(healthBar)
        absorbOverlay:ClearAllPoints()
        absorbOverlay:SetDrawLayer("OVERLAY")

        local absorbGlow = frame.overAbsorbGlow
        if absorbGlow and not absorbGlow:IsForbidden() then
            absorbGlow:ClearAllPoints()
            absorbGlow:SetPoint("TOPLEFT", absorbOverlay, "TOPLEFT", -5, 0);
            absorbGlow:SetPoint("BOTTOMLEFT", absorbOverlay, "BOTTOMLEFT", -5, 0);
            absorbGlow:SetAlpha(0.6);
            absorbGlow:SetDrawLayer("OVERLAY")
        end

        local totalAbsorb = UnitGetTotalAbsorbs(frame.displayedUnit) or 0
        if totalAbsorb > maxHealth then
            totalAbsorb = maxHealth
        end

        if totalAbsorb > 0 then
            if absorbBar:IsShown() then
                absorbOverlay:SetPoint("TOPRIGHT", absorbBar, "TOPRIGHT", 0, 0)
                absorbOverlay:SetPoint("BOTTOMRIGHT", absorbBar, "BOTTOMRIGHT", 0, 0)
            else
                absorbOverlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                absorbOverlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end

            local totalWidth, totalHeight = healthBar:GetSize()
            local barSize = totalAbsorb / maxHealth * totalWidth

            absorbOverlay:SetWidth(barSize)
            absorbOverlay:SetTexCoord(0, min(max(barSize / absorbOverlay.tileSize, 0), 1), 0, min(max(totalHeight / absorbOverlay.tileSize, 0), 1))
            absorbOverlay:Show()
        end
    end
end

--- UnitFrame
local function UnitFrameHealthBar_OnUpdate(self)
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
                UnitFrameHealPredictionBars_Update(self:GetParent())
            end
        end

        if animatedLossBar then
            animatedLossBar:UpdateLossAnimation(currValue);
        end
    end
end

local MAX_INCOMING_HEAL_OVERFLOW = 1.0
local function UnitFrameHealPredictionBars_Updates(frame)
    if (not frame.myHealPredictionBar and not frame.otherHealPredictionBar and not frame.healAbsorbBar and not frame.totalAbsorbBar) then
        return ;
    end

    local _, maxHealth = frame.healthbar:GetMinMaxValues();
    local health = frame.healthbar:GetValue();
    if (maxHealth <= 0) then
        return ;
    end

    local myIncomingHeal = UnitGetIncomingHeals(frame.unit, "player") or 0;
    local allIncomingHeal = UnitGetIncomingHeals(frame.unit) or 0;
    local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0;

    local myCurrentHealAbsorb = 0;
    if ( frame.healAbsorbBar ) then
        myCurrentHealAbsorb = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(frame.unit) or 0;

        --We don't fill outside the health bar with healAbsorbs.  Instead, an overHealAbsorbGlow is shown.
        if ( health < myCurrentHealAbsorb ) then
            frame.overHealAbsorbGlow:Show();
            myCurrentHealAbsorb = health;
        else
            frame.overHealAbsorbGlow:Hide();
        end
    end

    --See how far we're going over the health bar and make sure we don't go too far out of the frame.
    if ( health - myCurrentHealAbsorb + allIncomingHeal > maxHealth * MAX_INCOMING_HEAL_OVERFLOW ) then
        allIncomingHeal = maxHealth * MAX_INCOMING_HEAL_OVERFLOW - health + myCurrentHealAbsorb;
    end

    local otherIncomingHeal = 0;

    --Split up incoming heals.
    if (allIncomingHeal >= myIncomingHeal) then
        otherIncomingHeal = allIncomingHeal - myIncomingHeal;
    else
        myIncomingHeal = allIncomingHeal;
    end

    --We don't fill outside the the health bar with absorbs.  Instead, an overAbsorbGlow is shown.
    local overAbsorb = false;
    if (health - myCurrentHealAbsorb + allIncomingHeal + totalAbsorb >= maxHealth and Precog.db.healPredict) or (health + totalAbsorb >= maxHealth) then
        if (totalAbsorb > 0) then
            overAbsorb = true
        end

        if ((allIncomingHeal) > myCurrentHealAbsorb) and Precog.db.healPredict then
            totalAbsorb = max(0, maxHealth - (health - myCurrentHealAbsorb + allIncomingHeal));
        else
            totalAbsorb = max(0, maxHealth - health);
        end
    end

    if frame.overAbsorbGlow then
        if (overAbsorb) and Precog.db.absorbTrack then
            frame.overAbsorbGlow:Show()
        else
            frame.overAbsorbGlow:Hide()
        end
    end

    local healthTexture = frame.healthbar:GetStatusBarTexture();
    local myCurrentHealAbsorbPercent = 0;
    local healAbsorbTexture = nil;

    if ( frame.healAbsorbBar ) then
        myCurrentHealAbsorbPercent = myCurrentHealAbsorb / maxHealth;

        --If allIncomingHeal is greater than myCurrentHealAbsorb, then the current
        --heal absorb will be completely overlayed by the incoming heals so we don't show it.
        if ( myCurrentHealAbsorb > allIncomingHeal ) then
            local shownHealAbsorb = myCurrentHealAbsorb - allIncomingHeal;
            local shownHealAbsorbPercent = shownHealAbsorb / maxHealth;

            healAbsorbTexture = frame.healAbsorbBar:UpdateFillPosition(healthTexture, shownHealAbsorb, -shownHealAbsorbPercent);

            --If there are incoming heals the left shadow would be overlayed by the incoming heals
            --so it isn't shown.
            if frame.healAbsorbBar.LeftShadow then
                frame.healAbsorbBar.LeftShadow:SetShown(allIncomingHeal <= 0);
            end

            -- The right shadow is only shown if there are absorbs on the health bar.
            if frame.healAbsorbBar.RightShadow then
                frame.healAbsorbBar.RightShadow:SetShown(totalAbsorb > 0)
            end
        else
            frame.healAbsorbBar:Hide();
        end
    end

    --Show myIncomingHeal on the health bar.
    local incomingHealTexture;
    if Precog.db.healPredict then
        if frame.myHealPredictionBar then
            incomingHealTexture = frame.myHealPredictionBar:UpdateFillPosition(healthTexture, myIncomingHeal, -myCurrentHealAbsorbPercent);
        end

        local otherHealLeftTexture = (myIncomingHeal > 0) and incomingHealTexture or healthTexture;
        local xOffset = (myIncomingHeal > 0) and 0 or -myCurrentHealAbsorbPercent;

        --Append otherIncomingHeal on the health bar
        if frame.otherHealPredictionBar then
            incomingHealTexture = frame.otherHealPredictionBar:UpdateFillPosition(otherHealLeftTexture, otherIncomingHeal, xOffset);
        end
    else
        incomingHealTexture = healthTexture
    end

    --Append absorbs to the correct section of the health bar.
    local appendTexture = nil

    if ( healAbsorbTexture ) then
        --If there is a healAbsorb part shown, append the absorb to the end of that.
        appendTexture = healAbsorbTexture;
    else
        --Otherwise, append the absorb to the end of the the incomingHeals or health part;
        appendTexture = incomingHealTexture or healthTexture;
    end

    local absorbBar = frame.totalAbsorbBar

    if absorbBar and Precog.db.absorbTrack then
        absorbBar:UpdateFillPosition(appendTexture, totalAbsorb);
    end

    if Precog.db.Overshield then
        if not absorbBar or absorbBar:IsForbidden() then
            return
        end

        local absorbOverlay = absorbBar.TiledFillOverlay
        if not absorbOverlay or absorbOverlay:IsForbidden() then
            return
        end

        local healthBar = frame.healthbar
        if not healthBar or healthBar:IsForbidden() then
            return
        end

        local _, maxHealth = healthBar:GetMinMaxValues()
        if maxHealth <= 0 then
            return
        end

        local totalAbsorb = UnitGetTotalAbsorbs(frame.unit) or 0
        if totalAbsorb > maxHealth then
            totalAbsorb = maxHealth
        end

        if totalAbsorb > 0 then
            if absorbBar:IsShown() then
                absorbOverlay:SetPoint("TOPRIGHT", absorbBar.FillMask, "TOPRIGHT", 0, 0)
                absorbOverlay:SetPoint("BOTTOMRIGHT", absorbBar.FillMask, "BOTTOMRIGHT", 0, 0)
            else
                absorbOverlay:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                absorbOverlay:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end

            local totalWidth, totalHeight = healthBar:GetSize()
            local barSize = totalAbsorb / maxHealth * totalWidth

            absorbOverlay:SetWidth(barSize)
            absorbOverlay:SetTexCoord(0, min(max(barSize / absorbBar.tiledFillOverlaySize, 0), 1), 0, min(max(totalHeight / absorbBar.tiledFillOverlaySize, 0), 1))
            absorbOverlay:Show()
        else
            absorbOverlay:Hide()
        end
    end
end

local function UnitFrameManaBar_UpdateType(manaBar)
    local unitFrame = manaBar:GetParent()
    local powerType, powerToken = UnitPowerType(manaBar.unit)
    local info = PowerBarColor[powerToken]
    if (info) then
        if (not manaBar.lockColor) then
            if (manaBar.FullPowerFrame) and Precog.db.Feedback then
                manaBar.FullPowerFrame:Initialize(true)
            end
        end
    end

    if (manaBar.powerType ~= powerType or manaBar.powerType ~= powerType) then
        manaBar.powerType = powerType
        manaBar.powerToken = powerToken
        if (manaBar.FullPowerFrame) then
            manaBar.FullPowerFrame:RemoveAnims()
        end
        if manaBar.FeedbackFrame then
            manaBar.FeedbackFrame:StopFeedbackAnim()
        end
        manaBar.currValue = UnitPower("player", powerType)
        if unitFrame.myManaCostPredictionBar then
            unitFrame.myManaCostPredictionBar:Hide()
        end
        unitFrame.predictedPowerCost = 0
    end
end

if not UnitFrameManaCostPredictionBars_Update then
    UnitFrameManaCostPredictionBars_Update = function(frame, isStarting, startTime, endTime, spellID)
        if (not frame.manabar or not frame.myManaCostPredictionBar) then
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
        frame.myManaCostPredictionBar:UpdateFillPosition(manaBarTexture, cost);
    end
end

local function UnitFrame_Initialize(self)
    if Precog.db.animMana then
        local ManaPredictionBar = CreateFrame("StatusBar", "$parentManaCostPredictionBar", PlayerFrameManaBar, "ManaCostPredictionBarTemplate")
        ManaPredictionBar:SetFrameLevel(self.manabar:GetFrameLevel() + 1)
        ManaPredictionBar.fillTexture = "Interface\\TargetingFrame\\UI-StatusBar"
        ManaPredictionBar.Fill:SetTexture(ManaPredictionBar.fillTexture)
        ManaPredictionBar.FillMask:SetTexture(ManaPredictionBar.fillTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ManaPredictionBar.fillColor = CreateColor(0, 0.447, 1.000, 1.000)
        ManaPredictionBar.Fill:SetVertexColor(ManaPredictionBar.fillColor:GetRGBA())
        self.myManaCostPredictionBar = ManaPredictionBar

        self:RegisterUnitEvent("UNIT_SPELLCAST_START", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", self.unit)
        hooksecurefunc("UnitFrameManaBar_UpdateType", UnitFrameManaBar_UpdateType)
    end

    if Precog.db.animHealth then
        self.PlayerFrameHealthBarAnimatedHealth = CreateFrame("StatusBar", nil, self)
        Mixin(self.PlayerFrameHealthBarAnimatedHealth, AnimatedHealthLossMixin)
        self.PlayerFrameHealthBarAnimatedHealth:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        self.PlayerFrameHealthBarAnimatedHealth:SetFrameLevel(PlayerFrameHealthBar:GetFrameLevel() - 1)
        self.PlayerFrameHealthBarAnimatedHealth:OnLoad()
        self.PlayerFrameHealthBarAnimatedHealth:SetUnitHealthBar("player", PlayerFrameHealthBar)
        self.PlayerFrameHealthBarAnimatedHealth:Hide()
        function self.PlayerFrameHealthBarAnimatedHealth:UpdateLossAnimation(currentHealth)
            local totalAbsorb = UnitGetTotalAbsorbs(self.unit) or 0
            if totalAbsorb > 0 then
                self:CancelAnimation()
            end

            if self.animationStartTime then
                local animationValue, animationCompletePercent = self:GetHealthLossAnimationData(currentHealth, self.animationStartValue)
                self.animationCompletePercent = animationCompletePercent
                if animationCompletePercent >= 1 then
                    self:CancelAnimation()
                else
                    self:SetValue(animationValue)
                end
            end
        end
    end

    if self.manabar then
        if Precog.db.animMana then
            self.manabar.FeedbackFrame = CreateFrame("Frame", nil, self.manabar, "BuilderSpenderFrame")
            self.manabar.FeedbackFrame:SetAllPoints()
            self.manabar.FeedbackFrame:SetFrameLevel(self:GetParent():GetFrameLevel() + 2)
            self.manabar:SetScript("OnUpdate", UnitFrameManaBar_OnUpdate)
        end

        if Precog.db.Feedback then
            self.manabar.FullPowerFrame = CreateFrame("Frame", nil, self.manabar, "FullResourcePulseFrame")
            self.manabar.FullPowerFrame:SetPoint("TOPRIGHT", 0, 0)
            self.manabar.FullPowerFrame:SetSize(119, 12)
        end
    end

    UnitFrameHealthBar_Update(self.healthbar, self.unit)
    UnitFrameManaBar_Update(self.manabar, self.unit)
end

--- Some Settings

local function CheckBtn(title, desc, panel, onClick)
    local frame = CreateFrame("CheckButton", title, panel, "InterfaceOptionsCheckButtonTemplate")
    frame:SetScript("OnClick", function(self)
        local enabled = self:GetChecked()
        onClick(self, enabled and true or false)
    end)
    frame.text = _G[frame:GetName() .. "Text"]
    frame.text:SetText(title)
    frame.tooltipText = desc
    return frame
end

local options = {}
local displayOrder = {}

options = {
    CUFPredicts = { "Raidframe Incoming Heals", true },
    CUFAbsorbs = { "Raidframe Absorbs", true },
    CUFOvershield = { "Raidframe Overshield", false },
    healPredict = { "UnitFrame Incoming Heals", true },
    absorbTrack = { "UnitFrame Absorbs", true },
    animMana = { "PlayerFrame Mana-cost Prediction", true },
    animHealth = { "PlayerFrame Animated Health", false },
    Feedback = { "PlayerFrame Animated Full Power", true },
    Overshield = { "UnitFrame Overshield", false },
}

displayOrder = {
    "CUFPredicts",
    "CUFAbsorbs",
    "CUFOvershield",
    "healPredict",
    "absorbTrack",
    "Overshield",
    "animMana",
    "animHealth",
    "Feedback",
}

local function onClick(key)
    return function(self, value)
        Precog.db[key] = value
    end
end

local settingsFrame = CreateFrame("Frame")
settingsFrame:RegisterEvent("ADDON_LOADED")
settingsFrame:RegisterEvent("PLAYER_LOGIN")
settingsFrame:RegisterEvent("PLAYER_LOGOUT")
settingsFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        if not PrecognitoDB then
            PrecognitoDB = {}
        end

        for _, key in ipairs(displayOrder) do
            local value = options[key]
            if PrecognitoDB[key] == nil then
                PrecognitoDB[key] = value[2]
            end
        end

        Precog.db = PrecognitoDB

        local panel = CreateFrame("Frame")
        panel.name = "|cff33ff99Precognito|r"
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))

        local yOffset = -10
        for _, key in pairs(displayOrder) do
            local option = options[key]
            local title, _ = unpack(option)
            local btn = CheckBtn(title, title, panel, onClick(key))
            btn:SetPoint("TOPLEFT", 10, yOffset)
            btn:SetChecked(Precog.db[key])
            yOffset = yOffset - 30
        end

        UnitFrame_Initialize(PlayerFrame)

        for _, v in pairs({ PlayerFrame, TargetFrame, FocusFrame }) do
            if not Precog.db.healPredict then
                if v.myHealPredictionBar then
                    v.myHealPredictionBar:SetAlpha(0)
                end

                if v.otherHealPredictionBar then
                    v.otherHealPredictionBar:SetAlpha(0)
                end
            end

            if not Precog.db.absorbTrack then
                v.healAbsorbBar:SetAlpha(0)
                v.totalAbsorbBar:SetAlpha(0)
                v.overAbsorbGlow:SetAlpha(0)
                v.overHealAbsorbGlow:SetAlpha(0)
                v:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
                v:UnregisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            end
        end

        if Precog.db.CUFOvershield and Precog.db.CUFAbsorbs then
            hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", CompactUnitFrame_UpdateHealPredictions)
        end

        if not Precog.db.CUFPredicts or not Precog.db.CUFAbsorbs then
            hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
                if not Precog.db.CUFPredicts then
                    if frame.myHealPrediction and frame.myHealPrediction:GetTexture() ~= nil then
                        frame.myHealPrediction:SetTexture(0)
                    end
                    if frame.otherHealPrediction and frame.otherHealPrediction:GetTexture() ~= nil then
                        frame.otherHealPrediction:SetTexture(0)
                    end
                end

                if not Precog.db.CUFAbsorbs then
                    if frame.totalAbsorb and frame.totalAbsorb:GetAlpha() > 0 then
                        frame.totalAbsorb:SetAlpha(0)
                    end
                    if frame.totalAbsorbOverlay and frame.totalAbsorbOverlay:GetAlpha() > 0 then
                        frame.totalAbsorbOverlay:SetAlpha(0)
                    end
                    if frame.myHealAbsorb and frame.myHealAbsorb:GetAlpha() > 0 then
                        frame.myHealAbsorb:SetAlpha(0)
                    end
                    if frame.overAbsorbGlow and frame.overAbsorbGlow:GetAlpha() > 0 then
                        frame.overAbsorbGlow:SetAlpha(0)
                    end
                    if frame.overHealAbsorbGlow and frame.overHealAbsorbGlow:GetAlpha() > 0 then
                        frame.overHealAbsorbGlow:SetAlpha(0)
                    end
                    if frame.myHealAbsorbLeftShadow and frame.myHealAbsorbLeftShadow:GetAlpha() > 0 then
                        frame.myHealAbsorbLeftShadow:SetAlpha(0)
                    end
                    if frame.myHealAbsorbRightShadow and frame.myHealAbsorbRightShadow:GetAlpha() > 0 then
                        frame.myHealAbsorbRightShadow:SetAlpha(0)
                    end
                end
            end)
        end

        if Precog.db.Overshield or Precog.db.animMana then
            hooksecurefunc("UnitFrame_Update", function(self)
                if Precog.db.Overshield and Precog.db.absorbTrack then
                    local absorbBar = self.totalAbsorbBar
                    if not absorbBar or absorbBar:IsForbidden() then
                        return
                    end

                    local absorbOverlay = self.totalAbsorbBar.TiledFillOverlay
                    if not absorbOverlay or absorbOverlay:IsForbidden() then
                        return
                    end

                    local healthBar = self.healthbar
                    if not healthBar or healthBar:IsForbidden() then
                        return
                    end

                    absorbOverlay:SetParent(healthBar)
                    absorbOverlay:ClearAllPoints()

                    local absorbGlow = self.overAbsorbGlow
                    if absorbGlow and not absorbGlow:IsForbidden() then
                        absorbGlow:ClearAllPoints()
                        absorbGlow:SetPoint("TOPLEFT", absorbOverlay, "TOPLEFT", -5, 0)
                        absorbGlow:SetPoint("BOTTOMLEFT", absorbOverlay, "BOTTOMLEFT", -5, 0)
                        absorbGlow:SetAlpha(0.6)
                    end
                end

                UnitFrameHealPredictionBars_UpdateMax(self)
                UnitFrameHealPredictionBars_Update(self)
                if Precog.db.animMana then
                    UnitFrameManaCostPredictionBars_Update(self)
                end
            end)

            if Precog.db.Overshield and Precog.db.absorbTrack then
                hooksecurefunc("UnitFrameHealPredictionBars_Update", UnitFrameHealPredictionBars_Updates)
            end
        end

        -- Animates
        if Precog.db.animMana or Precog.db.Feedback then
            hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar, unit)
                if not statusbar then
                    return
                end
                UnitFrameHealPredictionBars_Update(statusbar:GetParent())
            end)
        end
    elseif event == "PLAYER_LOGOUT" then
        PrecognitoDB = Precog.db
    elseif event == "PLAYER_LOGIN" then
        --if Precog.db.animHealth then
        PlayerFrameHealthBar:SetScript("OnUpdate", UnitFrameHealthBar_OnUpdate)
        TargetFrameHealthBar:SetScript("OnUpdate", UnitFrameHealthBar_OnUpdate)
        FocusFrameHealthBar:SetScript("OnUpdate", UnitFrameHealthBar_OnUpdate)
        --end
    end
end)
