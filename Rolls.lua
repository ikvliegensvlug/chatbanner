-- ChatBanner: reading loot roll lines ("Need Roll - 87 for [item] by Bram"), so the
-- alert for who won can add the winning roll. The dungeon scoreboard with loot and
-- stats is its own add-on now: Dungeon Stats.
local _, ns = ...
local CB = ns.CB

-- "%s won: %s" -> pattern with captures, plus which capture is what.
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

-- This client starts roll lines with a link to the loot history: "|HlootHistory:9772545|h[Loot]|h: ".
-- Without it the lines read as on other clients (and its number is not the roll).
local function stripHistory(s)
  return (s:gsub("^|HlootHistory:[^|]*|h%[.-%]|h:%s*", ""))
end
CB.StripLootHistory = stripHistory

local rollPatterns
-- Returns { kind, who, link, roll } for a roll line, or nil. who is a short name.
local function parseRoll(text)
  if type(text) ~= "string" then return nil end
  if not rollPatterns then
    rollPatterns = {}
    for _, f in ipairs(ROLL_FORMATS) do
      local fmt = _G[f[1]]
      local pattern, order = toCapture(stripHistory(type(fmt) == "string" and fmt or f[2]))
      rollPatterns[#rollPatterns + 1] = { pattern = pattern, order = order, kind = f[3], roles = f[4] }
    end
  end
  text = stripHistory(text)
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

-- The rolls on items still being rolled for: rolls[link][who] = { kind, roll }.
-- Only kept in memory, for the few seconds between the rolls and the result.
local rolls, order = {}, {}

-- Called by the loot alert for every readable roll line, before it shows anything.
function CB:NoteRoll(roll)
  if not (roll and roll.link and roll.who) then return end
  if roll.kind ~= "needroll" and roll.kind ~= "greedroll" then return end
  if not rolls[roll.link] then
    rolls[roll.link] = {}
    order[#order + 1] = roll.link
    while #order > 20 do rolls[table.remove(order, 1)] = nil end
  end
  rolls[roll.link][roll.who] = { kind = roll.kind == "needroll" and "Need" or "Greed", roll = roll.roll }
end

-- What someone rolled on an item: { kind = "Need", roll = 87 } or nil.
function CB:RollOf(link, who)
  local r = link and rolls[link]
  return r and who and r[who] or nil
end
