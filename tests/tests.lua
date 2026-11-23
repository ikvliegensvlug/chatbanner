-- ChatBanner tests. Run with: npm test
local ns = {}
for _, file in ipairs(TOC_FILES) do
  local chunk = assert(load(readfile(ROOT .. "/" .. file), "@" .. file))
  chunk("ChatBanner", ns)
end
local CB = ns.CB
local setupOpenedAtFirstLogin   -- filled in right after the login below

local passed, failed = 0, 0
local function check(cond, msg)
  if not cond then error(msg or "check failed", 2) end
end

local function alerts()
  local list = {}
  for _, f in ipairs(AllFrames) do
    if f.kind == "Button" and f.parent == _G.ChatBannerFrame and f.shown then list[#list + 1] = f end
  end
  return list
end

local function msgOf(a)
  -- the message font string is the one whose text is not a tag or age
  return a.msg and a.msg.text
end

local function clearAlerts()
  local holder = _G.ChatBannerFrame
  Advance(1000)
  if holder.scripts.OnUpdate then holder.scripts.OnUpdate(holder, 0) end
end

local function test(name, fn)
  CB:ResetSettings()
  clearAlerts()
  Calls, Filters, Printed = {}, {}, {}
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("ok    " .. name)
  else
    failed = failed + 1
    print("FAIL  " .. name .. "\n      " .. tostring(err))
  end
end

-- start-up -------------------------------------------------------------------
Fire("ADDON_LOADED", "ChatBanner")
Fire("PLAYER_LOGIN")
setupOpenedAtFirstLogin = _G.ChatBannerSetup and _G.ChatBannerSetup.shown

test("settings are created with defaults", function()
  check(ChatBannerDB.width == 600, "width default")
  check(ChatBannerDB.sources.guild == true, "guild on by default")
  check(CB.db == ChatBannerDB, "db points at saved variables")
end)

test("options panel is registered under AddOns", function()
  check(Settings.registered and Settings.registered.name == "ChatBanner", "category registered")
  CB:RefreshOptions()
end)

test("/chatbanner opens the options", function()
  SlashCmdList.CHATBANNER("")
  check(Settings.opened == 42, "OpenToCategory called with the category id")
end)

test("a whisper shows an alert with the sender and text", function()
  Fire("CHAT_MSG_WHISPER", "hi there", "Bram-Realm")
  local a = alerts()
  check(#a == 1, "one alert, got " .. #a)
  check(msgOf(a[1]):find("Bram|r: hi there", 1, true), "message text: " .. tostring(msgOf(a[1])))
end)

test("left-click on a whisper replies, right-click dismisses", function()
  Fire("CHAT_MSG_WHISPER", "hi", "Bram")
  local a = alerts()[1]
  a:Click("LeftButton")
  check(Calls[1] == "tell:Bram", "reply opened: " .. tostring(Calls[1]))
  Fire("CHAT_MSG_GUILD", "yo", "Joost")
  for _, g in ipairs(alerts()) do
    if msgOf(g):find("yo", 1, true) then g:Click("RightButton") end
  end
  local holder = _G.ChatBannerFrame
  holder.scripts.OnUpdate(holder, 0)
  check(#alerts() == 0, "all alerts gone")
end)

test("a source switched off gives no alert", function()
  CB.db.sources.guild = false
  Fire("CHAT_MSG_GUILD", "hello", "Joost")
  check(#alerts() == 0, "guild alert should be skipped")
  Fire("CHAT_MSG_PARTY", "hello", "Lisa")
  check(#alerts() == 1, "party still alerts")
end)

test("own messages are skipped, unless the option is off", function()
  Fire("CHAT_MSG_PARTY", "my own", "Aztek")
  check(#alerts() == 0, "own party message skipped")
  CB.db.ignoreOwn = false
  Fire("CHAT_MSG_PARTY", "my own", "Aztek")
  check(#alerts() == 1, "own message shown when option is off")
end)

test("empty and whitespace-only messages give no alert", function()
  Fire("CHAT_MSG_SYSTEM", "")
  Fire("CHAT_MSG_SYSTEM", "  \n  ")
  Fire("CHAT_MSG_SYSTEM", "|cffffff00|r")
  check(#alerts() == 0, "no empty alerts, got " .. #alerts())
end)

test("multi-line messages become one line", function()
  Fire("CHAT_MSG_SYSTEM", "line one\nline two")
  check(msgOf(alerts()[1]) == "line one line two", "got " .. tostring(msgOf(alerts()[1])))
end)

test("text emotes fill in the sender name", function()
  Fire("CHAT_MSG_TEXT_EMOTE", "%s laughs at you.", "Bram-Realm")
  check(msgOf(alerts()[1]) == "Bram laughs at you.", "got " .. tostring(msgOf(alerts()[1])))
end)

test("messages hidden by a chat filter give no alert", function()
  Filters.CHAT_MSG_CHANNEL = { function(_, _, text) return text:find("spam") ~= nil end }
  Fire("CHAT_MSG_CHANNEL", "buy gold spam", "Bot", "", "2. Trade - City", "", "", 0, 2, "Trade - City")
  check(#alerts() == 0, "filtered message skipped")
  Fire("CHAT_MSG_CHANNEL", "LFM RFC", "Lisa", "", "2. Trade - City", "", "", 0, 2, "Trade - City")
  local a = alerts()
  check(#a == 1, "normal channel message shown")
  check(a[1].tag.text == "Trade", "channel label: " .. tostring(a[1].tag.text))
  a[1]:Click("LeftButton")
  check(Calls[1] == "open:/2 ", "reply in channel 2: " .. tostring(Calls[1]))
end)

test("only the newest alerts stay when over the maximum", function()
  CB.db.maxAlerts = 2
  CB:ApplyLayout()
  Fire("CHAT_MSG_SAY", "one", "A")
  Fire("CHAT_MSG_SAY", "two", "B")
  Fire("CHAT_MSG_SAY", "three", "C")
  check(#alerts() == 2, "two alerts, got " .. #alerts())
end)

test("alerts disappear after the chosen time", function()
  CB.db.duration = 5
  Fire("CHAT_MSG_YELL", "hey", "A")
  local holder = _G.ChatBannerFrame
  Advance(4)
  holder.scripts.OnUpdate(holder, 0)
  check(#alerts() == 1, "still there after 4 s")
  Advance(2)
  holder.scripts.OnUpdate(holder, 0)
  check(#alerts() == 0, "gone after 6 s")
end)

test("layout settings resize the alerts", function()
  CB.db.width, CB.db.rowHeight, CB.db.scale = 900, 50, 1.5
  CB.db.autoHeight = false
  CB:ApplyLayout()
  local holder = _G.ChatBannerFrame
  check(holder.w == 900 and holder.scale == 1.5, "holder size/scale")
  Fire("CHAT_MSG_SAY", "big", "A")
  local a = alerts()[1]
  check(a.w == 900 and a.h == 50, "alert size " .. a.w .. "x" .. a.h)
end)

test("sound plays only when switched on", function()
  SoundsPlayed = 0
  Fire("CHAT_MSG_SAY", "quiet", "A")
  check(SoundsPlayed == 0, "no sound by default")
  CB.db.sound = true
  Fire("CHAT_MSG_SAY", "loud", "A")
  check(SoundsPlayed == 1, "sound when on")
end)

test("/chatbanner test shows sample alerts", function()
  SlashCmdList.CHATBANNER("test")
  check(#alerts() == 5, "five samples, got " .. #alerts())
end)

test("unlock and reset position", function()
  SlashCmdList.CHATBANNER("unlock")
  check(CB.unlocked == true, "unlocked")
  CB.db.position = { "CENTER", "CENTER", 10, 20 }
  CB:ResetPosition()
  check(CB.db.position == false, "position reset")
  SlashCmdList.CHATBANNER("lock")
  check(CB.unlocked == false, "locked")
end)

test("options panel controls change the settings", function()
  local sliders, boxes = {}, {}
  for _, f in ipairs(AllFrames) do
    if f.kind == "Slider" then sliders[#sliders + 1] = f end
    if f.kind == "CheckButton" then boxes[#boxes + 1] = f end
  end
  check(#sliders == 7, "7 sliders, got " .. #sliders)
  -- grow upwards + one per source + row height follows font, label, colour, sound, own messages, loot summary
  check(#boxes == 1 + #CB.SOURCES + 6 + #CB.SETUP_GROUPS, "checkboxes, got " .. #boxes)
  CB:RefreshOptions()
  check(sliders[1].value == 600, "width slider shows the setting")
  sliders[1]:SetValue(803)          -- snaps to the 10-step
  check(CB.db.width == 800, "width set to " .. tostring(CB.db.width))
  check(_G.ChatBannerFrame.w == 800, "alerts resized")
  local whisperBox = boxes[3]        -- order: follow font size, grow upwards, then the sources
  whisperBox:SetChecked(false)
  whisperBox:Click()
  check(CB.db.sources.whisper == false, "whisper switched off")
  Fire("CHAT_MSG_WHISPER", "hi", "Bram")
  check(#alerts() == 0, "no whisper alert after switching it off")
end)

test("reset restores every default", function()
  CB.db.width = 1234
  CB.db.sources.system = false
  SlashCmdList.CHATBANNER("reset")
  check(CB.db.width == 600 and CB.db.sources.system == true, "defaults back")
end)

test("row height follows the font size by default", function()
  check(CB:RowHeight() == 34, "default row 34, got " .. CB:RowHeight())
  CB.db.fontSize = 28
  CB:ApplyLayout()
  Fire("CHAT_MSG_SAY", "big text", "A")
  local a = alerts()[1]
  check(a.h == 67, "row grows with the font, got " .. a.h)
  check(a.tagBox.h >= CB:LabelSize() + 6 and a.tagBox.h <= a.h - 4, "label box fits in the row")
  check(a.tagBox.w > a.tag:GetStringWidth() + CB:LabelSize(), "label box wider than its text")
  check(_G.ChatBannerFrame.h == (67 + 6) * CB.db.maxAlerts, "holder fits all rows")
end)

test("a fixed row height never cuts off the text", function()
  CB.db.autoHeight, CB.db.rowHeight, CB.db.fontSize = false, 20, 24
  CB:ApplyLayout()
  Fire("CHAT_MSG_GUILD", "hello", "A")
  local a = alerts()[1]
  check(a.h >= 24 + 8, "row at least font + padding, got " .. a.h)
  check(a.tagBox.h <= a.h - 4, "label box inside the row")
end)

test("the label and its box grow with the font size", function()
  Fire("CHAT_MSG_GUILD", "hello", "A")
  local a = alerts()[1]
  local smallW = a.tagBox.w
  CB.db.fontSize = 26
  CB:ApplyLayout()
  check(CB:LabelSize() == 21, "label size 21, got " .. CB:LabelSize())
  check(a.tagBox.w > smallW, "label box grows with the label")
end)

test("row height slider is greyed out while it follows the font", function()
  local sliders = {}
  for _, f in ipairs(AllFrames) do
    if f.kind == "Slider" then sliders[#sliders + 1] = f end
  end
  CB:RefreshOptions()
  local row = sliders[2]
  check(row.disabled == true, "disabled with autoHeight")
  CB.db.autoHeight = false
  CB:RefreshOptions()
  check(not row.disabled, "enabled without autoHeight")
end)

local function setupBoxes()
  local list = {}
  for _, f in ipairs(AllFrames) do
    if f.kind == "CheckButton" and f.parent == _G.ChatBannerSetup then list[#list + 1] = f end
  end
  return list
end

local function closeSetup()
  local s = _G.ChatBannerSetup
  s:Hide()
  s.scripts.OnHide(s)
end

test("the quick setup opens on the first login", function()
  check(setupOpenedAtFirstLogin == true, "setup shown at first login")
  closeSetup()
  check(CB.db.setupDone == true, "closing marks the setup as done")
  CB:MaybeSetup()
  check(not _G.ChatBannerSetup.shown, "not shown again once done")
end)

test("hiding the whole UI does not count as finishing the setup", function()
  ChatBannerDB.setupDone = nil
  CB:OpenSetup()
  local s = _G.ChatBannerSetup
  s.scripts.OnHide(s)                -- parent hidden: the frame itself stays shown
  check(ChatBannerDB.setupDone == nil, "not marked done")
  closeSetup()
  check(ChatBannerDB.setupDone == true, "done after the player closes it")
end)

test("the setup points to the full options", function()
  CB:OpenSetup()
  local hint = _G.ChatBannerSetup.hint.text
  check(hint:find("Options > AddOns > ChatBanner", 1, true), "options path named")
  check(hint:find("/chatbanner", 1, true), "command named")
  closeSetup()
end)

test("the resize corner scales the alerts and keeps the top-left corner", function()
  local holder = _G.ChatBannerFrame
  CB.db.width = 600
  CB:ApplyLayout()
  CB:SetUnlocked(true)
  holder.left, holder.top = 100, 800          -- top-left corner on screen, scale 1
  local grip = CB.resizeGrip
  grip.scripts.OnMouseDown(grip)
  CursorX = 100 + 900                         -- drag the right edge to 1.5x the width
  grip.scripts.OnUpdate(grip, 0)
  check(CB.db.scale == 1.5, "scale 1.5, got " .. tostring(CB.db.scale))
  check(holder.scale == 1.5, "holder scaled")
  check(CB.db.width == 600 and CB:RowHeight() == 34, "width and rows keep their proportions")
  local p = CB.db.position
  check(p[1] == "TOPLEFT" and p[2] == "BOTTOMLEFT", "anchored at the top-left")
  check(math.abs(p[3] * 1.5 - 100) < 1 and math.abs(p[4] * 1.5 - 800) < 1, "top-left corner stays put")
  CursorX = 100 + 100                         -- far too small: clamped
  grip.scripts.OnUpdate(grip, 0)
  check(CB.db.scale == 0.5, "never below 50%, got " .. tostring(CB.db.scale))
  CursorX = 100 + 5000
  grip.scripts.OnUpdate(grip, 0)
  check(CB.db.scale == 2, "never above 200%")
  grip.scripts.OnMouseUp(grip)
  check(CB.resizing == nil, "resize finished")
  CB:SetUnlocked(false)
end)

test("moving ends when the options close or the settings are reset", function()
  local panel = _G.ChatBannerOptions
  local mover = CB.resizeGrip.parent
  CB:SetUnlocked(true)
  check(mover.shown, "mover shown while unlocked")
  panel.scripts.OnHide(panel)
  check(not CB.unlocked and not mover.shown, "locked when the options close")
  CB:OpenSetup()
  CB:SetUnlocked(true)
  panel.scripts.OnHide(panel)
  check(CB.unlocked, "stays unlocked while the quick setup is open")
  closeSetup()
  check(not CB.unlocked, "locked when the setup closes")
  CB:SetUnlocked(true)
  CB:ResetSettings()
  check(not CB.unlocked and not mover.shown, "locked after a reset")
end)

test("/chatbanner setup opens it again", function()
  closeSetup()
  SlashCmdList.CHATBANNER("setup")
  check(_G.ChatBannerSetup.shown, "setup shown")
  closeSetup()
end)

test("an item up for a roll gives an alert with its link", function()
  local link = "|cff0070dd|Hitem:2000::::::::|h[Archeus]|h|r"
  GetLootRollItemLink = function(id) return id == 7 and link or nil end
  Fire("START_LOOT_ROLL", 7, 60000)
  local a = alerts()[1]
  check(a and a.tag.text == "Roll", "roll label")
  check(msgOf(a) == "Roll for " .. link, "item link shown, got " .. tostring(a and msgOf(a)))
  GetLootRollItemLink = nil
  GetLootRollItemInfo = function() return "icon", "Linen Cloth", 2, 1 end
  Fire("START_LOOT_ROLL", 8, 60000)
  check(msgOf(alerts()[1]) == "Roll for [Linen Cloth] x2", "name when no link")
  GetLootRollItemInfo = nil
end)

test("only roll results and Need among loot lines give an alert", function()
  Fire("CHAT_MSG_LOOT", "You receive loot: [Linen Cloth].")
  Fire("CHAT_MSG_LOOT", "Need Roll - 54 for [Archeus] by Bram")
  Fire("CHAT_MSG_LOOT", "Bram has selected Greed for: [Archeus]")
  check(#alerts() == 0, "no alerts for other loot lines, got " .. #alerts())
  Fire("CHAT_MSG_LOOT", "Bram won: [Archeus]")
  Fire("CHAT_MSG_LOOT", "You won: [Archeus]")
  Fire("CHAT_MSG_LOOT", "Everyone passed on: [Archeus]")
  check(#alerts() == 3, "three roll results, got " .. #alerts())
end)

test("selecting Need gives an alert with who and which item", function()
  Fire("CHAT_MSG_LOOT", "Bram-Realm has selected Need for: [Ironfoe]")
  local a = alerts()[1]
  check(a and a.tag.text == "Need", "Need label")
  check(msgOf(a):find("Bram", 1, true) and msgOf(a):find("Need on [Ironfoe]", 1, true), "who and item, got " .. msgOf(a))
  Fire("CHAT_MSG_LOOT", "You have selected Need for: [Ironfoe]")
  local mine = false
  for _, x in ipairs(alerts()) do if msgOf(x):find("Aztek", 1, true) then mine = true end end
  check(#alerts() == 2 and mine, "your own Need under your name")
end)

test("loot rolls can be switched off", function()
  CB.db.sources.loot = false
  GetLootRollItemLink = function() return "[Archeus]" end
  Fire("START_LOOT_ROLL", 1, 60000)
  Fire("CHAT_MSG_LOOT", "Bram won: [Archeus]")
  Fire("CHAT_MSG_LOOT", "Bram has selected Need for: [Archeus]")
  check(#alerts() == 0, "no roll alerts")
  GetLootRollItemLink = nil
end)

local BLUE = "|cff0070dd|Hitem:2000::::::::|h[Archeus]|h|r"
local PURPLE = "|cffa335ee|Hitem:2100::::::::|h[Ironfoe]|h|r"
local GREEN = "|cff1eff00|Hitem:2200::::::::|h[Gnoll Hide]|h|r"

local function enterDungeon(name)
  IsInInstance = function() return true, "party" end
  GetInstanceInfo = function() return name end
  Fire("PLAYER_ENTERING_WORLD")
end

local function leaveDungeon()
  IsInInstance = function() return false, "none" end
  Fire("PLAYER_ENTERING_WORLD")
end

local summary = function() return _G.ChatBannerSummary end
local function closeSummary() if summary() then summary():Hide() end end

-- combat log flags as the game sends them
local ME, MATE, ENEMY, MYPET = 0x401, 0x402, 0x848, 0x1001
local ts = 5000
local function combat(sub, src, srcFlags, dst, dstFlags, ...)
  ts = ts + 1
  CombatEvent = { ts, sub, false, src and ("G-" .. src), src, srcFlags or 0, 0,
                  dst and ("G-" .. dst), dst, dstFlags or 0, 0, ... }
  CombatEvent.n = 11 + select("#", ...)
  Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

test("loot lines are read with who got which item", function()
  local who, link = CB.ParseLoot("Bram-Realm receives loot: " .. BLUE .. ".")
  check(who == "Bram-Realm" and link == BLUE, "someone else")
  who, link = CB.ParseLoot("You receive loot: " .. PURPLE .. "x2.")
  check(who == nil and link == PURPLE, "you, more than one")
  check(CB.ParseLoot("You won: " .. BLUE) == nil, "roll results are not counted twice")
  check(CB.ItemQuality(BLUE) == 3 and CB.ItemQuality(PURPLE) == 4 and CB.ItemQuality(GREEN) == 2, "quality from colour")
end)

test("roll lines are read with who, item and roll", function()
  local r = CB.ParseRoll("Need Roll - 87 for " .. PURPLE .. " by Bram-Realm")
  check(r.kind == "needroll" and r.roll == 87 and r.link == PURPLE and r.who == "Bram", "need roll")
  r = CB.ParseRoll("You have selected Need for: " .. PURPLE)
  check(r.kind == "need" and r.who == "Aztek", "your own need")
  r = CB.ParseRoll("Everyone passed on: " .. PURPLE)
  check(r.kind == "passed" and r.who == nil, "everyone passed")
  r = CB.ParseRoll("You won: " .. PURPLE)
  check(r.kind == "won" and r.who == "Aztek", "you won, not a player called You")
end)

test("blue and better is the default for the loot summary", function()
  check(CB.db.lootMinQuality == 3, "blue by default")
end)

test("the winner's roll shows on the result alert and in the summary", function()
  enterDungeon("Wailing Caverns")
  Fire("CHAT_MSG_LOOT", "Bram has selected Need for: " .. PURPLE)
  Fire("CHAT_MSG_LOOT", "You have selected Need for: " .. PURPLE)
  Fire("CHAT_MSG_LOOT", "Need Roll - 54 for " .. PURPLE .. " by Bram")
  Fire("CHAT_MSG_LOOT", "Need Roll - 87 for " .. PURPLE .. " by Aztek")
  Fire("CHAT_MSG_LOOT", "You won: " .. PURPLE)
  Fire("CHAT_MSG_LOOT", "You receive loot: " .. PURPLE .. ".")
  local won
  for _, a in ipairs(alerts()) do if msgOf(a):find("You won", 1, true) then won = a end end
  check(won and msgOf(won):find("(Need 87)", 1, true), "roll on the result alert, got " .. tostring(won and msgOf(won)))
  local rows = CB:SummaryLoot(CB.db.lootRun)
  check(#rows == 1 and rows[1].text == "won by Aztek (Need 87) - also Need: Bram 54",
    "loot row, got " .. tostring(rows[1] and rows[1].text))
  leaveDungeon()
  closeSummary()
end)

test("the combat log counts damage, healing, buffs and more per player", function()
  GroupNames.party1 = "Bram"; GroupClasses.Bram = "WARRIOR"
  enterDungeon("Wailing Caverns")
  combat("SWING_DAMAGE", "Aztek", ME, "Kobold", ENEMY, 300)
  combat("SPELL_DAMAGE", "Aztek", ME, "Kobold", ENEMY, 1, "Ferocious Bite", 1, 912)
  combat("SPELL_DAMAGE", "Wolf", MYPET, "Kobold", ENEMY, 2, "Bite", 1, 100)
  combat("SPELL_DAMAGE", "Bram", MATE, "Kobold", ENEMY, 3, "Heroic Strike", 1, 400)
  combat("SPELL_DAMAGE", "Kobold", ENEMY, "Bram", MATE, 4, "Thrash", 1, 250)
  combat("SWING_DAMAGE", "Mutanus", ENEMY, "Bram", MATE, 1840)
  combat("SPELL_HEAL", "Aztek", ME, "Bram", MATE, 5, "Healing Touch", 8, 1000, 200)
  combat("SPELL_AURA_APPLIED", "Aztek", ME, "Bram", MATE, 6, "Mark of the Wild", 8, "BUFF")
  combat("SPELL_AURA_APPLIED", "Aztek", ME, "Aztek", ME, 7, "Cat Form", 1, "BUFF")
  combat("SPELL_AURA_APPLIED", "Kobold", ENEMY, "Kobold", ENEMY, 8, "Enrage", 1, "BUFF")
  combat("PARTY_KILL", "Aztek", ME, "Kobold", ENEMY)
  combat("UNIT_DIED", nil, 0, "Kobold", ENEMY)
  combat("UNIT_DIED", nil, 0, "Bram", MATE)
  local s = CB.db.lootRun.stats
  local a, b = s.players.Aztek, s.players.Bram
  check(a.dmg == 1312, "Aztek's damage with the pet, got " .. a.dmg)
  check(b.dmg == 400 and b.taken == 2090, "Bram dealt 400 and took 2090")
  check(a.heal == 800, "healing without overheal, got " .. a.heal)
  check(a.buffs == 1, "only buffs on someone else count, got " .. a.buffs)
  check(a.kb == 1 and s.kills == 1 and b.deaths == 1, "kills and deaths")
  check(s.rec.hit.who == "Aztek" and s.rec.hit.amount == 912 and s.rec.hit.what == "Ferocious Bite", "highest hit")
  check(s.rec.heal.amount == 800 and s.rec.taken.amount == 1840 and s.rec.taken.what == "Mutanus",
    "biggest heal and hit taken")
  check(a.class == "DRUID" and b.class == "WARRIOR", "classes noted")
  leaveDungeon()
  closeSummary()
  GroupNames.party1 = nil
end)

test("nothing is counted outside a dungeon", function()
  IsInInstance = function() return false, "none" end
  Fire("PLAYER_ENTERING_WORLD")
  combat("SWING_DAMAGE", "Aztek", ME, "Kobold", ENEMY, 300)
  check(CB.db.lootRun == nil, "no run")
end)

test("leaving a dungeon opens the scoreboard with portraits", function()
  GroupNames.party1 = "Bram"; GroupClasses.Bram = "WARRIOR"
  CB.db.lootMinQuality = 2
  enterDungeon("Wailing Caverns")
  combat("SPELL_DAMAGE", "Aztek", ME, "Kobold", ENEMY, 1, "Ferocious Bite", 1, 912)
  combat("SWING_DAMAGE", "Kobold", ENEMY, "Bram", MATE, 50)
  Fire("CHAT_MSG_LOOT", "Bram receives loot: " .. BLUE .. ".")
  Fire("CHAT_MSG_LOOT", "Lisa receives loot: " .. GREEN .. ".")
  Fire("CHAT_MSG_LOOT", "Bram receives loot: |cff9d9d9d|Hitem:1::::::::|h[Broken Fang]|h|r.")
  Portraits = {}
  GroupNames.party1 = nil                     -- Bram left the group before the end
  Now = Now + 38 * 60 + 12
  leaveDungeon()
  local f = summary()
  check(f and f.shown, "scoreboard shown")
  check(f.title.text == "Wailing Caverns" and f.meta.text:find("38:12", 1, true), "name and time, got " .. f.meta.text)
  local titles = {}
  for _, c in ipairs(AllFrames) do
    if c.parent == f and rawget(c, "badge") and c.shown then titles[#titles + 1] = c.title.text end
  end
  local all = table.concat(titles, ",")
  check(all:find("Most damage", 1, true) and all:find("Highest hit", 1, true) and all:find("Most damage taken", 1, true),
    "cards with data, got " .. all)
  check(not all:find("Most healing", 1, true) and not all:find("Died most", 1, true), "empty categories left out")
  check(#Portraits >= 1 and Portraits[1] == "player", "your own face as portrait")
  local rows = 0
  for _, r in ipairs(AllFrames) do
    if r.parent == f and rawget(r, "itemLink") and r.shown then rows = rows + 1 end
  end
  check(rows == 2, "green and blue loot, no grey, got " .. rows)
  check(CB.db.lootRun == nil and CB.db.lastLoot.name == "Wailing Caverns", "run finished and kept")
  closeSummary()
  SlashCmdList.CHATBANNER("summary")
  check(summary().shown, "/chatbanner summary opens it again")
  closeSummary()

  -- post to party
  local run = CB.db.lastLoot
  Sent = {}
  InGroup = false
  check(CB:PostSummary(run) == false and #Sent == 0, "not in a group: nothing sent")
  InGroup = true
  CB:PostSummary(run)
  check(#Sent >= 2 and Sent[1]:find("^PARTY:ChatBanner: Wailing Caverns %(38:12"), "header line, got " .. tostring(Sent[1]))
  local text = table.concat(Sent, "\n")
  check(text:find("Highest hit: Aztek 912 (Ferocious Bite)", 1, true), "categories posted")
  check(text:find("[Archeus]", 1, true), "loot posted")
  for _, line in ipairs(Sent) do check(#line - 6 <= 255, "lines fit in chat") end
  InRaid = true
  Sent = {}
  CB:PostSummary(run)
  check(Sent[1]:find("^RAID:"), "raid chat in a raid")
  InGroup, InRaid = false, false
end)

test("/chatbanner summary test shows a sample with your name", function()
  SlashCmdList.CHATBANNER("summary test")
  local f = summary()
  check(f.shown and f.title.text:find("sample", 1, true), "sample shown")
  local names = {}
  for _, c in ipairs(AllFrames) do
    if c.parent == f and rawget(c, "badge") and c.shown then names[#names + 1] = c.name.text end
  end
  check(#names == 9, "all nine categories, got " .. #names)
  check(table.concat(names, ","):find("Aztek", 1, true), "you are in it")
  closeSummary()
end)

test("numbers and times are short and readable", function()
  check(CB.FormatNumber(912) == "912" and CB.FormatNumber(1410) == "1,410" and CB.FormatNumber(48213) == "48.2k", "numbers")
  check(CB.FormatClock(2292) == "38:12" and CB.FormatClock(3725) == "1:02:05", "times")
end)

test("the options choose the lowest quality in the loot summary", function()
  CB:RefreshOptions()
  local dd
  for _, f in ipairs(AllFrames) do
    if rawget(f, "list") and f.text == "Blue (rare) and better" then dd = f end
  end
  check(dd, "dropdown shown with blue as default")
  check(not dd.list.shown, "menu closed at first")
  dd:Click()
  check(dd.list.shown and #dd.items == 3, "menu with green, blue and purple")
  dd.items[1]:Click()
  check(CB.db.lootMinQuality == 2 and dd.text == "Green (uncommon) and better", "green chosen")
  check(not dd.list.shown, "menu closes after a choice")
end)

test("the options never touch Blizzard's shared dropdown menus", function()
  -- UIDropDownMenu shares global state with the game's own menus; using it
  -- got ChatBanner blamed for blocked actions (party invites, player menus)
  local used = false
  for _, f in ipairs(AllFrames) do
    if f.template == "UIDropDownMenuTemplate" then used = true end
  end
  check(not used, "no UIDropDownMenuTemplate frames")
  for _, file in ipairs(TOC_FILES) do
    local src = readfile(ROOT .. "/" .. file)
    check(not src:find("UIDropDownMenu_", 1, true) and not src:find("CloseDropDownMenus", 1, true), file .. " uses UIDropDownMenu")
  end
end)

test("dying and running back does not end the dungeon", function()
  enterDungeon("Deadmines")
  Fire("CHAT_MSG_LOOT", "Bram receives loot: " .. BLUE .. ".")
  UnitIsDeadOrGhost = function() return true end
  leaveDungeon()
  check(not (summary() and summary().shown) and CB.db.lootRun, "still in the run as a ghost")
  UnitIsDeadOrGhost = function() return false end
  enterDungeon("Deadmines")
  Fire("CHAT_MSG_LOOT", "Lisa receives loot: " .. BLUE .. ".")
  leaveDungeon()
  check(#CB.db.lastLoot.items == 2, "both items in one summary")
  closeSummary()
  UnitIsDeadOrGhost = nil
end)

test("no scoreboard for an empty run or with the option off", function()
  enterDungeon("Ragefire Chasm")
  leaveDungeon()
  check(not (summary() and summary().shown), "nothing happened, nothing shown")
  CB.db.lootSummary = false
  enterDungeon("Ragefire Chasm")
  Fire("CHAT_MSG_LOOT", "Bram receives loot: " .. BLUE .. ".")
  leaveDungeon()
  check(not (summary() and summary().shown), "option off")
  IsInInstance, GetInstanceInfo = nil, nil
end)

test("quest kill and item progress give no alert by default", function()
  for _, msg in ipairs({ "Kobold Vermin slain: 3/10", "Candle: 2/8",
                         "Kobold Vermin slain: 10/10 (Complete)", "Objective Complete." }) do
    Fire("CHAT_MSG_SYSTEM", msg)
  end
  check(#alerts() == 0, "no quest progress alerts, got " .. #alerts())
  Fire("CHAT_MSG_SYSTEM", "Thrall has come online.")
  check(#alerts() == 1, "other system messages still alert")
end)

test("quest progress alerts when switched on, with its own label", function()
  CB.db.sources.quest = true
  Fire("CHAT_MSG_SYSTEM", "Kobold Vermin slain: 3/10")
  local a = alerts()[1]
  check(a and a.tag.text == "Quest", "quest label")
  CB.db.sources.system = false
  Fire("CHAT_MSG_SYSTEM", "Candle: 2/8")
  check(#alerts() == 2, "quest alerts do not depend on system messages")
end)

test("quest texts follow the game's translated strings", function()
  check(("Kobold slain: 1/8"):find(CB.ToPattern("%s slain: %d/%d")), "english pattern")
  check(("Kobold getötet: 1/8"):find(CB.ToPattern("%1$s getötet: %2$d/%3$d")), "numbered pattern")
  check(not ("Price: 5.00 (sale)"):find(CB.ToPattern("%s (Complete)")), "magic characters escaped")
  check(not CB.IsQuestProgress("Thrall has come online."), "normal system text")
end)

test("NPCs talking still alert by default", function()
  Fire("CHAT_MSG_MONSTER_YELL", "Honor your heroes!", "Herald of Thrall")
  check(#alerts() == 1, "npc alert")
end)

test("setup checkboxes switch whole groups of sources", function()
  CB:OpenSetup()
  local boxes = setupBoxes()
  check(#boxes == #CB.SETUP_GROUPS, "one box per group, got " .. #boxes)
  check(boxes[2].checked == true, "party and raid shown as on")
  check(boxes[8].checked == false, "quest progress shown as off")
  boxes[2]:SetChecked(false)
  boxes[2].scripts.OnClick(boxes[2])
  check(CB.db.sources.party == false and CB.db.sources.raid == false, "party and raid off")
  boxes[8]:SetChecked(true)
  boxes[8].scripts.OnClick(boxes[8])
  check(CB.db.sources.quest == true, "quest progress on")
  closeSetup()
end)

test("the setup's move button unlocks, closing locks again", function()
  CB:OpenSetup()
  CB:SetUnlocked(true)
  check(CB.unlocked, "unlocked")
  closeSetup()
  check(CB.unlocked == false, "locked after closing the setup")
end)

local function printedText() return table.concat(Printed, "\n") end

local function withVersion(v, fn)
  local old = CB.version
  CB.version = v
  local ok, err = pcall(fn)
  CB.version = old
  if not ok then error(err, 0) end
end

test("versions compare number by number", function()
  check(CB.CompareVersions("1.0.10", "1.0.9") == 1, "1.0.10 > 1.0.9")
  check(CB.CompareVersions("1.0", "1.0.0") == 0, "1.0 == 1.0.0")
  check(CB.CompareVersions("1.0.1", "1.0.2") == -1, "1.0.1 < 1.0.2")
end)

test("a new player gets a welcome line and no release notes", function()
  withVersion("1.0.2", function()
    ChatBannerDB.lastVersion = nil
    CB:Announce(true)
    check(printedText():find("Loaded", 1, true), "welcome shown")
    check(not printedText():find("What's new", 1, true), "no notes for new players")
    check(ChatBannerDB.lastVersion == "1.0.2", "version stored")
  end)
end)

test("an update from 1.0.0 shows every note since then", function()
  withVersion("1.0.2", function()
    ChatBannerDB.lastVersion = nil       -- 1.0.0 did not store a version
    CB:Announce(false)
    local text = printedText()
    check(text:find("Updated to 1.0.2", 1, true), "update line")
    check(text:find("What's new in 1.0.2", 1, true), "1.0.2 notes")
    check(text:find("What's new in 1.0.1", 1, true), "1.0.1 notes")
  end)
end)

test("an update from 1.0.1 shows only the newer notes, once", function()
  withVersion("1.0.2", function()
    ChatBannerDB.lastVersion = "1.0.1"
    CB:Announce(false)
    check(printedText():find("What's new in 1.0.2", 1, true), "1.0.2 notes")
    check(not printedText():find("What's new in 1.0.1", 1, true), "no old notes")
    Printed = {}
    CB:Announce(false)
    check(#Printed == 0, "nothing on the next login")
  end)
end)

test("/chatbanner news shows the notes again", function()
  withVersion("1.0.2", function()
    SlashCmdList.CHATBANNER("news")
    check(printedText():find("What's new in 1.0.1", 1, true), "notes shown")
  end)
end)

test("reset keeps the stored version", function()
  ChatBannerDB.lastVersion = "0.9"
  CB:ResetSettings()
  check(ChatBannerDB.lastVersion == CB.version, "version kept after reset")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error("tests failed") end
