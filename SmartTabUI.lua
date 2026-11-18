-- SmartTabUI: settings window for SmartTab, with a live preview of the ranking.
-- Open with /smarttab or the minimap button. Values are saved in SmartTabDB.

local frame
local widgets = {}
local refreshing = false
local previewLines = {}
local previewMode

local function DB() return SmartTabDB end

local function Round(v, step)
  return math.floor(v / step + 0.5) * step
end

local function Tip(w, tip)
  if not tip then return end
  w:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(tip, 1, 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  w:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Label(x, y, font, width)
  local t = frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
  if width then t:SetWidth(width) t:SetJustifyH("LEFT") end
  return t
end

local function Head(x, y, text)
  local t = Label(x - 4, y, "GameFontNormal")
  t:SetText(text)
  return t
end

local function MakeSlider(key, label, minV, maxV, step, fmt, x, y, tip)
  local name = "SmartTabUISlider" .. key
  local s = CreateFrame("Slider", name, frame, "OptionsSliderTemplate")
  s:SetWidth(240)
  s:SetHeight(16)
  s:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  getglobal(name .. "Low"):SetText(string.format(fmt, minV))
  getglobal(name .. "High"):SetText(string.format(fmt, maxV))
  local text = getglobal(name .. "Text")
  s.Refresh = function()
    local v = DB()[key]
    refreshing = true
    if type(v) == "number" then s:SetValue(v) end
    refreshing = false
    text:SetText(label .. ": |cffffffff" .. string.format(fmt, v or 0) .. "|r")
  end
  s:SetScript("OnValueChanged", function()
    if refreshing then return end
    local v = Round(this:GetValue(), step)
    DB()[key] = v
    text:SetText(label .. ": |cffffffff" .. string.format(fmt, v) .. "|r")
  end)
  Tip(s, tip)
  table.insert(widgets, s)
  return s
end

-- a check box on a 0/1 setting (or a true/false one with bool = true)
local function MakeCheck(key, label, x, y, tip, bool, onChange)
  local name = "SmartTabUICheck" .. key
  local c = CreateFrame("CheckButton", name, frame, "UICheckButtonTemplate")
  c:SetWidth(24)
  c:SetHeight(24)
  c:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
  getglobal(name .. "Text"):SetText(label)
  c.Refresh = function()
    local v = DB()[key]
    if v == 1 or v == true then c:SetChecked(1) else c:SetChecked(nil) end
  end
  c:SetScript("OnClick", function()
    local on = this:GetChecked() and true or false
    if bool then DB()[key] = on elseif on then DB()[key] = 1 else DB()[key] = 0 end
    if onChange then onChange(on) end
  end)
  Tip(c, tip)
  table.insert(widgets, c)
  return c
end

------------------------------------------------------------------------
-- Live preview: the ranked candidates around you, refreshed while open
------------------------------------------------------------------------
local function RefreshPreview()
  local list, err, _, label = SmartTab.Rank()
  local n = table.getn(previewLines)
  if previewMode then previewMode:SetText("Aiming with: " .. tostring(label or "-")) end
  if not list then
    previewLines[1]:SetText("|cffff6666" .. tostring(err) .. "|r")
    for i = 2, n do previewLines[i]:SetText("") end
    return
  end
  -- which one a fresh Tab press would pick
  local cur = SmartTab.TargetGuid()
  local pick = 1
  if list[1] and list[1].guid == cur and list[2] then pick = 2 end
  if table.getn(list) == 0 then
    previewLines[1]:SetText("|cff999999no candidate in range: Tab would use UnitXP's targeting|r")
    for i = 2, n do previewLines[i]:SetText("") end
    return
  end
  for i = 1, n do
    local c = list[i]
    if c then
      local side = c.deg >= 0 and "left" or "right"
      local color = c.tier == 1 and "|cffffffff" or "|cff999999"
      local mark = "      "
      if i == pick and c.guid ~= cur then mark = "|cff66ff66Tab >|r " end
      local tgt = ""
      if c.guid == cur then tgt = "  |cffffcc00(your target)|r" end
      previewLines[i]:SetText(string.format("%s%s%d. %s   %.1f yds, %.0f%s %s,  score %.2f%s|r%s",
        mark, color, i, c.name .. SmartTab.Tags(c), c.d, math.abs(c.deg), "\194\176", side, c.score,
        c.tier == 1 and "" or "  (outside cone)", tgt))
    else
      previewLines[i]:SetText("")
    end
  end
end

local W, H = 600, 690
local C1, C2 = 30, 320

local function Build()
  frame = CreateFrame("Frame", "SmartTabUIFrame", UIParent)
  frame:SetWidth(W)
  frame:SetHeight(H)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  frame:Hide()
  table.insert(UISpecialFrames, "SmartTabUIFrame") -- Esc closes it

  local tick = 0
  frame:SetScript("OnUpdate", function()
    tick = tick + (arg1 or 0)
    if tick < 0.25 then return end
    tick = 0
    RefreshPreview()
  end)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", frame, "TOP", 0, -20)
  title:SetText("SmartTab")

  local close = CreateFrame("Button", "SmartTabUIClose", frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

  -- left column: who counts
  -- left column: who counts and how Tab cycles
  local y = -84
  local function L() local v = y; y = y - 40; return v end
  Head(C1, -52, "Who counts")
  MakeSlider("cone", "Front cone (each side)", 5, 90, 5, "%d\194\176", C1, L(),
    "Mobs this far left or right of where you aim are 'in front'.\nIn-front mobs are always picked before the others.")
  MakeSlider("meleeCone", "Front cone in melee", 30, 180, 5, "%d\194\176", C1, L(),
    "Inside melee range the cone widens to this: up close, a small step\nchanges the angle a lot.")
  MakeSlider("range", "Max range", 10, 60, 1, "%d yds", C1, L(),
    "Mobs farther than this are ignored.\nOnly mobs with a nameplate can be seen.")
  MakeSlider("melee", "Melee range", 2, 10, 0.5, "%.1f yds", C1, L(),
    "Inside this distance a mob gets the melee bonus and the wider cone.")
  MakeSlider("cycle", "Cycle memory", 0, 10, 0.5, "%.1f s", C1, L(),
    "Every press ranks again from where you look now.\nMobs you tabbed through are skipped until this long after your\nlast press, so repeated Tab moves on through the pack.\n0 = no memory (Tab swaps between the best two).")
  MakeSlider("turnReset", "Turn resets the cycle", 0, 180, 5, "%d\194\176", C1, L(),
    "If you turn more than this between two presses, the mobs you\ntabbed through are forgotten: you get the best one in the new\ndirection, even one you visited before.")
  MakeSlider("petMalus", "Pet penalty", 0, 2, 0.05, "%.2f", C1, L(),
    "Removed from pets (hunter and warlock pets, other player-controlled\nNPCs). 2 = only picked when nothing else is around.")
  MakeSlider("totemMalus", "Totem penalty", 0, 2, 0.05, "%.2f", C1, L(),
    "Removed from totems. 2 = only picked when nothing else is around.")
  MakeSlider("ccMalus", "Crowd control penalty", 0, 3, 0.05, "%.2f", C1, L(),
    "Removed from mobs under a crowd control that damage breaks:\nPolymorph, Sap, Blind, Seduction, Freezing Trap, Hibernate,\nScare Beast, Shackle Undead, Repentance, Wyvern Sting.\n3 = only picked when nothing else is around.")
  local leftEnd = y

  -- right column: scoring and aiming
  y = -84
  Head(C2, -52, "Scoring")
  MakeSlider("wAngle", "Weight: facing", 0, 2, 0.05, "%.2f", C2, L(),
    "How much being near the centre of your view counts.\nAngle score: 1 dead centre, 0 at the cone edge.")
  MakeSlider("wDist", "Weight: distance", 0, 2, 0.05, "%.2f", C2, L(),
    "How much being close counts.\nDistance score: 1 on top of you, 0 at max range.\nHigher than facing = nearest mob in the cone wins.")
  MakeSlider("meleeBonus", "Melee bonus", 0, 1, 0.05, "%.2f", C2, L(),
    "Added inside melee range.\nRaise it to keep the mob you're hitting over a far one in the centre.")
  MakeSlider("combatBonus", "In combat bonus", 0, 1, 0.05, "%.2f", C2, L(),
    "Added for mobs already in combat.")
  MakeSlider("neutralMalus", "Neutral penalty", 0, 1, 0.05, "%.2f", C2, L(),
    "Removed for neutral (yellow) mobs.")
  MakeSlider("markBonus", "Raid mark bonus", 0, 1, 0.05, "%.2f", C2, L(),
    "Added for a raid-marked mob.")
  MakeSlider("skullBonus", "Skull bonus", 0, 1, 0.05, "%.2f", C2, L(),
    "Added for skull (instead of the raid mark bonus).")
  MakeSlider("fov", "Camera field of view", 50, 130, 1, "%d\194\176", C2, L(),
    "Only for 'Aim with the camera': how wide your view is, used to turn\na mob's place on screen into an angle. If mobs at the screen edge\nshow a wrong angle in the preview, adjust this.")

  -- check boxes, two rows under the columns
  y = leftEnd + 4
  MakeCheck("camera", "Aim with the camera", C1 - 4, y,
    "On: 'in front' means where your camera looks (mobs near the middle\nof your screen), even while you swing the camera with left-click.\nOff: where your character faces.\nWith no nameplate on screen it uses your character's facing.")
  MakeCheck("neutral", "Neutral mobs that aren't fighting", C2 - 4, y,
    "On: yellow mobs count (with the neutral penalty).\nOff: only once they're in combat.")
  MakeCheck("debug", "Chat line on each press", C1 - 4, y - 24,
    "Prints which mob was picked, its distance, angle and score.")
  MakeCheck("minimap", "Minimap button", C2 - 4, y - 24, nil, true, function(on)
    if SmartTabUI_ShowMinimap then SmartTabUI_ShowMinimap(on) end
  end)

  -- live preview
  y = y - 60
  Head(C1, y, "Live preview: what Tab would pick now (turn around to see it change)")
  previewMode = Label(C1, y - 18, "GameFontNormalSmall", W - 2 * C1)
  for i = 1, 6 do
    local l = Label(C1, y - 36 - (i - 1) * 16, "GameFontHighlightSmall", W - 2 * C1)
    previewLines[i] = l
  end

  local reset = CreateFrame("Button", "SmartTabUIReset", frame, "UIPanelButtonTemplate")
  reset:SetWidth(100)
  reset:SetHeight(22)
  reset:SetPoint("BOTTOM", frame, "BOTTOM", 0, 18)
  reset:SetText("Defaults")
  Tip(reset, "Puts every setting back to SmartTab's defaults.")
  reset:SetScript("OnClick", function()
    for k, v in pairs(SmartTab.DEFAULTS) do SmartTabDB[k] = v end
    SmartTabUI_Refresh()
    SmartTab.Chat("settings reset")
  end)
end

function SmartTabUI_Refresh()
  if not frame then return end
  for i = 1, table.getn(widgets) do widgets[i].Refresh() end
end

function SmartTabUI_Toggle()
  if not frame then Build() end
  if frame:IsShown() then
    frame:Hide()
  else
    SmartTabUI_Refresh()
    RefreshPreview()
    frame:Show()
  end
end

------------------------------------------------------------------------
-- Minimap button: click = settings window, drag = move around the minimap
------------------------------------------------------------------------
local mm
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function PlaceMinimap()
  local a = math.rad(SmartTabDB.minimapAngle or 200)
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
end

function SmartTabUI_ShowMinimap(on)
  if not mm then return end
  if on then mm:Show() else mm:Hide() end
end

function SmartTabUI_CreateMinimap()
  if mm then return end
  if SmartTabDB.minimap == nil then SmartTabDB.minimap = true end
  mm = CreateFrame("Button", "SmartTabMinimapButton", Minimap)
  mm:SetWidth(31)
  mm:SetHeight(31)
  mm:SetFrameStrata("MEDIUM")
  mm:SetFrameLevel(8)
  mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = mm:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot") -- Hunter's Mark icon
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("TOPLEFT", mm, "TOPLEFT", 6, -5)

  local border = mm:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53)
  border:SetHeight(53)
  border:SetPoint("TOPLEFT", mm, "TOPLEFT", 0, 0)

  mm:RegisterForClicks("LeftButtonUp")
  mm:RegisterForDrag("LeftButton")
  mm:SetScript("OnClick", function() SmartTabUI_Toggle() end)
  mm:SetScript("OnDragStart", function()
    this:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      SmartTabDB.minimapAngle = math.deg(atan2(py - my, px - mx))
      PlaceMinimap()
    end)
  end)
  mm:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
  mm:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("SmartTab")
    GameTooltip:AddLine("Click: settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move", 1, 1, 1)
    GameTooltip:Show()
  end)
  mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

  PlaceMinimap()
  SmartTabUI_ShowMinimap(SmartTabDB.minimap)
end
