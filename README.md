# baaad-strategy

<img src="hex-sticker.svg" align="right" width="160"/>

A Monte Carlo simulation in R that proves, statistically, that the sheep strategy in Catan is **baaad**.

The sheep strategy — obsessively settling on high-wool hexes and racing to the 2:1 Wool port — sounds clever. This project runs thousands of simulated games to show it loses significantly more often than a balanced approach.

---

## Strategies

Three strategies compete in every simulation:

| Strategy | Description |
|---|---|
| `balanced` | Maximizes pip count and resource diversity; prioritizes ore + grain for city scaling; uses best available port |
| `sheep` | Scores placements by adjacent wool pips; routes roads to the 2:1 Wool port; dumps surplus wool into dev cards |
| `ore_grain` | Prioritizes ore and grain hexes; fast-tracks city upgrades |

---

## Hypothesis

The sheep strategy should lose because:

- Wool is needed for settlements and dev cards but **not cities**, which are the primary VP-scaling mechanism
- Wool hexes are the **most abundant** (4 of 19), so opponents produce plenty naturally — the 2:1 Wool port offers less edge than a 2:1 Ore or 2:1 Grain port
- Prioritizing wool placement sacrifices better ore/grain spots, starving the city-building engine
- A wool surplus with no matching ore/grain cannot efficiently convert to victory points

**Success criterion:** sheep strategy win rate is statistically significantly lower than balanced strategy (p < 0.05) across 1,000 simulated games.

---

## Reproducing the Analysis

### 1. Prerequisites

- **R >= 4.1** — download from [cran.r-project.org](https://cran.r-project.org)
- **RStudio** (optional but recommended) — download from [posit.co/download/rstudio-desktop](https://posit.co/download/rstudio-desktop)

### 2. Clone the repository

```bash
git clone https://github.com/<your-username>/baaad-strategy.git
cd baaad-strategy
```

### 3. Install dependencies

Open R (or the RStudio console) and run:

```r
install.packages(c("ggplot2", "patchwork", "testthat"))
```

`parallel` is used for multi-core simulation but ships with base R — no installation needed.

### 4. Source the modules

All scripts assume the working directory is the repo root. In RStudio, open the project folder. From the R console:

```r
setwd("path/to/baaad-strategy")  # skip if already in the repo root

source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")
source("R/simulation.R")
source("R/analysis.R")
```

### 5. Define strategies

```r
strategies <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)
```

### 6. Run the simulation

```r
sim <- run_simulation(n_games = 1000, strategies = strategies, seed = 42)
```

This takes a few minutes on a single core. To speed it up with parallel workers:

```r
sim <- run_simulation(
  n_games    = 1000,
  strategies = strategies,
  seed       = 42,
  n_cores    = parallel::detectCores() - 1L
)
```

Results are automatically written to `results/simulation_results.csv` and `results/simulation_players.csv`.

### 7. Generate analysis figures

```r
run_analysis(sim)
```

This saves three plots to `figures/` and prints the chi-squared test result to the console:

| File | Contents |
|---|---|
| `figures/win_rates.png` | Win rate by strategy with confidence intervals |
| `figures/vp_distribution.png` | Final VP distribution per strategy |
| `figures/game_length.png` | Turn count distribution per game |

To reload results from a previous run without re-running the simulation:

```r
run_analysis("results")
```

### 8. Visualize a single game (optional)

```r
source("R/visualize_board.R")

result <- run_game(strategies, seed = 41)

# Board with piece positions and player legend
plot_board(result$board, players = result$player_objects)

# Full game-state view with per-player info panels
plot_game_state(result$board, result$player_objects)
```

To save the game-state image:

```r
png("figures/game_state.png", width = 2400, height = 1800, res = 150)
print(plot_game_state(result$board, result$player_objects))
dev.off()
```

### 9. Run the tests (optional)

```r
library(testthat)
test_dir("tests/testthat")
```

---

## Architecture

Written in base R with `ggplot2` and `patchwork`. Seven modules:

```
R/
  board.R           # hex graph, board generation, intersection/edge topology, ports
  player.R          # player state, resources, dev cards, VP tracking
  strategy.R        # strategy interface + three implementations
  game.R            # single game loop (setup, turns, win detection)
  simulation.R      # Monte Carlo runner (serial and parallel)
  analysis.R        # results aggregation, statistical test, output plots
  visualize_board.R # board and game-state visualizations
```

### Key simplifications vs. full Catan rules

| Rule | Simplification |
|---|---|
| Player-to-player trading | Omitted; bank/port trading only |
| Longest Road | Tracked; 2 VP awarded at threshold |
| Largest Army | Tracked; 2 VP at 3+ knights |
| Dev card variety | All five types implemented (Knight, VP, Road Building, Year of Plenty, Monopoly) |
| Robber targeting | Always targets the leading player |
