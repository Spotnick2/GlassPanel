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

-- A value, or nil when it is secret. Secrecy is tested FIRST: even `== nil`
-- on a secret is a comparison. Use at the point of every read.
function API.Plain(v)
    if API.IsSecret(v) then return nil end
    return v
end

-- Did the client return anything at all (a value, readable or secret)?
-- Use this instead of `raw ~= nil` on a raw read: on the client, comparing a
-- secret, even with nil, throws, and the offline stub can't catch that (no
-- Lua 5.1 value can make == throw).
function API.Returned(v)
    return API.IsSecret(v) or v ~= nil
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
-- Secrecy is tested FIRST, on everything: a client secret keeps its
-- underlying type, so a secret string passes type(x) == "string" and would be
-- stored, then throw when /gpanel failures concatenates it.
local function printable(v)
    if API.IsSecret(v) then return nil end
    if type(v) == "string" then return v end
    local ok, s = pcall(tostring, v)
    if ok and type(s) == "string" and not API.IsSecret(s) then return s end
    return nil
end

function API.Fail(key, err)
    GlassPanel.failures[printable(key) or "?"] = printable(err) or "(unprintable error)"
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
    copper = API.Plain(copper)
    if copper == nil then return nil end
    local fmt = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
    if fmt then
        local ok, text = pcall(fmt, copper)
        if ok and type(text) == "string" then return text end
    end
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- Hide a Blizzard frame (by global name) while one of our blocks replaces it,
-- and give it back afterwards. Used by the clock (TimeManagerClockButton) and
-- XP (MainStatusTrackingBarContainer).
--   s.Want(true|false)  -- our block is visible / not
--   s.Sync()            -- retry, e.g. when a load-on-demand Blizzard addon loads
-- We only ever Show() the frame again if we were the ones who hid it, so a
-- frame the user or Blizzard had hidden stays hidden. Blizzard re-shows these
-- frames (settings, Edit Mode), so an OnShow hook re-hides while wanted. The
-- state lives in locals, never as a field on their frame: writing into a
-- Blizzard frame's table taints it. Only for frames that are not protected.
-- Not handled: the user turning the frame OFF in Settings while we hide it
-- (hidden either way, nothing to observe), so it comes back when ours goes.
function API.Suppressor(globalName)
    local s = { want = false }
    local hid, hooked = false, false
    function s.Sync()
        local f = rawget(_G, globalName)
        if not f then return end
        if not hooked then
            -- Hiding a frame that was just shown (by Blizzard, or by the user
            -- in Settings) makes it ours to give back.
            f:HookScript("OnShow", function(self)
                if s.want then hid = true; self:Hide() end
            end)
            hooked = true
        end
        if s.want then
            if f:IsShown() then hid = true end
            f:Hide()
        elseif hid then
            hid = false
            f:Show()
        end
    end
    function s.Want(visible)
        s.want = visible
        s.Sync()
    end
    return s
end

-- A standard push button (UIPanelButtonTemplate exists here: porting guide),
-- for the options panel and the share window.
function API.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- UIPanelScrollFrameTemplate shows its bar (arrows, thumb) even with
-- nothing to scroll: show it only while the content is taller than the view
-- (as GlassUnitFrames' options panel does). Seen in game (#36). The range is
-- floored like the template's own ScrollFrame_OnScrollRangeChanged: under 1
-- unit (a fractional UI scale) is nothing to scroll. (The template's
-- scrollBarHideable flag would do this too, but isn't measured on Forever.)
function API.AutoHideScrollBar(scroll)
    local bar = scroll.ScrollBar
    if not bar then return end
    local function sync(self, _, yrange)
        bar:SetShown(math.floor(yrange or self:GetVerticalScrollRange() or 0) > 0)
    end
    scroll:HookScript("OnScrollRangeChanged", sync)
    sync(scroll)
end
