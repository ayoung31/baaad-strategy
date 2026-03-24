source("R/board.R")
source("R/player.R")
source("R/visualize_board.R")

board <- generate_board(seed = 42)
cat("Board generated:", length(board$hexes), "hexes\n")

players <- init_players(c("aggressive", "defensive", "random", "balanced"))

# ── Example pieces (4 players: red, blue, white, orange) ───────────────────
# Settlements
board <- place_structure(board,  2, 1, "settlement")
board <- place_structure(board, 34, 1, "settlement")
board <- place_structure(board, 11, 2, "settlement")
board <- place_structure(board, 45, 2, "settlement")
board <- place_structure(board, 20, 3, "settlement")
board <- place_structure(board, 47, 3, "settlement")
board <- place_structure(board,  6, 4, "settlement")
board <- place_structure(board, 39, 4, "settlement")

# Cities (upgrade two settlements)
board <- place_structure(board, 34, 1, "city")
board <- place_structure(board, 45, 2, "city")

# Roads: extend 2 edges from each settlement
place_roads_from <- function(board, int_id, player_id, n = 2L) {
  for (nbr in adjacent_intersections(int_id)) {
    if (n == 0L) break
    eid <- get_edge_id(board, int_id, nbr)
    if (!is.na(eid) && is.na(board$edges[[eid]]$owner)) {
      board <<- place_road(board, eid, player_id)
      n <- n - 1L
    }
  }
}

place_roads_from(board,  2, 1)
place_roads_from(board, 34, 1)
place_roads_from(board, 11, 2)
place_roads_from(board, 45, 2)
place_roads_from(board, 20, 3)
place_roads_from(board, 47, 3)
place_roads_from(board,  6, 4)
place_roads_from(board, 39, 4)

cat("Pieces placed\n")

dir.create("figures", showWarnings = FALSE)

png("figures/example_board.png", width = 1950, height = 1600, res = 150)
print(plot_board(board, size = 2.5, players = players))
dev.off()

cat("Saved to figures/example_board.png\n")
