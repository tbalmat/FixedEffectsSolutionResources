# Duke University Synthetic Data Project
# Data Simulation and Time Trials for Fixed Effects Modeling
# Author:  Tom Balmat
# Date:    May 2017

options(max.print=1000)      # number of elements, not rows
options(stringsAsFactors=F)
options(scipen=999999)

library(ggplot2)

setwd("\\\\SSRI-NAS-FE01.oit.duke.edu\\SSRI\\OPM\\Users\\Current\\tjb48\\Analysis\\FixedEffectsModel\\LargeModelSolutionComparison")

####
#### utilities
####

thousandsFormat <- function(x) {
  # format elements of x by comma delimited thousands
  # note that, of course, the return value is a character vector
  # convert spaces to "" in supplied value
  y <- rep("", length(x))
  for(i in 1:length(x)) {
    x0 <- gsub(" ", "", as.character(x[i]))
    xl <- nchar(x0)
    # while three byte triplets exist prepend final three and prefix with a comma
    while(xl>3) {
      # prepend a comma and final three digits
      y[i] <- paste(",", substring(x0, xl-2, xl), y[i], sep="")
      # right truncate three digits
      x0 <- substring(x0, 1, xl-3)
      xl <- xl-3
    }
    # prepend any remaining digits
    y[i] <- paste(x0, y[i], sep="")
  }
  return(y)
}

#####################################################################################################
#### simulated fixed effects test data generation
#####################################################################################################

feTestData <- function(n, nlv3, nlv4, nlv5) {
 
  # model:  Y = b0 + b1X1 + b2X2 + b3iX3i + b4jX4j + b5kX5k + e~N(0, evar)

  # function parameters:
  # n ..... number of observations to generate
  # nlv3 .. number of levels to generate for fixed effect 3
  # nlv4 .. number of levels to generate for fixed effect 4
  # nlv5 .. number of levels to generate for fixed effect 5

  # static parameters (modify as needed)
  # b0 .... intercept
  # b1 .... coefficient of X1
  # X1 .... vector of equally weighted values to sample for X1
  # b2 .... coefficient of X2
  # X2 .... vector of equally weighted values to sample for X2
  # b3 .... vector of X3 fixed effect coefficients (length(b3) equally weighted levels will be generated)
  # b4 .... vector of X4 fixed effect coefficients (length(b4) equally weighted levels will be generated)
  # b5 .... number of X5 fixed effect coefficients (length(b5) equally weighted levels will be generated)
  # evar .. variance of normally distributed errors
  b0 <- 10.333
  b1 <- 2.3
  X1 <- sample(seq(2, 4, 0.01), n, replace=T)
  b2 <- 5.5
  X2 <- sample(seq(3, 5, 0.01), n, replace=T)
  b3 <- sample(seq(0.5, 2.5, 2/nlv3)[1:nlv3])
  X3 <- sample(1:length(b3), n, replace=T)
  b4 <- sample(seq(2.5, 5, 2.5/nlv4)[1:nlv4])
  X4 <- sample(1:length(b4), n, replace=T)
  b5 <- sample(seq(5, 7.5, 2.5/nlv5)[1:nlv5])
  X5 <- sample(1:length(b5), n, replace=T)
  evar <- 10

  # set reference level coefficients to 0 so that b0 and ref levels unconfounded
  # this enables comparison of estimate b0 to known b0
  b3[1] <- 0
  b4[1] <- 0
  b5[1] <- 0

  # generate simulated indepent and calculated dependent values
  data.frame("Y" = rep(b0, n) + b1*X1 + b2*X2 + b3[X3] + b4[X4] + b5[X5] + rnorm(n, 0, evar),
             "X1"=X1, "X2"=X2,
             "X3"=sprintf("%05.0f", X3), "X4"=sprintf("%05.0f", X4), "X5"=sprintf("%05.0f", X5))
       
}

#################################################################################################
#### model fitting functions, one for each method being evaluated
#################################################################################################

####
#### method:  lm()
####

feSolution_lm <- function(data, subsetn=NULL) {

  # fit linear fixed effects model using lm()

  # parameters:
  # data ...... source data with vectors Y, X1, X2, X3, X4, X5 (X1, X2 continuous; X3, X4, X5 FE levels)
  # subsetn ... number of observations to fit per update cycle (useful for when data has more
  #             observations than lm() can accomodate in a single pass)

  # note that fixed effect parameter estimates are valid only when all fixed effect levels appear in
  # every subset of data

  # convert fixed effects to factors
  data <- data.frame(data[,c("Y", "X1", "X2")],
                     "X3"=factor(data[,"X3"]), "X4"=factor(data[,"X4"]), "X5"=factor(data[,"X5"]))

  # configure observation boundaries for first subset
  nobs <- nrow(data)
  if(is.null(subsetn))
    subsetn <- nobs
  obsid0 <- 1
  obsid1 <- min(obsid0+subsetn, nobs)

  t <- proc.time()

  # fit first subset
  m <- lm(Y~X1+X2+X3+X4+X5, data=data[obsid0:obsid1,])

  # fit remaining subsets, if any
  while(obsid1<nobs) {
    # update obs boundaries
    obsid0 <- obsid1+1
    obsid1 <- min(obsid0+subsetn, nobs)
    update(m, Y~X1+X2+X3+X4+X5, data=simDat[obsid0:obsid1,])
  }

  # return vector of results: execution time, intercept, continuous parameter estimates,
  # and estimates of first five levels of each FE
  c(m$coef[c(1, 2, 3, which(substr(names(m$coef), 1, 2)=="X3")[1:5],
                      which(substr(names(m$coef), 1, 2)=="X4")[1:5],
                      which(substr(names(m$coef), 1, 2)=="X5")[1:5])], (proc.time()-t)[1:3])

}

####
#### method: biglm()
####

feSolution_biglm <- function(data, subsetn=NULL) {

  # fit linear fixed effects model using biglm()

  # parameters:
  # data ...... source data with vectors Y, X1, X2, X3, X4, X5 (X1, X2 continuous; X3, X4, X5 FE levels)
  # subsetn ... number of observations to fit per update cycle (useful for when data has more
  #             observations than biglm() can accomodate in a single pass)

  # note that fixed effect parameter estimates are valid only when all fixed effect levels appear in
  # every subset of data

  library(biglm)

  # convert fixed effects to factors
  data <- data.frame(data[,c("Y", "X1", "X2")],
                     "X3"=factor(data[,"X3"]), "X4"=factor(data[,"X4"]), "X5"=factor(data[,"X5"]))

  # configure observation boundaries for first subset
  nobs <- nrow(data)
  if(is.null(subsetn))
    subsetn <- nobs
  obsid0 <- 1
  obsid1 <- min(obsid0+subsetn, nobs)

  t <- proc.time()

  # fit first subset
  m <- biglm(Y~X1+X2+X3+X4+X5, data=data[obsid0:obsid1,])

  # update model with remaining subsets
  while(obsid1<nobs) {
    # update obs boundaries
    obsid0 <- obsid1+1
    obsid1 <- min(obsid0+subsetn, nobs)
    update(m, Y~X1+X2+X3+X4+X5, data=data[obsid0:obsid1,])
  }

  # return vector of results: execution time, intercept, continuous parameter estimates,
  # and estimates of first five levels of each FE
  c(coef(m)[c(1, 2, 3, which(substr(names(coef(m)), 1, 2)=="X3")[1:5],
                       which(substr(names(coef(m)), 1, 2)=="X4")[1:5],
                       which(substr(names(coef(m)), 1, 2)=="X5")[1:5])], (proc.time()-t)[1:3])

}

####
#### method: bigglm()
####

feSolution_bigglm <- function(data, subsetn=NULL) {

  # fit linear fixed effects model using bigglm()

  # parameters:
  # data ...... source data with vectors Y, X1, X2, X3, X4, X5 (X1, X2 continuous; X3, X4, X5 FE levels)
  # subsetn ... number of observations to fit using bigglm's chunksize option

  # note that fixed effect parameter estimates are valid only when all fixed effect levels appear in
  # every subset of data

  library(biglm)

  # convert fixed effects to factors
  data <- data.frame(data[,c("Y", "X1", "X2")],
                     "X3"=factor(data[,"X3"]), "X4"=factor(data[,"X4"]), "X5"=factor(data[,"X5"]))

  # use entire data set if subset size not specified
  if(is.null(subsetn))
    subsetn <- nrow(data)

  t <- proc.time()

  # fit model using chunksize option
  m <- bigglm(Y~X1+X2+X3+X4+X5, data=data, chunksize=subsetn)

  # return vector of results: execution time, intercept, continuous parameter estimates,
  # and estimates of first five levels of each FE
  c(coef(m)[c(1, 2, 3, which(substr(names(coef(m)), 1, 2)=="X3")[1:5],
                       which(substr(names(coef(m)), 1, 2)=="X4")[1:5],
                       which(substr(names(coef(m)), 1, 2)=="X5")[1:5])], (proc.time()-t)[1:3])

}


####
#### method:  bigmemory, biglm.big.matrix()
####

feSolution_bigmatrix <- function(data) {

  # fit linear fixed effects model using biglm.big.matrix()

  # parameters:
  # data ...... source data with vectors Y, X1, X2, X3, X4, X5 (X1, X2 continuous; X3, X4, X5 FE levels)

  library(biganalytics)

  # convert fixed effects to factors
  data <- data.frame(data[,c("Y", "X1", "X2")],
                     "X3"=factor(data[,"X3"]), "X4"=factor(data[,"X4"]), "X5"=factor(data[,"X5"]))

  t <- proc.time()

  m <- biglm.big.matrix(Y~X1+X2+X3+X4+X5, fc=c("X3", "X4", "X5"), data=as.big.matrix(data))

  # return vector of results: execution time, intercept, continuous parameter estimates,
  # and estimates of first five levels of each FE
  c(coef(m)[c(1, 2, 3, which(substr(names(coef(m)), 1, 2)=="X3")[1:5],
                       which(substr(names(coef(m)), 1, 2)=="X4")[1:5],
                       which(substr(names(coef(m)), 1, 2)=="X5")[1:5])], (proc.time()-t)[1:3])

}

####
#### method:  SparseM
####

feSolution_sparseM <- function(data, ncore=12) {

  # fit linear fixed effects model using biglm.big.matrix()

  # parameters:
  # data ...... source data with vectors Y, X1, X2, X3, X4, X5 (X1, X2 continuous; X3, X4, X5 FE levels)
  # ncores .... number of parallel cores to use in composing sparse matrix

  library(SparseM)
  library(parallel)

  t <- proc.time()

  # define function to execute parallel operations
  # this enables assigning the global environment as its env, which avoids parLapply's
  # insistence on exporting the entire local environment (it never exports .GlobalEnv,
  # why it exports anything is a puzzle since environment objects cannot be referenced
  # in parallel functions anway) 
  # this is important if executing within a function with a local environment
  # since it prevents export of potentially large objects
  parWhich <- function(cl, ulev) {
    # return a matrix of indicator columns, list of which() results (vectors), one for each level in sequence of 
    # vector elements of the list are expected to be of non-uniform length, hence the requirement of collection
    # into a list, as opposed to a matrix or data frame 
    # it is assumed that feX has already been exported
    parApply(cl, as.matrix(ulev), 1, function(lev) {
                                       z <- rep(0, n)
                                       z[which(feX==lev)] <- 1
                                       return(z)
                                     })
  }
  environment(parWhich) <- .GlobalEnv

  # create a cluster of workers and export n, since it is used by all processes
  cl <- makePSOCKcluster(rep("localhost", ncore))
  n <- nrow(data)
  clusterExport(cl, "n", envir=environment())

  # initialize sparse matrix with constant and continuous vectors
  X <- as.matrix.csr(cbind(rep(1, nrow(data)), data[,"X1"], data[,"X2"]))

  # append, in parallel, indicator columns for each non-reference level of each fixed effect
  for(x in c("X3", "X4", "X5")) {
    # export vector of levels for current FE
    feX <- data[,x]
    clusterExport(cl, "feX", envir=environment())
    # append matrix of indicator columns, one for each level
    X <- cbind(X, as.matrix.csr(parWhich(cl, sort(unique(data[,x]))[-1])))
  }
  stopCluster(cl)

  # fit model
  # tmpmax value from suggestion in slm.fit() documentation
  m <- slm.fit(X, data[,"Y"], tmpmax=100*nrow(data))

  # return vector of results: execution time, intercept, continuous parameter estimates,
  # and estimates of first five levels of each FE
  X3end <- 2+length(unique(data[,"X3"]))
  X4end <- X3end+length(unique(data[,"X4"]))-1
  c(m$coefficients[c(1, 2, 3, 4:8, (X3end+1):(X3end+5), (X4end+1):(X4end+5))], (proc.time()-t)[1:3])

}

####
#### method:  lfe()
####

feSolution_lfe <- function(data) {

  # fit linear fixed effects model using lfe()

  # parameters:
  # data ...... source data with vectors Y, X1, X2, X3, X4, X5 (X1, X2 continuous; X3, X4, X5 FE levels)

  library(lfe)

  # prepend constant vector
  data <- data.frame("b0"=rep(1, nrow(data)), data)

  # fit model
  t <- proc.time()
  #mlfe <- felm(Y ~ X1+X2 | X3+X4+X5 | 0 | X3, data=data, exactDOF='rM') # clustered se on X3
  m <- felm(Y ~ X1+X2 | X3+X4+X5, data=data, exactDOF='rM', keepX=F, keepCX=F)
  # following seems to ignore method='cg' and imposes default Kaczmarz method
  # reference levels are ignored and first level of FE 1 is coerced into a reference level for all FEs
  # also, an intercept term is not estimated
  # since we have set actual effect of all reference levels to 0, b0 can be estimated from the
  # sum of effects X3.0001, X4.00001, and X5.00001
  # note that effects with respect to corresponding reference levels are often critical and must
  # be estimated 
  #b <- getfe(m, se=T, method="cg", references=c("X3.00001", "X4.00001", "X5.00001"), ef=efactory(m))
  b <- getfe(m, se=T, ef=efactory(m))

  proc.time()-t

  # return vector of results: execution time, intercept, continuous parameter estimates,
  # and estimates of first five levels of each FE
  # note the absence of an intercept term
  c(c(b["X3.00001", "effect"]+b["X4.00001", "effect"]+b["X5.00001", "effect"],
               m$coefficients[1:2],
               b[c(which(b[,"fe"]=="X3")[2:6],
                   which(b[,"fe"]=="X4")[2:6],
                   which(b[,"fe"]=="X5")[2:6]), "effect"]), (proc.time()-t)[1:3])

}

####
#### method:  speedlm
####

feSolution_speedlm <- function(data, subsetn=NULL) {

  # fit linear fixed effects model using speedlm()

  # parameters:
  # data ...... source data with vectors Y, X1, X2, X3, X4, X5 (X1, X2 continuous; X3, X4, X5 FE levels)
  # subsetn ... number of observations to fit per update cycle (useful for when data has more
  #             observations than speedlm() can accomodate in a single pass)

  # note that fixed effect parameter estimates are valid only when all fixed effect levels appear in
  # every subset of data

  library(speedglm)

  # convert fixed effects to factors
  data <- data.frame(data[,c("Y", "X1", "X2")],
                     "X3"=factor(data[,"X3"]), "X4"=factor(data[,"X4"]), "X5"=factor(data[,"X5"]))

  # configure observation boundaries for first subset
  nobs <- nrow(data)
  if(is.null(subsetn))
    subsetn <- nobs
  obsid0 <- 1
  obsid1 <- min(obsid0+subsetn, nobs)

  t <- proc.time()

  # fit first subset
  # request y estimates (others do it)
  m <- speedlm(Y~X1+X2+X3+X4+X5, data=data[obsid0:obsid1,], sparse=T, fitted=T)

  # compute parameter variances (others do it)
  # verified:  RSS=sum((data[,"Y"]-m$fitted.values)**2)/m$df.residual
  v <- diag(solve(m$XTX))*m$RSS

  # update model with remaining subsets
  while(obsid1<nobs) {
    # update obs boundaries
    obsid0 <- obsid1+1
    obsid1 <- min(obsid0+subsetn, nobs)
    update(m, data=data[obsid0:obsid1,])
  }

  # return vector of results: execution time, intercept, continuous parameter estimates,
  # and estimates of first five levels of each FE
  c(coef(m)[c(1, 2, 3, which(substr(names(m$coefficients), 1, 2)=="X3")[1:5],
                       which(substr(names(m$coefficients), 1, 2)=="X4")[1:5],
                       which(substr(names(m$coefficients), 1, 2)=="X5")[1:5])], (proc.time()-t)[1:3])

}

####
#### method:  feXTX
####

feSolution_feXTX <- function(data, ncore=12) {

  # fit linear fixed effects model using sparse XTX indicator matrix construction

  # parameters:
  # data ...... source data with vectors Y, X1, X2, X3, X4, X5 (X1, X2 continuous; X3, X4, X5 FE levels)
  # ncores .... number of parallel cores to use in composing sparse matrix

  # load Cholesky and feXTX functions

  sys.source("\\\\SSRI-NAS-FE01.oit.duke.edu\\SSRI\\OPM\\Users\\Current\\tjb48\\Analysis\\FixedEffectsModel\\LargeFixedEffectsModel\\FixedEffectsMatrixSolution.r", env=environment())
  sys.source("\\\\SSRI-NAS-FE01.oit.duke.edu\\SSRI\\OPM\\Users\\Current\\tjb48\\Analysis\\FixedEffectsModel\\LargeFixedEffectsModel\\CholeskyDecomposition\\choleskyDecompLoad.r", env=environment())
  sys.source("\\\\SSRI-NAS-FE01.oit.duke.edu\\SSRI\\OPM\\Users\\Current\\tjb48\\Analysis\\FixedEffectsModel\\LargeFixedEffectsModel\\CholeskyDecomposition\\cholInvDiagLoad.r", env=environment())

  t <- proc.time()

  # fit model
  # note the specification of Cholesky decomposition parallelized methods beta and variance estimation

  m <- feXTX(data=data,
             Y="Y",
             contX=c("X1", "X2"),
             fixedX=c("X3", "X4", "X5"),
             refLevel=c(min(data[,"X3"]), min(data[,"X4"]), min(data[,"X5"])),
             interactionX=NULL,
             estBetaVar="stdOLS",
             robustVarID=NULL,
             nCoreXTX=ncore,
             nCoreVar=0,
             solMethod="chol-parallel")

  # return vector of results: execution time, intercept, continuous parameter estimates,
  # and estimates of first five levels of each FE
  c(m$beta[c(1, 2, 3, which(substr(names(m$beta), 1, 2)=="X3")[1:5],
                      which(substr(names(m$beta), 1, 2)=="X4")[1:5],
                      which(substr(names(m$beta), 1, 2)=="X5")[1:5])], (proc.time()-t)[1:3])

}

########################################################################################
#### execute tests
########################################################################################

# create repository for results
# note the specification of Cholesky decomposition parallelized functions for feXTX results
init <- F
if(init)
  write.table(paste("method, n, lv3, lv4, lv5, cores, nsubset, b0, X1, X2, ",
                    "X3-000002, X3-000003, X3-000004, X3-000005, X3-000006, ",
                    "X4-000002, X4-000003, X4-000004, X4-000005, X4-000006, ",
                    "X5-000002, X5-000003, X5-000004, X5-000005, X5-000006, ",
                    "timeUser, timeSys, timeElapsed", sep=""),
              "FETestResults-feXTXCholeskyParallelized.csv.csv", quote=F, sep="", row.names=F, col.names=F)

# configure test parameters
dpar <- rbind(data.frame("n"=10000,    "lv3"=10,   "lv4"=15,   "lv5"=20,      "ncore"=2),
              data.frame("n"=25000,    "lv3"=10,   "lv4"=20,   "lv5"=40,      "ncore"=2),
              data.frame("n"=50000,    "lv3"=15,   "lv4"=30,   "lv5"=50,      "ncore"=2),
              data.frame("n"=100000,   "lv3"=15,   "lv4"=40,   "lv5"=60,      "ncore"=2),
              data.frame("n"=150000,   "lv3"=25,   "lv4"=40,   "lv5"=60,      "ncore"=2),
              data.frame("n"=250000,   "lv3"=25,   "lv4"=50,   "lv5"=75,      "ncore"=2),
              data.frame("n"=500000,   "lv3"=50,   "lv4"=75,   "lv5"=100,     "ncore"=4),
              data.frame("n"=1000000,  "lv3"=75,   "lv4"=150,  "lv5"=250,     "ncore"=8),
              data.frame("n"=1500000,  "lv3"=100,  "lv4"=250,  "lv5"=500,     "ncore"=10),
              data.frame("n"=2000000,  "lv3"=100,  "lv4"=500,  "lv5"=1000,    "ncore"=12),
              data.frame("n"=5000000,  "lv3"=200,  "lv4"=1000, "lv5"=5000,    "ncore"=20),
              data.frame("n"=10000000, "lv3"=1000, "lv4"=5000, "lv5"=10000,   "ncore"=22),
              data.frame("n"=25000000, "lv3"=1000, "lv4"=5000, "lv5"=25000,   "ncore"=22))

# execute tests, limiting slower methods to an upper bound on number of FE levels
for(i in 1:nrow(dpar)) {
  n <- dpar[i,"n"]
  lv3 <- dpar[i,"lv3"]
  lv4 <- dpar[i,"lv4"]
  lv5 <- dpar[i,"lv5"]
  ncore <- dpar[i,"ncore"]
  for(j in 1:5) {
    feDat <- feTestData(n, lv3, lv4, lv5)
    if(n<=1500000) {
      write.table(data.frame("lm", n, lv3, lv4, lv5, 0, 0, t(feSolution_lm(feDat))),
                  "FETestResults1.csv", quote=F, sep=", ", row.names=F, col.names=F, append=T)
      write.table(data.frame("biglm", n, lv3, lv4, lv5, 0, 0, t(feSolution_biglm(feDat))),
                  "FETestResults1.csv", quote=F, sep=", ", row.names=F, col.names=F, append=T)
      write.table(data.frame("bigglm", n, lv3, lv4, lv5, 0, 0, t(feSolution_bigglm(feDat))),
                  "FETestResults1.csv", quote=F, sep=", ", row.names=F, col.names=F, append=T)
      write.table(data.frame("bigmatrix", n, lv3, lv4, lv5, 0, 0, t(feSolution_bigmatrix(feDat))),
                  "FETestResults1.csv", quote=F, sep=", ", row.names=F, col.names=F, append=T)
      write.table(data.frame("sparseM", n, lv3, lv4, lv5, ncore, 0, t(feSolution_sparseM(feDat, 12))),
                  "FETestResults1.csv", quote=F, sep=", ", row.names=F, col.names=F, append=T)
      write.table(data.frame("speedlm", n, lv3, lv4, lv5, 0, 0, t(feSolution_speedlm(feDat))),
                  "FETestResults1.csv", quote=F, sep=", ", row.names=F, col.names=F, append=T)
    }
    if(F)
      write.table(data.frame("lfe", n, lv3, lv4, lv5, 0, 0, t(feSolution_lfe(feDat))),
                  "FETestResults1.csv", quote=F, sep=", ", row.names=F, col.names=F, append=T)
    if(T)
      write.table(data.frame("feXTX", n, lv3, lv4, lv5, ncore, 0, t(feSolution_feXTX(feDat, ncore))),
                  "FETestResults1.csv", quote=F, sep=", ", row.names=F, col.names=F, append=T)
    gc()
  }
}


#################################################################################################
#### plot execution times by observation count (and increasing fixed effect level count)
#################################################################################################

# retrieve execution time data
# note the use of Cholesky decomposition parallelized functions for feXTX results
rdat <- read.table("FETestResults-feXTXCholeskyParallelized.csv", header=T, sep=",", strip.white=T)

# verify existence of data for each method
table(rdat[,"method"], rdat[,"n"])

# convert execution times to minutes
rdat["timeElapsed"] <- rdat[,"timeElapsed"]/60

# aggregate mean execution times
gdat <- aggregate(rdat[,"timeElapsed"], by=list(rdat[,"method"], rdat[,"n"]), mean)
colnames(gdat) <- c("method", "n", "t")

# order methods for appearance in legend
gdat[,"method"] <- factor(gdat[,"method"], levels=c("lm", "biglm", "bigglm", "bigmatrix", "sparseM",
                                                    "speedlm", "lfe", "feXTX"))

# plot
# two plots:  pver=1 for one for less efficient methods, pver=2 one for lfe and feXTX
pver <- 2
if(pver==1) {
  k <- which(gdat[,"n"]<=1500000)
  kmaxn <- which(gdat[,"n"]==1500000)
  xbrk <- seq(0, 1500000, 500000)
  ybrkstep <- 10
  symoffset <- 25000
} else {
  k <- which(gdat[,"method"] %in% c("lfe", "feXTX"))
  kmaxn <- which(gdat[,"n"]==max(gdat[,"n"]))
  xbrk <- seq(0, 25000000, 5000000)
  ybrkstep <- 60
  symoffset <- 500000
}
png(paste("FETestResults", pver, ".png", sep=""), res=300, height=2400, width=2400)
ggplot() +
  geom_line(data=gdat[k,], aes(x=n, y=t, linetype=method), size=0.25) +
  scale_linetype_manual(guide=F, name="method",
                        values=c("lm"="solid", "biglm"="solid", "bigglm"="solid", "bigmatrix"="solid",
                                 "sparseM"="solid", "speedlm"="solid", "lfe"="solid", "feXTX"="solid")) +
  geom_point(data=gdat[kmaxn,], aes(x=n+symoffset, y=t+0.25, shape=method), size=4) +
  scale_shape_manual(name="method",
                     values=c("lm"="1", "biglm"="2", "bigglm"="3", "bigmatrix"="4",
                              "sparseM"="5", "speedlm"="6", "lfe"="7", "feXTX"="8")) +
  scale_x_continuous(breaks=xbrk, expand=c(0.1, 0.2), labels=thousandsFormat) +
  scale_y_continuous(breaks=seq(0, 1000, ybrkstep)) +
  theme(panel.background=element_blank(),
        panel.grid.major.x=element_blank(),
        panel.grid.major.y=element_blank(),
        panel.grid.minor=element_blank(),
        panel.border=element_rect(fill=NA),
        plot.title=element_text(size=12),
        axis.title.x=element_text(size=12),
        axis.title.y=element_text(size=12),
        axis.text.x=element_text(size=10),
        axis.text.y=element_text(size=10),
        legend.position="bottom",
        legend.background=element_rect(color = "gray"),
        legend.key=element_rect(fill = "white"),
        legend.box="horizontal",
        legend.title=element_text(size=11, face="plain"),
        legend.text=element_text(size=11)) +
  labs(x="\nnumber of observations", y="execution time (minutes)\n")
dev.off()
