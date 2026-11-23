-- ChatBanner: dungeon statistics from the combat log, per group member.
-- Only counted while a run is going (see Loot.lua); stored in that run, so a
-- /reload inside the dungeon keeps them.
local _, ns = ...
local CB = ns.CB

-- Combat log flags (the game's own values when it has them).
local MINE    = COMBATLOG_OBJECT_AFFILIATION_MINE  or 0x00000001
local PARTY   = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002
local RAID    = COMBATLOG_OBJECT_AFFILIATION_RAID  or 0x00000004
local PLAYER  = COMBATLOG_OBJECT_TYPE_PLAYER       or 0x00000400
local NPC     = COMBATLOG_OBJECT_TYPE_NPC          or 0x00000800
local PET     = COMBATLOG_OBJECT_TYPE_PET          or 0x00001000
local GUARDIAN = COMBATLOG_OBJECT_TYPE_GUARDIAN    or 0x00002000
local GROUP = MINE + PARTY + RAID

-- bit.band without depending on the bit library.
local band = (bit and bit.band) or function(a, b)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

local function inGroup(flags) return flags and band(flags, GROUP) ~= 0 end
local function isPlayer(flags) return flags and band(flags, PLAYER) ~= 0 end
local function isPetLike(flags) return flags and band(flags, PET + GUARDIAN) ~= 0 end

local function short(name)
  if not name then return nil end
  return (Ambiguate and Ambiguate(name, "short")) or (name:gsub("%-.*$", ""))
end

-- Units that can be in your group, to find a name's class and pet owners.
local function groupUnits()
  local units = { "player" }
  for i = 1, 4 do units[#units + 1] = "party" .. i end
  if IsInRaid and IsInRaid() then
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
  end
  return units
end
CB.GroupUnits = groupUnits

-- pet GUID -> owner name, refreshed when pets or the group change
local petOwner = {}
local function refreshPets()
  wipe(petOwner)
  if not UnitGUID then return end
  for _, unit in ipairs(groupUnits()) do
    local petUnit = unit == "player" and "pet" or unit:gsub("^(%a+)(%d+)$", "%1pet%2")
    local guid = UnitGUID(petUnit)
    local owner = UnitName(unit)
    if guid and owner then petOwner[guid] = short(owner) end
  end
end

local function classOf(name)
  for _, unit in ipairs(groupUnits()) do
    if UnitName(unit) and short(UnitName(unit)) == name then
      local _, class = UnitClass(unit)
      return class
    end
  end
end

-- Who gets the credit: the player, or the owner of a pet or totem.
local function credit(guid, name, flags)
  if not inGroup(flags) then return nil end
  if isPlayer(flags) then return short(name) end
  if isPetLike(flags) then
    if petOwner[guid] then return petOwner[guid] end
    if band(flags, MINE) ~= 0 then return short(UnitName("player")) end
  end
end

local function statsOf(run)
  if not run.stats then run.stats = { players = {}, kills = 0, rec = {} } end
  return run.stats
end

local function player(stats, name)
  local p = stats.players[name]
  if not p then
    p = { dmg = 0, heal = 0, buffs = 0, taken = 0, kb = 0, deaths = 0, active = 0 }
    p.class = classOf(name)
    stats.players[name] = p
  end
  return p
end

local function record(stats, key, who, amount, what)
  local r = stats.rec[key]
  if not r or amount > r.amount then stats.rec[key] = { who = who, amount = amount, what = what } end
end

local DAMAGE = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
                 SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, ENVIRONMENTAL_DAMAGE = true }
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
local MELEE = MELEE or "Melee"

-- One combat log event, with the arguments of CombatLogGetCurrentEventInfo().
function CB:NoteCombat(ts, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags, _, ...)
  local run = self.db.lootRun
  if not run then return end
  local stats = statsOf(run)

  if DAMAGE[sub] then
    local amount, spell
    if sub == "SWING_DAMAGE" then
      amount, spell = (...), MELEE
    elseif sub == "ENVIRONMENTAL_DAMAGE" then
      amount = select(2, ...)
      srcName = _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. tostring((...))] or "Environment"
    else
      spell = select(2, ...)
      amount = select(4, ...)
    end
    if type(amount) ~= "number" or amount <= 0 then return end
    local who = credit(srcGUID, srcName, srcFlags)
    if who and not inGroup(dstFlags) then
      local p = player(stats, who)
      p.dmg = p.dmg + amount
      -- active time for DPS: gaps of more than 5 seconds are not counted
      if p.last and ts - p.last <= 5 then p.active = p.active + (ts - p.last) end
      p.last = ts
      record(stats, "hit", who, amount, spell)
    elseif inGroup(dstFlags) and isPlayer(dstFlags) and not inGroup(srcFlags) then
      local victim = short(dstName)
      local p = player(stats, victim)
      p.taken = p.taken + amount
      record(stats, "taken", victim, amount, srcName)
    end

  elseif HEAL[sub] then
    local who = credit(srcGUID, srcName, srcFlags)
    if not who or not inGroup(dstFlags) then return end
    local spell, amount, over = select(2, ...), select(4, ...), select(5, ...)
    if type(amount) ~= "number" then return end
    local real = amount - (over or 0)
    if real <= 0 then return end
    local p = player(stats, who)
    p.heal = p.heal + real
    record(stats, "heal", who, real, spell)

  elseif sub == "SPELL_AURA_APPLIED" then
    -- buffs given to someone else in the group
    if select(4, ...) ~= "BUFF" or srcGUID == dstGUID then return end
    local who = credit(srcGUID, srcName, srcFlags)
    if who and inGroup(dstFlags) and isPlayer(dstFlags) then
      local p = player(stats, who)
      p.buffs = p.buffs + 1
    end

  elseif sub == "PARTY_KILL" then
    local who = credit(srcGUID, srcName, srcFlags)
    if who then
      local p = player(stats, who)
      p.kb = p.kb + 1
    end

  elseif sub == "UNIT_DIED" then
    if inGroup(dstFlags) and isPlayer(dstFlags) then
      local p = player(stats, short(dstName))
      p.deaths = p.deaths + 1
    elseif not inGroup(dstFlags) and dstFlags and band(dstFlags, NPC) ~= 0 then
      stats.kills = stats.kills + 1
    end
  end
end

function CB:HasStats(run)
  return run.stats ~= nil and next(run.stats.players) ~= nil
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_PET", "GROUP_ROSTER_UPDATE",
                     "PLAYER_ENTERING_WORLD" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
  if not CB.db then return end
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    if CB.db.lootRun and CombatLogGetCurrentEventInfo then
      CB:NoteCombat(CombatLogGetCurrentEventInfo())
    end
  else
    refreshPets()
  end
end)
