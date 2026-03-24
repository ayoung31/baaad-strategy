# strategy.R — Implementation Plan

## Purpose

`strategy.R` is Module 3 of the simulation stack. It defines the **strategy
interface** — the set of functions every strategy must implement — and provides
three concrete strategy implementations: `balanced_strategy`,
`sheep_strategy`, and `ore_grain_strategy`.

`game.R` calls into strategies via the interface without knowing which
implementation it is talking to. Each strategy is a plain R named list of
functions, making substitution trivial and keeping strategies fully isolated
from each other.

---

## Strategy Interface

Every strategy is a named list with exactly these four function slots:

```r
list(
  choose_initial_placement = function(board, player, taken_ids) { ... },
  choose_second_placement  = function(board, player, taken_ids) { ... },
  choose_road_placement    = function(board, player, game_state) { ... },
  choose_action            = function(board, player, game_state) { ... }
)
```

### Function signatures

#### `choose_initial_placement(board, player, taken_ids)`

Called during the **first** pass of the reverse snake draft (placements 1..N).
Returns a single intersection ID for the settlement. `taken_ids` is an integer
vector of all intersection IDs already claimed by any player, allowing the
strategy to avoid them and respect the distance rule.

> **Decision 1 — Distance rule enforcement location.**
> Should `strategy.R` filter to only valid spots before scoring, or should
> `game.R` validate the returned ID and error if illegal?
>
> **Recommendation:** Strategies filter using `is_valid_settlement_spot()` from
> `board.R` so they only score legal candidates. `game.R` adds a hard stop as
> a safety net. This keeps strategies self-consistent and avoids silent illegal
> placements.

#### `choose_second_placement(board, player, taken_ids)`

Called during the **second** pass of the reverse snake draft (placements N..1).
Same signature as `choose_initial_placement`. Separated from the first
placement because the second placement also determines starting resources and
some strategies (especially `sheep_strategy`) may weight the second pick
differently — e.g. targeting the 2:1 Wool port on the second pass once the
first pass secured production.

> **Decision 2 — One function or two for initial placement?**
>
> The original plan specifies one `choose_initial_placement` function for both
> picks. Separating them adds one slot to the interface but enables strategies
> to behave differently on each pick (the second pick is a known information
> state: you can see where everyone else placed on pass 1). This is especially
> important for `sheep_strategy` whose defining behaviour — securing the Wool
> port — is most naturally expressed as a second-placement goal.
>
> **Recommendation:** Use two separate functions. If a strategy does not need
> different logic, `choose_second_placement` can simply delegate to
> `choose_initial_placement`.

#### `choose_road_placement(board, player, game_state)`

Called whenever the player places a road — both during initial setup (one road
per settlement) and during the build phase of a normal turn. Returns a single
edge ID. `game_state` is the full game state list from `game.R`, providing
access to all players' locations and the current turn count.

> **Decision 3 — What does `game_state` contain?**
>
> Strategies need opponent information to make meaningful decisions (e.g.
> blocking, targeting the robber, racing for Longest Road). Suggested fields:
>
> ```r
> game_state <- list(
>   players     = list(...),   # all player objects (read-only for strategy)
>   turn        = <int>,       # current turn number
>   active_id   = <int>,       # which player is acting
>   deck_size   = <int>        # remaining dev cards in deck
> )
> ```
>
> **Recommendation:** Include all four fields above. Strategies should treat
> `game_state$players` as read-only; mutations happen only in `game.R`.

#### `choose_action(board, player, game_state)`

The main decision function, called repeatedly during a player's turn until the
strategy returns a sentinel indicating it is done. Returns an **action list**.

> **Decision 4 — Action return format.**
> Two design options:
>
> **Option A — Action list with a type tag:**
> ```r
> list(type = "build_settlement", intersection_id = 24L)
> list(type = "build_city",       intersection_id = 10L)
> list(type = "build_road",       edge_id = 7L)
> list(type = "buy_dev_card")
> list(type = "trade",  give = "wool", give_count = 2L, receive = "ore")
> list(type = "play_knight",         hex_id = 5L, victim_id = 2L)
> list(type = "play_year_of_plenty", res1 = "ore", res2 = "grain")
> list(type = "play_monopoly",       resource = "ore")
> list(type = "play_road_building",  edge1 = 3L, edge2 = 8L)
> list(type = "done")
> ```
>
> **Option B — Enumerated action constants + separate parameter args.**
>
> **Recommendation: Option A.** The tagged list is self-documenting, easy to
> log, and straightforward for `game.R` to dispatch with a switch/if-else
> chain. The `"done"` sentinel makes the turn loop clean.

---

## Shared Scoring Utilities

All three strategies score intersections during placement and need to evaluate
board positions. These helpers live at the top of `strategy.R` (not inside any
strategy list) and are called by all three strategy implementations.

### `score_intersection(board, intersection_id)`

Computes a base production score for an intersection — the sum of pip counts
across all adjacent hexes. This is the raw expected-resource-per-turn value,
used as the foundation for all placement decisions.

```
score = sum(pips of each adjacent non-desert hex)
```

Maximum possible score: 3 hexes × 5 pips = 15 (three 6/8 hexes — very rare).

### `score_intersection_diversity(board, intersection_id)`

Extends `score_intersection` to reward access to multiple distinct resource
types. Useful for `balanced_strategy` which values flexibility.

```
diversity_bonus = number of distinct resources among adjacent hexes
score = pip_sum + weight * diversity_bonus
```

> **Decision 5 — Diversity weight.**
> How much to weight each additional distinct resource?
> A weight of 1 (one extra "pip equivalent" per new resource type) is a
> reasonable starting point. This can be tuned empirically after running
> simulations to check that `balanced_strategy` wins more often than
> `sheep_strategy`.

### `score_intersection_for_resource(board, intersection_id, resource)`

Returns the total pips from adjacent hexes that produce `resource`. Used by
`sheep_strategy` to weight wool-producing hexes and by `ore_grain_strategy` to
weight ore/grain hexes.

### `valid_settlement_candidates(board, taken_ids)`

Returns all intersection IDs that satisfy `is_valid_settlement_spot()` and are
not in `taken_ids`. Filters the full 54 intersections down to the legal set
before any scoring loop.

### `valid_road_candidates(board, player)`

Returns all edge IDs where `is_valid_road_spot(board, edge_id, player$id)` is
TRUE. Used by all `choose_road_placement` implementations.

### `reachable_intersections(board, player, depth)`

Starting from the player's existing road network, returns all intersection IDs
reachable by placing exactly `depth` more roads. Used by road-placement logic
to plan routes toward target intersections (e.g. the Wool port for
`sheep_strategy`).

> **Decision 6 — Implement `reachable_intersections` or stub it?**
> A full BFS is not complex but adds ~20 lines. Without it, `sheep_strategy`
> cannot meaningfully route toward the Wool port and will just pick the closest
> valid road edge, which may not reflect the intended strategy.
>
> **Recommendation:** Implement it. The sheep strategy's defining behaviour
> (routing to the Wool port) is the whole point of the experiment; a stub would
> undermine the simulation's validity.

---

## Strategy Implementations

### `balanced_strategy`

**Goal:** Maximise pip count and resource diversity; build settlements and
cities efficiently; use the best available port.

#### Initial placement

Score every valid intersection using `score_intersection_diversity()`. Break
ties by raw pip score. Pick the highest-scoring unoccupied spot.

#### Second placement

Same scoring function. Since the board state has changed (opponents have
claimed spots), re-evaluate. Implicitly: this pass may pick up a port if a
high-scoring coastal spot happens to border one.

#### Road placement

During setup: extend toward the next highest-scoring unoccupied intersection
reachable within a reasonable road budget (depth ≤ 3).

During normal turns: extend toward the highest-scoring valid settlement spot
not yet occupied; if already at 5 settlements, prioritise longest road
extension for the 2 VP bonus when within reach of claiming it.

#### Trade logic (inside `choose_action`)

For each resource where `count ≥ best_available_rate`:
- Determine what is most needed to complete the next intended build.
- Execute the trade that brings the player closest to the next build goal.
- Repeat until no beneficial trade is possible.

#### Build priority order

1. City (if ore + grain sufficient and settlements exist) — best VP/resource ratio.
2. Settlement (if full settlement cost met and a valid spot exists reachable by roads).
3. Development card (if ore + wool + grain met and deck not empty).
4. Road (if a new settlement spot would become reachable within 2 more roads).
5. Done.

> **Decision 7 — Build priority ordering.**
> The ordering above (city > settlement > dev card > road) reflects standard
> Catan theory: cities give 2 VP for ~5 resource investment whereas settlements
> give 1 VP for 4 resources but require road infrastructure. This is the main
> lever that should cause `balanced_strategy` to outperform `sheep_strategy`.
> The ordering may need tuning; it is worth parameterising so it can be
> adjusted without rewriting the strategy.

#### Dev card play (inside `choose_action`)

- Play a Knight if holding 7+ cards (proactive robber eviction / discard
  avoidance) or if the player is close to Largest Army threshold.
- Play Year of Plenty toward the next build goal (prefer ore+grain).
- Play Monopoly for the resource the player is most short of relative to
  opponents' likely holdings.
- Do not play Road Building unless a specific route goal exists.

---

### `sheep_strategy`

**Goal:** Demonstrate the failure mode of over-investing in wool. The strategy
must be internally consistent (not self-sabotaging) but biased toward wool in
all decision points.

#### Initial placement

Score intersections using `score_intersection_for_resource(board, id, "wool")`
plus a small pip-sum bonus (to avoid placing on obviously terrible spots with
zero production):

```
score = wool_pips * 2 + total_pips * 0.5
```

The 2:1 weight on wool ensures that a strong wool spot beats a marginally
better balanced spot.

#### Second placement

Prioritise placing on or adjacent to the 2:1 Wool port. If a Wool port
intersection is reachable within 3 roads from the first settlement, pick the
highest wool-scoring intersection that also borders the port (or is as close
to it as possible). Otherwise, fall back to the same wool-heavy scoring as the
first placement.

> **Decision 8 — How aggressively should the sheep strategy target the Wool port?**
>
> Two options:
> - **Hard target:** Always try to place within road range of the Wool port on
>   the second pick, even if the production score is poor.
> - **Soft target:** Wool port is a tiebreaker; if the port spot has very low
>   pip count, pick a better wool-producing location instead.
>
> **Recommendation: Hard target.** The entire point is to demonstrate that
> targeting the Wool port is a bad strategy. A half-hearted sheep strategy that
> sometimes abandons the port is less convincing experimentally. Commit to the
> port pursuit even at a production cost.

#### Road placement

Route roads toward the Wool port if not yet settled there. Use
`reachable_intersections()` to find the shortest road path to the nearest Wool
port intersection. After the Wool port is secured, road logic falls back to
"extend toward any valid settlement spot."

#### Trade logic

With the Wool port, the strategy can trade 2 wool for 1 of anything. Prioritise
trading wool for ore and grain to fuel dev card purchases (the strategy's
secondary VP mechanism). Only convert wool → settlements as a last resort.

#### Build priority order

1. Development card (wool + ore + grain met) — the strategy's intended
   secondary path; also accumulates knights for Largest Army.
2. Settlement (if full cost met and valid spot reachable).
3. City (if ore + grain met) — lower priority than `balanced_strategy` because
   the strategy produces less ore/grain.
4. Road (to reach the Wool port or a new settlement spot).
5. Done.

> **Decision 9 — Should `sheep_strategy` still build cities at all?**
>
> If the strategy never builds cities, it is implausibly weak (it would cap at
> 5 VP from settlements + 2 from special cards + 5 from VP dev cards = 12
> maximum, but dev cards are unreliable). The more realistic failure mode is
> that it *tries* to build cities but is starved of ore/grain because its
> placements skewed toward wool. Modelling this starvation is more interesting
> than hardcoding city-avoidance.
>
> **Recommendation:** Keep cities in the build priority but at lower priority
> than dev cards, and let the resource starvation emerge naturally from the
> placement decisions.

#### Dev card play

- Play Knight cards eagerly to accumulate toward Largest Army (the sheep
  strategy's plausible VP path via dev cards).
- Play Year of Plenty for ore + grain to enable more dev card purchases.
- Play Monopoly for ore (the resource the strategy produces least but needs for
  dev cards).

---

### `ore_grain_strategy`

**Goal:** Serve as a reference "strong" strategy. Prioritise ore and grain
hexes; upgrade settlements to cities as fast as possible.

#### Initial placement

Score using a weighted combination:

```
score = ore_pips * 2 + grain_pips * 2 + total_pips * 0.5
```

The 2:1 weight on ore and grain is symmetric with `sheep_strategy`'s wool
weighting, making the two strategies directly comparable.

#### Second placement

Same scoring. If the 2:1 Ore port is reachable within 3 roads, weight it
heavily; similarly for 2:1 Grain. (The ore/grain 2:1 ports are significantly
more valuable than the Wool port — ore is the scarcest resource on the board.)

#### Road placement

Route toward the next valid settlement spot that maximises ore+grain pips.
After reaching 3 settlements, deprioritise new settlements and let the build
phase focus on city upgrades.

#### Build priority order

1. City — the core engine. Double production on ore and grain hexes.
2. Development card (if ore+grain already surplus after city target is met).
3. Settlement (only up to 3; after that city upgrades dominate).
4. Road (only when needed to reach the next settlement).
5. Done.

#### Trade logic

Trade any non-ore/grain surplus at the best available rate toward ore or grain.
Use the 2:1 Ore or Grain port aggressively if available.

---

## Robber Placement (shared logic, called from `game.R`)

When a 7 is rolled or a Knight is played, the active player must place the
robber. This decision is strategy-specific.

All strategies share a common helper:

### `choose_robber_placement(board, player, players, strategy_name)`

Returns the hex ID to place the robber on.

**Common rule for all strategies:** Cannot place on the desert. Cannot place on
the current robber location (must move it).

**Shared default logic:**
1. Find the player with the most VP (the leader).
2. Among all non-desert hexes not currently holding the robber, prefer hexes
   adjacent to the leader's settlements/cities.
3. Among those, prefer high-pip hexes (to maximise disruption).
4. Steal from the chosen hex's highest-card-count neighbour.

This follows the simulation plan's stated simplification: "robber targets the
leading player."

> **Decision 10 — Should strategies have different robber logic?**
>
> A `sheep_strategy` might realistically place the robber on ore/mountain hexes
> to slow down `ore_grain_strategy`. A `balanced_strategy` might target whoever
> has the most cards to trigger discards.
>
> **Recommendation:** Start with one shared robber function for all strategies.
> Robber targeting is a second-order effect; the first-order effect (placement
> scoring differences) should be sufficient to produce the desired win-rate gap.
> Add strategy-specific robber logic only if simulation results are
> inconclusive.

---

## Discard Logic

When a 7 is rolled, each player with more than 7 cards must discard half.
`player.R` provides `discard_to_limit()` which greedily discards the
most-held resource. Strategies can override this via `choose_discard()`.

### `choose_discard(player, strategy_name)`

Returns an updated player with cards removed.

> **Decision 11 — Per-strategy discard or a shared greedy discard?**
>
> `sheep_strategy` will frequently hold wool surplus. The greedy discard in
> `player.R` already handles this correctly (discards the most-held resource
> first). A custom discard that deliberately keeps wool would be unrealistic
> given that wool cannot build cities.
>
> `balanced_strategy` and `ore_grain_strategy` should prioritise keeping ore
> and grain.
>
> **Recommendation:** Implement `choose_discard()` as a strategy-aware function
> that keeps the resources most needed for the strategy's next build target and
> discards the rest. This is a small function but it will meaningfully
> differentiate how each strategy responds to the robber.

---

## File Structure

```r
# strategy.R

# --- Shared scoring helpers ---
score_intersection(board, intersection_id)
score_intersection_diversity(board, intersection_id, diversity_weight = 1)
score_intersection_for_resource(board, intersection_id, resource)
valid_settlement_candidates(board, taken_ids)
valid_road_candidates(board, player)
reachable_intersections(board, player, depth)

# --- Shared game-logic helpers ---
choose_robber_placement(board, player, players)
choose_discard(player, strategy_name)

# --- Strategy constructors ---
balanced_strategy()      # returns the strategy list
sheep_strategy()         # returns the strategy list
ore_grain_strategy()     # returns the strategy list
```

Each strategy constructor returns a list of four named functions (see interface
section). Constructors (rather than bare lists) allow future parameterisation
— e.g. `sheep_strategy(wool_weight = 2)` — without changing the interface.

---

## Interaction with Other Modules

| Caller | Calls into strategy.R via |
|---|---|
| `game.R` | `strategy$choose_initial_placement()`, `strategy$choose_second_placement()`, `strategy$choose_road_placement()`, `strategy$choose_action()`, `choose_robber_placement()`, `choose_discard()` |
| `strategy.R` (internal) | `board.R`: `is_valid_settlement_spot()`, `is_valid_road_spot()`, `hexes_at_intersection()`, `adjacent_intersections()`, `trade_rate_for()`, `best_port_for_player()` |
| `strategy.R` (internal) | `player.R`: `can_build()`, `can_trade()`, `can_play_dev_card()`, `count_resources()` |

---

## Key Decisions Summary

| # | Decision | Recommendation |
|---|---|---|
| 1 | Distance rule enforcement | Strategies filter to valid spots; `game.R` adds hard stop |
| 2 | One vs. two placement functions | Two functions (`choose_initial_placement` + `choose_second_placement`) |
| 3 | `game_state` contents | `list(players, turn, active_id, deck_size)` |
| 4 | Action return format | Tagged list with `type` field; `"done"` sentinel |
| 5 | Diversity weight in balanced scoring | Start at 1 (one pip-equivalent per new resource type) |
| 6 | Implement `reachable_intersections` | Yes — required for `sheep_strategy` port routing to be meaningful |
| 7 | Build priority ordering | City > settlement > dev card > road for `balanced_strategy` |
| 8 | Sheep strategy port aggression | Hard target — always pursue the Wool port even at a production cost |
| 9 | Sheep strategy city building | Yes, cities remain in priority; ore/grain starvation emerges naturally |
| 10 | Per-strategy robber logic | Shared function targeting the leader; revisit if results are inconclusive |
| 11 | Per-strategy discard logic | Strategy-aware `choose_discard()` that preserves the strategy's key resources |
