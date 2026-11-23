-- ChatBanner: settings, slash commands and start-up.
local ADDON, ns = ...

local CB = {}
ns.CB = CB
_G.ChatBanner = CB

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
CB.version = (GetMeta and GetMeta(ADDON, "Version")) or "?"

-- Alert sources, in the order the options panel shows them.
CB.SOURCES = {
  { key = "whisper",      label = "Whispers (incl. Battle.net)" },
  { key = "party",        label = "Party" },
  { key = "raid",         label = "Raid and raid warnings" },
  { key = "guild",        label = "Guild" },
  { key = "officer",      label = "Officer" },
  { key = "say",          label = "Say" },
  { key = "yell",         label = "Yell" },
  { key = "emote",        label = "Emotes" },
  { key = "channel",      label = "Channels (General, Trade, LFG ...)" },
  { key = "npc",          label = "NPCs talking" },
  { key = "boss",         label = "Boss emotes and whispers" },
  { key = "battleground", label = "Battleground messages" },
  { key = "system",       label = "System messages" },
  { key = "quest",        label = "Quest progress (mobs killed, items)" },
  { key = "loot",         label = "Loot rolls (items to roll on, who won)" },
}

CB.FONTS = {
  { key = "friz",     label = "Friz Quadrata (default)", path = "Fonts\\FRIZQT__.TTF" },
  { key = "arial",    label = "Arial Narrow",            path = "Fonts\\ARIALN.TTF" },
  { key = "morpheus", label = "Morpheus",                path = "Fonts\\MORPHEUS.TTF" },
  { key = "skurri",   label = "Skurri",                  path = "Fonts\\SKURRI.TTF" },
}

CB.BORDERS = {
  { key = "subtle", label = "Subtle" },
  { key = "type",   label = "Chat type colour" },
  { key = "none",   label = "None" },
}

CB.defaults = {
  -- position and size
  position = false,       -- false = default spot; otherwise { point, relPoint, x, y }
  width = 600,
  rowHeight = 34,         -- used when autoHeight is off
  autoHeight = true,      -- row height follows the font size
  scale = 1,
  maxAlerts = 5,
  duration = 10,
  growUp = false,
  -- style
  font = "friz",
  fontSize = 14,
  bgAlpha = 0.9,
  border = "subtle",
  showTag = true,
  colorText = true,
  -- behaviour
  sound = false,
  ignoreOwn = true,
  lootSummary = true,     -- after a dungeon: the scoreboard with stats and loot
  lootMinQuality = 3,     -- lowest loot quality on it: 2 green, 3 blue, 4 purple
  sources = {
    whisper = true, party = true, raid = true, guild = true, officer = true,
    say = true, yell = true, emote = true, channel = true, npc = true,
    boss = true, battleground = true, system = true,
    quest = false,        -- a kill counter alert after every mob is mostly noise
    loot = true,          -- only items to roll on and who won them, not every loot line
  },
}

function CB:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffChatBanner|r  " .. tostring(msg))
end

-- Fill in missing settings without touching the ones the player changed.
local function merge(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil then
      if type(v) == "table" then
        db[k] = {}
        merge(db[k], v)
      else
        db[k] = v
      end
    elseif type(v) == "table" and type(db[k]) == "table" then
      merge(db[k], v)
    end
  end
end
CB.Merge = merge

-- What changed per version, shown once in chat after an update (newest first).
CB.NEWS = {
  { version = "1.0.6", notes = {
    "Dungeon scoreboard: when you leave a dungeon or raid, a window shows who did the most damage, healing and buffing, who took the most damage, the records, the bad luck and the loot, with each player's portrait. Post to party shares it. /chatbanner summary opens it again.",
    "Need rolls: an alert when someone selects Need on an item, and the winner's roll with the result.",
  } },
  { version = "1.0.5", notes = {
    "New source: loot rolls. An alert when an item comes up for a roll, and one for who won it. Other loot lines stay in your chat. Switch it off under Loot rolls.",
    "Loot summary: when you leave a dungeon or raid, ChatBanner shows who got blue or better items. Choose green or purple instead in the options; /chatbanner loot shows it again.",
  } },
  { version = "1.0.4", notes = {
    "New quick setup with the most important choices: where the alerts go and which messages get one (/chatbanner setup).",
    "Move and resize in one go: drag the box to move, drag its corner to resize. The proportions stay the same.",
    "Moving and resizing ends when you close the options or the quick setup, or reset the settings.",
    "Quest progress such as 'Kobold Vermin slain: 3/10' is now its own source and off by default, so killing mobs no longer gives alerts.",
  } },
  { version = "1.0.3", notes = {
    "The 'Follow the font size' option now sits right under the Row height slider it controls.",
  } },
  { version = "1.0.2", notes = {
    "After an update, ChatBanner now tells you in chat what changed (/chatbanner news shows it again).",
    "The row height follows the font size (option), so larger text always fits.",
    "The channel label and its box grow with the font size, so the label always fits.",
  } },
  { version = "1.0.1", notes = {
    "Scrolling the options panel no longer changes a slider when the mouse passes over it.",
  } },
}

-- -1, 0 or 1, comparing "1.2.10" style versions number by number.
local function compareVersions(a, b)
  local pa, pb = {}, {}
  for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end
CB.CompareVersions = compareVersions

-- Print the notes of every version newer than `since` (all notes when nil).
function CB:ShowNews(since)
  local shown = false
  for _, entry in ipairs(self.NEWS) do
    if (not since or compareVersions(entry.version, since) > 0)
        and compareVersions(entry.version, self.version) <= 0 then
      self:Print("|cffffd100What's new in " .. entry.version .. "|r")
      for _, note in ipairs(entry.notes) do self:Print("  - " .. note) end
      shown = true
    end
  end
  return shown
end

-- On login: a welcome line for new players, the changes for updated ones.
function CB:Announce(isNew)
  local last = ChatBannerDB.lastVersion
  if isNew then
    self:Print("Loaded. Type /chatbanner for the options, /chatbanner test for a preview.")
  elseif not last or compareVersions(last, self.version) < 0 then
    -- No lastVersion means the player came from 1.0.0, which did not store it.
    self:Print("Updated to " .. self.version .. ".")
    self:ShowNews(last or "1.0.0")
  end
  ChatBannerDB.lastVersion = self.version
end

function CB:ResetSettings()
  if self.unlocked then self:SetUnlocked(false) end
  wipe(ChatBannerDB)
  merge(ChatBannerDB, self.defaults)
  ChatBannerDB.lastVersion = self.version
  ChatBannerDB.setupDone = true
  self.db = ChatBannerDB
  if self.ApplyLayout then self:ApplyLayout() end
  if self.RefreshOptions then self:RefreshOptions() end
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
local isNew = false
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON then
    isNew = ChatBannerDB == nil
    ChatBannerDB = ChatBannerDB or {}
    merge(ChatBannerDB, CB.defaults)
    CB.db = ChatBannerDB
    CB:InitAlerts()
  elseif event == "PLAYER_LOGIN" then
    CB:InitOptions()
    CB:Announce(isNew)
    CB:MaybeSetup()
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
  "/chatbanner  - open the options",
  "/chatbanner setup  - the quick setup with the most important choices",
  "/chatbanner test  - show sample alerts",
  "/chatbanner unlock  - move and resize the alerts (lock to finish)",
  "/chatbanner reset  - restore all default settings",
  "/chatbanner news  - show what changed in recent versions",
  "/chatbanner summary  - the scoreboard of the last dungeon (stats and loot)",
}

SLASH_CHATBANNER1 = "/chatbanner"
SLASH_CHATBANNER2 = "/cbanner"
SlashCmdList.CHATBANNER = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  if cmd == "" or cmd == "options" or cmd == "config" then
    CB:OpenOptions()
  elseif cmd == "setup" then
    CB:OpenSetup()
  elseif cmd == "test" then
    CB:Test()
  elseif cmd == "unlock" or cmd == "move" then
    CB:SetUnlocked(true)
  elseif cmd == "lock" then
    CB:SetUnlocked(false)
  elseif cmd == "reset" then
    CB:ResetSettings()
    CB:Print("All settings restored to default.")
  elseif cmd == "summary" or cmd == "loot" then
    CB:OpenSummary(CB.db.lastLoot)
  elseif cmd == "news" then
    if not CB:ShowNews() then CB:Print("No release notes for this version.") end
  else
    for _, line in ipairs(HELP) do CB:Print(line) end
  end
end
