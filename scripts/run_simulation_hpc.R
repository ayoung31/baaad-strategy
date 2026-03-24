#!/usr/bin/env Rscript
# =============================================================================
# run_simulation_hpc.R
# Monte Carlo runner intended for SLURM HPC submission.
#
# Usage:
#   Rscript scripts/run_simulation_hpc.R [n_games] [n_cores] [seed]
#
# Positional arguments (all optional — defaults shown):
#   n_games   Number of games to simulate          (default: 1000)
#   n_cores   Parallel workers                     (default: SLURM_CPUS_PER_TASK, else 1)
#   seed      Integer RNG base seed                (default: 42)
#
# Outputs (written to <project_root>/results/):
#   simulation_results.csv   — one row per game
#   player_results.csv       — one row per player per game
#
# Example — interactive:
#   Rscript scripts/run_simulation_hpc.R 1000 4 42
#
# Example — inside a SLURM job (n_cores picked up from environment):
#   Rscript scripts/run_simulation_hpc.R 1000
# =============================================================================

# -----------------------------------------------------------------------------
# Resolve project root from this script's path so sourcing works regardless
# of the working directory at the time of invocation.
# -----------------------------------------------------------------------------
args_full   <- commandArgs(trailingOnly = FALSE)
file_flag   <- grep("^--file=", args_full, value = TRUE)
script_path <- if (length(file_flag) > 0L) {
  normalizePath(sub("^--file=", "", file_flag))
} else {
  normalizePath(file.path(getwd(), "scripts", "run_simulation_hpc.R"))
}
project_dir <- normalizePath(file.path(dirname(script_path), ".."))

# -----------------------------------------------------------------------------
# Source all modules in dependency order.
# -----------------------------------------------------------------------------
for (f in c("board.R", "player.R", "strategy.R", "game.R", "simulation.R")) {
  source(file.path(project_dir, "R", f))
}

# -----------------------------------------------------------------------------
# Parse positional arguments.
# -----------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)

n_games <- if (length(args) >= 1L) as.integer(args[[1L]]) else 1000L
n_cores <- if (length(args) >= 2L) {
  as.integer(args[[2L]])
} else {
  slurm_cpus <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK")))
  if (!is.na(slurm_cpus)) slurm_cpus else 1L
}
seed <- if (length(args) >= 3L) as.integer(args[[3L]]) else 42L

cat(sprintf(
  "baaad-strategy simulation\n  n_games : %d\n  n_cores : %d\n  seed    : %d\n\n",
  n_games, n_cores, seed
))

# -----------------------------------------------------------------------------
# Define strategies.
# -----------------------------------------------------------------------------
strategies <- list(
  balanced  = balanced_strategy(),
  sheep     = sheep_strategy(),
  ore_grain = ore_grain_strategy()
)

# -----------------------------------------------------------------------------
# Run.
# -----------------------------------------------------------------------------
t_start <- proc.time()

sim <- run_simulation(n_games, strategies,
                      seed    = seed,
                      verbose = TRUE,
                      n_cores = n_cores)

elapsed <- (proc.time() - t_start)[["elapsed"]]
cat(sprintf("Finished in %.1f seconds (%.2f s/game).\n\n",
            elapsed, elapsed / n_games))

# -----------------------------------------------------------------------------
# Persist results.
# -----------------------------------------------------------------------------
results_dir <- file.path(project_dir, "results")
write_simulation_results(sim, path = results_dir)

# -----------------------------------------------------------------------------
# Print summary.
# -----------------------------------------------------------------------------
summary <- summarise_simulation(sim)

cat("\n--- Win rates ---\n")
wr <- summary$win_rates
wr$win_pct  <- round(wr$win_rate  * 100, 1)
wr$ci_lower <- round(wr$ci_lower  * 100, 1)
wr$ci_upper <- round(wr$ci_upper  * 100, 1)
print(wr[order(-wr$win_rate),
         c("strategy", "wins", "games_played", "win_pct", "ci_lower", "ci_upper")],
      row.names = FALSE)

cat(sprintf("\nStalemate rate : %.1f%%\n", summary$stalemate_rate * 100))
cat(sprintf("Mean turns     : %.1f\n",    summary$game_length$mean_turns[
  summary$game_length$winner_strategy == "overall"
]))
