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

-- Lua files listed in the TOC, in load order.
function tocFiles()
    local files = {}
    for line in io.lines("GlassPanel.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/")) end
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
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", true, false)
    WoW.tick()
    return GlassPanel
end

function block(id) return GlassPanel.Engine.byId[id] end
function textOf(id) return block(id).widget.label._text end
