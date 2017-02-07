\name{compute.backend.balance}
\alias{compute.backend.balance}
\title{
Divide workload units to jobs as evenly as possible.
}
\description{
This is often useful for balancing symmetric atoms of workload accross symmetric cores / nodes.
}
\usage{
compute.backend.balance(nr.units, nr.cores, core = NULL)
}
\arguments{
  \item{nr.units}{The number of workload atoms that you want to compute overall. Atoms are assumed 
  symmetric.}
  \item{nr.cores}{The number of cores you are going to provide compute.backend.run}
  \item{core}{A specific job number}
}
\details{
Simple utility. If you have assymetric nodes and/or jobs you may want to do more sophisticated load 
balancing.
}
\value{
When \code{core} is not provided (which is the default case), a list is returned, with one vector of
unit indexes per core. If \code{core} is provided, the vector of indexes of 
compute units that should be handled on this specific core is returned.
}
%\references{
%% ~put references to the literature/web site here ~
%}
\author{
Shachar Kaufman
}
%\note{
%%  ~~further notes~~
%}

%% ~Make other sections like Warning with \section{Warning }{....} ~

\seealso{
\code{\link{compute.backend.run}}
}

\examples{
  # Say we want to compute 100 equal computation chunks, on 7 cores/jobs. 
  # Then the following returns the chunk indexs (in 1:100) that should be run as job number 5 (of
  # the 7 jobs overall) so that the load is roughly balanced.
  
  units.to.run.on.core.5 = compute.backend.balance(nr.units = 100, nr.cores = 7, core = 5)
}

% Add one or more standard keywords, see file 'KEYWORDS' in the
% R documentation directory.
%\keyword{ ~kwd1 }
%\keyword{ ~kwd2 }% __ONLY ONE__ keyword per line
