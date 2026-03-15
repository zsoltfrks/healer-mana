local addon = CreateFrame("Frame")
local frames = {}
local healers = {}

local HM_DEFAULTS = {
    font     = "Fonts\\FRIZQT__.TTF",
    outline  = "THICKOUTLINE",
    scale    = 1.0,
    nameSize = 30,
    nameX    = 8,
    nameY    = 0,
    manaSize = 40,
    manaX    = 8,
    manaY    = 0,
}

local inEditMode = false
local setEditMode  -- forward declared; depends on updateHealers defined later

-- Default position
local defaultPosition = {
    point = "CENTER",
    x = 0,
    y = 200
}

-- Anchor — invisible parent frame for healer rows; becomes a drag handle in edit mode
local anchor = CreateFrame("Frame", "HM_Anchor", UIParent)
anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
anchor:SetSize(220, 36)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    HM_Position = { point = point, x = x, y = y }
end)

-- Background — only shown in edit mode
local anchorBg = anchor:CreateTexture(nil, "BACKGROUND")
anchorBg:SetAllPoints()
anchorBg:SetColorTexture(0, 0, 0, 0.6)
anchorBg:Hide()

-- Hint text — only shown in edit mode
local anchorText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchorText:SetPoint("LEFT", 10, 0)
anchorText:SetText("HealerMana  ·  drag to reposition")
anchorText:SetTextColor(0.75, 0.75, 0.75)
anchorText:Hide()

-- Lock button — clicking this exits edit mode and saves position
local lockBtn = CreateFrame("Button", nil, anchor)
lockBtn:SetSize(24, 24)
lockBtn:SetPoint("RIGHT", anchor, "RIGHT", -6, 0)
lockBtn:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
lockBtn:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Down")
lockBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
lockBtn:Hide()

lockBtn:SetScript("OnClick", function() setEditMode(false) end)

-- loadPosition function
local function loadPosition()
    anchor:ClearAllPoints()
    if HM_Position then
        anchor:SetPoint(HM_Position.point, UIParent, HM_Position.point, HM_Position.x, HM_Position.y)
    else
        anchor:SetPoint(defaultPosition.point, UIParent, defaultPosition.point, defaultPosition.x, defaultPosition.y)
    end
end

-- createHealerFrame function
local function createHealerFrame(index)
    local f = _G["HM_Healer"..index] or CreateFrame("Frame", "HM_Healer"..index, anchor)
    f:SetSize(220, 76)
    f:ClearAllPoints()
    if index == 1 then
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    else
        f:SetPoint("TOPLEFT", frames[index - 1].frame, "BOTTOMLEFT", 0, -4)
    end

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(70, 70)
    icon:SetPoint("LEFT", f, "LEFT", 0, 0)

    -- 1px black border (BACKGROUND layer renders behind ARTWORK)
    local iconBorder = f:CreateTexture(nil, "BACKGROUND")
    iconBorder:SetSize(72, 72)
    iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBorder:SetColorTexture(0, 0, 0, 1)

    -- Register early so updateFrames never sees nil even if SetFont below fails
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local mana = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frames[index] = { frame = f, icon = icon, name = name, mana = mana }

    name:SetFont(
        (HM_Settings and HM_Settings.font)     or HM_DEFAULTS.font,
        (HM_Settings and HM_Settings.nameSize) or HM_DEFAULTS.nameSize,
        (HM_Settings and HM_Settings.outline)  or HM_DEFAULTS.outline)
    name:SetTextColor(1, 1, 1)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT",
        (HM_Settings and HM_Settings.nameX) or HM_DEFAULTS.nameX,
        (HM_Settings and HM_Settings.nameY) or HM_DEFAULTS.nameY)

    mana:SetFont(
        (HM_Settings and HM_Settings.font)     or HM_DEFAULTS.font,
        (HM_Settings and HM_Settings.manaSize) or HM_DEFAULTS.manaSize,
        (HM_Settings and HM_Settings.outline)  or HM_DEFAULTS.outline)
    mana:SetTextColor(1, 1, 1)
    mana:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT",
        (HM_Settings and HM_Settings.manaX) or HM_DEFAULTS.manaX,
        (HM_Settings and HM_Settings.manaY) or HM_DEFAULTS.manaY)
end

-- isHealer function
local HEALER_CLASSES = {
    DRUID = true,
    PRIEST = true,
    PALADIN = true,
    SHAMAN = true,
    MONK = true,
    EVOKER = true
}

local function isHealer(unit)

    local role = UnitGroupRolesAssigned(unit)

    if role == "HEALER" then
        return true
    end

    local _, class = UnitClass(unit)

    if HEALER_CLASSES[class] then
        return true
    end

    return false
end

-- isDrinking function
-- TODO: check unit wether it's drinking or not, might be fked since latest addon update
-- TODO: need to test this
-- https://www.wowhead.com/classic/spell=22734/drink
local function isDrinking(unit)
    local spellID = UnitCastingInfo(unit)
    if spellID and spellID == 22734 or spellID == 431 and isHealer(unit) then
        return true
    end
    return false
end

-- Returns true only inside a 5-player dungeon (normal/heroic/mythic/mythic+)
local function isValidContext()
    local _, instanceType = IsInInstance()
    return instanceType == "party"
end

-- Rebuild the healers list from current party state
local function refreshHealers()

    wipe(healers)

    for i = 1, 4 do
        local unit = "party"..i
        if UnitExists(unit) and isHealer(unit) then
            table.insert(healers, unit)
        end
    end

    if isHealer("player") then
        table.insert(healers, "player")
    end

end

-- updateHealers function
local function updateHealers()
    local healerCount = #healers

    if healerCount > 0 or inEditMode then
        anchor:Show()
    else
        anchor:Hide()
    end
end

-- Update frames
local FOOD_ICON = "Interface\\Icons\\INV_Drink_18"

-- Spec icon cache: specID → FileDataID icon
-- Populated on first lookup so it works for any expansion without hardcoding IDs
local specIconCache = {}

-- Maps healer class to their single healer spec ID.
-- Priests have two (Disc=256, Holy=257); we default to Holy here.
local HEALER_SPEC_BY_CLASS = {
    PALADIN = 65,
    PRIEST  = 257,
    DRUID   = 105,
    SHAMAN  = 264,
    MONK    = 270,
    EVOKER  = 1468,
}

local function getSpecIcon(unit)
    local specID

    if unit == "player" then
        local idx = GetSpecialization()
        specID = idx and select(1, GetSpecializationInfo(idx))
    else
        -- GetInspectSpecialization only works after NotifyInspect, so fall back
        -- to the class-based healer spec table which is always available
        local _, class = UnitClass(unit)
        specID = class and HEALER_SPEC_BY_CLASS[class]
    end

    if not specID or specID == 0 then return nil end

    if specIconCache[specID] == nil then
        specIconCache[specID] = select(4, GetSpecializationInfoByID(specID)) or false
    end
    return specIconCache[specID] or nil
end

local function updateFrames()
    for i,unit in ipairs(healers) do

        if not frames[i] then
            createHealerFrame(i)
        end

        local f = frames[i]

        local name  = UnitName(unit) or "?"

        local mana = UnitPower(unit, 0) or 0
        local max  = UnitPowerMax(unit, 0) or 0

        local percent = 0
        if max > 0 then
            percent = math.floor(mana/max*100)
        end

        -- ICON
        if isDrinking(unit) then
            f.icon:SetTexture(FOOD_ICON)
            f.icon:SetTexCoord(0.0625, 0.9375, 0.0625, 0.9375)
        else
            local icon = getSpecIcon(unit)
            if icon then
                f.icon:SetTexture(icon)
                f.icon:SetTexCoord(0, 1, 0, 1)
            end
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

    -- Hide frames that belong to healers no longer in the list
    for i = #healers + 1, #frames do
        if frames[i] then frames[i].frame:Hide() end
    end
end

function HM_ApplySettings()
    anchor:SetScale(HM_Settings.scale)
    for _, f in ipairs(frames) do
        f.name:SetFont(HM_Settings.font, HM_Settings.nameSize, HM_Settings.outline)
        f.name:ClearAllPoints()
        f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", HM_Settings.nameX, HM_Settings.nameY)
        f.mana:SetFont(HM_Settings.font, HM_Settings.manaSize, HM_Settings.outline)
        f.mana:ClearAllPoints()
        f.mana:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", HM_Settings.manaX, HM_Settings.manaY)
    end
end

-- Edit mode: shows the drag handle and open lock button
setEditMode = function(enabled)
    inEditMode = enabled
    if enabled then
        anchorBg:Show()
        anchorText:Show()
        lockBtn:Show()
        anchor:EnableMouse(true)
        anchor:RegisterForDrag("LeftButton")
        anchor:Show()
    else
        anchorBg:Hide()
        anchorText:Hide()
        lockBtn:Hide()
        anchor:EnableMouse(false)
        updateHealers()
    end
end

-- Event handlers
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not HM_Settings then HM_Settings = {} end
        for k, v in pairs(HM_DEFAULTS) do
            if HM_Settings[k] == nil then HM_Settings[k] = v end
        end

        refreshHealers()
        loadPosition()
        updateHealers()
        updateFrames()
        HM_ApplySettings()

    elseif event == "GROUP_ROSTER_UPDATE" or event == "ROLE_CHANGED_INFORM" then
        if not HM_Settings then return end  -- not yet initialized; PLAYER_ENTERING_WORLD will handle it
        refreshHealers()
        updateHealers()
        updateFrames()

    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        local unit, powerType = ...
        if powerType == "MANA" and isHealer(unit) then
            updateFrames()
        end
    end
end)

-- Register events
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("GROUP_ROSTER_UPDATE")
addon:RegisterEvent("ROLE_CHANGED_INFORM")
addon:RegisterEvent("UNIT_POWER_UPDATE")
addon:RegisterEvent("UNIT_MAXPOWER")
addon:RegisterEvent("PLAYER_ROLES_ASSIGNED")

-- Command to toggle edit mode
SLASH_HEALERMANA1 = "/hm"
SlashCmdList["HEALERMANA"] = function()
    local valid = isValidContext()
    print(string.format("|cff00ccffHealerMana|r  dungeon:%s  members:%d  healers:%d",
        tostring(valid), GetNumGroupMembers(), #healers))
    -- dump every member so we can see their assigned role
    for i = 1, GetNumGroupMembers() do
        local u = "party" .. i
        if UnitExists(u) then
            print(string.format("  party%d  %s  role=%s", i,
                tostring(UnitName(u)), tostring(UnitGroupRolesAssigned(u))))
        end
    end
    print(string.format("  player  %s  role=%s",
        tostring(UnitName("player")), tostring(UnitGroupRolesAssigned("player"))))
    setEditMode(not inEditMode)
end

-- Test function and command to print healer info
local inTestMode = false

local function testFrame()
    if inTestMode then
        inTestMode = false
        refreshHealers()
        updateHealers()
        updateFrames()
        return
    end

    inTestMode = true
    print("test triggered")

    wipe(healers)

    anchor:Show()

    local playerName = UnitName("player") or "Testhealer"

    healers[1] = "player"

    if not frames[1] then
        createHealerFrame(1)
    end

    local f = frames[1]

    -- Icon
    local icon = getSpecIcon("player")
    if icon then
        f.icon:SetTexture(icon)
        f.icon:SetTexCoord(0, 1, 0, 1)
    end

    -- Text
    f.name:SetText(playerName)
    f.mana:SetText("100%")

    -- Full alpha
    f.frame:SetAlpha(1)

    f.frame:Show()
end

SLASH_HEALERMANATEST1 = "/hmtest"

SlashCmdList["HEALERMANATEST"] = function()
    testFrame()
end