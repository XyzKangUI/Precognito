local addonName, Precog = ...
local whitelist = {
    [PlayerFrame] = true,
    [TargetFrame] = true,
    [FocusFrame] = true
}
local UnitIsUnit, UnitGUID = UnitIsUnit, UnitGUID

--- Raid Frames
local MAX_INCOMING_HEAL_OVERFLOW = 1.05
hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
    local unit = frame.displayedUnit or frame.unit
    if not frame or not unit or string.find(unit, "nameplate") or not frame:IsVisible() then
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
    local totalAbsorb = 0

    local myCurrentHealAbsorb = 0
    if (precogFrame.myHealAbsorb) then
        totalAbsorb = Precog.UnitGetTotalAbsorbs and Precog.UnitGetTotalAbsorbs(frame.unit) or 0
        myCurrentHealAbsorb = 0

        --We don't fill outside the health bar with healAbsorbs.  Instead, an overHealAbsorbGlow is shown.
        if (health < myCurrentHealAbsorb) then
            precogFrame.overHealAbsorbGlow:Show()
            myCurrentHealAbsorb = health
        else
            precogFrame.overHealAbsorbGlow:Hide()
        end
    end

    --We don't fill outside the health bar with healAbsorbs.  Instead, an overHealAbsorbGlow is shown.
    local myCurrentHealAbsorb = 0
    if (health < myCurrentHealAbsorb) then
        precogFrame.overHealAbsorbGlow:Show()
        myCurrentHealAbsorb = health
    else
        precogFrame.overHealAbsorbGlow:Hide()
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
    if ((health - myCurrentHealAbsorb + allIncomingHeal + totalAbsorb >= maxHealth and Precog.db["CUFPredicts"]) or health + totalAbsorb >= maxHealth) then
        if (totalAbsorb > 0) then
            overAbsorb = true
        end

        if (allIncomingHeal > myCurrentHealAbsorb) and Precog.db["CUFPredicts"] then
            totalAbsorb = max(0, maxHealth - (health - myCurrentHealAbsorb + allIncomingHeal))
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

    local myCurrentHealAbsorbPercent = myCurrentHealAbsorb / maxHealth

    local healAbsorbTexture = nil

    --If allIncomingHeal is greater than myCurrentHealAbsorb, then the current
    --heal absorb will be completely overlayed by the incoming heals so we don't show it.
    if (myCurrentHealAbsorb > allIncomingHeal) then
        local shownHealAbsorb = myCurrentHealAbsorb - allIncomingHeal
        local shownHealAbsorbPercent = shownHealAbsorb / maxHealth
        healAbsorbTexture = CompactUnitFrameUtil_UpdateFillBar(frame, healthTexture, precogFrame.myHealAbsorb, shownHealAbsorb, -shownHealAbsorbPercent)

        --If there are incoming heals the left shadow would be overlayed by the incoming heals
        --so it isn't shown.
        if (allIncomingHeal > 0) then
            precogFrame.myHealAbsorbLeftShadow:Hide()
        else
            precogFrame.myHealAbsorbLeftShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPLEFT", 0, 0)
            precogFrame.myHealAbsorbLeftShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMLEFT", 0, 0)
            precogFrame.myHealAbsorbLeftShadow:Show()
        end

        -- The right shadow is only shown if there are absorbs on the health bar.
        if (totalAbsorb > 0) then
            precogFrame.myHealAbsorbRightShadow:SetPoint("TOPLEFT", healAbsorbTexture, "TOPRIGHT", -8, 0)
            precogFrame.myHealAbsorbRightShadow:SetPoint("BOTTOMLEFT", healAbsorbTexture, "BOTTOMRIGHT", -8, 0)
            precogFrame.myHealAbsorbRightShadow:Show()
        else
            precogFrame.myHealAbsorbRightShadow:Hide()
        end
    else
        precogFrame.myHealAbsorb:Hide()
        precogFrame.myHealAbsorbRightShadow:Hide()
        precogFrame.myHealAbsorbLeftShadow:Hide()
    end

    --Show myIncomingHeal on the health bar.
    local incomingHealsTexture
    if Precog.db["CUFPredicts"] then
        incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame, healthTexture, precogFrame.myHealPrediction, myIncomingHeal, -myCurrentHealAbsorbPercent)
        --Append otherIncomingHeal on the health bar.
        incomingHealsTexture = CompactUnitFrameUtil_UpdateFillBar(frame, incomingHealsTexture, precogFrame.otherHealPrediction, otherIncomingHeal);
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
    if Precog.db["CUFAbsorbs"] then
        CompactUnitFrameUtil_UpdateFillBar(frame, appendTexture, precogFrame.totalAbsorb, totalAbsorb)
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
end)

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
        precogFrame.myHealPrediction = precogFrame:CreateTexture(prefix .. "MyHealPredictionBar", "BORDER", "MyHealPredictionBarTemplate", 5)
        precogFrame.otherHealPrediction = precogFrame:CreateTexture(prefix .. "OtherPredictionBar", "BORDER", "OtherHealPredictionBarTemplate", 5)
        precogFrame.myHealAbsorb = precogFrame:CreateTexture(prefix .. "HealAbsorbBar", "ARTWORK", "HealAbsorbBarTemplate", 1)
        precogFrame.myHealAbsorbLeftShadow = precogFrame:CreateTexture(prefix .. "HealAbsorbBarLeftShadow", "ARTWORK", "HealAbsorbBarLeftShadowTemplate", 1)
        precogFrame.myHealAbsorbRightShadow = precogFrame:CreateTexture(prefix .. "HealAbsorbBarRightShadow", "ARTWORK", "HealAbsorbBarRightShadowTemplate", 1)
        precogFrame.totalAbsorb = precogFrame:CreateTexture(prefix .. "TotalAbsorbBar", "BORDER", "TotalAbsorbBarTemplate", 5)
        precogFrame.totalAbsorbOverlay = precogFrame:CreateTexture(prefix .. "TotalAbsorbBarOverlay", "BORDER", "TotalAbsorbBarOverlayTemplate", 6)
        precogFrame.overAbsorbGlow = precogFrame:CreateTexture(prefix .. "OverAbsorbGlow", "ARTWORK", "OverAbsorbGlowTemplate", 2)
        precogFrame.overHealAbsorbGlow = precogFrame:CreateTexture(prefix .. "OverHealAbsorbGlow", "ARTWORK", "OverHealAbsorbGlowTemplate", 2)

        precogFrame.myHealPrediction:ClearAllPoints()
        precogFrame.myHealPrediction:SetColorTexture(1, 1, 1)
        precogFrame.myHealPrediction:SetGradient("VERTICAL", CreateColor(8 / 255, 93 / 255, 72 / 255, 1), CreateColor(11 / 255, 136 / 255, 105 / 255, 1))
        precogFrame.myHealAbsorb:ClearAllPoints()
        precogFrame.myHealAbsorb:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true)
        precogFrame.myHealAbsorb:Hide()
        precogFrame.myHealAbsorbLeftShadow:ClearAllPoints()
        precogFrame.myHealAbsorbLeftShadow:Hide()
        precogFrame.myHealAbsorbRightShadow:ClearAllPoints()
        precogFrame.myHealAbsorbRightShadow:Hide()
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
        precogFrame.overHealAbsorbGlow:ClearAllPoints()
        precogFrame.overHealAbsorbGlow:SetTexture("Interface\\RaidFrame\\Absorb-Overabsorb")
        precogFrame.overHealAbsorbGlow:SetBlendMode("ADD")
        precogFrame.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMLEFT", 7, 0)
        precogFrame.overHealAbsorbGlow:SetPoint("TOPRIGHT", frame.healthBar, "TOPLEFT", 7, 0)
        precogFrame.overHealAbsorbGlow:SetWidth(16)
        precogFrame.overHealAbsorbGlow:Hide()

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

local function TotalShim(unit, ...)
    return 0
end

setfenv(UnitFrameHealPredictionBars_Update, setmetatable({}, {
    __index = function(t, k)
        if k == "UnitGetTotalAbsorbs" then
            if Precog.db.absorbTrack then
                return Precog.UnitGetTotalAbsorbs
            else
                return TotalShim
            end
        elseif k == "UnitGetTotalHealAbsorbs" then
            return TotalShim
        elseif k == "UnitGetIncomingHeals" and not Precog.db.healPredict then
            return TotalShim
        else
            return _G[k]
        end
    end
}))

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

local function UnitFrame_Initialize(self, totalAbsorbBar, overAbsorbGlow, overHealAbsorbGlow, healAbsorbBar, myManaCostPredictionBar)

    self.totalAbsorbBar = totalAbsorbBar
    self.overAbsorbGlow = overAbsorbGlow
    self.overHealAbsorbGlow = overHealAbsorbGlow
    self.healAbsorbBar = healAbsorbBar
    self.myManaCostPredictionBar = myManaCostPredictionBar

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
    if (self.overHealAbsorbGlow) then
        self.overHealAbsorbGlow:ClearAllPoints();
        self.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", self.healthbar, "BOTTOMLEFT", 7, 0);
        self.overHealAbsorbGlow:SetPoint("TOPRIGHT", self.healthbar, "TOPLEFT", 7, 0);
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

    local HealAbsorbBar = CreateFrame("StatusBar", "$parentHealAbsorbBar", healthbar, "PlayerFrameBarSegmentTemplate, HealAbsorbBarTemplate")
    HealAbsorbBar:SetFrameLevel(healthbar:GetFrameLevel() + 1)
    HealAbsorbBar.FillMask:SetTexture("Interface\\TargetingFrame\\UI-StatusBar", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    HealAbsorbBar.fillColor = CreateColor(0.424, 0.651, 0.051, 1.000)
    HealAbsorbBar.Fill:SetVertexColor(HealAbsorbBar.fillColor:GetRGBA())
    HealAbsorbBar.Fill:SetDrawLayer("ARTWORK", 1)

    if HealAbsorbBar.fillOverlays then
        for _, overlay in ipairs(HealAbsorbBar.fillOverlays) do
            overlay:SetDrawLayer("ARTWORK", 3)
        end
    end

    local TotalAbsorbBar = CreateFrame("StatusBar", "$parentTotalAbsorbBar", healthbar, "TotalAbsorbBarTemplate")
    TotalAbsorbBar:SetFrameLevel(healthbar:GetFrameLevel() + 1)
    TotalAbsorbBar.FillMask:SetTexture("Interface\\TargetingFrame\\UI-StatusBar", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    TotalAbsorbBar.fillColor = CreateColor(1.000, 1.000, 1.000, 1.000)
    TotalAbsorbBar.Fill:SetVertexColor(TotalAbsorbBar.fillColor:GetRGBA())
    TotalAbsorbBar.fillTexture = "Interface\\RaidFrame\\Shield-Fill"
    TotalAbsorbBar.Fill:SetTexture(TotalAbsorbBar.fillTexture)

    if TotalAbsorbBar.fillOverlays then
        for _, overlay in ipairs(TotalAbsorbBar.fillOverlays) do
            overlay:SetDrawLayer("ARTWORK", 3)
        end
    end

    local attachFrame = prefix ~= "PlayerFrame" and self.textureFrame or select(2, PlayerFrameTexture:GetPoint())
    local OverAbsorbGlow = attachFrame:CreateTexture("$parentOverAbsorbGlow", "OVERLAY", "OverAbsorbGlowTemplate", 5)
    local OverHealAbsorbGlow = attachFrame:CreateTexture("$parentOverHealAbsorbGlow", "OVERLAY", "OverHealAbsorbGlowTemplate", 5)

    --- Temp fix
    if healthbar and healthbar.MyHealPredictionBar then
        healthbar.MyHealPredictionBar.FillMask:SetTexture("Interface\\TargetingFrame\\UI-StatusBar", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    if healthbar and healthbar.OtherHealPredictionBar then
        healthbar.OtherHealPredictionBar.FillMask:SetTexture("Interface\\TargetingFrame\\UI-StatusBar", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    --- end

    local ManaPredictionBar
    if self == PlayerFrame then
        ManaPredictionBar = CreateFrame("StatusBar", "$parentManaCostPredictionBar", PlayerFrameManaBar, "ManaCostPredictionBarTemplate")
        ManaPredictionBar:SetFrameLevel(self.manabar:GetFrameLevel() + 1)
        ManaPredictionBar.fillTexture = "Interface\\TargetingFrame\\UI-StatusBar"
        ManaPredictionBar.Fill:SetTexture(ManaPredictionBar.fillTexture)
        ManaPredictionBar.FillMask:SetTexture("Interface\\TargetingFrame\\UI-StatusBar", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ManaPredictionBar.fillColor = CreateColor(0, 0.447, 1.000, 1.000)
        ManaPredictionBar.Fill:SetVertexColor(ManaPredictionBar.fillColor:GetRGBA())
    end

    UnitFrame_Initialize(self, TotalAbsorbBar, OverAbsorbGlow, OverHealAbsorbGlow, HealAbsorbBar, ManaPredictionBar)
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
    CUFPredicts = { "Raid Frame Incoming Heals", true },
    CUFAbsorbs = { "Raid Frame Absorbs", true },
    CUFOvershield = { "Raid Frame Overshield", false },
    healPredict = { "UnitFrame Incoming Heals", true },
    absorbTrack = { "UnitFrame Absorbs", true },
    animHealth = { "Player Animated Health", false },
    animMana = { "Player Mana Cost Prediction", true },
    Feedback = { "Player Power Animation", true },
    Overshield = { "UnitFrame Overshield", false },
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

        for option, value in pairs(options) do
            if PrecognitoDB[option] == nil then
                PrecognitoDB[option] = value[2]
            end
        end

        Precog.db = PrecognitoDB

        local panel = CreateFrame("Frame", nil, InterfaceOptionsPanelContainer)
        panel.name = "|cff33ff99Precognito|r"
        Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, panel.name))

        local yOffset = -10
        for key, option in pairs(options) do
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

        -- #2
        if Precog.db.animMana or Precog.db.Feedback then
            hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar, unit)
                if not statusbar or not whitelist[statusbar:GetParent()] then
                    return
                end
                UnitFrameHealPredictionBars_Update(statusbar:GetParent())
            end)
        end

        if Precog.db.Overshield then
            hooksecurefunc("UnitFrameHealPredictionBars_Update", function(frame)
                local absorbBar = frame.totalAbsorbBar
                if not absorbBar or absorbBar:IsForbidden() then
                    return
                end

                local absorbOverlay = frame.totalAbsorbBar.TiledFillOverlay
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
                        absorbOverlay:SetParent(absorbBar)
                        absorbOverlay:SetPoint("TOPRIGHT", absorbBar.FillMask, "TOPRIGHT", 0, 0)
                        absorbOverlay:SetPoint("BOTTOMRIGHT", absorbBar.FillMask, "BOTTOMRIGHT", 0, 0)
                    else
                        absorbOverlay:SetParent(healthBar)
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
            end)
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        UnitFrameHealPredictionBars_Update(TargetFrame)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        UnitFrameHealPredictionBars_Update(FocusFrame)
    end
end)