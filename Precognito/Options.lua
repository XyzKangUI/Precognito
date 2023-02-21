Precognito = LibStub("AceAddon-3.0"):NewAddon("Precognito")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local function getOption(info, value)
    if value then
        return Precognito.db.profile[info.arg][value]
    else
        return Precognito.db.profile[info.arg]
    end
end

local function setOption(info, value)
    Precognito.db.profile[info.arg] = value
end

Precognito.options = {
    type = "group",
    name = "Precognito",
    get = getOption,
    set = setOption,
    args = {
        tab1 = {
            type = "group",
            name = "RaidFrame Settings",
            args = {
                CUFPredicts = {
                    order = 1,
                    name = "Heal Prediction",
                    desc = "Predict direct incoming heals",
                    type = "toggle",
                    arg = "CUFPredict",
                },
                CUFAbsorbs = {
                    order = 2,
                    name = "Shield Tracker",
                    desc = "Tracks shield absorbs",
                    type = "toggle",
                    arg = "CUFAbsorb",
                },
            },
        },
        tab2 = {
            type = "group",
            name = "UnitFrame Settings",
            args = {
                animHealth = {
                    order = 5,
                    name = "Instant Health Updates",
                    desc = "Updates health animation more frequently",
                    type = "toggle",
                    arg = "animHealth",
                },
                animMana = {
                    order = 1,
                    name = "Animate Power Cost",
                    desc = "Displays cost of spells when casting",
                    type = "toggle",
                    arg = "animMana",
                },
                healPredict = {
                    order = 3,
                    name = "Heal Prediction",
                    desc = "Predict direct incoming heals",
                    type = "toggle",
                    arg = "healPredict",
                },
                absorbTrack = {
                    order = 4,
                    name = "Shield Tracker",
                    desc = "Tracks shield absorbs",
                    type = "toggle",
                    arg = "absorbTrack",
                },
                Feedback = {
                    order = 2,
                    name = "Animate Full Power",
                    desc = "Animate rage/energy when you reach max capacity in combat. Requires 'Animate Power Cost' to be enabled",
                    type = "toggle",
                    arg = "FeedBack",
                },
            },
        },
        tab3 = {
            type = "group",
            name = "Global Settings",
            args = {
                ChatMSG = {
                    order = 1,
                    name = "Sync Data",
                    desc = "Enabling this will share gear/talent stats with group members to improve absorb calculations. Disable this if you experience any lag",
                    type = "toggle",
                    arg = "syncMsg",
                },
            },
        },
    },
}

Precognito.defaults = {
    profile = {
        animHealth = true,
        animMana = true,
        healPredict = true,
        absorbTrack = true,
        CUFPredict = true,
        CUFAbsorb = true,
        syncMsg = false,
        FeedBack = true
    },
}

function Precognito:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("PrecognitoDB", self.defaults, true)

    AceConfig:RegisterOptionsTable("Precognito", self.options)
    AceConfigDialog:AddToBlizOptions("Precognito", "Precognito")

    if self.db.profile.CUFPredict or self.db.profile.CUFAbsorb then
        self:CUFInit()
    end

    if self.db.profile.animHealth or self.db.profile.animMana or self.db.profile.healPredict or
            self.db.profile.absorbTrack then
        self:UFInit()
    end
end