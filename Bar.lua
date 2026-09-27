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

function Bar.IsHidden(block)
    local d = db()
    return d and d.hidden and d.hidden[block.id] == true
end

local function onEnter(button)
    local block = button.block
    if not block.tooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if (button.left or 0) > Bar.frame:GetWidth() / 2 then
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

local drag            -- { button, block, lane = shift-drag } while dragging
local lastDragStop = -1

-- The cursor's x in bar coordinates.
local function cursorX()
    local x = GetCursorPosition()
    return x / Bar.frame:GetEffectiveScale() - (Bar.frame:GetLeft() or 0)
end

local function dropTarget()
    return Layout.DropTarget(Bar.geometry or {}, Bar.frame:GetWidth(), cursorX(), drag.block.id)
end

local function updateMarker()
    local t = dropTarget()
    Bar.marker:ClearAllPoints()
    Bar.marker:SetPoint("CENTER", Bar.content, "LEFT", drag.lane and cursorX() or t.slotX, 0)
end

local function onDragStart(button)
    drag = { button = button, block = button.block, lane = IsShiftKeyDown() }
    button:SetAlpha(0.4)
    GameTooltip:Hide()
    Bar.marker:Show()
    Bar.dragFrame:Show()
end

local function onDragStop(button)
    if not drag then return end
    local W = Bar.frame:GetWidth()
    if drag.lane then
        Layout.MoveLane(drag.block.id, W > 0 and cursorX() / W or 0)
    else
        local t = dropTarget()
        if t.x ~= nil then
            Layout.Move(drag.block.id, { x = t.x })
        else
            Layout.Move(drag.block.id, { lane = t.lane, index = t.index })
        end
    end
    button:SetAlpha(1)
    Bar.marker:Hide()
    Bar.dragFrame:Hide()
    drag = nil
    lastDragStop = GetTime()
    Bar.Layout()
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
    local fs = Glass.Font(top, Bar.FONT_SIZE, "LEFT")
    fs:SetPoint("LEFT", b, "LEFT", x, 0)
    b.label = fs

    block.widget = b
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
    return block.width or (b.textX + math.ceil(b.label:GetStringWidth()) + PAD)
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
    Bar.geometry = Layout.Place(Layout.Lanes(), Bar.frame:GetWidth(), widthOf)
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

function Bar.SetShown(shown)
    if not Bar.frame then return end
    Bar.frame:SetShown(shown)
    Bar.Layout()
end
