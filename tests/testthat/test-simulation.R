source(file.path(dirname(dirname(getwd())), "R", "board.R"))
source(file.path(dirname(dirname(getwd())), "R", "player.R"))
source(file.path(dirname(dirname(getwd())), "R", "strategy.R"))
source(file.path(dirname(dirname(getwd())), "R", "game.R"))
source(file.path(dirname(dirname(getwd())), "R", "simulation.R"))

# =============================================================================
# Shared fixtures
# =============================================================================

# Fake run_game() result — avoids running a full game for unit tests.
make_fake_result <- function(winner_id = 1L,
                             strategies = c("balanced", "sheep", "ore_grain"),
                             turns = 80L) {
  n <- length(strategies)
  player_rows <- lapply(seq_len(n), function(i) {
    data.frame(
      id           = i,
      strategy     = strategies[[i]],
      vp_visible   = 8L,
      vp_total     = if (!is.na(winner_id) && i == winner_id) 10L else 8L,
      settlements  = 2L,
      cities       = 2L,
      roads        = 8L,
      knights      = 1L,
      longest_road = FALSE,
      largest_army = FALSE,
      stringsAsFactors = FALSE
    )
  })
  list(
    winner_id      = winner_id,
    turns          = turns,
    players        = do.call(rbind, player_rows),
    player_objects = list(),
    board          = list()
  )
}

# Fake sim list — for testing summarise_simulation without running games.
# 5 games: balanced wins 2, sheep wins 1, ore_grain wins 1, 1 stalemate.
make_fake_sim <- function() {
  games <- data.frame(
    game_id         = 1:5,
    winner_id       = c(1L, 2L, 1L, NA_integer_, 3L),
    winner_strategy = c("balanced", "sheep", "balanced", NA_character_, "ore_grain"),
    turns           = c(80L, 90L, 75L, 500L, 85L),
    is_stalemate    = c(FALSE, FALSE, FALSE, TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  players <- do.call(rbind, lapply(1:5, function(g) {
    data.frame(
      game_id      = g,
      id           = 1:3,
      strategy     = c("balanced", "sheep", "ore_grain"),
      vp_visible   = c(10L, 7L, 8L),
      vp_total     = c(10L, 8L, 9L),
      settlements  = 2L,
      cities       = 2L,
      roads        = 8L,
      knights      = 1L,
      longest_road = FALSE,
      largest_army = FALSE,
      stringsAsFactors = FALSE
    )
  }))
  list(games = games, players = players)
}

STRATS <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)


# =============================================================================
# game_result_to_rows
# =============================================================================

test_that("game_result_to_rows returns a list with game and players elements", {
  rows <- game_result_to_rows(make_fake_result(), game_id = 1L)
  expect_named(rows, c("game", "players"), ignore.order = FALSE)
})

test_that("game_result_to_rows game element has exactly one row", {
  rows <- game_result_to_rows(make_fake_result(), game_id = 1L)
  expect_equal(nrow(rows$game), 1L)
})

test_that("game_result_to_rows game element has required columns", {
  rows <- game_result_to_rows(make_fake_result(), game_id = 1L)
  expected <- c("game_id", "winner_id", "winner_strategy", "turns", "is_stalemate")
  expect_named(rows$game, expected)
})

test_that("game_result_to_rows stamps game_id onto game row", {
  rows <- game_result_to_rows(make_fake_result(), game_id = 7L)
  expect_equal(rows$game$game_id, 7L)
})

test_that("game_result_to_rows players has one row per player", {
  result <- make_fake_result(strategies = c("balanced", "sheep", "ore_grain"))
  rows   <- game_result_to_rows(result, game_id = 1L)
  expect_equal(nrow(rows$players), 3L)
})

test_that("game_result_to_rows stamps game_id onto every player row", {
  rows <- game_result_to_rows(make_fake_result(), game_id = 5L)
  expect_true(all(rows$players$game_id == 5L))
})

test_that("game_result_to_rows players element has game_id as first column", {
  rows <- game_result_to_rows(make_fake_result(), game_id = 1L)
  expect_equal(names(rows$players)[[1L]], "game_id")
})

test_that("game_result_to_rows resolves winner_strategy from winner_id", {
  result <- make_fake_result(winner_id = 2L,
                             strategies = c("balanced", "sheep", "ore_grain"))
  rows <- game_result_to_rows(result, game_id = 1L)
  expect_equal(rows$game$winner_strategy, "sheep")
})

test_that("game_result_to_rows sets is_stalemate FALSE for a normal result", {
  rows <- game_result_to_rows(make_fake_result(winner_id = 1L), game_id = 1L)
  expect_false(rows$game$is_stalemate)
})

test_that("game_result_to_rows handles stalemate (winner_id = NA)", {
  result <- make_fake_result(winner_id = NA_integer_)
  rows   <- game_result_to_rows(result, game_id = 1L)
  expect_true(rows$game$is_stalemate)
  expect_true(is.na(rows$game$winner_id))
  expect_true(is.na(rows$game$winner_strategy))
})


# =============================================================================
# wilson_ci
# =============================================================================

test_that("wilson_ci returns a named vector with lower and upper", {
  ci <- wilson_ci(50L, 100L)
  expect_named(ci, c("lower", "upper"))
})

test_that("wilson_ci returns NA when n is 0", {
  ci <- wilson_ci(0L, 0L)
  expect_true(is.na(ci[["lower"]]))
  expect_true(is.na(ci[["upper"]]))
})

test_that("wilson_ci lower is less than upper", {
  ci <- wilson_ci(30L, 100L)
  expect_lt(ci[["lower"]], ci[["upper"]])
})

test_that("wilson_ci bounds are within [0, 1]", {
  for (k in c(0L, 1L, 50L, 99L, 100L)) {
    ci <- wilson_ci(k, 100L)
    expect_gte(ci[["lower"]], 0)
    expect_lte(ci[["upper"]], 1)
  }
})

test_that("wilson_ci interval is centred near 0.5 when k = n/2", {
  ci   <- wilson_ci(500L, 1000L)
  mid  <- (ci[["lower"]] + ci[["upper"]]) / 2
  expect_lt(abs(mid - 0.5), 0.01)
})

test_that("wilson_ci gives lower = 0 when k = 0", {
  ci <- wilson_ci(0L, 100L)
  expect_equal(ci[["lower"]], 0)
})

test_that("wilson_ci gives upper = 1 when k = n", {
  ci <- wilson_ci(100L, 100L)
  expect_equal(ci[["upper"]], 1)
})


# =============================================================================
# run_simulation
# =============================================================================

test_that("run_simulation returns a list with games and players elements", {
  sim <- run_simulation(2L, STRATS, seed = 1L)
  expect_named(sim, c("games", "players"), ignore.order = FALSE)
})

test_that("run_simulation games has one row per game", {
  sim <- run_simulation(3L, STRATS, seed = 1L)
  expect_equal(nrow(sim$games), 3L)
})

test_that("run_simulation players has one row per player per game", {
  sim <- run_simulation(3L, STRATS, seed = 1L)
  expect_equal(nrow(sim$players), 3L * length(STRATS))
})

test_that("run_simulation games has required columns", {
  sim      <- run_simulation(2L, STRATS, seed = 1L)
  expected <- c("game_id", "winner_id", "winner_strategy", "turns", "is_stalemate")
  expect_true(all(expected %in% names(sim$games)))
})

test_that("run_simulation players has required columns", {
  sim      <- run_simulation(2L, STRATS, seed = 1L)
  expected <- c("game_id", "id", "strategy", "vp_visible", "vp_total",
                "settlements", "cities", "roads", "knights",
                "longest_road", "largest_army")
  expect_true(all(expected %in% names(sim$players)))
})

test_that("run_simulation game_id values are sequential from 1", {
  sim <- run_simulation(3L, STRATS, seed = 1L)
  expect_equal(sim$games$game_id, 1:3)
})

test_that("run_simulation is reproducible with the same seed", {
  sim_a <- run_simulation(3L, STRATS, seed = 99L)
  sim_b <- run_simulation(3L, STRATS, seed = 99L)
  expect_equal(sim_a$games$winner_strategy, sim_b$games$winner_strategy)
  expect_equal(sim_a$games$turns,           sim_b$games$turns)
})

test_that("run_simulation produces different results with different seeds", {
  sim_a <- run_simulation(5L, STRATS, seed = 1L)
  sim_b <- run_simulation(5L, STRATS, seed = 999L)
  # Very unlikely all 5 games have identical turn counts under different seeds.
  expect_false(identical(sim_a$games$turns, sim_b$games$turns))
})

test_that("run_simulation accepts a fixed board", {
  board <- generate_board(seed = 42L)
  sim   <- run_simulation(2L, STRATS, board = board, seed = 1L)
  expect_equal(nrow(sim$games), 2L)
})

test_that("run_simulation winner_strategy is NA iff is_stalemate is TRUE", {
  sim <- run_simulation(5L, STRATS, seed = 1L)
  expect_equal(
    is.na(sim$games$winner_strategy),
    sim$games$is_stalemate
  )
})


# =============================================================================
# write_simulation_results
# =============================================================================

test_that("write_simulation_results creates the output directory", {
  tmp <- file.path(tempdir(), paste0("sim_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  write_simulation_results(make_fake_sim(), path = tmp)
  expect_true(dir.exists(tmp))
})

test_that("write_simulation_results creates both CSV files", {
  tmp <- file.path(tempdir(), paste0("sim_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  write_simulation_results(make_fake_sim(), path = tmp)
  expect_true(file.exists(file.path(tmp, "simulation_results.csv")))
  expect_true(file.exists(file.path(tmp, "player_results.csv")))
})

test_that("write_simulation_results CSV row counts match the input data.frames", {
  sim <- make_fake_sim()
  tmp <- file.path(tempdir(), paste0("sim_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  write_simulation_results(sim, path = tmp)
  games_csv   <- read.csv(file.path(tmp, "simulation_results.csv"))
  players_csv <- read.csv(file.path(tmp, "player_results.csv"))
  expect_equal(nrow(games_csv),   nrow(sim$games))
  expect_equal(nrow(players_csv), nrow(sim$players))
})

test_that("write_simulation_results returns sim invisibly", {
  sim <- make_fake_sim()
  tmp <- file.path(tempdir(), paste0("sim_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  result <- write_simulation_results(sim, path = tmp)
  expect_identical(result, sim)
})


# =============================================================================
# summarise_simulation
# =============================================================================

test_that("summarise_simulation returns a list with required elements", {
  summary <- summarise_simulation(make_fake_sim())
  expect_named(summary, c("win_rates", "stalemate_rate", "game_length", "mean_vp"),
               ignore.order = FALSE)
})

test_that("summarise_simulation win_rates has one row per strategy", {
  summary <- summarise_simulation(make_fake_sim())
  expect_equal(nrow(summary$win_rates), 3L)  # balanced, sheep, ore_grain
})

test_that("summarise_simulation win_rates has required columns", {
  summary  <- summarise_simulation(make_fake_sim())
  expected <- c("strategy", "wins", "games_played", "win_rate", "ci_lower", "ci_upper")
  expect_named(summary$win_rates, expected)
})

test_that("summarise_simulation win counts are correct", {
  summary <- summarise_simulation(make_fake_sim())
  wr      <- summary$win_rates
  expect_equal(wr$wins[wr$strategy == "balanced"],  2L)
  expect_equal(wr$wins[wr$strategy == "sheep"],     1L)
  expect_equal(wr$wins[wr$strategy == "ore_grain"], 1L)
})

test_that("summarise_simulation win_rate sums to 1 across strategies", {
  summary <- summarise_simulation(make_fake_sim())
  expect_equal(sum(summary$win_rates$win_rate), 1)
})

test_that("summarise_simulation stalemate_rate is correct", {
  summary <- summarise_simulation(make_fake_sim())
  # 1 stalemate out of 5 games
  expect_equal(summary$stalemate_rate, 0.2)
})

test_that("summarise_simulation stalemate_rate is between 0 and 1", {
  summary <- summarise_simulation(make_fake_sim())
  expect_gte(summary$stalemate_rate, 0)
  expect_lte(summary$stalemate_rate, 1)
})

test_that("summarise_simulation game_length has one row per strategy plus overall", {
  summary <- summarise_simulation(make_fake_sim())
  expect_equal(nrow(summary$game_length), 4L)  # 3 strategies + "overall"
  expect_true("overall" %in% summary$game_length$winner_strategy)
})

test_that("summarise_simulation game_length overall mean_turns uses all games", {
  sim     <- make_fake_sim()
  summary <- summarise_simulation(sim)
  expected_mean <- mean(sim$games$turns)
  overall <- summary$game_length$mean_turns[
    summary$game_length$winner_strategy == "overall"
  ]
  expect_equal(overall, expected_mean)
})

test_that("summarise_simulation mean_vp has one row per strategy", {
  summary <- summarise_simulation(make_fake_sim())
  expect_equal(nrow(summary$mean_vp), 3L)
})

test_that("summarise_simulation mean_vp values are positive", {
  summary <- summarise_simulation(make_fake_sim())
  expect_true(all(summary$mean_vp$mean_vp_total > 0))
})

test_that("summarise_simulation includes all strategies even if a strategy never wins", {
  sim <- make_fake_sim()
  # Remove all sheep wins so sheep has 0 wins.
  sim$games$winner_strategy[sim$games$winner_strategy == "sheep"] <- "balanced"
  sim$games$winner_id[sim$games$winner_strategy == "balanced" &
                        sim$games$winner_id == 2L] <- 1L
  summary <- summarise_simulation(sim)
  expect_true("sheep" %in% summary$win_rates$strategy)
  expect_equal(summary$win_rates$wins[summary$win_rates$strategy == "sheep"], 0L)
})
