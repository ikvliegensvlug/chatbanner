-- ChatBanner: a "run" is one visit to a dungeon or raid. During the run this file
-- notes who received green (uncommon) or better items and who rolled what;
-- Stats.lua adds the combat numbers. When you leave, Summary.lua shows it all,
-- with loot from the quality chosen in the options (db.lootMinQuality) upwards.
local _, ns = ...
local CB = ns.CB

local KEEP_QUALITY = 2  -- noted during the run: 2 = uncommon (green) and up

-- Choices for the lowest quality in the summary, as the options show them.
CB.LOOT_QUALITIES = {
  { key = 2, label = "Green (uncommon) and better", short = "green or better" },
  { key = 3, label = "Blue (rare) and better",      short = "blue or better" },
  { key = 4, label = "Purple (epic) and better",    short = "purple or better" },
}

-- Quality from the colour of an item link, for items the client has not cached yet.
local QUALITY_COLOURS = {
  ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6,
}

local function quality(link)
  if GetItemInfo then
    local _, _, q = GetItemInfo(link)
    if q then return q end
  end
  local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
  return hex and QUALITY_COLOURS[hex:lower()] or 0
end
CB.ItemQuality = quality

-- The game's (translated) loot lines. who = nil means the player.
local LOOT_FORMATS = {
  -- the "x2" versions first, or the plain ones would swallow the count
  { "LOOT_ITEM_MULTIPLE",       "%s receives loot: %sx%d.",    true },
  { "LOOT_ITEM_SELF_MULTIPLE",  "You receive loot: %sx%d.",    false },
  { "LOOT_ITEM",                "%s receives loot: %s.",       true },
  { "LOOT_ITEM_SELF",           "You receive loot: %s.",       false },
}

-- "%s receives loot: %s." -> pattern with captures, plus which capture is what.
-- Handles numbered arguments ("%2$s") that some translations use.
local function toCapture(fmt)
  local order, n = {}, 0
  local p = fmt:gsub("%%(%d?)%$?([sd])", function(num, kind)
    n = n + 1
    order[n] = tonumber(num) or n
    return kind == "s" and "<<S>>" or "<<D>>"
  end)
  p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  p = p:gsub("<<S>>", "(.+)"):gsub("<<D>>", "(%%d+)")
  return "^" .. p .. "$", order
end

local lootPatterns
-- Returns who (nil = you) and the item link of a loot line, or nil.
local function parseLoot(text)
  if type(text) ~= "string" then return nil end
  if not lootPatterns then
    lootPatterns = {}
    for _, f in ipairs(LOOT_FORMATS) do
      local fmt = _G[f[1]]
      local pattern, order = toCapture(type(fmt) == "string" and fmt or f[2])
      lootPatterns[#lootPatterns + 1] = { pattern = pattern, order = order, other = f[3] }
    end
  end
  for _, lp in ipairs(lootPatterns) do
    local caps = { text:match(lp.pattern) }
    if caps[1] then
      local args = {}
      for i, argNum in ipairs(lp.order) do args[argNum] = caps[i] end
      if lp.other then return args[1], args[2] end
      return nil, args[1]
    end
  end
end
CB.ParseLoot = parseLoot

-- Roll lines. Each format names what its arguments are; who = nil means you.
local ROLL_FORMATS = {
  { "LOOT_ROLL_NEED_SELF",     "You have selected Need for: %s", "need",     { "link" } },
  { "LOOT_ROLL_NEED",          "%s has selected Need for: %s",  "need",      { "who", "link" } },
  { "LOOT_ROLL_ROLLED_NEED",   "Need Roll - %d for %s by %s",   "needroll",  { "roll", "link", "who" } },
  { "LOOT_ROLL_ROLLED_GREED",  "Greed Roll - %d for %s by %s",  "greedroll", { "roll", "link", "who" } },
  -- "You won" before "%s won", or "You" would be taken for a name
  { "LOOT_ROLL_YOU_WON",       "You won: %s",                   "won",       { "link" } },
  { "LOOT_ROLL_WON",           "%s won: %s",                    "won",       { "who", "link" } },
  { "LOOT_ROLL_ALL_PASSED",    "Everyone passed on: %s",        "passed",    { "link" } },
}

local rollPatterns
-- Returns { kind, who, link, roll } for a roll line, or nil. who is a short name.
local function parseRoll(text)
  if type(text) ~= "string" then return nil end
  if not rollPatterns then
    rollPatterns = {}
    for _, f in ipairs(ROLL_FORMATS) do
      local fmt = _G[f[1]]
      local pattern, order = toCapture(type(fmt) == "string" and fmt or f[2])
      rollPatterns[#rollPatterns + 1] = { pattern = pattern, order = order, kind = f[3], roles = f[4] }
    end
  end
  for _, rp in ipairs(rollPatterns) do
    local caps = { text:match(rp.pattern) }
    if caps[1] then
      local args = {}
      for i, argNum in ipairs(rp.order) do args[argNum] = caps[i] end
      local r = { kind = rp.kind }
      for i, role in ipairs(rp.roles) do r[role] = args[i] end
      r.roll = tonumber(r.roll)
      local who = r.who or (rp.kind ~= "passed" and UnitName("player")) or nil
      r.who = who and ((Ambiguate and Ambiguate(who, "short")) or who) or nil
      return r
    end
  end
end
CB.ParseRoll = parseRoll

---------------------------------------------------------------------------
-- Tracking a run
---------------------------------------------------------------------------
local function inGroupInstance()
  if not IsInInstance then return nil end
  local inside, kind = IsInInstance()
  if inside and (kind == "party" or kind == "raid") then
    return (GetInstanceInfo and GetInstanceInfo()) or GetRealZoneText and GetRealZoneText() or "Dungeon"
  end
end

function CB:FinishLootRun()
  local run = self.db.lootRun
  if not run then return end
  -- the damage meter's numbers are secret during combat: finish once it is over
  if InCombatLockdown and InCombatLockdown() then
    self.finishAfterCombat = true
    return
  end
  self.finishAfterCombat = nil
  self.db.lootRun = nil
  run.duration = (time and run.start and (time() - run.start)) or 0
  if self.CollectStats then pcall(self.CollectStats, self, run) end
  if #run.items > 0 or (self.HasStats and self:HasStats(run)) then
    self.db.lastLoot = run
    if self.db.lootSummary and self.OpenSummary then self:OpenSummary(run) end
  end
end

-- Called on every zone change: start, continue or finish a run.
function CB:CheckLootRun()
  local name = inGroupInstance()
  local run = self.db.lootRun
  if name then
    if run and run.name ~= name then self:FinishLootRun(); run = nil end
    if not run then
      run = { name = name, items = {}, rolls = {}, start = time and time() or 0 }
      self.db.lootRun = run
      if self.StartStats then self:StartStats(run) end
    end
  elseif run then
    -- a ghost running back from the graveyard has not finished the dungeon yet
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    self:FinishLootRun()
  end
end

-- The rolls on one item in the current run.
local function rollsFor(run, link)
  run.rolls = run.rolls or {}
  local r = run.rolls[link]
  if not r then
    r = { need = {}, needers = {}, rolls = {} }
    run.rolls[link] = r
  end
  return r
end

-- What someone rolled on an item in the current run: { kind = "Need", roll = 87 } or nil.
function CB:RollOf(link, who)
  local run = self.db.lootRun
  local r = run and run.rolls and run.rolls[link]
  return r and who and r.rolls[who] or nil
end

local function noteRoll(run, roll)
  local r = rollsFor(run, roll.link)
  if roll.kind == "need" and roll.who and not r.need[roll.who] then
    r.need[roll.who] = true
    r.needers[#r.needers + 1] = roll.who
  elseif (roll.kind == "needroll" or roll.kind == "greedroll") and roll.who then
    r.rolls[roll.who] = { kind = roll.kind == "needroll" and "Need" or "Greed", roll = roll.roll }
  elseif roll.kind == "won" then
    r.winner = roll.who
  end
end

function CB:NoteLoot(text)
  local run = self.db.lootRun
  if not run then return end
  local roll = parseRoll(text)
  if roll then
    if roll.link then noteRoll(run, roll) end
    return
  end
  local who, link = parseLoot(text)
  if not link then return end
  local q = quality(link)
  if q < KEEP_QUALITY then return end
  if not who then who = UnitName("player") or "You" end
  who = (Ambiguate and Ambiguate(who, "short")) or who
  table.insert(run.items, { who = who, link = link, q = q })
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_ALIVE",
                     "PLAYER_UNGHOST", "PLAYER_REGEN_ENABLED", "CHAT_MSG_LOOT" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, text)
  if not CB.db then return end
  if event == "CHAT_MSG_LOOT" then
    CB:NoteLoot(text)
  elseif event == "PLAYER_REGEN_ENABLED" then
    if CB.finishAfterCombat then CB:FinishLootRun() end
  else
    CB:CheckLootRun()
  end
end)
