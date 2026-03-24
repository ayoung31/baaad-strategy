source("R/board.R")
source("R/visualize_board.R")

corners <- build_hex_corners(size = 1)

cat("Hex 1 corners (size = 1):\n")
for (k in seq_along(corners[[1]])) {
  cat(sprintf("  k=%d  x=%6.3f  y=%6.3f\n",
              k - 1L, corners[[1]][[k]]["x"], corners[[1]][[k]]["y"]))
}

# Every corner must be exactly distance = size from its hex centre
all_ok <- TRUE
for (i in seq_along(corners)) {
  ctr   <- hex_center_xy(HEX_GRID$row[i], HEX_GRID$col_in_row[i], 1)
  dists <- sapply(corners[[i]], function(p)
    sqrt((p["x"] - ctr["x"])^2 + (p["y"] - ctr["y"])^2))
  if (any(abs(dists - 1) > 1e-10)) {
    cat(sprintf("FAIL: hex %d has corner not at distance 1\n", i))
    all_ok <- FALSE
  }
}
cat(sprintf("\nAll 19 hexes: all corners at distance == size? %s\n", all_ok))
cat(sprintf("Total hexes in output: %d  (expected 19)\n", length(corners)))
cat(sprintf("Corners per hex: %d  (expected 6)\n", length(corners[[1]])))
