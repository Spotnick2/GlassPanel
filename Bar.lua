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

function Bar.UpdateCaption(block)
    local b = block.widget
    if not b then return end
    b.caption:SetText(Bar.ShowsCaption(block) and (block.label .. ": ") or "")
end

-- After a caption setting changes: every block, then the layout.
function Bar.RefreshCaptions()
    for _, block in ipairs(Engine.blocks) do Bar.UpdateCaption(block) end
    Bar.Layout()
end

function Bar.IsHidden(block)
    local d = db()
    return d and d.hidden and d.hidden[block.id] == true
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

local function onClick(button, mouseButton)
    -- The release that ends a drag is not a click.
    if drag or GetTime() - lastDragStop < 0.2 then return end
    local block = button.block
    if block.onClick then Engine.Call(block, "onClick", block.onClick, block, mouseButton) end
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
    Bar.UpdateCaption(block)
    b:Hide()   -- off screen until its first layout decides
    if block.build then Engine.Call(block, "build", block.build, block) end
    Engine.MarkDirty(block)
end

-- True if the text changed (the caller relayouts only then).
function Bar.SetText(block, text)
    local b = block.widget
    if not b then return false end
    -- The first paint always counts as a change: a new widget's text is nil
    -- too, and a first nil must still reach Bar.Layout to hide it (and to
    -- tell its onShown), e.g. a plugin registering after startup.
    if b.painted and b.text == text then return false end
    b.painted = true
    b.text = text
    b.label:SetText(text or "")
    return true
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
    return block.width
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
