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
GlassPanel.MEASURED_ON_BUILD = "1.60.1.71037"

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
-- The token is built from two pieces: the packager rewrites it whole in every
-- file it ships, Lua included, so a literal here would read as the release's
-- own version and every player's copy would count as a development copy (#59).
local UNPACKAGED_VERSION = "@" .. "project-version@"
function API.IsDevelopmentCopy()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata("GlassPanel", "Version")
    return version == "dev" or version == UNPACKAGED_VERSION
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
-- does on Forever). Fields: glass, backing, pane, reflect, title, and hint (which
-- wraps inside the window: anchor content below `win.hint`). Hidden.
--
-- The look is the reflective shell of References\Docs\LIBGLASS-WINDOW-STYLING.md
-- (#93), on the clean instance (LibGlass r9's Reflect): a moderately smoked
-- shell, an extra masked backing so the Settings panel can't show through
-- (#36), a header reflection over the title and hint, and one masked reading
-- region (`pane`) under them for whatever the caller puts in the window.
-- Backing (BACKGROUND -7) sits above the shadow (-8), under the tint (-6),
-- clipped by the glass's own rounded mask. The earlier look (a near-opaque backing on the
-- classic small glass) stays for the setting `windowGlass` "smoked" and for a library
-- copy older than r9 (or no clean instance).
local HEADER = 64   -- px the header reflection spans: gone before the reading region

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
    win.title = Glass.Font(win, 14, "LEFT")
    GlassPanel.Suite.Accented(win.title)   -- the stock UI's gold, or the suite's accent (#106)
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -12)
    win.hint = Glass.Font(win, 11, "LEFT")
    win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
    win.hint:SetPoint("RIGHT", win, "RIGHT", -14, 0)   -- wraps, never past the edge
    win.hint:SetTextColor(0.75, 0.75, 0.75)

    local clean = GlassPanel.CleanGlass and GlassPanel.CleanGlass()
    local smoked = type(GlassPanelDB) == "table" and GlassPanelDB.windowGlass == "smoked"   -- the player's choice (#93)
        and not GlassPanel.Suite.Following()   -- suspended while following Glass UI (#96)
    if clean and clean.Reflect and clean.SetSurfaceAlpha and not smoked then
        local g = clean.Apply(win, "large")
        win.glass = g
        clean.SetSurfaceTint(g, 0.085, 0.095, 0.115, 0.78)
        clean.SetWash(g, 0)
        clean.SetEdge(g, 0, 0, 0)
        clean.SetSurfaceAlpha(g, "rim", 0.12)
        clean.SetSurfaceAlpha(g, "dark", 0.55)
        clean.SetSurfaceAlpha(g, "grain", 0)
        clean.SetSurfaceAlpha(g, "shadow", 0.18)
        win.backing = win:CreateTexture(nil, "BACKGROUND", nil, -7)
        win.backing:SetAllPoints(win)
        win.backing:SetColorTexture(0.03, 0.03, 0.035, 0.55)
        win.backing:AddMaskTexture(g.mask)
        win.reflect = clean.Reflect(g, win, { header = math.max(0, math.min(HEADER, height - 12)) })
        -- The reading region: one plain masked texture under the hint, to the
        -- bottom, whatever the hint's line count.
        win.pane = win:CreateTexture(nil, "BACKGROUND", nil, -7)
        win.pane:SetPoint("TOPLEFT", win.hint, "BOTTOMLEFT", -6, -8)
        win.pane:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 8)
        win.pane:SetColorTexture(0.072, 0.082, 0.10, 0.94)
        local S = clean.SIZES.thin_small
        win.pane:AddMaskTexture(clean.Mask(win, S.mask, S.maskMargin, 0, win.pane))
    else
        win.glass = Glass.Apply(win, "small")
        win.backing = win:CreateTexture(nil, "BACKGROUND", nil, -7)
        win.backing:SetAllPoints(win)
        win.backing:SetColorTexture(0.05, 0.06, 0.08, 0.96)
        win.backing:AddMaskTexture(win.glass.mask)
    end
    return win
end

-- A one-time alert when a readout runs low (#130): Durability and Ammo, at the
-- levels where their figure turns yellow (1, low) and red (2, critical); 0 is fine.
--   local alert = API.LevelAlert(owner, enabled)  -- enabled(): the plugin's own option
--   alert.Set(level, message)  -- after each fresh reading; nil (unknown, unsure) is ignored
--   alert.Reset()              -- the next reading is a new baseline (thresholds or kind changed)
-- Once per crossing: said when the level gets worse than the worst one said
-- since it last improved, so a repair or a restock arms it again. The first
-- reading of a session is the baseline: a /reload while low says nothing. Never
-- in combat: a crossing in a fight is said when it ends, with the latest
-- message, if it's still worse. Switched off, it follows quietly, so switching
-- it on says nothing about what the bar already shows. Said as centre-screen
-- text (RaidWarningFrame, Blizzard_RaidWarning's AddMessage(text, colorInfo)),
-- a chat line and the raid-warning sound, each feature-detected, under pcall.
local RAID_WARNING_SOUND = 8959   -- SOUNDKIT.RAID_WARNING (SoundKitConstants.lua)
local ALERT_COLOUR = { [1] = { r = 1, g = 0.82, b = 0, hex = "ffd200" },
                       [2] = { r = 1, g = 0.25, b = 0.25, hex = "ff4040" } }
local held = {}   -- trackers with a crossing held until combat ends
local alertWaiter

local function sayAlert(owner, level, message)
    local c = ALERT_COLOUR[level] or ALERT_COLOUR[2]
    local rw = rawget(_G, "RaidWarningFrame")
    if type(rw) == "table" and type(rw.AddMessage) == "function" then
        local ok, err = pcall(rw.AddMessage, rw, message, { r = c.r, g = c.g, b = c.b })
        if not ok then API.Fail(owner .. ":alert", err) end
    end
    API.Print("|cff" .. c.hex .. message .. "|r")
    local play = rawget(_G, "PlaySound")
    if type(play) == "function" then
        local kits = rawget(_G, "SOUNDKIT")
        local id = type(kits) == "table" and type(kits.RAID_WARNING) == "number" and kits.RAID_WARNING
            or RAID_WARNING_SOUND
        pcall(play, id)
    end
end

local function holdUntilCombatEnds(tracker, owner)
    held[tracker] = true
    if not alertWaiter then
        alertWaiter = CreateFrame("Frame")
        alertWaiter:SetScript("OnEvent", function(self, event)
            self:UnregisterEvent(event)
            local list = {}
            for t in pairs(held) do list[#list + 1] = t end
            for _, t in ipairs(list) do
                held[t] = nil
                t.try()
            end
        end)
    end
    API.RegisterEvent(alertWaiter, "PLAYER_REGEN_ENABLED", owner)
end

function API.LevelAlert(owner, enabled)
    local a = {}
    local said, current, message   -- said nil: no baseline yet
    function a.try()
        if said == nil or current == nil or current <= said then return end
        local ok, on = pcall(enabled)
        if not (ok and on == true) then said = current; return end
        if API.Plain(InCombatLockdown()) ~= false then
            holdUntilCombatEnds(a, owner)
            return
        end
        said = current
        sayAlert(owner, current, message)
    end
    function a.Set(level, text)
        if type(level) ~= "number" or type(text) ~= "string" then return end
        current, message = level, text
        if said == nil or level < said then said = level end
        a.try()
    end
    function a.Reset()
        said, current, message = nil, nil, nil
        held[a] = nil
    end
    return a
end

-- Item data that loads late (#74): one loader per plugin, shared code. GearScore,
-- Reagents and Ammo each had their own copy, already drifting (one lost the
-- failed-load guard and looped). Rules, from those copies and their reviews:
-- - Request(id) asks once, only while the client says the item isn't cached
--   (evenIfCached: skip that check, for data missing although it says it's
--   cached), and never again once answered, loaded or failed: an answer that
--   leaves the data missing would otherwise loop (request, load, repaint,
--   request).
-- - ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED fire for every item the
--   client loads, so they're registered on the loader's own frame only while
--   one of its ids is pending.
-- - onLoaded(id, success) runs for each of its answers, under pcall (a throw is
--   recorded as "<owner>:itemload"); success is false for a failed load, nil
--   when unreadable.
-- - State(id): "pending", "failed" (answered with a failure), "loaded"
--   (answered), or nil (never asked). Reset() forgets every id (GearScore's
--   new gear); an answer to an id asked before is then ignored.
local ITEM_LOAD_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }
function API.ItemLoader(owner, onLoaded)
    local L = { pending = {}, answered = {}, failed = {} }
    local frame = CreateFrame("Frame")
    local listening = false
    local function listen(on)
        if on == listening then return end
        listening = on
        for _, e in ipairs(ITEM_LOAD_EVENTS) do
            if on then API.RegisterEvent(frame, e, owner) else frame:UnregisterEvent(e) end
        end
    end
    frame:SetScript("OnEvent", function(_, _, rawId, rawSuccess)
        local id = API.Plain(rawId)
        if id and L.pending[id] then
            L.pending[id] = nil
            L.answered[id] = true
            local success = API.Plain(rawSuccess)
            if success == false then L.failed[id] = true end
            if onLoaded then
                local ok, err = pcall(onLoaded, id, success)
                if not ok then API.Fail(owner .. ":itemload", err) end
            end
        end
        if next(L.pending) == nil then listen(false) end
    end)
    function L.Request(id, evenIfCached)
        if id == nil or L.pending[id] or L.answered[id] then return end
        if not evenIfCached then
            local ok, cached = pcall(C_Item.IsItemDataCachedByID, id)
            if ok and API.Plain(cached) == true then return end   -- loaded: nothing more will come
        end
        L.pending[id] = true
        C_Item.RequestLoadItemDataByID(id)
        listen(true)
    end
    function L.State(id)
        if L.pending[id] then return "pending" end
        if L.failed[id] then return "failed" end
        if L.answered[id] then return "loaded" end
        return nil
    end
    function L.Reset()
        L.pending, L.answered, L.failed = {}, {}, {}
        listen(false)
    end
    function L.Listening() return listening end
    return L
end

-- The picker window (#74): pick which entries a block shows, and in what
-- order (Currencies' chooser, #47; Reagents copied it, #68). spec:
-- - name, title, hint, empty: the window's global name and texts;
-- - items(): the entries offered, each { id = ..., ... }, in the order the
--   unpicked ones are listed;
-- - picks(items): the saved order, as ids;
-- - resolve(id): the entry for a saved id items() doesn't hold, or nil when
--   the client can't resolve it right now (it's kept, at the end, untouched);
-- - save(order): write the ids back;
-- - label(entry): a row's text;
-- - ordered = false: no Up/Down (#179: [Broker]'s picks are blocks of their
--   own, placed on the bar, so their order here means nothing).
-- Returns { Open, Refresh, RefreshSoon (once per frame, only while shown),
-- Window, rows }. Rows: a checkbox to show, Up/Down to order the shown ones.
local PICKER_ROW_W, PICKER_ROW_H = 340, 26
function API.Picker(spec)
    local p = { rows = {} }
    local rows, win = p.rows, nil

    -- The rows: the shown ones first, in order (only those the client
    -- resolves), then the rest as items() lists them. `shown` is that first
    -- part, as ids; `unresolved` the saved ids the client doesn't resolve now.
    local function entries()
        local items = spec.items()
        local byId = {}
        for _, e in ipairs(items) do byId[e.id] = e end
        local list, shown, used, unresolved = {}, {}, {}, {}
        for _, id in ipairs(spec.picks(items)) do
            local e = byId[id] or spec.resolve(id)
            if e then
                list[#list + 1] = e
                shown[#shown + 1] = id
                used[id] = true
            else
                unresolved[#unresolved + 1] = id
            end
        end
        for _, e in ipairs(items) do
            if not used[e.id] then list[#list + 1] = e end
        end
        return list, shown, used, unresolved
    end

    -- Write `shown` (the visible order) back, the unresolved saved ids kept
    -- at the end, untouched.
    local function saveShown(shown, unresolved)
        local keep = {}
        for _, id in ipairs(shown) do keep[#keep + 1] = id end
        for _, id in ipairs(unresolved) do keep[#keep + 1] = id end
        spec.save(keep)
        p.Refresh()
    end

    local function move(id, step)
        local _, shown, _, unresolved = entries()
        for i, v in ipairs(shown) do
            if v == id then
                local j = i + step
                if j >= 1 and j <= #shown then shown[i], shown[j] = shown[j], shown[i] end
                break
            end
        end
        saveShown(shown, unresolved)
    end

    local function toggle(id, on)
        local _, shown, _, unresolved = entries()
        local out = {}
        for _, v in ipairs(shown) do
            if v ~= id then out[#out + 1] = v end
        end
        if on then out[#out + 1] = id end
        saveShown(out, unresolved)
    end

    local function row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Frame", nil, win.content)
        r:SetSize(PICKER_ROW_W, PICKER_ROW_H)
        r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * PICKER_ROW_H)
        r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
        r.check:SetSize(24, 24)
        r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.check:SetScript("OnClick", function(self) toggle(r.id, self:GetChecked() and true or false) end)
        r.text = GlassPanel.Glass.Font(r, 12, "LEFT")
        r.text:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
        r.up = API.Button(r, "Up", 44, function() move(r.id, -1) end)
        r.up:SetPoint("RIGHT", r, "RIGHT", -52, 0)
        r.down = API.Button(r, "Down", 48, function() move(r.id, 1) end)
        r.down:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        rows[i] = r
        return r
    end

    function p.Refresh()
        if not win then return end
        local list, shown, used = entries()
        local pos = {}
        for i, id in ipairs(shown) do pos[id] = i end
        for i, e in ipairs(list) do
            local r = row(i)
            r.id = e.id
            r.check:SetChecked(used[e.id] == true)
            r.text:SetText(spec.label(e))
            r.up:SetShown(spec.ordered ~= false and used[e.id] == true)
            r.down:SetShown(spec.ordered ~= false and used[e.id] == true)
            r.up:SetEnabled(pos[e.id] ~= nil and pos[e.id] > 1)
            r.down:SetEnabled(pos[e.id] ~= nil and pos[e.id] < #shown)
            r:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        win.content:SetHeight(math.max(#list, 1) * PICKER_ROW_H)
        win.empty:SetShown(#list == 0)
    end

    -- Events come in bursts (login, loot, bags): one refresh per frame.
    local queued = false
    function p.RefreshSoon()
        if queued or not (win and win:IsShown()) then return end
        queued = true
        C_Timer.After(0, function()
            queued = false
            if win and win:IsShown() then p.Refresh() end
        end)
    end

    function p.Open()
        if not win then
            win = API.Window(spec.name, 400, 320)
            win.title:SetText(spec.title)
            win.hint:SetText(spec.hint)
            local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", win.hint, "BOTTOMLEFT", 0, -8)
            scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 42)
            win.content = CreateFrame("Frame", nil, scroll)
            win.content:SetSize(PICKER_ROW_W, PICKER_ROW_H)
            scroll:SetScrollChild(win.content)
            API.AutoHideScrollBar(scroll)
            win.empty = GlassPanel.Glass.Font(win.content, 12, "LEFT")
            win.empty:SetPoint("TOPLEFT", win.content, "TOPLEFT", 4, -4)
            win.empty:SetText(spec.empty)
            local close = API.Button(win, "Close", 90, function() win:Hide() end)
            close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
        end
        p.Refresh()
        win:Show()
    end

    function p.Window() return win end
    return p
end
