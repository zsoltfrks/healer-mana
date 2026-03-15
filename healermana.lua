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
anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)

anchor:SetSize(220, 40)
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
    f:SetSize(220, 64)

    if index == 1 then
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    else
        f:SetPoint("TOPLEFT", frames[index - 1].frame, "BOTTOMLEFT", 0, -4)
    end

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(56, 56)
    icon:SetPoint("LEFT", f, "LEFT", 0, 0)

    local name = f:CreateFontString(nil, "OVERLAY")
    name:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
    name:SetTextColor(1, 1, 1)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)

    local mana = f:CreateFontString(nil, "OVERLAY")
    mana:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
    mana:SetTextColor(1, 1, 1)
    mana:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)

    frames[index] = {
        frame = f,
        icon = icon,
        name = name,
        mana = mana,
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

local function updateFrames()

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
        if isDrinking(unit) then
            f.icon:SetTexture(FOOD_ICON)
        else
            local coords = CLASS_ICON_TCOORDS[class]

            f.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            f.icon:SetTexCoord(unpack(coords))
        end

        -- TEXT
        f.name:SetText(name)
        f.mana:SetText(percent.."%")

        -- RANGE FADE
        if UnitInRange(unit) == false then
            f.frame:SetAlpha(0.6)
        else
            f.frame:SetAlpha(1)
        end

        f.frame:Show()
    end
end

-- Event handlers
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        healers = {}
        local numGroupMembers = GetNumGroupMembers()

        for i = 1, numGroupMembers do
            local unit = "party" .. i
            if UnitExists(unit) and isHealer(unit) then
                table.insert(healers, unit)
            end
        end

        loadPosition()
        updateHealers()
        updateFrames()

    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_AURA" then
        local unit = ...
        if isHealer(unit) then
            updateFrames()
        end
    end
end)

-- Register events
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
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
     print("test triggered")

    wipe(healers)

    anchor:Show()
    anchor:SetAlpha(1)

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

    -- Full alpha
    f.frame:SetAlpha(1)

    f.frame:Show()

    anchor:Show()
end

SLASH_HEALERMANATEST1 = "/hmtest"

SlashCmdList["HEALERMANATEST"] = function()
    testFrame()
end