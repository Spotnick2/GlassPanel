-- Bar.lua: the glass strip across the top of the screen, one button per block,
-- and the layout. It knows how to draw a block, never what a block means.
--
-- Where blocks go is Layout.lua's model (free lanes, #6); this file places
-- the widgets, and lets the user drag them: drop near a gap to join that
-- lane, on empty space to start a lane, shift-drag to move a whole lane.
-- A block's width follows its text, so a relayout runs after any flush that
-- repainted something.
--
-- Nothing here is secure: the bar parents no secure frame, so it can be
-- shown, hidden and relaid out in combat.

GlassPanel = GlassPanel or {}
local API, Glass, Engine, Layout = GlassPanel.API, GlassPanel.Glass, GlassPanel.Engine, GlassPanel.Layout
local Bar = {}
GlassPanel.Bar = Bar

Bar.HEIGHT = 24         -- UIParent units; the screen is 768 tall at default scale
Bar.FONT_SIZE = 12
local ICON = 14
local PAD = 4           -- inside a block, around icon and text

local function db() return GlassPanelDB end

-- Whether the block is (or, when not yet laid out, may be) on screen: not
-- hidden by the user, and the bar shown.
function Bar.OnScreen(block)
    return not Bar.IsHidden(block) and Bar.frame ~= nil and Bar.frame:IsShown()
end

-- Whether a block shows its caption: never for a graphical (fixed-width)
-- block; else the user's per-block choice, then the global switch, then the
-- block's own default (showLabel = false opts out, like Gold and Clock).
function Bar.ShowsCaption(block)
    if block.width then return false end
    local d = db()
    local per = d and d.labelsFor and d.labelsFor[block.id]
    if per ~= nil then return per end
    if d and d.labels == false then return false end
    return block.showLabel ~= false
end

-- The caption's words: the block's caption(block) when it gives a plain,
-- non-empty string (Guild: the guild's name), else its label.
local function captionWords(block)
    if block.caption then
        local ok, res = Engine.Call(block, "caption", block.caption, block)
        res = ok and API.Plain(res) or nil
        if type(res) == "string" and res ~= "" then return res end
    end
    return block.label
end

-- Set the caption; true if it changed (its width moves what follows).
function Bar.UpdateCaption(block)
    local b = block.widget
    if not b then return false end
    local words = Bar.ShowsCaption(block) and (captionWords(block) .. ": ") or ""
    if b.captionText == words then return false end
    b.captionText = words
    b.caption:SetText(words)
    return true
end

-- After a caption setting changes: every block, then the layout.
function Bar.RefreshCaptions()
    for _, block in ipairs(Engine.blocks) do Bar.UpdateCaption(block) end
    Bar.Layout()
end

-- Whether a block shows its icon: it has one, and the user hasn't turned
-- it off (GlassPanelDB.iconsFor[id] = false, #24).
function Bar.ShowsIcon(block)
    if not block.icon then return false end
    local d = db()
    return not (d and d.iconsFor and d.iconsFor[block.id] == false)
end

-- What the value shows: the block's text, except that a graphical block
-- sized to its content this repaint (its width function said nil), with
-- empty text and no icon showing, shows its label: it would otherwise shrink
-- to a few pixels of nothing (XP+'s handle while zoomed with its icon off,
-- #78). b.text stays the block's own answer. True if the display changed.
local function syncDisplay(block)
    local b = block.widget
    local shown = b.text or ""
    if block.width ~= nil and b.fixedWidth == nil and b.text == "" and not Bar.ShowsIcon(block) then
        shown = block.label ~= "" and block.label or block.id
    end
    if b.shownText == shown then return false end
    b.shownText = shown
    b.label:SetText(shown)
    return true
end

-- Show or hide the icon, the caption starting after it or at the edge;
-- true if it changed (the width moves what follows).
function Bar.UpdateIcon(block)
    local b = block.widget
    if not (b and b.icon) then return false end
    local show = Bar.ShowsIcon(block)
    if b.iconShown == show then return false end
    b.iconShown = show
    b.icon:SetShown(show)
    b.textX = show and (PAD + ICON + PAD) or PAD
    b.caption:ClearAllPoints()
    b.caption:SetPoint("LEFT", b, "LEFT", b.textX, 0)
    -- The display may hang on the icon; the caller relays out without a repaint.
    if b.painted then syncDisplay(block) end
    return true
end

-- After an icon setting changes: every block, then the layout.
function Bar.RefreshIcons()
    for _, block in ipairs(Engine.blocks) do Bar.UpdateIcon(block) end
    Bar.Layout()
end

-- The block that stands in for this one right now (spec.replaces, #50:
-- [AltStable] replaces Gold), or nil. Live, never stored: only while the
-- replacing block is loaded and not hidden itself, and until the player shows
-- this one again (keep[id], Settings.SetHidden). So a character with the
-- replacing plugin off, or a refused block, keeps this one.
function Bar.ReplacedBy(block)
    local d = db()
    if not d or (type(d.keep) == "table" and d.keep[block.id]) then return nil end
    for _, other in ipairs(Engine.blocks) do
        if other.replaces == block.id and not (d.hidden and d.hidden[other.id]) then return other end
    end
    return nil
end

function Bar.IsHidden(block)
    local d = db()
    if d and d.hidden and d.hidden[block.id] == true then return true end
    return Bar.ReplacedBy(block) ~= nil
end

local function onEnter(button)
    local block = button.block
    if not block.tooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    -- The side the block's centre is on (a wide block's left edge can be left
    -- of the middle while most of it is right of it).
    if (button.left or 0) + button:GetWidth() / 2 > Bar.frame:GetWidth() / 2 then
        GameTooltip:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    else
        GameTooltip:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -4)
    end
    GameTooltip:ClearLines()
    if Engine.Call(block, "tooltip", block.tooltip, block, GameTooltip) then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

-- Redraw the tooltip if it's open on this block (called after a repaint).
function Bar.RefreshTooltip(block)
    local b = block.widget
    if b and b.visible and block.tooltip and GameTooltip:GetOwner() == b and GameTooltip:IsShown() then onEnter(b) end
end

local function onLeave(button)
    if GameTooltip:GetOwner() == button then GameTooltip:Hide() end
end

--------------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------------

local drag            -- { button, block, lane = shift-drag, startX, grab } while dragging
local lastDragStop = -1
local STILL = 10      -- px: a drag that moved less than this is a wobbly click

-- The cursor's x in bar coordinates.
local function cursorX()
    local x = GetCursorPosition()
    return x / Bar.frame:GetEffectiveScale() - (Bar.frame:GetLeft() or 0)
end

-- What a drop at the cursor would do. Cached per cursor x (the marker asks
-- every frame); Bar.Layout clears the cache, since a relayout mid-drag moves
-- the slots under a still cursor.
--   { none }  moved less than STILL px: a click that wobbled also starts a
--             drag, and must leave everything where it was;
--   { laneX } shift-drag: the whole lane moves by the cursor's displacement;
--   otherwise Layout.DropTarget, with the block released where the hand
--   left it (the cursor minus the grab offset), not centred on the cursor.
local function dropTarget()
    local cx = cursorX()
    if drag.cachedX == cx then return drag.cached end
    local W = Bar.frame:GetWidth()
    local t
    if math.abs(cx - drag.startX) < STILL then
        t = { none = true }
    elseif drag.lane then
        t = Layout.LaneTarget(Bar.geometry or {}, W, drag.block.id, cx - drag.startX)
    else
        t = Layout.DropTarget(Bar.geometry or {}, W, cx, drag.block.id, cx - drag.grab,
            drag.button:GetWidth())
    end
    drag.cachedX, drag.cached = cx, t
    return t
end

local function updateMarker()
    local t = dropTarget()
    Bar.marker:SetShown(not t.none)
    if t.none then return end
    Bar.marker:ClearAllPoints()
    Bar.marker:SetPoint("CENTER", Bar.content, "LEFT", t.slotX, 0)
end

local function onDragStart(button)
    local cx = cursorX()
    drag = { button = button, block = button.block, lane = IsShiftKeyDown(),
             startX = cx, grab = cx - (button.left or 0) }
    button:SetAlpha(0.4)
    GameTooltip:Hide()
    Bar.dragFrame:Show()
end

-- Put everything back to rest. `relayout` is false when called from an
-- OnHide that Bar.Layout itself may have caused.
local function endDrag(relayout)
    if not drag then return end
    drag.button:SetAlpha(1)
    Bar.marker:Hide()
    Bar.dragFrame:Hide()
    drag = nil
    lastDragStop = GetTime()
    if relayout then Bar.Layout() end
end

local function onDragStop()
    if not drag then return end
    local t = dropTarget()
    local id, W = drag.block.id, Bar.frame:GetWidth()
    if t.laneX then
        Layout.MoveLane(id, t.laneX, W)
    elseif t.x then
        Layout.Move(id, { x = t.x }, W)
    elseif not t.none then
        Layout.Move(id, { lane = t.lane, index = t.index }, W)
    end
    endDrag(true)
end

-- A hidden frame may never get OnDragStop: end the drag when the dragged
-- block (its text went empty) or the whole bar is hidden mid-drag, so the
-- marker and the click guard can't get stuck.
local function onHide(button)
    if drag and drag.button == button then endDrag(false) end
end

-- The release that ends a drag is not a click.
local function afterDrag() return drag ~= nil or GetTime() - lastDragStop < 0.2 end

local function onClick(button, mouseButton)
    if afterDrag() then return end
    local block = button.block
    if block.onClick then Engine.Call(block, "onClick", block.onClick, block, mouseButton) end
end

-- Wired only for a block with onDoubleClick: every other block keeps getting
-- the second click as an onClick.
local function onDoubleClick(button, mouseButton)
    if afterDrag() then return end
    local block = button.block
    Engine.Call(block, "onDoubleClick", block.onDoubleClick, block, mouseButton)
end

-- The widget for one block: a plain Button with an optional icon and a label.
function Bar.Attach(block)
    if block.widget then return end
    local b = CreateFrame("Button", nil, Bar.content)
    b.block = block
    b:SetHeight(Bar.HEIGHT - 2 * Glass.Inset("small"))
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    b:SetScript("OnClick", onClick)
    if block.onDoubleClick then b:SetScript("OnDoubleClick", onDoubleClick) end
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", onDragStart)
    b:SetScript("OnDragStop", onDragStop)
    b:SetScript("OnHide", onHide)

    -- The HIGHLIGHT layer is drawn only while the mouse is over the button.
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.08)

    local x = PAD
    if block.icon then
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON, ICON)
        icon:SetPoint("LEFT", b, "LEFT", PAD, 0)
        icon:SetTexture(block.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim the stock icon border
        b.icon = icon
        x = PAD + ICON + PAD
    end
    b.textX = x
    -- The label sits on its own layer ABOVE anything a graphical block builds
    -- (the XP bar goes up to +6), so an error mark is never covered by it.
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints(b)
    top:SetFrameLevel(b:GetFrameLevel() + 10)
    -- The caption ("Durability: ", gold, Titan-style) and the value after it.
    local caption = Glass.Font(top, Bar.FONT_SIZE, "LEFT")
    caption:SetPoint("LEFT", b, "LEFT", x, 0)
    caption:SetTextColor(1, 0.82, 0)
    b.caption = caption
    local fs = Glass.Font(top, Bar.FONT_SIZE, "LEFT")
    fs:SetPoint("LEFT", caption, "RIGHT", 0, 0)
    b.label = fs

    block.widget = b
    Bar.UpdateIcon(block)
    Bar.UpdateCaption(block)
    b:Hide()   -- off screen until its first layout decides
    if block.build then Engine.Call(block, "build", block.build, block) end
    Engine.MarkDirty(block)
end

-- A graphical block's width this repaint: its number, or what its width
-- function says (nil: sized to its content, like a text block). A bad answer
-- is recorded and the block is sized to its content.
local function fixedWidth(block)
    local w = block.width
    if type(w) ~= "function" then return w end
    local ok, res = Engine.Call(block, "width", w, block)
    if not ok then return nil end
    if API.IsSecret(res) then
        API.Fail(block.id .. ":width", "returned a secret value")
        return nil
    end
    if res == nil then return nil end
    if type(res) ~= "number" or res ~= res or res == math.huge or res < 16 then
        API.Fail(block.id .. ":width", "returned " .. tostring(res) .. ", not a number of pixels (at least 16) or nil")
        return nil
    end
    return res
end

-- True if anything that moves the layout changed (the caller relayouts only
-- then): the text, the caption, the width or what the value displays.
function Bar.SetText(block, text)
    local b = block.widget
    if not b then return false end
    -- A dynamic caption is re-read on every repaint (it can change without
    -- the value changing), and so is a width function (#78: XP+ zooms with
    -- its text "" throughout).
    local captionChanged = block.caption ~= nil and Bar.UpdateCaption(block)
    local width = fixedWidth(block)
    local widthChanged = b.fixedWidth ~= width
    b.fixedWidth = width
    -- The first paint always counts as a change: a new widget's text is nil
    -- too, and a first nil must still reach Bar.Layout to hide it (and to
    -- tell its onShown), e.g. a plugin registering after startup.
    local textChanged = not b.painted or b.text ~= text
    b.painted = true
    b.text = text
    local displayChanged = syncDisplay(block)
    return textChanged or captionChanged or widthChanged or displayChanged
end

local function shows(block)
    local b = block.widget
    -- nil never shows; "" shows only for a fixed-width (graphical) block.
    return not Bar.IsHidden(block) and b.text ~= nil and (b.text ~= "" or block.width ~= nil)
end

local function widthOf(id)
    local block = Engine.byId[id]
    if not (block and block.widget and shows(block)) then return nil end
    local b = block.widget
    return b.fixedWidth
        or (b.textX + math.ceil(b.caption:GetStringWidth()) + math.ceil(b.label:GetStringWidth()) + PAD)
end

-- Place every block. Hidden blocks and empty ones take no space.
-- A block's onShown hears when it appears on or leaves the screen, the whole
-- bar being toggled included.
function Bar.Layout()
    if not Bar.frame then return end
    local barShown = Bar.frame:IsShown()
    for _, block in ipairs(Engine.blocks) do
        local b = block.widget
        if b then
            local show = shows(block)
            b:SetShown(show)
            local visible = show and barShown
            if b.visible ~= visible then
                if block.onShown then Engine.Call(block, "onShown", block.onShown, block, visible) end
                -- Paint was skipped while off screen: catch up now.
                if visible and block.paint then Engine.MarkDirty(block) end
            end
            b.visible = visible
        end
    end
    Bar.geometry = Layout.Place(Layout.Current(), Bar.frame:GetWidth(), widthOf)
    if drag then drag.cachedX = nil end   -- the slots under the cursor may have moved
    for _, lane in ipairs(Bar.geometry) do
        for _, it in ipairs(lane.items) do
            local b = Engine.byId[it.id].widget
            b.left = it.left
            b:SetWidth(it.width)
            b:ClearAllPoints()
            b:SetPoint("LEFT", Bar.content, "LEFT", it.left, 0)
        end
    end
end

-- The bar's glass (#65): AltStable's two presets (..\AltStable\Skin.lua),
-- the body only (tint, grain, wash); the rim stays the instance's. Clear is
-- the surface as the library built it (SetSurfaceTint(g), the instance's
-- grain, the wash at its built strength), so it follows the library's look.
-- Smoked is AltStable's darker body; its grain and wash are scales of the
-- built ones (AltStable's 0.35 / 0.45 and 0.14 / 0.18). The grain is a plain
-- texture, set as region alpha. The wash is a gradient, which ignores
-- SetAlpha on this client (#83, porting guide section 3): it goes through
-- LibGlass r7's SetWash, which paints the gradient's peak.
-- The class colour is shaded by the preset's classShade at the surface's
-- alpha: at full strength it reads as painted plastic (AltStable, in game).
Bar.GLASS = {
    clear  = { classShade = 0.6 },
    smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, grain = 0.35 / 0.45, wash = 0.14 / 0.18, classShade = 0.3 },
}
Bar.GLASS_TINTS = { neutral = true, class = true }

-- The player's class colour (plain numbers), or nil.
local function classColor()
    local ok, _, class = pcall(UnitClass, "player")
    class = ok and API.Plain(class) or nil
    if type(class) ~= "string" then return nil end
    local ok2, c = pcall(C_ClassColor.GetClassColor, class)
    if not ok2 or type(c) ~= "table" then return nil end
    local r, g, b = API.Plain(c.r), API.Plain(c.g), API.Plain(c.b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return r, g, b
end

-- false while the class colour is wanted but unreadable.
-- `glass`: the instance that built g (its own style: a clean surface has no
-- grain to bring back), GlassPanel.Glass when nil.
local function paintGlass(g, material, tint, glass)
    glass = glass or Glass
    local p = Bar.GLASS[material] or Bar.GLASS.clear
    local known, cr, cg, cb = true, nil, nil, nil
    if tint == "class" then
        cr, cg, cb = classColor()
        known = cr ~= nil
    end
    if cr then
        -- nil alpha: the surface's own (clear); smoked brings its own.
        glass.SetSurfaceTint(g, cr * p.classShade, cg * p.classShade, cb * p.classShade, p.tint and p.tint[4])
    elseif p.tint then
        glass.SetSurfaceTint(g, p.tint[1], p.tint[2], p.tint[3], p.tint[4])
    else
        glass.SetSurfaceTint(g)   -- the colour it was built with
    end
    g.grain:SetAlpha(glass.STYLE.grain * (p.grain or 1))
    glass.SetWash(g, (glass.STYLE.wash or 0) * (p.wash or 1))
    return known
end

-- Paint the bar's body: material "clear"|"smoked", tint "neutral"|"class".
-- Unknown values fall back to clear and neutral. Live, on the one surface (no
-- reload). Returns false while the class colour is wanted but unreadable
-- (Bar.glassPending: PLAYER_ENTERING_WORLD tries again). A throw is recorded,
-- never raised: painting is optional, and it runs while the bar is built.
Bar.glassPending = false
Bar.surfaces = {}   -- { g, glass }: plugins' surfaces painted like the bar (API.MatchPanelGlass)

local function paintOne(g, material, tint, glass)
    -- Following Glass UI (#96) suspends the body: the saved choice is kept, the built look shows.
    if GlassPanel.Suite.Following() then material, tint = "clear", "neutral" end
    local ok, known = pcall(paintGlass, g, material, tint, glass)
    if not ok then
        API.Fail("bar:glass", known)
        return true
    end
    return known
end

function Bar.ApplyGlass(material, tint)
    local g = Bar.glass
    if not g then return true end
    local known = paintOne(g, material, tint)
    for _, s in ipairs(Bar.surfaces) do paintOne(s.g, material, tint, s.glass) end
    Bar.glassPending = not known
    return known
end

-- Public (#78): a plugin's own LibGlass surface painted like the bar, now and
-- whenever the player changes the bar's glass or tint (XP+'s zoomed bar
-- backing). `glass` is the instance that built it (GlassPanel.CleanGlass()'s,
-- or GlassPanel.Glass when nil). A surface handed over twice is kept once.
function API.MatchPanelGlass(g, glass)
    if type(g) ~= "table" then return end
    for _, s in ipairs(Bar.surfaces) do if s.g == g then return end end
    Bar.surfaces[#Bar.surfaces + 1] = { g = g, glass = glass }
    local d = GlassPanelDB or {}
    paintOne(g, d.glass, d.glassTint, glass)
end

function Bar.Build()
    if Bar.frame then return end
    local f = CreateFrame("Frame", "GlassPanelBar", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetHeight(Bar.HEIGHT)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    f:EnableMouse(false)   -- empty bar space clicks through to the world
    Bar.glass = Glass.Apply(f, "small")

    -- Blocks sit between the body and the rim, like GlassUF's bars.
    local content = CreateFrame("Frame", nil, f)
    content:SetAllPoints(f)
    content:SetFrameLevel(Glass.ContentLevel(f))
    Bar.content = content
    Bar.frame = f
    -- Lanes are placed by fractions of the width: redo them when it changes.
    f:SetScript("OnSizeChanged", function() Bar.Layout() end)
    f:SetScript("OnHide", function() endDrag(false) end)

    -- The drop marker, and a frame that moves it while a drag is on.
    local marker = content:CreateTexture(nil, "OVERLAY")
    marker:SetSize(2, Bar.HEIGHT - 6)
    marker:SetColorTexture(0.5, 0.83, 1, 0.9)
    marker:Hide()
    Bar.marker = marker
    local dragFrame = CreateFrame("Frame", nil, f)
    dragFrame:Hide()
    dragFrame:SetScript("OnUpdate", function() if drag then updateMarker() end end)
    Bar.dragFrame = dragFrame

    for _, block in ipairs(Engine.blocks) do Bar.Attach(block) end
    local d = GlassPanelDB or {}
    Bar.ApplyGlass(d.glass, d.glassTint)   -- last: the bar is whole whatever it does
end

-- Pull the bar's ends in (UIParent units) to make room for Blizzard's top
-- frames (Room.lua, #2). Our own frame, not protected: fine in combat.
-- OnSizeChanged relays out the lanes for the new width.
function Bar.SetInsets(left, right)
    local f = Bar.frame
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, 0)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -right, 0)
end

function Bar.SetShown(shown)
    if not Bar.frame then return end
    Bar.frame:SetShown(shown)
    Bar.Layout()
end
