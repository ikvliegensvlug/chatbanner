-- ChatBanner: a short setup with the most important choices.
-- Opens once on the first login (also for players updating from an older version);
-- /chatbanner setup opens it again.
local _, ns = ...
local CB = ns.CB

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- The choices that matter most, each covering one or more alert sources.
CB.SETUP_GROUPS = {
  { label = "Whispers",                           keys = { "whisper" } },
  { label = "Party and raid",                     keys = { "party", "raid" } },
  { label = "Guild and officer",                  keys = { "guild", "officer" } },
  { label = "Say, yell and emotes",               keys = { "say", "yell", "emote" } },
  { label = "Channels (General, Trade, LFG ...)", keys = { "channel" } },
  { label = "NPCs and mobs talking",              keys = { "npc" } },
  { label = "System messages",                    keys = { "system" } },
}

local frame
local boxes = {}

local function groupOn(group)
  for _, key in ipairs(group.keys) do
    if CB.db.sources[key] then return true end
  end
  return false
end

local function setGroup(group, on)
  for _, key in ipairs(group.keys) do CB.db.sources[key] = on end
end

local function text(parent, template, x, y, s)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText(s)
  return fs
end

local function button(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 24)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function build()
  frame = CreateFrame("Frame", "ChatBannerSetup", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(440, 372)
  frame:SetPoint("CENTER", 0, 80)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(0.05, 0.05, 0.06, 0.96)
    frame:SetBackdropBorderColor(1, 1, 1, 0.16)
  end
  if UISpecialFrames then table.insert(UISpecialFrames, "ChatBannerSetup") end  -- Esc closes it
  frame:Hide()

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  text(frame, "GameFontNormalLarge", 18, -16, "ChatBanner quick setup")
  text(frame, "GameFontHighlightSmall", 18, -40,
    "The most important choices. Everything else is under /chatbanner.")

  -- 1. Position
  text(frame, "GameFontNormal", 18, -70, "1.  Where should the alerts appear?")
  frame.moveButton = button(frame, "Move the alerts", 140, function()
    CB:SetUnlocked(not CB.unlocked)
  end)
  frame.moveButton:SetPoint("TOPLEFT", 18, -92)
  local reset = button(frame, "Reset position", 120, function() CB:ResetPosition() end)
  reset:SetPoint("LEFT", frame.moveButton, "RIGHT", 8, 0)
  local test = button(frame, "Show test alerts", 130, function() CB:Test() end)
  test:SetPoint("LEFT", reset, "RIGHT", 8, 0)

  -- 2. Sources
  text(frame, "GameFontNormal", 18, -132, "2.  Which messages should get an alert?")
  for i, group in ipairs(CB.SETUP_GROUPS) do
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 16, -150 - (i - 1) * 24)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(group.label)
    cb:SetScript("OnClick", function(self)
      setGroup(group, self:GetChecked() and true or false)
      if CB.RefreshOptions then CB:RefreshOptions() end
    end)
    boxes[i] = cb
  end

  -- Bottom row
  local more = button(frame, "All options", 120, function()
    frame:Hide()
    CB:OpenOptions()
  end)
  more:SetPoint("BOTTOMLEFT", 18, 16)
  local done = button(frame, "Done", 110, function() frame:Hide() end)
  done:SetPoint("BOTTOMRIGHT", -18, 16)
  frame.doneButton = done

  -- However it is closed, the setup counts as done and the alerts are locked again.
  frame:SetScript("OnHide", function()
    CB.db.setupDone = true
    if CB.unlocked then CB:SetUnlocked(false) end
  end)
end

function CB:RefreshSetup()
  if not frame then return end
  for i, group in ipairs(self.SETUP_GROUPS) do boxes[i]:SetChecked(groupOn(group)) end
  frame.moveButton:SetText(self.unlocked and "Lock position" or "Move the alerts")
end

function CB:OpenSetup()
  if not frame then build() end
  self:RefreshSetup()
  frame:Show()
end

-- Called at login: show the setup once, until the player has closed it.
function CB:MaybeSetup()
  if not self.db.setupDone then self:OpenSetup() end
end
