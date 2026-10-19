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

-- The material is Pearl (LibGlass r11), our own default look and the suite's
-- (#96). Glass UI is asked first, once (Suite.lua), whether the player wants
-- to follow the suite; either way Pearl is built, and a library older than
-- r11 (the newest copy among the glass addons runs) falls back to the
-- earlier look, said and reported: "library-too-old", or "build-failed" when
-- New itself errors. LibGlass never restyles a built instance, so there is
-- no retry.
local Suite = GlassPanel.Suite
Suite.Decide()
local lib, minor = LibStub("LibGlass-1.0")
local pearl = false
do
    local why
    if type(minor) ~= "number" or minor < 11 then
        why = "library-too-old"
    else
        local ok, made = pcall(lib.New, lib, { preset = "pearl" })
        if ok and made then
            GlassPanel.Glass, pearl = made, true
        else
            why = tostring(made):find("unknown preset", 1, true) and "library-too-old" or "build-failed"
        end
    end
    if not pearl then
        GlassPanel.Glass = lib:New()
        GlassPanel.API.Fail("glass:pearl", "the Pearl glass couldn't be built (" .. why .. "): the earlier look instead")
    end
    Suite.Built(pearl and "pearl" or nil, why, minor)
end

-- The clean-surface instance (#78): thin rims, no grain, softer bars, neutral
-- tracks. Pearl is that look with softer highlights, so when the main glass is
-- Pearl so is this one (#96); else r6's clean preset. An instance of its own,
-- made once on demand, for surfaces that opt
-- in (XP+'s zoomed bar, the windows); nil when the copy LibStub loaded is older (the
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
            local ok, inst = pcall(lib.New, lib, { preset = pearl and "pearl" or "clean" })
            if ok then clean = inst else GlassPanel.API.Fail("glass:clean", inst) end
        end
    end
    return clean or nil
end
