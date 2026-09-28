-- harness.lua: assertions and the addon loader. dofile it after wow_stubs.lua.

local passed, failed = 0, 0

function check(cond, msg)
    if cond then passed = passed + 1 else
        failed = failed + 1
        io.write("  FAIL: " .. tostring(msg) .. "\n")
    end
end

function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

function done(name)
    io.write(string.format("%s: %d passed, %d failed\n", name, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

-- The plugins under Plugins\, in name order: { name, dir, toc }. The TOC's
-- base name is the addon name, as deploy and the packager make it.
function plugins()
    local out = {}
    local p = io.popen('dir /b /ad Plugins 2>nul')
    for d in p:lines() do
        local dir = "Plugins/" .. d .. "/"
        local q = io.popen('dir /b "Plugins\\' .. d .. '\\*.toc" 2>nul')
        local toc = q:read("*l")
        q:close()
        if toc then out[#out + 1] = { name = toc:gsub("%.toc$", ""), dir = dir, toc = toc } end
    end
    p:close()
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Lua files listed in a TOC (default: the core's), in load order, as paths
-- from the repo root.
function tocFiles(toc, dir)
    toc, dir = toc or "GlassPanel.toc", dir or ""
    local files = {}
    for line in io.lines(dir .. toc) do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = dir .. (line:gsub("\\", "/")) end
    end
    return files
end

-- Load the addon the way the client does: every TOC file with (name, ns),
-- then ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD, and one frame.
-- opts.before(): runs after the files load but before ADDON_LOADED, where a
-- plugin that loads early would register.
function loadAddon(opts)
    opts = opts or {}
    -- A fresh session each call; client data (WoW.money, ...) set by the test stays.
    GlassPanel, GlassPanelDB = nil, nil
    WoW.frames, WoW.chat, WoW.timers = {}, {}, {}   -- a dead session's timers die with it
    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(file))
        chunk("GlassPanel", ns)
    end
    if opts.db then GlassPanelDB = opts.db end
    if opts.before then opts.before() end
    WoW.fire("ADDON_LOADED", "GlassPanel")
    -- The client sizes the bar from its anchors; the stub can't.
    -- (The stub computes the bar's width and rect from its anchors.)
    -- Then each plugin, the way the client does it: after the core's
    -- ADDON_LOADED (## Dependencies: GlassPanel), so its blocks register
    -- onto a bar that already exists. opts.plugins = false: the core alone.
    if opts.plugins ~= false then
        for _, p in ipairs(plugins()) do
            local pns = {}
            for _, file in ipairs(tocFiles(p.toc, p.dir)) do
                local chunk = assert(loadfile(file))
                chunk(p.name, pns)
            end
            WoW.fire("ADDON_LOADED", p.name)
        end
    end
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", true, false)
    WoW.tick()
    return GlassPanel
end

function block(id) return GlassPanel.Engine.byId[id] end
function textOf(id) return block(id).widget.label._text end
-- A block's left edge on the bar, as last laid out.
function leftOf(id) return block(id).widget.left end
-- Drag block id and drop it with the cursor at bar x (shift = move its lane).
-- The block is grabbed at its centre (or `grabAt` px from its left edge), so
-- by default "drop at x" puts the block's centre at x.
function dragTo(id, x, shift, grabAt)
    local b = block(id).widget
    WoW.shift = shift == true
    WoW.cursor = { ((b.left or 0) + (grabAt or b._width / 2)) * WoW.uiScale, 0 }
    b._scripts.OnDragStart(b)
    WoW.cursor = { x * WoW.uiScale, 0 }
    WoW.tick()
    b._scripts.OnDragStop(b)
    WoW.shift = false
end
