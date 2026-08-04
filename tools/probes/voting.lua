-- Ballots against the real API rather than the spec's mocks: does a cycle length
-- actually come off the surface, does a standing ballot open itself, and does a
-- closed ballot really move Nauvis's research queue and expansion target?
local voting = require("scripts.voting")
local nauvis = require("scripts.nauvis")
local research = require("scripts.research")
local nauvis_expansion = require("scripts.nauvis_expansion")
local stock = require("scripts.stock")

local M = {}

local function describe(kind)
    local ballot = voting.active(kind)
    if not ballot then return "closed" end
    return string.format("open, %d options, %d ticks left",
        #ballot.options, ballot.end_tick - game.tick)
end

-- Called from on_init, so no tick-0 guard here -- there is nothing to measure in
-- the world, only ballot state to drive.
function M.run()
    log("PROBE ticks_per_day: " .. voting.duration())

    -- No LuaPlayer exists headless, but weight is read straight out of storage,
    -- so a synthetic bondholder is enough to drive a ballot to a real result.
    -- The real warehouse is empty at on_init, so stock it to see the anchor move.
    storage.nauvis.minted = 100000
    storage.players[1] = { personal_credits = 60000 }
    nauvis.ensure_bonds(1)
    log("PROBE world value, empty warehouse: " .. nauvis.total_value())
    stock.set("iron-plate", 2000)
    stock.set("copper-plate", 1000)
    log("PROBE world value, stocked warehouse: " .. nauvis.total_value())

    -- The curve the whole redesign is about: each bond dearer than the last, even
    -- though buying burns the value it is priced off.
    for _ = 1, 6 do
        local held = nauvis.get_bonds(1)
        local price = nauvis.bond_price(1)
        local ok = nauvis.buy_bond(1)
        log(string.format("PROBE holding %d -> next bond %d (bought: %s, value now %d)",
            held, price, tostring(ok), nauvis.total_value()))
    end

    nauvis.add_bonds(1, 2)
    log("PROBE total bonds: " .. nauvis.total_bonds())

    voting.open("expansion")
    log("PROBE expansion ballot: " .. describe("expansion"))
    local ballot = voting.active("expansion")
    local choice = ballot.options[2].key
    local ok, err = voting.cast(1, "expansion", choice)
    log("PROBE cast " .. tostring(choice) .. ": " .. tostring(ok) .. " " .. tostring(err))
    log("PROBE decided early: " .. tostring(voting.decided_early("expansion")))
    voting.close("expansion")
    log("PROBE expansion target after close: " .. tostring(nauvis_expansion.target()))

    voting.open("research")
    local research_ballot = voting.active("research")
    if research_ballot then
        local tech = research_ballot.options[1].key
        voting.cast(1, "research", tech)
        voting.close("research")
        log("PROBE research wanted: " .. tostring(tech))
        log("PROBE research current: " .. tostring(research.current_research_name()))
        log("PROBE research queued: " .. tostring(research.get_next_research()))
    else
        log("PROBE research ballot: nothing on the frontier")
    end

    -- Both slots are full now, so the standing rule must leave them alone.
    voting.process()
    log("PROBE after process, expansion: " .. describe("expansion"))
    log("PROBE after process, research: " .. describe("research"))
end

return M
