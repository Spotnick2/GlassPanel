-- API.ItemLoader (#74): the one loader for item data that arrives late,
-- shared by GearScore, Reagents and Ammo. Their own tests cover how each
-- uses it; this is the helper's contract.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon({ plugins = false })
local API = GlassPanel.API

local answers = {}
local L = API.ItemLoader("Test", function(id, success) answers[#answers + 1] = { id = id, success = success } end)
eq(L.Listening(), false, "idle: the item-load events aren't listened to")

-- An item the client has cached: nothing to ask.
WoW.bagItems[5001] = { cached = true }
L.Request(5001)
eq(WoW.itemRequests[5001], nil, "cached: not requested")
eq(L.State(5001), nil, "cached: never asked")

-- Not cached: asked once, and listened for while pending.
L.Request(5002)
L.Request(5002)
eq(WoW.itemRequests[5002], 1, "not cached: requested once")
eq(L.State(5002), "pending", "pending")
eq(L.Listening(), true, "pending: listening")

-- The events fire for every item the client loads: another's is ignored.
WoW.fire("ITEM_DATA_LOAD_RESULT", 9999, true)
eq(#answers, 0, "another item's answer: ignored")
eq(L.Listening(), true, "still pending: still listening")

-- Ours: answered, the callback runs, and the listening stops.
WoW.fire("ITEM_DATA_LOAD_RESULT", 5002, true)
eq(#answers, 1, "our answer: the callback runs")
eq(answers[1].id, 5002, "with the id")
eq(answers[1].success, true, "and the result")
eq(L.State(5002), "loaded", "loaded")
eq(L.Listening(), false, "nothing pending: stops listening")

-- Answered is final, even if the data is still missing: the request loop
-- one of the copies had (request, load, repaint, request).
L.Request(5002)
eq(WoW.itemRequests[5002], 1, "answered: never asked again")

-- A failed load, from the other event.
L.Request(5003)
WoW.fire("GET_ITEM_INFO_RECEIVED", 5003, false)
eq(L.State(5003), "failed", "a failed load is recorded")
eq(answers[2].success, false, "and passed on")
L.Request(5003)
eq(WoW.itemRequests[5003], 1, "a failed load isn't asked again either")

-- An unreadable result reaches the callback as nil, not as a failure.
L.Request(5007)
WoW.fire("ITEM_DATA_LOAD_RESULT", 5007, WoW.Secret("success"))
eq(L.State(5007), "loaded", "an unreadable result isn't a failure")
eq(answers[3].success, nil, "and reads nil")

-- evenIfCached: data missing although the client says it's cached (GearScore).
WoW.bagItems[5004] = { cached = true }
L.Request(5004, true)
eq(WoW.itemRequests[5004], 1, "evenIfCached: asked anyway")
eq(L.State(5004), "pending", "pending")

-- Reset forgets every id; an answer to one asked before is then ignored.
L.Reset()
eq(L.Listening(), false, "reset: stops listening")
eq(L.State(5003), nil, "reset: the failure is forgotten")
L.Request(5005)
local before = #answers
WoW.fire("ITEM_DATA_LOAD_RESULT", 5004, true)
eq(#answers, before, "reset: a late answer to an earlier id is ignored")
eq(L.State(5004), nil, "and it isn't recorded")
L.Request(5003)
eq(WoW.itemRequests[5003], 2, "reset: a forgotten id may be asked again")

-- A secret id is no id.
WoW.fire("ITEM_DATA_LOAD_RESULT", WoW.Secret("item id"), true)
eq(#answers, before, "a secret id: ignored")

-- Each loader has its own ids, and a callback that throws is recorded under
-- its owner without stopping the loader.
local B = API.ItemLoader("Boom", function() error("boom") end)
B.Request(5006)
eq(L.State(5006), nil, "another loader's request isn't ours")
WoW.fire("ITEM_DATA_LOAD_RESULT", 5006, true)
check(GlassPanel.failures["Boom:itemload"], "a throwing callback is recorded as <owner>:itemload")
eq(B.State(5006), "loaded", "and the answer still counts")
eq(B.Listening(), false, "nothing left pending: stops listening")

GlassPanel.failures["Boom:itemload"] = nil
check(next(GlassPanel.failures) == nil, "no other failures")
done("test_itemloader")
