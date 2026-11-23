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

-- the game's damage meter: one session per fight
local function fight(id, duration, data)
  local s = { id = id, duration = duration }
  local kinds = { dmg = 0, heal = 2, taken = 7, deaths = 9 }
  for field, rows in pairs(data) do
    local list = {}
    for _, r in ipairs(rows) do
      list[#list + 1] = { name = r[1], totalAmount = r[2], classFilename = r[3], sourceDisplayType = r[4],
                          isLocalPlayer = r[5], sourceGUID = r[6] }
    end
    s[kinds[field]] = list
  end
  MeterSessions[#MeterSessions + 1] = s
end

test("the scoreboard never registers for the combat log", function()
  -- this client blocks add-ons that register for it ("has been blocked from an action")
  for _, file in ipairs(TOC_FILES) do
    local src = readfile(ROOT .. "/" .. file)
    check(not src:find("COMBAT_LOG_EVENT", 1, true), file .. " mentions the combat log event")
  end
end)

test("the damage meter's fights since entering are added up per player", function()
  MeterSessions = {}
  fight(1, 30, { dmg = { { "Aztek", 999, "DRUID" } } })        -- before the dungeon
  enterDungeon("Wailing Caverns")
  check(CB.db.lootRun.statsFrom == 1, "starts after the newest fight")
  fight(2, 40, { dmg = { { "Aztek-Realm", 1000, "DRUID" }, { "Bram", 400, "WARRIOR" }, { "Kobold", 5000, nil, 2 } },
                 heal = { { "Aztek", 800, "DRUID" } },
                 taken = { { "Bram", 2090, "WARRIOR" } } })
  fight(3, 20, { dmg = { { "Aztek", 312, "DRUID" } }, deaths = { { "Bram", 0, "WARRIOR" } } })   -- the meter gives 0 for a death
  local run = CB.db.lootRun
  leaveDungeon()
  closeSummary()
  local s = run.stats
  local a, b = s.players.Aztek, s.players.Bram
  check(a.dmg == 1312, "Aztek's damage without the fight before, got " .. a.dmg)
  check(a.active == 60, "active time from his fights, got " .. a.active)
  check(b.dmg == 400 and b.taken == 2090 and b.deaths == 1, "Bram's numbers")
  check(a.heal == 800, "healing")
  check(not s.players.Kobold, "enemies left out")
  check(a.class == "DRUID" and b.class == "WARRIOR", "classes from the meter")
  MeterSessions = {}
end)

test("secret numbers are skipped, and combat delays the end", function()
  MeterSessions = {}
  enterDungeon("Deadmines")
  fight(1, 40, { dmg = { { "Aztek", 1000, "DRUID" } } })
  InCombat = true
  leaveDungeon()
  check(CB.db.lootRun and not (summary() and summary().shown), "waits while in combat")
  InCombat = false
  SecretValues = true
  Fire("PLAYER_REGEN_ENABLED")
  check(CB.db.lootRun == nil, "finished after combat")
  check(not (summary() and summary().shown), "no numbers readable, nothing to show")
  SecretValues = false
  MeterSessions = {}
end)

test("nothing is counted outside a dungeon", function()
  IsInInstance = function() return false, "none" end
  Fire("PLAYER_ENTERING_WORLD")
  check(CB.db.lootRun == nil, "no run")
end)

test("links coloured by quality (|cnIQ2:) are read", function()
  enterDungeon("Wailing Caverns")
  local bracer = "|cnIQ2:|Hitem:14366::::::::27:1484::1::1:28:5254:::::|h[Mystic's Bracelets]|h|r"
  Fire("CHAT_MSG_LOOT", "You receive loot: " .. bracer .. ".")
  Fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ0:|Hitem:5124::::::::27:1484:::::::::|h[Small Raptor Tooth]|h|r.")
  local items = CB.db.lootRun.items
  check(#items == 1 and items[1].link == bracer and items[1].q == 2, "the green bracer, not the grey tooth, got " .. #items)
  leaveDungeon()
  closeSummary()
end)

test("alone, items taken from the loot window count once", function()
  enterDungeon("Deadmines")
  local slots = { BLUE, "|cff9d9d9d|Hitem:1::::::::|h[Broken Fang]|h|r" }
  GetNumLootItems = function() return #slots end
  GetLootSlotLink = function(i) return slots[i] end
  Fire("LOOT_OPENED")
  Fire("LOOT_SLOT_CLEARED", 1)
  Fire("LOOT_SLOT_CLEARED", 2)
  Fire("CHAT_MSG_LOOT", "You receive loot: " .. BLUE .. ".")   -- the same item again in chat
  local items = CB.db.lootRun.items
  check(#items == 1 and items[1].who == "Aztek" and items[1].link == BLUE, "one blue item, got " .. #items)
  Fire("CHAT_MSG_LOOT", "You receive loot: " .. BLUE .. ".")   -- a second one is a new item
  check(#items == 2, "a second drop counts")
  InGroup = true
  Fire("LOOT_OPENED")
  Fire("LOOT_SLOT_CLEARED", 1)
  check(#items == 2, "in a group the chat line decides")
  InGroup = false
  GetNumLootItems, GetLootSlotLink = nil, nil
  SlashCmdList.CHATBANNER("summary")
  check(summary().shown and summary().title.text == "Deadmines (so far)", "the run so far, got " .. summary().title.text)
  closeSummary()
  check(CB.db.lootRun and #CB.db.lootRun.items == 2, "still in the run")
  leaveDungeon()
  closeSummary()
end)

test("leaving a dungeon opens the scoreboard with portraits", function()
  GroupNames.party1 = "Bram"; GroupClasses.Bram = "WARRIOR"
  CB.db.lootMinQuality = 2
  MeterSessions = {}
  enterDungeon("Wailing Caverns")
  fight(1, 60, { dmg = { { "Aztek", 48213, "DRUID" } }, taken = { { "Bram", 50, "WARRIOR" } } })
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
  check(all:find("Most damage", 1, true) and all:find("Most damage taken", 1, true), "cards with data, got " .. all)
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
  check(text:find("Most damage: Aztek 48.2k (804 DPS)", 1, true), "categories posted, got " .. text)
  check(text:find("[Archeus]", 1, true), "loot posted")
  for _, line in ipairs(Sent) do check(#line - 6 <= 255, "lines fit in chat") end
  check(Sent[#Sent] == "PARTY:Download addon ChatBanner, free on CurseForge.", "ends with where to get ChatBanner")
  InRaid = true
  Sent = {}
  CB:PostSummary(run)
  check(Sent[1]:find("^RAID:"), "raid chat in a raid")
  InGroup, InRaid = false, false
  MeterSessions = {}
end)

test("the loot list puts the best first and its filter cycles green, blue, purple", function()
  local PURPLE = "|cffa335ee|Hitem:11684::::::::|h[Ironfoe]|h|r"
  local run = { name = "Deadmines", duration = 60, rolls = {},
    items = { { who = "Aztek", link = GREEN, q = 2 }, { who = "Bram", link = BLUE, q = 3 }, { who = "Lisa", link = PURPLE, q = 4 } } }
  CB.db.lootMinQuality = 2
  local rows = CB:SummaryLoot(run)
  check(#rows == 3 and rows[1].link == PURPLE and rows[3].link == GREEN, "best first")
  check(rows[1].text == "looted by Lisa", "no roll: looted, got " .. rows[1].text)
  CB:OpenSummary(run)
  local f = CB.summaryFilter
  check(f and f.shown and f.text.text:find("green or better", 1, true), "filter shows the choice")
  f:Click()
  check(CB.db.lootMinQuality == 3 and f.text.text:find("blue or better", 1, true), "click: blue")
  f:Click(); f:Click()
  check(CB.db.lootMinQuality == 2, "and around to green")
  CB.db.lootMinQuality = 4
  run.items = { run.items[1] }
  CB:OpenSummary(run)
  local empty = false
  for _, r in ipairs(AllFrames) do
    local info = rawget(r, "info"); if r.parent == summary() and info and r.shown and info.text:find("^No ") then empty = true end
  end
  check(f.shown and empty, "filter stays, with a note that nothing matches")
  CB.db.lootMinQuality = 3
  closeSummary()
end)

test("/chatbanner summary test shows a sample with your name", function()
  SlashCmdList.CHATBANNER("summary test")
  local f = summary()
  check(f.shown and f.title.text:find("sample", 1, true), "sample shown")
  local names = {}
  for _, c in ipairs(AllFrames) do
    if c.parent == f and rawget(c, "badge") and c.shown then names[#names + 1] = c.name.text end
  end
  check(#names == #CB.SUMMARY_CATEGORIES, "every category, got " .. #names)
  check(table.concat(names, ","):find("Aztek", 1, true), "you are in it")
  local emblem
  for _, c in ipairs(AllFrames) do
    if c.parent == f and rawget(c, "classIcon") and c.shown and c.classIcon.shown and c.name.text == "Bram" then
      emblem = c.classIcon
    end
  end
  check(emblem and emblem.atlas == "classicon-warrior", "players outside your group get their round class icon")
  closeSummary()
end)

test("players are found by GUID or by the start of a longer name", function()
  MeterSessions = {}
  GroupNames.party1 = "Bram"
  enterDungeon("Wailing Caverns")
  fight(1, 60, { dmg = { { "Bram Steelhand", 900, "WARRIOR", nil, nil, "Player-Bram" } },
                 taken = { { "Aztek Ensteek", 400, "DRUID" } } })
  Portraits = {}
  leaveDungeon()
  local units = table.concat(Portraits, ",")
  check(units:find("party1", 1, true), "Bram by GUID, got " .. units)
  check(units:find("player", 1, true), "you by the start of your name, got " .. units)
  closeSummary()
  GroupNames.party1 = nil
  MeterSessions = {}
end)

test("your own card shows your face even when the meter names you differently", function()
  MeterSessions = {}
  enterDungeon("Wailing Caverns")
  fight(1, 60, { dmg = { { "Aztek Ensteek", 3135, "DRUID", nil, true } } })
  Portraits = {}
  leaveDungeon()
  check(summary().shown and Portraits[1] == "player", "your portrait, got " .. tostring(Portraits[1]))
  closeSummary()
  MeterSessions = {}
end)

test("/chatbanner debug keeps loot lines and how they were read", function()
  SlashCmdList.CHATBANNER("debug")
  Fire("CHAT_MSG_LOOT", "You receive loot: " .. GREEN .. ".")
  SecretValues = true
  Fire("CHAT_MSG_LOOT", "You receive loot: " .. GREEN .. ".")
  SecretValues = false
  local log = CB.db.debug.loot
  check(#log == 2 and log[1].parsed == "you -> " .. GREEN .. " q2", "parsed line, got " .. tostring(log[1] and log[1].parsed))
  check(log[2].text == "<secret>", "secret lines are marked")
  SlashCmdList.CHATBANNER("debug")
  check(CB.db.debug == nil, "off again")
end)

test("secret chat text in a dungeon fight is shown as is, never read", function()
  SecretValues = true
  Fire("CHAT_MSG_PARTY", "heal me", "Bram-Realm")
  local a = alerts()[1]
  check(a and msgOf(a):find("heal me", 1, true), "party line shown")
  Fire("CHAT_MSG_SYSTEM", "Kobold Vermin slain: 3/10")
  Fire("CHAT_MSG_LOOT", "You receive loot: " .. GREEN .. ".")
  check(#alerts() == 1, "system and loot lines skipped when secret")
  SecretValues = false
  check(CB.lastError == nil, "no errors, got " .. tostring(CB.lastError))
end)

test("an error while handling chat never reaches the player", function()
  local real = CB.Show
  CB.Show = function() error("boom") end
  Fire("CHAT_MSG_SAY", "hello", "Bram")
  CB.Show = real
  check(CB.lastError and CB.lastError:find("boom", 1, true), "error kept, got " .. tostring(CB.lastError))
  CB.lastError = nil
end)

test("portraits are drawn again shortly after the scoreboard opens", function()
  SlashCmdList.CHATBANNER("summary test")
  Portraits = {}
  RunTimers()
  check(#Portraits >= 3 and Portraits[1] == "player", "your portrait redrawn by the timers, got " .. #Portraits)
  closeSummary()
  Portraits = {}
  RunTimers()
  check(#Portraits == 0, "nothing redrawn once closed")
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
