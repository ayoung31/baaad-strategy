# player.R — Full Implementation Reference

## Purpose

`player.R` defines all data structures and functions needed to represent and
manage an individual Catan player's state. It is Module 2 of the simulation
stack, sitting directly above `board.R` and below `game.R`.

Every mutation function returns a **new player list** rather than modifying the
existing one in place. This is consistent with `board.R`'s approach and keeps
state management in `game.R` explicit and easy to follow.

`player.R` does not `source()` any other module itself — it expects `board.R`
to already be loaded when functions like `grant_initial_resources()` are called.

---

## Data Structures

### Player Object

The top-level object returned by `make_player()`. A plain R named list:

```r
list(
  id                         = <int>,      # player index 1..N
  strategy_name              = <chr>,      # label for analysis
  resources                  = <int[5]>,   # named: lumber/brick/wool/grain/ore
  dev_cards                  = <int[5]>,   # playable hand; named by card type
  dev_cards_new              = <int[5]>,   # drawn this turn; not yet playable
  dev_cards_played_this_turn = <lgl>,      # one active card per turn limit
  knights_played             = <int>,      # cumulative knights for Largest Army
  road_locations             = <int[]>,    # edge IDs of placed roads
  settlement_locations       = <int[]>,    # intersection IDs of settlements
  city_locations             = <int[]>,    # intersection IDs of cities
  has_longest_road           = <lgl>,
  has_largest_army           = <lgl>,
  vp                         = <int>       # visible VP only; see compute_vp()
)
```

#### Field Reference

| Field | Type | Description |
|---|---|---|
| `id` | integer | Player index 1–N, used as the `owner` field in board objects |
| `strategy_name` | character | Strategy label stored for post-game analysis |
| `resources` | integer[5] | Named vector of current resource card counts |
| `dev_cards` | integer[5] | Named vector of playable dev cards in hand |
| `dev_cards_new` | integer[5] | Cards drawn this turn; moved to `dev_cards` next turn |
| `dev_cards_played_this_turn` | logical | `TRUE` after playing any non-VP dev card this turn |
| `knights_played` | integer | Total knights played across all turns |
| `road_locations` | integer vector | Edge IDs of all placed roads |
| `settlement_locations` | integer vector | Intersection IDs of active settlements |
| `city_locations` | integer vector | Intersection IDs of cities |
| `has_longest_road` | logical | Whether player currently holds Longest Road (2 VP) |
| `has_largest_army` | logical | Whether player currently holds Largest Army (2 VP) |
| `vp` | integer | Publicly visible VP from structures and special cards |

**Important:** `vp` does **not** include VP dev cards, which are secret. Always
use `compute_vp(player)` when evaluating win conditions or comparing player
scores.

#### Dev-card hand vectors

Both `dev_cards` and `dev_cards_new` are named integer vectors with keys:
`knight`, `road_building`, `year_of_plenty`, `monopoly`, `victory_point`.

The split into two vectors enforces the Catan rule that cards purchased on your
turn cannot be played until your next turn. `advance_dev_cards()` merges
`dev_cards_new` into `dev_cards` at the start of each turn.

---

## Constants

| Constant | Type | Description |
|---|---|---|
| `BUILD_COSTS` | named list of integer[5] | Resource cost vector for each item: `road`, `settlement`, `city`, `dev_card` |
| `PIECE_LIMITS` | integer[3] | Maximum pieces per player: `road = 15`, `settlement = 5`, `city = 4` |
| `DEV_CARD_COUNTS` | integer[5] | Standard deck composition (25 cards total) |
| `VP_VALUES` | integer[5] | VP awarded by each source: settlement, city, largest_army, longest_road, victory_point |
| `LARGEST_ARMY_MIN` | integer | Minimum knights played to claim Largest Army (`3`) |
| `LONGEST_ROAD_MIN` | integer | Minimum continuous road length to claim Longest Road (`5`) |

### BUILD_COSTS detail

```r
BUILD_COSTS <- list(
  road       = c(lumber=1, brick=1, wool=0, grain=0, ore=0),
  settlement = c(lumber=1, brick=1, wool=1, grain=1, ore=0),
  city       = c(lumber=0, brick=0, wool=0, grain=2, ore=3),
  dev_card   = c(lumber=0, brick=0, wool=1, grain=1, ore=1)
)
```

---

## Functions

### Player Constructor

---

#### `make_player(id, strategy_name = "unknown")`

Creates and returns a fresh player list with all fields at their initial values.
No resources, no structures placed, empty dev-card hands, VP = 0.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `id` | integer | — | Player index 1..N |
| `strategy_name` | character | `"unknown"` | Strategy label for analysis output |

**Returns:** Named list (see Player Object above).

---

### Resource Helpers

---

#### `add_resource(player, resource, amount)`

Adds `amount` copies of `resource` to the player's hand.

| Parameter | Type | Description |
|---|---|---|
| `player` | list | Player object |
| `resource` | character | Resource name (one of `RESOURCES` from `board.R`) |
| `amount` | integer | Cards to add; must be non-negative |

**Returns:** Updated player list.

---

#### `add_resources(player, amounts)`

Bulk version of `add_resource()`. Iterates over a named integer vector and
applies each addition in turn.

| Parameter | Type | Description |
|---|---|---|
| `player` | list | Player object |
| `amounts` | integer vector | Named vector of resources to add |

**Returns:** Updated player list.

Used by: `game.R` when applying `compute_production()` results for a dice roll.

---

#### `remove_resource(player, resource, amount)`

Deducts `amount` copies of `resource` from the player's hand. Does **not**
enforce non-negativity — callers must validate with `can_afford()` or
`can_trade()` first.

**Returns:** Updated player list.

---

#### `remove_resources(player, amounts)`

Bulk version of `remove_resource()`. Mirrors `add_resources()`.

**Returns:** Updated player list.

---

#### `count_resources(player)`

Returns the total number of resource cards across all types.

Used by: `must_discard()`, `discard_count()`, `steal_resource()`.

**Returns:** Integer.

---

#### `can_afford(player, cost)`

Checks whether the player holds at least the amount of each resource specified
in `cost`. Short-circuits on the first failing resource.

| Parameter | Type | Description |
|---|---|---|
| `player` | list | Player object |
| `cost` | integer vector | Named resource requirements (e.g. `BUILD_COSTS$settlement`) |

**Returns:** `TRUE` if all requirements are met.

---

### Build Helpers

---

#### `can_build(player, item)`

Validates that the player can afford the build AND has remaining pieces.

Piece checks:
- `"road"`: `length(road_locations) < 15`
- `"settlement"`: `length(settlement_locations) < 5`
- `"city"`: `length(city_locations) < 4` AND at least one settlement exists to upgrade
- `"dev_card"`: resource check only (deck limit enforced externally by `game.R`)

Does **not** check board placement legality — use `is_valid_settlement_spot()`
and `is_valid_road_spot()` from `board.R` for that.

| Parameter | Type | Description |
|---|---|---|
| `player` | list | Player object |
| `item` | character | One of `"road"`, `"settlement"`, `"city"`, `"dev_card"` |

**Returns:** `TRUE` if the build is legal from the player's perspective.

---

#### `do_build(player, item)`

Deducts the resource cost of `item` from the player's hand using `BUILD_COSTS`.
Does **not** update location vectors — that is done separately by the helpers
below so that game.R can interleave placement validation cleanly.

| Parameter | Type | Description |
|---|---|---|
| `player` | list | Player object |
| `item` | character | One of `"road"`, `"settlement"`, `"city"`, `"dev_card"` |

**Returns:** Updated player list with resources spent.

---

#### `add_road_location(player, edge_id)`

Appends `edge_id` to `player$road_locations`. Used for both paid roads and
free roads (Road Building card, initial setup).

**Returns:** Updated player list.

---

#### `add_settlement_location(player, intersection_id)`

Appends `intersection_id` to `player$settlement_locations` and increments
`player$vp` by 1.

**Returns:** Updated player list.

---

#### `upgrade_to_city(player, intersection_id)`

Moves `intersection_id` from `settlement_locations` to `city_locations` and
increments `vp` by 1 (net gain: city = 2, settlement = 1, so +1).
Resources must have been deducted by `do_build()` already.

**Returns:** Updated player list.

---

### Trading

---

#### `can_trade(player, give_resource, give_count)`

Returns `TRUE` if the player holds at least `give_count` of `give_resource`.
The applicable trade rate should be determined first via `trade_rate_for()`
from `board.R` and passed here as `give_count`.

**Returns:** logical.

---

#### `do_trade(player, give_resource, give_count, receive_resource)`

Executes a single bank or port trade: deducts `give_count` of `give_resource`,
adds 1 of `receive_resource`. Multiple trades in a turn can be chained by
calling this function repeatedly on the returned player.

| Parameter | Type | Description |
|---|---|---|
| `player` | list | Player object |
| `give_resource` | character | Resource being given |
| `give_count` | integer | Trade rate: 2 (2:1 port), 3 (3:1 port), or 4 (bank) |
| `receive_resource` | character | Resource received |

**Returns:** Updated player list.

---

### Robber and Discard Mechanics

---

#### `must_discard(player)`

Returns `TRUE` if `count_resources(player) > 7`.

Used by: `game.R` at the start of robber processing when a 7 is rolled.

---

#### `discard_count(player)`

Returns `floor(n / 2)` where `n = count_resources(player)`, or `0` if `n ≤ 7`.

**Returns:** Integer.

---

#### `discard_to_limit(player)`

Removes excess cards greedily (most-held resource first) until the hand is at
`floor(n / 2)` cards. This default favours discarding wool surplus, which
directly penalises the sheep strategy.

Strategy modules may implement a smarter discard by manipulating
`player$resources` directly before calling `discard_to_limit()` as a
safety net.

**Returns:** Updated player list.

---

#### `steal_resource(thief, victim)`

Picks one card uniformly at random from the victim's hand and transfers it to
the thief. Returns a named list `list(thief = ..., victim = ...)`.

If `victim` has no cards, both players are returned unchanged.

| Parameter | Type | Description |
|---|---|---|
| `thief` | list | Player doing the stealing |
| `victim` | list | Player being stolen from |

**Returns:** `list(thief = <player>, victim = <player>)`.

---

### Development Cards

---

#### `draw_dev_card(player, card_type)`

Adds one card of `card_type` to `player$dev_cards_new` (not yet playable).
`game.R` manages the deck and passes the card type here.

**Returns:** Updated player list.

---

#### `advance_dev_cards(player)`

Called at the **start of each turn**. Merges `dev_cards_new` into `dev_cards`
(elementwise addition), resets `dev_cards_new` to all zeros, and sets
`dev_cards_played_this_turn = FALSE`.

**Returns:** Updated player list.

---

#### `can_play_dev_card(player, card_type)`

Returns `FALSE` if:
- Player holds zero copies of `card_type` in `dev_cards`
- `card_type == "victory_point"` (passive reveal, not actively played)
- `dev_cards_played_this_turn == TRUE`

**Returns:** logical.

---

#### `spend_dev_card(player, card_type)`

Internal helper: decrements `dev_cards[[card_type]]`, sets
`dev_cards_played_this_turn = TRUE`, and increments `knights_played` if
`card_type == "knight"`.

Called by all `play_*` functions below.

**Returns:** Updated player list.

---

#### `play_year_of_plenty(player, res1, res2)`

Spends a Year of Plenty card and adds 1 of `res1` and 1 of `res2` to the
player's hand (any two resources from the bank).

**Returns:** Updated player list.

---

#### `play_monopoly(players, player_id, resource)`

Takes the **full players list** (all players are affected). Spends the Monopoly
card for player `player_id`, transfers all copies of `resource` from every
other player to the monopoly player, and returns the updated players list.

| Parameter | Type | Description |
|---|---|---|
| `players` | list | All player objects indexed by ID |
| `player_id` | integer | Player playing the card |
| `resource` | character | Resource to monopolise |

**Returns:** Updated players list.

---

#### `play_road_building(player)`

Marks the Road Building card as spent. The two free road placements are handled
in `game.R` / `strategy.R` via `add_road_location()` for each chosen edge.

**Returns:** Updated player list.

---

### Special Card Tracking

---

#### `award_longest_road(player)` / `revoke_longest_road(player)`

Award or revoke the Longest Road special card. Adjusting VP by ±2 and setting
`has_longest_road`. The pair must be called together by `game.R`: call
`revoke_longest_road()` on the old holder first, then `award_longest_road()`
on the new holder.

**Returns:** Updated player list.

---

#### `award_largest_army(player)` / `revoke_largest_army(player)`

Same pattern as Longest Road but for Largest Army. Adjusts VP by ±2 and
toggles `has_largest_army`.

**Returns:** Updated player list.

---

### Victory Points

---

#### `compute_vp(player)`

Returns the player's true total VP:

```
player$vp  +  dev_cards[["victory_point"]]  +  dev_cards_new[["victory_point"]]
```

`dev_cards_new` VP cards are counted because a player may reveal them
immediately if it pushes them to 10 VP.

Always use this function in win-condition checks — never compare `player$vp`
directly.

**Returns:** Integer total VP.

---

#### `has_won(player)`

Returns `compute_vp(player) >= 10L`.

Used by: `game.R` at the end of each player's turn to detect a winner.

**Returns:** logical.

---

### Initialisation Helpers

---

#### `grant_initial_resources(player, board, intersection_id)`

Grants 1 resource card per adjacent non-desert hex for the second settlement
in initial placement. Calls `hexes_at_intersection()` from `board.R`.

| Parameter | Type | Description |
|---|---|---|
| `player` | list | Player object |
| `board` | list | Board object from `generate_board()` |
| `intersection_id` | integer | Second settlement's intersection ID |

**Returns:** Updated player list with starting resources added.

---

#### `init_players(strategy_names)`

Creates N player objects (one per element of `strategy_names`) with IDs 1..N.

| Parameter | Type | Description |
|---|---|---|
| `strategy_names` | character vector | Strategy labels, one per player |

**Returns:** List of player objects indexed 1..N.

---

### Summary Utility

---

#### `player_summary(player)`

Converts the player's state into a single-row `data.frame`. Useful for
turn-by-turn logging, debugging, and feeding rows into the results table in
`simulation.R` / `analysis.R`.

**Columns:**

| Column | Type | Description |
|---|---|---|
| `id` | integer | Player index |
| `strategy` | character | Strategy label |
| `lumber` / `brick` / `wool` / `grain` / `ore` | integer | Individual resource counts |
| `total_resources` | integer | Hand size |
| `roads` / `settlements` / `cities` | integer | Piece counts |
| `knights_in_hand` | integer | Playable knights in hand |
| `knights_played` | integer | Cumulative knights played |
| `vp_cards` | integer | VP dev cards in playable hand |
| `vp_public` | integer | Visible VP (`player$vp`) |
| `vp_total` | integer | True VP including hidden cards (`compute_vp()`) |
| `has_longest_road` | logical | Longest Road holder |
| `has_largest_army` | logical | Largest Army holder |

**Returns:** Single-row data.frame.

---

## Relationship to the Dev-Card Deck

`player.R` tracks **per-player** card counts only. The shared deck (a shuffled
character vector of 25 card types) is owned and managed by `game.R`:

```
game.R owns:   deck  ← shuffled character vector of 25 card types
                       (length decreases as cards are drawn)

player.R owns: dev_cards        ← playable hand (integer[5])
               dev_cards_new    ← drawn this turn, not yet playable (integer[5])
```

When a player buys a dev card, `game.R` pops the top of the deck, gets the
card type, deducts the cost with `do_build(player, "dev_card")`, and then
calls `draw_dev_card(player, card_type)` to record the draw.

---

## Interaction with Other Modules

| Caller | Functions used |
|---|---|
| `game.R` | `init_players()`, `advance_dev_cards()`, `add_resource()`, `add_resources()`, `must_discard()`, `discard_to_limit()`, `steal_resource()`, `can_build()`, `do_build()`, `add_road_location()`, `add_settlement_location()`, `upgrade_to_city()`, `draw_dev_card()`, `spend_dev_card()`, `play_monopoly()`, `play_year_of_plenty()`, `play_road_building()`, `grant_initial_resources()`, `award_longest_road()`, `revoke_longest_road()`, `award_largest_army()`, `revoke_largest_army()`, `compute_vp()`, `has_won()` |
| `strategy.R` | `can_build()`, `can_trade()`, `do_trade()`, `can_play_dev_card()`, `count_resources()`, `player_summary()` |
| `simulation.R` | `player_summary()`, `compute_vp()` |
| `analysis.R` | `player_summary()` (via result data frames produced by `simulation.R`) |
