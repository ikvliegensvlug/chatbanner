-- ChatBanner: options panel in the game's Options > AddOns list (/chatbanner opens it).
local _, ns = ...
local CB = ns.CB

local panel, content
local widgets = {}

local COL1, COL2 = 16, 300      -- left edges of the two columns
local SLIDER_W = 250

---------------------------------------------------------------------------
-- Widgets. Each one gets Refresh(), called whenever the panel opens or settings change.
---------------------------------------------------------------------------
local function add(w)
  widgets[#widgets + 1] = w
  return w
end

local function header(text, y)
  local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", COL1, y)
  fs:SetText(text)
  local line = content:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 1, 1, 0.15)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", COL1, y - 22)
  line:SetPoint("RIGHT", content, "RIGHT", -16, 0)
end

local function checkbox(label, x, y, get, set)
  local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", x, y)
  local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  fs:SetText(label)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
  end)
  cb.Refresh = function() cb:SetChecked(get() and true or false) end
  return add(cb)
end

local function slider(label, x, y, min, max, step, format, get, set)
  local f = CreateFrame("Frame", nil, content)
  f:SetSize(SLIDER_W, 40)
  f:SetPoint("TOPLEFT", x, y)
  local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  name:SetPoint("TOPLEFT")
  name:SetText(label)
  local value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  value:SetPoint("TOPRIGHT")

  local s = CreateFrame("Slider", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(SLIDER_W, 17)
  s:SetPoint("TOPLEFT", 0, -18)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  if s.SetBackdrop then
    s:SetBackdrop({
      bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
      edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
      tile = true, tileSize = 8, edgeSize = 8,
      insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
  end
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  -- No mouse wheel on sliders: it would change settings while scrolling the panel.
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / step + 0.5) * step
    value:SetText(format(v))
    if not self.updating then set(v) end
  end)
  f.Refresh = function()
    s.updating = true
    s:SetValue(get())
    s.updating = false
    value:SetText(format(get()))
    -- optional f.enabled(): greys the slider out when it does not apply
    local on = not f.enabled or f.enabled()
    if on then s:Enable() else s:Disable() end
    f:SetAlpha(on and 1 or 0.45)
  end
  return add(f)
end

-- options = { { key = ..., label = ... }, ... }
local function dropdown(label, x, y, options, get, set)
  local title = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOPLEFT", x, y)
  title:SetText(label)

  local function labelOf(key)
    for _, o in ipairs(options) do if o.key == key then return o.label end end
    return options[1].label
  end

  -- Our own small menu, not Blizzard's UIDropDownMenu: that one shares global
  -- state with the game's own menus (right-click on a player, invites), and an
  -- add-on touching it gets blamed when the game later does a protected action.
  local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  b:SetSize(SLIDER_W, 24)
  b:SetPoint("TOPLEFT", x, y - 18)
  local arrow = b:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  arrow:SetSize(20, 20)
  arrow:SetPoint("RIGHT", -2, 0)

  local list = CreateFrame("Frame", nil, b, BackdropTemplateMixin and "BackdropTemplate" or nil)
  list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
  list:SetSize(SLIDER_W, #options * 20 + 8)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  if list.SetBackdrop then
    list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    list:SetBackdropColor(0.05, 0.05, 0.06, 0.98)
    list:SetBackdropBorderColor(1, 1, 1, 0.25)
  end
  list:Hide()
  b.list = list
  b.items = {}
  for i, o in ipairs(options) do
    local item = CreateFrame("Button", nil, list)
    item:SetSize(SLIDER_W - 8, 20)
    item:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
    item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    item.label = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    item.label:SetPoint("LEFT", 6, 0)
    item.label:SetText(o.label)
    item:SetScript("OnClick", function()
      set(o.key)
      list:Hide()
      b.Refresh()
    end)
    b.items[i] = item
  end

  b:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
  b:SetScript("OnHide", function() list:Hide() end)
  b.Refresh = function()
    b:SetText(labelOf(get()))
    for i, o in ipairs(options) do
      b.items[i].label:SetTextColor(1, o.key == get() and 0.82 or 1, o.key == get() and 0 or 1)
    end
  end
  return add(b)
end

local function button(text, x, y, width, onClick)
  local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  b:SetSize(width, 24)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

---------------------------------------------------------------------------
-- Setters
---------------------------------------------------------------------------
local function setting(key, relayout)
  return function() return CB.db[key] end, function(v)
    CB.db[key] = v
    if relayout then
      CB:ApplyLayout()
      CB:RefreshOptions()   -- e.g. the row height shown follows the font size
    end
  end
end

local function percent(v) return math.floor(v * 100 + 0.5) .. "%" end
local function plain(v) return tostring(math.floor(v + 0.5)) end
local function seconds(v) return math.floor(v + 0.5) .. " s" end

---------------------------------------------------------------------------
-- Building the panel
---------------------------------------------------------------------------
local function build()
  local y = -16
  local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", COL1, y)
  title:SetText("ChatBanner")
  local version = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
  version:SetText("v" .. CB.version)
  local intro = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  intro:SetPoint("TOPLEFT", COL1, y - 30)
  intro:SetText("Big on-screen alerts for chat. Left-click an alert to reply, right-click to dismiss.")

  -- Position and size
  y = -84
  header("Position and size", y)
  y = y - 34
  CB.unlockButton = button("Move and resize", COL1, y, 150, function()
    CB:SetUnlocked(not CB.unlocked)
  end)
  button("Reset position", COL1 + 160, y, 130, function() CB:ResetPosition() end)
  button("Show test alerts", COL1 + 300, y, 150, function() CB:Test() end)
  button("Quick setup", COL1 + 460, y, 110, function() CB:OpenSetup() end)
  y = y - 40
  slider("Width", COL1, y, 250, 1400, 10, plain, setting("width", true))
  local _, setRow = setting("rowHeight", true)
  local row = slider("Row height", COL2, y, 20, 80, 1, plain,
    function() return CB:RowHeight() end, setRow)
  row.enabled = function() return not CB.db.autoHeight end
  checkbox("Follow the font size", COL2, y - 42, setting("autoHeight", true))
  y = y - 76
  slider("Scale", COL1, y, 0.5, 2, 0.05, percent, setting("scale", true))
  slider("Alerts on screen at once", COL2, y, 1, 10, 1, plain, setting("maxAlerts", true))
  y = y - 50
  slider("Time on screen", COL1, y, 2, 30, 1, seconds, setting("duration"))
  checkbox("New alerts grow upwards", COL2, y - 10, setting("growUp", true))

  -- Sources
  y = y - 62
  header("Alerts from", y)
  y = y - 34
  local half = math.ceil(#CB.SOURCES / 2)
  for i, src in ipairs(CB.SOURCES) do
    local col = i <= half and COL1 or COL2
    local row = (i <= half) and (i - 1) or (i - half - 1)
    checkbox(src.label, col, y - row * 26,
      function() return CB.db.sources[src.key] end,
      function(v) CB.db.sources[src.key] = v end)
  end
  y = y - half * 26 - 6
  button("All", COL1, y, 80, function()
    for _, src in ipairs(CB.SOURCES) do CB.db.sources[src.key] = true end
    CB:RefreshOptions()
  end)
  button("None", COL1 + 90, y, 80, function()
    for _, src in ipairs(CB.SOURCES) do CB.db.sources[src.key] = false end
    CB:RefreshOptions()
  end)

  -- Style
  y = y - 46
  header("Style", y)
  y = y - 34
  dropdown("Font", COL1, y, CB.FONTS, setting("font", true))
  slider("Font size", COL2, y, 8, 28, 1, plain, setting("fontSize", true))
  y = y - 56
  dropdown("Border", COL1, y, CB.BORDERS, setting("border", true))
  slider("Background opacity", COL2, y, 0, 1, 0.05, percent, setting("bgAlpha", true))
  y = y - 56
  checkbox("Show the channel label", COL1, y, setting("showTag", true))
  checkbox("Colour the text like the chat type", COL2, y, setting("colorText"))

  -- Behaviour
  y = y - 44
  header("Behaviour", y)
  y = y - 34
  checkbox("Play a sound with each alert", COL1, y, setting("sound"))
  checkbox("Skip my own messages", COL2, y, setting("ignoreOwn"))
  y = y - 44
  button("Reset all settings", COL1, y, 160, function()
    CB:ResetSettings()
    CB:Print("All settings restored to default.")
  end)

  content:SetHeight(-y + 40)
end

function CB:RefreshOptions()
  if not panel then return end
  for _, w in ipairs(widgets) do w.Refresh() end
  if CB.unlockButton then
    CB.unlockButton:SetText(CB.unlocked and "Done moving" or "Move and resize")
  end
end

function CB:InitOptions()
  panel = CreateFrame("Frame", "ChatBannerOptions", UIParent)
  panel.name = "ChatBanner"
  panel:Hide()

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(600, 800)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

  build()
  panel:SetScript("OnShow", function() CB:RefreshOptions() end)
  -- Closing the options (or switching to another category) ends moving and
  -- resizing, unless the quick setup is still open and owns it.
  panel:SetScript("OnHide", function()
    if CB.unlocked and not CB:SetupShown() then CB:SetUnlocked(false) end
  end)

  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "ChatBanner")
    Settings.RegisterAddOnCategory(category)
    self.category = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function CB:OpenOptions()
  if InCombatLockdown() then
    self:Print("Options open after combat. Try again in a moment.")
    return
  end
  if self.category and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(self.category:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    -- called twice: the first call only opens the frame on some clients
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end
