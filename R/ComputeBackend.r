# Main API

compute.backend.run = function(config, processing.func, 
  package.dependencies = NULL, source.dependencies = NULL, 
  cluster.batch.name = 'unnamed-batch', cluster.dependencies = NULL, 
  cluster.requirements = NULL, this.scratch.root = NULL, 
  cluster.scratch.root = NULL, cluster.submitter.hn = NULL, 
  cluster.submitter.username = NULL, cluster.root = NULL, combine = rbind)
{
  if (!is.null(config$rng.seed)) {
    set.seed(config$rng.seed)
  }
  if (!is.null(config$core.rng.seeds)) {
    config$core.rng.seeds = sample(.Machine$integer.max, config$nr.cores, replace = F)
  }
  
  if (!(config$nr.cores > 0)) {
    stop('config$nr.cores has to be an integer greater than 0')
  }
  
  if (config$compute.backend == 'serial') {
    # Compute locally and serially (useful for debugging)
    for (i in seq_along(package.dependencies)) {
      library(package.dependencies[i], character.only = T)
    }
    for (i in seq_along(source.dependencies)) {
      source(source.dependencies[i])
    }

    res = NULL
    for (i in 1:config$nr.cores) {
      set.seed(config$core.rng.seeds[i])      
      res.core = processing.func(config, i)
      res = combine(res, res.core)
    }
  } else if (config$compute.backend == 'multicore') {
    # Compute locally but use multiple cores
    cl = makeCluster(config$nr.cores)
    registerDoParallel(cl)
    
    res = foreach (core = 1:config$nr.cores, .combine = combine, .packages = package.dependencies) %dopar% {
      for (i in seq_along(source.dependencies)) {
        source(source.dependencies[i])
      }
    
      set.seed(config$core.rng.seeds[i])      
      processing.func(config, core)
    }
    
    stopCluster(cl)
  } else if (config$compute.backend %in% c('condor', 'pbs', 'slurm', 'uge')) {
    if (is.null(this.scratch.root) || is.null(cluster.root) || is.null(cluster.scratch.root) || is.null(cluster.submitter.hn) || is.null(cluster.submitter.username) || is.null(cluster.submitter.username)) {
      stop ('Missing cluster configuration')
    }

    # Compute on multiple nodes of a cluster
    res = .submit.cluster.jobs.blocking(
      batch.name = cluster.batch.name, 
      job.input = config,
      job.func = processing.func,
      nr.jobs = config$nr.cores,
      package.dependencies = package.dependencies, 
      source.dependencies = source.dependencies, 
      dependencies = cluster.dependencies,
      requirements = cluster.requirements,
      this.scratch.root = this.scratch.root,
      scratch.root = cluster.scratch.root,
      submitter.hn = cluster.submitter.hn,
      submitter.username = cluster.submitter.username,
      root = cluster.root, 
      combine.function = combine)
  } else {
    stop('Unexpected compute.backend specified')
  }
  
  return (res)
}

# This is a convenience function that mimics the the behavior of "apply"
compute.backend.apply = function(config, X, MARGIN, FUN, ...) {
  #
  # Argument checking, preprocessing, and degenerate cases (copied from "apply")
  #
  
  FUN = match.fun(FUN)
  dl = length(dim(X))
  
  if (!dl) {
    stop("dim(X) must have a positive length")
  }
  
  if (is.object(X)) {
    if (dl == 2L) {
      X = as.matrix(X)
    } else {
      X = as.array(X)
    }
  }
  
  d = dim(X)
  dn = dimnames(X)
  ds = seq_len(dl)
  
  if (is.character(MARGIN)) {
    dnn = names(dn)
    if (is.null(dnn)) {
      stop("'X' must have named dimnames")
    }
    
    MARGIN = match(MARGIN, dnn)
    
    if (anyNA(MARGIN)) {
      stop("not all elements of 'MARGIN' are names of dimensions")
    }
  }
  
  s.call  = ds[-MARGIN]
  s.ans   = ds[ MARGIN]
  d.call  = d [-MARGIN]
  d.ans   = d [ MARGIN]
  dn.call = dn[-MARGIN]
  dn.ans  = dn[ MARGIN]
  
  d2 = prod(d.ans)

  if (d2 == 0L) {
    newX = array(vector(typeof(X), 1L), dim = c(prod(d.call), 1L))
    if (length(d.call) < 2L) {
      ans = FUN(newX[, 1], ...)
    } else {
      ans = FUN(array(newX[, 1L], d.call, dn.call), ...)
    }
    
    if (is.null(ans)) {
      return (ans)
    } else if (length(d.ans) < 2L) {
      return (ans[1L][-1L])
    } else {
      return (array(ans, d.ans, dn.ans))
    }
  }
  
  #
  # Actual work that needs to be parallelized
  #

  config$COMPBACKAPP_newX = aperm(X, c(s.call, s.ans))
  dim(config$COMPBACKAPP_newX) = c(prod(d.call), d2)
  config$COMPBACKAPP_cnt = d2
  config$COMPBACKAPP_args = list(...)
  
  apply.processing.func = function(config, core) {
    idxs.this.core = compute.backend.balance(config$COMPBACKAPP_cnt, config$nr.cores, core)
    nr.idxs.this.core = length(idxs.this.core)
    
    if (nr.idxs.this.core < 1) {
      return (NULL)
    }
    
    ans = vector("list", nr.idxs.this.core)
    
    for (i in 1:nr.idxs.this.core) {
      tmp = do.call(FUN, c(config$COMPBACKAPP_geti(config, idxs.this.core[i]), config$COMPBACKAPP_args))
      if (!is.null(tmp)) {
        ans[[i]] = tmp
      }
    }
    
    return (ans)
  }
  
  if (length(d.call) < 2L) {
    if (length(dn.call))  {
      dimnames(config$COMPBACKAPP_newX) = c(dn.call, list(NULL))
    }
    
    config$COMPBACKAPP_geti = function(config, i) { config$COMPBACKAPP_newX[, i] }
    
    ans = compute.backend.run(config, apply.processing.func, 
      package.dependencies = config$lib.deps, source.dependencies = config$src.deps, 
      cluster.batch.name = config$cluster.batch.name, cluster.dependencies = config$file.deps, 
      cluster.requirements = config$cluster.requirements, combine = c)
  } else {
    config$COMPBACKAPP_d.call = d.call
    config$COMPBACKAPP_dn.call = dn.call
    config$COMPBACKAPP_geti = function(config, i) { array(config$COMPBACKAPP_newX[, i], config$COMPBACKAPP_d.call, config$COMPBACKAPP_dn.call) }
    
    ans = compute.backend.run(config, apply.processing.func, 
      package.dependencies = config$lib.deps, source.dependencies = config$src.deps,                               
      cluster.batch.name = config$cluster.batch.name, cluster.dependencies = config$file.deps, 
      cluster.requirements = config$cluster.requirements, combine = c)
  }
  
  #
  # Post processing (copied from "apply")
  #
  
  ans.list = is.recursive(ans[[1L]])
  l.ans = length(ans[[1L]])
  ans.names = names(ans[[1L]])
  
  if (!ans.list) {
    ans.list = any(unlist(lapply(ans, length)) != l.ans)
  }
  
  if (!ans.list && length(ans.names)) {
    all.same = vapply(ans, function(x) identical(names(x), ans.names), NA)
    if (!all(all.same)) {
      ans.names = NULL
    }
  }
  
  if (!ans.list) {
    ans = unlist(ans, recursive = FALSE)
    len.a = length(ans)
  } else {
    len.a = d2
  }
  
  if (length(MARGIN) == 1L && len.a == d2) {
    if (length(dn.ans[[1L]])) {
      names(ans) = dn.ans[[1L]]
    } else {
      names(ans) = NULL
    }
    return (ans)
  }
  
  if (len.a == d2) {
    return (array(ans, d.ans, dn.ans))
  }
  
  if (len.a && len.a %% d2 == 0L) {
    if (is.null(dn.ans))  {
      dn.ans = vector(mode = "list", length(d.ans))
    }
    
    dn.ans = c(list(ans.names), dn.ans)
    
    if (!all(vapply(dn.ans, is.null, NA))) {
      return (array(ans, c(len.a %/% d2, d.ans), dn.ans))
    } else {
      return (array(ans, c(len.a %/% d2, d.ans), NULL))
    }
  }
  
  return (ans)  
}

# In the "condor" and "pbs" backends I'm splitting the units across condor 
# jobs, each job runs the code in the file job.r (this needs to be with 
# execution priviliges).

# NOTES (on top of what's written above in this file):
#
# - The batch.name parameter will be used as the name for the temporary 
#   directory used by all jobs so it should be a legal dir name that the excuting
#   user has permissions to create.
# - job.input can be anything (usually a list with all the stuff the processing 
#   function needs to work on.
# - nr.jobs is the nubmer of jobs to submit. Jobs will be handed a serial number
#   argument running from 0 to (nr.jobs - 1).
# - this.scratch.root and cluster.scratch.root are paths to the same physical 
#   directory where all temporary batch files will be put. this.scratch.root is
#   the path accesible from the machine running the present function. 
#   cluster.scratch.root is the path to the same direcotry, but as accessed from
#   the cluster nodes. "/batch.name" is appended to both, and this dir is created
#   if it does not already exist.
# - The default submitter is TAU CS nova (condor), and uses my username.
#   I have set up a password-free SSH connection from the machines I usueally
#   run this code (namely, my office PC and the CS RSdtudio VM).
#
# It's not a reliable implementation... if jobs are suspended or killed this
# will get stuck waiting for completion (it can be easily interrupted from R
# but the user will not get any notification). On the other hand, if there is
# an R error in the processing job itself, this will be caught and reported.

.submit.cluster.jobs.blocking = function(batch.name, job.input, job.func, nr.jobs, 
  package.dependencies, source.dependencies, 
  dependencies, requirements = NULL, this.scratch.root, scratch.root,
  submitter.hn, submitter.username, root, combine.function = rbind)
{
  # 1. Define the temporary directory used by all jobs
  tmpdir.this = sprintf('%s/%s', this.scratch.root, batch.name)
  tmpdir.cluster = sprintf('%s/%s', scratch.root, batch.name)
  
  # Create it and clear any garbage from previous runs (deletes files!!!)
  dir.create(tmpdir.this, showWarnings = F)
  dir.create(sprintf('%s/seed-results', tmpdir.this), showWarnings = F)
  system(sprintf('rm %s/*signal.RData', tmpdir.this))
  
  # 2. Save config so that all jobs will be able to read it
  save(job.input, job.func, package.dependencies, source.dependencies, 
       file = sprintf('%s/jobinput.RData', tmpdir.this))
  
  # 3. Generate a cluster job submission file
  job.submission.filename = 'submit-all.job'
  job.executable = 'cluster_job.r'
  job.min.ram = 512 # MB
  nr.jobs = nr.jobs

  if (config$compute.backend == 'condor') {
    pnrstr = '$(Process)'
    envstr =  sprintf('HOME=%s', root)
    actual.job.executable = job.executable # 'condor_rscript_wrapper.sh'
    
    if (is.null(requirements)) {
      requirements = paste('FreeMemoryMB >= ', job.min.ram, sep = '')
    }
    
    cat(file = sprintf('%s/%s', tmpdir.this, job.submission.filename), sep = '',
      'Universe     = vanilla'                                          , '\n',
      'Executable   = ', tmpdir.cluster, '/', actual.job.executable     , '\n',
      'Environment  = \"', envstr, '\"'                                 , '\n',
      'Arguments    = ', pnrstr, ' ', nr.jobs, ' ', tmpdir.cluster      , '\n',
      'Initialdir   = ', tmpdir.cluster                                 , '\n',
      'Log          = job-', pnrstr, '.log'                             , '\n',
      'Output       = job-', pnrstr, '.out'                             , '\n',
      'Error        = job-', pnrstr, '.error'                           , '\n',
      'Requirements = ', requirements                                   , '\n',
      'Rank         = Memory'                                           , '\n', # LoadAvg
      'Notification = Never'                                            , '\n',
      'Queue ', nr.jobs)
    
    exec.fullpath = system.file(paste('exec/relaunch_jobs.r', sep = ''), package = 'ComputeBackend')
    system(sprintf('install %s %s/relaunch_jobs.r', exec.fullpath, tmpdir.this))
    system(sprintf('dos2unix %s/relaunch_jobs.r', tmpdir.this))
    #exec.fullpath = system.file(paste('exec/condor_rscript_wrapper.sh', sep = ''), package = 'ComputeBackend')
    #system(sprintf('install %s %s/condor_rscript_wrapper.sh', exec.fullpath, tmpdir.this))
    #system(sprintf('dos2unix %s/condor_rscript_wrapper.sh', tmpdir.this))
  } else if (config$compute.backend == 'pbs') {
    cat(file = sprintf('%s/%s', tmpdir.this, job.submission.filename), sep = '',
      '#!/bin/bash', '\n',
      '#PBS -N ', batch.name, '\n',
      '#PBS -q all_l_p', '\n',
     #'#PBS -M your@email.here', '\n', # FIXME at some point I'll have to make this a parameter too
      '#PBS -m n', '\n',
      '#PBS -l select=1:ncpus=1', '\n',
      '#PBS -V\n',
      '\n',
      'PBS_O_WORKDIR=', tmpdir.cluster, '\n',
      'cd $PBS_O_WORKDIR', '\n',
      './', job.executable, ' $job_serial ', nr.jobs, ' ', tmpdir.cluster, '\n')
    
    exec.fullpath = system.file(paste('exec/pbs_job_submitter.sh', sep = ''), package = 'ComputeBackend')
    system(sprintf('install %s %s/pbs_job_submitter.sh', exec.fullpath, tmpdir.this))
    system(sprintf('dos2unix %s/pbs_job_submitter.sh', tmpdir.this))
  } else if (config$compute.backend == 'uge') {
    if (is.null(requirements)) {
      requirements = 'h_data=1024M,h_rt=1:00:00,highp'
    }
    
    cat(file = sprintf('%s/%s', tmpdir.this, job.submission.filename), sep = '',
      '#!/bin/csh -f', '\n',
      '#$ -cwd', '\n',
      '#$ -o ', tmpdir.cluster, '/job-$JOB_ID.log', '\n',
      '#$ -j y', '\n',
      '#$ -l ', requirements, '\n',
      '#$ -q eeskin_*.q', '\n',
      '#$ -v QQAPP=Rscript', '\n',
     #'#PBS -M your@email.here', '\n', # FIXME at some point I'll have to make this a parameter too
      '#$ -m n', '\n',
      '#$ -r n', '\n',
      '\n',
      'unalias *', '\n',
      '\n',
      'set qqversion =', '\n',
      'set qqapp     = "R serial"', '\n',
      'set qqidir    = ', tmpdir.cluster, '\n',
      'set qqjob     = Unified', '\n',
      'set qqodir    = ', tmpdir.cluster, '\n',
      '\n',
      'cd ', tmpdir.cluster, '\n',
      'source /u/local/bin/qq.sge/qr.runtime', '\n',
      'if ($status != 0) exit (1)', '\n',
      '\n',
      '#', '\n',
      '# Run the user program', '\n',
      '#', '\n',
      'source /u/local/Modules/default/init/modules.csh', '\n',
      'module load R', '\n',
      'module li', '\n',
      '\n',
      'echo "This is actually job serial $job_serial"', '\n',
      'Rscript ', tmpdir.cluster, '/', job.executable, ' $job_serial ', nr.jobs, ' ', tmpdir.cluster, '\n',
      '\n',
      '#\n',
      '# Cleanup after serial execution\n',
      '#\n',
      'source /u/local/bin/qq.sge/qr.runtime\n',
      'exit (0)', '\n')
    
    exec.fullpath = system.file(paste('exec/pbs_job_submitter.sh', sep = ''), package = 'ComputeBackend')
    system(sprintf('install %s %s/pbs_job_submitter.sh', exec.fullpath, tmpdir.this))
    system(sprintf('dos2unix %s/pbs_job_submitter.sh', tmpdir.this))
  } else if (config$compute.backend == 'slurm') {
    # TODO: may need to add these switched to the job issue command
    # 1. for multiple cores per job: "--c"
    # 2. for more than the default 2GB memory limit: "--mem XXXX_in_BM"
    # 3. for more time than the maximum allowed by default (?): -t h:m:s.

    if (is.null(requirements)) {
      requirements = '-k'
    }
    
    cat(file = sprintf('%s/%s', tmpdir.this, job.submission.filename), sep = '',
        '#!/bin/bash', '\n',
        '#SBATCH -J ', batch.name, '\n',
      # '#SBATCH -D ', tmpdir.cluster, '\n',
        '#SBATCH -p bioinfo', '\n',
      # '#SBATCH -w "pasta[1-2],mussel[1-2]"', '\n',
        '#SBATCH ', requirements, '\n',
        '\n',
        'if (($#<1)); then\n',
        '  echo "Usage: $0 [job serial]"\n',
        '  echo "Example: $0 50"\n',
        '  exit\n',
        'fi\n',
        '\n',
        'job_serial=$1\n',
        '\n',
        'cd ', tmpdir.cluster, '\n',
        'Rscript cluster_job.r $job_serial ', nr.jobs, ' ', tmpdir.cluster, '\n')
    
    exec.fullpath = system.file(paste('exec/slurm_job_submitter.sh', sep = ''), package = 'ComputeBackend')
    system(sprintf('install %s %s/slurm_job_submitter.sh', exec.fullpath, tmpdir.this))
    system(sprintf('dos2unix %s/slurm_job_submitter.sh', tmpdir.this))
  }
  
  # Copy the executable and dependencies to the temp dir
  exec.fullpath = system.file(paste('exec/', job.executable, sep = ''), package = 'ComputeBackend')
  system(sprintf('install %s %s/%s', exec.fullpath, tmpdir.this, job.executable))
  system(sprintf('dos2unix %s/%s', tmpdir.this, job.executable))
  
  for (dpn in dependencies) {
    system(sprintf('install %s %s/%s', dpn, tmpdir.this, dpn))
    # (no dos2unix or other prosessing - users will have to take care of their own)
  }
  
  # 5. Now I need to ssh to the headnode and submit the above using the job 
  # management system.

  # No need for password, I've set up the headnode to recognize the (virtual) 
  # machine running R/RStudio (the id of the machine changes when it dies, so 
  # this occasionally needs to be removed from ~/.ssh/authorized_keys and re-added.
  #system('ssh-keygen -t rsa -f id_rsa -P \'\'')
  #system('cat id_rsa.pub >> ~/.ssh/authorized_keys')
  #unlink('id_rsa')

  if (config$compute.backend == 'condor') {
    cmd.retval = system(command = paste(sep = '', 'ssh -T -o "ForwardX11 no" ', 
      submitter.username, '@', submitter.hn, ' "cd ', tmpdir.cluster,
      '; condor_submit ', job.submission.filename, '"')) #'; condor_reschedule"'))
  } else if (config$compute.backend == 'pbs' || config$compute.backend == 'uge') {
    cmd.retval = system(command = paste(sep = '', 'ssh -T -o "ForwardX11 no" ', 
      submitter.username, '@', submitter.hn, ' "cd ', tmpdir.cluster,
      '; ./pbs_job_submitter.sh ', batch.name, ' ', nr.jobs, '"'))
  } else if (config$compute.backend == 'slurm') {
    cmd.retval = system(command = paste(sep = '', 'ssh -T -o "ForwardX11 no" ', 
      submitter.username, '@', submitter.hn, ' "cd ', tmpdir.cluster,
      '; ./slurm_job_submitter.sh ', nr.jobs, '"'))
  }

  # 6. Then I need to poll for signal files until all jobs are done.

  cat(date(), ': Waiting for', nr.jobs, 'jobs to finish\n')
  pending.jobs = 1:nr.jobs

  rls.cntr = 0
  while (length(pending.jobs) > 0) {
    Sys.sleep(10)
    
    jobs.to.remove = NULL
    
    for (i in pending.jobs) {
      if (file.exists(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1))) {
        .load.robust(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1)) # => signal
        if (!is.null(signal)) {
          cat(date(), ': Job', i, 'completed WITH ERROR; rerun with relaunch_jobs\n')
          unlink(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1))          
        } else {
          jobs.to.remove = c(jobs.to.remove, which(pending.jobs == i))
          cat(date(), ': Job', i, 'completed OK (', length(pending.jobs) - length(jobs.to.remove), 'jobs remaining )\n')
        }
      }
    }
    
    if (!is.null(jobs.to.remove)) {
      pending.jobs = pending.jobs[-jobs.to.remove]
    }
    
    ## Often some nodes are problematic, and will cause jobs to get stuck in 
    ## condor mode "H" (held). So I can try and release them. Not sure if this 
    ## is the best solution.
    #if (rls.cntr < 10) {
    #  rls.cntr = rls.cntr + 1
    #  cmd.retval = system(command = paste(sep = '', 'ssh -T -o "ForwardX11 no" ', 
    #    condor.submitter.username, '@', condor.submitter.hn, ' "condor_release ', condor.submitter.username, '"'))
    #}
  }
  
  # 7. Finally, I need to read the output files, and combine the output.

  cat(date(), ': Loading and combining job outputs\n')
  res = NULL
  
  for (i in 1:nr.jobs) {
    if (!.file.exists.robust(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1))) {
      cat('The output files for job', i, 'were there, but now for some reason they are not?! Skipping...\n')
      next
    }
    
    .load.robust(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1)) # => signal
    if (is.null(signal)) {
      cat('Job', i, 'ok\n')
      #unlink(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1))
      .load.robust(sprintf('%s/job-%g-out.RData', tmpdir.this, i - 1)) # => res.job
      res = combine.function(res, res.job)
    } else {
      cat('Job', i, 'failed with error:\n  ', paste(signal))
    }
  }
  
  return (res)
}

compute.backend.salvage.cluster.run = function(config, 
  cluster.batch.name = 'unnamed-batch', 
  this.scratch.root = NULL,
  ignore.missing.signals = T)
{
  nr.jobs = config$nr.cores
  tmpdir.this = sprintf('%s/%s', this.scratch.root, cluster.batch.name)
  nr.fs.retries = 3
  
  cat(date(), ': Loading and combining job outputs\n')
  res = NULL
  
  for (i in 1:nr.jobs) {
    if (!.file.exists.robust(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1), nr.fs.retries)) {
      if (ignore.missing.signals) {
        cat('The output signal file for job', i, 'is missing, but I will ignore this\n')
        signal = NULL
      } else {
        cat('The output files for job', i, 'where there, but now for some reason they are not?! Skipping...\n')
        next
      }
    } else {
      .load.robust(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1)) # => signal
      
      if (is.null(signal)) {
        cat('Job', i, 'ok (so I am removing the signal file)\n')
        #unlink(sprintf('%s/job-%g-signal.RData', tmpdir.this, i - 1))
      } else {
        cat('Job', i, 'failed with error:\n  ', paste(signal))
        next
      }
    }
  
    if (!.file.exists.robust(sprintf('%s/job-%g-out.RData', tmpdir.this, i - 1), nr.fs.retries)) {
      cat('The output data file for job', i, 'does not exist. Skipping...\n')
      next
    }
        
    .load.robust(sprintf('%s/job-%g-out.RData', tmpdir.this, i - 1)) # => res.job
    res = combine.function(res, res.job)
  }
  
  return (res)
}

# I'm experiencing weird issues in accessing the mounted CS filesystems, and so
# need the below
.file.exists.robust = function(filename, nr.retries = 3) {
  sucss = F
  rtrc = 0
  
  while (!sucss & rtrc < nr.retries) {
    rtrc = rtrc + 1
  
    if (!file.exists(filename)) {
      if (rtrc < nr.retries) {
        Sys.sleep(1)
      }
    } else {
      sucss = T
      break
    }
  }
  
  return (sucss)
}

.load.robust = function(file, envir = parent.frame(), verbose = F, nr.retries = 3) {
  rtrc = 0
  
  while (T) {
    rtrc = rtrc + 1

    res = NULL
    try ({res = load(file, envir, verbose)})
    sucss = !is.null(res) && !inherits(res, 'try-error')
    
    if (sucss) {
      break
    } else if (rtrc < nr.retries) {
      Sys.sleep(1)
    } else {
      break
    }
  }
  
  return (res)
}

# This is often useful for balancing work accross cores
compute.backend.balance = function(nr.units, nr.cores, core = NULL) {
  d = rep(floor(nr.units / nr.cores), nr.cores)
  rem = nr.units %% nr.cores
  if (rem > 0) {
    d[1:rem] = d[1:rem] + 1
  }
  
  if (is.null(core)) {
    ret = list()
    u = 0
    for (i in 1:nr.cores) {
      if (d[i]) {
        ret[[i]] = (u + 1):(u + d[i])
        u = u + d[i]
      } else {
        ret[[i]] = rep(0, 0)
      }
    }
  } else {
    if (d[core] == 0) {
      ret = NULL
    } else {
      dc = c(0, cumsum(d))
      ret = dc[core] + (1:d[core])
    }
  }
  
  return (ret)
}
