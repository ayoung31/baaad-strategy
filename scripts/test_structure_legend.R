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

# Check structure_df is non-null and has expected values
int_coords   <- build_intersection_coords(size = 1)
structure_df <- build_structure_df(result$board, int_coords)

cat("structure_df rows:", if (is.null(structure_df)) "NULL" else nrow(structure_df), "\n")
if (!is.null(structure_df)) {
  cat("structure values:", paste(sort(unique(structure_df$structure)), collapse = ", "), "\n")
}

dir.create("figures", showWarnings = FALSE)
png("figures/test_structure_legend.png", width = 1950, height = 1600, res = 150)
print(plot_board(result$board, players = result$player_objects))
dev.off()
cat("Saved figures/test_structure_legend.png\n")
