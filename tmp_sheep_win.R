source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")
source("R/visualize_board.R")

# game_id=62, simulation seed=42 → game seed = 42+62 = 104
result <- run_game(
  list(balanced  = balanced_strategy(),
       sheep     = sheep_strategy(),
       ore_grain = ore_grain_strategy()),
  seed = 104
)

p <- result$players
cat(sprintf("Winner: %s in %d turns\n", p$strategy[result$winner_id], result$turns))
print(p[, c("strategy", "vp_total", "settlements", "cities", "roads", "knights")])

# Plot and save
plt <- plot_game_state(result$board, result$player_objects, size = 2.5)
ggsave("figures/game_sheep_win.png", plot = plt, width = 16, height = 10, dpi = 150)
cat("Saved: figures/game_sheep_win.png\n")
