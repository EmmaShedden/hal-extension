#!/usr/bin/env bash
# Run an analysis R script in the fa26-hal env with single-threaded BLAS per worker process
# (scripts parallelize across fits with mclapply; multithreaded OpenBLAS in each worker oversubscribes the CPU).
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
exec /home/eshedden/miniconda3/envs/fa26-hal/bin/Rscript "$@"
