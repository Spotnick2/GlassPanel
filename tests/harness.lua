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

-- Every folder under Plugins\, in name order: { name, folder, dir, toc }.
-- The TOC's base name is the addon name, as deploy and the packager make it;
-- a folder with no TOC has toc = nil, and test_toc fails on it. Listed once
-- per test run: loadAddon runs many times and this spawns processes.
local pluginList
function plugins()
    if pluginList then return pluginList end
    local out = {}
    local p = io.popen('dir /b /ad Plugins 2>nul')
    for d in p:lines() do
        local q = io.popen('dir /b "Plugins\\' .. d .. '\\*.toc" 2>nul')
        local toc = q:read("*l")
        q:close()
        out[#out + 1] = { folder = d, dir = "Plugins/" .. d .. "/", toc = toc,
                          name = toc and (toc:gsub("%.toc$", "")) or d }
    end
    p:close()
    table.sort(out, function(a, b) return a.name < b.name end)
    pluginList = out
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
-- opts.before(): runs after the core's files load but before its ADDON_LOADED:
-- a block registered there takes the early path (attached at Bar.Build).
-- Real plugins load after it (below), so don't use this to stand in for one.
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
    -- (The stub computes the bar's width and rect from its anchors.)
    -- Then each plugin, the way the client does it: after the core's
    -- ADDON_LOADED (## Dependencies: GlassPanel), so its blocks register
    -- onto a bar that already exists. opts.plugins = false: the core alone.
    -- opts.plugins: false (core alone), a list of addon names, or nil for the
    -- file-wide PLUGINS list a test may set (layout tests pin theirs so a new
    -- plugin doesn't reshuffle the lanes they assert on), else every plugin.
    local allow = opts.plugins
    if allow == nil then allow = rawget(_G, "PLUGINS") end
    local only
    if type(allow) == "table" then
        only = {}
        for _, n in ipairs(allow) do only[n] = true end
    end
    if allow ~= false then
        for _, p in ipairs(plugins()) do
            if p.toc and (not only or only[p.name]) then
                local pns = {}
                for _, file in ipairs(tocFiles(p.toc, p.dir)) do
                    local chunk = assert(loadfile(file))
                    chunk(p.name, pns)
                end
                WoW.fire("ADDON_LOADED", p.name)
            end
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
