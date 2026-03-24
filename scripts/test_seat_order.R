source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")

strategies <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)

# Use the actual run_game result so seat assignment includes board RNG consumption
result <- run_game(strategies, seed = 41)
cat("seed=41 actual seat assignment:\n")
for (p in result$player_objects) {
  cat(sprintf("  player %d (turn order %d): %s\n", p$id, p$id, p$strategy_name))
}

# Check across multiple seeds
cat("\nSeat assignments across seeds 41-50:\n")
cat(sprintf("%-6s  %-12s %-12s %-12s\n", "seed", "player1", "player2", "player3"))
for (s in 41:50) {
  r <- run_game(strategies, seed = s)
  nms <- sapply(r$player_objects, `[[`, "strategy_name")
  cat(sprintf("%-6d  %-12s %-12s %-12s\n", s, nms[1], nms[2], nms[3]))
}
