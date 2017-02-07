#!/bin/bash

# For use with PBS: qsub each job

if (($#<2)); then
  echo "Usage: $0 [cluster batch name] [total number of jobs]"
  echo "Example: $0 HHG 50"
  exit
fi

cluster_batch_name=$1
nr_jobs=$2

for jobi in `seq 1 $nr_jobs`; do
  let job_serial=jobi-1
  qsub -N $cluster_batch_name-$job_serial -V -v job_serial=$job_serial submit-all.job
done

