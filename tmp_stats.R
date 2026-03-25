source("R/board.R")
source("R/player.R")
source("R/strategy.R")
source("R/game.R")
source("R/simulation.R")
source("R/analysis.R")

sim <- load_simulation_results("results")
s   <- summarise_simulation(sim)
wr  <- s$win_rates

# Run chi-squared test directly on observed win counts
observed <- wr$wins
names(observed) <- wr$strategy
n_games  <- sum(observed)
expected <- rep(n_games / length(observed), length(observed))

result <- chisq.test(observed)

cat("=== Win Rates ===\n")
for (i in seq_len(nrow(wr))) {
  cat(sprintf("  %-10s  %d/%d  (%.1f%%)  95%% CI [%.1f%%, %.1f%%]\n",
    wr$strategy[i], wr$wins[i], n_games,
    wr$win_rate[i] * 100,
    wr$ci_lower[i] * 100,
    wr$ci_upper[i] * 100))
}

cat("\n=== Chi-Squared Test ===\n")
cat(sprintf("  H0: all strategies win equally often (expected %.1f wins each)\n", expected[1]))
cat(sprintf("  Observed: balanced=%d, ore_grain=%d, sheep=%d\n",
  observed["balanced"], observed["ore_grain"], observed["sheep"]))
cat(sprintf("  chi-sq = %.2f,  df = %d,  p-value = %s\n",
  result$statistic, result$parameter,
  format.pval(result$p.value, digits = 4, eps = 1e-10)))
cat(sprintf("  Significant at p < 0.05: %s\n",
  ifelse(result$p.value < 0.05, "YES", "NO")))
