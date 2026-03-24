source(file.path(dirname(dirname(getwd())), "R", "board.R"))
source(file.path(dirname(dirname(getwd())), "R", "player.R"))
source(file.path(dirname(dirname(getwd())), "R", "strategy.R"))
source(file.path(dirname(dirname(getwd())), "R", "game.R"))
source(file.path(dirname(dirname(getwd())), "R", "simulation.R"))
source(file.path(dirname(dirname(getwd())), "R", "analysis.R"))

# =============================================================================
# Shared fixtures
# =============================================================================

# Mirrors make_fake_sim() from test-simulation.R.
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

FAKE_SIM     <- make_fake_sim()
FAKE_SUMMARY <- summarise_simulation(FAKE_SIM)

# win_rates data.frame with a clearly significant result (unequal wins).
significant_win_rates <- data.frame(
  strategy     = c("balanced", "sheep", "ore_grain"),
  wins         = c(700L, 100L, 200L),
  games_played = 1000L,
  win_rate     = c(0.70, 0.10, 0.20),
  ci_lower     = c(0.67, 0.08, 0.18),
  ci_upper     = c(0.73, 0.12, 0.22),
  stringsAsFactors = FALSE
)

# win_rates data.frame with a non-significant result (nearly equal wins).
nonsignificant_win_rates <- data.frame(
  strategy     = c("balanced", "sheep", "ore_grain"),
  wins         = c(34L, 33L, 33L),
  games_played = 100L,
  win_rate     = c(0.34, 0.33, 0.33),
  ci_lower     = c(0.25, 0.24, 0.24),
  ci_upper     = c(0.44, 0.43, 0.43),
  stringsAsFactors = FALSE
)


# =============================================================================
# STRATEGY_COLORS
# =============================================================================

test_that("STRATEGY_COLORS is a named character vector", {
  expect_type(STRATEGY_COLORS, "character")
  expect_named(STRATEGY_COLORS)
})

test_that("STRATEGY_COLORS contains all three strategy names", {
  expect_true(all(c("balanced", "sheep", "ore_grain") %in% names(STRATEGY_COLORS)))
})

test_that("STRATEGY_COLORS values are valid hex colour strings", {
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}$", STRATEGY_COLORS)))
})

test_that("sheep colour matches pasture terrain colour from visualize_board.R", {
  expect_equal(STRATEGY_COLORS[["sheep"]], "#8ecf3a")
})

test_that("ore_grain colour matches fields terrain colour from visualize_board.R", {
  expect_equal(STRATEGY_COLORS[["ore_grain"]], "#e8c030")
})


# =============================================================================
# load_simulation_results
# =============================================================================

test_that("load_simulation_results returns a list with games and players", {
  tmp <- file.path(tempdir(), paste0("analysis_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  write_simulation_results(FAKE_SIM, path = tmp)
  result <- load_simulation_results(tmp)
  expect_named(result, c("games", "players"))
})

test_that("load_simulation_results round-trips games data correctly", {
  tmp <- file.path(tempdir(), paste0("analysis_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  write_simulation_results(FAKE_SIM, path = tmp)
  result <- load_simulation_results(tmp)
  expect_equal(nrow(result$games),   nrow(FAKE_SIM$games))
  expect_equal(nrow(result$players), nrow(FAKE_SIM$players))
})

test_that("load_simulation_results round-trips column names correctly", {
  tmp <- file.path(tempdir(), paste0("analysis_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  write_simulation_results(FAKE_SIM, path = tmp)
  result <- load_simulation_results(tmp)
  expect_equal(sort(names(result$games)),   sort(names(FAKE_SIM$games)))
  expect_equal(sort(names(result$players)), sort(names(FAKE_SIM$players)))
})

test_that("load_simulation_results errors when games CSV is missing", {
  tmp <- file.path(tempdir(), paste0("analysis_test_", as.integer(Sys.time())))
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))
  # Only write players file, not games file.
  write.csv(FAKE_SIM$players, file.path(tmp, "player_results.csv"),
            row.names = FALSE)
  expect_error(load_simulation_results(tmp), "file\\(s\\) not found")
})

test_that("load_simulation_results errors when both files are missing", {
  tmp <- file.path(tempdir(), paste0("analysis_test_", as.integer(Sys.time())))
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))
  expect_error(load_simulation_results(tmp), "file\\(s\\) not found")
})


# =============================================================================
# plot_win_rates
# =============================================================================

test_that("plot_win_rates returns a ggplot object", {
  p <- plot_win_rates(FAKE_SUMMARY)
  expect_true(inherits(p, "gg"))
})

test_that("plot_win_rates title is correct", {
  p <- plot_win_rates(FAKE_SUMMARY)
  expect_equal(p$labels$title, "Win rate by strategy")
})

test_that("plot_win_rates y-axis label is correct", {
  p <- plot_win_rates(FAKE_SUMMARY)
  expect_equal(p$labels$y, "Win rate")
})

test_that("plot_win_rates data has one row per strategy", {
  p <- plot_win_rates(FAKE_SUMMARY)
  expect_equal(nrow(p$data), nrow(FAKE_SUMMARY$win_rates))
})

test_that("plot_win_rates win_pct values are in 0-100 range", {
  p <- plot_win_rates(FAKE_SUMMARY)
  expect_true(all(p$data$win_pct >= 0 & p$data$win_pct <= 100))
})

test_that("plot_win_rates strategy is a factor ordered by win rate descending", {
  p <- plot_win_rates(FAKE_SUMMARY)
  lvls       <- levels(p$data$strategy)
  rates      <- p$data$win_rate[match(lvls, as.character(p$data$strategy))]
  expect_true(all(diff(rates) <= 0))
})


# =============================================================================
# plot_vp_distribution
# =============================================================================

test_that("plot_vp_distribution returns a ggplot object", {
  p <- plot_vp_distribution(FAKE_SIM)
  expect_true(inherits(p, "gg"))
})

test_that("plot_vp_distribution title is correct", {
  p <- plot_vp_distribution(FAKE_SIM)
  expect_equal(p$labels$title, "Final VP distribution by strategy")
})

test_that("plot_vp_distribution y-axis label is correct", {
  p <- plot_vp_distribution(FAKE_SIM)
  expect_equal(p$labels$y, "VP at game end")
})

test_that("plot_vp_distribution uses vp_total not vp_visible", {
  p <- plot_vp_distribution(FAKE_SIM)
  expect_equal(rlang::as_label(p$mapping$y), "vp_total")
})

test_that("plot_vp_distribution strategy levels ordered by median vp_total descending", {
  p    <- plot_vp_distribution(FAKE_SIM)
  lvls <- levels(p$data$strategy)
  meds <- vapply(lvls, function(s) {
    median(p$data$vp_total[as.character(p$data$strategy) == s])
  }, numeric(1))
  expect_true(all(diff(meds) <= 0))
})


# =============================================================================
# plot_game_length
# =============================================================================

test_that("plot_game_length returns a ggplot object", {
  p <- plot_game_length(FAKE_SIM)
  expect_true(inherits(p, "gg"))
})

test_that("plot_game_length title is correct", {
  p <- plot_game_length(FAKE_SIM)
  expect_equal(p$labels$title, "Game length by winner strategy")
})

test_that("plot_game_length excludes stalemate rows from plot data", {
  p <- plot_game_length(FAKE_SIM)
  expect_false(any(is.na(p$data$winner_strategy)))
})

test_that("plot_game_length data row count equals decided games only", {
  p         <- plot_game_length(FAKE_SIM)
  n_decided <- sum(!FAKE_SIM$games$is_stalemate)
  expect_equal(nrow(p$data), n_decided)
})

test_that("plot_game_length subtitle reports stalemate count", {
  p           <- plot_game_length(FAKE_SIM)
  n_stalemate <- sum(FAKE_SIM$games$is_stalemate)
  expect_true(grepl(as.character(n_stalemate), p$labels$subtitle))
})


# =============================================================================
# test_win_rates
# =============================================================================

test_that("test_win_rates returns a list with required elements", {
  result <- suppressWarnings(test_win_rates(FAKE_SUMMARY))
  expect_named(result,
               c("statistic", "df", "p_value", "significant", "interpretation"),
               ignore.order = FALSE)
})

test_that("test_win_rates p_value is between 0 and 1", {
  result <- suppressWarnings(test_win_rates(FAKE_SUMMARY))
  expect_gte(result$p_value, 0)
  expect_lte(result$p_value, 1)
})

test_that("test_win_rates significant is logical", {
  result <- suppressWarnings(test_win_rates(FAKE_SUMMARY))
  expect_type(result$significant, "logical")
})

test_that("test_win_rates significant is TRUE when p_value < 0.05", {
  result <- test_win_rates(list(win_rates = significant_win_rates))
  expect_true(result$significant)
  expect_lt(result$p_value, 0.05)
})

test_that("test_win_rates significant is FALSE when win rates are equal", {
  result <- test_win_rates(list(win_rates = nonsignificant_win_rates))
  expect_false(result$significant)
  expect_gte(result$p_value, 0.05)
})

test_that("test_win_rates df equals n_strategies minus 1", {
  result <- suppressWarnings(test_win_rates(FAKE_SUMMARY))
  n_strats <- nrow(FAKE_SUMMARY$win_rates)
  expect_equal(unname(result$df), n_strats - 1L)
})

test_that("test_win_rates interpretation is a non-empty string", {
  result <- suppressWarnings(test_win_rates(FAKE_SUMMARY))
  expect_type(result$interpretation, "character")
  expect_gt(nchar(result$interpretation), 0L)
})

test_that("test_win_rates interpretation contains chi-squared symbol", {
  result <- suppressWarnings(test_win_rates(FAKE_SUMMARY))
  expect_true(grepl("\u03c7\u00b2", result$interpretation))
})

test_that("test_win_rates interpretation says 'differ significantly' when significant", {
  result <- test_win_rates(list(win_rates = significant_win_rates))
  expect_true(grepl("differ significantly", result$interpretation))
})

test_that("test_win_rates interpretation says 'do not differ' when not significant", {
  result <- test_win_rates(list(win_rates = nonsignificant_win_rates))
  expect_true(grepl("do not differ", result$interpretation))
})


# =============================================================================
# run_analysis
# =============================================================================

test_that("run_analysis returns summary list invisibly", {
  tmp <- file.path(tempdir(), paste0("analysis_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  result <- suppressWarnings(run_analysis(FAKE_SIM, output_dir = tmp))
  expect_named(result, c("win_rates", "stalemate_rate", "game_length", "mean_vp"))
})

test_that("run_analysis creates the output directory", {
  tmp <- file.path(tempdir(), paste0("analysis_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  suppressWarnings(run_analysis(FAKE_SIM, output_dir = tmp))
  expect_true(dir.exists(tmp))
})

test_that("run_analysis saves all three PNG files", {
  tmp <- file.path(tempdir(), paste0("analysis_test_", as.integer(Sys.time())))
  on.exit(unlink(tmp, recursive = TRUE))
  suppressWarnings(run_analysis(FAKE_SIM, output_dir = tmp))
  expect_true(file.exists(file.path(tmp, "win_rates.png")))
  expect_true(file.exists(file.path(tmp, "vp_distribution.png")))
  expect_true(file.exists(file.path(tmp, "game_length.png")))
})

test_that("run_analysis accepts a path string and loads CSVs automatically", {
  tmp_data <- file.path(tempdir(), paste0("analysis_data_",  as.integer(Sys.time())))
  tmp_figs <- file.path(tempdir(), paste0("analysis_figs_",  as.integer(Sys.time())))
  on.exit({ unlink(tmp_data, recursive = TRUE); unlink(tmp_figs, recursive = TRUE) })
  write_simulation_results(FAKE_SIM, path = tmp_data)
  result <- suppressWarnings(run_analysis(tmp_data, output_dir = tmp_figs))
  expect_named(result, c("win_rates", "stalemate_rate", "game_length", "mean_vp"))
  expect_true(file.exists(file.path(tmp_figs, "win_rates.png")))
})
