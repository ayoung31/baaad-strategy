# Catan Sheep Strategy Simulation — High-Level Plan

## Goal

Run N simulated Catan games comparing players using a **sheep strategy** against players using a **balanced/optimal strategy**, and demonstrate that the sheep strategy produces a significantly lower win rate.

---

## Sheep Strategy Definition

A player is using the sheep strategy if they:
1. **Initial placement:** Prioritize intersections adjacent to high-pip sheep (wool) hexes over other resource diversity.
2. **Port acquisition:** Actively route roads toward and place a second settlement on the 2:1 Wool port.

---

## Why Sheep Strategy Should Lose (Hypothesis)

- Wool is needed for settlements and dev cards but **not** for cities, which are the primary VP-scaling mechanism.
- Wool hexes are the **most abundant** (4 hexes) so other players produce plenty of sheep naturally — the 2:1 Wool port provides less relative advantage than a 2:1 Ore or 2:1 Grain port.
- Prioritizing sheep placement means sacrificing better-positioned ore/grain spots, starving the city-building engine.
- A Wool surplus with no matching Ore/Grain cannot efficiently convert to VP.

---

## Architecture

All code is written in R. Board state, player state, and strategies are represented as lists/environments. The simulation uses base R with `ggplot2` for visualization.

### Module 1: `board.R` — Board Representation

- Represent the board as a list of hexes, intersections (vertices), and edges (roads).
- Hex attributes: terrain type, number token, pip count.
- Standard tile counts: 4 Forest, 3 Hills, 4 Pasture, 4 Fields, 3 Mountains, 1 Desert.
- Standard token distribution: two each of 3–11, one each of 2 and 12.
- Port placement: 4 general (3:1), one each of 5 specific 2:1 ports around the coast.
- Support both a fixed "standard" board and random board generation via `generate_board()`.

### Module 2: `player.R` — Player State

- Represent each player as a named list tracking: resource cards, settlements placed, cities placed, roads placed, dev cards, knight count, VP.
- Helper functions: `can_build(player, item)`, `do_build(player, item)`, `do_trade(player, give, receive)`.
- Resource cap enforcement: discard when holding >7 on a 7 roll.

### Module 3: `strategy.R` — Strategy Interface + Implementations

Define strategies as named lists of functions (R's equivalent of a class interface):
- `choose_initial_placement(board, player, taken)` → intersection id
- `choose_road_placement(board, player, game_state)` → edge id
- `choose_action(board, player, game_state)` → build/trade/dev-card action

**Strategies to implement:**

| Strategy           | Description |
|--------------------|-------------|
| `balanced_strategy` | Maximize pip count and resource diversity at initial placement; prioritize ore+grain for cities; use best available port. |
| `sheep_strategy`   | Score intersections heavily by adjacent sheep pip count; route roads toward and settle on the 2:1 Wool port; spend surplus wool on dev cards. |
| `ore_grain_strategy` | Prioritize ore and grain hexes; fast-track city upgrades. (baseline for comparison) |

### Module 4: `game.R` — Game Loop

Single game simulation:

```
run_game(strategies, board):
    board <- generate_board()
    players <- init_players(strategies)
    run_initial_placement(board, players)  # reverse snake draft

    repeat:
        for each player i:
            roll <- sample(1:6, 1) + sample(1:6, 1)
            if roll == 7:
                apply_robber(board, players, i)
            else:
                distribute_resources(board, players, roll)

            players[[i]] <- trade_phase(players[[i]], strategy, board)
            players[[i]] <- build_phase(players[[i]], strategy, board)

            if players[[i]]$vp >= 10:
                return(i)

        if turns > 200: return(NA)  # stalemate
```

### Module 5: `simulation.R` — Monte Carlo Runner

- `run_simulation(n_games, strategies)` loops over N games and collects results.
- Track per-game: winner index, winner strategy, game length (turns), final VP per player.
- Returns a `data.frame` with one row per game; also writes to `results/simulation_results.csv`.

### Module 6: `analysis.R` — Results + Visualization

- Read `results/simulation_results.csv`.
- Use `ggplot2` to plot:
  - Win rate by strategy (bar chart with confidence intervals).
  - VP distribution at game end per strategy (boxplot or violin).
- Statistical significance: chi-squared test (`chisq.test`) on win count table.

---

## Simplifications (vs. Full Catan)

To keep the simulation tractable:

| Full Rule                        | Simplification |
|----------------------------------|----------------|
| Player-to-player trading         | Omit or simplify to fixed trade offers — focus on bank/port trading |
| Longest Road                     | Track road length, award 2VP when threshold met |
| Largest Army                     | Track knight count, award 2VP at 3+ knights |
| Development card variety         | Implement Knights and VP cards; optionally stub Progress cards |
| Robber targeting logic           | Robber targets the leading player (most VP) |
| UI / visualization               | Console output only; ggplot2 charts for analysis |

---

## File Structure

```
baaad-strategy/
  docs/
    catan_instructions.md
    plans/
      simulation_strategy.md
  R/
    board.R         # hex graph, board generation, ports
    player.R        # player state and resource management
    strategy.R      # strategy interface + implementations
    game.R          # single game loop
    simulation.R    # monte carlo runner
    analysis.R      # results aggregation and plotting
  results/          # CSV output from simulation runs
  tests/            # testthat unit tests for board, player, game logic
```

---

## Success Criteria

- Sheep strategy win rate is statistically significantly lower than Balanced strategy (p < 0.05).
- Results are reproducible with a fixed random seed.
- Simulation runs 1000 games in reasonable time (< 60 seconds).

---

## Implementation Order

1. `board.R` — board generation and graph structure
2. `player.R` — player state
3. `game.R` — game loop with stub strategies
4. `strategy.R` — implement balanced_strategy and sheep_strategy
5. `simulation.R` — multi-game runner
6. `analysis.R` — results and charts
7. Tests and validation (`testthat`)
