\name{ComputeBackend-package}
\alias{ComputeBackend-package}
\docType{package}
\title{Compute Backend}
\description{Gives a consistent interface for computing serially (with easy debugging), local multicore, or on various cluster job management systems.}
\details{
\tabular{ll}{
Package: \tab ComputeBackend\cr
Type: \tab Package\cr
Version: \tab 1.0\cr
Date: \tab 2013-04-23\cr
License: \tab GPL-2\cr
}
The main functions are compute.backend.run or compute.backend.apply.
}
\author{
Shachar Kaufman <shachar.kaufman@gmail.com>
}
%\references{
%Nothing at this point.
%}
%\seealso{
%GridR.
%}
\examples{
  # See a more detailed and hopefully useful example under compute.backend.run
  
  config = list()
  config$compute.backend = 'serial'
  config$nr.cores = 10
  config$rng.seed = 123
  processing.func = function(config, core) { cat('Running job', core, '\n') }
  compute.backend.run(config, processing.func)
}
