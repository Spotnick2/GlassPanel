-- AltStable's public API (Plugins/AltStable), version 1, as documented in
-- ..\AltStable\docs\PUBLIC-API.md. Not a client API: AltStable is another
-- addon, and this mirrors its documented contract (not its code).
-- WoW.alts = { characters = { { guid, name, realm, faction, class, level,
-- money, hidden, current }, ... }, version = 1 }; WoW.altsChanged() fires
-- "CharactersChanged"; WoW.altsToggles counts ToggleSheet calls.
table.insert(WoW.resetHooks, function()
    WoW.alts = { characters = {}, version = 1 }
    WoW.altsToggles = 0
    WoW.altsListeners = {}
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
    table.insert(WoW.altsListeners, fn)
end
function AltStable.UnregisterCallback(event, fn)
    for i, f in ipairs(WoW.altsListeners) do if f == fn then table.remove(WoW.altsListeners, i) return end end
end

function WoW.altsChanged()
    for _, fn in ipairs(WoW.altsListeners) do fn("CharactersChanged") end
end
