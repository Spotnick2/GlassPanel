-- Settings.lua: GlassPanelDB's defaults, and the one place a setting is
-- changed and applied. /gpanel, the options panel (#24) and an imported
-- setup (#34) all go through here, so they can't drift apart.

GlassPanel = GlassPanel or {}
local Glass, Bar, Layout = GlassPanel.Glass, GlassPanel.Bar, GlassPanel.Layout
local Settings = {}
GlassPanel.Settings = Settings

Settings.DEFAULTS = { font = "arial", shown = true, room = "auto", labels = true }

local function db() return GlassPanelDB end

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
    if not Glass.FONTS[d.font] then d.font = Settings.DEFAULTS.font end
    if d.room ~= "auto" and d.room ~= "full" then d.room = Settings.DEFAULTS.room end
    return d
end

-- false when the font isn't known.
function Settings.SetFont(key)
    if not Glass.SetFont(key) then return false end
    db().font = key
    Bar.Layout()   -- every width depends on the font: remeasure
    return true
end

function Settings.SetShown(shown)
    db().shown = shown and true or false
    Bar.SetShown(db().shown)
end

-- false when the mode isn't "auto" or "full".
function Settings.SetRoom(mode)
    if mode ~= "auto" and mode ~= "full" then return false end
    db().room = mode
    GlassPanel.Room.Update()
    return true
end

-- The gold captions, for every block.
function Settings.SetLabels(on)
    db().labels = on and true or false
    Bar.RefreshCaptions()
end

-- One block's caption: true, false, or nil (follow the global setting).
function Settings.SetLabelFor(id, value)
    db().labelsFor[id] = value
    Bar.RefreshCaptions()
end

-- One block's icon; only "off" is stored (a block shows its icon by default).
function Settings.SetIconFor(id, shown)
    if shown then db().iconsFor[id] = nil else db().iconsFor[id] = false end
    Bar.RefreshIcons()
end

function Settings.SetHidden(id, hidden)
    db().hidden[id] = hidden and true or nil
    Bar.Layout()
end

function Settings.ResetLayout()
    Layout.Reset()
    Bar.Layout()
end
