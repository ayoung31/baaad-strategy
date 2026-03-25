source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")
source("R/visualize_board.R")

if (!dir.exists("figures")) dir.create("figures")

for (seed in c(16, 99)) {
  result <- run_game(
    list(balanced = balanced_strategy(),
         sheep    = sheep_strategy(),
         ore_grain = ore_grain_strategy()),
    seed = seed
  )

  p <- plot_game_state(result$board, result$player_objects, size = 2.5)

  outfile <- sprintf("figures/game_seed_%d.png", seed)
  ggsave(outfile, plot = p, width = 16, height = 10, dpi = 150)
  cat("Saved:", outfile, "\n")
}
