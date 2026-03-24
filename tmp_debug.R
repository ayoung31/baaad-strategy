source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")

diagnose <- function(seed) {
  result <- run_game(
    list(balanced=balanced_strategy(), sheep=sheep_strategy(), ore_grain=ore_grain_strategy()),
    seed = seed
  )
  cat("\n=== Seed", seed, "===\n")
  cat("Winner:", result$players$strategy[result$winner_id], "\n")
  print(result$players[, c("strategy","vp_total","settlements","cities","roads","knights")])

  # For each player show their settlement locations and adjacent resources
  cat("\nSettlement resource coverage:\n")
  board <- result$board
  for (i in seq_len(nrow(result$players))) {
    p   <- result$player_objects[[i]]
    cat(sprintf("  %s (player %d):\n", p$strategy_name, p$id))
    all_locs <- c(p$settlement_locations, p$city_locations)
    covered  <- character(0)
    for (int_id in all_locs) {
      res_here <- character(0)
      for (hid in hexes_at_intersection(board, int_id)) {
        r <- board$hexes[[hid]]$resource
        if (!is.na(r)) { res_here <- c(res_here, r); covered <- union(covered, r) }
      }
      cat(sprintf("    intersection %d: %s\n", int_id, paste(unique(res_here), collapse=", ")))
    }
    cat(sprintf("    covered resources: %s\n", paste(sort(covered), collapse=", ")))
    has_lb <- all(c("lumber","brick") %in% covered)
    cat(sprintf("    has lumber+brick: %s\n\n", has_lb))
  }
}

diagnose(46)
diagnose(52)
