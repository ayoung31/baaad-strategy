# game.R — Full Implementation Reference

## Purpose

`game.R` is Module 4 (the final module) of the simulation stack. It wires together `board.R`, `player.R`, and `strategy.R` into a complete playable game.

This module owns all state mutation: rolling dice, distributing resources, enforcing the robber, executing actions returned by strategies, and updating the two special cards (Longest Road, Largest Army).

`run_game()` is the only public entry point external callers need; everything else is internal machinery.

Dependencies (must be sourced first): `board.R`, `player.R`, `strategy.R`.

---

## Entry Point

### `run_game(strategies, board = NULL, seed = NULL, max_turns = 500)`

Runs a complete Catan game to completion.

| Parameter | Type | Description |
|---|---|---|
| `strategies` | named list | One strategy object per player (see strategy.R interface). Names become each player's `strategy_name` in the result. List length = number of players. |
| `board` | list or NULL | Optional pre-built board from `generate_board()`. If NULL, a fresh random board is generated. |
| `seed` | integer or NULL | Optional RNG seed for reproducibility. Affects board generation (when board=NULL) and all in-game randomness. |
| `max_turns` | integer | Stalemate cap: if this many individual player turns elapse without a winner, the game ends and `winner_id = NA`. Default: 500. |

**Returns:** Game result list from `make_game_result()`:

| Field | Type | Description |
|---|---|---|
| `winner_id` | integer or NA | 1-indexed player ID of the winner, or `NA_integer_` for stalemate |
| `turns` | integer | Total individual player turns elapsed |
| `players` | data.frame | One row per player with: `id`, `strategy`, `vp_visible`, `vp_total`, `settlements`, `cities`, `roads`, `knights`, `longest_road`, `largest_army` |
| `player_objects` | list | Raw player objects; pass directly to `plot_board(players = ...)` |
| `board` | list | Final board state; pass directly to `plot_board(board = ...)` |

**Win condition:** After each player's turn, `compute_vp(player)` (which includes hidden VP dev cards) is checked against 10.

**Example:**

```r
source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")

strategies <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)

result <- run_game(strategies, seed = 42)
cat("Winner: player", result$winner_id, "in", result$turns, "turns\n")
print(result$players[, c("strategy", "vp_total", "cities")])
```

---

## Internal Functions

### Dev-Card Deck

---

#### `make_deck()`

Constructs a shuffled development card deck using `DEV_CARD_COUNTS` from `player.R` (25 cards total: 14 knights, 5 VP cards, 2 each of road building / year of plenty / monopoly).

**Returns:** Character vector of length 25, randomly shuffled.

---

#### `draw_from_deck(deck)`

Draws the top card from the deck.

| Parameter | Type | Description |
|---|---|---|
| `deck` | character vector | Current deck state |

**Returns:** Named list:
- `card`: character card type, or `NA_character_` if the deck is empty.
- `deck`: updated (shorter) deck.

---

### Resource Distribution

---

#### `distribute_resources(board, players, roll)`

Calls `compute_production(board, roll)` (board.R) to get the production table, then applies `add_resource()` to each affected player.

| Parameter | Type | Description |
|---|---|---|
| `board` | list | Board object |
| `players` | list | All player objects |
| `roll` | integer | Dice total (2–12, not 7) |

**Returns:** Updated players list.

---

### Robber

---

#### `apply_robber(board, players, active_id)`

Handles a roll of 7. Three phases:

1. **Discard:** Every player with more than 7 resource cards calls `choose_discard(player, strategy_name)` (strategy.R) to remove cards down to half (rounded down).
2. **Placement:** The active player calls `choose_robber_placement(board, player, players)` (strategy.R) to pick a hex; robber is moved there via `move_robber()` (board.R).
3. **Steal:** `choose_steal_victim(board, player, players, hex_id)` (strategy.R) returns a victim; `steal_resource()` (player.R) transfers one random card.

| Parameter | Type | Description |
|---|---|---|
| `board` | list | Board object |
| `players` | list | All player objects |
| `active_id` | integer | Player index who rolled 7 |

**Returns:** Named list with updated `board` and `players`.

---

### Special Card Updates

---

#### `update_longest_road(board, players)`

Recomputes `longest_road(board, player_id)` (board.R) for all players and transfers the Longest Road card if needed.

Rules enforced:
- Minimum 5 continuous road segments to hold the card (`LONGEST_ROAD_MIN`).
- A player steals the card only by **strictly exceeding** the current holder's length.
- Ties do not transfer the card.
- If no one holds it yet, it is awarded to the first player who reaches 5+.

Called after every road placement (`build_road`, `play_road_building`).

**Returns:** Updated players list.

---

#### `update_largest_army(players, active_id)`

Checks whether the active player (who just played a knight) should receive or steal the Largest Army card.

Rules enforced:
- Minimum 3 knights played to hold the card (`LARGEST_ARMY_MIN`).
- A player steals the card only by **strictly exceeding** the holder's knight count.
- Only the active player can trigger a change in any given call.

**Returns:** Updated players list.

---

### Action Dispatch

---

#### `apply_action(action, board, players, deck, active_id)`

Applies a single action returned by a strategy's `choose_action()`. Dispatches on `action$type`:

| `type` | What happens |
|---|---|
| `"build_road"` | `do_build("road")` → `place_road()` → `add_road_location()` → `update_longest_road()` |
| `"build_settlement"` | `do_build("settlement")` → `place_structure(…, "settlement")` → `add_settlement_location()` |
| `"build_city"` | `do_build("city")` → `place_structure(…, "city")` → `upgrade_to_city()` |
| `"buy_dev_card"` | `do_build("dev_card")` → `draw_from_deck()` → `draw_dev_card()` |
| `"trade"` | `do_trade(give, give_count, receive)` |
| `"play_knight"` | `spend_dev_card("knight")` → `move_robber()` → `steal_resource()` → `update_largest_army()` |
| `"play_year_of_plenty"` | `play_year_of_plenty(res1, res2)` |
| `"play_monopoly"` | `play_monopoly(players, active_id, resource)` |
| `"play_road_building"` | `play_road_building()` → place two free roads → `update_longest_road()` |
| `"done"` | Not handled here — caller stops the loop |

Unknown `type` values are silently ignored.

| Parameter | Type | Description |
|---|---|---|
| `action` | list | Action list from strategy |
| `board` | list | Board object |
| `players` | list | All player objects |
| `deck` | character vector | Dev-card deck |
| `active_id` | integer | Acting player index |

**Returns:** Named list with updated `board`, `players`, `deck`.

---

#### `run_action_phase(board, players, deck, active_id, strategy, game_state)`

Runs the full action phase for one player's turn by calling `strategy$choose_action()` in a loop until `list(type = "done")` is returned.

After each action, `game_state$players` and `game_state$deck_size` are refreshed so the strategy sees up-to-date state on its next call.

A safety limit of 50 actions per turn prevents infinite loops in buggy strategies.

| Parameter | Type | Description |
|---|---|---|
| `board` | list | Board object |
| `players` | list | All player objects |
| `deck` | character vector | Dev-card deck |
| `active_id` | integer | Active player index |
| `strategy` | list | Strategy object (four-function interface) |
| `game_state` | list | `list(players, turn, active_id, deck_size)` |

**Returns:** Named list with updated `board`, `players`, `deck`.

---

### Initial Placement

---

#### `run_initial_placement(board, players, strategies)`

Runs the reverse snake draft before the main game loop.

Draft order:
- **Forward pass** (1 → n): each player places their first settlement + road.
- **Reverse pass** (n → 1): each player places their second settlement + road, then receives starting resources from the second settlement via `grant_initial_resources()` (player.R).

Each setup road must connect directly to the settlement placed that same turn. This is enforced by passing `must_connect_to = int_id` to `choose_road_placement()`.

Functions called per player per pass:
- `choose_initial_placement()` / `choose_second_placement()` → settlement location
- `choose_road_placement(…, must_connect_to = int_id)` → adjacent road
- `place_structure()`, `place_road()` (board.R) → update board
- `add_settlement_location()`, `add_road_location()` (player.R) → update player
- `grant_initial_resources()` (player.R) → second placement only

**Returns:** Named list with updated `board` and `players`.

---

### Turn Execution

---

#### `run_turn(board, players, deck, active_id, strategies, turn)`

Executes one complete player turn:

1. `advance_dev_cards(player)` — moves last turn's purchased cards into the playable hand and resets the one-play-per-turn flag.
2. Roll `sample(1:6,1) + sample(1:6,1)`.
3. If roll == 7: `apply_robber()`. Otherwise: `distribute_resources()`.
4. `run_action_phase()`.

| Parameter | Type | Description |
|---|---|---|
| `board` | list | Board object |
| `players` | list | All player objects |
| `deck` | character vector | Dev-card deck |
| `active_id` | integer | Index of the player taking the turn |
| `strategies` | list | All strategy objects |
| `turn` | integer | Current turn counter (passed into game_state) |

**Returns:** Named list with updated `board`, `players`, `deck`.

---

### Result

---

#### `make_game_result(winner_id, players, turn, board)`

Constructs the game result summary returned by `run_game()`.

| Parameter | Type | Description |
|---|---|---|
| `winner_id` | integer or NA | Winning player index, or `NA_integer_` for stalemate |
| `players` | list | Final player objects |
| `turn` | integer | Total turns elapsed |
| `board` | list | Final board state |

**Returns:** Named list with `winner_id`, `turns`, `players` data.frame, `player_objects` (raw player list), and `board`.

---

## Interaction with Other Modules

| This module calls | From |
|---|---|
| `generate_board()` | board.R |
| `place_structure()`, `place_road()`, `move_robber()`, `compute_production()`, `longest_road()` | board.R |
| `init_players()`, `advance_dev_cards()`, `grant_initial_resources()` | player.R |
| `add_resource()`, `do_build()`, `do_trade()` | player.R |
| `add_road_location()`, `add_settlement_location()`, `upgrade_to_city()` | player.R |
| `draw_dev_card()`, `spend_dev_card()` | player.R |
| `play_year_of_plenty()`, `play_monopoly()`, `play_road_building()` | player.R |
| `steal_resource()`, `must_discard()`, `compute_vp()` | player.R |
| `award_longest_road()`, `revoke_longest_road()` | player.R |
| `award_largest_army()`, `revoke_largest_army()` | player.R |
| `LONGEST_ROAD_MIN`, `LARGEST_ARMY_MIN`, `DEV_CARD_COUNTS` | player.R (constants) |
| `choose_robber_placement()`, `choose_steal_victim()`, `choose_discard()` | strategy.R |
| Strategy interface: `choose_initial_placement()`, `choose_second_placement()`, `choose_road_placement()`, `choose_action()` | strategy.R constructors |
