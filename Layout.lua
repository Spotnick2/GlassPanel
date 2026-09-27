-- Layout.lua: where blocks go (#6). Pure model, no frames: Bar.lua draws it.
--
-- A lane is a group of blocks around an anchor x, a fraction of the bar width:
--   x == 0  packs from the left edge,  x == 1  packs from the right edge,
--   anything else is centred on the anchor (and kept on screen).
-- There are as many lanes as the user makes: dropping a block on empty bar
-- space starts one, and a lane disappears when its last block leaves.
--
-- Saved in GlassPanelDB.layout = { { x = 0..1, ids = { "gold", ... } }, ... },
-- ids in visual left-to-right order. Ids of blocks that aren't loaded (a
-- disabled module) stay put, so re-enabling one restores its place. A block
-- never placed goes to the lane its spec's side names (0 / 0.5 / 1) by order.

GlassPanel = GlassPanel or {}
local Engine = GlassPanel.Engine
local Layout = {}
GlassPanel.Layout = Layout

Layout.EDGE = 8     -- px from the bar's ends to the first block
Layout.GAP = 8      -- px between blocks in a lane
Layout.SNAP = 40    -- px: a drop this close to a slot joins it, else starts a lane

local SIDE_X = { left = 0, center = 0.5, right = 1 }
Layout.SIDE_X = SIDE_X   -- the named lanes, for /gpanel move

local function saved()
    local d = GlassPanelDB
    if type(d) ~= "table" or type(d.layout) ~= "table" then return {} end
    local out = {}
    for _, lane in ipairs(d.layout) do
        if type(lane) == "table" and type(lane.x) == "number" and lane.x >= 0 and lane.x <= 1
            and type(lane.ids) == "table" then
            local ids = {}
            for _, id in ipairs(lane.ids) do
                if type(id) == "string" then ids[#ids + 1] = id end
            end
            out[#out + 1] = { x = lane.x, ids = ids }
        end
    end
    return out
end

local function byX(a, b) return a.x < b.x end

local function laneAt(lanes, x)
    for _, lane in ipairs(lanes) do
        if lane.x == x then return lane end
    end
    local lane = { x = x, ids = {} }
    lanes[#lanes + 1] = lane
    return lane
end

local function prune(lanes)
    for i = #lanes, 1, -1 do
        if #lanes[i].ids == 0 then table.remove(lanes, i) end
    end
    table.sort(lanes, byX)
    return lanes
end

-- The effective lanes: the saved layout plus every registered block it
-- doesn't mention, sorted by x, no empty lanes. A fresh copy each call.
function Layout.Lanes()
    local lanes = saved()
    local placed = {}
    for _, lane in ipairs(lanes) do
        for _, id in ipairs(lane.ids) do placed[id] = true end
    end
    local unplaced = {}
    for _, block in ipairs(Engine.blocks) do
        if not placed[block.id] then unplaced[#unplaced + 1] = block end
    end
    table.sort(unplaced, function(a, c)
        if a.order ~= c.order then return a.order < c.order end
        return a._seq < c._seq
    end)
    for _, block in ipairs(unplaced) do
        local x = SIDE_X[block.side] or 0
        local lane = laneAt(lanes, x)
        if x == 1 then
            table.insert(lane.ids, 1, block.id)   -- lower order sits nearer the right edge
        else
            lane.ids[#lane.ids + 1] = block.id
        end
    end
    return prune(lanes)
end

function Layout.Save(lanes)
    GlassPanelDB.layout = prune(lanes)
end

function Layout.Reset()
    GlassPanelDB.layout = nil
end

local function removeId(lanes, id)
    for _, lane in ipairs(lanes) do
        for i, v in ipairs(lane.ids) do
            if v == id then table.remove(lane.ids, i) return lane end
        end
    end
end

-- A cursor at bar x -> an anchor, snapping to the ends within EDGE + SNAP px:
-- the same rule for dropping a block and for moving a lane.
function Layout.SnapPx(cx, W)
    if cx <= Layout.EDGE + Layout.SNAP then return 0 end
    if cx >= W - Layout.EDGE - Layout.SNAP then return 1 end
    return W > 0 and cx / W or 0
end

-- The lane nearest to x within tol: typed percentages are rounded (a dragged
-- lane sits at 0.4371 while /gpanel list shows 44%).
local function laneNear(lanes, x, tol)
    local best, bestD
    for _, lane in ipairs(lanes) do
        local d = math.abs(lane.x - x)
        if d <= tol and (not bestD or d < bestD) then best, bestD = lane, d end
    end
    return best
end

-- Snap an anchor near the ends to the ends; keep it in 0..1.
function Layout.SnapX(x)
    if x <= 0.02 then return 0 end
    if x >= 0.98 then return 1 end
    return x
end

-- Move a block. target = { lane = x, index = n } to join the lane anchored
-- at x before its n-th id (nil or past the end = last), or { x = f } to start
-- a new lane (joining an existing lane at exactly that anchor instead).
function Layout.Move(id, target)
    local lanes = Layout.Lanes()
    removeId(lanes, id)
    if target.x ~= nil then
        local x = Layout.SnapX(target.x)
        local lane = laneAt(lanes, x)
        if x == 0 then table.insert(lane.ids, 1, id) else lane.ids[#lane.ids + 1] = id end
    else
        local lane = laneNear(lanes, target.lane, 0.006) or laneAt(lanes, target.lane)
        local n = target.index
        if n == nil or n > #lane.ids + 1 then n = #lane.ids + 1 end
        if n < 1 then n = 1 end
        table.insert(lane.ids, n, id)
    end
    Layout.Save(lanes)
end

-- Move the whole lane holding `id` to anchor x. Landing on another lane's
-- anchor merges the two (the moved lane's blocks go after).
function Layout.MoveLane(id, x)
    x = Layout.SnapX(x)
    local lanes = Layout.Lanes()
    local from
    for _, lane in ipairs(lanes) do
        for _, v in ipairs(lane.ids) do if v == id then from = lane end end
    end
    if not from or from.x == x then return end
    for _, lane in ipairs(lanes) do
        if lane ~= from and lane.x == x then
            for _, v in ipairs(from.ids) do lane.ids[#lane.ids + 1] = v end
            from.ids = {}
            Layout.Save(lanes)
            return
        end
    end
    from.x = x
    Layout.Save(lanes)
end

-- Geometry for bar width W. widthOf(id) -> px, or nil when the block isn't
-- shown (hidden, empty, not loaded). Returns { { x, ids, items = { { id,
-- left, width } } } } for the lanes with something visible.
function Layout.Place(lanes, W, widthOf)
    local out = {}
    for _, lane in ipairs(lanes) do
        local items, total = {}, 0
        for _, id in ipairs(lane.ids) do
            local w = widthOf(id)
            if w then
                if #items > 0 then total = total + Layout.GAP end
                items[#items + 1] = { id = id, width = w }
                total = total + w
            end
        end
        if #items > 0 then
            local start
            if lane.x == 0 then
                start = Layout.EDGE
            elseif lane.x == 1 then
                start = W - Layout.EDGE - total
            else
                start = lane.x * W - total / 2
                start = math.max(Layout.EDGE, math.min(start, W - Layout.EDGE - total))
            end
            for _, it in ipairs(items) do
                it.left = start
                start = start + it.width + Layout.GAP
            end
            out[#out + 1] = { x = lane.x, ids = lane.ids, items = items }
        end
    end
    return out
end

-- Where a block dragged to bar x = cx lands: { lane = x, index = n } for the
-- nearest gap within SNAP px, else { x = f } for a new lane. The dragged
-- block itself is ignored, and indexes are into its lane without it.
function Layout.DropTarget(geometry, W, cx, draggedId)
    local best, bestDist
    for _, lane in ipairs(geometry) do
        local ids, items = {}, {}
        for _, id in ipairs(lane.ids) do if id ~= draggedId then ids[#ids + 1] = id end end
        for _, it in ipairs(lane.items) do if it.id ~= draggedId then items[#items + 1] = it end end
        if #items > 0 then
            local pos = {}
            for i, id in ipairs(ids) do pos[id] = i end
            for k = 1, #items + 1 do
                local sx, index
                if k == 1 then
                    sx, index = items[1].left - Layout.GAP / 2, pos[items[1].id]
                elseif k == #items + 1 then
                    local last = items[#items]
                    sx, index = last.left + last.width + Layout.GAP / 2, pos[last.id] + 1
                else
                    local a, c = items[k - 1], items[k]
                    sx, index = (a.left + a.width + c.left) / 2, pos[c.id]
                end
                local dist = math.abs(cx - sx)
                if not bestDist or dist < bestDist then
                    best, bestDist = { lane = lane.x, index = index, slotX = sx }, dist
                end
            end
        end
    end
    if best and bestDist <= Layout.SNAP then return best end
    return { x = Layout.SnapPx(cx, W), slotX = cx }
end
