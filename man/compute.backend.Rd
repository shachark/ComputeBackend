\name{compute.backend.run}
\alias{compute.backend.run}
\alias{compute.backend.salvage.cluster.run}
\title{
Compute backend main interface
}
\description{
A consistent interface for running R code locally or on a remote cluster.
}
\usage{
compute.backend.run = function(config, processing.func, 
  package.dependencies = NULL, source.dependencies = NULL, 
  cluster.batch.name = 'unnamed-batch', cluster.dependencies = NULL, 
  cluster.requirements = NULL, this.scratch.root = NULL, 
  cluster.scratch.root = NULL, cluster.submitter.hn = NULL, 
  cluster.submitter.username = NULL, cluster.root = NULL, combine = rbind)

compute.backend.salvage.cluster.run(config, 
  cluster.batch.name = 'unnamed-batch', 
  this.scratch.root = NULL,
  ignore.missing.signals = TRUE)
}
\arguments{
  \item{config}{a list with mandatory fields \code{compute.backend}, \code{nr.cores}, and
  \code{rng.seed}. See Details.}
  \item{processing.func}{a function accepting two arguments: \code{config} and \code{core}. The 
  former is a copy of the \code{config} given to \code{compute.backend.run}, and the latter is
  an integer in \code{1:config$nr.cores} that specifies the serial number of the current 
  segment/core/job to be handled by the function. The function should perform the required processing, 
  using any other fields from \code{config}, and then return an R variable that can be rbinded with 
  the results of other jobs.}
  \item{package.dependencies}{vector with names of packages to call \code{library()} on.}
  \item{source.dependencies}{vector with names of files to call \code{source()} on.}
  \item{cluster.batch.name}{specifies a temporary directory in condor and pbs modes.}
  \item{cluster.dependencies}{either \code{NULL}, or a list of source file names relative to the current
  directory that need to \code{source()}-ed. These will be copied to the cluster system.}
  \item{cluster.requirements}{either \code{NULL}, or a backend-specific requirements string.}
  \item{this.scratch.root}{the path to the batch working directory, as accessed from the 
  machine calling \code{compute.backend.*}.}
  \item{cluster.scratch.root}{the path to the batch working directory, as accessed from the compute 
  node machines.}
  \item{cluster.submitter.hn}{hostname of a machine from which cluster jobs may be launched.}
  \item{cluster.submitter.username}{username of a user with job launching permissions.}
  \item{cluster.root}{home directory of \code{cluster.submitter.username}.}
  \item{combine}{a function is used for combining the output from individual segments/cores/jobs 
  (defaults to \code{rbind}.}
  \item{ignore.missing.signals}{a logical indicating whether missing job completion signals should 
  be ignored.}
}
\details{
NOTE: This documentation is preliminary since the package is currently designed with my own research
needs in mind rather than general public use. See the example below for more details and just follow
it to set yourself up quickly. For deeper details, examine the source code for 
\code{compute.backend.run}. For example, it contains examples on how to set up the \code{cluster.*}
arguments. 

A little about the currently supported backends: \code{serial} just runs a loop calling the 
processing function for each 'core' (which is really just a chunk of computation load in this case).
This is useful for debugging since it runs as regular code in the current R session (so you've got
prints to the console, standard R/Rstudio debugging etcetera). \code{multicore} still runs on the
local machine where you call \code{run.compute.backend} from, but each job runs on a different core.
This uses \code{doParallel} (or really \code{doRNG}) under the hood but give you a coherent 
interface and quick switching between this and the other compute backends. It makes sense in this 
case to not specify more \code{config$nr.cores} than the number of physical (or virtual) cores on
your machine. You can use \code{compute.backend.balance} or your own logic to do load balancing of
more jobs on the fixed number of cores you've got. The cluster backends (\code{condor}, \code{sge},
\code{slurm}, \code{uge}, and \code{pbs}) are named after the job management systems they're meant
to work with. I only actually tested them on very specific clusters (the Condor CS cluster at TAU,
the PBS TAMNUN cluster at the Technion, the SLURM cluster at ICSI, the SGE cluster at UCLA, and the
UGE cluster at UCSF). You may need to tinker with it on other clusters...

The cluster backends also need some additional setup to work with your user accounts. In these 
backends, you have one "launching" machine that runs your main code which calls 
\code{compute.backend.run}. This machine actually logs in with ssh to a cluster headnode (or any
machine that can issue jobs on the cluster). In some configurations, the launching machine and the 
issuing machine can be one and the same, but it can be convenient to edit code and debug on a separate 
launching machine. The launching machine needs to be able to access the "working directory", which
will be the actual working directory for the R session running your \code{processing.func}. So this 
needs to be a directory that's also accessible on the cluster compute nodes and headnode. You will
have to specify the path to this directory on the launching machine and on the cluster (if the 
filesystem is fully shared then these paths will be the same). All important files, such as output
files and logs that you may want to look at from time to time, will be written  to the working
directory. The launching machine has to be able to run \code{ssh} and login this way to the cluster
headnode \emph{without being prompted for a password} (look online on how to set this up). Currently
these modes are only supported on Linux because I gave up on working with SSH from R on Windows. 

It is assumed that either \code{~/.Rprofile} or \code{./.Rprofile} has been set up and takes care
of calling \code{.libPaths()} for setting up the local package path if necessary.
}
\value{
The result of calling \code{combine} on the outputs of individual calls to \code{processing.func}
with each of \code{core = 1:config$nr.cores}.
}
%\references{
%% ~put references to the literature/web site here ~
%}
\author{
Shachar Kaufman <shachar.kaufman@gmail.com>
}
\note{
Please take into account that this thing is a very simplistic framework, only used for my modest 
code written for research projects. It was not intended to be released, and I haven't polished the
rough edges...
}

%% ~Make other sections like Warning with \section{Warning }{....} ~

\seealso{
\code{\link{compute.backend.balance}}
\code{\link{compute.backend.apply}}
}
\examples{
# A simple usage example for ComputeBackend

library (ComputeBackend)

# 1. Define a config structure to share between all jobs
config = list()

# 1.1 This has some mandatory fields

# The first specifies which backend we want to use. 
# Currently supported backends are { serial, multicore, slurm, pbs, condor, uge }
config$compute.backend = 'multicore'

# The second specifies the number of cores (or maybe a more accurate name is jobs) will be run
config$nr.cores = 3

# To get reproducible pseudo random numbers, specify the seed
# Note that reproducibility is only guaranteed within the same backend and the same number of cores
# (so changing the backend may change the random sequence you get).
config$rng.seed = 123

# 1.2 Then you can add whatever other information needed across jobs. Typically stuff like
# constants, file names, and even code (functions) and data (if a replicate kept in memory for
# each job is your thing). These are totally up to you (just don't overwrite the above mandatory 
# fields).

# In this example, we will compute the sum and product of m normal variables, and we will repeat
# this procedure for n independent draws.
config$n = 100
config$m = 150

# 2. Define the function to be run as each single job.
# Jobs are symmetric. But if you need something more complex then you can do this in an additional 
# layer of R logic. 

# The job function has to have the following signature.

compute.job = function(config, core) {
  # Remember that this function may be running on a different node (and specifically, R session)
  # than the one you launch compute.backend.run from, and there is no automatic R session state
  # recreation (except config, which is passed as an argument). So you need to load whatever
  # libraries you need, etc.
  
  library (ComputeBackend) # Here I'm going to call compute.backend.balance so I'm loading ComputeBackend
  
  # If you need, source more of your code (but make sure you specify these files in the call to
  # compute.cackend.run, otherwise they may not be available on a cluster node).
  # source ('more_stuff_you_need.r')
  
  # Here I use the compute.backend.balance to figure out which compute units I want to handle in the
  # specific core/job whose number was given above as an argument. For simplicity, I define here 
  # each draw of m normals as a computation unit.
  idxs.this.core = compute.backend.balance(config$n, config$nr.cores, core)
  nr.idxs.this.core = length(idxs.this.core)
  
  res.core = NULL
  
  for (i in 1:nr.idxs.this.core) {
    cat(date(), 'Working on unit', i, 'of', nr.idxs.this.core, 'this core\n')
    
    dat = rnorm(config$m)
    s = sum(dat)
    p = prod(dat)
    
    # I'm rbinding data.frames in this example, but do note that this can be heavy if you do it many
    # times with big frames. Better to use a simple matrix if possible, or a data.table.
    res.core = rbind(res.core, data.frame(s = s, p = p))
  }
  
  # The current implementation of comptue.backend.run does rbind to combine the results from the
  # different jobs. So what you return must be rbind-able.
  return (res.core)
}

# 3. Let's actually run this thing

res = compute.backend.run(config, compute.job, package.dependencies = c('ComputeBackend'))

print(res)

# If you run on a cluster you may want to specify additional arguments to the above, such as:
# [TODO more explanations (running on a cluster is much more involved)]
# cluster.batch.name = 'Example'
# cluster.dependencies = c('more_stuff_you_need.r')
# cluster.requirements = 'something your cluster understands'
# this.scratch.root = 'working dir path on the computer calling compute.backend.run'
# cluster.root = 'full path of your homedir on the cluster'
# cluster.scratch.root = 'full path to same working dir above, as accessible from cluster compute 
#   nodes'
# cluster.submitter.hn = 'hostname of cluster headnode, should be ssh accessible from the machine 
#   calling compute.backend.run'
# cluster.submitter.username = 'your username on the headnode. You will have to set up 
#   saved public key (password-free) ssh from launching machine to headnode! look it up on the web'

# And then you may need to use this in case of emergency... 
# TODO more explanations
# res = compute.backend.salvage.cluster.run(config, 'Example')
}
% Add one or more standard keywords, see file 'KEYWORDS' in the
% R documentation directory.
%\keyword{ ~kwd1 }
%\keyword{ ~kwd2 }% __ONLY ONE__ keyword per line
