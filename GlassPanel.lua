-- GlassPanel.lua: bootstrap, saved settings and the /gpanel command.

local ADDON = ...
GlassPanel = GlassPanel or {}
local API, Glass, Engine, Bar, Layout = GlassPanel.API, GlassPanel.Glass, GlassPanel.Engine, GlassPanel.Bar, GlassPanel.Layout
local say = API.Print

local DEFAULTS = { font = "arial", shown = true }

-- Read settings, fill missing keys. Nothing may REQUIRE a value to have
-- survived: SavedVariables were broken on builds before 70009.
local function ensureDefaults()
    if type(GlassPanelDB) ~= "table" then GlassPanelDB = {} end
    local db = GlassPanelDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    if type(db.hidden) ~= "table" then db.hidden = {} end
    if not Glass.FONTS[db.font] then db.font = DEFAULTS.font end
    return db
end

local function findBlock(id)
    local block = id and Engine.byId[id]
    if not block then say("no block '" .. tostring(id) .. "' (see /gpanel list)") end
    return block
end

local COMMANDS = {
    { "list", "lanes, their blocks, and which are hidden" },
    { "move <id> left|center|right|<0-100> [n]", "move a block to a lane (or start one at n% of the bar)" },
    { "layout reset", "forget the arrangement: blocks go back to their default lanes" },
    { "show <id>", "show a block" },
    { "hide <id>", "hide a block" },
    { "toggle", "show or hide the whole bar" },
    { "font arial|friz", "bar font" },
    { "failures", "errors recorded from blocks and event registration" },
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
        local id, where, n = arg:match("^(%S+)%s+(%S+)%s*(%d*)$")
        local block = findBlock(id)
        if not block then return end
        local x = ({ left = 0, center = 0.5, right = 1 })[where or ""]
        local pct = tonumber(where or "")
        if x == nil and pct and pct >= 0 and pct <= 100 then x = pct / 100 end
        if x == nil then say("usage: /gpanel move <id> left|center|right|<0-100> [position]") return end
        if n ~= "" then
            Layout.Move(block.id, { lane = x, index = tonumber(n) })
        else
            Layout.Move(block.id, { x = x })
        end
        Bar.Layout()
    elseif cmd == "layout" and arg == "reset" then
        Layout.Reset()
        Bar.Layout()
        say("layout reset")
    elseif cmd == "show" or cmd == "hide" then
        local block = findBlock(arg)
        if not block then return end
        db.hidden[block.id] = (cmd == "hide") or nil
        Bar.Layout()
    elseif cmd == "toggle" then
        db.shown = not db.shown
        Bar.SetShown(db.shown)
    elseif cmd == "font" then
        arg = arg:lower()
        if Glass.SetFont(arg) then
            db.font = arg
            -- Every width depends on the font: remeasure.
            Bar.Layout()
        else
            say("fonts: arial, friz")
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
        local db = ensureDefaults()
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

GlassPanel._test = { slash = slash }
