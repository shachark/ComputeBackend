#!/usr/bin/Rscript
# NOTE: you may want to change the above if your Rscript is located in a non-standard location.

# This RScript is one cluster job in a larger simulation defined elsewhere.

library('base', 'stats', 'utils', 'methods')

signal = NULL

args = commandArgs(T)

if (length(args) != 3) {
  stop('Usage: cluster_job.r [job serial number (starts at 0)] [total number of jobs] [path to tmp dir]')
}

job.number = as.numeric(args[1])
nr.jobs = as.numeric(args[2])
tmpdir = args[3]

cat('Job started with arguments:\n')
cat('   job number .............', job.number, '\n')
cat('   total number of jobs ...', nr.jobs, '\n')
cat('   tmpdir path ............', tmpdir, '\n\n')

tryCatch(expr = {
  setwd(tmpdir)
  load(file = 'jobinput.RData') # => job.input, job.func, package.dependencies, source.dependencies

  for (i in seq_along(package.dependencies)) {
    library(package.dependencies[i], character.only = T)
  }
  for (i in seq_along(source.dependencies)) {
    source(source.dependencies[i])
  }
  
  set.seed(job.input$cluster.rng.seeds[job.number + 1])
  res.job = job.func(job.input, job.number + 1)
  save(res.job, file = sprintf('job-%g-out.RData', job.number))
  
  # If requested, save another copy of the results under the given random seed
  if (!is.null(job.input$save.per.seed) && job.input$save.per.seed) {
    save(res.job, file = sprintf('seed-results/%g.RData', job.input$cluster.rng.seeds[job.number + 1]))
  }
}, error = function(e) {
  assign("signal", e, envir = .GlobalEnv)
  cat(paste(signal), '\n')
  traceback()
}, finally = {
  save(signal, file = sprintf('job-%g-signal.RData', job.number))
  if (is.null(signal)) {
    cat('Job done without errors.\n')
  } else {
    cat('Job done with errors.\n')
  }
})
