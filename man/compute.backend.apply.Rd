\name{compute.backend.apply}
\alias{compute.backend.apply}
\title{Compute backend apply function}
\description{
A convenience function that mimics the the behavior of \code{apply} but runs on any platform 
supported by ComputeBackend.
}
\usage{
compute.backend.apply(config, X, MARGIN, FUN, ...)
}
%- maybe also 'usage' for other objects documented here.
\arguments{
  \item{config}{a list with mandatory fields \code{compute.backend}, \code{nr.cores}, and
  \code{rng.seed}. See the help for compute.backend.run.}
  \item{X}{see \code{apply}.}
  \item{MARGIN}{see \code{apply}.}
  \item{FUN}{see \code{apply}.}
  \item{...}{see \code{apply}.}
}
\details{
This functions like the base R \code{apply}, only that each execution of \code{FUN} is a 
ComputeBackend job similar to the \code{processing.func} in \code{compute.backend.run}.
}
\value{
Same as calling \code{apply}.
}
\author{
Shachar Kaufman <shachar.kaufman@gmail.com>
}

\seealso{
\code{\link{apply}}
\code{\link{compute.backend.run}}
}
\examples{
config = list(compute.backend = 'multicore', nr.cores = 3, rng.seed = 123)
X = runif(100)
compute.backend.apply(config, X, 1, sum)
}
