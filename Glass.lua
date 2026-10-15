-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Its contract, write-up and textures are
-- there: material changes are LibGlass PRs, not edits here.
--
-- An instance, not the library itself: STYLE, the live setters and the font
-- registry are this addon's own, so GlassPanel's font never touches another
-- glass addon's surfaces. Plugins reach it as GlassPanel.Glass (public API),
-- with the same dot-call shape (Glass.Apply, Glass.Bar, Glass.MEDIA, ...).

GlassPanel = GlassPanel or {}
GlassPanel.Glass = LibStub("LibGlass-1.0"):New()

-- LibGlass r6's clean preset (#78): thin rims, no grain, softer bars, neutral
-- tracks. An instance of its own, made once on demand, for surfaces that opt
-- in (XP+'s zoomed bar); nil when the copy LibStub loaded is older (the
-- newest copy among every glass addon runs, so a development checkout or an
-- older addon could still bring r5): callers fall back to GlassPanel.Glass.
-- Presets are construction settings: text stays on GlassPanel.Glass, whose
-- font the player sets.
local clean
function GlassPanel.CleanGlass()
    if clean == nil then
        clean = false
        local lib, minor = LibStub("LibGlass-1.0")
        if type(minor) == "number" and minor >= 6 then
            local ok, inst = pcall(lib.New, lib, { preset = "clean" })
            if ok then clean = inst else GlassPanel.API.Fail("glass:clean", inst) end
        end
    end
    return clean or nil
end
