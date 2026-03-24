source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")
source("R/visualize_board.R")

strategies <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)

result <- run_game(strategies, seed = 41)

cat("Players:\n")
for (p in result$player_objects) {
  cat(sprintf("  Player %d (%s): VP=%d, knights=%d, LR=%s, LA=%s\n",
              p$id, p$strategy_name,
              p$vp + p$dev_cards[["victory_point"]],
              p$knights_played,
              p$has_longest_road, p$has_largest_army))
}

dir.create("figures", showWarnings = FALSE)
png("figures/test_player_panels.png", width = 2400, height = 1800, res = 150)
print(plot_game_state(result$board, result$player_objects, size = 1))
dev.off()
cat("Saved figures/test_player_panels.png\n")
