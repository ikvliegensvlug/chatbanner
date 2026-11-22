-- ChatBanner tests. Run with: npm test
local ns = {}
for _, file in ipairs(TOC_FILES) do
  local chunk = assert(load(readfile(ROOT .. "/" .. file), "@" .. file))
  chunk("ChatBanner", ns)
end
local CB = ns.CB

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
  -- grow upwards + one per source + label, colour, sound, own messages
  check(#boxes == 1 + #CB.SOURCES + 4, "checkboxes, got " .. #boxes)
  CB:RefreshOptions()
  check(sliders[1].value == 600, "width slider shows the setting")
  sliders[1]:SetValue(803)          -- snaps to the 10-step
  check(CB.db.width == 800, "width set to " .. tostring(CB.db.width))
  check(_G.ChatBannerFrame.w == 800, "alerts resized")
  local whisperBox = boxes[2]        -- order: grow upwards, then the sources
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

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error("tests failed") end
