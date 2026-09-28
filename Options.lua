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

local function note(col, text, width)
    local fs = label(text, "GameFontHighlightSmall")
    fs:SetWidth(width or 300)
    place(col, fs, 18, 4)
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

-- Mutually exclusive choices: { { value, text }, ... }.
local function radios(col, title, options, get, set)
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
        for _, rb in ipairs(group) do rb:SetChecked(rb.value == current) end
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

    header(left, "Layout")
    note(left, "Drag a block to move it; shift-drag moves its whole lane.")
    widgets.reset = button(left, "Reset layout", 160, function()
        Settings.ResetLayout()
        API.Print("layout reset")
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
-- GetID included).
function Options.Open()
    local S = rawget(_G, "Settings")
    if not (category and type(S) == "table" and S.OpenToCategory) then return false end
    return pcall(function() return S.OpenToCategory(category:GetID()) end) and true or false
end

-- A setting changed (from /gpanel, an import, this panel): an open panel
-- shows it at once, never a stale box that would write the opposite.
Settings.listener = function()
    if panel.built and panel:IsVisible() then refreshAll() end
end

local reg = CreateFrame("Frame")
API.RegisterEvent(reg, "PLAYER_LOGIN", "options")
reg:SetScript("OnEvent", register)

Options._test = { panel = panel, controls = widgets, refreshers = refreshers, rows = rows,
                  category = function() return category end }
