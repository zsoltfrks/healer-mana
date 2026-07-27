--- HealerMana — healer mana tracker for 5-player dungeons.
-- Displays spec icon, name, and mana percentage for each healer in the party.
-- Supports Masque icon skinning and offers a draggable anchor in edit mode.
-- @author zsoltfrks (Grimdk-TarrenMill)
-- @see settings.lua for the configuration panel

------------------------------------------------------------------------
-- Compatibility shims
------------------------------------------------------------------------

--- issecretvalue and securecallfunction only exist on 12.0+ clients.
-- Stubbing them keeps the addon loadable on older clients instead of
-- erroring out on the first call.
local issecretvalue = _G.issecretvalue or function() return false end
local securecallfunction = _G.securecallfunction or function(fn, ...) return fn(...) end

--- The specialization globals were deprecated in 11.2.0 in favour of the
-- C_SpecializationInfo namespace. Resolve whichever set the client provides.
local specAPI = _G.C_SpecializationInfo or {}
local getSpecialization         = specAPI.GetSpecialization         or _G.GetSpecialization
local getSpecializationInfo     = specAPI.GetSpecializationInfo     or _G.GetSpecializationInfo
local getSpecializationInfoByID = specAPI.GetSpecializationInfoByID or _G.GetSpecializationInfoByID

--- Hidden event frame that drives all addon logic.
local addon = CreateFrame("Frame")

--- Per-healer UI row data, indexed 1..N matching the healers table.
-- Each entry contains:
-- @field frame Frame: the parent row frame (HM_Healer<N>)
-- @field icon  Texture: the spec/drinking icon texture
-- @field name  FontString: healer name display
-- @field mana  FontString: mana percentage display
local frames = {}

--- Cached mana percentages keyed by player GUID.
-- UnitPower returns secret (unreadable) numbers when unit power is restricted
-- (e.g. during M+ combat). When that happens the arithmetic on the return
-- value errors, so we fall back to the last successfully computed percentage.
-- The key is the GUID rather than the unit token because tokens are recycled:
-- "party1" can point at a different player after a roster change, which would
-- otherwise surface the previous member's mana.
local manaCache = {}
local MANA_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

--- Resolve the cache key for a unit, preferring its GUID over the unit token.
-- @param unit string: unit token.
-- @return string: the GUID when readable, otherwise the unit token itself.
local function cacheKey(unit)
    local guid = UnitGUID(unit)
    if guid and not issecretvalue(guid) then return guid end
    return unit
end

------------------------------------------------------------------------
-- Power reading helpers
------------------------------------------------------------------------

--- Safe wrapper for UnitIsUnit that handles secret boolean returns.
-- In 12.0.x tainted execution paths UnitIsUnit may return a secret boolean.
-- Returns false (no match) when the result is secret rather than raising
-- a taint error on the boolean test.
-- @param a string: first unit token
-- @param b string: second unit token
-- @return boolean: true only if the units match and the result is not secret
local function safeUnitIsUnit(a, b)
    local result = UnitIsUnit(a, b)
    if issecretvalue(result) then return false end
    return result and true or false
end

--- Read a unit's name, substituting a placeholder when it is missing or secret.
-- Both SetText and string.format raise on a secret value, so every display path
-- goes through here.
-- @param unit string: unit token
-- @return string: the unit name, or "?"
local function safeUnitName(unit)
    local name = UnitName(unit)
    if name == nil or issecretvalue(name) then return "?" end
    return name
end

--- Try to read mana percentage directly via UnitPower inside a secure context.
-- Returns the percentage (0–100) or nil if the value is secret / unavailable.
local function readPowerDirect(unit)
    local ok, pct = pcall(securecallfunction, function(u)
        local cur = UnitPower(u, MANA_POWER_TYPE) or 0
        local max = UnitPowerMax(u, MANA_POWER_TYPE) or 0
        -- Patch 12.0.0: UnitPower returns a secret value on tainted execution paths.
        -- issecretvalue() is safe to call on secret values; it returns true without
        -- raising a taint error, letting us bail before the arithmetic would crash.
        if issecretvalue(cur) or issecretvalue(max) then return nil end
        if max > 0 then
            return math.floor(cur / max * 100)
        end
        return 0
    end, unit)
    if ok and type(pct) == "number" then return pct end
    return nil
end

--- Safely convert a StatusBar's current value into a 0-100 percentage.
-- Uses interpolated values when available so animated bars match what the user sees.
-- Returns nil if the bar has secret or unusable values.
local function readPercentFromBar(bar)
    if not (bar and bar.GetValue and bar.GetMinMaxValues) then
        return nil
    end

    local ok, cur, _, max = pcall(function()
        local value = bar.GetInterpolatedValue and bar:GetInterpolatedValue() or bar:GetValue()
        local minValue, maxValue = bar:GetMinMaxValues()
        return value, minValue, maxValue
    end)

    if ok and cur ~= nil and max ~= nil
            and not issecretvalue(cur) and not issecretvalue(max)
            and max > 0 then
        return math.floor(cur / max * 100)
    end

    return nil
end

--- Try to read mana percentage from an existing UI power bar (StatusBar).
-- Scans Blizzard compact party frames and ElvUI party frames for a bar whose
-- unit matches the requested token, then reads its widget values which are
-- plain numbers even when UnitPower itself returns secrets.
-- Returns the percentage (0–100) or nil if no matching bar was found.
local function readPowerFromFrames(unit)
    -- Default Blizzard party frames (non-raid-style) are pooled frames with unitToken/ManaBar.
    local partyFrame = rawget(_G, "PartyFrame")
    local framePool = partyFrame and partyFrame.PartyMemberFramePool
    if framePool and framePool.EnumerateActive then
        for memberFrame in framePool:EnumerateActive() do
            if memberFrame.unitToken and safeUnitIsUnit(memberFrame.unitToken, unit) then
                local pct = readPercentFromBar(memberFrame.ManaBar)
                if pct ~= nil then
                    return pct
                end
            end
        end
    end

    -- Raid-style Blizzard party frames are exposed via CompactPartyFrame.memberUnitFrames.
    local compactPartyFrame = rawget(_G, "CompactPartyFrame")
    if compactPartyFrame and compactPartyFrame.memberUnitFrames then
        for _, frame in ipairs(compactPartyFrame.memberUnitFrames) do
            if frame and frame.unit and safeUnitIsUnit(frame.unit, unit) then
                local pct = readPercentFromBar(frame.powerBar or frame.PowerBar)
                if pct ~= nil then
                    return pct
                end
            end
        end
    end

    -- Blizzard compact party/raid frames: CompactPartyFrameMemberN or CompactRaidFrameN
    for _, pattern in ipairs({"CompactPartyFrameMember", "CompactRaidFrame"}) do
        for idx = 1, 5 do
            local frame = _G[pattern .. idx]
            if frame and frame.unit and safeUnitIsUnit(frame.unit, unit) then
                local pct = readPercentFromBar(frame.powerBar or frame.PowerBar)
                if pct ~= nil then
                    return pct
                end
            end
        end
    end

    -- ElvUI party frames: ElvUF_PartyGroup1UnitButtonN
    for idx = 1, 5 do
        local frame = _G["ElvUF_PartyGroup1UnitButton" .. idx]
        if frame and frame.unit and safeUnitIsUnit(frame.unit, unit) then
            local pct = readPercentFromBar(frame.Power)
            if pct ~= nil then
                return pct
            end
        end
    end

    return nil
end

--- Read mana percentage for a unit using a fallback chain:
-- 1. UnitPower via securecallfunction  (fastest, works outside restrictions)
-- 2. Blizzard / ElvUI power bar widget (bypasses secret values)
-- 3. Last known cached value           (stale but non-zero)
-- 4. 0
local function getUnitManaPercent(unit)
    local key = cacheKey(unit)

    local pct = readPowerDirect(unit)
    if pct ~= nil then
        manaCache[key] = pct
        return pct
    end

    pct = readPowerFromFrames(unit)
    if pct ~= nil then
        manaCache[key] = pct
        return pct
    end

    return manaCache[key] or 0
end

--- Ordered list of unit tokens ("party1"–"party4", "player") that are healers.
-- Rebuilt by refreshHealers on every roster or instance change.
local healers = {}

--- Set view of `healers` for O(1) membership tests in the event handler.
-- UNIT_AURA and UNIT_POWER_UPDATE fire for many units, so the handler filters
-- on this table before doing any further work.
local healerLookup = {}

--- Optional Masque integration.
-- If the Masque library is available, a skin group is created for all healer
-- icon buttons. When absent both values are nil and the addon falls back to
-- a simple 1 px black border around the icon.
-- @see createHealerFrame
local MSQ = LibStub and LibStub("Masque", true)
local masqueGroup = MSQ and MSQ:Group("HealerMana", "Healer Icons")

--- Default values for every key that can appear in the saved HM_Settings table.
-- PLAYER_ENTERING_WORLD merges these into HM_Settings so nil checks are not
-- needed later.
-- @field font     string: path to the default font file
-- @field outline  string: font outline flag ("THICKOUTLINE", "OUTLINE", or "")
-- @field scale    number: anchor frame scale multiplier
-- @field nameSize number: font size for the healer name
-- @field nameX    number: horizontal offset of the name from the icon
-- @field nameY    number: vertical offset of the name from the icon
-- @field manaSize number: font size for the mana percentage
-- @field manaX    number: horizontal offset of the mana text from the icon
-- @field manaY    number: vertical offset of the mana text from the icon
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
--- True while the /hmtest preview row is up. Declared here rather than next to
-- testFrame because the event handler has to ignore events in test mode, and a
-- later `local` would leave that closure reading a nil global instead.
local inTestMode = false
local setEditMode  -- forward declared; depends on updateHealers defined later

--- Default anchor position used when no saved HM_Position exists.
-- @field point string: anchor point on UIParent
-- @field x     number: horizontal offset
-- @field y     number: vertical offset
local defaultPosition = {
    point = "CENTER",
    x = 0,
    y = 200
}

------------------------------------------------------------------------
-- Anchor frame
------------------------------------------------------------------------

--- Anchor — invisible parent frame for healer rows.
-- Becomes a drag handle in edit mode. All healer row frames are children
-- of this frame so they move together.
local anchor = CreateFrame("Frame", "HM_Anchor", UIParent)
anchor:SetPoint(defaultPosition.point, UIParent, defaultPosition.point, defaultPosition.x, defaultPosition.y)
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

------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------

--- Restore the anchor position from saved variables or fall back to defaults.
-- Reads from the global HM_Position table; if absent, uses defaultPosition.
local function loadPosition()
    anchor:ClearAllPoints()
    if HM_Position then
        anchor:SetPoint(HM_Position.point, UIParent, HM_Position.point, HM_Position.x, HM_Position.y)
    else
        anchor:SetPoint(defaultPosition.point, UIParent, defaultPosition.point, defaultPosition.x, defaultPosition.y)
    end
end

------------------------------------------------------------------------
-- Healer frame construction
------------------------------------------------------------------------

--- Create (or recycle) a single healer row frame at the given index.
-- The frame contains a Masque-compatible icon button, a 1 px black border,
-- a name FontString, and a mana FontString. The result is stored in the
-- module-level `frames` table at position `index`.
-- @param index number: 1-based position in the vertical list.
local function createHealerFrame(index)
    -- Building a row twice would create a second icon button under the same
    -- global name, leaking the first one and orphaning its Masque skin.
    if frames[index] then return end

    local f = _G["HM_Healer"..index] or CreateFrame("Frame", "HM_Healer"..index, anchor)
    f:SetSize(220, 76)
    f:ClearAllPoints()
    local previousRow = index > 1 and frames[index - 1] and frames[index - 1].frame
    if previousRow then
        f:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -4)
    else
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    end

    -- Dedicated icon frame — Masque sizes its skin to fill this frame,
    -- so it must match the icon exactly (70×70), not the full row frame.
    local iconBtn = CreateFrame("Button", "HM_HealerIcon"..index, f)
    iconBtn:SetSize(70, 70)
    iconBtn:SetPoint("LEFT", f, "LEFT", 0, 0)

    local icon = iconBtn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()

    -- 1px black border (BACKGROUND layer renders behind ARTWORK)
    local iconBorder = iconBtn:CreateTexture(nil, "BACKGROUND")
    iconBorder:SetSize(72, 72)
    iconBorder:SetPoint("CENTER", iconBtn, "CENTER", 0, 0)
    iconBorder:SetColorTexture(0, 0, 0, 1)

    if masqueGroup then
        masqueGroup:AddButton(iconBtn, { Icon = icon })
    end

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

------------------------------------------------------------------------
-- Role detection
------------------------------------------------------------------------

--- Check whether a unit is assigned the HEALER role.
-- Only trusts the explicit group role assignment; class-based fallback is
-- intentionally omitted to avoid false positives for off-spec players.
-- @param unit string: unit token (e.g. "party1", "player").
-- @return boolean: true if the unit's assigned role is "HEALER".
local function isHealer(unit)
    return UnitGroupRolesAssigned(unit) == "HEALER"
end

--- Reference drink spell used to resolve the localised aura name.
-- Every drink — conjured water, refreshment tables, vendor drinks — applies an
-- aura sharing this name, so matching on the name covers all of them without
-- maintaining a spell ID list that goes stale every expansion.
local DRINK_SPELL_ID = 430

--- Memoised localised name of the drink aura ("Drink" on enUS clients).
-- false means the client could not resolve it; nil means it has not been tried.
local drinkAuraName

--- Look up and cache the localised drink aura name.
-- Taken from the client itself, so it stays correct on non-English locales.
-- @return string|nil: the aura name, or nil if it could not be resolved.
local function getDrinkAuraName()
    if drinkAuraName == nil then
        local ok, name = pcall(function()
            return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(DRINK_SPELL_ID)
        end)
        drinkAuraName = (ok and name) or false
    end
    return drinkAuraName or nil
end

--- Detect whether a unit currently has the drink aura.
-- Drinking applies an aura rather than starting a cast or channel, so
-- UnitCastingInfo never reports it. AuraData fields such as spellId and name
-- are not designated NeverSecret and become secret for restricted party units,
-- so only the presence of the returned table is tested — no field is read.
-- @param unit string: unit token to check.
-- @return boolean: true if the unit is drinking.
local function isDrinking(unit)
    local auraName = getDrinkAuraName()
    if not auraName or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
        return false
    end

    local ok, aura = pcall(securecallfunction, C_UnitAuras.GetAuraDataBySpellName, unit, auraName, "HELPFUL")
    return ok and aura ~= nil and not issecretvalue(aura)
end

------------------------------------------------------------------------
-- Context check
------------------------------------------------------------------------

--- Check whether the player is in a valid context for the addon.
-- Returns true only inside a 5-player dungeon (normal/heroic/mythic/mythic+).
-- The addon hides all frames and skips processing outside of this context.
-- @return boolean: true if instanceType is "party".
local function isValidContext()
    local _, instanceType = IsInInstance()
    return instanceType == "party"
end

------------------------------------------------------------------------
-- Healer list management
------------------------------------------------------------------------

--- Rebuild the healers list from the current party state.
-- Wipes the existing list and iterates party1–party4 plus "player",
-- inserting any unit whose assigned role is HEALER.
-- Must be followed by updateHealers and updateFrames to reflect changes.
local function refreshHealers()

    wipe(healers)
    wipe(healerLookup)

    for i = 1, 4 do
        local unit = "party"..i
        if UnitExists(unit) and isHealer(unit) then
            table.insert(healers, unit)
            healerLookup[unit] = true
        end
    end

    if isHealer("player") then
        table.insert(healers, "player")
        healerLookup["player"] = true
    end

end

--- Show or hide the anchor frame based on healer count and edit mode.
-- The anchor (and therefore all child healer row frames) is visible when
-- at least one healer exists or when the user is in edit mode.
local function updateHealers()
    local healerCount = #healers

    if healerCount > 0 or inEditMode then
        anchor:Show()
    else
        anchor:Hide()
    end
end

------------------------------------------------------------------------
-- Spec icon resolution
------------------------------------------------------------------------

local FOOD_ICON = "Interface\\Icons\\INV_Drink_18"

--- Shown when a healer's spec icon cannot be resolved, so a recycled row never
-- keeps the previous healer's icon.
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Cache mapping specID → FileDataID icon texture.
-- Populated on first lookup via GetSpecializationInfoByID so it works for
-- any expansion without hardcoding file IDs.
local specIconCache = {}

--- Maps each healer-capable class to its primary healer spec ID.
-- Used as a fallback for party members where GetInspectSpecialization is
-- unavailable. Priests have two healer specs (Disc=256, Holy=257); we
-- default to Holy.
-- @field PALADIN number: 65 (Holy)
-- @field PRIEST  number: 257 (Holy)
-- @field DRUID   number: 105 (Restoration)
-- @field SHAMAN  number: 264 (Restoration)
-- @field MONK    number: 270 (Mistweaver)
-- @field EVOKER  number: 1468 (Preservation)
local HEALER_SPEC_BY_CLASS = {
    PALADIN = 65,
    PRIEST  = 257,
    DRUID   = 105,
    SHAMAN  = 264,
    MONK    = 270,
    EVOKER  = 1468,
}

--- Resolve the healer spec icon texture for a unit.
-- For "player" uses the actual current spec. For party members falls back
-- to the class-based HEALER_SPEC_BY_CLASS table because
-- GetInspectSpecialization requires a prior NotifyInspect call.
-- Results are cached in specIconCache for the lifetime of the session.
-- @param unit string: unit token (e.g. "party1", "player").
-- @return number|nil: FileDataID icon texture, or nil if unavailable.
local function getSpecIcon(unit)
    local specID

    if unit == "player" then
        local idx = getSpecialization and getSpecialization()
        specID = idx and select(1, getSpecializationInfo(idx))
    else
        -- GetInspectSpecialization only works after NotifyInspect, so fall back
        -- to the class-based healer spec table which is always available
        local _, class = UnitClass(unit)
        specID = class and HEALER_SPEC_BY_CLASS[class]
    end

    if not specID or specID == 0 then return nil end

    if specIconCache[specID] == nil then
        specIconCache[specID] = getSpecializationInfoByID
            and select(4, getSpecializationInfoByID(specID)) or false
    end
    return specIconCache[specID] or nil
end

------------------------------------------------------------------------
-- Frame update loop
------------------------------------------------------------------------

--- Refresh all visible healer row frames with current data.
-- Creates frames on demand if they don't yet exist. For each healer in
-- the list: resolves icon (drinking or spec), reads mana percentage via
-- a pcall wrapper to avoid taint errors, updates the text, and applies
-- a range-based alpha fade. Hides any surplus frames.
local function updateFrames()
    for i,unit in ipairs(healers) do

        if not frames[i] then
            createHealerFrame(i)
        end

        local f = frames[i]

        local unitName = safeUnitName(unit)

        -- Read mana via the fallback chain (direct → UI frames → cache).
        local percent = getUnitManaPercent(unit)

        -- ICON — always assign a texture. Rows are recycled between healers, so
        -- skipping the assignment leaves the previous healer's spec icon, or a
        -- stale food icon, on screen.
        f.icon:SetTexture(isDrinking(unit) and FOOD_ICON or getSpecIcon(unit) or UNKNOWN_ICON)
        f.icon:SetTexCoord(0.0625, 0.9375, 0.0625, 0.9375)

        -- TEXT
        f.name:SetText(unitName)
        f.mana:SetText(percent.."%")

        -- RANGE FADE — UnitInRange is unrestricted for group members; player is
        -- always in range of themselves. If the return value is secret (tainted
        -- path), default to full alpha rather than incorrectly dimming the frame.
        local inRange = (unit == "player") or UnitInRange(unit)
        f.frame:SetAlpha((issecretvalue(inRange) or inRange) and 1 or 0.6)

        f.frame:Show()
    end

    -- Hide frames that belong to healers no longer in the list
    for i = #healers + 1, #frames do
        if frames[i] then frames[i].frame:Hide() end
    end
end

------------------------------------------------------------------------
-- Settings application
------------------------------------------------------------------------

--- Apply current HM_Settings to all existing healer row frames.
-- Updates the anchor scale and reconfigures every healer row's font,
-- size, and text anchor offsets. Called after any setting change from
-- the settings panel or on initial load.
-- @see settings.lua
function HM_ApplySettings()
    if not HM_Settings then return end
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

------------------------------------------------------------------------
-- Edit mode
------------------------------------------------------------------------

--- Toggle edit mode on or off.
-- When enabled, shows the anchor background, hint text, and lock button,
-- enables dragging so the user can reposition the healer frames.
-- When disabled, hides edit-mode visuals and re-evaluates anchor visibility
-- via updateHealers (anchor hides if no healers are present).
-- @param enabled boolean: true to enter edit mode, false to leave it.
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

------------------------------------------------------------------------
-- Event handling
------------------------------------------------------------------------

--- Central event handler for all registered events.
-- PLAYER_ENTERING_WORLD: initialises settings, loads position, and performs
--   the first healer scan if inside a dungeon.
-- GROUP_ROSTER_UPDATE / ROLE_CHANGED_INFORM / PLAYER_ROLES_ASSIGNED:
--   re-scans the party for healers and refreshes all frames.
-- UNIT_POWER_UPDATE / UNIT_MAXPOWER: refreshes frames when a healer's
--   mana changes.
-- UNIT_AURA: refreshes frames so the drinking icon appears and clears, since
--   drinking is an aura and produces no power event at full mana.
--
-- The unit-scoped events fire for every unit the client tracks, so they filter
-- on healerLookup before anything more expensive runs.
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if not HM_Settings then HM_Settings = {} end
        for k, v in pairs(HM_DEFAULTS) do
            if HM_Settings[k] == nil then HM_Settings[k] = v end
        end

        loadPosition()

        if isValidContext() then
            refreshHealers()
        else
            wipe(healers)
            wipe(healerLookup)
        end
        updateHealers()
        updateFrames()
        HM_ApplySettings()

    elseif event == "GROUP_ROSTER_UPDATE" or event == "ROLE_CHANGED_INFORM" or event == "PLAYER_ROLES_ASSIGNED" then
        if not HM_Settings or inTestMode then return end
        if not isValidContext() then
            wipe(healers)
            wipe(healerLookup)
            updateHealers()
            -- Still refresh so leftover rows are hidden; in edit mode the anchor
            -- stays up and would otherwise keep showing the old group.
            updateFrames()
            return
        end
        refreshHealers()
        updateHealers()
        updateFrames()

    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        local unit, powerType = ...
        if not healerLookup[unit] or powerType ~= "MANA" then return end
        if inTestMode or not isValidContext() then return end

        -- This event fires with a clean call stack from the WoW engine, so
        -- UnitPower returns plain values here. Cache the result directly so
        -- updateFrames always has fresh data even when its own read is tainted.
        local cur = UnitPower(unit, MANA_POWER_TYPE)
        local max = UnitPowerMax(unit, MANA_POWER_TYPE)
        if cur and max and not issecretvalue(cur) and not issecretvalue(max) and max > 0 then
            manaCache[cacheKey(unit)] = math.floor(cur / max * 100)
        end
        updateFrames()

    elseif event == "UNIT_AURA" then
        local unit = ...
        if not healerLookup[unit] then return end
        if inTestMode or not isValidContext() then return end
        updateFrames()
    end
end)

-- Register events
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("GROUP_ROSTER_UPDATE")
addon:RegisterEvent("ROLE_CHANGED_INFORM")
addon:RegisterEvent("UNIT_POWER_UPDATE")
addon:RegisterEvent("UNIT_MAXPOWER")
addon:RegisterEvent("PLAYER_ROLES_ASSIGNED")
addon:RegisterEvent("UNIT_AURA")

------------------------------------------------------------------------
-- Periodic refresh
------------------------------------------------------------------------

--- Range fade has no event behind it, and the power-bar fallback is only read
-- when updateFrames runs — so when UnitPower is returning secrets and no power
-- event arrives, the display would freeze. A light ticker keeps it current.
-- It costs nothing while the anchor is hidden, which is everywhere but dungeons.
C_Timer.NewTicker(0.25, function()
    if inTestMode or not anchor:IsShown() then return end
    if #healers == 0 or not isValidContext() then return end
    updateFrames()
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

--- /hm — Toggle edit mode and print a debug summary.
-- Prints dungeon context, group member count, healer count, and the role
-- assignment of each party member and the player. Then toggles the anchor
-- drag handle on or off.
SLASH_HEALERMANA1 = "/hm"
SlashCmdList["HEALERMANA"] = function()
    local valid = isValidContext()
    print(string.format("|cff00ccffHealerMana|r  dungeon:%s  members:%d  healers:%d",
        tostring(valid), GetNumGroupMembers(), #healers))
    -- dump every member so we can see their assigned role. GetNumGroupMembers
    -- counts the player too, so iterating up to it would probe a party5 that
    -- never exists — party1–party4 is the full set.
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            print(string.format("  party%d  %s  role=%s", i,
                safeUnitName(u), tostring(UnitGroupRolesAssigned(u))))
        end
    end
    print(string.format("  player  %s  role=%s",
        safeUnitName("player"), tostring(UnitGroupRolesAssigned("player"))))
    setEditMode(not inEditMode)
end

------------------------------------------------------------------------
-- Test mode
------------------------------------------------------------------------

-- TODO: add a /hm reset command that wipes saved position and shows the anchor in the middle of the screen
--       maybe also reset other settings to defaults, but that might be overkill for a single command

--- Toggle a test healer frame using the player's own character.
-- On first call: creates a single healer row for "player" with the current
-- spec icon, name, and 100% mana. On second call: tears down the test
-- frame and restores the real healer state.
-- Useful for previewing settings when not inside a dungeon.
local function testFrame()
    if inTestMode then
        inTestMode = false
        -- refreshHealers does not check context on its own, so calling it
        -- outside a dungeon would leave the player listed and the anchor up.
        if isValidContext() then
            refreshHealers()
        else
            wipe(healers)
            wipe(healerLookup)
        end
        updateHealers()
        updateFrames()
        return
    end

    inTestMode = true

    wipe(healers)
    wipe(healerLookup)

    anchor:Show()

    local playerName = safeUnitName("player")

    healers[1] = "player"

    if not frames[1] then
        createHealerFrame(1)
    end

    local f = frames[1]

    -- Icon — fall back rather than leaving whatever the row showed before.
    f.icon:SetTexture(getSpecIcon("player") or UNKNOWN_ICON)
    f.icon:SetTexCoord(0.0625, 0.9375, 0.0625, 0.9375)

    -- Text
    f.name:SetText(playerName)
    f.mana:SetText("100%")

    -- Full alpha
    f.frame:SetAlpha(1)

    f.frame:Show()
end

--- /hmtest — Toggle the test healer preview frame.
SLASH_HEALERMANATEST1 = "/hmtest"

SlashCmdList["HEALERMANATEST"] = function()
    testFrame()
end

------------------------------------------------------------------------
-- Public API (consumed by settings.lua)
------------------------------------------------------------------------

--- Toggle the test preview frame on/off.
-- @see testFrame
HM_TogglePreview = testFrame

--- Enter or leave edit mode (anchor drag handle).
-- @param enabled boolean: true to unlock, false to lock.
-- @see setEditMode
HM_SetEditMode   = setEditMode
