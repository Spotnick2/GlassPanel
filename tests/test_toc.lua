-- The manifest, the pinned build, and the media the material names.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open("GlassPanel.toc"):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassPanelDB", 1, true), "saved variables declared")
for _, f in ipairs(tocFiles()) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
eq(tocFiles()[1], "Compat.lua", "Compat loads first")
for _, f in ipairs(tocFiles()) do
    local src = io.open(f):read("*a")
    check(src:find("\nGlassPanel = GlassPanel or {}\n", 1, true), "starts with the namespace line: " .. f)
end
eq(tocFiles()[#tocFiles()], "GlassPanel.lua", "bootstrap loads last")
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

-- [Core] and its grouped plugins (#7), AtlasLoot-style in the AddOns list,
-- AltStable-style on disk: Plugins\<Name>\GlassPanel<Name>.toc.
check(toc:find("## Title: |cff7fd4ffGlass|r Panel |cFF22B14C[Core]|r", 1, true), "core title says [Core]")
check(toc:find("## Group: GlassPanel", 1, true), "core in the GlassPanel group")
local icon = toc:match("## IconTexture: ([^\r\n]+)")
check(icon, "core has an icon")
-- .pkgmeta's move-folders block, parsed: only uncommented "  src: dst" lines
-- between "move-folders:" and the next top-level key count.
local moves = {}
do
    local inBlock = false
    for line in io.lines(".pkgmeta") do
        line = line:gsub("\r", "")
        if line:match("^move%-folders:%s*$") then
            inBlock = true
        elseif line:match("^[^%s#]") then
            inBlock = false
        elseif inBlock then
            local src, dst = line:match("^  ([^#%s][^:]*):%s*(%S+)%s*$")
            if src then moves[src] = dst end
        end
    end
end
local list = plugins()
check(#list >= 3, "plugins found (" .. #list .. ")")
for _, p in ipairs(list) do
    check(p.toc, "Plugins/" .. p.folder .. " has a TOC (without one it never loads or ships)")
end
for _, p in ipairs(list) do
  if p.toc then
    local t = io.open(p.dir .. p.toc):read("*a")
    local name = p.name
    check(name:match("^GlassPanel%u"), name .. ": AltStable-style name GlassPanel<Name>")
    check(t:find("## Interface: 16001", 1, true), name .. ": interface 16001")
    check(t:find("## Version: @project-version@", 1, true), name .. ": version token")
    check(t:find("## Title: |cff7fd4ffGlass|r Panel |cFF0099FF[", 1, true), name .. ": title 'Glass Panel [X]'")
    check(t:find("## Group: GlassPanel", 1, true), name .. ": grouped under the core")
    -- The core first; a bridge plugin may add the addon it reads (AltStable),
    -- never another GlassPanel plugin: each block switches off on its own.
    local deps = {}
    for d in (t:match("## Dependencies:([^\r\n]*)") or ""):gmatch("[^,%s]+") do deps[#deps + 1] = d end
    eq(deps[1], "GlassPanel", name .. ": depends on the core, listed first")
    for i = 2, #deps do
        check(not deps[i]:match("^GlassPanel"), name .. ": no dependency on another plugin (" .. deps[i] .. ")")
    end
    eq(t:match("## IconTexture: ([^\r\n]+)"), icon, name .. ": the core's icon")
    local files = tocFiles(p.toc, p.dir)
    check(#files > 0, name .. ": lists its files")
    for _, f in ipairs(files) do
        local src = io.open(f, "r")
        check(src ~= nil, name .. ": file exists: " .. f)
        if src then
            check(src:read("*a"):find("\nGlassPanel = GlassPanel or {}\n", 1, true), "starts with the namespace line: " .. f)
            src:close()
        end
    end
    local folder = p.dir:gsub("/$", "")
    eq(moves["GlassPanel/" .. folder], name, name .. ": .pkgmeta move-folders moves " .. folder .. " out")
  end
end

-- The core runs alone: every plugin can be switched off.
loadAddon({ plugins = false })
eq(#GlassPanel.Engine.blocks, 0, "core alone registers no blocks")
check(next(GlassPanel.failures) == nil, "core alone: no failures")
WoW.chat = {}
GlassPanel._test.slash("list")
check(WoW.chat[1] and WoW.chat[1]:find("drag a block", 1, true), "core alone: /gpanel list prints its header")
eq(#WoW.chat, 1, "core alone: and no lanes")

-- Two places that must agree, never derived from each other; the stub's
-- GetBuildInfo is the third: a mismatch is said at login (and only then).
WoW.chat = {}
loadAddon()
eq(GlassPanel.MEASURED_ON_BUILD, "1.60.1.70124", "MEASURED_ON_BUILD")
eq(GlassPanel.API.ClientBuild(), GlassPanel.MEASURED_ON_BUILD, "stub GetBuildInfo matches MEASURED_ON_BUILD")
check(not table.concat(WoW.chat, "\n"):find("differs", 1, true), "same build: no notice at login")
local realBuild = GetBuildInfo
GetBuildInfo = function() return "1.60.1", "99999", "", 16001 end
loadAddon()
check(table.concat(WoW.chat, "\n"):find("client build 1.60.1.99999 differs from the measured 1.60.1.70124", 1, true),
      "another build: said at login")
GetBuildInfo = realBuild

-- Every texture the material names exists in Media/.
for size, S in pairs(GlassPanel.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = "Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "bar_mask", "bar_fill", "gloss", "bar_edge", "grain", "sheen2", "track_fade" }) do
    check(io.open("Media/" .. t .. ".tga", "rb") ~= nil, "texture exists: " .. t)
end

-- Glass.lua is a copy of GlassUnitFrames' material on its MAIN branch: only
-- the namespace lines and the header may differ. Read through git, not the
-- working tree, whose branch another session may have switched.
local upstream = io.popen('git -C ../GlassUnitFrames show main:Glass.lua 2>nul')
local theirs = upstream and upstream:read("*a") or ""
if upstream then upstream:close() end
if theirs ~= "" then
    local function body(s)
        s = s:gsub("\r", "")
        s = s:gsub("^.-\nlocal ADDON = %.%.%.\n", "")   -- drop the header comment
        s = s:gsub("GlassUF", "GlassPanel")
        return s
    end
    local mine = io.open("Glass.lua"):read("*a")
    check(body(mine) == body(theirs), "Glass.lua matches GlassUnitFrames main:Glass.lua (copy it back)")
else
    io.write("  (Glass.lua upstream check skipped: no ../GlassUnitFrames git repo)\n")
end

-- A texture path written with single backslashes ("Interface\Icons\X")
-- loses them in Lua 5.1 ("\I" is read as "I", no error from luac): the
-- path silently breaks. Every shipped file, core and plugins.
local shipped = {}
for _, f in ipairs(tocFiles()) do shipped[#shipped + 1] = f end
for _, p in ipairs(list) do
    if p.toc then for _, f in ipairs(tocFiles(p.toc, p.dir)) do shipped[#shipped + 1] = f end end
end
for _, f in ipairs(shipped) do
    local src = io.open(f, "r"):read("*a")
    local bad = src:match('"Interface\\[^\\][^"]*"')
    check(not bad, f .. ": texture path with single backslashes " .. tostring(bad))
end

done("test_toc")
