#!/usr/bin/Rscript

options(warn = 1)

args = commandArgs(TRUE)

warning('REMINDER: job serials are 1-based, but job output files are 0-based')

if (length(args) == 0 || length(args) %% 2 != 0) {
  stop('Usage: [-r "overriding cluster requirements"] [-jf "filename with one job serial per line"] [-jr "R code that defines the serials of jobs to be rerun"]')
}

load(file = 'jobinput.RData') # => job.input, job.func
total.nr.jobs = job.input$nr.cores
requirements = job.input$cluster.requirements
wdstr = strsplit(getwd(), '/')
batch.name = wdstr[[1]][length(wdstr[[1]])]

for (ai in seq(1, length(args), by = 2)) {
  if (args[ai] == '-r') {
    requirements = args[ai + 1]
  } else if (args[ai] == '-jf') {
    job.numbers = read.table(args[ai + 1], header = F)$V1
    if (length(job.numbers) == 0) {
      stop('No job serials found in given file')
    }
  } else if (args[ai] == '-jr') {
    job.numbers = eval(parse(text = args[ai + 1]))
  } else {
    stop('Unexpected argument switch')
  }
}

nr.jobs = length(job.numbers)
cat('Launching', nr.jobs, 'jobs:\n')

for (i in 1:nr.jobs) {
  cat('Job', job.numbers[i], '\n')
    
  if (job.input$compute.backend == 'pbs') {
    system(sprintf('qsub -N %s-%g -V -v job_serial=%g submit-all.job', 
                   batch.name, job.numbers[i] - 1, job.numbers[i] - 1))
  } else if (job.input$compute.backend == 'condor') {
    tmpdir = getwd()
    job.submission.filename = 'relaunch.job'
    job.executable = 'cluster_job.r' #'condor_rscript_wrapper.sh'
    envstr = paste('HOME=', Sys.getenv('HOME'), sep ='')
    
    cat(file = sprintf('%s/%s', tmpdir, job.submission.filename), sep = '',
        'Universe     = vanilla'                                    , '\n',
        'Executable   = ', tmpdir, '/', job.executable              , '\n',
        'Environment  = \"', envstr, '\"'                           , '\n',
        'Arguments    = ', job.numbers[i], ' ', total.nr.jobs, ' ', tmpdir, '\n',
        'Log          = ', tmpdir, '/job-', job.numbers[i], '.log'  , '\n',
        'Output       = ', tmpdir, '/job-', job.numbers[i], '.out'  , '\n',
        'Error        = ', tmpdir, '/job-', job.numbers[i], '.error', '\n',
        'Requirements =' , requirements                             , '\n',
        'Rank         = LoadAvg'                                    , '\n',
        'Notification = Never'                                      , '\n',
        'Queue')
  
    system(command = paste('condor_submit', job.submission.filename))
  } else {
    stop('Unexpected compute.backend in config file')
  }
}

cat('Done\n')
