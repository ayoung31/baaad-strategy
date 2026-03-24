source("R/board.R")
source("R/player.R")
source("R/visualize_board.R")

board <- generate_board(seed = 42)
players <- init_players(c("aggressive", "defensive", "random", "balanced"))

# Place same settlements as generate_board_plot.R
board <- place_structure(board,  2, 1, "settlement")
board <- place_structure(board, 34, 1, "settlement")
board <- place_structure(board, 11, 2, "settlement")
board <- place_structure(board, 45, 2, "settlement")
board <- place_structure(board, 20, 3, "settlement")
board <- place_structure(board, 47, 3, "settlement")
board <- place_structure(board,  6, 4, "settlement")
board <- place_structure(board, 39, 4, "settlement")

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

coords <- build_intersection_coords(size = 1)

cat("Roads placed (intersection endpoints and segment length):\n")
cat(sprintf("%-8s %-6s %-6s   %-8s %-8s   %-8s %-8s   %s\n",
            "edge", "int_i", "int_j", "x_i", "y_i", "x_j", "y_j", "length"))

for (e in board$edges) {
  if (is.na(e$owner)) next
  c1 <- coords[coords$intersection_id == e$ends[1], ]
  c2 <- coords[coords$intersection_id == e$ends[2], ]
  len <- sqrt((c1$x - c2$x)^2 + (c1$y - c2$y)^2)
  cat(sprintf("edge %-4d  %-6d %-6d   %-8.3f %-8.3f   %-8.3f %-8.3f   %.4f  player=%d\n",
              e$id, e$ends[1], e$ends[2],
              c1$x, c1$y, c2$x, c2$y, len, e$owner))
}

# Also print which hexes each road-endpoint intersection belongs to
cat("\nHex membership for road-endpoint intersections:\n")
membership <- build_hex_membership()
owned_ints <- unique(unlist(lapply(board$edges[sapply(board$edges, function(e) !is.na(e$owner))],
                                   function(e) e$ends)))
for (vid in sort(owned_ints)) {
  cat(sprintf("  int %2d: hexes %s\n", vid, paste(membership[[vid]], collapse=",")))
}
