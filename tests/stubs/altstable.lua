-- AltStable's public API (Plugins/AltStable), version 1, as documented in
-- ..\AltStable\docs\PUBLIC-API.md. Not a client API: AltStable is another
-- addon, and this mirrors its documented contract (not its code).
-- WoW.alts = { characters = { { guid, name, realm, faction, class, level,
-- money, hidden, current }, ... }, version = 1 }; WoW.altsToggles counts
-- ToggleSheet calls. WoW.altsChanged() is a change: like AltStable, one
-- "CharactersChanged" per burst, on the next frame (WoW.flushTimers(0)), each
-- listener under pcall (errors in WoW.altsErrors). A listener registered by
-- an earlier loadAddon session is never called: that session is dead.
table.insert(WoW.resetHooks, function()
    WoW.alts = { characters = {}, version = 1 }
    WoW.altsToggles = 0
    WoW.altsListeners, WoW.altsErrors, WoW.altsBurst = {}, {}, 0
end)

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    c.account = c.account or ""
    c.hidden = c.hidden == true
    c.current = c.current == true
    return c
end

AltStable = setmetatable({}, { __index = function(_, k)
    if k == "PUBLIC_API_VERSION" then return WoW.alts.version end
end })

function AltStable.GetCharacters()
    local out = {}
    for _, c in ipairs(WoW.alts.characters) do out[#out + 1] = copy(c) end
    table.sort(out, function(a, b)
        local ra, rb = tostring(a.realm or ""), tostring(b.realm or "")
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return out
end

function AltStable.GetTotals()
    local t = { money = 0, unknown = 0, characters = 0, hidden = 0, levels = 0 }
    for _, c in ipairs(WoW.alts.characters) do
        if c.hidden then t.hidden = t.hidden + 1 else
            t.characters = t.characters + 1
            t.levels = t.levels + (c.level or 0)
            if c.money then t.money = t.money + c.money else t.unknown = t.unknown + 1 end
        end
    end
    return t
end

function AltStable.ToggleSheet() WoW.altsToggles = WoW.altsToggles + 1 end
function AltStable.OpenSheet() end

function AltStable.RegisterCallback(event, fn)
    assert(event == "CharactersChanged", "unknown event " .. tostring(event))
    table.insert(WoW.altsListeners, { fn = fn, session = GlassPanel })
end
function AltStable.UnregisterCallback(event, fn)
    for i, f in ipairs(WoW.altsListeners) do if f.fn == fn then table.remove(WoW.altsListeners, i) return end end
end

function WoW.altsChanged()
    WoW.altsBurst = WoW.altsBurst + 1
    local burst = WoW.altsBurst
    C_Timer.After(0, function()
        if burst ~= WoW.altsBurst then return end   -- a later change in the same burst delivers
        for _, l in ipairs(WoW.altsListeners) do
            if l.session == GlassPanel then
                local ok, err = pcall(l.fn, "CharactersChanged")
                if not ok then table.insert(WoW.altsErrors, err) end
            end
        end
    end)
end
