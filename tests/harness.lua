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
    for _, d in ipairs(WoW.list("Plugins")) do
        local toc = WoW.list("Plugins/" .. d, ".toc")[1]
        out[#out + 1] = { folder = d, dir = "Plugins/" .. d .. "/", toc = toc,
                          name = toc and (toc:gsub("%.toc$", "")) or d }
    end
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

-- Every file line of the core's TOC, in load order (our .lua files and the
-- embedded library's .xml).
function tocLines()
    local lines = {}
    for line in io.lines("GlassPanel.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then lines[#lines + 1] = line end
    end
    return lines
end

-- The embedded LibGlass-1.0 comes from a checkout, not from Libs\ (gitignored,
-- filled by the packager): $LIBGLASS, else ../LibGlass. No checkout fails the
-- run loudly; a silently skipped library would test nothing.
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
function libGlassRoot()
    local root = (os.getenv("LIBGLASS") or "../LibGlass"):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/LibGlass-1.0.xml", "rb")
    if not f then
        error("LibGlass checkout not found at " .. root .. " (no LibGlass-1.0.xml): clone "
              .. "github.com/Spotnick2/LibGlass there or set LIBGLASS", 0)
    end
    f:close()
    return root
end

-- The Lua files the library's XML loads, as paths, in order: what the client
-- runs for the TOC's XML line. A listed file that is missing fails here.
-- Read once per test run: loadAddon runs many times.
local libScripts
function libGlassScripts()
    if libScripts then return libScripts end
    local root = libGlassRoot()
    local f = assert(io.open(root .. "/LibGlass-1.0.xml", "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error("LibGlass checkout at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error("LibGlass-1.0.xml at " .. root .. " lists no Script files", 0) end
    libScripts = files
    return files
end

-- Like the client: a plugin loads only when every addon its ## Dependencies
-- names is installed (the core, and WoW.installed for the others).
function dependenciesMet(p)
    local f = assert(io.open(p.dir .. p.toc, "rb"))
    local deps = f:read("*a"):match("## Dependencies:([^\r\n]*)") or ""
    f:close()
    for d in deps:gmatch("[^,%s]+") do
        if d ~= "GlassPanel" and not WoW.installed[d] then return false end
    end
    return true
end

-- Load the addon the way the client does: every TOC file with (name, ns),
-- the library's XML expanded in place, then ADDON_LOADED, PLAYER_LOGIN,
-- PLAYER_ENTERING_WORLD, and one frame.
-- opts.before(): runs after the core's files load but before its ADDON_LOADED:
-- a block registered there takes the early path (attached at Bar.Build).
-- Real plugins load after it (below), so don't use this to stand in for one.
function loadAddon(opts)
    opts = opts or {}
    -- A fresh session each call; client data (WoW.money, ...) set by the test stays.
    -- LibStub too: a kept one would skip the library's load and hand out the
    -- dead session's copy.
    GlassPanel, GlassPanelDB, LibStub = nil, nil, nil
    WoW.frames, WoW.chat, WoW.timers = {}, {}, {}   -- a dead session's timers die with it
    local ns = {}
    for _, line in ipairs(tocLines()) do
        local files = { line }
        if line == LIBGLASS_XML then
            files = libGlassScripts()
        elseif not line:match("%.lua$") then
            error("the harness can't load TOC line " .. line, 0)
        end
        for _, file in ipairs(files) do
            local chunk = assert(loadfile(file))
            chunk("GlassPanel", ns)
        end
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
        local exists = {}
        for _, p in ipairs(plugins()) do exists[p.name] = true end
        for _, n in ipairs(allow) do
            -- A misspelled or renamed plugin would silently not load.
            if not exists[n] then error("pinned plugin '" .. n .. "' doesn't exist under Plugins/", 2) end
            only[n] = true
        end
    end
    if allow ~= false then
        for _, p in ipairs(plugins()) do
            if p.toc and (not only or only[p.name]) and dependenciesMet(p) then
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

-- The ForeverProbe host (the probes' own; never shipped), from its checkout:
-- $FOREVERPROBE, else ../ForeverProbe (GlassChat's loader). nil when there's
-- no checkout: it's a private repo, so CI has none, and the probe test skips.
function foreverProbeRoot()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/ForeverProbe.toc", "rb")
    if not f then return nil end
    f:close()
    return root
end

function loadForeverProbe()
    local root = foreverProbeRoot()
    if not root then error("ForeverProbe checkout not found: clone it to ../ForeverProbe or set FOREVERPROBE", 0) end
    local toc = assert(io.open(root .. "/ForeverProbe.toc", "rb"))
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
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
