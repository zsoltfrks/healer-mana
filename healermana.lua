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

-- Load saved position or use default
local function LoadPosition()
    if HM_Position then
        anchor:SetPoint(HM_Position.point, UIParent, HM_Position.point, HM_Position.x, HM_Position.y)
    else
        anchor:SetPoint(defaultPosition.point, UIParent, defaultPosition.point, defaultPosition.x, defaultPosition.y)
    end
end

--LoadPosition()

-- isHealer function
local function isHealer(unit)
    return UnitGroupRolesAssigned(unit) == "HEALER"
end

-- isDrinking function
-- TODO: check current foods/drinks that healers use to restore mana, and check if the unit is currently consuming one of those items
local function isDrinking(unit)
    return true
end