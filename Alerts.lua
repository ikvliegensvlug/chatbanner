-- ChatBanner: the alerts themselves. Listens to chat events and shows a stack of
-- clickable alerts. Left-click replies in the same channel, right-click dismisses.
local _, ns = ...
local CB = ns.CB

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GAP = 6
local FADE = 0.6

-- event -> source (options key), tag text, ChatTypeInfo key, how a click replies.
-- noSender: the message already names who did it (system text, emotes).
local EVENTS = {
  CHAT_MSG_WHISPER           = { source = "whisper", tag = "Whisper", chat = "WHISPER", reply = "tell" },
  CHAT_MSG_BN_WHISPER        = { source = "whisper", tag = "Whisper", chat = "BN_WHISPER", reply = "bnet" },
  CHAT_MSG_PARTY             = { source = "party", tag = "Party", chat = "PARTY", reply = "/p " },
  CHAT_MSG_PARTY_LEADER      = { source = "party", tag = "Party", chat = "PARTY_LEADER", reply = "/p " },
  CHAT_MSG_RAID              = { source = "raid", tag = "Raid", chat = "RAID", reply = "/ra " },
  CHAT_MSG_RAID_LEADER       = { source = "raid", tag = "Raid", chat = "RAID_LEADER", reply = "/ra " },
  CHAT_MSG_RAID_WARNING      = { source = "raid", tag = "Warning", chat = "RAID_WARNING", reply = "/ra " },
  CHAT_MSG_GUILD             = { source = "guild", tag = "Guild", chat = "GUILD", reply = "/g " },
  CHAT_MSG_GUILD_ACHIEVEMENT = { source = "guild", tag = "Guild", chat = "GUILD" },
  CHAT_MSG_OFFICER           = { source = "officer", tag = "Officer", chat = "OFFICER", reply = "/o " },
  CHAT_MSG_SAY               = { source = "say", tag = "Say", chat = "SAY", reply = "/s " },
  CHAT_MSG_YELL              = { source = "yell", tag = "Yell", chat = "YELL", reply = "/y " },
  CHAT_MSG_EMOTE             = { source = "emote", tag = "Emote", chat = "EMOTE" },
  CHAT_MSG_TEXT_EMOTE        = { source = "emote", tag = "Emote", chat = "TEXT_EMOTE", noSender = true },
  CHAT_MSG_CHANNEL           = { source = "channel", tag = "Channel", chat = "CHANNEL", reply = "channel" },
  CHAT_MSG_MONSTER_SAY       = { source = "npc", tag = "NPC", chat = "MONSTER_SAY" },
  CHAT_MSG_MONSTER_YELL      = { source = "npc", tag = "NPC", chat = "MONSTER_YELL" },
  CHAT_MSG_MONSTER_WHISPER   = { source = "npc", tag = "NPC", chat = "MONSTER_WHISPER" },
  CHAT_MSG_MONSTER_EMOTE     = { source = "npc", tag = "NPC", chat = "MONSTER_EMOTE", noSender = true },
  CHAT_MSG_RAID_BOSS_EMOTE   = { source = "boss", tag = "Boss", chat = "RAID_BOSS_EMOTE", noSender = true },
  CHAT_MSG_RAID_BOSS_WHISPER = { source = "boss", tag = "Boss", chat = "RAID_BOSS_WHISPER" },
  CHAT_MSG_BG_SYSTEM_NEUTRAL = { source = "battleground", tag = "Battleground", chat = "BG_SYSTEM_NEUTRAL", noSender = true },
  CHAT_MSG_BG_SYSTEM_ALLIANCE = { source = "battleground", tag = "Battleground", chat = "BG_SYSTEM_ALLIANCE", noSender = true },
  CHAT_MSG_BG_SYSTEM_HORDE   = { source = "battleground", tag = "Battleground", chat = "BG_SYSTEM_HORDE", noSender = true },
  CHAT_MSG_SYSTEM            = { source = "system", tag = "System", chat = "SYSTEM", noSender = true },
  -- loot rolls: the item you can roll on, and who won it (other loot lines stay in chat)
  START_LOOT_ROLL            = { source = "loot", tag = "Roll", chat = "LOOT", noSender = true },
  CHAT_MSG_LOOT              = { source = "loot", tag = "Roll", chat = "LOOT", noSender = true, rollsOnly = true },
}
CB.EVENTS = EVENTS

-- Quest progress ("Kobold Vermin slain: 3/10") arrives as a system message.
-- It gets its own source, so the kill counter can be off while system messages stay on.
local QUEST = { source = "quest", tag = "Quest", chat = "SYSTEM", noSender = true }
CB.QUEST = QUEST

-- "Bram: Need on [Ironfoe]", from a loot line
local NEED = { source = "loot", tag = "Need", chat = "LOOT" }

-- The game's own (translated) texts, with English fallbacks.
local QUEST_FORMATS = {
  { "ERR_QUEST_ADD_KILL_SII",         "%s slain: %d/%d" },
  { "ERR_QUEST_ADD_PLAYER_KILL_SII",  "Players slain: %d/%d" },
  { "ERR_QUEST_ADD_ITEM_SII",         "%s: %d/%d" },
  { "ERR_QUEST_ADD_FOUND_SII",        "%s: %d/%d" },
  { "ERR_QUEST_OBJECTIVE_COMPLETE_S", "%s (Complete)" },
  { "ERR_QUEST_UNKNOWN_COMPLETE",     "Objective Complete." },
}

-- "%s slain: %d/%d" -> "^.+ slain: %d+/%d+$"
local function toPattern(fmt)
  local p = fmt:gsub("%%%d?%$?s", "<<S>>"):gsub("%%%d?%$?d", "<<D>>")
  p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  p = p:gsub("<<S>>", ".+"):gsub("<<D>>", "%%d+")
  return "^" .. p .. "$"
end
CB.ToPattern = toPattern

local questPatterns
local function isQuestProgress(text)
  if type(text) ~= "string" then return false end
  if not questPatterns then
    questPatterns = {}
    for _, f in ipairs(QUEST_FORMATS) do
      local fmt = _G[f[1]]
      questPatterns[#questPatterns + 1] = toPattern(type(fmt) == "string" and fmt or f[2])
    end
  end
  for _, p in ipairs(questPatterns) do
    if text:find(p) then return true end
  end
  return false
end
CB.IsQuestProgress = isQuestProgress

-- "Roll for [Item]" when a roll window opens; the link shows in the item's quality colour.
local function rollText(rollID)
  local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
  if not link and GetLootRollItemInfo then
    local _, name, count = GetLootRollItemInfo(rollID)
    if name then link = "[" .. name .. "]" .. ((count or 1) > 1 and (" x" .. count) or "") end
  end
  return link and ("Roll for " .. link) or nil
end

-- Chat text the game keeps secret from add-ons (in dungeon fights on this client).
local function isSecret(v)
  return v ~= nil and issecretvalue ~= nil and issecretvalue(v) and true or false
end
CB.IsSecret = isSecret

local holder, mover
local active, pool = {}, {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function fontPath()
  for _, f in ipairs(CB.FONTS) do
    if f.key == CB.db.font then return f.path end
  end
  return CB.FONTS[1].path
end

local function shortName(sender)
  if not sender or sender == "" then return nil end
  if Ambiguate then return Ambiguate(sender, "short") end
  return (sender:gsub("%-.*$", ""))
end

local function chatColor(chat)
  local info = ChatTypeInfo and ChatTypeInfo[chat]
  if info and info.r then return info.r, info.g, info.b end
  return 0.9, 0.9, 0.9
end

-- Background plus four 1-pixel edges.
local function addBox(frame)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetTexture(WHITE)
  frame.bg:SetAllPoints()
  frame.edges = {}
  for i = 1, 4 do
    local e = frame:CreateTexture(nil, "BORDER")
    e:SetTexture(WHITE)
    frame.edges[i] = e
  end
  local e = frame.edges
  e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(1)
  e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(1)
  e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(1)
  e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(1)
end

local function edgeColor(frame, r, g, b, a)
  for i = 1, 4 do frame.edges[i]:SetVertexColor(r, g, b, a) end
end

-- Normal edge colour of an alert, depending on the border style.
local function restEdge(t)
  local mode = CB.db.border
  if mode == "type" then
    edgeColor(t, t.r or 1, t.g or 1, t.b or 1, 0.9)
  elseif mode == "none" then
    edgeColor(t, 0, 0, 0, 0)
  else
    edgeColor(t, 1, 1, 1, 0.16)
  end
end

---------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------
local function reply(t)
  local r = t.reply
  if not r then return end
  if r == "tell" then
    if ChatFrame_SendTell then ChatFrame_SendTell(t.sender) end
  elseif r == "bnet" then
    if ChatFrame_SendBNetTell then ChatFrame_SendBNetTell(t.sender) end
  elseif r == "channel" then
    if t.channelNum and ChatFrame_OpenChat then ChatFrame_OpenChat("/" .. t.channelNum .. " ") end
  elseif ChatFrame_OpenChat then
    ChatFrame_OpenChat(r)
  end
end

---------------------------------------------------------------------------
-- One alert
---------------------------------------------------------------------------
-- Size of the label text (channel tag and age), following the font size.
function CB:LabelSize()
  return math.max(6, math.floor(self.db.fontSize * 0.8 + 0.5))
end

-- Height of one alert. Never smaller than what the text and label need;
-- with autoHeight it grows and shrinks along with the font size.
function CB:RowHeight()
  local db = self.db
  local needed = math.max(db.fontSize, self:LabelSize() + 8) + 8
  if db.autoHeight then
    return math.max(needed, math.floor(db.fontSize * 2.4 + 0.5))
  end
  return math.max(needed, db.rowHeight)
end

local function styleAlert(t)
  local db = CB.db
  local font, size, label = fontPath(), db.fontSize, CB:LabelSize()
  local rowH = CB:RowHeight()
  t:SetSize(db.width, rowH)
  t.bg:SetVertexColor(0, 0, 0, db.bgAlpha)
  restEdge(t)
  t.tag:SetFont(font, label, "")
  t.msg:SetFont(font, size, "")
  t.age:SetFont(font, label, "")
  -- the label box hugs its text, so it fits at every font and label size
  t.tagBox:SetHeight(math.min(rowH - 4, label + 10))
  t.tagBox:SetWidth(t.tag:GetStringWidth() + label + 4)
  t.tagBox:SetShown(db.showTag)
  t.msg:ClearAllPoints()
  if db.showTag then
    t.msg:SetPoint("LEFT", t.tagBox, "RIGHT", 10, 0)
  else
    t.msg:SetPoint("LEFT", t, "LEFT", 12, 0)
  end
  t.msg:SetPoint("RIGHT", t, "RIGHT", -(14 + math.ceil(label * 3)), 0)
end

local function makeAlert()
  local t = CreateFrame("Button", nil, holder)
  addBox(t)
  t.tagBox = CreateFrame("Frame", nil, t)
  t.tagBox:SetPoint("LEFT", 10, 0)
  addBox(t.tagBox)
  t.tagBox.bg:SetVertexColor(0, 0, 0, 0)
  t.tag = t.tagBox:CreateFontString(nil, "OVERLAY")
  t.tag:SetPoint("CENTER")
  t.msg = t:CreateFontString(nil, "OVERLAY")
  t.msg:SetJustifyH("LEFT")
  t.msg:SetWordWrap(false)
  t.age = t:CreateFontString(nil, "OVERLAY")
  t.age:SetPoint("RIGHT", -10, 0)
  t.age:SetTextColor(0.55, 0.56, 0.58)
  for _, fs in ipairs({ t.tag, t.msg, t.age }) do
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
  end
  t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  t:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then reply(self) end
    self.expire = 0
  end)
  t:SetScript("OnEnter", function(self)
    self.hover = true
    edgeColor(self, 1, 1, 1, 1)
  end)
  t:SetScript("OnLeave", function(self)
    self.hover = false
    restEdge(self)
  end)
  t:Hide()
  styleAlert(t)
  return t
end

local function stack()
  local step = CB:RowHeight() + GAP
  for i, t in ipairs(active) do
    t:ClearAllPoints()
    if CB.db.growUp then
      t:SetPoint("BOTTOM", holder, "BOTTOM", 0, (i - 1) * step)
    else
      t:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * step)
    end
  end
end

local function release(t)
  for i, x in ipairs(active) do
    if x == t then table.remove(active, i) break end
  end
  t:Hide()
  pool[#pool + 1] = t
  stack()
end

local function tick()
  local now = GetTime()
  for i = #active, 1, -1 do
    local t = active[i]
    if t.hover then t.expire = math.max(t.expire, now + 2) end
    local left = t.expire - now
    if left <= 0 then
      release(t)
    else
      t:SetAlpha(left < FADE and left / FADE or 1)
      local age = math.floor(now - t.born)
      t.age:SetText(age < 2 and "now" or (age .. "s"))
    end
  end
  if #active == 0 then holder:SetScript("OnUpdate", nil) end
end

-- Show one alert. info = EVENTS entry; extra = { tag = "Trade", channelNum = 2, duration = 30 }
function CB:Show(info, text, sender, extra)
  local db = self.db
  local t = table.remove(pool) or makeAlert()
  styleAlert(t)
  t.reply, t.sender = info.reply, sender
  t.channelNum = extra and extra.channelNum
  local r, g, b = chatColor(info.chat)
  t.r, t.g, t.b = r, g, b
  t.tag:SetText((extra and extra.tag) or info.tag)
  t.tag:SetTextColor(r, g, b)
  t.tagBox:SetWidth(t.tag:GetStringWidth() + self:LabelSize() + 4)
  edgeColor(t.tagBox, r, g, b, 0.9)
  restEdge(t)

  -- a secret sender (see onEvent) can be shown but not shortened
  local name = (info.reply == "bnet" or isSecret(sender)) and sender or shortName(sender)
  if name and not info.noSender then
    t.msg:SetText("|cffffffff" .. name .. "|r: " .. text)
  else
    t.msg:SetText(text)
  end
  if db.colorText then t.msg:SetTextColor(r, g, b) else t.msg:SetTextColor(0.93, 0.93, 0.93) end

  t.born = GetTime()
  t.expire = t.born + ((extra and extra.duration) or db.duration)
  t.hover = false
  t:SetAlpha(1)
  t:Show()
  table.insert(active, 1, t)
  while #active > db.maxAlerts do release(active[#active]) end
  stack()
  holder:SetScript("OnUpdate", tick)

  if db.sound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
    PlaySound(SOUNDKIT.TELL_MESSAGE, "Master")
  end
end

---------------------------------------------------------------------------
-- Chat events
---------------------------------------------------------------------------
-- Run the chat filters of Blizzard and other add-ons: what your chat hides,
-- ChatBanner does not show either. Returns nil when filtered, else the arguments.
local function runFilters(event, ...)
  local args, n = { ... }, select("#", ...)
  local filters = ChatFrame_GetMessageEventFilters and ChatFrame_GetMessageEventFilters(event)
  if filters then
    for _, filter in ipairs(filters) do
      local res = { pcall(filter, DEFAULT_CHAT_FRAME, event, unpack(args, 1, n)) }
      if res[1] then
        if res[2] then return nil end
        if res[3] ~= nil then
          for i = 3, #res do args[i - 2] = res[i] end
        end
      end
    end
  end
  return args
end

-- One line of plain text, or nil when nothing readable is left.
local function clean(text, info, sender)
  if type(text) ~= "string" then return nil end
  if info.noSender and sender and text:find("%%s") then
    text = text:gsub("%%s", shortName(sender) or sender)
  end
  text = text:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  if not plain:find("%S") then return nil end
  return text
end
CB.CleanText = clean

function CB:NoteError(err)
  self.lastError = tostring(err)
  if self.db and self.db.debug then
    local log = self.db.debug.errors or {}
    self.db.debug.errors = log
    log[#log + 1] = self.lastError
    while #log > 10 do table.remove(log, 1) end
  end
end

local function onEvent(_, event, ...)
  local info = EVENTS[event]
  if not info then return end

  -- In a dungeon fight the game may hand add-ons "secret" chat text: it can be
  -- shown, but not read or compared, so no quest check, filters or roll parsing.
  local first, second = ...
  if isSecret(first) or isSecret(second) then
    if info.rollsOnly or event == "CHAT_MSG_SYSTEM" or event == "START_LOOT_ROLL" then return end
    if not CB.db.sources[info.source] then return end
    CB:Show(info, first, second)
    return
  end
  if event == "CHAT_MSG_SYSTEM" and isQuestProgress((...)) then info = QUEST end
  if not CB.db.sources[info.source] then return end
  if event == "START_LOOT_ROLL" then
    local text = rollText((...))
    if text then CB:Show(info, text) end
    return
  end
  local roll
  if info.rollsOnly then
    -- of all loot lines only "X selected Need", "X won" and "Everyone passed" alert
    roll = CB.ParseRoll and CB.ParseRoll((...))
    if roll and CB.NoteRoll then CB:NoteRoll(roll) end   -- remembered for "X won (Need 87)"
    if not roll or not (roll.kind == "need" or roll.kind == "won" or roll.kind == "passed") then return end
  end
  local args = runFilters(event, ...)
  if not args then return end
  local text, sender = args[1], args[2]
  -- the [Loot] link in front of roll lines on this client: the alert shows the line itself
  if roll and type(text) == "string" and CB.StripLootHistory then text = CB.StripLootHistory(text) end

  -- your own messages (whispering yourself still alerts, handy for testing)
  if CB.db.ignoreOwn and info.reply and info.reply ~= "tell" and info.reply ~= "bnet" then
    local me = UnitName("player")
    if me and shortName(sender) == me then return end
  end

  text = clean(text, info, sender)
  if not text then return end

  if roll then
    if roll.kind == "need" then
      CB:Show(NEED, "Need on " .. roll.link, roll.who)
      return
    elseif roll.kind == "won" then
      local r = CB.RollOf and CB:RollOf(roll.link, roll.who)
      if r then text = text .. " (" .. r.kind .. " " .. r.roll .. ")" end
    end
  end

  local extra
  if event == "CHAT_MSG_CHANNEL" then
    local channelName = args[9]
    extra = {
      tag = (type(channelName) == "string" and channelName:match("^([^%s%-]+)")) or info.tag,
      channelNum = args[8],
    }
  end
  CB:Show(info, text, sender, extra)
end

---------------------------------------------------------------------------
-- Position, size and moving
---------------------------------------------------------------------------
function CB:ApplyLayout()
  local db = self.db
  holder:SetScale(db.scale)
  holder:SetSize(db.width, (self:RowHeight() + GAP) * db.maxAlerts)
  holder:ClearAllPoints()
  local p = db.position
  if p then
    holder:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    holder:SetPoint("TOP", UIParent, "TOP", 0, -60)
  end
  for _, t in ipairs(active) do styleAlert(t) end
  for _, t in ipairs(pool) do styleAlert(t) end
  while #active > db.maxAlerts do release(active[#active]) end
  stack()
end

function CB:ResetPosition()
  self.db.position = false
  self:ApplyLayout()
end

---------------------------------------------------------------------------
-- Resizing: the corner grip changes the scale, so width, height, text and
-- spacing all grow and shrink together. The top-left corner stays put.
---------------------------------------------------------------------------
local MIN_SCALE, MAX_SCALE = 0.5, 2

local function cursorX()
  local x = GetCursorPosition()
  return x / UIParent:GetEffectiveScale()
end

function CB:StartResize()
  local s = holder:GetScale()
  -- top-left corner in UIParent units
  self.resizing = { left = holder:GetLeft() * s, top = holder:GetTop() * s }
end

-- Scale so that the right edge lands at x (UIParent units).
function CB:ResizeTo(x)
  local r = self.resizing
  if not r then return end
  local s = (x - r.left) / self.db.width
  s = math.max(MIN_SCALE, math.min(MAX_SCALE, s))
  s = math.floor(s * 20 + 0.5) / 20               -- same 5% steps as the slider
  self.db.scale = s
  self.db.position = { "TOPLEFT", "BOTTOMLEFT",
    math.floor(r.left / s + 0.5), math.floor(r.top / s + 0.5) }
  self:ApplyLayout()
end

function CB:StopResize()
  if not self.resizing then return end
  self.resizing = nil
  if self.RefreshOptions then self:RefreshOptions() end
end

function CB:SetUnlocked(on)
  self.unlocked = on and true or false
  if not self.unlocked then self:StopResize() end
  mover:SetShown(self.unlocked)
  if self.unlocked then
    self:Print("Drag the box to move the alerts, drag its corner to resize. Type /chatbanner lock when done.")
  end
  if self.RefreshOptions then self:RefreshOptions() end
  if self.RefreshSetup then self:RefreshSetup() end
end

function CB:Test()
  local E = EVENTS
  self:Show(E.CHAT_MSG_SYSTEM, "Thrall has come online.")
  self:Show(E.CHAT_MSG_MONSTER_YELL, "Honor your heroes!", "Herald of Thrall")
  self:Show(E.CHAT_MSG_CHANNEL, "LFM Ragefire Chasm, need 1 tank", "Lisa", { tag = "Trade", channelNum = 2 })
  self:Show(E.CHAT_MSG_GUILD, "anyone doing Leatherworking?", "Joost")
  self:Show(E.CHAT_MSG_WHISPER, "coming along to Wailing Caverns?", "Bram")
end

function CB:InitAlerts()
  holder = CreateFrame("Frame", "ChatBannerFrame", UIParent)
  holder:SetFrameStrata("HIGH")
  holder:SetMovable(true)
  holder:SetClampedToScreen(true)

  mover = CreateFrame("Frame", nil, holder)
  mover:SetAllPoints()
  mover:SetFrameLevel(holder:GetFrameLevel() + 20)
  addBox(mover)
  mover.bg:SetVertexColor(0.2, 0.6, 1, 0.25)
  edgeColor(mover, 0.2, 0.6, 1, 1)
  local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("CENTER")
  label:SetText("ChatBanner: drag to move, drag the corner to resize")
  mover:EnableMouse(true)
  mover:RegisterForDrag("LeftButton")
  mover:SetScript("OnDragStart", function() holder:StartMoving() end)
  mover:SetScript("OnDragStop", function()
    holder:StopMovingOrSizing()
    local p, _, rp, x, y = holder:GetPoint()
    CB.db.position = { p, rp, math.floor(x + 0.5), math.floor(y + 0.5) }
  end)

  -- resize grip in the bottom-right corner
  local grip = CreateFrame("Button", nil, mover)
  grip:SetSize(18, 18)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(mover:GetFrameLevel() + 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(self)
    CB:StartResize()
    self:SetScript("OnUpdate", function() CB:ResizeTo(cursorX()) end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    CB:StopResize()
  end)
  CB.resizeGrip = grip
  mover:Hide()

  self:ApplyLayout()

  local ev = CreateFrame("Frame")
  for event in pairs(EVENTS) do pcall(ev.RegisterEvent, ev, event) end
  -- an error here must never interrupt play: keep it for /chatbanner debug instead
  ev:SetScript("OnEvent", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok then CB:NoteError(err) end
  end)
end
