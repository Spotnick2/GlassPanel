-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else, plugins
-- included, calls through GlassPanel.API. Nothing is injected into _G.

GlassPanel = GlassPanel or {}
local API = {}
GlassPanel.API = API

-- The build the notes this addon relies on were measured on. Bump only after
-- re-measuring in game; tests/test_toc.lua pins the same literal.
GlassPanel.MEASURED_ON_BUILD = "1.60.1.70009"

function API.Print(msg)
    print("|cff7fd4ffGlassPanel|r " .. msg)
end

-- True for a Retail secret value. Such a value may be handed back to the
-- client (SetText, SetFormattedText, StatusBar) but never compared, added,
-- concatenated, tostring'd or truth-tested in Lua.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- The one failure recorder: key -> last error, read by /gpanel failures.
-- A block that throws is recorded here and the rest of the bar still paints.
GlassPanel.failures = {}

-- Called from inside the isolation boundary, so it must not throw itself:
-- a block may error() with a secret or an object whose __tostring throws.
function API.Fail(key, err)
    local msg = "(unprintable error)"
    if type(err) == "string" then
        msg = err
    elseif not API.IsSecret(err) then
        local ok, s = pcall(tostring, err)
        if ok and type(s) == "string" then msg = s end
    end
    GlassPanel.failures[key] = msg
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported: a silently missing
-- handler is the bug this exists to prevent. `owner` names who asked (a
-- block id) so the report points at the right plugin.
function API.RegisterEvent(frame, name, owner)
    local ok, registered = pcall(frame.RegisterEvent, frame, name)
    if ok and registered ~= false then return true end
    local why = ok and "refused" or tostring(registered)
    API.Fail("event:" .. name, (owner or "?") .. ": " .. why)
    API.Print("|cffff6060could not register|r " .. name .. " for " .. (owner or "?") .. " (" .. why .. ")")
    return false
end

-- Copper -> "12g 34s 56c" with coin icons. The global GetCoinTextureString
-- is absent on Forever (70009 dump); only the C_CurrencyInfo one exists.
-- Returns nil for a secret amount: GetMoney has been measured secret on a PvP
-- realm, and nothing says the formatter accepts one.
function API.CoinText(copper)
    -- Secrecy first: even == nil on a secret is a comparison.
    if API.IsSecret(copper) or copper == nil then return nil end
    local fmt = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
    if fmt then
        local ok, text = pcall(fmt, copper)
        if ok and type(text) == "string" then return text end
    end
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end
