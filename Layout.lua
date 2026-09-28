-- Layout.lua: where blocks go (#6). Pure model, no frames: Bar.lua draws it.
--
-- A lane is a group of blocks around an anchor x, a fraction of the bar width:
--   x == 0  packs from the left edge,  x == 1  packs from the right edge,
--   anything else is centred on the anchor (and kept on screen).
-- There are as many lanes as the user makes: dropping a block on empty bar
-- space starts one, and a lane disappears when its last block leaves. Lanes
-- never draw over each other: Place pushes overlapping lanes apart.
--
-- Saved in GlassPanelDB.layout = { { x = 0..1, ids = { "gold", ... } }, ... },
-- ids in visual left-to-right order. Ids of blocks that aren't loaded (a
-- disabled plugin) stay put, so re-enabling one restores its place. A block
-- never placed goes to the lane its spec's side names (0 / 0.5 / 1) by order.

GlassPanel = GlassPanel or {}
local Engine = GlassPanel.Engine
local Layout = {}
GlassPanel.Layout = Layout

Layout.EDGE = 8        -- px from the bar's ends to the first block
Layout.GAP = 8         -- px between blocks in a lane
Layout.LANE_GAP = 16   -- px kept between two lanes
Layout.SNAP = 40       -- px: a drop this close to a gap joins it, or to an end snaps to it

local SIDE_X = { left = 0, center = 0.5, right = 1 }
Layout.SIDE_X = SIDE_X   -- the named lanes, for /gpanel move

-- Lanes validated: bad entries dropped, and an id kept only in the first
-- place it appears (a hand-edited file, or an imported setup, could list it
-- twice). Always a fresh table.
function Layout.Clean(layout)
    if type(layout) ~= "table" then return {} end
    local out, seen = {}, {}
    for _, lane in ipairs(layout) do
        if type(lane) == "table" and type(lane.x) == "number" and lane.x >= 0 and lane.x <= 1
            and type(lane.ids) == "table" then
            local ids = {}
            for _, id in ipairs(lane.ids) do
                if type(id) == "string" and not seen[id] then
                    seen[id] = true
                    ids[#ids + 1] = id
                end
            end
            out[#out + 1] = { x = lane.x, ids = ids }
        end
    end
    return out
end

-- The saved lanes, validated.
local function saved()
    local d = GlassPanelDB
    return Layout.Clean(type(d) == "table" and d.layout or nil)
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
-- doesn't mention, sorted by x, no empty lanes. A fresh copy each call, for
-- callers that change it (then Save).
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

-- The same, cached for reading (Bar.Layout runs on every text change). It is
-- rebuilt when the saved table or the set of blocks changes: Save and Reset
-- replace the table, and registration adds a block.
local cache, cacheLayout, cacheBlocks
function Layout.Current()
    local layout = GlassPanelDB and GlassPanelDB.layout
    if cache and cacheLayout == layout and cacheBlocks == #Engine.blocks then return cache end
    cache, cacheLayout, cacheBlocks = Layout.Lanes(), layout, #Engine.blocks
    return cache
end

function Layout.Save(lanes)
    GlassPanelDB.layout = prune(lanes)
end

function Layout.Reset()
    GlassPanelDB.layout = nil
    cache = nil
end

local function removeId(lanes, id)
    for _, lane in ipairs(lanes) do
        for i, v in ipairs(lane.ids) do
            if v == id then table.remove(lane.ids, i) return lane end
        end
    end
end

-- THE edge rule, in px: a span that comes within SNAP of an end of the bar
-- snaps to that end (0 or 1); otherwise its centre, as a fraction.
function Layout.Anchor(left, right, W)
    if W <= 0 then return 0 end
    if left <= Layout.EDGE + Layout.SNAP then return 0 end
    if right >= W - Layout.EDGE - Layout.SNAP then return 1 end
    return (left + right) / 2 / W
end

-- The lane nearest to x within SNAP px, or nil.
local function laneNear(lanes, x, W, except)
    local best, bestD
    for _, lane in ipairs(lanes) do
        local d = math.abs(lane.x - x) * W
        if lane ~= except and d <= Layout.SNAP and (not bestD or d < bestD) then best, bestD = lane, d end
    end
    return best
end

-- Move a block. target = { lane = x, index = n } joins the lane anchored at
-- (or within SNAP px of) x, before its n-th id (nil or past the end = last);
-- { x = f } starts a lane there, or joins one already there (at the end
-- nearer f). W is the bar width, for the SNAP distance.
function Layout.Move(id, target, W)
    W = W or 1000
    local lanes = Layout.Lanes()
    removeId(lanes, id)
    if target.x ~= nil then
        local lane = laneNear(lanes, target.x, W)
        if lane then
            if target.x == 0 or (target.x ~= 1 and target.x < lane.x) then
                table.insert(lane.ids, 1, id)
            else
                lane.ids[#lane.ids + 1] = id
            end
        else
            laneAt(lanes, target.x).ids[1] = id
        end
    else
        local lane = laneNear(lanes, target.lane, W) or laneAt(lanes, target.lane)
        local n = target.index
        if n == nil or n > #lane.ids + 1 then n = #lane.ids + 1 end
        if n < 1 then n = 1 end
        table.insert(lane.ids, n, id)
    end
    Layout.Save(lanes)
end

-- Move the whole lane holding `id` to anchor x. Landing within SNAP px of
-- another lane's anchor merges the two (the moved lane's blocks go on the
-- side it came from).
function Layout.MoveLane(id, x, W)
    W = W or 1000
    local lanes = Layout.Lanes()
    local from
    for _, lane in ipairs(lanes) do
        for _, v in ipairs(lane.ids) do if v == id then from = lane end end
    end
    if not from or from.x == x then return end
    local into = laneNear(lanes, x, W, from)
    if into then
        if from.x < into.x then
            for i = #from.ids, 1, -1 do table.insert(into.ids, 1, from.ids[i]) end
        else
            for _, v in ipairs(from.ids) do into.ids[#into.ids + 1] = v end
        end
        from.ids = {}
    else
        from.x = x
    end
    Layout.Save(lanes)
end

-- Geometry for bar width W. widthOf(id) -> px, or nil when the block isn't
-- shown (hidden, empty, not loaded). Returns { { x, ids, items = { { id,
-- left, width } }, left, right } } for the lanes with something visible.
-- Lanes are then kept LANE_GAP apart: a left-to-right pass pushes a lane
-- that overlaps the previous one to the right, and a right-to-left pass pulls
-- back any pushed past the right end. Only when everything can't fit do lanes
-- still overlap.
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
            end
            start = math.max(Layout.EDGE, math.min(start, W - Layout.EDGE - total))
            out[#out + 1] = { x = lane.x, ids = lane.ids, items = items, left = start, width = total }
        end
    end
    table.sort(out, function(a, b) return a.left < b.left end)
    for i = 2, #out do
        local min = out[i - 1].left + out[i - 1].width + Layout.LANE_GAP
        if out[i].left < min then out[i].left = min end
    end
    for i = #out, 1, -1 do
        local max = (i == #out) and (W - Layout.EDGE) or (out[i + 1].left - Layout.LANE_GAP)
        if out[i].left + out[i].width > max then out[i].left = math.max(Layout.EDGE, max - out[i].width) end
    end
    for _, lane in ipairs(out) do
        local x = lane.left
        for _, it in ipairs(lane.items) do
            it.left = x
            x = x + it.width + Layout.GAP
        end
        lane.right = lane.left + lane.width
    end
    return out
end

-- Where a block dragged so that its left edge is at `left` (cursor minus the
-- grab offset; `width` its own) lands, with the cursor at bar x = cx:
--   over another block        -> that block's lane, before or after it;
--   within SNAP px of a gap   -> that gap;
--   anywhere else             -> a new lane where the block was released.
-- Returns { lane = x, index = n, slotX } or { x = f, slotX }. The dragged
-- block is ignored, and indexes are into its lane without it.
function Layout.DropTarget(geometry, W, cx, draggedId, left, width)
    left, width = left or cx, width or 0
    local best, bestDist
    for _, lane in ipairs(geometry) do
        local ids, items = {}, {}
        for _, id in ipairs(lane.ids) do if id ~= draggedId then ids[#ids + 1] = id end end
        for _, it in ipairs(lane.items) do if it.id ~= draggedId then items[#items + 1] = it end end
        if #items > 0 then
            local pos = {}
            for i, id in ipairs(ids) do pos[id] = i end
            for _, it in ipairs(items) do
                if cx >= it.left and cx <= it.left + it.width then
                    if cx < it.left + it.width / 2 then
                        return { lane = lane.x, index = pos[it.id], slotX = it.left - Layout.GAP / 2 }
                    end
                    return { lane = lane.x, index = pos[it.id] + 1, slotX = it.left + it.width + Layout.GAP / 2 }
                end
            end
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
    local x = Layout.Anchor(left, left + width, W)
    return { x = x, slotX = left + width / 2 }
end

-- Where the lane holding `id` goes when shift-dragged by dx px: its span
-- moved by dx, snapped at the ends like a block. Returns { laneX, slotX }.
function Layout.LaneTarget(geometry, W, id, dx)
    for _, lane in ipairs(geometry) do
        for _, it in ipairs(lane.items) do
            if it.id == id then
                local l, r = lane.left + dx, lane.right + dx
                return { laneX = Layout.Anchor(l, r, W), slotX = (l + r) / 2 }
            end
        end
    end
    return { none = true }
end
