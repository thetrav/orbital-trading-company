# Company ownership, shares, valuation and the Nauvis state

Plan for growing `scripts/company_gui.lua` from a create/join dialog into the full
company-management terminal, and for moving the economy from "credits per force" to
"credits per player **and** per force, linked by shares", with Nauvis as the issuing
state.

Target entity stays `otc-company-monitor` (`prototypes/company_monitor.lua`), opened via
`on_gui_opened` in `control.lua:271`.

---

## 1. Model

### Two player-facing ledgers

| Ledger | Where | Who spends it |
| --- | --- | --- |
| Personal credits | `storage.players[index].personal_credits` | Buying shares (which is how you found or join a company) |
| Company credits | `storage.companies[name].credits` (exists today) | Buy chests, expansions, dividends |

Nothing in the buy/sell/expansion path changes: those keep using company credits.
Personal credits only move through the company monitor.

### Nauvis is the state, not a company

`storage.companies["Nauvis"]` already exists (`control.lua:87`) as a zero-credit stub.
It becomes the issuing authority, and is **never joinable** — it is filtered out of every
company list and cannot be applied to, bought into, or put into receivership.

Nauvis does not have a balance that constrains it. Money is created when players sell to
it and destroyed when they buy from it:

| Player action | Money supply |
| --- | --- |
| Sell chest pays out | **minted** — credits appear from nothing |
| Buy chest charges | **burned** |
| Expansion purchase | **burned** |
| Nauvis buys a departing player's shares | **minted** |
| Player buys shares back from Nauvis | **burned** |
| Future fees | **burned** |

So `companies["Nauvis"].credits` stops being a spendable balance and becomes a signed
money-supply counter (`minted - burned`), useful as a diagnostic and as the input to
future bond pricing. It is allowed to go negative and nothing checks it before spending.
Every mint/burn goes through one helper — `nauvis.mint(amount, reason)` /
`nauvis.burn(amount, reason)` — so the accounting stays in one place.

Tax is explicitly out of scope. The sinks are buy-chest purchases and expansions.

### Bonds (implemented — see `doc/nauvis_voting.md`)

Players convert personal credits into Nauvis **bonds**, which behave like shares in the
state and carry voting weight over Nauvis decisions. Every player is issued one on
creation; more are priced at a percentage of `nauvis.total_value()` multiplied by the
bonds the buyer already holds, and buying burns the price.
`storage.nauvis.bonds[player_index]` is the holding, and `scripts/voting.lua` is the only
thing that reads it as weight.

Note for §3: `nauvis.total_value()` is the first thing in the codebase that wants a
whole-world valuation, and it currently approximates one as money supply plus the
warehouse. When `valuation.lua` lands, company book value belongs in that sum — bond
pricing and company valuation should not end up with two different ideas of what the
world is worth.

### Shares, and one company at a time

**A player may hold shares in exactly one company.** Shareholding *is* membership:
holding shares in company X sets `player.force = X`, which is what drives permissions.
There is no such thing as an outside investor, and no separate members table — the cap
table is the roster.

- Par value `SHARE_PAR = 100` credits. Founding with 5 000 credits issues 50 shares.
- New issues are priced at **current share value** (§3), not par, so existing holders are
  diluted in percentage but not in value.
- `role` is tracked alongside the holding: the founder is `manager`, and managers promote
  holders, authorise issues and declare dividends.

Joining is **instant** for now: a player with the credits buys in and is a holder on the
same tick, with no approval step. The intended end state is a shareholder **vote** on
admissions, so the join path is written as a single `resolve_application()` seam that
today returns "approved" immediately — see §8.

This constraint is what makes the force mapping sound: one holding → one force → one
permission set, with no ambiguity about which force a player belongs to.

### Leaving means divesting

Because holding shares sets your force, leaving a company necessarily means giving up the
holding. The exit counterparty is **Nauvis, not the company** — a company should never be
drained of cash by someone quitting.

The end state is an **auction**: a departing holder's block goes to market, Nauvis sets a
floor and is the buyer of last resort. For now the auction is skipped and the floor is
taken immediately, so leaving is instant and always succeeds:

1. Player clicks `Leave`. Their shares are sold to Nauvis at the floor,
   `per_share × LEAVE_FLOOR` (start at 0.9), paid into personal credits as newly minted
   money. Nauvis mints whatever is needed — the sale can never fail for lack of a buyer.
2. Nauvis records the block in `storage.nauvis.holdings[company]` — it market-makes, it
   does not vote or manage.
3. Player's force reverts to `Nauvis`, `player_data.company = nil`, and they may now found
   or join elsewhere.

The price comes from a single `settlement_price()` seam so the auction can later sit in
front of it without touching the transfer logic — see §8.

Nauvis-held blocks are offered in the Companies tab, so joining a company can mean buying
an existing block rather than a fresh issue. This gives the join flow a supply of shares
even when a company has no treasury stock, and it means the floor discount is the only
value lost on a quit.

If the last holder leaves, the company enters `receivership = true` (Phase 7): Nauvis now
holds 100 %, assets are frozen, and the company is listed for takeover at a discount on
valuation. Buying it out transfers Nauvis's block to the buyer, who becomes manager.

---

## 2. Storage schema

Additions to what AGENTS.md documents.

```lua
storage.players[index] = {
    -- existing fields …
    personal_credits = 0,           -- new
    company_gui_tab  = "companies", -- new, per-player UI state
    company_gui_selection = nil,    -- selected company name in the list tab
}

storage.companies[name] = {
    credits       = 0,              -- existing
    founded_tick  = 0,
    holders       = {               -- cap table AND roster; one entry per player
        [player_index] = { shares = 50, role = "manager", joined_tick = 0 },
    },
    treasury_shares = 0,            -- issued but unsold, held by the company
    shares_issued = 50,             -- denormalised total, maintained in one helper
    pending       = {},             -- reserved for the admissions vote; unused today
    auctions      = {},             -- reserved for share auctions; unused today
    receivership  = false,
    valuation     = {               -- cache, recomputed on a slow tick
        tick = 0, cash = 0, assets = 0, inventory = 0,
        earnings = 0, total = 0, per_share = 0,
    },
    ledger        = {},             -- ring buffer of {tick, kind, amount, player_index}
}

storage.nauvis = {                  -- new top-level table
    minted   = 0,
    burned   = 0,
    holdings = { [company_name] = shares },  -- blocks bought back from leavers
    bonds    = {},                  -- reserved, unused until the bond feature lands
}

storage.company_assets[name] = {    -- new top-level table
    rooms = { [shape_name] = count },
    book_value = 0,                 -- sum of purchase costs, see §3
}
```

`companies["Nauvis"]` keeps only `credits` (the signed money-supply figure) and is skipped
by every company iteration except the Nauvis tab. Guard that with one predicate —
`company.is_state(name)` — rather than repeating the name comparisons that currently
appear in `company_gui.lua:105` and `control.lua`.

`ledger` kinds: `found`, `issue`, `join`, `buy_shares`, `sell_shares`, `dividend`, `leave`,
`receivership`. 60-entry ring buffer, same pattern as `scripts/trading_history.lua`.

### Migration

Extend `ensure_company_setup()` in `control.lua:82`:

1. Default `pd.personal_credits = 0` for every player row.
2. Create `storage.nauvis` seeded from the existing `companies["Nauvis"].credits`.
3. For every non-state company without `holders`: build the cap table from the players
   whose `pd.company` matches, mark the lowest player index `manager`, and issue
   `credits / SHARE_PAR` shares split evenly, so legacy saves get a sane cap table.
4. Default `company_assets[name] = { rooms = {}, book_value = company.credits }` —
   existing rooms are unrecoverable, so seed from cash and let it drift correct.
5. Recompute `shares_issued` from `holders` + `treasury_shares` on every load, so a
   desync self-heals.
6. Assert the one-company invariant: if a legacy player somehow maps to a force with no
   holding, give them a holding; the invariant must hold before any GUI reads it.

---

## 3. Valuation

New module `scripts/valuation.lua`, recomputed on `on_nth_tick(600)` (10 s) per company
and cached in `company.valuation`. Nauvis is not valued.

```
total     = cash + assets + inventory + earnings_multiple
per_share = total / max(shares_issued, 1)
```

- **cash** — `company.credits`.
- **assets** — `company_assets[name].book_value`, incremented by the expansion cost in
  `expand_gui.lua:336` when a room is bought. No depreciation for now; add per-room decay
  later if rooms become a value-farm.
- **inventory** — sum over the company's buy/sell chests and station surfaces of
  `utils.get_price(item) * count` at the sell multiplier (0.99), the realisable price.
  Iterating every chest every 10 s is fine at current scale; if it isn't, cache per-chest
  and refresh on the existing per-tick chest pass.
- **earnings_multiple** — profit rate × `EARNINGS_MULTIPLE` (start at 60). Profit rate
  comes from data `scripts/trading_history.lua` already keeps: `sold - bought` summed over
  the 60-entry ring buffer, divided by its span in seconds. Negative earnings reduce
  valuation, which is intended.

`per_share` prices new issues, Nauvis buybacks and takeovers, floored at `SHARE_PAR / 10`
so a bankrupt company cannot issue unlimited shares for nothing.

---

## 4. UI

`company_gui.lua` becomes a three-tab `tabbed-pane`, still named `otc_company_frame`,
still opened by the monitor. Three tabs, always present — no tab appears or disappears
based on state, only its contents change, so the layout stays predictable.

### Tab 1: Companies

The list/browse view, and the only place a player without a holding can act.

- `Found a company`: name field + capital field (min `FOUNDING_MIN = 5000` personal
  credits). Existing validation in `handle_create` — reserved names, collisions, trim —
  carries over, plus a check that the player holds no shares anywhere.
- One row per company: name, holder count, valuation, `per_share`, and an action:
  - `Join` — buys at `per_share` from treasury stock or from a Nauvis-held block, and
    admits instantly. Routed through `resolve_application()` so an admissions vote can be
    inserted without changing the button.
  - `Take over` — receivership entries only.
- Nauvis is not listed.
- For a player who already holds shares, every action is disabled with the tooltip
  explaining the one-company rule; the list stays visible so players can watch rivals.

### Tab 2: Company

Management of the company you hold shares in. Shows an explanatory placeholder when you
hold none.

- Header: name, founded date, holder count, receivership badge.
- Valuation breakdown: Cash / Assets / Inventory / Earnings / **Total**, plus `per_share`
  and the value of your own holding.
- Your position: shares, % of company, personal credits.
- Cap table: `name — role — shares — %`, ordered by holding, including any Nauvis-held
  block shown as a distinct non-voting row. Manager-only `Promote` / `Remove`.
- Actions: `Issue N shares` at `per_share` into treasury (manager), `Buy` from treasury,
  `Declare dividend` (manager), `Leave company`. `Leave` states the settlement price in
  its confirmation so the number is never a surprise.
- Recent ledger entries.

No approvals or auction UI is built. When voting lands it belongs directly under the cap
table — the tab is laid out with that space free — and auction listings belong beside the
ledger. Neither gets a disabled placeholder: unlike bonds, these replace flows that
already work, so an empty section would just read as broken.

Single-holder companies hide the cap table and promote/remove controls — solo players
should not wade through governance UI.

### Tab 3: Nauvis

- Money supply: minted, burned, net. Framed as state accounting, not a balance.
- Nauvis's share holdings — which companies it is currently market-making, and at what
  size, since those are the blocks available to buy in the Companies tab.
- **Bonds** section, present but disabled, captioned as coming soon: this is where credits
  will convert into bonds and where Nauvis governance votes will appear.

### Credits display

`market_gui.create_credits_gui` gets a second label for personal credits next to the
company balance, and `update_all_forces_credits` refreshes it too. Keep the existing
`otc_credits_label` name and add `otc_personal_credits_label` so nothing else breaks.

### Event wiring

`control.lua` currently matches three literal element names plus
`^otc_company_join_(.+)$` (`control.lua:368-385`). Replace with a single dispatcher:
`company_gui.handle_click` receives the element and pattern-matches
`^otc_company_([%a_]+)_?(.*)$` internally, so new buttons stop needing `control.lua`
edits. Wire `on_gui_selected_tab_changed` to persist `player_data.company_gui_tab`.

---

## 5. Where personal credits come from

1. **Starting grant** — `STARTING_PERSONAL_CREDITS = 10000` minted by Nauvis on first
   `on_player_created`, enough to found one company at the minimum with change.
2. **Dividends** — manager declares `X` per share; company credits move to holders'
   personal accounts. Blocked below a `MIN_RESERVE` so a manager cannot strip a company
   to insolvency in one click. Nauvis-held blocks *do* receive dividends, which burns
   that portion back out of the supply.
3. **Divesting** — leaving sells the holding to Nauvis at the haircut (minted).

Salary is not modelled: dividends plus share appreciation are enough, and a wage would
need a payroll tick.

---

## 6. Phasing

Each phase ends with `./validate.sh` green and is independently playable.

1. **Personal ledger + Nauvis accounting** — `personal_credits`, `storage.nauvis`,
   `nauvis.mint`/`burn` routed through buy chest, sell chest and expansion, starting
   grant, second credits label. No behaviour change beyond numbers on screen.
2. **Three-tab skeleton** — tabbed frame, click dispatcher, Companies tab reproducing
   today's create/join exactly, Company tab minimal, Nauvis tab showing money supply.
   Mostly refactor, easy to verify.
3. **Cap table** — `holders`, roles, the one-company invariant enforced, founding spends
   personal credits at `SHARE_PAR`, Company tab read-only. Migration seeds legacy saves.
4. **Join and leave** — instant `Join` through `resolve_application()`, `Leave` selling to
   Nauvis at `settlement_price()`, Nauvis holdings surfaced in both the Companies and
   Nauvis tabs. Both seams commented per §8.
5. **Valuation** — `scripts/valuation.lua`, `company_assets` book value hooked into
   `expand_gui`, breakdown in the Company tab, `per_share` in the list.
6. **Share issues** — treasury stock, new issues at `per_share`, buying from treasury,
   ledger display.
7. **Dividends and receivership** — dividend declaration with reserve check, last-holder
   receivership, takeover flow.

Phases 1–4 are load-bearing; 5–7 are additive and can be reordered or dropped without
stranding earlier work. Bonds sit beyond this plan entirely.

---

## 7. Risks and open questions

- **Valuation gaming.** Inventory valued at market price, in a market whose prices react
  to the player's own trades (`supply_demand.lua`), lets a company inflate its book by
  hoarding a thin item. Mitigation: value inventory at *base* price instead of offset
  price if this shows up in play.
- **The floor is the whole exit tax.** With Nauvis buying at `per_share × 0.9` and no
  auction to clear first, quitting is cheap, instant and always available. If players
  start company-hopping to chase valuations, lower `LEAVE_FLOOR` or add a cooldown before
  the next join rather than blocking the exit — and note the eventual auction naturally
  adds friction here, since a block would have to sit on the market before Nauvis takes
  it.
- **Money supply is unbounded by construction.** That is the intent of the MMT framing,
  but it means the only thing anchoring prices is `supply_demand.lua`'s clamp to ±50 % of
  base. Worth watching whether minting on sells plus minting on buybacks outpaces the
  burn from purchases and expansions; the Nauvis tab's net figure is the instrument for
  noticing.
- **Instant join means no gatekeeping at all.** Until the vote exists, anyone with the
  credits can walk into any company and gain its force permissions. That is a real
  griefing surface in multiplayer; if it bites before voting lands, the cheap stopgap is
  a manager toggle on `resolve_application()` rather than building the vote early.
- **Open — dividend authority:** any manager, or a majority-of-shares vote? Plan assumes
  any manager with `MIN_RESERVE` as the guardrail. This is the third thing wanting a
  vote, which argues for building the voting primitive once and generically.
- **Open — player-to-player share transfers.** Not planned; the treasury and Nauvis are
  the only counterparties. A direct market is a natural follow-on once auctions exist,
  since both need the same order-matching UI.

---

## 8. Extension seams

Three systems are deliberately stubbed. Each gets **one function** that today returns the
trivial answer, so the future version is a change in one place rather than a hunt through
call sites. AGENTS.md says no comments unless asked — these are asked for, and are the
only comments the feature should carry.

### `company.resolve_application(company_name, player_index)` → `"approved"`

Called by the `Join` button before any credits or shares move. Today it approves
unconditionally.

```lua
-- SEAM: admissions vote goes here. Return "pending" and park the request in
-- company.pending; the vote resolves it later and calls company.admit() directly.
-- Callers must already handle a non-"approved" result without moving credits.
```

Write the caller so a `"pending"` return is a clean no-op with a player message — that
way the vote can be dropped in without revisiting the join flow.

### `company.settlement_price(company_name, shares)` → `per_share × LEAVE_FLOOR`

Called by `Leave`, and later by receivership. Today it returns the Nauvis floor directly.

```lua
-- SEAM: share auction goes here. This is the reserve price, not the clearing price --
-- list the block in company.auctions, let players bid above it, and fall back to this
-- value with Nauvis as buyer of last resort when the auction closes unsold.
```

The transfer logic must not assume the buyer is Nauvis: take the buyer as a parameter,
defaulting to Nauvis, so an auction winner slots in unchanged.

### `storage.nauvis.bonds`

No longer a seam — bonds and the ballots they weight are built. See
`doc/nauvis_voting.md`. The three decisions §7 wanted a generic vote for (admissions,
dividend authority, share auctions) are all *company* decisions and still unbuilt;
`scripts/voting.lua` is the primitive to reach for when they land, but its ballots are
weighted by bonds, so a company vote needs a share-weighted variant.
