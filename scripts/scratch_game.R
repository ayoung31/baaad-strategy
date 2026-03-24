source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")

# =============================================================================
# 1. Single game — fixed seed for reproducibility
# =============================================================================

strategies <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)

result <- run_game(strategies, seed = 42)

cat("=== Single game (seed 42) ===\n")
cat("Winner: player", result$winner_id,
    paste0("(", result$players$strategy[result$winner_id], ")"),
    "in", result$turns, "turns\n\n")
print(result$players)

# =============================================================================
# 2. Monte Carlo: 100 games, track win rates
# =============================================================================

cat("\n=== Monte Carlo: 100 games ===\n")

n_games <- 2L
wins    <- c(balanced = 0L, sheep = 0L, ore_grain = 0L, stalemate = 0L)
turns   <- numeric(n_games)

for (g in seq_len(n_games)) {
  cat("Game ", g, " of ", n_games, "\n")
  r <- run_game(strategies, seed = 42)
  turns[g] <- r$turns
  if (is.na(r$winner_id)) {
    wins["stalemate"] <- wins["stalemate"] + 1L
  } else {
    winner_strategy <- r$players$strategy[r$winner_id]
    wins[winner_strategy] <- wins[winner_strategy] + 1L
  }
}

cat("Win counts (out of", n_games, "games):\n")
print(wins)
cat("\nWin rates:\n")
print(round(wins / n_games, 2))
cat("\nTurns — mean:", round(mean(turns), 1),
    "  min:", min(turns),
    "  max:", max(turns), "\n")

# =============================================================================
# 3. Inspect final board state from the single game (seed 42)
# =============================================================================

cat("\n=== Board summary (seed 42) ===\n")
b <- generate_board(seed = 42)
print(board_hex_summary(b))

plot_board(b, size = 1)
