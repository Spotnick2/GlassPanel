-- Currencies stubs (Plugins/Currencies, #47). WoW.currencies[id] = { name,
-- quantity, max, icon, weekly, weeklyMax } is what the client knows;
-- WoW.currencyTab = { { header = name } | id, ... } is the currency tab as
-- listed (collapsed headers hide rows). A field set to "secret" comes back
-- secret. C_CurrencyInfo itself (GetCoinTextureString) is in wow_stubs.lua.
table.insert(WoW.resetHooks, function()
    WoW.currencies = {}
    WoW.currencyTab = {}
end)

local function sv(v, label) if v == "secret" then return WoW.Secret(label) end return v end

function C_CurrencyInfo.GetCurrencyInfo(id)
    local c = WoW.currencies[id]
    if not c then return nil end
    return { name = c.name, currencyID = id, quantity = sv(c.quantity or 0, "quantity"), maxQuantity = c.max or 0,
             iconFileID = c.icon or 134400, quantityEarnedThisWeek = c.weekly or 0,
             maxWeeklyQuantity = c.weeklyMax or 0, discovered = true }
end
function C_CurrencyInfo.GetCurrencyListSize() return #WoW.currencyTab end
-- The dump's CurrencyInfo: each row has its currencyID.
function C_CurrencyInfo.GetCurrencyListInfo(i)
    local e = WoW.currencyTab[i]
    if type(e) == "table" then return { name = e.header, isHeader = true, currencyID = 0, quantity = 0 } end
    local c = WoW.currencies[e]
    return c and { name = c.name, isHeader = false, currencyID = e, quantity = sv(c.quantity or 0, "quantity") } or nil
end
