#!/bin/bash

# For use with SLURM: sbatch each job

if (($#<1)); then
  echo "Usage: $0 [total number of jobs]"
  echo "Example: $0 50"
  exit
fi

nr_jobs=$1

for jobi in `seq 1 $nr_jobs`; do
  let job_serial=jobi-1
  sbatch submit-all.job $job_serial
done

