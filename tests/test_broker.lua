-- [Broker] (#179): other addons' LibDataBroker-1.1 data sources as blocks,
-- against the REAL LibDataBroker-1.1 and CallbackHandler-1.0 the plugin
-- bundles. Off until picked; data sources only; AltStable's left out while
-- [AltStable] is loaded; text (value + suffix), label, icon (+ coords),
-- clicks, the three tooltip kinds in Titan's order; brokers before and after
-- us; a picked broker that throws is recorded, never raised.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelBroker" }

local LIBS = { "Plugins/Broker/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua",
               "Plugins/Broker/Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua" }

-- Another addon that embeds LibDataBroker and makes its objects before ours
-- loads (opts.before: after the core's files, so LibStub exists).
local function early(objects)
    return function()
        for _, f in ipairs(LIBS) do assert(loadfile(f))() end
        local LDB = LibStub("LibDataBroker-1.1")
        for name, o in pairs(objects) do LDB:NewDataObject(name, o) end
    end
end
local function LDB() return LibStub("LibDataBroker-1.1") end
local function T() return GlassPanel.Engine.optionSets[1]._test end
local function B(name) return block("ldb:" .. name) end
local function open()
    local panel = GlassPanel.Options._test.panel
    panel:Hide(); panel:Show()
    local btn = GlassPanel.Options._test.controls["options:set:broker:1"]
    check(btn ~= nil, "a 'Choose data brokers...' button under Plugin options")
    btn._scripts.OnClick(btn)
    return T().picker.Window()
end
local function rowFor(id)
    for _, r in ipairs(T().picker.rows) do if r.id == id and r:IsShown() then return r end end
end
local function tick(id, on)
    local r = rowFor(id)
    r.check:SetChecked(on); r.check._scripts.OnClick(r.check)
    WoW.tick()
end
local function names(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.id end
    return table.concat(out, ",")
end

--------------------------------------------------------------------------------
-- Offered, off until picked
--------------------------------------------------------------------------------

GlassPanelBrokerDB = nil
local clicks = {}
loadAddon({ before = early({
    Fps = { type = "data source", text = "60 fps", label = "FPS", icon = "Interface\\Icons\\fps",
            OnClick = function(frame, button) clicks[#clicks + 1] = { frame, button } end,
            OnTooltipShow = function(tt) tt:AddLine("Frames per second") end },
    Launch = { type = "launcher", icon = 1, OnClick = function() end },
    Untyped = { text = "?" },
    AltStable = { type = "data source", text = "1g", label = "AltStable", icon = 8197123 },
}) })
eq(B("Fps"), nil, "nothing picked: no block")
eq(names(T().available()), "AltStable,Fps", "data sources only, by label ([AltStable] isn't loaded)")
eq(#GlassPanel.Engine.blocks, 0, "no blocks at all")
local win = open()
eq(win and win._shown, true, "the button opens the chooser")
local r = rowFor("Fps")
check(r ~= nil, "Fps has a row")
eq(r.text._text, "|TInterface\\Icons\\fps:16:16|t FPS  |cffaaaaaaFps|r", "its icon, label and name")
eq(r.check:GetChecked(), false, "unticked")
eq(r.up:IsShown(), false, "no Up/Down (ordered = false)")

-- Ticked: a block, at once.
tick("Fps", true)
eq(table.concat(GlassPanelBrokerDB.picks, ","), "Fps", "saved by name")
check(B("Fps") ~= nil, "Fps has a block")
eq(textOf("ldb:Fps"), "60 fps", "its text")
eq(B("Fps").widget.caption._text, "FPS: ", "its label is the caption")
eq(B("Fps").widget.icon._file, "Interface\\Icons\\fps", "its icon")
eq(table.concat(B("Fps").widget.icon._coords, ","), "0,1,0,1", "the whole texture (no iconCoords)")
eq(B("Fps").widget.icon._shown, true, "shown")
eq(rowFor("Fps").up:IsShown(), false, "still no Up/Down once ticked")

-- The broker changes: the block follows on the next frame.
LDB():GetDataObjectByName("Fps").text = "59 fps"
WoW.tick()
eq(textOf("ldb:Fps"), "59 fps", "text follows")
LDB():GetDataObjectByName("Fps").label = "Frames"
WoW.tick()
eq(B("Fps").widget.caption._text, "Frames: ", "label follows")
LDB():GetDataObjectByName("Fps").iconCoords = { 0.1, 0.9, 0.2, 0.8 }
WoW.tick()
eq(table.concat(B("Fps").widget.icon._coords, ","), "0.1,0.9,0.2,0.8", "iconCoords honoured")
LDB():GetDataObjectByName("Fps").icon = 12345
WoW.tick()
eq(B("Fps").widget.icon._file, 12345, "icon follows")
local withIcon = B("Fps").widget._width
LDB():GetDataObjectByName("Fps").icon = nil
WoW.tick()
eq(B("Fps").widget.icon._shown, false, "no icon: none drawn")
eq(B("Fps").widget.textX, 4, "and the text starts at the edge")
eq(B("Fps").widget._width, withIcon - 18, "the block narrows by the icon")
LDB():GetDataObjectByName("Fps").icon = 12345
WoW.tick()
eq(B("Fps").widget.icon._shown, true, "back")

-- Clicks: the broker gets our button and the mouse button.
local w = B("Fps").widget
WoW.now = WoW.now + 1
w._scripts.OnClick(w, "RightButton")
eq(#clicks, 1, "OnClick called")
check(clicks[1][1] == w and clicks[1][2] == "RightButton", "with the block's frame and the button")
w._scripts.OnDoubleClick(w, "LeftButton")
eq(#clicks, 2, "no OnDoubleClick: the second click goes to OnClick")

-- OnTooltipShow fills the core's tooltip.
w._scripts.OnEnter(w)
eq(GameTooltip._owner, w, "our GameTooltip, owned by the block")
eq(table.concat(GameTooltip._lines, "\n"), "Frames per second", "OnTooltipShow's lines")
eq(GameTooltip._shown, true, "shown")
-- An open tooltip is redrawn when the broker changes.
local o = LDB():GetDataObjectByName("Fps")
o.OnTooltipShow = function(tt) tt:AddLine("now " .. o.text) end
o.text = "58 fps"
WoW.tick()
eq(table.concat(GameTooltip._lines, "\n"), "now 58 fps", "redrawn after a change")
w._scripts.OnLeave(w)
eq(GameTooltip._shown, false, "hidden on leave")

-- Unticked: off the bar at once; the pick is gone.
tick("Fps", false)
eq(#GlassPanelBrokerDB.picks, 0, "unticked: not saved")
eq(B("Fps").widget._shown, false, "its block left the bar")
tick("Fps", true)
eq(B("Fps").widget._shown, true, "ticked again: back")
eq(#WoW.secureErrors, 0, "no callback threw")

--------------------------------------------------------------------------------
-- A /reload: the picks come back at login; a pick whose addon is gone is kept
--------------------------------------------------------------------------------

GlassPanelBrokerDB = { picks = { "Fps", "Gone", "Fps", 7 } }
loadAddon({ reload = true, before = early({ Fps = { type = "data source", text = "30 fps" } }) })
eq(textOf("ldb:Fps"), "30 fps", "a saved pick has its block at login")
eq(B("Gone"), nil, "a pick whose broker isn't here: no block")
open()
eq(rowFor("Gone"), nil, "and no row")
tick("Fps", false)
eq(table.concat(GlassPanelBrokerDB.picks, ","), "Gone", "but kept when the picks change (duplicates and junk dropped)")

--------------------------------------------------------------------------------
-- Late brokers
--------------------------------------------------------------------------------

GlassPanelBrokerDB = { picks = { "Late", "Typed" } }
loadAddon()
eq(B("Late"), nil, "not here yet")
open()
LDB():NewDataObject("Late", { type = "data source", text = "hello" })
WoW.tick()
eq(textOf("ldb:Late"), "hello", "a picked broker made after login gets its block")
local typed = LDB():NewDataObject("Typed", { text = "t" })
WoW.tick()
eq(B("Typed"), nil, "no type yet: not a data source")
typed.type = "data source"
WoW.tick()
eq(textOf("ldb:Typed"), "t", "typed after creation: its block")
LDB():NewDataObject("New", { type = "data source", text = "n" })
WoW.flushTimers(0); WoW.tick()
check(rowFor("New") ~= nil, "an open chooser lists a new broker")
eq(B("New"), nil, "unpicked: no block")

--------------------------------------------------------------------------------
-- The text: value + suffix, secrets, junk
--------------------------------------------------------------------------------

GlassPanelBrokerDB = { picks = { "V", "S", "N", "E" } }
loadAddon({ before = early({
    V = { type = "data source", value = "12", suffix = "ms" },
    S = { type = "data source", text = "x" },
    N = { type = "data source", text = 42 },
    E = { type = "data source", text = "" },
}) })
eq(textOf("ldb:V"), "12 ms", "no text: value and suffix")
eq(textOf("ldb:N"), "42", "a number is written out")
eq(B("E").widget._shown, false, "empty text: no space")
LDB():GetDataObjectByName("S").text = WoW.Secret("broker text")
WoW.tick()
eq(textOf("ldb:S"), "|cffaaaaaa?|r", "a secret text: a grey ?")
LDB():GetDataObjectByName("S").label = WoW.Secret("broker label")
WoW.tick()
eq(B("S").widget.caption._text, "S: ", "a secret label: the broker's name")
LDB():GetDataObjectByName("S").icon = WoW.Secret("broker icon")
WoW.tick()
eq(B("S").widget.icon._shown, false, "a secret icon: none")
LDB():GetDataObjectByName("S").icon = "x"
LDB():GetDataObjectByName("S").iconCoords = { 0, "a", 0, 1 }
WoW.tick()
check(GlassPanel.failures["ldb:S:icon"] ~= nil, "bad iconCoords are recorded")
eq(table.concat(B("S").widget.icon._coords, ","), "0.08,0.92,0.08,0.92", "and the stock trim drawn")

--------------------------------------------------------------------------------
-- The hover, in Titan's order: a tooltip frame, OnEnter, OnTooltipShow
--------------------------------------------------------------------------------

local entered, left = {}, {}
local tipFrame
GlassPanelBrokerDB = { picks = { "Frame", "Enter", "Plain" } }
loadAddon({ before = function()
    early({
        Enter = { type = "data source", text = "e",
                  OnEnter = function(f) entered[#entered + 1] = f end,
                  OnLeave = function(f) left[#left + 1] = f end,
                  OnTooltipShow = function(tt) tt:AddLine("never") end },
        Plain = { type = "data source", text = "p", label = "Plainly" },
    })()
    tipFrame = CreateFrame("Frame", nil, UIParent)
    tipFrame:Hide()
    LDB():NewDataObject("Frame", { type = "data source", text = "f", tooltip = tipFrame,
                                   OnEnter = function() entered[#entered + 1] = "frame's" end })
end })
GameTooltip:Hide()
local fw = B("Frame").widget
fw._scripts.OnEnter(fw)
eq(tipFrame._shown, true, "a tooltip frame is shown")
eq(tipFrame._points[1][2], fw, "anchored to the block")
eq(#entered, 0, "it wins over OnEnter")
eq(GameTooltip._shown, false, "and no GameTooltip of ours")
fw._scripts.OnLeave(fw)
eq(tipFrame._shown, false, "hidden on leave")

local ew = B("Enter").widget
ew._scripts.OnEnter(ew)
eq(entered[1], ew, "OnEnter gets the block's frame")
eq(GameTooltip._shown, false, "OnEnter does it all: no tooltip of ours")
LDB():GetDataObjectByName("Enter").text = "e2"
WoW.tick()
eq(#entered, 1, "a repaint doesn't call OnEnter again")
ew._scripts.OnLeave(ew)
eq(left[1], ew, "OnLeave gets it too")

local pw = B("Plain").widget
pw._scripts.OnEnter(pw)
eq(table.concat(GameTooltip._lines, "\n"), "Plainly\np", "no tooltip method: its label and text")
pw._scripts.OnLeave(pw)

-- A broker that throws: recorded under its block, never raised.
LDB():GetDataObjectByName("Enter").OnEnter = function() error("boom") end
ew._scripts.OnEnter(ew)
check(GlassPanel.failures["ldb:Enter:onEnter"] ~= nil, "a throwing OnEnter is recorded")
eq(table.concat(GameTooltip._lines, "\n"), "never", "and the core's tooltip stands in (OnTooltipShow)")
ew._scripts.OnLeave(ew)
LDB():GetDataObjectByName("Enter").OnClick = function() error("click") end
WoW.now = WoW.now + 1
ew._scripts.OnClick(ew, "LeftButton")
check(GlassPanel.failures["ldb:Enter:onClick"] ~= nil, "a throwing OnClick is recorded")
LDB():GetDataObjectByName("Enter").OnDoubleClick = function(f, b) entered[#entered + 1] = b end
ew._scripts.OnDoubleClick(ew, "RightButton")
eq(entered[#entered], "RightButton", "OnDoubleClick when it has one")

--------------------------------------------------------------------------------
-- AltStable's broker: left out while [AltStable] is loaded
--------------------------------------------------------------------------------

GlassPanelBrokerDB = { picks = { "AltStable" } }
loadAddon({ plugins = { "GlassPanelBroker", "GlassPanelAltStable" },
            before = early({ AltStable = { type = "data source", text = "1g" } }) })
eq(B("AltStable"), nil, "picked, but [AltStable] shows it: no block")
eq(names(T().available()), "", "and not offered")
check(block("altstable") ~= nil, "(the native block is there)")

done("test_broker")
