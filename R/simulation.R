# =============================================================================
# simulation.R
# Monte Carlo runner for the Catan sheep-strategy simulation.
#
# Entry point: run_simulation(n_games, strategies, board, seed, verbose)
#
# Dependencies (must be sourced first): board.R, player.R, strategy.R, game.R
# =============================================================================


# =============================================================================
# Private helpers
# =============================================================================

#' Convert a single run_game() result into two tidy data.frames.
#'
#' Splits the game result list returned by run_game() into:
#'   - A one-row game-level data.frame.
#'   - A per-player data.frame (one row per player) with game_id prepended.
#'
#' @param result  Named list returned by run_game().
#' @param game_id Integer identifier for this game (1-indexed within the run).
#' @return Named list with two elements:
#'   - `game`:    One-row data.frame with columns:
#'                  game_id, winner_id, winner_strategy, turns, is_stalemate
#'   - `players`: data.frame (one row per player) with columns:
#'                  game_id, id, strategy, vp_visible, vp_total,
#'                  settlements, cities, roads, knights,
#'                  longest_road, largest_army
game_result_to_rows <- function(result, game_id) {
  is_stalemate     <- is.na(result$winner_id)
  winner_strategy  <- if (is_stalemate) {
    NA_character_
  } else {
    result$players$strategy[result$players$id == result$winner_id]
  }

  game_row <- data.frame(
    game_id          = game_id,
    winner_id        = result$winner_id,
    winner_strategy  = winner_strategy,
    turns            = result$turns,
    is_stalemate     = is_stalemate,
    stringsAsFactors = FALSE
  )

  player_rows <- cbind(game_id = game_id, result$players,
                       stringsAsFactors = FALSE)

  list(game = game_row, players = player_rows)
}


# =============================================================================
# Main entry point
# =============================================================================

#' Run N simulated Catan games and collect results.
#'
#' Calls run_game() once per game, converts each result via game_result_to_rows(),
#' and returns two tidy data.frames. Failed games are skipped and logged to
#' stderr without stopping the run.
#'
#' @param n_games    Integer number of games to simulate.
#' @param strategies Named list of strategy objects (passed directly to
#'   run_game()). Names become strategy labels in the output. Length determines
#'   the number of players.
#' @param board      Optional pre-built board list from generate_board(). When
#'   NULL (default) a fresh random board is generated for each game. Pass a
#'   fixed board to isolate strategy differences from board variance.
#' @param seed       Optional integer base seed for reproducibility. Each game
#'   uses seed + game_id so individual games are reproducible in isolation while
#'   the full run is also deterministic. When NULL, no seed is set.
#' @param verbose    Logical. When TRUE, prints a progress dot every 100 games
#'   and a summary line at the end. Default FALSE.
#' @return Named list with two elements:
#'   - `games`:   data.frame with one row per game; columns:
#'                  game_id, winner_id, winner_strategy, turns, is_stalemate
#'   - `players`: data.frame with one row per player per game; columns:
#'                  game_id, id, strategy, vp_visible, vp_total,
#'                  settlements, cities, roads, knights,
#'                  longest_road, largest_army
run_simulation <- function(n_games, strategies, board = NULL, seed = NULL,
                           verbose = FALSE) {
  game_rows   <- vector("list", n_games)
  player_rows <- vector("list", n_games)
  n_errors    <- 0L

  for (i in seq_len(n_games)) {
    game_seed <- if (!is.null(seed)) seed + i else NULL

    result <- tryCatch(
      run_game(strategies, board = board, seed = game_seed),
      error = function(e) {
        message("simulation.R: game ", i, " failed — ", conditionMessage(e))
        NULL
      }
    )

    if (is.null(result)) {
      n_errors <- n_errors + 1L
      next
    }

    rows            <- game_result_to_rows(result, game_id = i)
    game_rows[[i]]   <- rows$game
    player_rows[[i]] <- rows$players

    if (verbose && i %% 100L == 0L) cat(".")
  }

  if (verbose) cat("\n")

  # Drop NULLs left by failed games before binding.
  game_rows   <- Filter(Negate(is.null), game_rows)
  player_rows <- Filter(Negate(is.null), player_rows)

  if (n_errors > 0L) {
    message("run_simulation: ", n_errors, " of ", n_games,
            " games failed and were excluded from results.")
  }

  list(
    games   = do.call(rbind, game_rows),
    players = do.call(rbind, player_rows)
  )
}


# =============================================================================
# Persistence
# =============================================================================

#' Write simulation results to CSV files.
#'
#' Writes the two data.frames from run_simulation() to separate CSV files.
#' Creates the output directory if it does not exist.
#'
#' @param sim  Named list returned by run_simulation() (must have `games` and
#'   `players` elements).
#' @param path Directory path to write into. Defaults to "results/".
#' @return Invisibly returns `sim` so the call can be piped.
write_simulation_results <- function(sim,
                                     path = "results") {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE)

  games_file   <- file.path(path, "simulation_results.csv")
  players_file <- file.path(path, "player_results.csv")

  write.csv(sim$games,   games_file,   row.names = FALSE)
  write.csv(sim$players, players_file, row.names = FALSE)

  message("Wrote ", nrow(sim$games),   " game rows to ",   games_file)
  message("Wrote ", nrow(sim$players), " player rows to ", players_file)

  invisible(sim)
}


# =============================================================================
# Aggregation
# =============================================================================

#' Compute a 95% Wilson confidence interval for a proportion.
#'
#' @param k Integer number of successes.
#' @param n Integer number of trials.
#' @return Named numeric vector with elements `lower` and `upper`.
wilson_ci <- function(k, n) {
  if (n == 0L) return(c(lower = NA_real_, upper = NA_real_))
  z    <- 1.96
  phat <- k / n
  denom  <- 1 + z^2 / n
  centre <- (phat + z^2 / (2 * n)) / denom
  margin <- (z * sqrt(phat * (1 - phat) / n + z^2 / (4 * n^2))) / denom
  c(lower = max(0, centre - margin), upper = min(1, centre + margin))
}

#' Summarise results from run_simulation() into win rates, game length, and
#' mean VP per strategy.
#'
#' @param sim Named list returned by run_simulation() (must have `games` and
#'   `players` elements).
#' @return Named list with four elements:
#'   - `win_rates`:     data.frame with columns strategy, wins, games_played,
#'                      win_rate, ci_lower, ci_upper (one row per strategy;
#'                      stalemate games excluded from games_played).
#'   - `stalemate_rate`: numeric fraction of games that ended in stalemate.
#'   - `game_length`:   data.frame with columns winner_strategy, mean_turns,
#'                      median_turns (one row per strategy + one "overall" row).
#'   - `mean_vp`:       data.frame with columns strategy, mean_vp_total
#'                      (average final VP per strategy across all games).
summarise_simulation <- function(sim) {
  games   <- sim$games
  players <- sim$players

  n_total      <- nrow(games)
  stalemate_rate <- mean(games$is_stalemate)

  # --- Win rates (exclude stalemates) ---
  decided       <- games[!games$is_stalemate, ]
  all_strategies <- sort(unique(players$strategy))

  win_rate_rows <- lapply(all_strategies, function(strat) {
    wins         <- sum(decided$winner_strategy == strat, na.rm = TRUE)
    games_played <- nrow(decided)
    ci           <- wilson_ci(wins, games_played)
    data.frame(
      strategy     = strat,
      wins         = wins,
      games_played = games_played,
      win_rate     = if (games_played > 0L) wins / games_played else NA_real_,
      ci_lower     = ci[["lower"]],
      ci_upper     = ci[["upper"]],
      stringsAsFactors = FALSE
    )
  })
  win_rates <- do.call(rbind, win_rate_rows)

  # --- Game length by winner strategy + overall ---
  length_rows <- lapply(all_strategies, function(strat) {
    subset <- decided$turns[decided$winner_strategy == strat]
    data.frame(
      winner_strategy = strat,
      mean_turns      = if (length(subset) > 0L) mean(subset)   else NA_real_,
      median_turns    = if (length(subset) > 0L) median(subset) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
  overall_row <- data.frame(
    winner_strategy = "overall",
    mean_turns      = mean(games$turns),
    median_turns    = median(games$turns),
    stringsAsFactors = FALSE
  )
  game_length <- rbind(do.call(rbind, length_rows), overall_row)

  # --- Mean final VP per strategy ---
  vp_rows <- lapply(all_strategies, function(strat) {
    vp <- players$vp_total[players$strategy == strat]
    data.frame(
      strategy     = strat,
      mean_vp_total = mean(vp),
      stringsAsFactors = FALSE
    )
  })
  mean_vp <- do.call(rbind, vp_rows)

  list(
    win_rates      = win_rates,
    stalemate_rate = stalemate_rate,
    game_length    = game_length,
    mean_vp        = mean_vp
  )
}
