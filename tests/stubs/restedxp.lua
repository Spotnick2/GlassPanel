-- RestedXP Guides (Plugins/RestedXP), not a client API: another addon,
-- modelled on RXPGuides v4.11.23 as RXPProbe measured it on 70374
-- (docs/FOREVER-PROBE.md). Nothing exists until a test calls
-- WoW.installRXP() inside loadAddon's `before` (LibStub is new each session):
-- it marks RXPGuides installed (WoW.installed, so the plugin loads), makes the
-- RXP table and registers the libraries RestedXP embeds in LibStub.
--   WoW.rxp.player = { x, y, instance } (x "secret": a secret position)
--   WoW.facing (radians; "secret": a secret)
--   WoW.rxpToggles: the launcher's left-clicks; WoW.rxpSend(msg, ...) sends a message.

table.insert(WoW.resetHooks, function()
    WoW.facing = 0
    WoW.rxp = nil
    WoW.rxpToggles = 0
    WoW.rxpHandlers = {}
end)

-- 70338 dump: GetPlayerFacing() -> optional result:number.
function GetPlayerFacing()
    if WoW.facing == "secret" then return WoW.Secret("facing") end
    return WoW.facing
end

-- HereBeDragons-2.0's own maths (RXPGuides/libs/HereBeDragons:591-641),
-- including its blind spot: the instance is ignored.
local function worldVector(_, instanceID, oX, oY, dX, dY)
    if not (oX and oY and dX and dY) then return nil, nil end
    local dx, dy = dX - oX, dY - oY
    local angle = math.atan2(-dx, dy)
    if angle > 0 then angle = 2 * math.pi - angle else angle = -angle end
    return angle, math.sqrt(dx * dx + dy * dy)
end

function WoW.installRXP(opts)
    opts = opts or {}
    WoW.installed.RXPGuides = true
    WoW.rxpToggles = 0
    WoW.rxp = { player = { x = 0, y = 0, instance = 1 } }
    local hbd = LibStub:NewLibrary("HereBeDragons-2.0", 1)
    hbd.GetPlayerWorldPosition = function()
        local p = WoW.rxp.player
        if p.x == "secret" then return WoW.Secret("x"), WoW.Secret("y"), p.instance end
        return p.x, p.y, p.instance
    end
    hbd.GetWorldVector = worldVector
    if not opts.noLauncher then
        local ldb = LibStub:NewLibrary("LibDataBroker-1.1", 1)
        ldb.GetDataObjectByName = function(_, name)
            if name ~= "RXPGuides" then return nil end
            return { type = "data source", OnClick = function(_, button)
                if button == "LeftButton" then RXP.settings.ToggleActive() end
            end }
        end
    end
    local ae = LibStub:NewLibrary("AceEvent-3.0", 1)
    ae.Embed = function(_, t)
        function t:RegisterMessage(name, fn) WoW.rxpHandlers[name] = fn end
    end
    if opts.noTable then return end
    local arrow = CreateFrame("Frame", "RXPG_ARROW", UIParent)
    arrow.element = { wx = 30, wy = 40, instance = 1, step = { index = 14, active = true } }
    local steps = {}
    for i = 1, 196 do steps[i] = {} end
    rawset(_G, "RXP", {
        game = "FOREVER",
        currentGuide = { name = "12-17 The Barrens", steps = steps },
        arrowFrame = arrow,
        settings = {
            profile = { showEnabled = true },
            ToggleActive = function()
                WoW.rxpToggles = WoW.rxpToggles + 1
                local p = RXP.settings.profile
                p.showEnabled = not p.showEnabled
                -- Its arrow is in the toggle only while drawn (IsFeatureEnabled, map.lua:61-64).
                if not p.disableArrow then arrow:SetShown(p.showEnabled) end
            end,
        },
    })
end

function WoW.rxpSend(msg, ...)
    local fn = WoW.rxpHandlers[msg]
    if fn then fn(msg, ...) end
end

-- Uninstalled again: the next loadAddon has no RestedXP.
function WoW.removeRXP()
    WoW.installed.RXPGuides = nil
    rawset(_G, "RXP", nil)
    rawset(_G, "RXPG_ARROW", nil)
end
