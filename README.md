# ComputeBackend
An R package that provides a consistent interface for running R code locally and on various cluster computing platforms.

Currently supports local serial, local multicore, Condor, PBS, SLURM, and UGE.

I've been using it extensively for my research since 2012, but on your setup it may require some code adjustments to work properly.

#### To install diectly from GitHub:
```
install.packages('devtools')
devtools::install_github('shachark/ComputeBackend')
```
