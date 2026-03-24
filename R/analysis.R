# =============================================================================
# analysis.R
# Results aggregation and visualisation for the Catan sheep-strategy simulation.
#
# Entry point: run_analysis(sim, output_dir = "figures")
#
# Dependencies: ggplot2, simulation.R (for summarise_simulation)
# =============================================================================

library(ggplot2)


# =============================================================================
# Constants
# =============================================================================

# Strategy colours used consistently across all plots.
# Matched to the terrain colours in visualize_board.R:
#   sheep     <- pasture  (#8ecf3a)
#   ore_grain <- fields   (#e8c030)
#   balanced  <- blue     (#1155CC, matches PLAYER_COLORS player 2)
STRATEGY_COLORS <- c(
  balanced  = "#1155CC",
  sheep     = "#8ecf3a",
  ore_grain = "#e8c030"
)


# =============================================================================
# Data loading
# =============================================================================

#' Load simulation results from CSV files written by write_simulation_results().
#'
#' Reads both output files and returns a named list matching the schema
#' produced by run_simulation(), so the result can be passed directly to
#' summarise_simulation() or any plot function.
#'
#' @param path Directory containing the CSV files. Default "results".
#' @return Named list with two elements:
#'   - `games`:   data.frame (one row per game)
#'   - `players`: data.frame (one row per player per game)
#'   See simulation.R for full column documentation.
load_simulation_results <- function(path = "results") {
  games_file   <- file.path(path, "simulation_results.csv")
  players_file <- file.path(path, "player_results.csv")

  missing <- c(games_file, players_file)[!file.exists(c(games_file, players_file))]
  if (length(missing) > 0L) {
    stop("load_simulation_results: file(s) not found: ",
         paste(missing, collapse = ", "))
  }

  list(
    games   = read.csv(games_file,   stringsAsFactors = FALSE),
    players = read.csv(players_file, stringsAsFactors = FALSE)
  )
}


# =============================================================================
# Plot: win rates
# =============================================================================

#' Bar chart of win rates by strategy with 95% Wilson confidence interval bars.
#'
#' A horizontal dashed reference line marks the fair-share win rate
#' (1 / number of strategies), i.e. the expected rate if all strategies were
#' equally strong.
#'
#' @param summary Named list returned by summarise_simulation(). Only the
#'   `win_rates` element is used.
#' @return A ggplot object.
plot_win_rates <- function(summary) {
  wr <- summary$win_rates

  # Convert proportions to percentages for axis readability.
  wr$win_pct    <- wr$win_rate * 100
  wr$ci_lo_pct  <- wr$ci_lower * 100
  wr$ci_hi_pct  <- wr$ci_upper * 100

  fair_share_pct <- 100 / nrow(wr)

  # Order bars by win rate descending so the strongest strategy is on the left.
  wr$strategy <- factor(wr$strategy,
                        levels = wr$strategy[order(wr$win_rate, decreasing = TRUE)])

  ggplot(wr, aes(x = strategy, y = win_pct, fill = strategy)) +
    geom_col(width = 0.6) +
    geom_errorbar(aes(ymin = ci_lo_pct, ymax = ci_hi_pct),
                  width = 0.15, colour = "#333333", linewidth = 0.7) +
    geom_hline(yintercept = fair_share_pct,
               linetype = "dashed", colour = "#666666", linewidth = 0.5) +
    annotate("text", x = Inf, y = fair_share_pct,
             label = "fair share", hjust = 1.1, vjust = -0.5,
             size = 3, colour = "#666666") +
    scale_fill_manual(values = STRATEGY_COLORS, guide = "none") +
    scale_y_continuous(limits = c(0, 100),
                       labels = function(x) paste0(x, "%")) +
    labs(
      title = "Win rate by strategy",
      subtitle = paste0("Error bars show 95% Wilson CI  \u00b7  ",
                        sum(wr$wins), " decided games"),
      x = NULL,
      y = "Win rate"
    ) +
    theme_minimal(base_size = 13) +
    theme(panel.grid.major.x = element_blank())
}


# =============================================================================
# Statistical test
# =============================================================================

#' Chi-squared test of win rate equality across strategies.
#'
#' Constructs a wins / losses contingency table from the win_rates data.frame
#' and calls chisq.test(). Stalemate games are already excluded from
#' games_played in summarise_simulation(), so the table only contains decided
#' games.
#'
#' @param summary Named list returned by summarise_simulation(). Only the
#'   `win_rates` element is used.
#' @return Named list with five elements:
#'   - `statistic`:     numeric chi-squared test statistic.
#'   - `df`:            integer degrees of freedom.
#'   - `p_value`:       numeric p-value.
#'   - `significant`:   logical; TRUE when p_value < 0.05.
#'   - `interpretation`: character string suitable for printing, e.g.
#'       "Win rates differ significantly across strategies (χ²=47.2, df=2, p<0.001)."
test_win_rates <- function(summary) {
  wr <- summary$win_rates

  wins   <- wr$wins
  losses <- wr$games_played - wr$wins
  contingency <- rbind(wins = wins, losses = losses)
  colnames(contingency) <- wr$strategy

  result <- chisq.test(contingency)

  p   <- result$p.value
  chi <- round(result$statistic, 1)
  df  <- result$parameter

  p_str <- if (p < 0.001) "p<0.001" else paste0("p=", round(p, 3))

  direction <- if (result$p.value < 0.05) "differ significantly" else "do not differ significantly"
  interpretation <- paste0(
    "Win rates ", direction, " across strategies ",
    "(\u03c7\u00b2=", chi, ", df=", df, ", ", p_str, ")."
  )

  list(
    statistic      = result$statistic,
    df             = result$parameter,
    p_value        = p,
    significant    = p < 0.05,
    interpretation = interpretation
  )
}


# =============================================================================
# Plot: game length
# =============================================================================

#' Density plot of game length (turns) by winner strategy.
#'
#' Stalemates are excluded — they have no winner strategy and would distort the
#' distribution. Stalemate rate is already reported by summarise_simulation().
#'
#' @param sim Named list returned by run_simulation() or
#'   load_simulation_results(). Only the `games` element is used.
#' @return A ggplot object.
plot_game_length <- function(sim) {
  decided <- sim$games[!sim$games$is_stalemate, ]

  decided$strategy <- factor(decided$winner_strategy,
                             levels = names(STRATEGY_COLORS))

  n_decided   <- nrow(decided)
  n_stalemate <- nrow(sim$games) - n_decided

  ggplot(decided, aes(x = turns, colour = strategy, fill = strategy)) +
    geom_density(alpha = 0.2, linewidth = 0.8) +
    scale_colour_manual(values = STRATEGY_COLORS, name = "Winner") +
    scale_fill_manual(  values = STRATEGY_COLORS, name = "Winner") +
    labs(
      title = "Game length by winner strategy",
      subtitle = paste0(n_decided, " decided games  \u00b7  ",
                        n_stalemate, " stalemate(s) excluded"),
      x = "Turns (individual player turns)",
      y = "Density"
    ) +
    theme_minimal(base_size = 13) +
    theme(panel.grid.major.x = element_blank())
}


# =============================================================================
# Plot: VP distribution
# =============================================================================

#' Violin + boxplot of final VP totals by strategy.
#'
#' Uses vp_total (includes hidden VP dev cards) rather than vp_visible.
#' The violin shows the full distribution shape; the overlaid boxplot gives a
#' quick read on median and IQR.
#'
#' @param sim Named list returned by run_simulation() or
#'   load_simulation_results(). Only the `players` element is used.
#' @return A ggplot object.
plot_vp_distribution <- function(sim) {
  players <- sim$players

  # Order strategies by median vp_total descending — same visual logic as
  # plot_win_rates (strongest strategy on the left).
  medians     <- tapply(players$vp_total, players$strategy, median)
  strat_order <- names(sort(medians, decreasing = TRUE))
  players$strategy <- factor(players$strategy, levels = strat_order)

  n_games <- length(unique(players$game_id))

  ggplot(players, aes(x = strategy, y = vp_total, fill = strategy)) +
    geom_violin(trim = TRUE, alpha = 0.55, colour = NA) +
    geom_boxplot(width = 0.15, outlier.shape = NA,
                 fill = "white", colour = "#333333", linewidth = 0.6) +
    scale_fill_manual(values = STRATEGY_COLORS, guide = "none") +
    scale_y_continuous(breaks = seq(0, 10, by = 2)) +
    labs(
      title = "Final VP distribution by strategy",
      subtitle = paste0("vp_total includes VP dev cards  \u00b7  ",
                        n_games, " games"),
      x = NULL,
      y = "VP at game end"
    ) +
    theme_minimal(base_size = 13) +
    theme(panel.grid.major.x = element_blank())
}


# =============================================================================
# Main entry point
# =============================================================================

#' Run the full analysis: produce all plots, run the statistical test, and
#' save figures to disk.
#'
#' Accepts either an in-memory sim list (from run_simulation()) or a directory
#' path string (passed to load_simulation_results()), so it works both
#' inline and post-hoc:
#'
#'   run_simulation(1000, strategies) |> run_analysis()
#'   run_analysis("results")
#'
#' @param sim  Named list returned by run_simulation() / load_simulation_results(),
#'   OR a character string path to the results directory.
#' @param output_dir Directory to write PNG figures into. Created if absent.
#'   Default "figures".
#' @return The summary list from summarise_simulation(), invisibly.
run_analysis <- function(sim, output_dir = "figures") {
  if (is.character(sim)) sim <- load_simulation_results(sim)

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  summary <- summarise_simulation(sim)

  # --- Plots ---
  plots <- list(
    win_rates       = plot_win_rates(summary),
    vp_distribution = plot_vp_distribution(sim),
    game_length     = plot_game_length(sim)
  )

  figure_files <- c(
    win_rates       = "win_rates.png",
    vp_distribution = "vp_distribution.png",
    game_length     = "game_length.png"
  )

  for (nm in names(plots)) {
    path <- file.path(output_dir, figure_files[[nm]])
    ggsave(path, plot = plots[[nm]], width = 8, height = 5.33,
           dpi = 150, units = "in")
    message("Saved ", path)
  }

  # --- Statistical test ---
  test <- test_win_rates(summary)
  message("\n", test$interpretation)

  invisible(summary)
}
