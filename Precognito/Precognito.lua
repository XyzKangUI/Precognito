local addonName, Precog = ...
local whitelist = {
    [PlayerFrame] = true,
    [TargetFrame] = true,
    [FocusFrame] = true
}
local UnitIsUnit, UnitGUID = UnitIsUnit, UnitGUID
local min, max = math.min, math.max
local strfind = string.find

--- Raid Frames
local MAX_INCOMING_HEAL_OVERFLOW = 1.05
local function CompactUnitFrame_UpdateHealPrediction(frame)
    local unit = frame.displayedUnit or frame.unit
    if not frame or not unit or strfind(unit, "nameplate") or not frame:IsVisible() then
        return
    end

    if frame and not frame:GetName() then
        return
    end

    local precogFrame = _G[frame:GetName() .. "PrecogFrame"]
    if not precogFrame then
        return
    end

    local _, maxHealth = frame.healthBar:GetMinMaxValues()
    local health = frame.healthBar:GetValue()

    if (maxHealth <= 0) then
        return
    end

    local myIncomingHeal = UnitGetIncomingHeals(frame.displayedUnit, "player") or 0
    local allIncomingHeal = UnitGetIncomingHeals(frame.displayedUnit) or 0
    local totalAbsorb = Precog.UnitGetTotalAbsorbs(frame.displayedUnit) or 0
    local necroAmount = 0

    if precogFrame.NecroAbsorbBar and Precog.db.CUFNecro then
        necroAmount = Precog.NecroAbsorb(frame.unit) or 0
    end

    --See how far we're going over the health bar and make sure we don't go too far out of the frame.
    if (health + allIncomingHeal > maxHealth * MAX_INCOMING_HEAL_OVERFLOW) then
        allIncomingHeal = maxHealth * MAX_INCOMING_HEAL_OVERFLOW - health
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
    if (((health + allIncomingHeal + totalAbsorb - necroAmount) >= maxHealth and Precog.db["CUFPredicts"]) or health + totalAbsorb >= maxHealth) then
        if (totalAbsorb > 0) then
            overAbsorb = true
        end

        if (allIncomingHeal - necroAmount > 0) and Precog.db["CUFPredicts"] then
            totalAbsorb = max(0, maxHealth - (health + allIncomingHeal - necroAmount))
        else
            totalAbsorb = max(0, maxHealth - health)
        end
    end

    if (precogFrame.overAbsorbGlow) then
        if (overAbsorb) and Precog.db["CUFAbsorbs"] then
            precogFrame.overAbsorbGlow:Show()
        else
            precogFrame.overAbsorbGlow:Hide()
        end
    end

    local healthTexture = frame.healthBar:GetStatusBarTexture()

    --Show myIncomingHeal on the health bar.
    local incomingHealsTexture
    if Precog.db["CUFPredicts"] then
        incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame, healthTexture, precogFrame.myHealPrediction, myIncomingHeal - necroAmount)
        --Append otherIncomingHeal on the health bar.
        incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame, incomingHealsTexture, precogFrame.otherHealPrediction, otherIncomingHeal - necroAmount);
    else
        incomingHealsTexture = healthTexture
    end

    --Append absorbs to the correct section of the health bar.
    local appendTexture = incomingHealsTexture

    if Precog.db["CUFAbsorbs"] then
        if necroAmount >= allIncomingHeal then
            appendTexture = healthTexture
        end
        CompactUnitFrameUtil_UpdateFillBar(frame, appendTexture, precogFrame.totalAbsorb, totalAbsorb)
    end

    if Precog.db.CUFNecro then
        local necrobar = precogFrame.NecroAbsorbBar
        if necrobar then
            if allIncomingHeal > 0 then
                necroAmount = max(necroAmount - allIncomingHeal, 0)
            end
            CompactUnitFrameUtil_UpdateFillBar(frame, healthTexture, necrobar, -necroAmount)
        end
    end

    if Precog.db["CUFOvershield"] then
        local absorbBar = precogFrame.totalAbsorb
        if not absorbBar or absorbBar:IsForbidden() then
            return
        end

        local absorbOverlay = precogFrame.totalAbsorbOverlay
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

        local totalAbsorb = Precog.UnitGetTotalAbsorbs(frame.displayedUnit) or 0
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

local function SetupRaidFrames(frame)
    local unit = frame.unit or frame.displayedUnit
    if not frame or not unit or frame:IsForbidden() or string.find(unit, "nameplate") then
        return
    end

    local prefix = frame and frame:GetName()
    if prefix and not _G[prefix .. "PrecogFrame"] then
        local precogFrame = CreateFrame("StatusBar", prefix .. "PrecogFrame", frame)
        precogFrame:SetAllPoints(frame)
        precogFrame:SetFrameLevel(frame:GetFrameLevel())
        precogFrame.myHealPrediction = precogFrame:CreateTexture(prefix .. "MyHealPredictionBar", "ARTWORK", "MyHealPredictionBarTemplate", 1)
        precogFrame.otherHealPrediction = precogFrame:CreateTexture(prefix .. "OtherPredictionBar", "ARTWORK", "OtherHealPredictionBarTemplate", 1)
        precogFrame.totalAbsorb = precogFrame:CreateTexture(prefix .. "TotalAbsorbBar", "BORDER", "TotalAbsorbBarTemplate", 5)
        precogFrame.totalAbsorbOverlay = precogFrame:CreateTexture(prefix .. "TotalAbsorbBarOverlay", "BORDER", "TotalAbsorbBarOverlayTemplate", 6)
        precogFrame.overAbsorbGlow = precogFrame:CreateTexture(prefix .. "OverAbsorbGlow", "ARTWORK", "OverAbsorbGlowTemplate", 2)

        precogFrame.myHealPrediction:ClearAllPoints()
        precogFrame.myHealPrediction:SetColorTexture(1, 1, 1)
        precogFrame.myHealPrediction:SetGradient("VERTICAL", CreateColor(8 / 255, 93 / 255, 72 / 255, 1), CreateColor(11 / 255, 136 / 255, 105 / 255, 1))
        precogFrame.otherHealPrediction:ClearAllPoints()
        precogFrame.otherHealPrediction:SetColorTexture(1, 1, 1)
        precogFrame.otherHealPrediction:SetGradient("VERTICAL", CreateColor(11 / 255, 53 / 255, 43 / 255, 1), CreateColor(21 / 255, 89 / 255, 72 / 255, 1))
        precogFrame.totalAbsorb:ClearAllPoints()
        precogFrame.totalAbsorb:SetTexture("Interface\\RaidFrame\\Shield-Fill")
        precogFrame.totalAbsorb.overlay = precogFrame.totalAbsorbOverlay
        precogFrame.totalAbsorbOverlay:SetTexture("Interface\\RaidFrame\\Shield-Overlay", true, true)    --Tile both vertically and horizontally
        precogFrame.totalAbsorbOverlay:SetAllPoints(precogFrame.totalAbsorb)
        precogFrame.totalAbsorbOverlay.tileSize = 32
        precogFrame.overAbsorbGlow:ClearAllPoints()
        precogFrame.overAbsorbGlow:SetTexture("Interface\\RaidFrame\\Shield-Overshield")
        precogFrame.overAbsorbGlow:SetBlendMode("ADD")
        precogFrame.overAbsorbGlow:SetPoint("BOTTOMLEFT", frame.healthBar, "BOTTOMRIGHT", -7, 0)
        precogFrame.overAbsorbGlow:SetPoint("TOPLEFT", frame.healthBar, "TOPRIGHT", -7, 0)
        precogFrame.overAbsorbGlow:SetWidth(16)
        precogFrame.overAbsorbGlow:Hide()

        local NecroAbsorbBar
        if Precog.db.CUFNecro then
            precogFrame.NecroAbsorbBar = precogFrame:CreateTexture(prefix .. "NecroAbsorbBar", "ARTWORK", "MyHealPredictionBarTemplate", 3)
            precogFrame.NecroAbsorbBar:ClearAllPoints()
            precogFrame.NecroAbsorbBar:SetColorTexture(1, 1, 1)
            precogFrame.NecroAbsorbBar:SetGradient("VERTICAL", CreateColor(240 / 255, 105 / 255, 105 / 255, 0.7), CreateColor(245 / 255, 56 / 255, 56 / 255, 0.9))
        end

        if Precog.db["CUFOvershield"] then
            local absorbBar = precogFrame.totalAbsorb
            if not absorbBar or absorbBar:IsForbidden() then
                return
            end

            local absorbOverlay = precogFrame.totalAbsorbOverlay
            if not absorbOverlay or absorbOverlay:IsForbidden() then
                return
            end

            local healthBar = frame.healthBar
            if not healthBar or healthBar:IsForbidden() then
                return
            end

            absorbOverlay:SetParent(healthBar)
            absorbOverlay:ClearAllPoints()
            absorbOverlay:SetDrawLayer("OVERLAY")

            local absorbGlow = precogFrame.overAbsorbGlow
            if absorbGlow and not absorbGlow:IsForbidden() then
                absorbGlow:ClearAllPoints()
                absorbGlow:SetPoint("TOPLEFT", absorbOverlay, "TOPLEFT", -5, 0)
                absorbGlow:SetPoint("BOTTOMLEFT", absorbOverlay, "BOTTOMLEFT", -5, 0)
                absorbGlow:SetAlpha(0.6)
                absorbGlow:SetDrawLayer("OVERLAY")
            end
        end

        EventRegistry:RegisterCallback("Precognito", function()
            CompactUnitFrame_UpdateHealPrediction(frame)
        end)
    end
end
hooksecurefunc("CompactUnitFrame_SetUnit", SetupRaidFrames)

--- UnitFrame

local MAX_INCOMING_HEAL_OVERFLOW = 1.0;
local function UnitFrameHealPredictionBars_Update(frame)
    if (not frame.myHealPredictionBar and not frame.otherHealPredictionBar and not frame.healAbsorbBars and not frame.totalAbsorbBars) then
        return ;
    end

    local _, maxHealth = frame.healthbar:GetMinMaxValues();
    local health = frame.healthbar:GetValue();
    if (maxHealth <= 0) then
        return ;
    end

    local myIncomingHeal = UnitGetIncomingHeals(frame.unit, "player") or 0;
    local allIncomingHeal = UnitGetIncomingHeals(frame.unit) or 0;
    local totalAbsorb = Precog.UnitGetTotalAbsorbs(frame.unit) or 0;
    local necroAmount = 0

    if frame.necroAbsorbBar and Precog.db.necroTrack then
        necroAmount = Precog.NecroAbsorb(frame.unit) or 0
    end

    --See how far we're going over the health bar and make sure we don't go too far out of the frame.
    if (health + allIncomingHeal > maxHealth * MAX_INCOMING_HEAL_OVERFLOW) then
        allIncomingHeal = maxHealth * MAX_INCOMING_HEAL_OVERFLOW - health;
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
    if (health + allIncomingHeal + totalAbsorb - necroAmount >= maxHealth and Precog.db.healPredict) or (health + totalAbsorb >= maxHealth) then
        if (totalAbsorb > 0) then
            overAbsorb = true
        end

        if ((allIncomingHeal - necroAmount) > 0) and Precog.db.healPredict then
            totalAbsorb = max(0, maxHealth - (health + allIncomingHeal - necroAmount));
        else
            totalAbsorb = max(0, maxHealth - health);
        end
    end

    if (frame.overAbsorbGlow) then
        if (overAbsorb) and Precog.db.absorbTrack then
            if not frame.overAbsorbGlow:IsShown() then
                frame.overAbsorbGlow:Show()
            end
        else
            if frame.overAbsorbGlow:IsShown() then
                frame.overAbsorbGlow:Hide();
            end
        end
    end

    local healthTexture = frame.healthbar:GetStatusBarTexture();

    --Show myIncomingHeal on the health bar.
    local incomingHealTexture;
    if Precog.db.healPredict then
        if (frame.myHealPredictionBar and (frame.myHealPredictionBar.UpdateFillPosition ~= nil)) then
            incomingHealTexture = frame.myHealPredictionBar:UpdateFillPosition(healthTexture, myIncomingHeal - necroAmount);
        end

        local otherHealLeftTexture = (myIncomingHeal > 0) and incomingHealTexture or healthTexture;

        --Append otherIncomingHeal on the health bar
        if (frame.otherHealPredictionBar and (frame.otherHealPredictionBar.UpdateFillPosition ~= nil)) then
            incomingHealTexture = frame.otherHealPredictionBar:UpdateFillPosition(otherHealLeftTexture, otherIncomingHeal - necroAmount, 0);
        end
    else
        incomingHealTexture = healthTexture
    end

    --Append absorbs to the correct section of the health bar.
    local appendTexture = incomingHealTexture or healthTexture;
    local absorbBar = frame.totalAbsorbBars

    if absorbBar and absorbBar.UpdateFillPosition and Precog.db.absorbTrack then
        if necroAmount >= allIncomingHeal then
            appendTexture = healthTexture
        end

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

        local totalAbsorb = Precog.UnitGetTotalAbsorbs(frame.unit) or 0
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

    if Precog.db.necroTrack then
        local necrobar = frame.necroAbsorbBar
        if necrobar then
            if allIncomingHeal > 0 then
                necroAmount = max(necroAmount - allIncomingHeal, 0)
            end
            necrobar:UpdateFillPosition(healthTexture, -necroAmount)
        end
    end

end

local function UnitFrameHealthBar_OnUpdate_New(self)
    if (not self.disconnected and not self.lockValues) then
        local currValue = UnitHealth(self.unit)
        local animatedLossBar = self.AnimatedLossBar
        if (currValue ~= self.currValue) then
            if (not self.ignoreNoUnit or UnitGUID(self.unit)) then
                if animatedLossBar then
                    animatedLossBar:UpdateHealth(currValue, self.currValue)
                end
                self:SetValue(currValue)
                self.currValue = currValue
                TextStatusBar_UpdateTextString(self)
                UnitFrameHealPredictionBars_Update(self:GetParent())
            end
        end
        if animatedLossBar then
            animatedLossBar:UpdateLossAnimation(currValue)
        end
    end
end

local function UnitFrameManaBar_UpdateType(manaBar)
    if (not manaBar) or not whitelist[manaBar:GetParent()] then
        return
    end

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

function UnitFrameManaCostPredictionBars_Update(frame, isStarting, startTime, endTime, spellID)
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

local function UnitFrame_Initialize(self, totalAbsorbBars, overAbsorbGlow, myManaCostPredictionBar, NecroAbsorbBar)

    self.totalAbsorbBars = totalAbsorbBars
    self.overAbsorbGlow = overAbsorbGlow
    self.myManaCostPredictionBar = myManaCostPredictionBar
    self.necroAbsorbBar = NecroAbsorbBar

    if self.necroAbsorbBar then
        self.necroAbsorbBar:Hide()
    end

    if not Precog.db.healPredict then
        self.myHealPredictionBar:SetAlpha(0)
        self.otherHealPredictionBar:SetAlpha(0)
    end

    if (self.myManaCostPredictionBar) and self.unit == "player" then
        self:RegisterUnitEvent("UNIT_SPELLCAST_START", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", self.unit)
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", self.unit)
        hooksecurefunc("UnitFrameManaBar_UpdateType", UnitFrameManaBar_UpdateType)
    end

    if (self.overAbsorbGlow) then
        self.overAbsorbGlow:ClearAllPoints();
        self.overAbsorbGlow:SetPoint("TOPLEFT", self.healthbar, "TOPRIGHT", -7, 0);
        self.overAbsorbGlow:SetPoint("BOTTOMLEFT", self.healthbar, "BOTTOMRIGHT", -7, 0);
    end

    self.healthbar:SetScript("OnUpdate", UnitFrameHealthBar_OnUpdate_New)

    if Precog.db.absorbTrack then
        EventRegistry:RegisterCallback("Precognito", function(arg1, arg2)
            if UnitIsUnit(arg2, self.unit) or arg2 == UnitGUID(self.unit) then
                UnitFrameHealPredictionBars_Update(self)
            end
        end)
    end

    if (self.unit == "player") then
        if Precog.db.animHealth then
            self.PlayerFrameHealthBarAnimatedHealth = Mixin(CreateFrame("StatusBar", nil, self), AnimatedHealthLossMixin)
            self.PlayerFrameHealthBarAnimatedHealth:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            self.PlayerFrameHealthBarAnimatedHealth:SetFrameLevel(self.healthbar:GetFrameLevel() - 1)
            self.PlayerFrameHealthBarAnimatedHealth:OnLoad()
            self.PlayerFrameHealthBarAnimatedHealth:SetUnitHealthBar("player", self.healthbar)
            self.PlayerFrameHealthBarAnimatedHealth:Hide()
            function self.PlayerFrameHealthBarAnimatedHealth:UpdateLossAnimation(currentHealth)
                local totalAbsorb = Precog.UnitGetTotalAbsorbs(self.unit) or 0
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
    end

    UnitFrameHealthBar_Update(self.healthbar, self.unit)
    UnitFrameManaBar_Update(self.manabar, self.unit)
    UnitFrameHealPredictionBars_Update(self)
end

local function OnInitialize(self)
    local prefix = self:GetName()
    local healthbar = self.healthBar or self.HealthBar

    local TotalAbsorbBar = CreateFrame("StatusBar", "$parentTotalAbsorbBars", healthbar, "TotalAbsorbBarTemplate")
    TotalAbsorbBar:SetFrameLevel(healthbar:GetFrameLevel() + 1)
    TotalAbsorbBar.FillMask:SetTexture("Interface\\TargetingFrame\\UI-StatusBar", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    TotalAbsorbBar.fillTexture = "Interface\\RaidFrame\\Shield-Fill"
    TotalAbsorbBar.Fill:SetTexture(TotalAbsorbBar.fillTexture)
    TotalAbsorbBar.fillColor = CreateColor(1.000, 1.000, 1.000, 1.000)
    TotalAbsorbBar.Fill:SetVertexColor(TotalAbsorbBar.fillColor:GetRGBA())

    if TotalAbsorbBar.fillOverlays then
        for _, overlay in ipairs(TotalAbsorbBar.fillOverlays) do
            overlay:SetDrawLayer("ARTWORK", 3)
        end
    end

    local attachFrame = prefix ~= "PlayerFrame" and self.textureFrame or select(2, PlayerFrameTexture:GetPoint())
    local OverAbsorbGlow = attachFrame:CreateTexture("$parentOverAbsorbGlow", "OVERLAY", "OverAbsorbGlowTemplate", 5)

    local ManaPredictionBar
    if self == PlayerFrame then
        ManaPredictionBar = CreateFrame("StatusBar", "$parentManaCostPredictionBar", PlayerFrameManaBar, "ManaCostPredictionBarTemplate")
        ManaPredictionBar:SetFrameLevel(self.manabar:GetFrameLevel() + 1)
        ManaPredictionBar.fillTexture = "Interface\\TargetingFrame\\UI-StatusBar"
        ManaPredictionBar.Fill:SetTexture(ManaPredictionBar.fillTexture)
        ManaPredictionBar.FillMask:SetTexture(ManaPredictionBar.fillTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ManaPredictionBar.fillColor = CreateColor(0, 0.447, 1.000, 1.000)
        ManaPredictionBar.Fill:SetVertexColor(ManaPredictionBar.fillColor:GetRGBA())
    end

    local NecroAbsorbBar
    if Precog.db.necroTrack then
        NecroAbsorbBar = CreateFrame("StatusBar", "$parentTotalAbsorbBar", healthbar, "PlayerFrameBarSegmentTemplate, MyHealPredictionBarTemplate")
        NecroAbsorbBar:SetFrameLevel(healthbar:GetFrameLevel() + 3)
        NecroAbsorbBar.fillTexture = "Interface\\TargetingFrame\\UI-StatusBar"
        NecroAbsorbBar.FillMask:SetTexture(NecroAbsorbBar.fillTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        NecroAbsorbBar.Fill:SetTexture(NecroAbsorbBar.fillTexture)
        NecroAbsorbBar.FillMask:SetDrawLayer("OVERLAY", 7)
        NecroAbsorbBar.fillColor = CreateColor(240 / 255, 105 / 255, 105 / 255, 1)
        --NecroAbsorbBar.fillColor = CreateColor(144/255, 77/255, 232/255, 1)
        NecroAbsorbBar.Fill:SetVertexColor(NecroAbsorbBar.fillColor:GetRGBA())
    end

    UnitFrame_Initialize(self, TotalAbsorbBar, OverAbsorbGlow, ManaPredictionBar, NecroAbsorbBar)
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

local options = {
    CUFPredicts = { "Raidframe Incoming Heals", true },
    CUFAbsorbs = { "Raidframe Absorbs", true },
    CUFOvershield = { "Raidframe Overshield", false },
    CUFNecro = { "Raidframe Necrotic Strike Absorbs", false },
    healPredict = { "UnitFrame Incoming Heals", true },
    absorbTrack = { "UnitFrame Absorbs", true },
    necroTrack = { "UnitFrame Necrotic Strike Absorbs", false },
    animMana = { "PlayerFrame Mana-cost Prediction", true },
    animHealth = { "PlayerFrame Animated Health", false },
    Feedback = { "PlayerFrame Animated Full Power", true },
    Overshield = { "UnitFrame Overshield", false },
}

local displayOrder = {
    "CUFPredicts",
    "CUFAbsorbs",
    "CUFOvershield",
    "CUFNecro",
    "healPredict",
    "absorbTrack",
    "Overshield",
    "necroTrack",
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
settingsFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
settingsFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
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

        local panel = CreateFrame("Frame", nil, InterfaceOptionsPanelContainer)
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
    elseif event == "PLAYER_LOGOUT" then
        PrecognitoDB = Precog.db
    elseif event == "PLAYER_LOGIN" then

        for v in pairs(whitelist) do
            OnInitialize(v)
        end

        -- #1
        hooksecurefunc("UnitFrame_Update", function(self)
            if not whitelist[self] then
                return
            end

            if Precog.db.Overshield then
                local absorbBar = self.totalAbsorbBars
                if not absorbBar or absorbBar:IsForbidden() then
                    return
                end

                local absorbOverlay = self.totalAbsorbBars.TiledFillOverlay
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

        -- #2
        if Precog.db.animMana or Precog.db.Feedback then
            hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar, unit)
                if not statusbar or not whitelist[statusbar:GetParent()] then
                    return
                end
                UnitFrameHealPredictionBars_Update(statusbar:GetParent())
            end)
        end

        -- #3
        hooksecurefunc("UnitFrameHealPredictionBars_Update", UnitFrameHealPredictionBars_Update)

        -- #4
        hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", CompactUnitFrame_UpdateHealPrediction)
    elseif event == "PLAYER_TARGET_CHANGED" then
        UnitFrameHealPredictionBars_Update(TargetFrame)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        UnitFrameHealPredictionBars_Update(FocusFrame)
    end
end)