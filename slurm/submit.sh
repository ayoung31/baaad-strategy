#!/bin/bash
# =============================================================================
# submit.sh
# SLURM submission script for the baaad-strategy Monte Carlo simulation.
#
# Submit with:
#   sbatch slurm/submit.sh
#
# Override defaults at submission time with --export:
#   sbatch --export=ALL,N_GAMES=5000,SEED=99 slurm/submit.sh
# =============================================================================

# -----------------------------------------------------------------------------
# SLURM directives — adjust to match your cluster's limits and queue names.
# -----------------------------------------------------------------------------
#SBATCH --job-name=catan-sim
#SBATCH --output=logs/catan-sim-%j.out   # %j = job ID
#SBATCH --error=logs/catan-sim-%j.err
#SBATCH --ntasks=1                        # single task; parallelism is within R
#SBATCH --cpus-per-task=20                # R workers; tune to your node size
#SBATCH --mem=16G                         # ~2 GB per worker is comfortable
#SBATCH --time=01:00:00                   # 1000 games / 8 cores ≈ 15–20 min;
                                          # 1 h gives headroom for slower boards

# -----------------------------------------------------------------------------
# Simulation parameters — override via --export at submission time.
# -----------------------------------------------------------------------------
N_GAMES=${N_GAMES:-1000}
SEED=${SEED:-42}

# -----------------------------------------------------------------------------
# Environment setup — edit the module name to match your cluster's R install.
# -----------------------------------------------------------------------------
module purge
module load r/4.4.0

# Ensure the logs directory exists (SLURM will not create it for you).
mkdir -p logs

# Print a brief job summary to the log.
echo "========================================"
echo "Job ID    : $SLURM_JOB_ID"
echo "Node      : $SLURM_NODELIST"
echo "CPUs      : $SLURM_CPUS_PER_TASK"
echo "N_GAMES   : $N_GAMES"
echo "SEED      : $SEED"
echo "Started   : $(date)"
echo "========================================"

# -----------------------------------------------------------------------------
# Run the simulation.
# n_cores is passed explicitly; the script also reads SLURM_CPUS_PER_TASK as
# a fallback, but being explicit avoids surprises.
# -----------------------------------------------------------------------------
Rscript scripts/run_simulation_hpc.R "$N_GAMES" "$SLURM_CPUS_PER_TASK" "$SEED"

EXIT_CODE=$?

echo "========================================"
echo "Finished  : $(date)"
echo "Exit code : $EXIT_CODE"
echo "========================================"

exit $EXIT_CODE
