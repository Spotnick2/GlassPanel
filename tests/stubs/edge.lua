-- EventRegistry stub (Edge.lua, #97): WoW.callbacks[event] = { { fn, owner } }.
-- WoW.triggered records every event an addon fired itself ({ event, ... }), then
-- runs the callbacks as TriggerEvent does, owner first.
table.insert(WoW.resetHooks, function()
    WoW.callbacks = {}
    WoW.triggered = {}
end)

EventRegistry = {}
function EventRegistry:RegisterCallback(event, fn, owner)
    WoW.callbacks[event] = WoW.callbacks[event] or {}
    table.insert(WoW.callbacks[event], { fn, owner })
end
function EventRegistry:TriggerEvent(event, ...)
    table.insert(WoW.triggered, { event, ... })
    for _, c in ipairs(WoW.callbacks[event] or {}) do c[1](c[2], ...) end
end
