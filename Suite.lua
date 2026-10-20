-- Suite.lua: Glass UI's suite theme (#96; Glass UI's docs/SUITE.md). Glass UI
-- is optional (## OptionalDeps: GlassUI, so it loads first when it is enabled).
-- Its Suite API 1 is asked ONCE per session, at the top of Glass.lua, before
-- any glass is built: "does the player want this addon to follow the suite's
-- Pearl?" Following is opt-in, on Glass UI's page.
--
-- While following, the glass body (`glass`) and the windows' look
-- (`windowGlass`) are suspended: kept as the player saved them, and not
-- applied (the defaults show: Clear, Reflective) nor changed from /gpanel,
-- the options panel or an import ("set in Glass UI"). Still local: the font
-- and the tint (neutral or class colour).
-- Not following (no Glass UI, an older one, or the switch off): our own look,
-- which is Pearl too since #96.
--
-- Whatever was built is reported to Glass UI (Suite.Report) for its page.
-- Glass UI is never read beyond these calls, and never writes to our tables.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local Suite = {}
GlassPanel.Suite = Suite

Suite.ADDON = "GlassPanel"

local api                  -- GlassUI.Suite, when it speaks API 1
local following = false
local decided = false
local built, failure, minor
local listen             -- the accent listener (below)

-- Glass UI's suite API, when it speaks version 1 exactly (anything else
-- counts as absent: the released Glass UI has no `Suite` at all).
local function suiteAPI()
    local G = rawget(_G, "GlassUI")
    if type(G) ~= "table" then return nil end
    local S = rawget(G, "Suite")
    if type(S) ~= "table" or rawget(S, "API") ~= 1 then return nil end
    if type(rawget(S, "Theme")) ~= "function" or type(rawget(S, "Report")) ~= "function" then return nil end
    return S
end

-- Once per session. True when the suite's Pearl is to be followed.
function Suite.Decide()
    if decided then return following end
    decided = true
    api = suiteAPI()
    if api then
        local ok, answer = pcall(api.Theme, Suite.ADDON)
        if ok and type(answer) == "table" and answer.preset == "pearl" then following = true end
    end
    if following then listen() end
    return following
end

function Suite.Following() return following end

-- Glass.lua says what it built: `preset` ("pearl" or nil for the older
-- look), `why` when Pearl couldn't be built ("library-too-old"|"build-failed"),
-- and the library's MINOR.
function Suite.Built(preset, why, libMinor)
    built, failure, minor = preset, why, libMinor
    Suite.Report()
end

-- What we built and show, for Glass UI's page (plain values only).
function Suite.Report()
    if not api or not decided then return end
    local state = {
        api = 1,
        built = following and failure == nil and built or nil,
        reason = following and failure or nil,
        minor = minor,
        options = function()
            if GlassPanel.Options and GlassPanel.Options.Open then GlassPanel.Options.Open() end
        end,
    }
    local ok, err = pcall(api.Report, Suite.ADDON, state)
    if not ok then API.Fail("suite:report", err) end
end

-- Glass UI's own page, for the "set in Glass UI" button. `Open` was added
-- within API 1: feature-detected, called under pcall.
function Suite.CanOpen()
    return api ~= nil and type(rawget(api, "Open")) == "function"
end
function Suite.Open()
    if not Suite.CanOpen() then return false end
    local ok, opened = pcall(api.Open)
    return ok and opened == true
end

-- The suite's accent (#106): the colour of the stock UI's gold text (bar
-- captions, window titles) follows Glass UI's accent while we follow the suite.
-- `Suite.Accent` was added within API 1: feature-detected, called under pcall
-- with no name (the current accent), its answer checked (three plain numbers
-- 0-1). Anything else, or not following: Blizzard's gold.
local GOLD = { 1, 0.82, 0 }
local accented = {}        -- the fontstrings wearing it

function Suite.AccentColor()
    if following and api and type(rawget(api, "Accent")) == "function" then
        local ok, c = pcall(api.Accent)
        if ok and type(c) == "table" then
            local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
            if API.Plain(r) and API.Plain(g) and API.Plain(b)
               and type(r) == "number" and type(g) == "number" and type(b) == "number"
               and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 then
                return r, g, b
            end
        end
    end
    return GOLD[1], GOLD[2], GOLD[3]
end

local function paintAccented()
    local r, g, b = Suite.AccentColor()
    for _, fs in ipairs(accented) do fs:SetTextColor(r, g, b) end
end

-- Dress a fontstring in the accent now and whenever Glass UI changes it.
function Suite.Accented(fs)
    accented[#accented + 1] = fs
    fs:SetTextColor(Suite.AccentColor())
end

-- Live: Glass UI fires LookChanged (an EventRegistry event) on every look
-- change, in combat too. Registered once, when we follow.
function listen()
    local E = rawget(_G, "EventRegistry")
    if not (following and type(E) == "table" and E.RegisterCallback) then return end
    local ok, err = pcall(E.RegisterCallback, E, "GlassUI.Suite.LookChanged", paintAccented, Suite)
    if not ok then API.Fail("suite:accent", err) end
end

Suite._test = { suiteAPI = suiteAPI, paint = paintAccented, built = function() return built, failure, minor end }
