-- Minimal fake of the WoW API: just enough to load ChatBanner and drive it with events.
-- Unknown widget methods are harmless no-ops, so only behaviour the tests check is modelled.

unpack = unpack or table.unpack
SlashCmdList = {}
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local now = 1000
function GetTime() return now end
function Advance(sec) now = now + sec end

Printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) Printed[#Printed + 1] = msg end }

AllFrames = {}
local events = {}

local Methods = {}
local function newObj(kind, name, parent)
  local o = { kind = kind, name = name, parent = parent, scripts = {}, points = {},
              shown = true, alpha = 1, w = 0, h = 0, text = "", checked = false, value = 0 }
  return setmetatable(o, { __index = function(_, k)
    return Methods[k] or function() end
  end })
end

function Methods:SetScript(n, f) self.scripts[n] = f end
function Methods:GetScript(n) return self.scripts[n] end
function Methods:HookScript(n, f)
  local old = self.scripts[n]
  self.scripts[n] = function(...) if old then old(...) end f(...) end
end
function Methods:SetSize(w, h) self.w, self.h = w, h end
function Methods:SetWidth(w) self.w = w end
function Methods:SetHeight(h) self.h = h end
function Methods:Disable() self.disabled = true end
function Methods:Enable() self.disabled = false end
function Methods:GetWidth() return self.w end
function Methods:GetHeight() return self.h end
function Methods:GetScale() return self.scale or 1 end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetLeft() return self.left or 0 end
function Methods:GetTop() return self.top or 0 end
CursorX = 0
function GetCursorPosition() return CursorX, 0 end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:SetShown(v) self.shown = v and true or false end
function Methods:IsShown() return self.shown end
function Methods:IsVisible() return self.shown end
function Methods:SetAlpha(a) self.alpha = a end
function Methods:GetAlpha() return self.alpha end
function Methods:SetText(t) self.text = t end
function Methods:GetText() return self.text end
function Methods:GetStringWidth() return #(self.text or "") * 7 end
function Methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Methods:ClearAllPoints() self.points = {} end
function Methods:GetPoint() local p = self.points[1] or {} return p[1], p[2], p[3], p[4], p[5] end
function Methods:GetFrameLevel() return 1 end
function Methods:GetName() return self.name end
function Methods:SetChecked(v) self.checked = v end
function Methods:GetChecked() return self.checked end
function Methods:SetMinMaxValues(a, b) self.min, self.max = a, b end
function Methods:SetValue(v)
  self.value = v
  if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
end
function Methods:GetValue() return self.value end
function Methods:SetScale(s) self.scale = s end
function Methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function Methods:IsObjectType(t) return self.kind == t end
function Methods:CreateTexture() return newObj("Texture", nil, self) end
function Methods:CreateFontString() return newObj("FontString", nil, self) end
function Methods:RegisterEvent(e)
  events[e] = events[e] or {}
  table.insert(events[e], self)
end
function Methods:Click(button)
  if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
end

function CreateFrame(kind, name, parent, template)
  local f = newObj(kind, name, parent)
  f.template = template
  if name then _G[name] = f end
  AllFrames[#AllFrames + 1] = f
  return f
end

UIParent = newObj("Frame", "UIParent")

function Fire(event, ...)
  for _, f in ipairs(events[event] or {}) do
    if f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

-- game state
function InCombatLockdown() return false end
function UnitName() return "Aztek" end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }
ChatTypeInfo = setmetatable({}, { __index = function() return { r = 0.5, g = 0.6, b = 0.7 } end })
SOUNDKIT = { TELL_MESSAGE = 3081 }
SoundsPlayed = 0
function PlaySound() SoundsPlayed = SoundsPlayed + 1 end

-- chat calls the alerts make
Calls = {}
function ChatFrame_SendTell(name) Calls[#Calls + 1] = "tell:" .. name end
function ChatFrame_SendBNetTell(name) Calls[#Calls + 1] = "bnet:" .. name end
function ChatFrame_OpenChat(text) Calls[#Calls + 1] = "open:" .. text end

-- chat filters (other add-ons)
Filters = {}
function ChatFrame_GetMessageEventFilters(event) return Filters[event] end

-- options panel
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name)
    Settings.registered = { frame = frame, name = name }
    return { GetID = function() return 42 end }
  end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function(id) Settings.opened = id end,
}
function UIDropDownMenu_Initialize(dd, fn) dd.init = fn end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText(dd, t) dd.text = t end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function CloseDropDownMenus() end
