-- [Broker] (#179): what LibDataBroker-1.1 and CallbackHandler-1.0 need from
-- the client, and the AddOns list.
--
-- securecallfunction (in the 71037 dump): CallbackHandler dispatches every
-- callback through it. Like the client's, an error in the callee goes to the
-- error handler and the dispatch goes on; here it lands in WoW.secureErrors.
-- C_AddOns.IsAddOnLoaded(name) -> loadedOrLoading, loaded (the dump's
-- signature): true for the core and each plugin loadAddon loaded
-- (WoW.loadedAddons, kept by the harness), and anything in WoW.loadedAddons.
table.insert(WoW.resetHooks, function()
    WoW.secureErrors = {}
end)

function securecallfunction(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then WoW.secureErrors[#WoW.secureErrors + 1] = tostring(err) end
end

C_AddOns.IsAddOnLoaded = function(name)
    local loaded = (WoW.loadedAddons or {})[name] == true
    return loaded, loaded
end
