local addon = CreateFrame("Frame")
local frames = {}
local healers = {}

-- Default position
local defaultPosition = {
    point = "CENTER",
    x = 0,
    y = 200
}

-- Anchoring function
local anchor = CreateFrame("Frame", "HM_Anchor", UIParent)

anchor:SetSize(200, 40)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")

anchor:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()

    local point, _, _, x, y = self:GetPoint()

    HM_Position = {
        point = point,
        x = x,
        y = y
    }

end)

local background = anchor:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0, 0.8, 1, 0.3)

local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
text:SetPoint("CENTER")
text:SetText("HealerMana Anchor")

-- loadPosition function
local function loadPosition()
    if HM_Position then
        anchor:SetPoint(HM_Position.point, UIParent, HM_Position.point, HM_Position.x, HM_Position.y)
    else
        anchor:SetPoint(defaultPosition.point, UIParent, defaultPosition.point, defaultPosition.x, defaultPosition.y)
    end
end

-- createHealerFrame function
local function createHealerFrame(index)
    local f = CreateFrame("Frame", "HM_Healer"..index, anchor)
    f:SetSize(200, 40)

    local icon = f:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", 5, 0)

    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", icon, "RIGHT", 5, 0)

    local mana = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mana:SetPoint("RIGHT", -5, 0)

    local stack = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stack:SetPoint("TOPRIGHT", -5, -5)

    frames[index] = {
        frame = f,
        icon = icon,
        name = name,
        mana = mana,
        stack = stack
    }
end

-- isHealer function
local function isHealer(unit)
    return UnitGroupRolesAssigned(unit) == "HEALER"
end

-- isDrinking function
-- TODO: check unit wether it's drinking or not, might be fked since latest addon update
-- TODO: need to test this
-- https://www.wowhead.com/classic/spell=22734/drink
local function isDrinking(unit)
    local spellID = UnitCastingInfo(unit)
    if spellID and spellID == 22734 and isHealer(unit) then
        return true
    end
    return false
end

-- updateHealers function
local function updateHealers()
    local numGroupMembers = GetNumGroupMembers()
    local healerCount = 0

    for i = 1, numGroupMembers do
        local unit = "party" .. i
        if UnitExists(unit) and isHealer(unit) then
            healerCount = healerCount + 1
        end
    end

    if healerCount > 0 then
        anchor:Show()
    else
        anchor:Hide()
    end
end

-- Update frames
local FOOD_ICON = "Interface\\Icons\\INV_Drink_18"

local function UpdateFrames()

    for i,unit in ipairs(healers) do

        if not frames[i] then
            createHealerFrame(i)
        end

        local f = frames[i]

        local name = UnitName(unit)
        local class = select(2,UnitClass(unit))

        local mana = UnitPower(unit,0)
        local max = UnitPowerMax(unit,0)

        local percent = 0
        if max > 0 then
            percent = math.floor(mana/max*100)
        end

        -- ICON
        if IsDrinking(unit) then
            f.icon:SetTexture(FOOD_ICON)
        else
            local coords = CLASS_ICON_TCOORDS[class]

            f.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            f.icon:SetTexCoord(unpack(coords))
        end

        -- TEXT
        f.name:SetText(name)
        f.mana:SetText(percent.."%")
        f.stack:SetText(i)

        -- RANGE FADE
        if UnitInRange(unit) == false then
            f:SetAlpha(0.6)
        else
            f:SetAlpha(1)
        end

        f:Show()
    end
end

-- Event handlers
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "GROUP_ROSTER_UPDATE" then
        healers = {}
        local numGroupMembers = GetNumGroupMembers()

        for i = 1, numGroupMembers do
            local unit = "party" .. i
            if UnitExists(unit) and isHealer(unit) then
                table.insert(healers, unit)
            end
        end

        updateHealers()
        UpdateFrames()
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_AURA" then
        local unit = ...
        if isHealer(unit) then
            UpdateFrames()
        end
    end
end)

-- Register events
addon:RegisterEvent("GROUP_ROSTER_UPDATE")
addon:RegisterEvent("UNIT_POWER_UPDATE")
addon:RegisterEvent("UNIT_MAXPOWER")
addon:RegisterEvent("UNIT_AURA")

-- Command to toggle anchor
SLASH_HEALERMANA1 = "/hm"
SlashCmdList["HEALERMANA"] = function()
    if anchor:IsShown() then
        anchor:Hide()
    else
        anchor:Show()
    end
end

-- Test function and command to print healer info
local TEST_ICON = "Interface\\Icons\\spell_monk_mistweaver_spec"

local function testFrame()
    wipe(healers)

    local playerName = UnitName("player") or "Testhealer"

    healers[1] = "player"

    if not frames[1] then
        createHealerFrame(1)
    end

    local f = frames[1]

    -- Icon
    f.icon:SetTexture("Interface\\Icons\\spell_monk_mistweaver_spec")
    f.icon:SetTexCoord(0,1,0,1)

    -- Text
    f.name:SetText(playerName)
    f.mana:SetText("100%")
    f.stack:SetText("1")

    -- Full alpha
    f.frame:SetAlpha(1)

    f.frame:Show()

    anchor:Show()
end

SLASH_HEALERMANATEST1 = "/hmtest"

SlashCmdList["HEALERMANATEST"] = function()
    testFrame()
end