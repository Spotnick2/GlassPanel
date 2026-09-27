-- Bar.lua: the glass strip across the top of the screen, one button per block,
-- and the layout. It knows how to draw a block, never what a block means.
--
-- Blocks sit in two lanes: "left" packs from the left edge, "right" from the
-- right edge. Within a lane, `order` then registration order decides. A
-- block's width follows its text, so a relayout runs after any flush that
-- repainted something.
--
-- Nothing here is secure: the bar parents no secure frame, so it can be
-- shown, hidden and relaid out in combat.

GlassPanel = GlassPanel or {}
local API, Glass, Engine = GlassPanel.API, GlassPanel.Glass, GlassPanel.Engine
local Bar = {}
GlassPanel.Bar = Bar

Bar.HEIGHT = 24         -- UIParent units; the screen is 768 tall at default scale
Bar.FONT_SIZE = 12
local ICON = 14
local PAD = 4           -- inside a block, around icon and text
local GAP = 8           -- between blocks
local EDGE = 8          -- from the bar's ends to the first block

local function db() return GlassPanelDB end

function Bar.IsHidden(block)
    local d = db()
    return d and d.hidden and d.hidden[block.id] == true
end

local function onEnter(button)
    local block = button.block
    if not block.tooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if block.side == "right" then
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

local function onClick(button, mouseButton)
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
    local fs = Glass.Font(b, Bar.FONT_SIZE, "LEFT")
    fs:SetPoint("LEFT", b, "LEFT", x, 0)
    b.label = fs

    block.widget = b
    if block.build then Engine.Call(block, "build", block.build, block) end
    Engine.MarkDirty(block)
end

-- True if the text changed (the caller relayouts only then).
function Bar.SetText(block, text)
    local b = block.widget
    if not b or b.text == text then return false end
    b.text = text
    b.label:SetText(text or "")
    return true
end

local function sorted(side)
    local list = {}
    for _, block in ipairs(Engine.blocks) do
        if block.side == side and block.widget then list[#list + 1] = block end
    end
    table.sort(list, function(a, c)
        if a.order ~= c.order then return a.order < c.order end
        return a._seq < c._seq
    end)
    return list
end

-- Place every block. Hidden blocks and empty ones (text "") take no space.
-- A block's onShown hears when it appears on or leaves the screen, the whole
-- bar being toggled included.
function Bar.Layout()
    if not Bar.frame then return end
    local barShown = Bar.frame:IsShown()
    for _, side in ipairs({ "left", "right" }) do
        local offset = EDGE
        for _, block in ipairs(sorted(side)) do
            local b = block.widget
            -- nil never shows; "" shows only for a fixed-width (graphical) block.
            local show = not Bar.IsHidden(block) and b.text ~= nil and (b.text ~= "" or block.width ~= nil)
            b:SetShown(show)
            local visible = show and barShown
            if block.onShown and b.visible ~= visible then
                Engine.Call(block, "onShown", block.onShown, block, visible)
            end
            b.visible = visible
            if show then
                local w = block.width or (b.textX + math.ceil(b.label:GetStringWidth()) + PAD)
                b:SetWidth(w)
                b:ClearAllPoints()
                if side == "left" then
                    b:SetPoint("LEFT", Bar.content, "LEFT", offset, 0)
                else
                    b:SetPoint("RIGHT", Bar.content, "RIGHT", -offset, 0)
                end
                offset = offset + w + GAP
            end
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

    for _, block in ipairs(Engine.blocks) do Bar.Attach(block) end
end

function Bar.SetShown(shown)
    if not Bar.frame then return end
    Bar.frame:SetShown(shown)
    Bar.Layout()
end
