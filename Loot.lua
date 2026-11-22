-- ChatBanner: loot summary. Inside a dungeon or raid it notes who received a
-- green (uncommon) or better item; when you leave, it shows who got what,
-- from the lowest quality chosen in the options (db.lootMinQuality, blue by default) upwards.
local _, ns = ...
local CB = ns.CB

local KEEP_QUALITY = 2  -- noted during the run: 2 = uncommon (green) and up

-- Choices for the lowest quality in the summary, as the options show them.
CB.LOOT_QUALITIES = {
  { key = 2, label = "Green (uncommon) and better", short = "green or better" },
  { key = 3, label = "Blue (rare) and better",      short = "blue or better" },
  { key = 4, label = "Purple (epic) and better",    short = "purple or better" },
}

local function qualityLabel(q)
  for _, o in ipairs(CB.LOOT_QUALITIES) do if o.key == q then return o.short end end
  return CB.LOOT_QUALITIES[2].short
end

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

local LOOT_INFO = { source = "loot", tag = "Loot", chat = "LOOT" }

function CB:LootSummaryLines(run)
  -- group the items per player, in the order they first got something
  local min = self.db.lootMinQuality or 3
  local players, byName = {}, {}
  for _, item in ipairs(run.items) do
    if (item.q or 3) >= min then
      if not byName[item.who] then
        byName[item.who] = {}
        players[#players + 1] = item.who
      end
      table.insert(byName[item.who], item.link)
    end
  end
  local lines = {}
  for _, who in ipairs(players) do
    lines[#lines + 1] = { who = who, items = table.concat(byName[who], ", ") }
  end
  return lines
end

-- Print the summary in chat; with alert = true also show it on screen.
-- Returns false when nothing reaches the chosen quality.
function CB:ShowLootSummary(run, alert)
  local which = qualityLabel(self.db.lootMinQuality)
  local lines = run and self:LootSummaryLines(run) or {}
  if #lines == 0 then
    if not alert then self:Print("No " .. which .. " items in the last dungeon.") end
    return false
  end
  self:Print("|cffffd100Loot from " .. run.name .. "|r (" .. which .. ")")
  for _, l in ipairs(lines) do self:Print("  " .. l.who .. ": " .. l.items) end
  if alert then
    -- the newest alert ends up on top, so show the players last to first
    for i = #lines, 1, -1 do
      self:Show(LOOT_INFO, lines[i].items, lines[i].who, { duration = 30 })
    end
    self:Show(LOOT_INFO, run.name .. " done: who got what", nil, { duration = 30, tag = "Summary" })
  end
  return true
end

function CB:FinishLootRun()
  local run = self.db.lootRun
  if not run then return end
  self.db.lootRun = nil
  if #run.items > 0 then
    self.db.lastLoot = run
    if self.db.lootSummary then self:ShowLootSummary(run, true) end
  end
end

-- Called on every zone change: start, continue or finish a run.
function CB:CheckLootRun()
  local name = inGroupInstance()
  local run = self.db.lootRun
  if name then
    if run and run.name ~= name then self:FinishLootRun(); run = nil end
    if not run then self.db.lootRun = { name = name, items = {} } end
  elseif run then
    -- a ghost running back from the graveyard has not finished the dungeon yet
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    self:FinishLootRun()
  end
end

function CB:NoteLoot(text)
  local run = self.db.lootRun
  if not run then return end
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
                     "PLAYER_UNGHOST", "CHAT_MSG_LOOT" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, text)
  if not CB.db then return end
  if event == "CHAT_MSG_LOOT" then
    CB:NoteLoot(text)
  else
    CB:CheckLootRun()
  end
end)
