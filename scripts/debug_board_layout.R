source("R/board.R")
source("R/player.R")
source("R/visualize_board.R")
library(ggplot2)

SIZE <- 1

board <- generate_board(seed = 42)

# Same placements as generate_board_plot.R
board <- place_structure(board,  2, 1, "settlement")
board <- place_structure(board, 34, 1, "settlement")
board <- place_structure(board, 11, 2, "settlement")
board <- place_structure(board, 45, 2, "settlement")
board <- place_structure(board, 20, 3, "settlement")
board <- place_structure(board, 47, 3, "settlement")
board <- place_structure(board,  6, 4, "settlement")
board <- place_structure(board, 39, 4, "settlement")
board <- place_structure(board, 34, 1, "city")
board <- place_structure(board, 45, 2, "city")

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
place_roads_from(board,  2, 1); place_roads_from(board, 34, 1)
place_roads_from(board, 11, 2); place_roads_from(board, 45, 2)
place_roads_from(board, 20, 3); place_roads_from(board, 47, 3)
place_roads_from(board,  6, 4); place_roads_from(board, 39, 4)

# --- Build data frames manually ---
coords <- build_intersection_coords(SIZE)

# Hex polygon outlines
hex_df <- do.call(rbind, lapply(seq_len(nrow(HEX_GRID)), function(i) {
  ctr <- hex_center_xy(HEX_GRID$row[i], HEX_GRID$col_in_row[i], SIZE)
  ang <- (30 + 60 * 0:5) * pi / 180
  data.frame(
    x     = ctr["x"] + SIZE * cos(ang),
    y     = ctr["y"] + SIZE * sin(ang),
    hex   = i,
    group = i
  )
}))

# Hex centre labels
hex_ctr <- do.call(rbind, lapply(seq_len(nrow(HEX_GRID)), function(i) {
  ctr <- hex_center_xy(HEX_GRID$row[i], HEX_GRID$col_in_row[i], SIZE)
  data.frame(x = ctr["x"], y = ctr["y"], label = as.character(i))
}))

# Roads (owned edges)
PLAYER_COLORS <- c("1"="#CC2200","2"="#1155CC","3"="#888888","4"="#FF8800")
road_df <- build_road_df(board, coords)
if (!is.null(road_df)) road_df$colour <- PLAYER_COLORS[road_df$player_id]

# Intersection points + labels
int_df <- coords
int_df$owned <- !is.na(sapply(board$intersections, `[[`, "owner")[1:54])

p <- ggplot() +
  geom_polygon(data = hex_df,
               aes(x = x, y = y, group = group),
               fill = NA, colour = "black", linewidth = 0.4) +
  geom_text(data = hex_ctr, aes(x = x, y = y, label = label),
            size = 3, colour = "navy", fontface = "bold") +
  # All intersection dots
  geom_point(data = int_df, aes(x = x, y = y), size = 1.5,
             shape = 21, fill = "white", colour = "black") +
  # Intersection ID labels
  geom_text(data = int_df, aes(x = x, y = y, label = intersection_id),
            size = 2, vjust = -0.8, colour = "darkred") +
  coord_equal() +
  theme_void() +
  labs(title = "Debug: hex IDs (blue) and intersection IDs (red)")

# Roads on top
if (!is.null(road_df)) {
  p <- p +
    geom_segment(data = road_df,
                 aes(x = x, y = y, xend = xend, yend = yend, colour = I(colour)),
                 linewidth = 2, lineend = "round")
}

dir.create("figures", showWarnings = FALSE)
png("figures/debug_layout.png", width = 1600, height = 1400, res = 150)
print(p)
dev.off()
cat("Saved figures/debug_layout.png\n")
