# Nauvis governance: bonds and ballots

How the state decides things. Implemented in `scripts/voting.lua`, with the polling
station in the Nauvis tab of `scripts/company_gui.lua`.

---

## Bonds

A **bond** is one vote in every Nauvis ballot. It is the state's counterpart to a company
share: shares govern a company, bonds govern Nauvis, and neither substitutes for the
other. A player holding no shares in any company still votes.

- Every player is issued **one** bond when they are created (`nauvis.ensure_bonds`).
  A save written before bonds gives its existing players theirs on load.
- Buying **burns** the price, consistent with every other player→Nauvis payment.
- Bonds are never sold back and never expire. Governance weight only accumulates.

### Pricing

```
price = BOND_RATE × total_value() × bonds_you_already_hold      -- 3 %, floored at 100

total_value() = nauvis.net()                                    -- every credit in existence
              + Σ warehouse stock × utils.get_base_price(item)
              ( + company book value, when valuation.lua lands )
```

Two deliberate choices, each fixing a specific failure:

**The anchor is total value, not the money supply.** Pricing off credits alone meant the
purchase shrank its own price base — burning 10 % of the supply made the next bond 10 %
cheaper, so a player could walk down a geometric curve and convert their whole balance
into an unbounded number of votes. Counting the warehouse widens the anchor enormously
(in a stocked mid-game world it is the larger half), so a burn barely moves it. It also
gives the trading loop a real tension: supplying Nauvis makes governance dearer for
everyone, including you.

`get_base_price`, not `get_price`, because market price moves with scarcity and demand —
anchoring governance to it would let someone corner a thin item to crash the bond price
and buy influence cheaply. Same mitigation `doc/company_ownership.md` §7 reaches for
against valuation gaming.

**The price is progressive.** Multiplying by the buyer's existing holding makes the
cumulative cost of *h* bonds roughly `RATE × value × h²/2` — quadratic, so doubling your
influence costs four times as much. This is the standard quadratic-voting lever, and it
also finishes off the walk-down: the multiplier climbs faster than the burn shrinks the
anchor, so every bond is dearer than the last. Measured in a world worth ₾400 000:

| Bonds held | Next bond |
| --- | --- |
| 1 | ₾12 000 |
| 2 | ₾23 280 |
| 3 | ₾32 825 |

A player with ₾60 000 gets two more bonds and then simply cannot afford a third. The
trade against a flat rate: the *first* extra bond is cheaper, so more players can afford a
second vote, while the tenth is effectively unbuyable.

The intended feel is that governance follows money without being purchasable outright:
a rich player can buy influence, but the price is set by the whole economy and rises
against them personally, so the richer everyone is, the more it costs to out-vote them.

## Ballots

One ballot per **kind** at a time, keyed in `storage.voting.ballots`:

| Kind | What it decides | Opened by |
| --- | --- | --- |
| `mayor` | Who holds the mayor's office | Any bondholder, from the Nauvis tab |
| `research` | What Nauvis researches next | Itself, whenever nothing is queued |
| `expansion` | What Nauvis builds next | Itself, whenever nothing is under construction |

Rules, all of them deliberate:

- **One day/night cycle** long — `surface.ticks_per_day`, so a changed cycle carries
  through. Announced in chat when it opens, and again one minute before it closes.
- **First past the post, simple plurality.** No runoffs, no thresholds.
- **Ties are drawn at random** from the tied options, with `math.random` — Factorio's RNG
  is deterministic across clients, so this is desync-safe. A ballot nobody voted in is the
  all-zero tie, so "no votes means a random pick" falls out of the same code path.
- **It ends early the moment the result is fixed**: either every issued bond has voted, or
  the leader's margin exceeds the bonds still outstanding. A ballot with *no* votes yet is
  never counted as decided — otherwise a world whose players have not joined has zero
  eligible bonds and every ballot resolves at random on tick one.
- **Options are frozen when the ballot opens.** The GUI writes its dropdown once, so the
  periodic refresh can never move a selection out from under someone mid-click. The
  research ballot is capped at the eight cheapest technologies on the frontier: a ballot
  thirty entries long is a list, not a choice.

### Standing ballots

Research and expansion are standing business. Rather than three call sites remembering to
open a ballot (game start, technology finished, expansion built), `ensure_standing()` runs
once a second and opens one whenever the corresponding slot is empty — Nauvis has no
research current and none queued, or no expansion target. `nauvis_expansion.build`
clearing `target` and `research.set_next_research` setting `next` are what make that work;
they are the busy flags.

---

## Open questions

- **The mayor has no powers.** The office is elected and displayed; nothing reads
  `storage.nauvis.mayor`. `doc/design-thinking.md` wants the mayor to place expansions by
  hand instead of the district packer choosing — that is the obvious first power, and it
  is the reason the role exists at all.
- **Bond concentration is slowed, not solved.** Quadratic pricing makes a majority
  expensive rather than impossible, and nothing caps a holding or dilutes one — a player
  who keeps buying through a long, profitable game still gets there eventually. `BOND_RATE`
  is the first knob; bonds decaying, or a per-player cap, are the blunt instruments if it
  bites in play.
- **A rising anchor does not re-price bonds already held.** Someone who bought while the
  world was poor keeps their votes for free as it gets rich, so buying *early* is
  strictly better than buying late. That is arguably correct — it rewards the players who
  built the economy — but it is a first-mover advantage nobody chose.
- **Absent players still count.** Eligible weight is every issued bond, including bonds
  held by players who are not logged in, so a ballot in a mostly-empty server rarely ends
  early and usually runs the full cycle. Counting only connected players would end votes
  faster but would let a result flip when someone logs in mid-ballot.
- **A vote per kind, not per question.** Two expansion ballots cannot run at once, which
  is right, but it also means calling a mayoral election while one is running is refused
  rather than queued.
