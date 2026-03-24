source("R/board.R")
source("R/visualize_board.R")

all_ids <- unlist(HEX_INTERSECTIONS)
cat("Max intersection ID in HEX_INTERSECTIONS:", max(all_ids), "\n")
cat("IDs > 54:", sort(unique(all_ids[all_ids > 54])), "\n")

edges <- build_edges()
cat("Total edges built:", length(edges), "\n")

# Check for any edge endpoint > 54
bad_edges <- Filter(function(e) e$ends[1] > 54 || e$ends[2] > 54, edges)
cat("Edges with endpoint > 54:", length(bad_edges), "\n")
for (e in bad_edges) cat(sprintf("  edge %d: %d -- %d\n", e$id, e$ends[1], e$ends[2]))

# Check adjacency for any neighbour > 54
invalid <- which(sapply(seq_len(54), function(i) any(INTERSECTION_ADJACENCY[[i]] > 54)))
cat("Intersections with neighbours > 54:", invalid, "\n")
for (i in invalid) {
  bad <- INTERSECTION_ADJACENCY[[i]][INTERSECTION_ADJACENCY[[i]] > 54]
  cat(sprintf("  intersection %d -> %s\n", i, paste(bad, collapse = ", ")))
}

# Check that all edge lengths equal size=1 (adjacent corners of a unit hexagon)
coords <- build_intersection_coords(size = 1)
cat("\nEdge length check (all should be ~1.000):\n")
lengths <- sapply(edges, function(e) {
  c1 <- coords[coords$intersection_id == e$ends[1], ]
  c2 <- coords[coords$intersection_id == e$ends[2], ]
  sqrt((c1$x - c2$x)^2 + (c1$y - c2$y)^2)
})
cat(sprintf("  Min: %.4f  Max: %.4f  (expected 1.000)\n", min(lengths), max(lengths)))
bad_len <- which(abs(lengths - 1) > 1e-6)
cat(sprintf("  Edges with length != 1: %d\n", length(bad_len)))
for (idx in bad_len) {
  e <- edges[[idx]]
  cat(sprintf("  edge %d: %d -- %d  length=%.4f\n", e$id, e$ends[1], e$ends[2], lengths[idx]))
}
