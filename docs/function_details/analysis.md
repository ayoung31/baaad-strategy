# analysis.R — Full Implementation Reference

## Purpose

`analysis.R` is Module 6 (the final module) of the simulation stack. It reads simulation results, produces three diagnostic plots, and runs a chi-squared test to check whether the win rate differences across strategies are statistically significant.

`run_analysis()` is the only entry point external callers need. All plot and test functions are also callable individually for ad-hoc exploration.

Dependencies: `ggplot2`, `simulation.R` (for `summarise_simulation()`).

---

## Constants

### `STRATEGY_COLORS`

Named character vector mapping each strategy to a fixed colour. Used by all three plot functions so colours are consistent across charts.

| Strategy | Colour | Matches |
|---|---|---|
| `balanced` | `#1155CC` | Player 2 blue in `visualize_board.R` |
| `sheep` | `#8ecf3a` | Pasture terrain in `visualize_board.R` |
| `ore_grain` | `#e8c030` | Fields terrain in `visualize_board.R` |

---

## Entry Point

### `run_analysis(sim, output_dir = "figures")`

Runs the full analysis pipeline: summarises results, produces all three plots, saves them as PNGs, and prints the statistical test result.

| Parameter | Type | Description |
|---|---|---|
| `sim` | list or character | Either a sim list from `run_simulation()` / `load_simulation_results()`, or a directory path string. When a string is passed, `load_simulation_results(sim)` is called automatically. |
| `output_dir` | character | Directory to write PNG figures into. Created if absent. Default `"figures"`. |

**Returns:** The summary list from `summarise_simulation()`, invisibly.

**Output files:**

| File | Plot |
|---|---|
| `{output_dir}/win_rates.png` | Bar chart of win rates with CI error bars |
| `{output_dir}/vp_distribution.png` | Violin + boxplot of final VP by strategy |
| `{output_dir}/game_length.png` | Density curves of game length by winner strategy |

All figures are saved at 8 × 5.33 inches, 150 DPI (1200 × 800 px).

**Example — inline (pipe from run_simulation):**

```r
source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")
source("R/simulation.R")
source("R/analysis.R")

strategies <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)

summary <- run_simulation(1000, strategies, seed = 42L, verbose = TRUE) |>
             run_analysis()

print(summary$win_rates)
```

**Example — post-hoc (from saved CSVs):**

```r
source("R/simulation.R")
source("R/analysis.R")

run_analysis("results")
```

---

## Data Loading

### `load_simulation_results(path = "results")`

Reads both CSV files written by `write_simulation_results()` and returns a sim list compatible with all analysis functions.

| Parameter | Type | Description |
|---|---|---|
| `path` | character | Directory containing the CSV files. Default `"results"`. |

**Returns:** Named list with `games` and `players` data.frames. See `simulation.R` for full column documentation.

**Errors** with a clear message naming the missing file(s) if either CSV is absent.

---

## Plot Functions

All plot functions return a `ggplot` object. The caller decides whether to print it interactively or pass it to `ggsave()`.

---

### `plot_win_rates(summary)`

Bar chart of win rate by strategy with 95% Wilson confidence interval error bars.

| Parameter | Type | Description |
|---|---|---|
| `summary` | list | Named list from `summarise_simulation()`. Only `win_rates` is used. |

**Design:**
- Bars ordered by win rate descending (strongest strategy on the left).
- Horizontal dashed reference line at the fair-share rate (1 / n_strategies).
- Y-axis in percentages (0–100%) rather than proportions.
- Subtitle reports the number of decided games (the n underlying the CIs).

**Returns:** ggplot object.

---

### `plot_vp_distribution(sim)`

Violin plot with overlaid boxplot of final VP totals, one violin per strategy.

| Parameter | Type | Description |
|---|---|---|
| `sim` | list | Sim list from `run_simulation()` or `load_simulation_results()`. Only `players` is used. |

**Design:**
- Uses `vp_total` (includes hidden VP dev cards) not `vp_visible`.
- Violins ordered by median VP descending.
- `trim = TRUE` clips violin tails to the data range (VP is bounded at 10).
- White-filled boxplot overlaid for median and IQR; outlier dots suppressed as redundant.

**Returns:** ggplot object.

---

### `plot_game_length(sim)`

Density curves of game length (individual player turns) by winner strategy.

| Parameter | Type | Description |
|---|---|---|
| `sim` | list | Sim list from `run_simulation()` or `load_simulation_results()`. Only `games` is used. |

**Design:**
- Stalemates excluded (no winner strategy to colour by). The subtitle reports how many were excluded.
- One density curve per strategy, coloured by `STRATEGY_COLORS`.
- Legend retained (curves overlap; x-axis cannot label them).

**Returns:** ggplot object.

---

## Statistical Test

### `test_win_rates(summary)`

Chi-squared test of win rate equality across all strategies.

| Parameter | Type | Description |
|---|---|---|
| `summary` | list | Named list from `summarise_simulation()`. Only `win_rates` is used. |

Constructs a 2 × n_strategies contingency table (wins / losses per strategy) and calls `chisq.test()`. Stalemate games are already excluded from `games_played` in `summarise_simulation()`, so the table contains only decided games.

**Returns:** Named list:

| Field | Type | Description |
|---|---|---|
| `statistic` | numeric | Chi-squared test statistic |
| `df` | integer | Degrees of freedom |
| `p_value` | numeric | p-value |
| `significant` | logical | `TRUE` when `p_value < 0.05` |
| `interpretation` | character | Ready-to-print sentence, e.g. `"Win rates differ significantly across strategies (χ²=47.2, df=2, p<0.001)."` |

---

## Interaction with Other Modules

| This module calls | From |
|---|---|
| `summarise_simulation()` | simulation.R |
| `ggplot()`, `geom_col()`, `geom_violin()`, `geom_density()`, `ggsave()` | ggplot2 |
| `chisq.test()` | base R |
