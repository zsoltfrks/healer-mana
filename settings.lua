--- HealerMana Settings Panel — custom standalone UI opened via /hms.
-- Provides controls for font, outline, scale, and per-text positioning.
-- Also contains info/feedback fields, quick actions, and footer buttons
-- for preview and anchor lock/unlock.
-- @author zsoltfrks (Grimdk-TarrenMill)
-- @see healermana.lua for the core addon logic

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

--- Available font choices displayed in the settings panel.
-- Each entry maps a display name to a font file path.
-- @field name string: human-readable font name
-- @field path string: WoW font file path (e.g. "Fonts\\FRIZQT__.TTF")
-- TODO: add more fonts based on the users available fonts in elvui folder eg.
local FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF"   },
    { name = "Skurri",        path = "Fonts\\skurri.ttf"   },
}

--- Available outline modes for font rendering.
-- @field name string: display label
-- @field flag string: WoW font outline flag ("", "OUTLINE", or "THICKOUTLINE")
local OUTLINES = {
    { name = "None",    flag = ""              },
    { name = "Outline", flag = "OUTLINE"       },
    { name = "Thick",   flag = "THICKOUTLINE"  },
}

------------------------------------------------------------------------
-- Colour palette
------------------------------------------------------------------------

--- Accent colour components (dark, hex #101010).
-- Used for selected-state button borders and section labels.
local AR, AG, AB = 0.063, 0.063, 0.063

--- Muted text colour used for labels and descriptions.
local DIM         = { 0.50, 0.50, 0.55 }

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

--- Buttons whose text colour indicates the currently selected font.
local fontButtons       = {}
--- Buttons whose text colour indicates the currently selected outline.
local outlineButtons    = {}
--- Registered slider entries for batch-refresh in refreshPanel.
-- Each entry: { slider = Slider, label = FontString, key = string, prefix = string }
local registeredSliders = {}
local scaleSlider, scaleLabel

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

--- Shared backdrop table used by all flat-coloured frames.
-- Uses the 8×8 white pixel texture for both fill and 1 px edge.
local SOLID = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

--- Apply a flat backdrop wsettings.lua healermana.lua healermana.tocith fill and border colours to a frame.
-- The frame must inherit BackdropTemplate.
-- @param frame Frame: target frame.
-- @param r number: fill red (0–1).
-- @param g number: fill green (0–1).
-- @param b number: fill blue (0–1).
-- @param a number|nil: fill alpha, defaults to 1.
-- @param br number: border red (0–1).
-- @param bg number: border green (0–1).
-- @param bb number: border blue (0–1).
-- @param ba number|nil: border alpha, defaults to 1.
local function applyBg(frame, r, g, b, a, br, bg, bb, ba)
    frame:SetBackdrop(SOLID)
    frame:SetBackdropColor(r, g, b, a or 1)
    frame:SetBackdropBorderColor(br, bg, bb, ba or 1)
end

--- Create a coloured line (divider or accent strip) on a parent frame.
-- @param parent Frame: the frame to draw on.
-- @param w number: line width in pixels.
-- @param h number: line height in pixels.
-- @param r number: red (0–1).
-- @param g number: green (0–1).
-- @param b number: blue (0–1).
-- @param a number|nil: alpha, defaults to 1.
-- @param anchorPoint string|nil: SetPoint anchor, defaults to "TOP".
-- @param x number|nil: x-offset, defaults to 0.
-- @param y number|nil: y-offset, defaults to 0.
-- @return Texture: the created texture.
local function makeLine(parent, w, h, r, g, b, a, anchorPoint, x, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(w, h)
    t:SetPoint(anchorPoint or "TOP", parent, anchorPoint or "TOP", x or 0, y or 0)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

--- Create a custom flat button with hover state.
-- Uses BackdropTemplate instead of UIPanelButtonTemplate for a modern
-- flat appearance that matches the panel aesthetic.
-- @param parent Frame: parent frame.
-- @param w number: button width.
-- @param h number: button height.
-- @param text string: button label.
-- @param onClick function: click handler.
-- @return Button: the created button (has ._label FontString field).
local function makeBtn(parent, w, h, text, onClick)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    applyBg(f, 0.13, 0.13, 0.17, 1, 0.26, 0.26, 0.30)
    f:EnableMouse(true)
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetAllPoints()
    lbl:SetText(text)
    lbl:SetTextColor(0.88, 0.88, 0.90)
    f:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.20, 0.26, 1)
        self:SetBackdropBorderColor(0.48, 0.48, 0.55, 1)
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.13, 0.13, 0.17, 1)
        self:SetBackdropBorderColor(0.26, 0.26, 0.30, 1)
    end)
    f:SetScript("OnClick", onClick)
    f._label = lbl
    return f
end

--- Create an accent-coloured button for primary footer actions.
-- Inherits from makeBtn and overrides colours to use a highlighted style.
-- @param parent Frame: parent frame.
-- @param w number: button width.
-- @param h number: button height.
-- @param text string: button label.
-- @param onClick function: click handler.
-- @return Button: the created accent button.
local function makeAccentBtn(parent, w, h, text, onClick)
    local f = makeBtn(parent, w, h, text, onClick)
    f:SetBackdropColor(0.14, 0.14, 0.17, 1)
    f:SetBackdropBorderColor(0.35, 0.35, 0.40, 1)
    f._label:SetTextColor(1, 1, 1)
    f:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.22, 0.22, 0.26, 1)
        self:SetBackdropBorderColor(0.50, 0.50, 0.55, 1)
    end)
    f:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.14, 0.14, 0.17, 1)
        self:SetBackdropBorderColor(0.35, 0.35, 0.40, 1)
    end)
    return f
end

--- Apply selected or deselected visual state to a toggle button.
-- Selected buttons get an accent border and gold text; deselected buttons
-- revert to the default flat style with muted text.
-- @param btn Button: a button created by makeBtn with a ._value field.
-- @param selected boolean: true if this button represents the active choice.
local function setToggleSelected(btn, selected)
    if selected then
        btn:SetBackdropColor(0.12, 0.12, 0.14, 1)
        btn:SetBackdropBorderColor(0.45, 0.45, 0.50, 1)
        btn._label:SetTextColor(1, 0.82, 0)
    else
        btn:SetBackdropColor(0.13, 0.13, 0.17, 1)
        btn:SetBackdropBorderColor(0.26, 0.26, 0.30, 1)
        btn._label:SetTextColor(0.58, 0.58, 0.63)
    end
end

--- Refresh a group of toggle buttons, highlighting the one matching currentValue.
-- @param buttons table: array of buttons, each with a ._value field.
-- @param currentValue any: the value to match against each button's ._value.
local function refreshGroup(buttons, currentValue)
    for _, btn in ipairs(buttons) do
        setToggleSelected(btn, btn._value == currentValue)
    end
end

--- Create an all-caps section header label with accent-tinted colour.
-- @param parent Frame: parent frame.
-- @param text string: label text (typically UPPER CASE).
-- @param x number: x-offset from parent TOPLEFT.
-- @param y number: y-offset from parent TOPLEFT.
-- @return FontString: the created label.
local function makeSectionLabel(parent, text, x, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(text)
    lbl:SetTextColor(0.70, 0.70, 0.75)
    return lbl
end

--- Synchronise all panel controls with the current HM_Settings values.
-- Called on panel show and after programmatic setting changes.
local function refreshPanel()
    if not HM_Settings then return end
    refreshGroup(fontButtons,    HM_Settings.font)
    refreshGroup(outlineButtons, HM_Settings.outline)
    if scaleSlider then scaleSlider:SetValue(HM_Settings.scale) end
    if scaleLabel  then scaleLabel:SetText(string.format("SCALE: %.2f×", HM_Settings.scale)) end
    for _, e in ipairs(registeredSliders) do
        local val = HM_Settings[e.key]
        if val ~= nil then
            e.slider:SetValue(val)
            e.label:SetText(e.prefix .. ": " .. math.floor(val + 0.5))
        end
    end
end

------------------------------------------------------------------------
-- Main panel
------------------------------------------------------------------------

--- The root settings panel frame (480×560, draggable, HIGH strata).
-- Opened and closed via /hms. Contains all sections as child frames.
local panel = CreateFrame("Frame", "HM_SettingsPanel", UIParent, "BackdropTemplate")
panel:SetSize(480, 596)
panel:SetPoint("CENTER")
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
panel:SetFrameStrata("HIGH")
panel:Hide()
applyBg(panel, 0.031, 0.031, 0.031, 0.90, 0.12, 0.12, 0.14)
panel:SetScript("OnShow", refreshPanel)


------------------------------------------------------------------------
-- Close button
------------------------------------------------------------------------

--- Custom close button — dark red square with "X" label.
local closeBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
closeBtn:SetSize(22, 22)
closeBtn:SetPoint("TOPRIGHT", -8, -9)
applyBg(closeBtn, 0.10, 0.10, 0.12, 1, 0.25, 0.25, 0.28)
closeBtn:EnableMouse(true)
local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
closeLbl:SetAllPoints()
closeLbl:SetText("X")
closeLbl:SetTextColor(0.75, 0.75, 0.78)
closeBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.20, 0.20, 0.24, 1)
    self:SetBackdropBorderColor(0.50, 0.50, 0.55, 1)
end)
closeBtn:SetScript("OnLeave", function(self)
    applyBg(self, 0.10, 0.10, 0.12, 1, 0.25, 0.25, 0.28)
end)
closeBtn:SetScript("OnClick", function() panel:Hide() end)

------------------------------------------------------------------------
-- Header
------------------------------------------------------------------------

local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("TOPLEFT", 16, -14)
titleText:SetText("|cffccccccgrim|rHealerMana")

local versionText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
versionText:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
versionText:SetText("Version: v1.0")
versionText:SetTextColor(DIM[1], DIM[2], DIM[3])

local tagline = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tagline:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
tagline:SetText("Healer mana tracker  ·  Dungeon only  ·  Masque compatible")
tagline:SetTextColor(DIM[1], DIM[2], DIM[3])

-- Header separator
makeLine(panel, 452, 1, 0.22, 0.22, 0.27, 0.9, "TOP", 0, -52)

------------------------------------------------------------------------
-- Info & Feedback section (left column)
------------------------------------------------------------------------

--- Left info box showing author name and a read-only GitHub URL.
-- The EditBox is locked to prevent edits; clicking it selects all text
-- so the user can Ctrl+C to copy the URL.
local infoSection = CreateFrame("Frame", nil, panel, "BackdropTemplate")
infoSection:SetSize(224, 110)
infoSection:SetPoint("TOPLEFT", 14, -60)
applyBg(infoSection, 0.06, 0.06, 0.08, 1, 0.16, 0.16, 0.20)

makeSectionLabel(infoSection, "INFO & FEEDBACK", 10, -10)

local authorLabel = infoSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
authorLabel:SetPoint("TOPLEFT", 10, -28)
authorLabel:SetText("Author")
authorLabel:SetTextColor(DIM[1], DIM[2], DIM[3])

local authorName = infoSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
authorName:SetPoint("TOPLEFT", 10, -44)
authorName:SetText("|cff00cc66zsoltfrks|r - |cff6699ccGrimdk-TarrenMill|r")

local githubLabel = infoSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
githubLabel:SetPoint("TOPLEFT", 10, -64)
githubLabel:SetText("GitHub")
githubLabel:SetTextColor(DIM[1], DIM[2], DIM[3])

local githubBox = CreateFrame("EditBox", nil, infoSection, "BackdropTemplate")
githubBox:SetSize(198, 20)
githubBox:SetPoint("TOPLEFT", 10, -82)
applyBg(githubBox, 0.04, 0.04, 0.06, 1, 0.26, 0.26, 0.30)
githubBox:SetFontObject("GameFontNormalSmall")
githubBox:SetAutoFocus(false)
githubBox:SetTextInsets(4, 4, 2, 2)
githubBox:SetText("https://github.com/zsoltfrks/healer-mana")
githubBox:SetCursorPosition(0)
githubBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
githubBox:SetScript("OnEscapePressed",   function(self) self:ClearFocus() end)
githubBox:SetScript("OnTextChanged", function(self)
    self:SetText("https://github.com/zsoltfrks/healer-mana")
    self:HighlightText()
end)

------------------------------------------------------------------------
-- Quick Actions section (right column)
------------------------------------------------------------------------

--- Right actions box with Reload UI and Reset Settings buttons.
-- Reset triggers a confirmation dialog before wiping saved variables.
local actionsSection = CreateFrame("Frame", nil, panel, "BackdropTemplate")
actionsSection:SetSize(224, 110)
actionsSection:SetPoint("TOPRIGHT", -14, -60)
applyBg(actionsSection, 0.06, 0.06, 0.08, 1, 0.16, 0.16, 0.20)

makeSectionLabel(actionsSection, "QUICK ACTIONS", 10, -10)

local actionsDesc = actionsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
actionsDesc:SetPoint("TOPLEFT", 10, -28)
actionsDesc:SetText("Affects addon settings directly.")
actionsDesc:SetTextColor(DIM[1], DIM[2], DIM[3])

local reloadBtn = makeBtn(actionsSection, 96, 26, "Reload UI", function() ReloadUI() end)
reloadBtn:SetPoint("TOPLEFT", 10, -54)

local resetBtn = makeBtn(actionsSection, 106, 26, "Reset Settings", function()
    StaticPopup_Show("HM_CONFIRM_RESET")
end)
resetBtn:SetPoint("LEFT", reloadBtn, "RIGHT", 6, 0)

--- Confirmation dialog shown before resetting all settings.
-- Wipes HM_Settings and HM_Position, then reloads the UI.
StaticPopupDialogs["HM_CONFIRM_RESET"] = {
    text = "Reset all HealerMana settings and position to defaults?\n\nThis will reload your UI.",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        HM_Settings = nil
        HM_Position = nil
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Separator below info/actions
makeLine(panel, 452, 1, 0.22, 0.22, 0.27, 0.9, "TOP", 0, -178)

------------------------------------------------------------------------
-- Settings section (font, outline, scale, name/mana offsets)
------------------------------------------------------------------------

--- Main settings box containing all visual customisation controls.
-- Houses font selection, outline toggle, scale slider, and per-text
-- (Name / Mana%) size and offset sliders.
local ss = CreateFrame("Frame", nil, panel, "BackdropTemplate")
ss:SetSize(452, 356)
ss:SetPoint("TOP", panel, "TOP", 0, -186)
applyBg(ss, 0.05, 0.05, 0.07, 1, 0.14, 0.14, 0.18)

-- FONT
makeSectionLabel(ss, "FONT", 12, -12)

for i, f in ipairs(FONTS) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local btn = makeBtn(ss, 136, 24, f.name, function()
        HM_Settings.font = f.path
        refreshGroup(fontButtons, HM_Settings.font)
        HM_ApplySettings()
    end)
    btn:SetPoint("TOPLEFT", 12 + col * 142, -28 - row * 30)
    btn._value = f.path
    fontButtons[i] = btn
end

-- OUTLINE
makeSectionLabel(ss, "OUTLINE", 12, -96)

for i, o in ipairs(OUTLINES) do
    local btn = makeBtn(ss, 92, 24, o.name, function()
        HM_Settings.outline = o.flag
        refreshGroup(outlineButtons, HM_Settings.outline)
        HM_ApplySettings()
    end)
    btn:SetPoint("TOPLEFT", 12 + (i - 1) * 98, -112)
    btn._value = o.flag
    outlineButtons[i] = btn
end

-- Scale divider
makeLine(ss, 428, 1, 0.20, 0.20, 0.25, 0.7, "TOP", 0, -144)

-- SCALE
scaleLabel = makeSectionLabel(ss, "SCALE: 1.00×", 12, -152)

scaleSlider = CreateFrame("Slider", "HM_ScaleSlider", ss, "OptionsSliderTemplate")
scaleSlider:SetPoint("TOPLEFT", 12, -172)
scaleSlider:SetWidth(424)
scaleSlider:SetMinMaxValues(0.5, 2.0)
scaleSlider:SetValueStep(0.05)
scaleSlider:SetObeyStepOnDrag(true)
scaleSlider:SetValue(1.0)
scaleSlider.Low:SetText("0.5×")
scaleSlider.High:SetText("2.0×")
scaleSlider:SetScript("OnValueChanged", function(self, value)
    if not HM_Settings then return end
    HM_Settings.scale = value
    scaleLabel:SetText(string.format("SCALE: %.2f×", value))
    HM_ApplySettings()
end)

-- Name / Mana divider
makeLine(ss, 428, 1, 0.20, 0.20, 0.25, 0.7, "TOP", 0, -202)

------------------------------------------------------------------------
-- Slider factory
------------------------------------------------------------------------

--- Create a labelled slider bound to a key in HM_Settings.
-- The slider is parented to the settings section (ss) and updates
-- HM_Settings on drag, immediately applying changes via HM_ApplySettings.
-- @param x number: x-offset within the settings section.
-- @param y number: y-offset within the settings section.
-- @param w number: slider width in pixels.
-- @param settingKey string: key in HM_Settings to read/write.
-- @param labelPrefix string: prefix shown before the value (e.g. "Size").
-- @param minVal number: minimum slider value.
-- @param maxVal number: maximum slider value.
-- @param step number: slider step increment.
local function makeSlider(x, y, w, settingKey, labelPrefix, minVal, maxVal, step)
    local lbl = ss:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", ss, "TOPLEFT", x, y)
    local val = (HM_Settings and HM_Settings[settingKey]) or minVal
    lbl:SetText(labelPrefix .. ": " .. math.floor(val + 0.5))
    lbl:SetTextColor(0.72, 0.72, 0.78)

    local sl = CreateFrame("Slider", nil, ss, "OptionsSliderTemplate")
    sl:SetWidth(w)
    sl:SetPoint("TOPLEFT", ss, "TOPLEFT", x, y - 16)
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

------------------------------------------------------------------------
-- Name / Mana% offset sliders
------------------------------------------------------------------------

-- NAME text controls (size, X-offset, Y-offset)
makeSectionLabel(ss, "NAME",  12, -210)
makeSlider( 12, -226, 202, "nameSize", "Size",  8, 60,  1)
makeSlider( 12, -262, 202, "nameX",    "X",     0, 50,  1)
makeSlider( 12, -298, 202, "nameY",    "Y",   -40, 40,  1)

-- MANA% text controls (size, X-offset, Y-offset)
makeSectionLabel(ss, "MANA%", 238, -210)
makeSlider(238, -226, 202, "manaSize", "Size",  8, 60,  1)
makeSlider(238, -262, 202, "manaX",    "X",     0, 50,  1)
makeSlider(238, -298, 202, "manaY",    "Y",   -40, 40,  1)

-- Separator above footer
makeLine(panel, 452, 1, 0.22, 0.22, 0.27, 0.9, "TOP", 0, -550)

------------------------------------------------------------------------
-- Footer bar (Preview / Unlock / Lock)
------------------------------------------------------------------------

--- Footer bar with primary action buttons.
-- Preview: toggles a test healer frame via HM_TogglePreview (defined in healermana.lua).
-- Unlock Anchor: enters edit mode so the anchor can be dragged.
-- Lock Anchor: exits edit mode, hiding the drag handle.
local footer = CreateFrame("Frame", nil, panel, "BackdropTemplate")
footer:SetSize(480, 42)
footer:SetPoint("BOTTOM", panel, "BOTTOM", 0, 0)
applyBg(footer, 0.05, 0.05, 0.06, 1, 0.12, 0.12, 0.14)

local previewBtn = makeAccentBtn(footer, 120, 28, "Preview", function()
    if HM_TogglePreview then HM_TogglePreview() end
end)
previewBtn:SetPoint("LEFT", footer, "LEFT", 14, 0)

local unlockBtn = makeBtn(footer, 136, 28, "Unlock Anchor", function()
    if HM_SetEditMode then HM_SetEditMode(true) end
end)
unlockBtn:SetPoint("LEFT", previewBtn, "RIGHT", 8, 0)

local lockBtn = makeBtn(footer, 120, 28, "Lock Anchor", function()
    if HM_SetEditMode then HM_SetEditMode(false) end
end)
lockBtn:SetPoint("LEFT", unlockBtn, "RIGHT", 8, 0)

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------

--- /hms — Toggle the settings panel open or closed.
SLASH_HEALERMANASETTINGS1 = "/hms"
SlashCmdList["HEALERMANASETTINGS"] = function()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end
