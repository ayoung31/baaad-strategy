# baaad-strategy

<img src="hex-sticker.svg" align="right" width="160"/>

A Monte Carlo simulation in R that proves, statistically, that the sheep strategy in Catan is **baaad**.

The sheep strategy — obsessively settling on high-wool hexes and racing to the 2:1 Wool port — sounds clever. This project runs thousands of simulated games to show it loses significantly more often than a balanced approach.

---

## What It Does

Simulates N games of Catan with players using different strategies and compares win rates via chi-squared test. Three strategies compete:

| Strategy | Description |
|---|---|
| `balanced_strategy` | Maximizes pip count and resource diversity; prioritizes ore + grain for city scaling; uses best available port |
| `sheep_strategy` | Scores placements by adjacent wool pips; routes roads to the 2:1 Wool port; dumps surplus wool into dev cards |
| `ore_grain_strategy` | Prioritizes ore and grain hexes; fast-tracks city upgrades |

---

## Hypothesis

The sheep strategy should lose because:

- Wool is needed for settlements and dev cards but **not cities**, which are the primary VP-scaling mechanism
- Wool hexes are the **most abundant** (4 of 19), so opponents produce plenty naturally — the 2:1 Wool port offers less edge than a 2:1 Ore or 2:1 Grain port
- Prioritizing wool placement sacrifices better ore/grain spots, starving the city-building engine
- A wool surplus with no matching ore/grain cannot efficiently convert to victory points

**Success criterion:** sheep strategy win rate is statistically significantly lower than balanced strategy (p < 0.05) across 1,000 simulated games.

---

## Architecture

All code is written in R using base R and `ggplot2`. Six modules:

```
R/
  board.R       # hex graph, board generation, ports
  player.R      # player state and resource management
  strategy.R    # strategy interface + implementations
  game.R        # single game loop
  simulation.R  # Monte Carlo runner
  analysis.R    # results aggregation and plotting
results/        # CSV output from simulation runs
tests/          # testthat unit tests
```

### Key simplifications vs. full Catan rules

| Rule | Simplification |
|---|---|
| Player-to-player trading | Omitted; bank/port trading only |
| Longest Road | Tracked; 2 VP awarded at threshold |
| Largest Army | Tracked; 2 VP at 3+ knights |
| Dev card variety | Knights and VP cards; Progress cards stubbed |
| Robber targeting | Always targets the leading player |

---

## Usage

```r
source("R/simulation.R")

results <- run_simulation(n_games = 1000, seed = 42)

source("R/analysis.R")
plot_win_rates(results)
```

Results are written to `results/simulation_results.csv`.
