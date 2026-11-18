-- SmartTab: Tab targeting by where your character faces and how far enemies are.
-- Only acts when you press its key (never changes your target on its own).
-- Needs SuperWoW (GetPlayerFacing, UnitPosition, TargetUnit(guid), nameplate GUIDs).
-- Uses UnitXP SP3 for distance and line of sight when present.
--   /run SmartTab_Next()   best enemy where you look, skipping the ones you just tabbed through
--   /run SmartTab_Prev()   back through the ones you tabbed through (or your last enemy)

BINDING_HEADER_SMARTTAB = "SmartTab"
BINDING_NAME_SMARTTAB_NEXT = "Smart target (best / next)"
BINDING_NAME_SMARTTAB_PREV = "Smart target (previous)"

SmartTabDB = SmartTabDB or {}
SmartTabLog = SmartTabLog or {}

local DEFAULTS = {
  cone         = 30,    -- half-width of the "in front" cone, degrees (30 = 30 left to 30 right)
  meleeCone    = 90,    -- inside melee range, a mob this far off-centre still counts as in front
  range        = 40,    -- max distance, yards
  melee        = 5,     -- melee range, yards
  wAngle       = 1.0,   -- weight of the angle score (0..1: 1 dead centre, 0 at the cone edge)
  wDist        = 0.5,   -- weight of the distance score (0..1: 1 on top of you, 0 at max range)
  meleeBonus   = 0.15,  -- extra score inside melee range
  combatBonus  = 0.10,  -- extra score for a mob already in combat
  neutralMalus = 0.10,  -- score removed for a neutral (yellow) mob
  petMalus     = 0.50,  -- score removed for a pet (hunter / warlock pets, other player-controlled NPCs)
  totemMalus   = 0.50,  -- score removed for a totem
  ccMalus      = 1.00,  -- score removed for a mob under crowd control that damage breaks
  markBonus    = 0.10,  -- extra score for a raid-marked mob
  skullBonus   = 0.20,  -- extra score for skull (replaces markBonus)
  neutral      = 1,     -- 1 = neutral mobs are candidates, 0 = only when in combat
  cycle        = 3,     -- seconds: mobs you tabbed through are skipped for this long after your last press
  turnReset    = 30,    -- degrees: turning more than this between presses forgets the mobs you tabbed through
  camera       = 0,     -- 1 = aim with the camera (nameplates on screen), 0 = with your character's facing
  fov          = 110,   -- camera horizontal field of view, degrees (turns screen positions into angles)
  debug        = 0,     -- 1 = one chat line per press
  logMax       = 2000,  -- log lines kept in SavedVariables (SmartTabLog)
}

local CFG = SmartTabDB
local PI = math.pi
local ST = {}                 -- helpers
local idx, lastPress, lastView = 0, -100, nil
local visited, history = {}, {}   -- mobs tabbed through in this cycle; their order (for Shift-Tab)

function ST.Log(s)
  table.insert(SmartTabLog, date("%H:%M:%S") .. string.format(" %.2f ", GetTime()) .. s)
  local n = table.getn(SmartTabLog)
  local max = CFG.logMax or 2000
  while n > max do table.remove(SmartTabLog, 1); n = n - 1 end
end

function ST.Chat(s)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSmartTab|r " .. s)
end

function ST.Dist(g, a, b, pa, pb)
  if type(UnitXP) == "function" then
    local ok, d = pcall(UnitXP, "distanceBetween", "player", g)
    if ok and type(d) == "number" then return d end
  end
  local da, db = a - pa, b - pb
  return math.sqrt(da * da + db * db)
end

function ST.InSight(g)
  if type(UnitXP) ~= "function" then return true end
  local ok, v = pcall(UnitXP, "inSight", "player", g)
  if ok and v == false then return false end
  return true
end

function ST.Norm(x)
  while x > PI do x = x - 2 * PI end
  while x < -PI do x = x + 2 * PI end
  return x
end

-- world direction from you to (a, b), radians, same scale as GetPlayerFacing
-- (axis order checked in game with TabProbe: bearing = atan2(da, db))
function ST.Bearing(a, b, pa, pb)
  return math.atan2(a - pa, b - pb)
end

-- angle from the screen centre to a nameplate, radians; positive = left. nil when off screen.
function ST.ScreenOffset(plate)
  if not plate:IsVisible() then return nil end
  local x = plate:GetCenter()
  if not x then return nil end
  local px = x * plate:GetEffectiveScale()
  local w = WorldFrame:GetWidth() * WorldFrame:GetEffectiveScale()
  if not w or w <= 0 then return nil end
  local f = (w / 2) / math.tan(math.rad(CFG.fov) / 2)
  return math.atan((w / 2 - px) / f)
end

-- crowd control that damage breaks, by debuff icon (1.12's UnitDebuff returns the icon).
-- Not here: Gouge (same icon as Rend), fears (they take some damage before breaking).
local CC_ICONS = {
  { "Spell_Nature_Polymorph", "Polymorph" },
  { "Spell_Magic_PolymorphPig", "Polymorph" },
  { "Ability_Hunter_Pet_Turtle", "Polymorph" },
  { "Ability_Sap", "Sap" },
  { "Spell_Shadow_MindSteal", "Blind / Seduction" },
  { "Spell_Frost_ChainsOfIce", "Freezing Trap" },
  { "Spell_Nature_Sleep", "Hibernate / Sleep" },
  { "Ability_Druid_Cower", "Scare Beast" },
  { "Spell_Nature_Slow", "Shackle Undead" },
  { "Spell_Holy_PrayerOfHealing", "Repentance" },
  { "INV_Spear_02", "Wyvern Sting" },
}

function ST.BreakableCC(g)
  for i = 1, 16 do
    local tex = UnitDebuff(g, i)
    if not tex then return nil end
    for j = 1, table.getn(CC_ICONS) do
      if string.find(tex, CC_ICONS[j][1], 1, true) then return CC_ICONS[j][2] end
    end
  end
  return nil
end

-- a mob that can be a candidate, without its angle yet
function ST.Candidate(g, plate, pa, pb)
  if UnitIsDead(g) or not UnitCanAttack("player", g) then return nil end
  if UnitCreatureType and UnitCreatureType(g) == "Critter" then return nil end
  local hostile = UnitIsEnemy("player", g)
  local combat = UnitAffectingCombat(g)
  if not hostile and CFG.neutral == 0 and not combat then return nil end
  local a, b = UnitPosition(g)
  if not a then return nil end
  local d = ST.Dist(g, a, b, pa, pb)
  if d > CFG.range then return nil end
  if not ST.InSight(g) then return nil end
  local kind
  if UnitCreatureType and UnitCreatureType(g) == "Totem" then
    kind = "totem"
  elseif UnitPlayerControlled and UnitPlayerControlled(g) and not UnitIsPlayer(g) then
    kind = "pet"
  end
  return { guid = g, name = UnitName(g) or "?", d = d, hostile = hostile, combat = combat, kind = kind,
           cc = ST.BreakableCC(g),
           bearing = ST.Bearing(a, b, pa, pb), screen = ST.ScreenOffset(plate) }
end

-- off: signed angle from the view direction, radians (positive = left)
function ST.Score(c, off)
  local deg = math.abs(off) * 180 / PI
  local cone = CFG.cone
  if c.d <= CFG.melee and CFG.meleeCone > cone then cone = CFG.meleeCone end
  local inCone = deg <= cone
  local angleScore
  if inCone then angleScore = 1 - deg / cone else angleScore = 1 - deg / 180 end
  local score = CFG.wAngle * angleScore + CFG.wDist * (1 - c.d / CFG.range)
  if c.d <= CFG.melee then score = score + CFG.meleeBonus end
  if c.combat then score = score + CFG.combatBonus end
  if not c.hostile then score = score - CFG.neutralMalus end
  if c.kind == "pet" then score = score - CFG.petMalus end
  if c.kind == "totem" then score = score - CFG.totemMalus end
  if c.cc then score = score - CFG.ccMalus end
  local mark = GetRaidTargetIndex and GetRaidTargetIndex(c.guid)
  if mark == 8 then score = score + CFG.skullBonus elseif mark then score = score + CFG.markBonus end
  c.deg = off * 180 / PI
  c.score = score
  c.tier = inCone and 1 or 2
end

-- camera direction, from the mobs whose nameplate is on screen:
-- each one gives (its world direction - its angle from the screen centre)
function ST.CameraYaw(cands)
  local sx, sy, n = 0, 0, 0
  for i = 1, table.getn(cands) do
    local c = cands[i]
    if c.screen then
      local y = c.bearing - c.screen
      sx = sx + math.sin(y)
      sy = sy + math.cos(y)
      n = n + 1
    end
  end
  if n == 0 then return nil end
  return math.atan2(sx, sy)
end

-- returns ranked list, error, view direction, view label
function ST.Rank()
  if type(GetPlayerFacing) ~= "function" or type(UnitPosition) ~= "function" then
    return nil, "SuperWoW not found"
  end
  local ok, facing = pcall(GetPlayerFacing)
  local pa, pb = UnitPosition("player")
  if not ok or type(facing) ~= "number" or not pa then return nil, "no facing / position" end

  local out, seen = {}, {}
  local kids = { WorldFrame:GetChildren() }
  for i = 1, table.getn(kids) do
    local p = kids[i]
    local okn, g = pcall(p.GetName, p, 1)
    if okn and type(g) == "string" and string.sub(g, 1, 2) == "0x" and not seen[g] and UnitExists(g) then
      seen[g] = true
      local c = ST.Candidate(g, p, pa, pb)
      if c then table.insert(out, c) end
    end
  end

  local view, label = facing, "character"
  local useScreen = false
  if CFG.camera == 1 then
    local yaw = ST.CameraYaw(out)
    if yaw then
      view, label, useScreen = yaw, "camera", true
    else
      label = "character (camera: no nameplate on screen)"
    end
  end
  for i = 1, table.getn(out) do
    local c = out[i]
    local off
    if useScreen and c.screen then off = c.screen else off = ST.Norm(c.bearing - view) end
    ST.Score(c, off)
  end

  table.sort(out, function(x, y)
    if x.tier ~= y.tier then return x.tier < y.tier end
    return x.score > y.score
  end)
  return out, nil, view, label, facing
end

function ST.TargetGuid()
  if not UnitExists("target") then return nil end
  local _, g = UnitExists("target")
  if type(g) == "string" then return g end
  if type(GetUnitGUID) == "function" then return GetUnitGUID("target") end
  return nil
end

-- " (pet, Polymorph)" etc.
function ST.Tags(c)
  local t = {}
  if c.kind then table.insert(t, c.kind) end
  if c.cc then table.insert(t, c.cc) end
  if table.getn(t) == 0 then return "" end
  return " (" .. table.concat(t, ", ") .. ")"
end

function ST.Describe(c)
  local side = c.deg >= 0 and "L" or "R"
  local scr = c.screen and string.format(" scr=%.1f", c.screen * 180 / PI) or " scr=off"
  return string.format("%s%s %.1fy %.0f%s s=%.2f t%d b=%.3f%s", c.name, ST.Tags(c), c.d, math.abs(c.deg), side, c.score, c.tier, c.bearing, scr)
end

function ST.Pick(c, how, n)
  TargetUnit(c.guid)
  local msg = how .. " -> " .. ST.Describe(c) .. " (" .. idx .. "/" .. n .. ")"
  ST.Log(msg)
  if CFG.debug == 1 then ST.Chat(msg) end
end

function ST.Fallback(why)
  ST.Log("no candidate (" .. why .. "): UnitXP fallback")
  if CFG.debug == 1 then ST.Chat("no candidate (" .. why .. ")") end
  if type(UnitXP) == "function" then
    pcall(UnitXP, "target", "nextEnemyConsideringDistance")
  else
    TargetNearestEnemy()
  end
end

-- Every press ranks again from where you look now, then takes the best mob
-- you haven't tabbed through in this cycle. The cycle ends `cycle` seconds
-- after your last press, or when you turn more than `turnReset` degrees.
function SmartTab_Next()
  local now = GetTime()
  local ranked, err, view, label, facing = ST.Rank()
  if not ranked then ST.Fallback(err); return end

  local lines = {}
  for i = 1, table.getn(ranked) do table.insert(lines, ST.Describe(ranked[i])) end
  ST.Log(string.format("press: view %s %.3f, facing %.3f, %d candidates: %s", label, view, facing, table.getn(ranked), table.concat(lines, " | ")))

  if now - lastPress > CFG.cycle then
    visited, history = {}, {}
  elseif lastView and math.abs(ST.Norm(view - lastView)) * 180 / PI > CFG.turnReset then
    ST.Log(string.format("turned %.0f deg: new cycle", math.abs(ST.Norm(view - lastView)) * 180 / PI))
    visited = {}
  end
  lastPress, lastView = now, view

  local n = table.getn(ranked)
  if n == 0 then ST.Fallback("none in range"); return end
  local cur = ST.TargetGuid()
  if cur then visited[cur] = true end

  local pick
  for i = 1, n do
    if not visited[ranked[i].guid] then pick = i; break end
  end
  if not pick then
    -- everything visited: start over (still not your current target)
    visited = {}
    if cur then visited[cur] = true end
    for i = 1, n do
      if ranked[i].guid ~= cur then pick = i; break end
    end
    if pick then ST.Log("all candidates visited: new cycle") end
  end
  if not pick then
    ST.Log("only candidate is your current target")
    if CFG.debug == 1 then ST.Chat("only " .. ranked[1].name .. " in range") end
    return
  end

  local c = ranked[pick]
  visited[c.guid] = true
  if cur and table.getn(history) == 0 then table.insert(history, cur) end
  table.insert(history, c.guid)
  idx = pick
  ST.Pick(c, "rank", n)
end

-- back through the mobs you tabbed through in this cycle; otherwise your last enemy
function SmartTab_Prev()
  local now = GetTime()
  if now - lastPress <= CFG.cycle then
    lastPress = now
    while table.getn(history) > 1 do
      table.remove(history)                      -- the mob you're on
      local g = history[table.getn(history)]
      if UnitExists(g) and not UnitIsDead(g) then
        TargetUnit(g)
        ST.Log("prev -> " .. (UnitName(g) or "?"))
        if CFG.debug == 1 then ST.Chat("prev -> " .. (UnitName(g) or "?")) end
        return
      end
    end
  end
  lastPress = now
  ST.Log("prev: nothing to go back to -> last enemy")
  TargetLastEnemy()
end

-- /smarttab               settings window
-- /smarttab list          show settings in chat
-- /smarttab <key> <num>   change a setting (e.g. /smarttab cone 40)
-- /smarttab debug         toggle the chat line
-- /smarttab reset         defaults
-- /smarttab clearlog      empty SmartTabLog
function ST.Slash(msg)
  local _, _, key, val = string.find(msg or "", "^%s*(%S*)%s*(%S*)")
  if key == "" or key == "config" then
    if SmartTabUI_Toggle then SmartTabUI_Toggle() return end
  end
  if key == "" or key == "list" then
    local keys = {}
    for k in pairs(DEFAULTS) do table.insert(keys, k) end
    table.sort(keys)
    for i = 1, table.getn(keys) do ST.Chat(keys[i] .. " = " .. tostring(CFG[keys[i]])) end
    return
  end
  if key == "debug" and val == "" then
    if CFG.debug == 1 then CFG.debug = 0 else CFG.debug = 1 end
    ST.Chat("debug " .. (CFG.debug == 1 and "on" or "off"))
    return
  end
  if key == "reset" then
    for k, v in pairs(DEFAULTS) do CFG[k] = v end
    ST.Chat("settings reset")
    if SmartTabUI_Refresh then SmartTabUI_Refresh() end
    return
  end
  if key == "clearlog" then
    SmartTabLog = {}
    ST.Chat("log cleared")
    return
  end
  if DEFAULTS[key] == nil then ST.Chat("unknown setting: " .. key); return end
  local num = tonumber(val)
  if not num then ST.Chat(key .. " = " .. tostring(CFG[key])); return end
  CFG[key] = num
  ST.Chat(key .. " set to " .. num)
  if SmartTabUI_Refresh then SmartTabUI_Refresh() end
end

-- shared with SmartTabUI.lua
SmartTab = { DEFAULTS = DEFAULTS, Rank = ST.Rank, TargetGuid = ST.TargetGuid, Chat = ST.Chat, Tags = ST.Tags }

SLASH_SMARTTAB1 = "/smarttab"
SlashCmdList["SMARTTAB"] = ST.Slash

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "SmartTab" then
    SmartTabDB = SmartTabDB or {}
    SmartTabLog = SmartTabLog or {}
    CFG = SmartTabDB
    for k, v in pairs(DEFAULTS) do if CFG[k] == nil then CFG[k] = v end end
    if type(GetPlayerFacing) ~= "function" or type(UnitPosition) ~= "function" then
      ST.Chat("SuperWoW not found: Tab will fall back to the normal targeting")
    end
    if SmartTabUI_CreateMinimap then SmartTabUI_CreateMinimap() end
  end
end)
