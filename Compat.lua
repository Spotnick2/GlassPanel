-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else, plugins
-- included, calls through GlassPanel.API. Nothing is injected into _G.

GlassPanel = GlassPanel or {}
local API = {}
GlassPanel.API = API

-- The build this addon was last checked on: loads clean in game, /gpanel
-- failures empty, and its API dump matches the previous one (#52). Behaviours
-- measured once (secret values, Edit Mode, the aura icons) keep the build they
-- were measured on in their own notes. At login, any other build is said,
-- in a development copy only (API.IsDevelopmentCopy): a release keeps quiet.
-- tests/test_toc.lua pins the same literal; the stub's GetBuildInfo matches.
GlassPanel.MEASURED_ON_BUILD = "1.60.1.70124"

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

-- A development copy: `dev` from Tools/deploy.ps1, or the packager's raw
-- token in an unpackaged checkout. The build notice speaks only there (the
-- Priestly way, its #76): a release that still runs on a newer client gains
-- nothing from being told it was checked on an older one, and what flags an
-- addon out of date is the TOC's Interface number, not this.
function API.IsDevelopmentCopy()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata("GlassPanel", "Version")
    return version == "dev" or version == "@project-version@"
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

-- Hide a Blizzard frame that Blizzard manages (and may show again itself)
-- while one of our blocks replaces it, and give it back (#9: XP+ hides
-- StatusTrackingBarManager, which holds Blizzard's XP and rep bars).
-- The references' way (ElvUI, EllesmereUI; GlassUnitFrames' unit and cast
-- bars): reparent to a hidden frame, never Hide() (on Edit Mode systems it
-- goes through a protected SetShownBase that a later combat show turns into
-- ADDON_ACTION_BLOCKED). Every change is deferred to a timer (never inside
-- Blizzard's call), and waits for combat to end if the frame is protected.
-- While Edit Mode is open the frame is given back (so it can be seen and
-- moved there) and hidden again once Edit Mode closes: nothing is ever
-- hidden while Edit Mode is open. Blizzard
-- reparenting it is noticed through hooksecurefunc and undone the same
-- deferred way; a layout change (EDIT_MODE_LAYOUTS_UPDATED) re-checks.
-- Giving it back restores the parent Blizzard last gave it.
-- Pick the frame with care: one whose children call its methods through
-- GetParent() can't be reparented under ours. Measured on 70009: Edit Mode
-- threw "attempt to call a nil value" from MainStatusTrackingBarContainer
-- (its UpdateShownState calls GetParent():CheckForLayoutChange()), so XP+
-- hides the manager above it instead, which doesn't use its own parent.
--   local h = API.SystemHider("StatusTrackingBarManager")
--   h.Set(true)   -- hide, when safe;   h.Set(false)   -- give it back
local systemParent
function API.SystemHider(globalName)
    local h = { want = false }
    local frame, home, hooked, scheduled
    local waiter = CreateFrame("Frame")
    local sync

    local function editModeOpen()
        local em = rawget(_G, "EditModeManagerFrame")
        return type(em) == "table" and em.IsShown ~= nil and API.Plain(em:IsShown()) == true
    end

    local function later(seconds)
        if scheduled then return end
        scheduled = true
        C_Timer.After(seconds, function() scheduled = false; sync() end)
    end
    function h.request() later(0) end

    waiter:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then self:UnregisterEvent(event) end
        if h.want or (frame and systemParent and frame:GetParent() == systemParent) then h.request() end
    end)
    API.RegisterEvent(waiter, "EDIT_MODE_LAYOUTS_UPDATED", "hide " .. globalName)

    -- Edit Mode opening (give it back) and closing (hide it again): hooks
    -- that only schedule, never act inside Edit Mode's own Show/Hide.
    local emHooked = false
    local function watchEditMode()
        if emHooked then return end
        local em = rawget(_G, "EditModeManagerFrame")
        if type(em) == "table" and em.HookScript then
            emHooked = true
            em:HookScript("OnShow", function() h.request() end)
            em:HookScript("OnHide", function() h.request() end)
        end
    end

    sync = function()
        frame = frame or rawget(_G, globalName)
        if type(frame) ~= "table" or not frame.SetParent then
            if h.want then API.Fail("hide " .. globalName, "no such frame on this client") end
            return
        end
        watchEditMode()
        local hide = h.want and not editModeOpen()
        if API.Plain(InCombatLockdown()) ~= false and API.Plain((frame:IsProtected())) ~= false then
            API.RegisterEvent(waiter, "PLAYER_REGEN_ENABLED", "hide " .. globalName)
            return
        end
        if not systemParent then
            systemParent = CreateFrame("Frame", nil, UIParent)
            systemParent:Hide()
        end
        local parent = frame:GetParent()
        if hide then
            if not hooked then
                hooked = true
                hooksecurefunc(frame, "SetParent", function(_, p)
                    if h.want and p ~= systemParent then h.request() end
                end)
            end
            if parent ~= systemParent then
                home = parent   -- where Blizzard last put it
                frame:SetParent(systemParent)
            end
        elseif parent == systemParent and home then
            frame:SetParent(home)
        end
    end

    -- Hide (true) or give back (false), when it's safe.
    function h.Set(want)
        want = want and true or false
        if want == h.want then return end
        h.want = want
        h.request()
    end
    -- Whether it's hidden by us right now.
    function h.IsHidden()
        return frame ~= nil and systemParent ~= nil and frame:GetParent() == systemParent
    end
    return h
end

-- A glass dialog window: FULLSCREEN_DIALOG (above the Settings panel it may
-- be opened from), clamped, Escape closes it (UISpecialFrames, as AltStable
-- does on Forever), and an opaque backing under the glass: the glass is made
-- for the world, and over the Settings panel its text showed through (#36).
-- The backing sits above the shadow (-8), under the tint (-6), clipped by the
-- glass's own rounded mask. Fields: glass, backing, title, and hint (which
-- wraps inside the window: anchor content below `win.hint`). Hidden.
function API.Window(name, width, height)
    local Glass = GlassPanel.Glass
    local win = CreateFrame("Frame", name, UIParent)
    win:SetSize(width, height)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    local special = rawget(_G, "UISpecialFrames")
    if type(special) == "table" and name then table.insert(special, name) end
    win.glass = Glass.Apply(win, "small")
    win.backing = win:CreateTexture(nil, "BACKGROUND", nil, -7)
    win.backing:SetAllPoints(win)
    win.backing:SetColorTexture(0.05, 0.06, 0.08, 0.96)
    win.backing:AddMaskTexture(win.glass.mask)
    win.title = Glass.Font(win, 14, "LEFT")
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -12)
    win.hint = Glass.Font(win, 11, "LEFT")
    win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
    win.hint:SetPoint("RIGHT", win, "RIGHT", -14, 0)   -- wraps, never past the edge
    win.hint:SetTextColor(0.75, 0.75, 0.75)
    return win
end
