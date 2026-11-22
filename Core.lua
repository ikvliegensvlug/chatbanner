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
  rowHeight = 34,
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
  sources = {
    whisper = true, party = true, raid = true, guild = true, officer = true,
    say = true, yell = true, emote = true, channel = true, npc = true,
    boss = true, battleground = true, system = true,
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

function CB:ResetSettings()
  wipe(ChatBannerDB)
  merge(ChatBannerDB, self.defaults)
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
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON then
    ChatBannerDB = ChatBannerDB or {}
    merge(ChatBannerDB, CB.defaults)
    CB.db = ChatBannerDB
    CB:InitAlerts()
  elseif event == "PLAYER_LOGIN" then
    CB:InitOptions()
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
  "/chatbanner  - open the options",
  "/chatbanner test  - show sample alerts",
  "/chatbanner unlock  - drag the alerts to a new spot (lock to finish)",
  "/chatbanner reset  - restore all default settings",
}

SLASH_CHATBANNER1 = "/chatbanner"
SLASH_CHATBANNER2 = "/cbanner"
SlashCmdList.CHATBANNER = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  if cmd == "" or cmd == "options" or cmd == "config" then
    CB:OpenOptions()
  elseif cmd == "test" then
    CB:Test()
  elseif cmd == "unlock" or cmd == "move" then
    CB:SetUnlocked(true)
  elseif cmd == "lock" then
    CB:SetUnlocked(false)
  elseif cmd == "reset" then
    CB:ResetSettings()
    CB:Print("All settings restored to default.")
  else
    for _, line in ipairs(HELP) do CB:Print(line) end
  end
end
