-- Options.lua: the options panel (#24), Game Menu > Options > AddOns >
-- Glass Panel. A canvas panel on Retail's Settings framework
-- (Settings.RegisterCanvasLayoutCategory + RegisterAddOnCategory), as
-- GlassUnitFrames (#39) and Priestly do on Forever. UICheckButtonTemplate,
-- UIRadioButtonTemplate, UIPanelButtonTemplate and UIPanelScrollFrameTemplate
-- all exist here (porting guide). No UIDropDownMenu: choices are radios.
--
-- Everything goes through GlassPanel.Settings, the same setters as /gpanel,
-- and the panel re-reads the state every time it opens, so a slash command
-- never leaves it showing stale values. Plugins that register after the
-- panel was first built get their row the next time it opens.

GlassPanel = GlassPanel or {}
local API, Engine, Bar, Settings = GlassPanel.API, GlassPanel.Engine, GlassPanel.Bar, GlassPanel.Settings
local Options = {}
GlassPanel.Options = Options

local panel = CreateFrame("Frame", "GlassPanelOptions")
panel.name = "Glass Panel"
local refreshers = {}    -- re-read one control's state; run on open and after any change
local widgets = {}       -- named controls (tests)
local rows = {}          -- block id -> its plugin row
local category

local function db() return GlassPanelDB end

-- Everything sits in a scroll child: the plugin list grows with plugins.
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(660, 600)
scroll:SetScrollChild(content)
API.AutoHideScrollBar(scroll)

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function label(text, template)
    local fs = content:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

-- A column laid out top to bottom.
local function column(x, top) return { x = x, y = top } end

local function place(col, region, height, indent)
    region:SetPoint("TOPLEFT", content, "TOPLEFT", col.x + (indent or 0), col.y)
    col.y = col.y - height
end

local function header(col, text)
    col.y = col.y - 6
    place(col, label(text, "GameFontNormalLarge"), 26)
end

local function note(col, text, width, height)
    local fs = label(text, "GameFontHighlightSmall")
    fs:SetWidth(width or 300)
    place(col, fs, height or 18, 4)
end

local function button(col, text, width, onClick)
    local b = API.Button(content, text, width, onClick)
    place(col, b, 28, 4)
    return b
end

local function refreshAll()
    for i, fn in ipairs(refreshers) do
        local ok, err = pcall(fn)
        if not ok then API.Fail("options:control " .. i, err) end
    end
end

-- A check button with its text on the right (none when text is nil).
local function checkButton(text, radio)
    local cb = CreateFrame("CheckButton", nil, content, radio and "UIRadioButtonTemplate" or "UICheckButtonTemplate")
    if not radio then cb:SetSize(24, 24) end
    if text then
        cb.label = label(text)
        cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    end
    return cb
end

-- get() -> bool; set(bool). Everything is re-read after a click (one
-- setting can change what another row shows: captions).
local function checkbox(col, text, get, set)
    local cb = checkButton(text)
    place(col, cb, 28, 4)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        refreshAll()
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

-- Hand-built slider (GlassUnitFrames' Options.lua): the text and the value on
-- one line, the track under it. get() -> number; set(number), rounded to the
-- step. Refreshing it (SetValue fires OnValueChanged) never writes back.
local SLIDER_W = 200
local function slider(col, text, min, max, step, fmt, get, set)
    local fs = label(text)
    local value = label("")
    value:SetPoint("LEFT", fs, "LEFT", SLIDER_W + 12, 0)
    place(col, fs, 18, 4)
    local s = CreateFrame("Slider", nil, content)
    s:SetSize(SLIDER_W, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.3, 0.9)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    place(col, s, 26, 8)
    local refreshing = false
    local function show(v) value:SetText(string.format(fmt, v)) end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.max(min, math.min(max, math.floor((v - min) / step + 0.5) * step + min))
        show(v)
        if refreshing then return end
        set(v)
        refreshAll()
    end)
    refreshers[#refreshers + 1] = function()
        local v = get()
        if type(v) ~= "number" or v ~= v then v = min end
        v = math.max(min, math.min(max, v))
        refreshing = true
        s:SetValue(v)
        refreshing = false
        show(v)
    end
    return s
end

-- Mutually exclusive choices: { { value, text }, ... }.
-- `locked()` (optional) greys the group out: its setting is suspended (#96).
local function radios(col, title, options, get, set, locked)
    if title then place(col, label(title), 22, 4) end
    local group = {}
    for _, o in ipairs(options) do
        local rb = checkButton(o[2], true)
        rb.value = o[1]
        rb:SetScript("OnClick", function()
            set(o[1])
            refreshAll()   -- a refused choice snaps back
        end)
        place(col, rb, 22, 8)
        group[#group + 1] = rb
    end
    refreshers[#refreshers + 1] = function()
        local current = get()
        local off = locked and locked() and true or false
        for _, rb in ipairs(group) do
            rb:SetChecked(rb.value == current)
            rb:SetEnabled(not off)
            rb:SetAlpha(off and 0.35 or 1)
        end
    end
    return group
end

--------------------------------------------------------------------------------
-- Plugin rows
--------------------------------------------------------------------------------

local NAME_W, COL_W = 140, 56   -- the name, then one column per toggle

local function greyed(cb, off)
    cb:SetEnabled(not off)
    cb:SetAlpha(off and 0.35 or 1)
end

-- One row: the block's name, then Shown, Caption, Icon. Placed by
-- layoutRows (the list is re-sorted when a plugin comes in late).
local function pluginRow(block)
    local id = block.id
    local name = label(block.label or id)
    name:SetWidth(NAME_W)
    local row = { name = name, sortKey = (block.label or id):lower() }
    local function toggle(i, get, set)
        local cb = checkButton(nil)
        cb:SetPoint("LEFT", name, "LEFT", NAME_W + (i - 1) * COL_W, 0)
        cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
        return cb
    end
    row.shown = toggle(1, function() return not Bar.IsHidden(block) end,
        function(v) Settings.SetHidden(id, not v) end)
    row.caption = toggle(2, function() return Bar.ShowsCaption(block) end,
        function(v) Settings.SetLabelFor(id, v) end)
    row.icon = toggle(3, function() return Bar.ShowsIcon(block) end,
        function(v) Settings.SetIconFor(id, v) end)
    -- A graphical block never has a caption; a block without an icon has
    -- nothing to show.
    greyed(row.caption, block.width ~= nil)
    greyed(row.icon, block.icon == nil)
    rows[id] = row
    return row
end

local pluginCol, rowsTop
local ROW_H = 26

-- A row for every registered block, all in name order (a late plugin
-- goes where its name sorts, not at the bottom).
local function layoutRows()
    for _, block in ipairs(Engine.blocks) do
        if not rows[block.id] then pluginRow(block) end
    end
    local list = {}
    for _, row in pairs(rows) do list[#list + 1] = row end
    table.sort(list, function(a, b) return a.sortKey < b.sortKey end)
    for i, row in ipairs(list) do
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", content, "TOPLEFT", pluginCol.x + 4, rowsTop - (i - 1) * ROW_H)
    end
    pluginCol.y = rowsTop - #list * ROW_H
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local left

-- Plugin options: a block's own on/off settings (spec.options), under
-- "Plugin options" in the left column, one group per plugin, added the
-- first time the panel opens after the plugin registered. get/set are the
-- plugin's code: both run under pcall, a throw is recorded, never raised.
local optionBlocks = {}   -- block id -> true once its options are on the panel
local optionsHeader = false
local function addPluginOptions()
    for _, block in ipairs(Engine.blocks) do
        if block.options and #block.options > 0 and not optionBlocks[block.id] then
            optionBlocks[block.id] = true
            if not optionsHeader then
                optionsHeader = true
                header(left, "Plugin options")
            end
            place(left, label(block.label or block.id, "GameFontNormal"), 22, 4)
            for i, o in ipairs(block.options) do
                local key = "options:" .. block.id .. ":" .. i
                if type(o.run) == "function" then
                    widgets[key] = button(left, o.label, 200, function()
                        local ok, err = pcall(o.run)
                        if not ok then API.Fail(key, err) end
                    end)
                elseif o.min ~= nil then
                    widgets[key] = slider(left, o.label, o.min, o.max, o.step or 0.05, o.fmt or "%.2f",
                        function()
                            local ok, v = pcall(o.get)
                            if not ok then API.Fail(key .. ":get", v) return nil end
                            return API.Plain(v)
                        end,
                        function(v)
                            local ok, err = pcall(o.set, v)
                            if not ok then API.Fail(key, err) end
                        end)
                else
                    widgets[key] = checkbox(left, o.label,
                        function()
                            local ok, v = pcall(o.get)
                            if not ok then API.Fail(key .. ":get", v) return false end
                            return v
                        end,
                        function(v)
                            local ok, err = pcall(o.set, v)
                            if not ok then API.Fail(key, err) end
                        end)
                end
                if o.note then note(left, o.note) end
            end
        end
    end
end

local function build()
    local title = label("Glass Panel", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    local sub = label("A liquid-glass info bar. Drag blocks on the bar to move them; /gpanel lists the commands.",
        "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -6)

    left = column(16, -72)
    pluginCol = column(340, -72)

    header(left, "Bar")
    widgets.shown = checkbox(left, "Show the bar",
        function() return db().shown end, Settings.SetShown)
    widgets.labels = checkbox(left, "Captions on every block",
        function() return db().labels end, Settings.SetLabels)
    note(left, "A plugin's own Caption box (right) wins over this.")
    widgets.font = radios(left, "Font", { { "arial", "Arial Narrow" }, { "friz", "Friz Quadrata" } },
        function() return db().font end, Settings.SetFont)
    widgets.room = radios(left, "Width", { { "auto", "Stop short of Blizzard's top frames" },
        { "full", "Always full width" } },
        function() return db().room end, Settings.SetRoom)
    widgets.glass = radios(left, "Glass", { { "clear", "Clear" }, { "smoked", "Smoked" } },
        function() return db().glass end, Settings.SetGlass, GlassPanel.Suite.Following)
    widgets.glassTint = radios(left, "Tint", { { "neutral", "Neutral" }, { "class", "Class colour" } },
        function() return db().glassTint end, Settings.SetGlassTint, GlassPanel.Suite.Following)
    widgets.windowGlass = radios(left, "Windows", { { "reflective", "Reflective" }, { "smoked", "Smoked" } },
        function() return db().windowGlass end, Settings.SetWindowGlass, GlassPanel.Suite.Following)
    note(left, "Share, Setup and the other dialogs. A window already open keeps its look until /reload.", 300, 32)   -- two lines at this width
    -- Following Glass UI (#96): the body, its tint and the windows are set there; ours stay saved.
    local suiteNote = label("Following Glass UI (Pearl): the glass, its tint and the windows are set in Glass UI.", "GameFontHighlightSmall")
    suiteNote:SetWidth(300)
    place(left, suiteNote, 34, 4)
    widgets.suiteButton = button(left, "Open Glass UI", 160, function() GlassPanel.Suite.Open() end)
    refreshers[#refreshers + 1] = function()
        local on = GlassPanel.Suite.Following()
        suiteNote:SetShown(on)
        widgets.suiteButton:SetShown(on and GlassPanel.Suite.CanOpen())
    end

    header(left, "Layout")
    note(left, "Drag a block to move it; shift-drag moves its whole lane.")
    widgets.reset = button(left, "Reset layout", 160, function()
        Settings.ResetLayout()
        API.Print("layout reset")
    end)
    note(left, "Or move Blizzard's top frames below a full-width bar:")
    widgets.setup = button(left, "Make room in Edit Mode...", 200, function() GlassPanel.Setup.Open() end)
    widgets.setupBack = button(left, "Switch back", 200, function()
        local _, msg = GlassPanel.Setup.SwitchBack()
        API.Print(msg)
    end)

    header(left, "Share setup")
    note(left, "Copy this bar's whole setup to another account.")
    widgets.export = button(left, "Export...", 160, function() GlassPanel.Share.Open("export") end)
    widgets.import = button(left, "Import...", 160, function() GlassPanel.Share.Open("import") end)

    header(pluginCol, "Plugins")
    local heads = { "Shown", "Caption", "Icon" }
    for i, h in ipairs(heads) do
        local fs = label(h, "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", pluginCol.x + 4 + NAME_W + (i - 1) * COL_W - 4, pluginCol.y)
    end
    pluginCol.y = pluginCol.y - 20
    rowsTop = pluginCol.y
end

panel:SetScript("OnShow", function(self)
    if not self.built then
        self.built = true
        build()
    end
    layoutRows()
    addPluginOptions()
    content:SetHeight(math.max(-left.y, -pluginCol.y) + 16)
    refreshAll()
end)

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

-- Blizzard's Settings framework is the GLOBAL Settings (our setters are the
-- local of the same name above), read with rawget.
local function register()
    local S = rawget(_G, "Settings")
    if category or type(S) ~= "table" then return end
    if not (S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory) then return end
    local ok, c = pcall(S.RegisterCanvasLayoutCategory, panel, panel.name)
    if not (ok and c) then API.Fail("options:register", c) return end
    category = c
    local ok2, err = pcall(S.RegisterAddOnCategory, category)
    if not ok2 then API.Fail("options:register", err) end
end

-- Open the panel; false when the Settings framework can't (a throw from
-- GetID included). Opened from nothing (the Options window closed), the
-- client has shown Glass Panel selected with an empty page (#104, seen from
-- Glass UI's button). OpenToCategory again would do nothing (Blizzard's
-- SelectCategory skips a category that is already the current one), so a
-- frame later, if our page still isn't up, the selection is forced:
-- SettingsPanel:ActivateCategory(category, true) displays the canvas again.
local function openToCategory()
    local S = rawget(_G, "Settings")
    if not (category and type(S) == "table" and S.OpenToCategory) then return false end
    return pcall(function() return S.OpenToCategory(category:GetID()) end) and true or false
end
function Options.Open()
    local ok = openToCategory()
    if ok and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if panel:IsVisible() then return end
            local ok, err = pcall(function()
                local P = rawget(_G, "SettingsPanel")
                P:ActivateCategory(P:GetCategoryList():GetCategory(category:GetID()), true)
            end)
            if not ok then API.Fail("options:redisplay", err) end
        end)
    end
    return ok
end

-- A setting changed (from /gpanel, an import, this panel): an open panel
-- shows it at once, never a stale box that would write the opposite.
Settings.listener = function()
    if panel.built and panel:IsVisible() then refreshAll() end
end

local reg = CreateFrame("Frame")
API.RegisterEvent(reg, "PLAYER_LOGIN", "options")
reg:SetScript("OnEvent", register)

Options._test = { panel = panel, scroll = scroll, controls = widgets, refreshers = refreshers, rows = rows,
                  category = function() return category end }
