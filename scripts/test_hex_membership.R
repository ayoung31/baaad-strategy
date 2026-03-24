source("R/board.R")
source("R/visualize_board.R")

m <- build_hex_membership()

cat(sprintf("List length: %d  (expected 54)\n", length(m)))

# Count how many intersections belong to 1, 2, or 3 hexes
counts <- sapply(m, length)
cat(sprintf("Intersections in 1 hex: %d\n", sum(counts == 1L)))
cat(sprintf("Intersections in 2 hexes: %d\n", sum(counts == 2L)))
cat(sprintf("Intersections in 3 hexes: %d\n", sum(counts == 3L)))
cat(sprintf("Intersections in 0 hexes: %d  (should be 0)\n", sum(counts == 0L)))

# Spot checks
cat(sprintf("\nIntersection  1 in hexes: %s  (expected: 1)\n",
            paste(m[[1]], collapse = ",")))
cat(sprintf("Intersection  3 in hexes: %s  (expected: 1,2)\n",
            paste(m[[3]], collapse = ",")))
cat(sprintf("Intersection 17 in hexes: %s  (expected: 3+ hexes)\n",
            paste(m[[17]], collapse = ",")))
