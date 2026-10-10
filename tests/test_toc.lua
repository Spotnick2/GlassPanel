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
-- The embedded material loads before any of our files: Glass.lua calls
-- LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first of our own files")
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

-- The packager rewrites its keywords in every file it ships, not only the TOC
-- (#59, Priestly #83): no shipped Lua file may hold one whole, or the release
-- reads differently from the source these tests load. Matched by shape, since
-- the packager has a family of them (@project-revision@, @debug@, ...). The
-- plugins' files are checked in the loop below.
local function noPackagerKeyword(f)
    local n = 0
    for line in io.lines(f) do
        n = n + 1
        local keyword = line:match("(@[%w%-]+@)")
        if keyword then
            check(false, f .. " holds the packager keyword " .. keyword .. " at line " .. n)
            return
        end
    end
    check(true, f .. " holds no packager keyword")
end
for _, f in ipairs(tocFiles()) do noPackagerKeyword(f) end

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
            noPackagerKeyword(f)
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
-- GetBuildInfo is the third: a mismatch is said at login (and only then), in a
-- development copy only.
local function said() return table.concat(WoW.chat, " | ") end
WoW.chat = {}
WoW.addonVersion = "dev"
loadAddon()
eq(GlassPanel.MEASURED_ON_BUILD, "1.60.1.70338", "MEASURED_ON_BUILD")
eq(GlassPanel.API.ClientBuild(), GlassPanel.MEASURED_ON_BUILD, "stub GetBuildInfo matches MEASURED_ON_BUILD")
check(not said():find("differs", 1, true), "same build: no notice at login")
local realBuild = GetBuildInfo
GetBuildInfo = function() return "1.60.1", "99999", "", 16001 end
loadAddon()
check(said():find("client build 1.60.1.99999 differs from the measured " .. GlassPanel.MEASURED_ON_BUILD, 1, true),
      "another build, deployed copy (dev): said at login")
-- Once per new build: the next login on it keeps quiet, a newer one speaks.
local saved = GlassPanelDB
loadAddon({ db = saved })
check(not said():find("differs", 1, true), "same new build, next login: not said again")
GetBuildInfo = function() return "1.60.1", "99998", "", 16001 end
loadAddon({ db = saved })
check(said():find("client build 1.60.1.99998", 1, true), "a newer build: said once more")
GetBuildInfo = function() return "1.60.1", "99999", "", 16001 end
WoW.addonVersion = "@project-version@"
loadAddon()
check(said():find("differs", 1, true), "another build, unpackaged checkout: said too")
-- A release keeps quiet on any build: the notice is for whoever re-measures.
WoW.addonVersion = "v1.0.0"
loadAddon()
check(not said():find("differs", 1, true), "another build, release: no notice")
GetBuildInfo = realBuild

-- Every texture the material names ships with the library (Libs\LibGlass-1.0\Media
-- in the package; the checkout's Media/ here). GlassPanel has no Media/ of its own.
local root = libGlassRoot()
for size, S in pairs(GlassPanel.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "bar_mask", "bar_fill", "gloss", "bar_edge", "grain", "sheen2", "track_fade" }) do
    check(io.open(root .. "/Media/" .. t .. ".tga", "rb") ~= nil, "texture exists: " .. t)
end
-- Glass.MEDIA points into the embedded copy, where the packager puts it.
eq(GlassPanel.Glass.MEDIA, "Interface\\AddOns\\GlassPanel\\Libs\\LibGlass-1.0\\Media\\", "MEDIA is the embedded copy's")
-- An instance of our own, not the library: our font setting never reaches
-- another glass addon's surfaces.
check(GlassPanel.Glass ~= LibStub("LibGlass-1.0"), "Glass is an instance, not the library")

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
