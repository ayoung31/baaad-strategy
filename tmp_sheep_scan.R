source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")

cat("Scanning for sheep wins...\n\n")

for (seed in 1:200) {
  result <- run_game(
    list(balanced = balanced_strategy(),
         sheep    = sheep_strategy(),
         ore_grain = ore_grain_strategy()),
    seed = seed
  )
  p <- result$players
  if (!is.na(result$winner_id) && p$strategy[result$winner_id] == "sheep") {
    sheep_row <- p[p$strategy == "sheep", ]
    og_row    <- p[p$strategy == "ore_grain", ]
    bal_row   <- p[p$strategy == "balanced", ]
    cat(sprintf(
      "Seed %3d | turns=%3d | sheep(%dvp %ds %dc %dkn %ddr) | bal(%dvp %ds %dc) | og(%dvp %ds %dc)\n",
      seed, result$turns,
      sheep_row$vp_total, sheep_row$settlements, sheep_row$cities,
      sheep_row$knights, sheep_row$roads,
      bal_row$vp_total, bal_row$settlements, bal_row$cities,
      og_row$vp_total, og_row$settlements, og_row$cities
    ))
  }
}
