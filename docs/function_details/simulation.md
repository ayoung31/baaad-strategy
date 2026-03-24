# simulation.R — Full Implementation Reference

## Purpose

`simulation.R` is Module 5 of the simulation stack. It is the Monte Carlo runner that calls `run_game()` repeatedly, collects results into two tidy data.frames, and provides helpers for persisting and summarising those results.

External callers need three functions: `run_simulation()` to produce results, `write_simulation_results()` to persist them, and `summarise_simulation()` to aggregate them. Everything else is internal.

Dependencies (must be sourced first): `board.R`, `player.R`, `strategy.R`, `game.R`.

---

## Output Schema

All public functions work with the same two data.frames. The schema is fixed so that `analysis.R` and any ad-hoc scripts can rely on stable column names.

### `games` data.frame — one row per game

| Column | Type | Description |
|---|---|---|
| `game_id` | integer | 1-indexed game counter within the simulation run |
| `winner_id` | integer or NA | Seat index (1-indexed) of the winning player, or `NA` for stalemate |
| `winner_strategy` | character or NA | Strategy name of the winner, or `NA` for stalemate |
| `turns` | integer | Total individual player turns elapsed |
| `is_stalemate` | logical | `TRUE` when no player reached 10 VP within `max_turns` |

### `players` data.frame — one row per player per game

| Column | Type | Description |
|---|---|---|
| `game_id` | integer | Links to `games$game_id` |
| `id` | integer | Player seat index (1-indexed) |
| `strategy` | character | Strategy name |
| `vp_visible` | integer | VP visible on the table (excludes VP dev cards) |
| `vp_total` | integer | Full VP including VP dev cards |
| `settlements` | integer | Number of settlements at game end |
| `cities` | integer | Number of cities at game end |
| `roads` | integer | Number of roads placed |
| `knights` | integer | Total knights played |
| `longest_road` | logical | Whether this player held Longest Road at game end |
| `largest_army` | logical | Whether this player held Largest Army at game end |

---

## Entry Point

### `run_simulation(n_games, strategies, board = NULL, seed = NULL, verbose = FALSE)`

Runs `n_games` complete Catan games and returns the results as two tidy data.frames.

| Parameter | Type | Description |
|---|---|---|
| `n_games` | integer | Number of games to simulate |
| `strategies` | named list | One strategy object per player (see strategy.R interface). Names become strategy labels in the output. List length = number of players. |
| `board` | list or NULL | Optional pre-built board from `generate_board()`. When NULL (default), a fresh random board is generated for each game. Pass a fixed board to isolate strategy differences from board variance. |
| `seed` | integer or NULL | Optional base RNG seed. Each game uses `seed + game_id` so individual games are reproducible in isolation while the full run is also deterministic. When NULL, no seed is set. |
| `verbose` | logical | When TRUE, prints a progress dot every 100 games and a summary line at completion. Default FALSE. |

**Returns:** Named list with two elements:

- `games`: data.frame following the `games` schema above.
- `players`: data.frame following the `players` schema above.

Failed games (those where `run_game()` throws an error) are skipped, a message is written to stderr, and the final count of failures is reported. The returned data.frames contain only successful games.

**Example:**

```r
source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")
source("R/simulation.R")

strategies <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)

sim <- run_simulation(1000, strategies, seed = 1L, verbose = TRUE)
# .......... (10 dots for 1000 games)

nrow(sim$games)    # 1000
nrow(sim$players)  # 3000 (3 players × 1000 games)
```

---

## Public Helpers

### `write_simulation_results(sim, path = "results")`

Writes the two data.frames to CSV files inside `path`. Creates the directory if it does not exist.

| Parameter | Type | Description |
|---|---|---|
| `sim` | list | Named list returned by `run_simulation()` |
| `path` | character | Output directory. Default `"results"`. |

**Output files:**

| File | Contents |
|---|---|
| `{path}/simulation_results.csv` | `sim$games` — one row per game |
| `{path}/player_results.csv` | `sim$players` — one row per player per game |

**Returns:** `sim` invisibly, so the call can be piped:

```r
sim <- run_simulation(1000, strategies, seed = 1L) |>
         write_simulation_results()
```

---

### `summarise_simulation(sim)`

Aggregates the two data.frames into a named list of summary tables ready for printing or passing to `analysis.R`.

| Parameter | Type | Description |
|---|---|---|
| `sim` | list | Named list returned by `run_simulation()` |

**Returns:** Named list with four elements:

#### `win_rates` — data.frame

One row per strategy. Stalemate games are excluded from `games_played` and `win_rate`.

| Column | Type | Description |
|---|---|---|
| `strategy` | character | Strategy name |
| `wins` | integer | Number of games won |
| `games_played` | integer | Number of decided (non-stalemate) games |
| `win_rate` | numeric | `wins / games_played` |
| `ci_lower` | numeric | Lower bound of 95% Wilson confidence interval |
| `ci_upper` | numeric | Upper bound of 95% Wilson confidence interval |

#### `stalemate_rate` — numeric scalar

Fraction of all games (including stalemates) that ended without a winner.

#### `game_length` — data.frame

One row per strategy (games won by that strategy) plus one `"overall"` row.

| Column | Type | Description |
|---|---|---|
| `winner_strategy` | character | Strategy name, or `"overall"` |
| `mean_turns` | numeric | Mean individual player turns for games won by this strategy |
| `median_turns` | numeric | Median individual player turns |

#### `mean_vp` — data.frame

One row per strategy.

| Column | Type | Description |
|---|---|---|
| `strategy` | character | Strategy name |
| `mean_vp_total` | numeric | Mean final VP (including VP dev cards) across all games |

**Example:**

```r
summary <- summarise_simulation(sim)

print(summary$win_rates[, c("strategy", "win_rate", "ci_lower", "ci_upper")])
#      strategy  win_rate  ci_lower  ci_upper
#      balanced     0.512     0.481     0.543
#         sheep     0.183     0.160     0.208
#     ore_grain     0.305     0.277     0.334

cat("Stalemate rate:", summary$stalemate_rate, "\n")

print(summary$mean_vp)
```

---

## Internal Functions

### `game_result_to_rows(result, game_id)`

Private helper. Converts the list returned by `run_game()` into the two-row-set format consumed by `run_simulation()`.

| Parameter | Type | Description |
|---|---|---|
| `result` | list | Game result list from `run_game()` |
| `game_id` | integer | Game index to stamp onto both output frames |

**Returns:** Named list with `game` (one-row data.frame) and `players` (per-player data.frame).

`winner_strategy` is looked up from `result$players` using `winner_id` rather than stored redundantly in the game result, so there is no risk of the two fields diverging.

---

### `wilson_ci(k, n)`

Private helper. Computes a 95% Wilson confidence interval for a proportion.

| Parameter | Type | Description |
|---|---|---|
| `k` | integer | Number of successes |
| `n` | integer | Number of trials |

**Returns:** Named numeric vector with elements `lower` and `upper`. Returns `c(lower = NA, upper = NA)` when `n == 0`.

The Wilson interval is used instead of the normal approximation because it behaves correctly near 0 and 1 — relevant when a strategy wins very rarely.

---

## Interaction with Other Modules

| This module calls | From |
|---|---|
| `run_game()` | game.R |
| `balanced_strategy()`, `sheep_strategy()`, `ore_grain_strategy()` | strategy.R (passed in by caller; not called internally) |
| `generate_board()` | board.R (called inside `run_game()`; not directly) |
