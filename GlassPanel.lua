-- GlassPanel.lua: bootstrap, saved settings and the /gpanel command.

local ADDON = ...
GlassPanel = GlassPanel or {}
local API, Glass, Engine, Bar, Layout = GlassPanel.API, GlassPanel.Glass, GlassPanel.Engine, GlassPanel.Bar, GlassPanel.Layout
local Settings = GlassPanel.Settings
local say = API.Print

local function findBlock(id)
    local block = id and Engine.byId[id]
    if not block then say("no block '" .. tostring(id) .. "' (see /gpanel list)") end
    return block
end

-- /gpanel covered (#2): every visible frame in the bar's band (the top
-- Bar.HEIGHT of the screen), outermost only (a listed frame's children are
-- implied), marked "under" when the bar is drawn over it and "beside" when
-- the bar already stops short of it (Room.lua). Screen pixels throughout
-- (rect * effective scale), since frames differ in scale. Read-only: nothing
-- is moved, forbidden frames are skipped, every number goes through API.Plain.
local P = API.Plain

-- Screen rect { l, r, top, bottom } of f, or nil (Room's conversion, so
-- both agree where a frame is). Called under pcall.
local function screenRect(f)
    local l, r, top, bottom = GlassPanel.Room.ScreenRect(f)
    if not l then return nil end
    return { l = l, r = r, top = top, bottom = bottom }
end

local function coveredEntry(f, bar, band, screenW)
    if f:IsForbidden() or not f:IsVisible() or f == bar or f:GetParent() == bar then return nil end
    local r = screenRect(f)
    if not r then return nil end
    local width, height = r.r - r.l, r.top - r.bottom
    if width < 2 or height < 2 or width >= screenW * 0.9 then return nil end   -- specks and full-screen layers
    if r.bottom >= band.top or r.top <= band.bottom then return nil end
    local name = f:GetDebugName()
    if type(name) ~= "string" or name:find("^GlassPanel") then return nil end
    local under = r.r > band.l and r.l < band.r
    return { frame = f, name = name, strata = f:GetFrameStrata(), protected = (f:IsProtected()),
             mouse = f:IsMouseEnabled(), under = under, depth = math.floor(band.top - r.top + 0.5) }
end

local function coveredFrames()
    local bar = Bar.frame
    if not bar then return {} end
    local okBar, band = pcall(screenRect, bar)
    local okUI, ui = pcall(screenRect, UIParent)
    if not (okBar and band and okUI and ui) then return {} end
    local screenW = ui.r - ui.l
    local hits, isHit = {}, {}
    local f = EnumerateFrames()
    while f do
        local fine, entry = pcall(coveredEntry, f, bar, band, screenW)
        if fine and entry then hits[#hits + 1] = entry; isHit[f] = true end
        f = EnumerateFrames(f)
    end
    local out = {}
    for _, e in ipairs(hits) do
        local p, nested = e.frame:GetParent(), false
        while p do
            if isHit[p] then nested = true break end
            p = p:GetParent()
        end
        if not nested then out[#out + 1] = e end
    end
    return out
end

local COMMANDS = {
    { "list", "lanes, their blocks, and which are hidden" },
    { "move <id> left|center|right|<0-100> [n]", "move a block into a lane (a % starts one there); n = position as /gpanel list shows it" },
    { "layout reset", "forget the arrangement: blocks go back to their default lanes" },
    { "labels on|off", "the gold captions before values (\"Bags: \"), for every block" },
    { "label <id> on|off|default", "one block's caption" },
    { "icon <id> on|off", "one block's icon" },
    { "show <id>", "show a block" },
    { "hide <id>", "hide a block" },
    { "toggle", "show or hide the whole bar" },
    { "font arial|friz", "bar font" },
    { "options", "open the options panel (Options > AddOns > Glass Panel)" },
    { "setup", "move Blizzard's top frames below the bar in an Edit Mode layout (shows the plan first)" },
    { "setup back", "switch back to the Edit Mode layout you had before" },
    { "export", "the whole setup as a string, to copy to another account" },
    { "import", "paste a setup exported on another account" },
    { "failures", "errors recorded from blocks and event registration" },
    { "room auto|full|why", "auto: the bar ends short of Blizzard's top frames (default); full: always full width; why: what it measured" },
    { "covered", "list the frames under the bar (#2 measurement)" },
}

local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local db = GlassPanelDB
    if cmd == "list" then
        say("drag a block to move it; shift-drag to move its whole lane")
        for _, lane in ipairs(Layout.Lanes()) do
            local names = {}
            for _, id in ipairs(lane.ids) do
                local block = Engine.byId[id]
                if not block then
                    names[#names + 1] = "|cff888888" .. id .. " (not loaded)|r"
                elseif Bar.IsHidden(block) then
                    names[#names + 1] = "|cff888888" .. id .. " (hidden)|r"
                else
                    names[#names + 1] = id
                end
            end
            say(string.format("lane at %d%%: %s", math.floor(lane.x * 100 + 0.5), table.concat(names, ", ")))
        end
    elseif cmd == "move" then
        local usage = "usage: /gpanel move <id> left|center|right|<0-100> [position]"
        local id, where, n = arg:match("^(%S+)%s+(%S+)%s*(%d*)$")
        if not id then say(usage) return end
        local block = findBlock(id)
        if not block then return end
        local W = Bar.frame and Bar.frame:GetWidth() or 0
        local x = Layout.SIDE_X[where]
        local pct = tonumber(where or "")
        if x == nil and pct and pct >= 0 and pct <= 100 then
            -- The same edge rule as a drag: near an end is that end.
            x = Layout.Anchor(pct / 100 * W, pct / 100 * W, W)
        end
        if x == nil then say(usage) return end
        if n ~= "" then
            Layout.Move(block.id, { lane = x, index = tonumber(n) }, W)
        else
            Layout.Move(block.id, { x = x }, W)
        end
        Bar.Layout()
    elseif cmd == "layout" and arg == "reset" then
        Settings.ResetLayout()
        say("layout reset")
    elseif cmd == "labels" then
        arg = arg:lower()
        if arg ~= "on" and arg ~= "off" then say("labels: on or off") return end
        Settings.SetLabels(arg == "on")
    elseif cmd == "label" then
        local id, v = arg:match("^(%S+)%s+(%S+)$")
        local block = findBlock(id)
        if not block then return end
        v = v:lower()
        if v == "on" then Settings.SetLabelFor(block.id, true)
        elseif v == "off" then Settings.SetLabelFor(block.id, false)
        elseif v == "default" then Settings.SetLabelFor(block.id, nil)
        else say("label <id> on|off|default") end
    elseif cmd == "icon" then
        local id, v = arg:match("^(%S+)%s+(%S+)$")
        local block = findBlock(id)
        if not block then return end
        v = v:lower()
        if v ~= "on" and v ~= "off" then say("icon <id> on|off") return end
        if not block.icon then say(block.id .. " has no icon") return end
        Settings.SetIconFor(block.id, v == "on")
    elseif cmd == "show" or cmd == "hide" then
        local block = findBlock(arg)
        if not block then return end
        Settings.SetHidden(block.id, cmd == "hide")
    elseif cmd == "toggle" then
        Settings.SetShown(not db.shown)
    elseif cmd == "font" then
        if not Settings.SetFont(arg:lower()) then say("fonts: arial, friz") end
    elseif cmd == "room" then
        if arg:lower() == "why" then
            say("room (" .. db.room .. "): what each watched frame measured, screen px")
            local ok, lines = pcall(GlassPanel.Room.Explain)
            if not ok then API.Fail("room:why", lines) say("  couldn't tell (see /gpanel failures)") return end
            for _, line in ipairs(lines) do say("  " .. line) end
        elseif not Settings.SetRoom(arg:lower()) then
            say("room: auto, full or why (now " .. db.room .. ")")
        end
    elseif cmd == "options" then
        if not GlassPanel.Options.Open() then say("find the options under Game Menu > Options > AddOns > Glass Panel") end
    elseif cmd == "setup" then
        if arg:lower() == "back" then
            local _, msg = GlassPanel.Setup.SwitchBack()
            say(msg)
        else
            GlassPanel.Setup.Open()
        end
    elseif cmd == "export" then
        GlassPanel.Share.Open("export")
    elseif cmd == "import" then
        GlassPanel.Share.Open("import")
    elseif cmd == "covered" then
        local list = coveredFrames()
        say(#list .. " frame(s) in the bar's band (under = drawn over, beside = the bar stops short):")
        for i, e in ipairs(list) do
            if i > 30 then say("  ...") break end
            say(string.format("  %s  %s  %s%s%s  %d", e.under and "under " or "beside", e.name, e.strata,
                e.protected and " PROTECTED" or "", e.mouse and " mouse" or "", e.depth))
        end
    elseif cmd == "failures" then
        local n = 0
        for key, err in pairs(GlassPanel.failures) do
            n = n + 1
            say(key .. ": " .. err)
        end
        if n == 0 then say("no failures recorded") end
    else
        say("commands:")
        for _, c in ipairs(COMMANDS) do say("  /gpanel " .. c[1] .. " - " .. c[2]) end
    end
end

local boot = CreateFrame("Frame")
API.RegisterEvent(boot, "ADDON_LOADED", "core")
API.RegisterEvent(boot, "PLAYER_LOGIN", "core")
API.RegisterEvent(boot, "PLAYER_ENTERING_WORLD", "core")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        local db = Settings.EnsureDefaults()
        Glass.SetFont(db.font)
        Bar.Build()
        Bar.SetShown(db.shown)
        SLASH_GLASSPANEL1 = "/gpanel"
        SlashCmdList.GLASSPANEL = slash
    elseif event == "PLAYER_LOGIN" then
        local build = API.ClientBuild()
        if build ~= GlassPanel.MEASURED_ON_BUILD then
            say("client build " .. build .. " differs from the measured " .. GlassPanel.MEASURED_ON_BUILD
                .. "; some notes may be stale")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Many APIs answer only once the world is up: repaint everything.
        Engine.MarkAllDirty()
    end
end)

GlassPanel._test = { slash = slash, coveredFrames = coveredFrames }
