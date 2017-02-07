#!/bin/bash

# NOTE: Currently, this script is not used.

# For reasons unknown, there are automount issues that cause jobs to fail unless
# run preceeded by touching the file.

if (($#<3)); then
  echo "Usage: $0 [job serial number (starts at 0)] [total number of jobs] [path to tmp dir]"
  echo "Example: $0 1 5 /a/home/cc/math/shachark/tmp"
  exit
fi

jobid=$1
nrjobs=$2
workdir=$3

ex=$workdir/cluster_job.r

echo "`date`: Wrapper: Trying to access executable"
echo ""

while [ ! -f $ex ]; do
  echo "`date`: Wrapper: still not accessible"
  ls -la $ex > /dev/null
  sleep 5
done

echo "Wrapper: executable seems to be accessible. Executing..."
echo ""
echo ""

$ex $jobid $nrjobs $workdir
