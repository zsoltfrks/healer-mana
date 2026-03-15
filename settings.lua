-- HealerMana Settings Panel

local FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF"   },
    { name = "Skurri",        path = "Fonts\\skurri.ttf"   },
}

local OUTLINES = {
    { name = "None",    flag = ""              },
    { name = "Outline", flag = "OUTLINE"       },
    { name = "Thick",   flag = "THICKOUTLINE"  },
}

local fontButtons    = {}
local outlineButtons = {}
local registeredSliders = {}
local scaleSlider
local scaleLabel

local function refreshGroup(buttons, currentValue)
    for _, btn in ipairs(buttons) do
        if btn._value == currentValue then
            btn:GetFontString():SetTextColor(1, 0.82, 0)        -- gold: selected
        else
            btn:GetFontString():SetTextColor(0.55, 0.55, 0.55)  -- gray: unselected
        end
    end
end

local function refreshPanel()
    if not HM_Settings then return end
    refreshGroup(fontButtons,    HM_Settings.font)
    refreshGroup(outlineButtons, HM_Settings.outline)
    if scaleSlider then
        scaleSlider:SetValue(HM_Settings.scale)
    end
    if scaleLabel then
        scaleLabel:SetText(string.format("Scale: %.2fx", HM_Settings.scale))
    end
    for _, entry in ipairs(registeredSliders) do
        local val = HM_Settings[entry.key]
        if val ~= nil then
            entry.slider:SetValue(val)
            entry.label:SetText(entry.prefix .. ": " .. math.floor(val + 0.5))
        end
    end
end

-- ── Panel ──────────────────────────────────────────────────────────────────────

local panel = CreateFrame("Frame", "HM_SettingsPanel", UIParent, "BackdropTemplate")
panel:SetSize(298, 420)
panel:SetPoint("CENTER")
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
panel:SetFrameStrata("HIGH")
panel:Hide()

panel:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
panel:SetBackdropColor(0, 0, 0, 0.92)

panel:SetScript("OnShow", refreshPanel)

-- Title
local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("TOP", 0, -16)
titleText:SetText("HealerMana Settings")

-- Close button
local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", 2, 2)
closeBtn:SetScript("OnClick", function() panel:Hide() end)

-- ── Section: Font ──────────────────────────────────────────────────────────────

local fontSectionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fontSectionLabel:SetPoint("TOPLEFT", 16, -46)
fontSectionLabel:SetText("Font")

for i, f in ipairs(FONTS) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(124, 22)
    btn:SetPoint("TOPLEFT", 16 + col * 130, -62 - row * 27)
    btn:SetText(f.name)
    btn._value = f.path
    btn:SetScript("OnClick", function()
        HM_Settings.font = f.path
        refreshGroup(fontButtons, HM_Settings.font)
        HM_ApplySettings()
    end)
    fontButtons[i] = btn
end

-- ── Section: Outline ───────────────────────────────────────────────────────────

local outlineSectionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
outlineSectionLabel:SetPoint("TOPLEFT", 16, -124)
outlineSectionLabel:SetText("Outline")

for i, o in ipairs(OUTLINES) do
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(82, 22)
    btn:SetPoint("TOPLEFT", 16 + (i - 1) * 88, -140)
    btn:SetText(o.name)
    btn._value = o.flag
    btn:SetScript("OnClick", function()
        HM_Settings.outline = o.flag
        refreshGroup(outlineButtons, HM_Settings.outline)
        HM_ApplySettings()
    end)
    outlineButtons[i] = btn
end

-- ── Section: Scale ─────────────────────────────────────────────────────────────

scaleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
scaleLabel:SetPoint("TOPLEFT", 16, -178)
scaleLabel:SetText("Scale: 1.00x")

scaleSlider = CreateFrame("Slider", "HM_ScaleSlider", panel, "OptionsSliderTemplate")
scaleSlider:SetPoint("TOPLEFT", 16, -208)
scaleSlider:SetWidth(264)
scaleSlider:SetMinMaxValues(0.5, 2.0)
scaleSlider:SetValueStep(0.05)
scaleSlider:SetObeyStepOnDrag(true)
scaleSlider:SetValue(1.0)
scaleSlider.Low:SetText("0.5x")
scaleSlider.High:SetText("2.0x")

scaleSlider:SetScript("OnValueChanged", function(self, value)
    if not HM_Settings then return end
    HM_Settings.scale = value
    scaleLabel:SetText(string.format("Scale: %.2fx", value))
    HM_ApplySettings()
end)

-- ── makeSlider helper ───────────────────────────────────────────────────────────

local function makeSlider(settingKey, labelPrefix, minVal, maxVal, step, x, y, width)
    local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    local val = (HM_Settings and HM_Settings[settingKey]) or minVal
    lbl:SetText(labelPrefix .. ": " .. math.floor(val + 0.5))

    local sl = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    sl:SetWidth(width)
    sl:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y - 16)
    sl:SetMinMaxValues(minVal, maxVal)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    sl:SetValue(val)
    sl.Low:SetText("")
    sl.High:SetText("")

    sl:SetScript("OnValueChanged", function(self, value)
        if not HM_Settings then return end
        HM_Settings[settingKey] = value
        lbl:SetText(labelPrefix .. ": " .. math.floor(value + 0.5))
        HM_ApplySettings()
    end)

    table.insert(registeredSliders, { slider = sl, label = lbl, key = settingKey, prefix = labelPrefix })
end

-- ── Section: Name text ─────────────────────────────────────────────────────────

local nameSectionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
nameSectionLabel:SetPoint("TOPLEFT", 16, -248)
nameSectionLabel:SetText("Name")

makeSlider("nameSize", "Size", 8, 60, 1, 16, -265, 124)
makeSlider("nameX",    "X",   0, 50, 1, 16, -305, 124)
makeSlider("nameY",    "Y", -40, 40, 1, 16, -345, 124)

-- ── Section: Mana% text ────────────────────────────────────────────────────────

local manaSectionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
manaSectionLabel:SetPoint("TOPLEFT", 158, -248)
manaSectionLabel:SetText("Mana%")

makeSlider("manaSize", "Size", 8, 60, 1, 158, -265, 124)
makeSlider("manaX",    "X",   0, 50, 1, 158, -305, 124)
makeSlider("manaY",    "Y", -40, 40, 1, 158, -345, 124)

-- ── Slash command ──────────────────────────────────────────────────────────────

SLASH_HEALERMANASETTINGS1 = "/hms"
SlashCmdList["HEALERMANASETTINGS"] = function()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end
