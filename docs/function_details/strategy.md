# strategy.R — Full Implementation Reference

## Purpose

`strategy.R` is Module 3 of the simulation stack. It defines:

1. The **strategy interface** — four function slots every strategy must implement.
2. **Shared helpers** — scoring, routing, robber placement, discard, and trading utilities called by all strategies.
3. Three **concrete strategy implementations**: `balanced_strategy`, `sheep_strategy`, and `ore_grain_strategy`.

`game.R` calls strategies exclusively through the interface, never directly by implementation name, so strategies are fully interchangeable.

Dependencies (must be sourced first): `board.R`, `player.R`.

---

## Strategy Interface

Every strategy is a plain R named list with exactly four function slots:

```r
list(
  choose_initial_placement = function(board, player, taken_ids) { ... },
  choose_second_placement  = function(board, player, taken_ids) { ... },
  choose_road_placement    = function(board, player, game_state) { ... },
  choose_action            = function(board, player, game_state) { ... }
)
```

### `choose_initial_placement(board, player, taken_ids)`

Called for the **first** settlement in the reverse snake draft.

| Parameter | Type | Description |
|---|---|---|
| `board` | list | Board object from `board.R` |
| `player` | list | The player making the choice |
| `taken_ids` | integer vector | All intersection IDs already occupied by any player |

**Returns:** Single integer intersection ID. Must satisfy `is_valid_settlement_spot()` — strategies filter to valid candidates before scoring.

---

### `choose_second_placement(board, player, taken_ids)`

Called for the **second** settlement (reverse pass of the snake draft). Separated from `choose_initial_placement` because the information state differs — all first-pass placements are visible — and strategies may want different logic on the second pick (e.g. `sheep_strategy` hard-targets the Wool port here).

Same parameters and return type as `choose_initial_placement`.

---

### `choose_road_placement(board, player, game_state, must_connect_to = NULL)`

Called whenever a road is placed: once during initial setup (adjacent to each settlement) and any number of times during normal turns.

| Parameter | Type | Description |
|---|---|---|
| `board` | list | Board object |
| `player` | list | The player making the choice |
| `game_state` | list | Full game state (see `game_state` structure below) |
| `must_connect_to` | integer or NULL | When non-NULL, only edges adjacent to this intersection ID are considered. Used during initial setup to enforce the Catan rule that each setup road must connect directly to the settlement placed that same turn. |

**Returns:** Single integer edge ID. Must satisfy `is_valid_road_spot()`.

---

### `choose_action(board, player, game_state)`

The main per-turn decision function. Called repeatedly by `game.R` in a loop until the strategy returns `list(type = "done")`. Each call returns exactly one action.

**Returns:** Action list (see Action Format below).

---

## game_state Structure

Passed to `choose_road_placement` and `choose_action`:

```r
game_state <- list(
  players   = list(...),  # all player objects (read-only inside strategies)
  turn      = <int>,      # turns elapsed since game start
  active_id = <int>,      # ID of the player currently taking their turn
  deck_size = <int>       # dev cards remaining in the deck
)
```

Strategies may inspect `game_state$players` to read opponent VP, settlement/city locations, and card counts, but must never modify it. `game.R` owns all state mutation.

---

## Action Format

`choose_action` returns a named list with a `type` field. `game.R` dispatches on `type`:

| `type` | Additional fields | Description |
|---|---|---|
| `"build_road"` | `edge_id` | Place a road at the given edge |
| `"build_settlement"` | `intersection_id` | Place a settlement |
| `"build_city"` | `intersection_id` | Upgrade a settlement to a city |
| `"buy_dev_card"` | — | Purchase one dev card from the deck |
| `"trade"` | `give`, `give_count`, `receive` | Bank or port trade |
| `"play_knight"` | `hex_id`, `victim_id` | Play a Knight card; move robber; steal |
| `"play_year_of_plenty"` | `res1`, `res2` | Play Year of Plenty |
| `"play_monopoly"` | `resource` | Play Monopoly |
| `"play_road_building"` | `edge1`, `edge2` | Play Road Building; place two free roads |
| `"done"` | — | End the action phase for this turn |

`victim_id` may be `NA_integer_` when no valid steal target exists.

---

## Shared Helpers

### Scoring

---

#### `score_intersection(board, intersection_id)`

Returns the sum of pip counts across all non-desert hexes adjacent to the intersection. Raw expected-resource-per-turn value. Maximum: 15 (three 6/8 hexes).

**Returns:** Integer.

---

#### `score_intersection_diversity(board, intersection_id, diversity_weight = 1)`

Pip sum plus `diversity_weight` per distinct resource type among adjacent hexes. Used by `balanced_strategy` to reward flexible production spots.

**Returns:** Numeric.

---

#### `score_intersection_for_resource(board, intersection_id, resource)`

Pip sum from adjacent hexes that produce `resource` only. Used by `sheep_strategy` (wool) and `ore_grain_strategy` (ore, grain).

**Returns:** Integer.

---

#### `make_gap_fn(board, player, base_fn, balance_weight)`

Creates a gap-aware scoring closure that wraps `base_fn` with a bonus for resource types the player's current network does not yet produce. For each candidate intersection, adds `balance_weight × pips` for every adjacent hex whose resource is not already covered by any of the player's existing settlements or cities.

Used by `sheep_strategy` and `ore_grain_strategy` in `choose_second_placement` and the settlement-placement step of `choose_action`, so that specialised strategies always have some lumber/brick coverage rather than being stranded without infrastructure resources.

**Returns:** Function `(board, id) -> numeric`.

---

#### `valid_settlement_candidates(board, taken_ids)`

Filters all 54 intersections to those passing `is_valid_settlement_spot()` and not in `taken_ids`. Every strategy calls this before any scoring loop.

**Returns:** Integer vector of valid intersection IDs.

---

#### `valid_road_candidates(board, player)`

Returns all edge IDs where `is_valid_road_spot(board, edge_id, player$id)` is TRUE.

**Returns:** Integer vector of valid edge IDs.

---

### Routing

---

#### `reachable_intersections(board, player, depth)`

BFS outward from the player's existing road network. Returns all intersection IDs reachable by placing at most `depth` additional roads. Intersections blocked by an opponent's structure are not passable.

Used by all strategies to check whether a settlement spot is immediately buildable (`depth = 0`) or to plan a multi-step route.

| Parameter | Type | Description |
|---|---|---|
| `board` | list | Board object |
| `player` | list | Player object |
| `depth` | integer | Maximum additional roads to consider |

**Returns:** Integer vector of reachable intersection IDs.

---

#### `road_toward(board, player, target_id)`

Among all currently valid road placements, picks the edge whose endpoint is closest (BFS distance) to `target_id`. Used by all strategies' `choose_road_placement` implementations.

**Returns:** Integer edge ID, or `NA_integer_` if no candidates exist.

---

#### `bfs_distances(board, source_id)`

BFS from `source_id` to all intersections along all board edges (regardless of ownership — this is a planning function). Returns a length-54 numeric vector of distances; unreachable nodes get `Inf`.

**Returns:** Named numeric vector of length 54.

---

#### `best_settlement_target(board, player, score_fn, taken_ids)`

Among all valid unoccupied settlement candidates, returns the intersection ID with the highest score under `score_fn`. Used by road placement logic to identify where to route toward.

**Returns:** Integer intersection ID, or `NA_integer_`.

---

### Port Helpers

---

#### `port_intersections(board, resource)`

Returns all intersection IDs that border a port for the given resource (`NA` = general 3:1 ports).

**Returns:** Integer vector.

---

#### `nearest_wool_port_intersection(board, player)`

Finds the Wool port intersection closest (BFS distance) to the player's existing road network. Used by `sheep_strategy` to identify its routing target.

**Returns:** Integer intersection ID, or `NA_integer_`.

---

#### `nearest_og_port_intersection(board, player)`

Finds the closest 2:1 Ore or Grain port intersection (BFS distance from the player's network), considering both port types together. Used by `ore_grain_strategy` to identify its routing target.

**Returns:** Integer intersection ID, or `NA_integer_`.

---

### Game Logic

---

#### `choose_robber_placement(board, player, players)`

Shared robber logic for all strategies. Targets the opponent with the most public VP; among their adjacent hexes, picks the highest-pip one. Falls back to the highest-pip moveable hex if the leader has no exposed structures.

Rules enforced: cannot stay on the current robber hex; cannot place on the desert.

| Parameter | Type | Description |
|---|---|---|
| `board` | list | Board object |
| `player` | list | Active player (the one moving the robber) |
| `players` | list | All player objects |

**Returns:** Integer hex ID.

---

#### `choose_steal_victim(board, player, players, hex_id)`

After placing the robber on `hex_id`, returns the player ID of the opponent with the most resource cards among those adjacent to the hex. Returns `NA_integer_` if no valid victim exists.

**Returns:** Integer player ID or `NA_integer_`.

---

#### `choose_discard(player, strategy_name)`

Strategy-aware discard. Each strategy preserves its most-valued resources and discards surpluses first:

| Strategy | Discard order (first → last) |
|---|---|
| `"balanced"` | wool → lumber → brick → grain → ore |
| `"sheep"` | lumber → brick → ore → grain → wool |
| `"ore_grain"` | wool → lumber → brick → grain → ore |

Removes exactly `discard_count(player)` cards from `player.R`.

**Returns:** Updated player list.

---

### Trading

---

#### `trade_toward(board, player, item)`

Repeatedly executes bank/port trades that move the player closer to affording `item`. Stops when the player can afford the item or no further trade helps. Uses `trade_rate_for()` from `board.R` for each resource's best available rate.

**Returns:** Updated player list.

---

#### `first_trade_action(board, player, item)`

Returns the first single trade action (as an action list) that reduces the gap to affording `item`, or `NULL` if no useful trade exists. Used by `choose_action` to return one trade step at a time (since `game.R` calls `choose_action` in a loop).

**Returns:** Action list `list(type = "trade", ...)` or `NULL`.

---

#### `closing_action(board, player, game_state, score_fn)`

Shared late-game routine called by all three strategies once `compute_vp(player) >= closing_vp`. When a strategy is in the home stretch, rigid specialisation hurts — the goal is simply to reach 10 VP as fast as possible. This function uses the same flexible priority chain as `balanced_strategy` but scores candidates with the calling strategy's own `score_fn`, so placement preferences remain coherent.

Priority: play dev card → trade toward city/settlement/dev_card → build city → build settlement → buy dev card → build road → done.

**Returns:** Action list.

---

## Strategy Constructors

Each strategy is created by calling its constructor function, which returns the four-function interface list. Constructors accept optional weight and threshold parameters so behaviour can be tuned without modifying internals.

---

### `balanced_strategy(diversity_weight = 1, closing_vp = 5)`

**Goal:** Maximise expected production and resource diversity. Prioritise city upgrades (best VP-per-resource) and smooth shortfalls via trading.

#### Placement scoring

```
score = pip_sum + diversity_weight * n_distinct_resources
```

Both picks use the same formula; re-evaluated after each placement.

#### Build priority (`choose_action`)

When `compute_vp(player) >= closing_vp`: delegates to the shared `closing_action` routine.

Otherwise:

1. Play dev card (Knight only when `knights_played >= 2`; Year of Plenty toward city; Monopoly for largest gap)
2. Trade toward city → settlement → dev_card → road — simulate-then-commit; only commits if the full sequence reaches affordability. Road is a last resort so a brick-less balanced can trade into roads when needed (rarely fires given balanced's diverse placement).
3. Build city
4. Build settlement (if a valid spot is reachable in 0 roads)
5. Buy dev card
6. Build road (only if it opens a new settlement spot)
7. Done

#### Road routing

Routes toward the highest diversity-scoring unoccupied intersection within reach.

---

### `sheep_strategy(wool_weight = 2, total_weight = 0.5, closing_vp = 5, balance_weight = 1)`

**Goal:** Demonstrate the failure mode of wool over-investment. Intentionally suboptimal but internally consistent.

#### Placement scoring

```
score = wool_pips * wool_weight + total_pips * total_weight
```

**Second placement:** Two-phase logic based on whether the first settlement already covers both lumber and brick:
- **Infrastructure missing:** Candidate intersections are filtered to those providing at least one of the missing infra resources (lumber, brick). Intersections covering **both** are tried first; if none exist, intersections covering at least one are used; final fallback is all candidates. Gap-aware scoring (`make_gap_fn`) picks the best from the filtered set. No port bonus is applied — getting infrastructure takes priority over the port.
- **Infrastructure covered:** Gap-aware scoring applies normally, with a flat +100 bonus added to Wool port intersections (hard-target the port once infra is secured).

#### Build priority (`choose_action`)

When `compute_vp(player) >= closing_vp`: delegates to the shared `closing_action` routine.

Otherwise:

1. Play Knight — gated on `knights_played >= 2` (avoids wasting early knights before close to Largest Army threshold)
2. Play Year of Plenty for ore+grain (fuel dev cards)
3. Play Monopoly for ore
4. Trade toward city → settlement → dev_card → road — simulate-then-commit pattern; only commits if the full sequence reaches affordability. City almost always fails for sheep (no ore/grain), so settlement fires in practice when sheep has accumulated enough wool to trade 4:1 for grain.
5. Buy dev card
6. Build settlement
7. Build city (lower priority — resource starvation emerges naturally)
8. Build road toward Wool port or next wool spot
9. Done

#### Road routing

Routes toward the nearest Wool port intersection until the port is secured, then toward the next wool-heavy settlement spot.

#### Why this strategy loses

- Places on wool-heavy spots that sacrifice ore/grain pip count.
- Commits roads to the Wool port at the cost of productive interior spots.
- The Wool port is the least impactful 2:1 port — wool is already abundant (4 hexes) so opponents produce it freely without needing the port.
- Dev card purchasing (wool path) is an unreliable VP route compared to cities.
- City starvation: ore/grain shortfall means city upgrades are delayed or impossible.

---

### `ore_grain_strategy(og_weight = 2, total_weight = 0.5, closing_vp = 5, balance_weight = 1)`

**Goal:** Reference strong strategy. Fast-track city upgrades via ore+grain dominance.

#### Placement scoring

```
score = (ore_pips + grain_pips) * og_weight + total_pips * total_weight
```

`total_weight = 0.5` is a weak tie-breaker on total production, matching `sheep_strategy`'s setting so that both strategies weight their secondary (non-target) production equally. The `make_gap_fn` infrastructure guard handles non-target resource coverage explicitly, so `total_weight` only needs to break ties between otherwise equal target-resource spots.

**Second placement:** Two-phase logic mirroring `sheep_strategy`:
- **Infrastructure missing:** Same infra-first filter as sheep — candidates restricted to those providing missing lumber/brick (prefer both; fall back to one; final fallback all). Gap-aware scoring uses `og_weight` as the balance weight (matching the ore/grain multiplier so infra bonuses can compete). No port bonus.
- **Infrastructure covered:** Gap-aware scoring with `balance_weight`, plus a +50 bonus on Ore and Grain port intersections (hard preference — mirrors the commitment expressed in road routing).

#### Build priority (`choose_action`)

When `compute_vp(player) >= closing_vp`: delegates to the shared `closing_action` routine.

Otherwise:

1. Play dev card (same Knight/Year of Plenty/Monopoly logic as balanced)
2. Trade toward city → settlement → dev_card → road — simulate-then-commit; only commits if the full sequence reaches affordability. Road is included so a brick-less ore_grain can trade into roads to pursue port access.
3. Build city (top priority — the entire strategy)
4. Build settlement (production base before dev cards; capped at 4 total structures)
5. Buy dev card (reached only when city is out of reach and no settlement can be placed — resources are genuinely surplus)
6. Build road (only when settlement count < 4) — routes toward nearest Ore/Grain port if not yet secured, then toward best ore+grain settlement spot
7. Done

#### Road routing

Routes toward the nearest 2:1 Ore or Grain port intersection until a port is secured (mirrors `sheep_strategy`'s wool port logic). Once the port is controlled, routes toward the highest ore+grain scoring unoccupied intersection.

#### Why this strategy wins

- Ore is scarce (3 hexes) and essential for cities — securing it early creates a compounding production advantage.
- Cities double ore/grain output, which funds more cities — exponential VP scaling.
- Settlement count is capped at 4 (not 5), keeping the city upgrade path clear while allowing enough infrastructure to reach 8 VP from cities alone (needing only 2 dev-card VP to close out).

---

## Interaction with Other Modules

| Caller | What it calls |
|---|---|
| `game.R` | `strategy$choose_initial_placement()`, `strategy$choose_second_placement()`, `strategy$choose_road_placement()`, `strategy$choose_action()`, `choose_robber_placement()`, `choose_steal_victim()`, `choose_discard()` |
| `strategy.R` → `board.R` | `is_valid_settlement_spot()`, `is_valid_road_spot()`, `hexes_at_intersection()`, `adjacent_intersections()`, `trade_rate_for()`, `get_edge()`, `HEX_INTERSECTIONS` |
| `strategy.R` → `player.R` | `can_build()`, `can_trade()`, `do_trade()`, `can_play_dev_card()`, `count_resources()`, `discard_count()`, `remove_resource()`, `BUILD_COSTS`, `PIECE_LIMITS` |
