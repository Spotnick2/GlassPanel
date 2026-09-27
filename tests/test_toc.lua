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
eq(tocFiles()[#tocFiles()], "GlassPanel.lua", "bootstrap loads last")
local seen = {}
for _, f in ipairs(tocFiles()) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

-- Two places that must agree, never derived from each other.
loadAddon()
eq(GlassPanel.MEASURED_ON_BUILD, "1.60.1.70009", "MEASURED_ON_BUILD")

-- Every texture the material names exists in Media/.
for size, S in pairs(GlassPanel.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = "Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "bar_mask", "bar_fill", "gloss", "bar_edge", "grain", "sheen2" }) do
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

done("test_toc")
