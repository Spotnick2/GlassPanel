-- Settings.lua: GlassPanelDB's defaults, and the one place a setting is
-- changed and applied. /gpanel, the options panel (#24) and an imported
-- setup (#34) all go through here, so they can't drift apart.

GlassPanel = GlassPanel or {}
local Glass, Bar, Layout = GlassPanel.Glass, GlassPanel.Bar, GlassPanel.Layout
local Settings = {}
GlassPanel.Settings = Settings

Settings.DEFAULTS = { font = "arial", shown = true, room = "auto", labels = true }

local function db() return GlassPanelDB end

-- Called after any setting changes, however it was changed (the options
-- panel sets this to re-read its controls while it's open).
Settings.listener = nil
local function changed()
    if Settings.listener then
        local ok, err = pcall(Settings.listener)
        if not ok then GlassPanel.API.Fail("settings:listener", err) end
    end
end

-- Read settings, fill missing keys. Nothing may REQUIRE a value to have
-- survived: SavedVariables were broken on builds before 70009.
function Settings.EnsureDefaults()
    if type(GlassPanelDB) ~= "table" then GlassPanelDB = {} end
    local d = GlassPanelDB
    for k, v in pairs(Settings.DEFAULTS) do
        if d[k] == nil then d[k] = v end
    end
    if type(d.hidden) ~= "table" then d.hidden = {} end
    if type(d.labelsFor) ~= "table" then d.labelsFor = {} end
    if type(d.iconsFor) ~= "table" then d.iconsFor = {} end
    if d.editModeReturn ~= nil and type(d.editModeReturn) ~= "table" then d.editModeReturn = nil end
    if not Glass.FONTS[d.font] then d.font = Settings.DEFAULTS.font end
    if d.room ~= "auto" and d.room ~= "full" then d.room = Settings.DEFAULTS.room end
    return d
end

-- false when the font isn't known.
function Settings.SetFont(key)
    if not Glass.SetFont(key) then return false end
    db().font = key
    Bar.Layout()   -- every width depends on the font: remeasure
    changed()
    return true
end

function Settings.SetShown(shown)
    db().shown = shown and true or false
    Bar.SetShown(db().shown)
    changed()
end

-- false when the mode isn't "auto" or "full".
function Settings.SetRoom(mode)
    if mode ~= "auto" and mode ~= "full" then return false end
    db().room = mode
    GlassPanel.Room.Update()
    changed()
    return true
end

-- The gold captions, for every block.
function Settings.SetLabels(on)
    db().labels = on and true or false
    Bar.RefreshCaptions()
    changed()
end

-- One block's caption: true, false, or nil (follow the global setting).
function Settings.SetLabelFor(id, value)
    db().labelsFor[id] = value
    Bar.RefreshCaptions()
    changed()
end

-- One block's icon; only "off" is stored (a block shows its icon by default).
function Settings.SetIconFor(id, shown)
    if shown then db().iconsFor[id] = nil else db().iconsFor[id] = false end
    Bar.RefreshIcons()
    changed()
end

function Settings.SetHidden(id, hidden)
    db().hidden[id] = hidden and true or nil
    Bar.Layout()
    changed()
end

function Settings.ResetLayout()
    Layout.Reset()
    Bar.Layout()
    changed()
end

local function copyMap(m)
    local out = {}
    for k, v in pairs(m or {}) do out[k] = v end
    return out
end

-- Replace the whole setup (an import, #34: a table from Share.Clean) and
-- show it with one layout pass. Fresh tables throughout, so the layout
-- cache sees a new one.
function Settings.ApplyAll(setup)
    local d = db()
    d.font, d.shown, d.room, d.labels = setup.font, setup.shown, setup.room, setup.labels
    d.hidden, d.labelsFor, d.iconsFor = copyMap(setup.hidden), copyMap(setup.labelsFor), copyMap(setup.iconsFor)
    d.layout = Layout.Clean(setup.layout)
    Glass.SetFont(d.font)
    for _, block in ipairs(GlassPanel.Engine.blocks) do
        Bar.UpdateIcon(block)
        Bar.UpdateCaption(block)
    end
    if Bar.frame then Bar.frame:SetShown(d.shown) end
    GlassPanel.Room.Update()
    Bar.Layout()
    changed()
end
