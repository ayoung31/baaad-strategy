source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")

run_seed <- function(seed) {
  result <- run_game(
    list(balanced = balanced_strategy(),
         sheep    = sheep_strategy(),
         ore_grain = ore_grain_strategy()),
    seed = seed
  )
  p <- result$players
  winner_strat <- if (is.na(result$winner_id)) "stalemate" else p$strategy[result$winner_id]
  cat(sprintf(
    "Seed %3d | Winner: %-10s | turns=%3d | bal(%dvp %ds %dc) sheep(%dvp %ds %dc %dkn) og(%dvp %ds %dc)\n",
    seed, winner_strat, result$turns,
    p$vp_total[1], p$settlements[1], p$cities[1],
    p$vp_total[2], p$settlements[2], p$cities[2], p$knights[2],
    p$vp_total[3], p$settlements[3], p$cities[3]
  ))
}

seeds <- c(1:30, 42, 46, 52, 99, 100, 123, 200, 314)
for (s in seeds) run_seed(s)
